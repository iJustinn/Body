import Foundation

/// Presentation only. Explicit monotonic time makes dwell and settlement testable
/// without sleeping, and never holds the store's execution slot open.
struct BodySyncPresentation: Hashable {
    enum Phase: Hashable { case hidden, syncing, updated, partial }
    enum Calculation: String, CaseIterable, Sendable { case readiness, stress, trainingLoad, bodyRadar }
    enum Stage: Hashable, Sendable {
        case authorizing, fetching, syncing, updatingHealth, updatingRings
        case updating(HealthMetricKind)
        case computing(Calculation)
        case writingEffort, finishing
    }

    private(set) var sessionID: UUID?
    private(set) var passID: UUID?
    private(set) var phase: Phase = .hidden
    private(set) var pending: Set<UUID> = []
    private(set) var stage: Stage = .fetching
    private(set) var displayedStage: Stage = .fetching
    private(set) var didPublish = false
    private(set) var hadFailure = false
    private(set) var completedAt: Date?
    private var stageChangedAt: TimeInterval = 0
    private var settleAt: TimeInterval?
    private var dismissAt: TimeInterval?

    static let dwell: TimeInterval = 0.5
    static let settleDelay: TimeInterval = 0.6
    static let confirmationDuration: TimeInterval = 1.8

    var nextDeadline: TimeInterval? {
        if let dismissAt { return dismissAt }
        let dwellAt = phase == .syncing && stage != displayedStage ? stageChangedAt + Self.dwell : nil
        return [dwellAt, settleAt].compactMap { $0 }.min()
    }

    mutating func begin(now: TimeInterval) {
        advance(now: now)
        if phase != .syncing {
            sessionID = UUID()
            phase = .syncing
            didPublish = false
            hadFailure = false
            completedAt = nil
            stage = .fetching
            displayedStage = .fetching
            stageChangedAt = now
        }
        passID = UUID()
        settleAt = nil
        dismissAt = nil
    }

    mutating func enqueue(_ token: UUID, replacing previous: UUID? = nil, now: TimeInterval) {
        pending.insert(token)
        if let previous { pending.remove(previous) }
        reconcile(now: now)
    }

    mutating func release(_ token: UUID, now: TimeInterval) {
        pending.remove(token)
        reconcile(now: now)
    }

    mutating func report(_ next: Stage, owner: UUID, now: TimeInterval) {
        guard phase == .syncing, passID == owner else { return }
        stage = next == .fetching && stage != .fetching && stage != .authorizing ? .updatingHealth : next
        advance(now: now)
    }

    mutating func record(published: Bool = false, failed: Bool = false, owner: UUID) {
        guard phase == .syncing, passID == owner else { return }
        didPublish = didPublish || published
        hadFailure = hadFailure || failed
    }

    mutating func finish(now: TimeInterval) {
        passID = nil
        reconcile(now: now)
    }

    mutating func invalidate() {
        self = Self()
    }

    private mutating func reconcile(now: TimeInterval) {
        guard phase == .syncing else { return }
        if passID == nil, !pending.isEmpty {
            stage = .syncing
        }
        if passID == nil, pending.isEmpty {
            if settleAt == nil { settleAt = now + Self.settleDelay }
        } else {
            settleAt = nil
        }
        advance(now: now)
    }

    mutating func advance(now: TimeInterval, date: Date = .now) {
        if phase == .syncing {
            if stage != displayedStage, now >= stageChangedAt + Self.dwell {
                displayedStage = stage
                stageChangedAt = now
            }
            if let settleAt, now >= settleAt, passID == nil, pending.isEmpty {
                phase = didPublish ? (hadFailure ? .partial : .updated) : .hidden
                completedAt = phase == .hidden ? nil : date
                self.settleAt = nil
                dismissAt = phase == .hidden ? nil : now + Self.confirmationDuration
            }
        } else if let dismissAt, now >= dismissAt {
            phase = .hidden
            self.dismissAt = nil
        }
    }
}
