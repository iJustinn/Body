import Foundation
import HealthKit

/// The approved foreground lifecycle owns this reconciler in ordinary builds.
/// Production refresh/compute remains query-derived even when this owner runs.
actor WorkoutJournalReconciler {
    enum Result: Equatable { case caughtUp, morePending, busy, failed, timedOut, superseded, capacityExceeded }
    private enum Page: Sendable {
        case changes([WorkoutJournalEntry], [UUID], Data)
        case failed, invalidAnchor, cancelled
    }

    private let engine: HealthKitFetchEngine
    private let file: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private var journal: WorkoutChangeJournal
    private var needsSave: Bool
    private var scanning = false
    private var admissionEpoch: UInt64 = 0
    private static let batchLimit = 500
    private static let entryLimit = 10_000

    init(engine: HealthKitFetchEngine, file: URL, scope: WorkoutJournalScope? = nil, date: Date = Date(),
         write: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.engine = engine
        self.file = file
        self.write = write
        let loadedJournal = WorkoutChangeJournalStore.load(file: file)
        // The installation identity and fixed predicate live in the same excluded-
        // from-backup envelope. A missing/unusable envelope starts a new identity.
        let scope = scope ?? loadedJournal?.scope ?? WorkoutJournalScope(
            installationID: UUID(), lowerBound: date.addingTimeInterval(-408 * 86_400), predicateVersion: 1)
        if var loaded = loadedJournal {
            needsSave = loaded.scope != scope
            if needsSave { loaded.restart(scope: scope) }
            journal = loaded
        } else {
            journal = WorkoutChangeJournal(scope: scope)
            needsSave = true
        }
    }

    func snapshot() -> WorkoutChangeJournal { journal }

    /// Scope/anchor repair preserves canonical history but immediately fences work.
    @discardableResult
    func restart(scope: WorkoutJournalScope) -> Bool {
        admissionEpoch &+= 1
        journal.restart(scope: scope)
        needsSave = true
        return persistPendingRestart()
    }

    /// Deletes only this rebuildable journal, never dashboard/month/detail history.
    func clear() throws {
        admissionEpoch &+= 1
        journal = WorkoutChangeJournal(scope: journal.scope)
        needsSave = true
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    /// Call only after *all* dependent repairs have durably committed under this
    /// token and their own source/permission/calendar/compute admission checks.
    func acknowledgeDurableRepair(generation: UUID, revision: UInt64,
                                  admission: HealthDashboardPublicationToken? = nil) -> Bool {
        guard !needsSave, journal.bootstrapComplete,
              admission?.isValid != false,
              journal.generation == generation, journal.revision == revision else { return false }
        var next = journal
        next.dirtyIntervals = [:]
        next.requiresFullRepair = false
        next.repairProgress = nil
        next.revision &+= 1
        return commit(next)
    }

    /// Progress never retires dirty work; it only avoids replaying durable month
    /// repairs. A delta, restart, or changed dependency context discards it.
    func checkpointRepair(_ progress: WorkoutJournalRepairProgress, generation: UUID, revision: UInt64,
                          admission: HealthDashboardPublicationToken? = nil) -> Bool {
        guard !needsSave, journal.bootstrapComplete, admission?.isValid != false,
              journal.generation == generation, journal.revision == revision else { return false }
        var next = journal
        next.repairProgress = progress
        next.revision &+= 1
        return commit(next)
    }

    private func commit(_ next: WorkoutChangeJournal) -> Bool {
        guard WorkoutChangeJournalStore.save(next, file: file, write: write) != .failed else { return false }
        journal = next
        needsSave = false
        return true
    }

    private func persistPendingRestart() -> Bool { !needsSave || commit(journal) }

    func scan(maxPages: Int = 4, deadline: Duration = .seconds(120)) async -> Result {
        guard !scanning else { return .busy }
        guard (1...16).contains(maxPages), deadline > .zero,
              journal.scope.predicateVersion == 1,
              journal.scope.lowerBound.timeIntervalSince1970.isFinite else { return .failed }
        scanning = true
        defer { scanning = false }
        guard !Task.isCancelled, persistPendingRestart() else { return .failed }
        let epoch = admissionEpoch
        let contextRevision = await engine.queryContextRevision
        let clock = ContinuousClock(), started = ContinuousClock.now
        for _ in 0..<maxPages {
            let remaining = min(deadline, .seconds(120)) - started.duration(to: clock.now)
            guard remaining > .zero else { return .timedOut }
            guard !Task.isCancelled, epoch == admissionEpoch else { return .superseded }
            let revision = journal.revision
            let request = BodyWorkoutChangesRequest(lowerBound: journal.scope.lowerBound,
                anchor: journal.anchor, limit: Self.batchLimit)
            let engine = engine
            let fetch = Task { () -> Page in
                let result = await withBackgroundQueryPool { await engine.fetchWorkoutChanges(request) }
                switch result {
                case .success(let batch):
                    let entries = batch.workouts.map {
                        WorkoutJournalEntry(id: $0.uuid, start: $0.startDate, end: $0.endDate,
                            activityType: $0.workoutActivityType.rawValue, duration: $0.duration,
                            sourceBundleIdentifier: $0.sourceRevision.source.bundleIdentifier)
                    }
                    return .changes(entries, batch.deletedIDs, batch.anchor)
                case .failure(let error):
                    if let error = error as? BodyWorkoutAnchorError, case .invalidArchive = error { return .invalidAnchor }
                    if let error = error as? HKError, error.code == .errorInvalidArgument, request.anchor != nil {
                        return .invalidAnchor
                    }
                    return .failed
                case .cancelled: return .cancelled
                }
            }
            let outcome = await withTaskCancellationHandler {
                await OneShotDeadlineRace.run(deadline: remaining) { await fetch.value }
            } onCancel: { fetch.cancel() }
            fetch.cancel()
            // Actor hop first; every mutable admission check is after it.
            guard await engine.queryContextRevision == contextRevision,
                  !Task.isCancelled, epoch == admissionEpoch, journal.revision == revision else { return .superseded }
            guard case .finished(let page) = outcome else { return .timedOut }
            switch page {
            case .invalidAnchor:
                return restart(scope: journal.scope) ? .morePending : .failed
            case .failed, .cancelled: return .failed
            case .changes(let entries, let deleted, let anchor):
                guard entries.count <= Self.batchLimit, deleted.count <= Self.batchLimit,
                      !anchor.isEmpty, anchor.count <= 1_048_576,
                      entries.allSatisfy({ $0.start >= request.lowerBound && $0.end >= $0.start
                          && $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite
                          && $0.duration.isFinite && $0.duration >= 0 }) else { return .failed }
                let empty = entries.isEmpty && deleted.isEmpty
                if empty && journal.bootstrapComplete && journal.anchor == anchor { return .caughtUp }
                var next = journal
                next.apply(additions: entries, deletedIDs: deleted, nextAnchor: anchor)
                guard next.entries.count <= Self.entryLimit, (next.staging?.count ?? 0) <= Self.entryLimit else {
                    return .capacityExceeded
                }
                if next.dirtyIntervals.count > Self.entryLimit {
                    next.dirtyIntervals = [:]
                    next.requiresFullRepair = true
                }
                guard commit(next) else { return .failed }
                if empty { return .caughtUp }
            }
        }
        return .morePending
    }
}
