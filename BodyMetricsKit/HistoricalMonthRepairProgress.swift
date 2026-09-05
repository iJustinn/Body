import Foundation

/// A bounded-staleness cursor, encoded in the same envelope as repaired inputs.
/// One month per eligible pass; a completed cycle waits a day before restarting.
struct HistoricalMonthRepairProgress: Codable, Equatable, Sendable {
    let nextMonthStart: Date?
    let validatedAt: Date
    let context: String

    static func candidate(
        after progress: Self?, now: Date, earliest: Date,
        context: String, calendar: Calendar
    ) -> Date? {
        guard let current = calendar.dateInterval(of: .month, for: now)?.start,
              let newest = calendar.date(byAdding: .month, value: -1, to: current),
              let floor = calendar.dateInterval(of: .month, for: earliest)?.start,
              floor <= newest else { return nil }
        if let progress, progress.context == context {
            let age = now.timeIntervalSince(progress.validatedAt)
            let interval: TimeInterval = progress.nextMonthStart == nil ? 86400 : 300
            if age >= 0 && age < interval { return nil }
            if age >= 0, let next = progress.nextMonthStart {
                return max(floor, min(next, newest))
            }
        }
        return newest
    }

    static func completed(
        month: Date, now: Date, earliest: Date, context: String, calendar: Calendar
    ) -> Self {
        let floor = calendar.dateInterval(of: .month, for: earliest)?.start ?? earliest
        let previous = calendar.date(byAdding: .month, value: -1, to: month)
        return .init(nextMonthStart: previous.flatMap { $0 >= floor ? $0 : nil },
            validatedAt: now, context: context)
    }
}
