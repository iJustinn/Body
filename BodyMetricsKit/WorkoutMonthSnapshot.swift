//
//  WorkoutMonthSnapshot.swift
//  Body
//

import Foundation
import os

struct WorkoutDaySummary: Codable, Equatable, Identifiable {
    let dateKey: String
    let day: Int
    let workouts: [WorkoutSummary]
    /// The device zone this day's workouts were resolved in when the snapshot was
    /// built (the first workout's, in start order, on the rare day that resolved
    /// to more than one). `nil` when no zone was resolved: no resolver, no ledger
    /// record covering the workout, a resolved zone that would have left the
    /// month, or a snapshot written before this field existed. A row that prints
    /// a workout's date or time next to this day's header formats it in this zone
    /// so the two agree; `nil` keeps the current zone, as before. Optional on
    /// decode and omitted from the encoded form when `nil`, so old snapshots load
    /// here and new ones load in builds that predate the field.
    let timeZoneIdentifier: String?

    init(
        dateKey: String,
        day: Int,
        workouts: [WorkoutSummary],
        timeZoneIdentifier: String? = nil
    ) {
        self.dateKey = dateKey
        self.day = day
        self.workouts = workouts
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var id: String { dateKey }

    var workoutCount: Int {
        workouts.count
    }

    var totalDuration: TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }

    var totalEnergyKilocalories: Double {
        workouts.reduce(0) { $0 + ($1.activeEnergyKilocalories ?? 0) }
    }

    var totalDistanceMeters: Double {
        workouts.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
    }

    var primaryWorkoutType: BodyWorkoutType? {
        workouts
            .sorted {
                if $0.duration == $1.duration {
                    return $0.startDate < $1.startDate
                }
                return $0.duration > $1.duration
            }
            .first?
            .type
    }

    var distinctWorkoutTypes: [BodyWorkoutType] {
        var seen: Set<BodyWorkoutType> = []
        return workouts.compactMap { workout in
            guard seen.insert(workout.type).inserted else { return nil }
            return workout.type
        }
    }
}

struct WorkoutMonthSnapshot: Codable, Equatable {
    /// Bumped when the persisted shape changes in a way that requires a
    /// migration on load. Optional on decode so existing on-disk snapshots
    /// (which predate this field) load as `nil` and are treated as the
    /// implicit baseline. New saves write the current value.
    static let currentSchemaVersion = 1

    let month: Int
    let year: Int
    let generatedAt: Date
    let days: [WorkoutDaySummary]
    let schemaVersion: Int?

    init(
        month: Int,
        year: Int,
        generatedAt: Date,
        days: [WorkoutDaySummary],
        schemaVersion: Int? = WorkoutMonthSnapshot.currentSchemaVersion
    ) {
        self.month = month
        self.year = year
        self.generatedAt = generatedAt
        self.days = days
        self.schemaVersion = schemaVersion
    }

    var activeDayCount: Int {
        days.filter { !$0.workouts.isEmpty }.count
    }

    var workoutCount: Int {
        days.reduce(0) { $0 + $1.workoutCount }
    }

    var totalDuration: TimeInterval {
        days.reduce(0) { $0 + $1.totalDuration }
    }

    var totalEnergyKilocalories: Double {
        days.reduce(0) { $0 + $1.totalEnergyKilocalories }
    }

    var totalDistanceMeters: Double {
        days.reduce(0) { $0 + $1.totalDistanceMeters }
    }

    var workoutTypeBreakdown: [WorkoutTypeBreakdown] {
        var totals: [BodyWorkoutType: (duration: TimeInterval, count: Int)] = [:]

        for day in days {
            for workout in day.workouts {
                let current = totals[workout.type] ?? (duration: 0, count: 0)
                totals[workout.type] = (
                    duration: current.duration + workout.duration,
                    count: current.count + 1
                )
            }
        }

        return totals
            .map { entry in
                WorkoutTypeBreakdown(
                    type: entry.key,
                    duration: entry.value.duration,
                    count: entry.value.count
                )
            }
            .sorted {
                if $0.duration == $1.duration {
                    // The raw value is the last resort: two types with the same
                    // duration *and* the same priority would otherwise come out in
                    // dictionary order, and the leading entry picks the summary
                    // card's tint and its "Top Activity".
                    if $0.type.displayPriority == $1.type.displayPriority {
                        return $0.type.rawValue < $1.type.rawValue
                    }
                    return $0.type.displayPriority > $1.type.displayPriority
                }
                return $0.duration > $1.duration
            }
    }

    var leadingBlankDayCount: Int {
        let calendar = Calendar.bodyGregorian
        return calendar.leadingBlankDayCount(for: Self.date(month: month, year: year, day: 1, calendar: calendar))
    }

    var monthTitle: String {
        guard let date = Calendar.bodyGregorian.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return "\(month)/\(year)"
        }

        return BodyDateFormatterCache.formatter(template: "yMMMM").string(from: date)
    }

    func day(_ number: Int) -> WorkoutDaySummary? {
        days.first { $0.day == number }
    }

    /// Whether `reference` falls on `day` within this snapshot's month, used to
    /// highlight "today" in the calendar grid. Returns `false` whenever the
    /// snapshot is showing a different month or year than `reference`, so past
    /// or future months never highlight a day.
    func isToday(_ day: WorkoutDaySummary, reference: Date = Date(), calendar: Calendar = .bodyGregorian) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: reference)
        return components.year == year
            && components.month == month
            && components.day == day.day
    }

    /// `timeZoneIdentifier` resolves the zone the device was in when a workout
    /// started, so a workout keeps the calendar day it happened on instead of
    /// being re-dayed by whatever zone the phone is in now. `nil` (the default,
    /// and any day the resolver has no record for) groups by `calendar`'s own
    /// zone exactly as before.
    static func make(
        month: Int,
        year: Int,
        workouts: [WorkoutSummary],
        calendar: Calendar = .bodyGregorian,
        generatedAt: Date = Date(),
        timeZoneIdentifier: ((Date) -> String?)? = nil
    ) -> WorkoutMonthSnapshot {
        guard let range = calendar.range(of: .day, in: .month, for: date(month: month, year: year, day: 1, calendar: calendar)) else {
            return WorkoutMonthSnapshot(month: month, year: year, generatedAt: generatedAt, days: [])
        }

        // Each workout keeps the zone its day was resolved in alongside its key,
        // so the day it lands in can carry that zone for presentation.
        let keyed = workouts.map { workout -> (key: String, zoneIdentifier: String?, workout: WorkoutSummary) in
            // A resolved zone only wins while it keeps the workout inside the
            // month being built: `range.map` below drops any key outside it, so
            // a workout the resolved zone pushes into the neighbouring month
            // would vanish from both months rather than move.
            if let identifier = timeZoneIdentifier?(workout.startDate),
               let zone = TimeZone(identifier: identifier) {
                var zonedCalendar = calendar
                zonedCalendar.timeZone = zone
                let zoned = zonedCalendar.dateComponents([.year, .month, .day], from: workout.startDate)
                if zoned.year == year, zoned.month == month {
                    return (dateKey(year: year, month: month, day: zoned.day ?? 1), identifier, workout)
                }
            }
            let components = calendar.dateComponents([.year, .month, .day], from: workout.startDate)
            let key = dateKey(year: components.year ?? year, month: components.month ?? month, day: components.day ?? 1)
            return (key, nil, workout)
        }
        let grouped = Dictionary(grouping: keyed, by: \.key)

        let days = range.map { day in
            let key = dateKey(year: year, month: month, day: day)
            let entries = (grouped[key] ?? []).sorted { $0.workout.startDate < $1.workout.startDate }
            return WorkoutDaySummary(
                dateKey: key,
                day: day,
                workouts: entries.map(\.workout),
                // The earliest workout's zone on a day that resolved to more than
                // one, which only a mid-day zone change can produce.
                timeZoneIdentifier: entries.first?.zoneIdentifier
            )
        }

        return WorkoutMonthSnapshot(month: month, year: year, generatedAt: generatedAt, days: days)
    }

    /// Returns a copy with the Workout Metrics detail fields (VO₂max, power,
    /// cadence, swim strokes) stripped from every workout, for when the user
    /// disables the Workout Metrics permission. Preserves the month identity and
    /// `generatedAt` so a re-saved snapshot stays change-deduped on disk. Maps
    /// each day's workouts in place rather than regrouping by `dateKey` through
    /// `calendar`, so a workout near a month boundary is never reassigned to a
    /// different day (and dropped outright) just because the calendar's time
    /// zone changed since the snapshot was built. `calendar` is unused; kept
    /// only so existing call sites do not need to change.
    func removingWorkoutMetrics(calendar: Calendar = .bodyGregorian) -> WorkoutMonthSnapshot {
        WorkoutMonthSnapshot(
            month: month,
            year: year,
            generatedAt: generatedAt,
            days: days.map { day in
                WorkoutDaySummary(
                    dateKey: day.dateKey,
                    day: day.day,
                    workouts: day.workouts.map { $0.removingWorkoutMetrics() },
                    timeZoneIdentifier: day.timeZoneIdentifier
                )
            },
            schemaVersion: schemaVersion
        )
    }

    /// Returns a copy with heart-rate recovery stripped from every workout, for
    /// when the user disables the Heart permission. Same identity/`generatedAt`
    /// preservation and in-place-mapping rationale as
    /// `removingWorkoutMetrics(calendar:)`. `calendar` is unused; kept only so
    /// existing call sites do not need to change.
    func removingHeartRateRecovery(calendar: Calendar = .bodyGregorian) -> WorkoutMonthSnapshot {
        WorkoutMonthSnapshot(
            month: month,
            year: year,
            generatedAt: generatedAt,
            days: days.map { day in
                WorkoutDaySummary(
                    dateKey: day.dateKey,
                    day: day.day,
                    workouts: day.workouts.map { $0.removingHeartRateRecovery() },
                    timeZoneIdentifier: day.timeZoneIdentifier
                )
            },
            schemaVersion: schemaVersion
        )
    }

    static var placeholder: WorkoutMonthSnapshot {
        makePlaceholder(generatedAt: Date(), calendar: .bodyGregorian)
    }

    /// A truthful "no data yet" snapshot for the month containing `generatedAt`
    /// — unlike `.placeholder`, this contains no fabricated workouts. Used
    /// wherever live (non-preview) data is unavailable so views render an
    /// honest empty state instead of sample content masquerading as real
    /// history.
    static func makeEmpty(
        generatedAt: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> WorkoutMonthSnapshot {
        let month = calendar.component(.month, from: generatedAt)
        let year = calendar.component(.year, from: generatedAt)
        return make(month: month, year: year, workouts: [], calendar: calendar, generatedAt: generatedAt)
    }

    static func makePlaceholder(
        generatedAt: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> WorkoutMonthSnapshot {
        let month = calendar.component(.month, from: generatedAt)
        let year = calendar.component(.year, from: generatedAt)
        let sampleWorkouts: [WorkoutSummary] = [
            sampleWorkout(day: 1, month: month, year: year, type: .running, duration: 2_400, energy: 310, distance: 5_200, calendar: calendar),
            sampleWorkout(day: 2, month: month, year: year, type: .strengthTraining, duration: 3_600, energy: 410, distance: nil, calendar: calendar),
            sampleWorkout(day: 3, month: month, year: year, type: .walking, duration: 1_800, energy: 145, distance: 2_100, calendar: calendar),
            sampleWorkout(day: 4, month: month, year: year, type: .yoga, duration: 2_700, energy: 120, distance: nil, calendar: calendar),
            sampleWorkout(day: 5, month: month, year: year, type: .strengthTraining, duration: 3_000, energy: 330, distance: nil, calendar: calendar),
            sampleWorkout(day: 6, month: month, year: year, type: .cycling, duration: 4_200, energy: 520, distance: 18_000, calendar: calendar),
            sampleWorkout(day: 7, month: month, year: year, type: .running, duration: 2_200, energy: 285, distance: 4_800, calendar: calendar),
            sampleWorkout(day: 8, month: month, year: year, type: .hiit, duration: 1_500, energy: 260, distance: nil, calendar: calendar),
            sampleWorkout(day: 9, month: month, year: year, type: .hiking, duration: 5_400, energy: 610, distance: 7_300, calendar: calendar)
        ]

        return make(month: month, year: year, workouts: sampleWorkouts, calendar: calendar, generatedAt: generatedAt)
    }

    private func dateComponents(day: Int, calendar: Calendar) -> DateComponents {
        calendar.dateComponents(
            [.weekday],
            from: Self.date(month: month, year: year, day: day, calendar: calendar)
        )
    }

    private static func sampleWorkout(
        day: Int,
        month: Int,
        year: Int,
        type: BodyWorkoutType,
        duration: TimeInterval,
        energy: Double?,
        distance: Double?,
        calendar: Calendar
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", day))") ?? UUID(),
            type: type,
            startDate: date(month: month, year: year, day: day, calendar: calendar),
            duration: duration,
            activeEnergyKilocalories: energy,
            distanceMeters: distance,
            sourceName: "Preview"
        )
    }

    private static func date(month: Int, year: Int, day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private static func dateKey(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension Calendar {
    func bodyRotatedVeryShortWeekdaySymbols(locale: Locale = .current) -> [String] {
        let formatter = BodyDateFormatterCache.formatter(dateFormat: "", calendar: self, locale: locale)
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        let fallback = ["S", "M", "T", "W", "T", "F", "S"]
        let source = symbols.isEmpty ? fallback : symbols
        let startIndex = max(0, firstWeekday - 1)
        return Array(source[startIndex...]) + Array(source[..<startIndex])
    }

    func leadingBlankDayCount(for firstDate: Date) -> Int {
        let weekday = component(.weekday, from: firstDate)
        return (weekday - firstWeekday + 7) % 7
    }
}

struct WorkoutTypeBreakdown: Equatable, Identifiable {
    let type: BodyWorkoutType
    let duration: TimeInterval
    let count: Int

    var id: BodyWorkoutType { type }
}

extension Calendar {
    /// Caches the built calendar so every call site does not pay to
    /// reconstruct one, rebuilding only when the device's time zone has
    /// actually changed. `firstWeekday` is pinned to `1` (Sunday) regardless
    /// of locale, so the captured `Locale` at build time does not matter and
    /// does not need to be part of the cache key.
    private static let bodyGregorianCache = OSAllocatedUnfairLock<(timeZoneID: String, calendar: Calendar)?>(initialState: nil)

    static var bodyGregorian: Calendar {
        let currentTimeZoneID = TimeZone.current.identifier
        return bodyGregorianCache.withLock { cached in
            if let cached, cached.timeZoneID == currentTimeZoneID {
                return cached.calendar
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = 1
            cached = (timeZoneID: currentTimeZoneID, calendar: calendar)
            return calendar
        }
    }
}
