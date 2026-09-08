import Foundation

/// Delta membership only chooses repair coverage. It never supplies a score.
struct WorkoutJournalRepairPlan {
    let months: [BodyWorkoutMonthKey]

    init?(journal: WorkoutChangeJournal, retainedMonths: Set<BodyWorkoutMonthKey>,
          date: Date, calendar: Calendar) {
        var keys: Set<BodyWorkoutMonthKey> = []
        var intervals = Array(journal.dirtyIntervals.values)
        if journal.requiresFullRepair {
            keys.formUnion(retainedMonths)
            intervals.append(DateInterval(start: date.addingTimeInterval(-408 * 86_400), end: date))
        }
        for interval in intervals {
            guard var cursor = calendar.dateInterval(of: .month, for: interval.start)?.start,
                  let last = calendar.dateInterval(of: .month, for: interval.end)?.start else { return nil }
            // Refuse pathological coverage without discarding its obligation.
            var count = 0
            while cursor <= last {
                count += 1
                guard count <= 2_400, keys.count <= 2_400 else { return nil }
                keys.insert(BodyWorkoutMonthKey(date: cursor, calendar: calendar))
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor), next > cursor else { return nil }
                cursor = next
            }
        }
        months = keys.sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    }

    static func identity(_ key: BodyWorkoutMonthKey) -> String { "\(key.year):\(key.month)" }
}
