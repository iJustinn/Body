import Foundation

/// Rebuildable canonical membership, not enriched workout details or score authority.
struct WorkoutJournalEntry: Codable, Equatable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let activityType: UInt
    let duration: TimeInterval
    let sourceBundleIdentifier: String
}

struct WorkoutJournalScope: Codable, Equatable, Sendable {
    let installationID: UUID
    /// Fixed for this generation. Never recalculate a moving predicate per page.
    let lowerBound: Date
    let predicateVersion: Int
}

struct WorkoutJournalRepairProgress: Codable, Equatable, Sendable {
    var context: String
    var completedMonths: Set<String> = []
    var baselineInvalidated = false
    var detailsInvalidated = false
    // Optional for schema-1 envelopes written before retry scheduling existed.
    var monthAttempts: [String: MonthAttempt]?

    struct MonthAttempt: Codable, Equatable, Sendable {
        var count: Int
        var startedAt: Date

        var delay: TimeInterval {
            [300.0, 1_800, 7_200, 21_600][min(max(count, 1), 4) - 1]
        }
    }

    func mayAttemptMonth(_ identity: String, at date: Date) -> Bool {
        guard !completedMonths.contains(identity) else { return false }
        guard let attempt = monthAttempts?[identity] else { return true }
        // Clock rollback must not strand a repair behind a future wall-clock date.
        return date < attempt.startedAt || date.timeIntervalSince(attempt.startedAt) >= attempt.delay
    }

    mutating func beginMonthAttempt(_ identity: String, at date: Date) {
        var attempts = monthAttempts ?? [:]
        let previous = min(max(attempts[identity]?.count ?? 0, 0), 4)
        attempts[identity] = MonthAttempt(count: min(previous + 1, 4), startedAt: date)
        monthAttempts = attempts
    }

    mutating func completeMonth(_ identity: String) {
        completedMonths.insert(identity)
        monthAttempts?.removeValue(forKey: identity)
        if monthAttempts?.isEmpty == true { monthAttempts = nil }
    }
}

struct WorkoutChangeJournal: Codable, Equatable, Sendable {
    static let currentSchema = 1
    var schema = currentSchema
    var scope: WorkoutJournalScope
    var generation = UUID()
    var revision: UInt64 = 0
    var anchor: Data?
    var entries: [String: WorkoutJournalEntry] = [:]
    /// Non-nil until an empty page proves this bootstrap has drained.
    var staging: [String: WorkoutJournalEntry]? = [:]
    var dirtyIntervals: [String: DateInterval] = [:]
    var requiresFullRepair = true
    var repairProgress: WorkoutJournalRepairProgress?

    var bootstrapComplete: Bool { staging == nil }

    mutating func restart(scope: WorkoutJournalScope) {
        self.scope = scope
        generation = UUID()
        revision = 0
        anchor = nil
        staging = [:]
        requiresFullRepair = true
        repairProgress = nil
        // Keep the previous canonical generation and obligations until repair.
    }

    private mutating func dirty(_ entry: WorkoutJournalEntry) {
        let key = entry.id.uuidString
        let old = dirtyIntervals[key]
        dirtyIntervals[key] = DateInterval(start: min(old?.start ?? entry.start, entry.start),
            end: max(old?.end ?? entry.end, entry.end))
    }

    mutating func apply(additions: [WorkoutJournalEntry], deletedIDs: [UUID], nextAnchor: Data) {
        if staging != nil || !additions.isEmpty || !deletedIDs.isEmpty { repairProgress = nil }
        var target = staging ?? entries
        for entry in additions {
            if let old = target[entry.id.uuidString] { dirty(old) }
            if let old = entries[entry.id.uuidString] { dirty(old) }
            dirty(entry)
            target[entry.id.uuidString] = entry
        }
        for id in deletedIDs {
            let key = id.uuidString
            let old = target.removeValue(forKey: key) ?? entries[key]
            if let old { dirty(old) } else { requiresFullRepair = true }
        }
        if staging != nil {
            staging = target
            if additions.isEmpty && deletedIDs.isEmpty {
                for (id, old) in entries where target[id] != old { dirty(old) }
                entries = target
                staging = nil
            }
        } else {
            entries = target
        }
        anchor = nextAnchor
        revision &+= 1
    }
}
