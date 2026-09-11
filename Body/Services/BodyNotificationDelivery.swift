import Foundation
import HealthKit
@preconcurrency import UserNotifications

/// Separate from the rebuildable journal: staged additions survive a process exit
/// between candidate capture and anchor commit. Submission is serialized here.
actor BodyNotificationDelivery {
    static let shared = BodyNotificationDelivery()
    struct Delivery: Sendable {
        var authorization: @Sendable () async -> UNAuthorizationStatus
        var add: @Sendable (UNNotificationRequest) async throws -> Void
    }
    struct Candidate: Codable {
        var entry: WorkoutJournalEntry
        var generation: UUID
        var revision: UInt64
        var foreground: Bool
    }
    struct WorkoutState: Codable {
        var pending: [String: Candidate] = [:]
        var seen: [WorkoutJournalEntry] = []
    }
    private var state: WorkoutState
    private let file: URL
    private let defaults: UserDefaults
    private let delivery: Delivery
    private let foreground: @Sendable () async -> Bool
    private var delivering = false

    init(file: URL? = nil, defaults: UserDefaults = .standard, delivery: Delivery? = nil,
         foreground: @escaping @Sendable () async -> Bool = { await MainActor.run { BodyAppRuntime.isForegroundActive } }) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notifications/workouts.json")
        self.defaults = defaults
        self.delivery = delivery ?? Delivery(
            authorization: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
            add: { try await UNUserNotificationCenter.current().add($0) })
        self.foreground = foreground
        state = (try? Data(contentsOf: self.file)).flatMap { try? JSONDecoder().decode(WorkoutState.self, from: $0) } ?? WorkoutState()
    }

    private func save(_ next: WorkoutState) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var resource = file
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resource.setResourceValues(values)
            state = next
            return true
        } catch { return false }
    }

    func stage(_ entries: [WorkoutJournalEntry], generation: UUID, revision: UInt64, now: Date = Date()) async -> Bool {
        let isForeground = await foreground()
        var next = state
        next.seen.removeAll { $0.end < now.addingTimeInterval(-30 * 3600) }
        next.pending = next.pending.filter { $0.value.entry.end >= now.addingTimeInterval(-6 * 3600) }
        if BodyNotificationPreferences.enabled(BodyNotificationPreferences.workoutKey, defaults: defaults) {
            let since = BodyNotificationPreferences.since(BodyNotificationPreferences.workoutKey, defaults: defaults, now: now)
            for entry in entries where entry.end >= since && entry.end <= now && entry.end >= now.addingTimeInterval(-6 * 3600) {
                if next.pending[entry.id.uuidString] == nil {
                    next.pending[entry.id.uuidString] = Candidate(entry: entry, generation: generation,
                        revision: revision, foreground: isForeground)
                }
            }
        }
        return save(next)
    }

    nonisolated static func duplicates(_ first: WorkoutJournalEntry, _ second: WorkoutJournalEntry) -> Bool {
        if first.id == second.id { return true }
        let a = first.end.timeIntervalSince(first.start), b = second.end.timeIntervalSince(second.start)
        guard a > 0, b > 0 else { return false }
        let overlap = max(0, min(first.end, second.end).timeIntervalSince(max(first.start, second.start)))
        return overlap / a >= 0.8 && overlap / b >= 0.8
    }

    func deliverWorkouts(journal: WorkoutChangeJournal, lease: BodyBackgroundLease?,
                         isCurrent: @escaping @Sendable () async -> Bool = { true }, now: Date = Date()) async {
        guard !delivering else { return }
        delivering = true
        defer { delivering = false }
        let revision = defaults.string(forKey: BodyNotificationPreferences.revisionKey)
        for candidate in state.pending.values.sorted(by: { $0.entry.end < $1.entry.end }) {
            let entry = candidate.entry
            let key = entry.id.uuidString
            let since = BodyNotificationPreferences.since(BodyNotificationPreferences.workoutKey, defaults: defaults, now: now)
            guard journal.bootstrapComplete, candidate.generation == journal.generation,
                  journal.revision >= candidate.revision, journal.entries[key] == entry,
                  entry.end >= since, entry.end >= now.addingTimeInterval(-6 * 3600), entry.end <= now else {
                // A not-yet-committed page may still be retried. A different
                // generation or a committed deletion, however, cannot deliver.
                if candidate.generation != journal.generation || journal.revision >= candidate.revision || entry.end < since {
                    var next = state; next.pending.removeValue(forKey: key); _ = save(next)
                }
                continue
            }
            let inForeground = await foreground()
            if candidate.foreground || inForeground || state.seen.contains(where: { Self.duplicates($0, entry) }) {
                var next = state; next.pending.removeValue(forKey: key); next.seen.append(entry)
                guard save(next) else { return }
                continue
            }
            guard lease?.isValid == true,
                  await admitted(key: BodyNotificationPreferences.workoutKey, revision: revision),
                  await isCurrent(), lease?.isValid == true, !Task.isCancelled,
                  BodyNotificationPreferences.enabled(BodyNotificationPreferences.workoutKey, defaults: defaults),
                  defaults.string(forKey: BodyNotificationPreferences.revisionKey) == revision else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notifications.workout.title", defaultValue: "Workout synced")
            let type = HealthKitWorkoutStore.workoutType(for: HKWorkoutActivityType(rawValue: entry.activityType) ?? .other).displayName
            let duration = Self.duration(entry.duration)
            content.body = String(localized: "notifications.workout.body", defaultValue: "\(type) · \(duration). Finished \(entry.end.formatted(date: .omitted, time: .shortened)).")
            content.sound = .default
            content.userInfo = ["workoutID": key, "workoutStart": entry.start.timeIntervalSince1970]
            do {
                try await delivery.add(UNNotificationRequest(identifier: "workout.\(key)", content: content, trigger: nil))
                var next = state; next.pending.removeValue(forKey: key); next.seen.append(entry)
                guard save(next) else { return }
            } catch { return }
        }
    }

    private struct SleepReceipt: Codable {
        var day: String
        var start: Date
        var end: Date
    }

    func deliverSleep(_ sleep: SleepSummary, lease: BodyBackgroundLease?,
                      isCurrent: @escaping @Sendable () async -> Bool,
                      now: Date = Date(), calendar: Calendar = .bodyGregorian) async {
        guard !delivering, !Task.isCancelled,
              BodyNotificationPreferences.enabled(BodyNotificationPreferences.sleepKey, defaults: defaults),
              sleep.matchesDay(now, calendar: calendar) else { return }
        let main = sleep.stageSnapshot.mainSession
        guard let start = main.sleepStartDate, let end = main.sleepEndDate,
              start < end, end <= now, main.mergedAsleepDuration > 0,
              end >= BodyNotificationPreferences.since(BodyNotificationPreferences.sleepKey, defaults: defaults, now: now) else { return }
        delivering = true
        defer { delivering = false }
        let key = "notifications.sleep.receipts"
        let revision = defaults.string(forKey: BodyNotificationPreferences.revisionKey)
        let parts = calendar.dateComponents([.year, .month, .day], from: sleep.stageSnapshot.date ?? end)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var receipts = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([SleepReceipt].self, from: $0) } ?? []
        receipts.removeAll { $0.end < now.addingTimeInterval(-7 * 86400) }
        guard !receipts.contains(where: { $0.day == day || ($0.start < end && $0.end > start) }) else { return }
        let active = await foreground()
        guard await isCurrent(), !Task.isCancelled,
              lease == nil ? active : (!active && lease?.isValid == true) else { return }
        if !active {
            guard await admitted(key: BodyNotificationPreferences.sleepKey, revision: revision),
                  await isCurrent(), lease?.isValid == true, !Task.isCancelled,
                  BodyNotificationPreferences.enabled(BodyNotificationPreferences.sleepKey, defaults: defaults),
                  defaults.string(forKey: BodyNotificationPreferences.revisionKey) == revision else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notifications.sleep.title", defaultValue: "Sleep data is ready")
            let duration = Self.duration(main.mergedAsleepDuration)
            content.body = String(localized: "notifications.sleep.body", defaultValue: "Your sleep data has synced: \(duration) asleep. Tap to view Sleep.")
            content.sound = .default
            content.userInfo = ["metric": "sleep"]
            do {
                try await delivery.add(UNNotificationRequest(identifier: "sleep.\(day)", content: content, trigger: nil))
            } catch { return }
        }
        guard defaults.string(forKey: BodyNotificationPreferences.revisionKey) == revision else { return }
        receipts.append(.init(day: day, start: start, end: end))
        if let data = try? JSONEncoder().encode(receipts) { defaults.set(data, forKey: key) }
    }

    private func admitted(key: String, revision: String?) async -> Bool {
        let authorization = await delivery.authorization()
        let active = await foreground()
        return !active && !Task.isCancelled && (authorization == .authorized || authorization == .provisional)
            && BodyNotificationPreferences.enabled(key, defaults: defaults)
            && defaults.string(forKey: BodyNotificationPreferences.revisionKey) == revision
    }

    nonisolated static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, seconds)) ?? "0"
    }

    func evaluateStress(input: StressDayInput, baselines: StressBaselines, context: String,
                        lease: BodyBackgroundLease?, isCurrent: @escaping @Sendable () async -> Bool,
                        now: Date = Date(), calendar: Calendar = .bodyGregorian) async {
        guard !delivering, BodyNotificationPreferences.enabled(BodyNotificationPreferences.stressKey, defaults: defaults) else { return }
        delivering = true
        defer { delivering = false }
        let revision = defaults.string(forKey: BodyNotificationPreferences.revisionKey)
        let since = BodyNotificationPreferences.since(BodyNotificationPreferences.stressKey, defaults: defaults, now: now)
        let storageKey = "notifications.stress.state"
        let old = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(BodyStressNotificationState.self, from: $0) }
        let signature = context + "|" + calendar.timeZone.identifier + "|" + String(since.timeIntervalSince1970)
        let prior: BodyStressNotificationState
        if let old, old.context == signature {
            prior = old
        } else {
            prior = BodyStressNotificationState(context: signature, through: old == nil ? since : now, high: false)
        }
        guard baselines.quietHeartRate != nil else { return }
        let result = BodyStressNotificationState.evaluate(input: input, baselines: baselines, prior: prior,
            since: since, now: now, calendar: calendar)
        guard await isCurrent(), !Task.isCancelled else { return }
        let active = await foreground()
        guard !Task.isCancelled, lease == nil ? active : (!active && lease?.isValid == true) else { return }
        if let event = result.event, !active {
            guard lease?.isValid == true, await admitted(key: BodyNotificationPreferences.stressKey, revision: revision),
                  await isCurrent(), lease?.isValid == true, !Task.isCancelled,
                  BodyNotificationPreferences.enabled(BodyNotificationPreferences.stressKey, defaults: defaults),
                  defaults.string(forKey: BodyNotificationPreferences.revisionKey) == revision else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notifications.stress.title", defaultValue: "High stress detected earlier")
            let score = Int((event.score ?? 0).rounded())
            content.body = String(localized: "notifications.stress.body", defaultValue: "Your stress score reached \(score) at \(event.interval.end.formatted(date: .omitted, time: .shortened)).")
            content.sound = .default
            do {
                try await delivery.add(UNNotificationRequest(identifier: "stress.\(event.interval.start.timeIntervalSince1970)", content: content, trigger: nil))
            } catch { return }
        } else if !active {
            guard lease?.isValid == true else { return }
        }
        // A settings change during submission cannot overwrite the new interval.
        guard defaults.string(forKey: BodyNotificationPreferences.revisionKey) == revision,
              let data = try? JSONEncoder().encode(result.state) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct BodyStressNotificationState: Codable, Equatable {
    var context: String
    var through: Date
    var high: Bool

    static func hasCoverage(_ interval: DateInterval, samples: [HealthTrendDataPoint]) -> Bool {
        let points = samples.filter { $0.value.isFinite && $0.date >= interval.start && $0.date < interval.end }.sorted { $0.date < $1.date }
        guard interval.duration == 900, points.count >= 3 else { return false }
        let bins = Set(points.map { Int($0.date.timeIntervalSince(interval.start) / 300) })
        return bins == Set([0, 1, 2]) && zip(points, points.dropFirst()).allSatisfy { $1.date.timeIntervalSince($0.date) <= 300 }
    }

    static func evaluate(input: StressDayInput, baselines: StressBaselines, prior: Self, since: Date,
                         now: Date, calendar: Calendar) -> (state: Self, event: StressWindow?) {
        var next = prior
        var event: StressWindow?
        let lower = max(prior.through, since, calendar.startOfDay(for: now))
        for window in StressScoreCalculator.windows(for: input, baselines: baselines, calendar: calendar, now: now) {
            guard window.interval.start >= lower, window.interval.duration == 900,
                  window.interval.end <= now.addingTimeInterval(-1800) else { continue }
            next.through = window.interval.end
            guard input.sleepInterval.map({ !$0.intersects(window.interval) }) ?? true,
                  hasCoverage(window.interval, samples: input.heartRateSamples), let band = window.band else { continue }
            if band == .high {
                if !next.high { event = window }
                next.high = true
            } else { next.high = false }
        }
        return (next, event)
    }
}
