//
//  ActivityRings.swift
//  Body
//

import Foundation

struct ActivityRingSummary: Codable, Equatable {
    var move: ActivityRingMetric
    var exercise: ActivityRingMetric
    var stand: ActivityRingMetric

    var isCompleted: Bool {
        move.isClosed &&
            exercise.isClosed &&
            stand.isClosed
    }

    var isEmpty: Bool {
        move.value == nil &&
            move.goal == nil &&
            exercise.value == nil &&
            exercise.goal == nil &&
            stand.value == nil &&
            stand.goal == nil
    }

    static let empty = ActivityRingSummary(
        move: .empty,
        exercise: .empty,
        stand: .empty
    )
}

struct ActivityRingMetric: Codable, Equatable {
    var value: Double?
    var goal: Double?

    var progress: Double {
        min(completionProgress, 1)
    }

    var completionProgress: Double {
        guard let value, let goal, goal > 0, value.isFinite, goal.isFinite else {
            return 0
        }

        return max(value / goal, 0)
    }

    var headProgress: Double {
        let remainder = completionProgress.truncatingRemainder(dividingBy: 1)
        return completionProgress >= 1 && remainder == 0 ? 1 : remainder
    }

    /// Whether the ring counts as closed. Compares the whole-number values the UI
    /// displays (both sides `.rounded()`), so a day shown as "500/500" earns its
    /// star even when the raw HealthKit value is fractionally short (499.6/500).
    var isClosed: Bool {
        guard let value, let goal, value.isFinite, goal.isFinite else {
            return false
        }

        let roundedGoal = goal.rounded()
        guard roundedGoal >= 1 else {
            return false
        }

        return value.rounded() >= roundedGoal
    }

    var showsFullStartMarker: Bool {
        completionProgress <= 0
    }

    static let empty = ActivityRingMetric(value: nil, goal: nil)
}

struct ActivityRingDaySummary: Codable, Equatable, Identifiable {
    var date: Date
    var summary: ActivityRingSummary
    /// HealthKit activity summaries identify a Gregorian calendar day. `date`
    /// remains the original query instant for backward decoding, not grouping.
    var calendarDay: CalendarDay?

    struct CalendarDay: Codable, Equatable {
        let year: Int
        let month: Int
        let day: Int

        init(date: Date, calendar: Calendar) {
            year = calendar.component(.year, from: date)
            month = calendar.component(.month, from: date)
            day = calendar.component(.day, from: date)
        }

        func date(in calendar: Calendar) -> Date? {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.year, from: date) == year,
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day else { return nil }
            return date
        }
    }

    init(date: Date, summary: ActivityRingSummary, calendar: Calendar = .bodyGregorian) {
        self.date = date
        self.summary = summary
        calendarDay = CalendarDay(date: date, calendar: calendar)
    }

    func date(in calendar: Calendar) -> Date? {
        calendarDay?.date(in: calendar)
    }

    var monthKey: ActivityRingMonthKey? {
        calendarDay.map { ActivityRingMonthKey(month: $0.month, year: $0.year) }
    }

    var id: Date {
        date
    }
}

struct ActivityRingCalendarDay: Equatable, Identifiable {
    var date: Date
    var summary: ActivityRingSummary
    var hasData: Bool
    var isFuture: Bool

    var id: Date {
        date
    }
}

struct ActivityRingCalendarMonth: Equatable, Identifiable {
    var month: Int
    var year: Int
    var days: [ActivityRingCalendarDay]

    var id: String {
        "\(year)-\(month)"
    }

    var completedRingCount: Int {
        days.filter { day in
            day.hasData && !day.isFuture && day.summary.isCompleted
        }
        .count
    }

    var closedMoveRingCount: Int { closedRingCount(\.move) }
    var closedExerciseRingCount: Int { closedRingCount(\.exercise) }
    var closedStandRingCount: Int { closedRingCount(\.stand) }

    private func closedRingCount(_ ring: KeyPath<ActivityRingSummary, ActivityRingMetric>) -> Int {
        days.filter { $0.hasData && !$0.isFuture && $0.summary[keyPath: ring].isClosed }.count
    }
}

struct ActivityRingMonthKey: Codable, Equatable, Hashable, Identifiable {
    let month: Int
    let year: Int

    var id: String {
        "\(year)-\(month)"
    }

    init(month: Int, year: Int) {
        self.month = month
        self.year = year
    }

    init(date: Date, calendar: Calendar = .bodyGregorian) {
        month = calendar.component(.month, from: date)
        year = calendar.component(.year, from: date)
    }

    func startDate(calendar: Calendar = .bodyGregorian) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }
}

struct ActivityRingHistorySnapshot: Codable, Equatable {
    var days: [ActivityRingDaySummary]
    var loadedMonthKeys: [ActivityRingMonthKey]
    /// Legacy instants have no proven original zone. Keep their values on disk,
    /// but do not display guessed calendar days or count them as closed rings.
    var unattributedDays: [ActivityRingDaySummary]
    /// Authoritative query coverage, including empty months omitted from the UI.
    var validatedMonthKeys: [ActivityRingMonthKey]

    var pendingDayIdentityMonthKeys: [ActivityRingMonthKey] {
        let pending = Set(unattributedDays.flatMap { Self.possibleMonthKeys(for: $0) })
            .subtracting(validatedMonthKeys)
        return Self.sortedUniqueMonthKeys(Array(pending))
    }

    private static let attributionCalendar: Calendar = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc
    }()

    private static func possibleMonthKeys(for day: ActivityRingDaySummary) -> [ActivityRingMonthKey] {
        return (-2...2).map { offset in
            ActivityRingMonthKey(date: day.date.addingTimeInterval(Double(offset) * 86_400), calendar: attributionCalendar)
        }
    }

    var isEmpty: Bool {
        days.isEmpty && unattributedDays.isEmpty
    }

    static let empty = ActivityRingHistorySnapshot(days: [])

    init(days: [ActivityRingDaySummary], loadedMonthKeys: [ActivityRingMonthKey] = [],
         unattributedDays: [ActivityRingDaySummary] = [], validatedMonthKeys: [ActivityRingMonthKey]? = nil) {
        self.days = days.sorted { $0.date < $1.date }
        self.loadedMonthKeys = Self.sortedUniqueMonthKeys(loadedMonthKeys)
        self.unattributedDays = unattributedDays
        self.validatedMonthKeys = Self.sortedUniqueMonthKeys(validatedMonthKeys ?? loadedMonthKeys)
    }

    private enum CodingKeys: String, CodingKey {
        case days
        case loadedMonthKeys
        case unattributedDays
        case validatedMonthKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDays = try container.decode([ActivityRingDaySummary].self, forKey: .days)
        days = decodedDays.filter { $0.calendarDay != nil }.sorted { $0.date < $1.date }
        unattributedDays = (try container.decodeIfPresent([ActivityRingDaySummary].self, forKey: .unattributedDays) ?? [])
            + decodedDays.filter { $0.calendarDay == nil }
        // Old loaded-month claims do not prove the original day attribution.
        let hasIdentityCoverage = container.contains(.validatedMonthKeys)
        loadedMonthKeys = Self.sortedUniqueMonthKeys(
            hasIdentityCoverage ? (try container.decodeIfPresent([ActivityRingMonthKey].self, forKey: .loadedMonthKeys) ?? []) : []
        )
        validatedMonthKeys = Self.sortedUniqueMonthKeys(
            try container.decodeIfPresent([ActivityRingMonthKey].self, forKey: .validatedMonthKeys) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(days, forKey: .days)
        try container.encode(loadedMonthKeys, forKey: .loadedMonthKeys)
        try container.encode(unattributedDays, forKey: .unattributedDays)
        try container.encode(validatedMonthKeys, forKey: .validatedMonthKeys)
    }

    func calendarMonths(
        calendar: Calendar = .bodyGregorian,
        date: Date = Date(),
        visibleLoadedMonthCount: Int? = nil
    ) -> [ActivityRingCalendarMonth] {
        let today = calendar.startOfDay(for: date)
        var summariesByDay: [Date: ActivityRingSummary] = [:]
        for day in days.sorted(by: { $0.date < $1.date }) {
            guard let date = day.date(in: calendar) else { continue }
            summariesByDay[calendar.startOfDay(for: date)] = day.summary
        }
        let currentMonthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let summaryMonthStarts = Set(summariesByDay.keys
            .compactMap { calendar.dateInterval(of: .month, for: $0)?.start }
            .filter { $0 <= currentMonthStart })
        let loadedMonthStarts = loadedMonthKeySet(calendar: calendar)
            .compactMap { $0.startDate(calendar: calendar) }
            .filter { $0 <= currentMonthStart }
        let earliestSummaryMonthStart = summaryMonthStarts.min()
        let displayableLoadedMonthStarts = loadedMonthStarts.filter { loadedMonthStart in
            guard let earliestSummaryMonthStart else {
                return loadedMonthStart >= currentMonthStart
            }

            return loadedMonthStart >= earliestSummaryMonthStart
        }
        var monthStarts = Array(summaryMonthStarts.union(displayableLoadedMonthStarts))
            .sorted()

        if monthStarts.isEmpty {
            monthStarts = [currentMonthStart]
        }

        if let visibleLoadedMonthCount {
            monthStarts = Array(monthStarts.suffix(max(visibleLoadedMonthCount, 1)))
        }

        return monthStarts.compactMap { monthStart in
            guard calendar.dateInterval(of: .month, for: monthStart) != nil else {
                return nil
            }

            let month = calendar.component(.month, from: monthStart)
            let year = calendar.component(.year, from: monthStart)
            let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<1
            let calendarDays = dayRange.compactMap { day -> ActivityRingCalendarDay? in
                guard let dayDate = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                    return nil
                }

                let dayStart = calendar.startOfDay(for: dayDate)
                let summary = summariesByDay[dayStart]
                return ActivityRingCalendarDay(
                    date: dayStart,
                    summary: summary ?? .empty,
                    hasData: summary != nil,
                    isFuture: dayStart > today
                )
            }

            return ActivityRingCalendarMonth(month: month, year: year, days: calendarDays)
        }
    }

    func loadedMonthKeySet(calendar: Calendar = .bodyGregorian) -> [ActivityRingMonthKey] {
        let dayMonthKeys = days.compactMap(\.monthKey)
        return Self.sortedUniqueMonthKeys(loadedMonthKeys + dayMonthKeys)
    }

    func filteringDaysToLoadedMonths(calendar: Calendar = .bodyGregorian) -> ActivityRingHistorySnapshot {
        let loadedKeys = Set(loadedMonthKeys)
        guard !loadedKeys.isEmpty else {
            return self
        }

        return ActivityRingHistorySnapshot(
            days: days.filter { $0.monthKey.map { loadedKeys.contains($0) } ?? false },
            loadedMonthKeys: loadedMonthKeys, unattributedDays: unattributedDays, validatedMonthKeys: validatedMonthKeys
        )
    }

    func removingLikelyBoundaryTruncatedLoadedMonths(
        date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> ActivityRingHistorySnapshot {
        let currentMonthStart = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let explicitLoadedKeys = Set(loadedMonthKeys)
        guard !explicitLoadedKeys.isEmpty else {
            return self
        }

        let daysByMonth = Dictionary(grouping: days) { day in
            day.monthKey
        }
        let truncatedKeys = explicitLoadedKeys.filter { key in
            guard
                !validatedMonthKeys.contains(key),
                let monthStart = key.startDate(calendar: calendar),
                monthStart < currentMonthStart,
                let monthDays = daysByMonth[key],
                monthDays.count == 1,
                let onlyDay = monthDays.first
            else {
                return false
            }

            return onlyDay.calendarDay?.day == 1
        }

        guard !truncatedKeys.isEmpty else {
            return self
        }

        return ActivityRingHistorySnapshot(
            days: days.filter { day in day.monthKey.map { !truncatedKeys.contains($0) } ?? true },
            loadedMonthKeys: loadedMonthKeys.filter { !truncatedKeys.contains($0) },
            unattributedDays: unattributedDays, validatedMonthKeys: validatedMonthKeys
        )
    }

    /// Loaded-month keys older than the earliest month with day data never
    /// display (see `calendarMonths`), but they make older-month pagination
    /// resume from however far back a previous session probed. Strips them;
    /// gap months between data months are kept. With no day data at all,
    /// keeps the recent dashboard window (current month and the prior
    /// `keepingRecentMonthCount - 1`) so a legitimately empty fresh-install
    /// cache isn't stripped and refetched.
    func removingLoadedMonthsOlderThanEarliestData(
        date: Date = Date(),
        calendar: Calendar = .bodyGregorian,
        keepingRecentMonthCount: Int = 3
    ) -> ActivityRingHistorySnapshot {
        guard !loadedMonthKeys.isEmpty else {
            return self
        }

        let earliestKeptMonthStart: Date
        if let earliestDayDate = days.compactMap({ $0.date(in: calendar) }).min() {
            guard let earliestDataMonthStart = calendar.dateInterval(of: .month, for: earliestDayDate)?.start else {
                return self
            }

            earliestKeptMonthStart = earliestDataMonthStart
        } else {
            guard
                let currentMonthStart = calendar.dateInterval(of: .month, for: date)?.start,
                let windowStart = calendar.date(
                    byAdding: .month,
                    value: -(max(keepingRecentMonthCount, 1) - 1),
                    to: currentMonthStart
                )
            else {
                return self
            }

            earliestKeptMonthStart = windowStart
        }

        let keptKeys = loadedMonthKeys.filter { key in
            guard let keyStart = key.startDate(calendar: calendar) else {
                return false
            }

            return keyStart >= earliestKeptMonthStart
        }

        guard keptKeys.count != loadedMonthKeys.count else {
            return self
        }

        return ActivityRingHistorySnapshot(days: days, loadedMonthKeys: keptKeys,
                                           unattributedDays: unattributedDays, validatedMonthKeys: validatedMonthKeys)
    }

    /// REPLACES, it does not merge. Every month `other` claims as loaded loses
    /// the days this snapshot holds for it, and keeps only the days `other`
    /// supplies; months `other` does not claim are untouched. That is what
    /// makes a refreshed window authoritative over the cache it overwrites.
    ///
    /// Read the name as "replacing", not as the `merging` sibling directly
    /// above: a caller that hands over a month it has no days for silently
    /// erases that month. This bit once, when a backfill chunk claimed months
    /// all the way to the walk end instead of just its own window and wiped
    /// days an earlier chunk had already published. It compiles, it runs, and
    /// it produces a plausible looking calendar that is quietly missing data,
    /// so the callers pin it with tests rather than trusting the shape:
    /// `testActivityRingBackfillChunksNeverShareAMonth` (chunk windows can
    /// never claim the same month) and
    /// `testActivityRingHistoryChunksAccumulateThroughTheApplyFunnel` (days
    /// survive across arrivals).
    func replacingLoadedMonths(
        with other: ActivityRingHistorySnapshot,
        calendar: Calendar = .bodyGregorian
    ) -> ActivityRingHistorySnapshot {
        let otherLoadedKeys = other.loadedMonthKeys.isEmpty
            ? other.loadedMonthKeySet(calendar: calendar)
            : other.loadedMonthKeys
        // Empty validated chunks are authoritative too, even when their months
        // are omitted from the visible grid. Their coverage is exactly the
        // query window, never a speculative span to the history start.
        let replacementKeys = Set(otherLoadedKeys + other.validatedMonthKeys)
        let retainedDays = days.filter { day in
            day.monthKey.map { !replacementKeys.contains($0) } ?? true
        }

        let validated = Set(validatedMonthKeys + other.validatedMonthKeys)
        var archived = unattributedDays
        for day in other.unattributedDays where !archived.contains(day) { archived.append(day) }
        // A legacy midnight could name either side of a month boundary. Do not
        // retire it until every possible month has been read successfully. Use
        // a conservative two-day UTC margin, wider than any supported zone.
        archived.removeAll { day in
            Self.possibleMonthKeys(for: day).allSatisfy { validated.contains($0) }
        }

        return ActivityRingHistorySnapshot(
            days: retainedDays + other.days,
            loadedMonthKeys: loadedMonthKeys + otherLoadedKeys,
            unattributedDays: archived, validatedMonthKeys: Array(validated)
        )
    }

    private static func sortedUniqueMonthKeys(_ keys: [ActivityRingMonthKey]) -> [ActivityRingMonthKey] {
        Array(Set(keys)).sorted {
            if $0.year == $1.year {
                return $0.month < $1.month
            }

            return $0.year < $1.year
        }
    }
}
