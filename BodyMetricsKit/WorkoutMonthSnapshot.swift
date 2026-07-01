//
//  WorkoutMonthSnapshot.swift
//  Body
//

import Foundation

struct WorkoutDaySummary: Codable, Equatable, Identifiable {
    let dateKey: String
    let day: Int
    let workouts: [WorkoutSummary]

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

        return BodyDateFormatterCache.formatter(dateFormat: "MMMM yyyy").string(from: date)
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

    static func make(
        month: Int,
        year: Int,
        workouts: [WorkoutSummary],
        calendar: Calendar = .bodyGregorian,
        generatedAt: Date = Date()
    ) -> WorkoutMonthSnapshot {
        guard let range = calendar.range(of: .day, in: .month, for: date(month: month, year: year, day: 1, calendar: calendar)) else {
            return WorkoutMonthSnapshot(month: month, year: year, generatedAt: generatedAt, days: [])
        }

        let grouped = Dictionary(grouping: workouts) { workout in
            let components = calendar.dateComponents([.year, .month, .day], from: workout.startDate)
            return dateKey(year: components.year ?? year, month: components.month ?? month, day: components.day ?? 1)
        }

        let days = range.map { day in
            let key = dateKey(year: year, month: month, day: day)
            return WorkoutDaySummary(
                dateKey: key,
                day: day,
                workouts: (grouped[key] ?? []).sorted { $0.startDate < $1.startDate }
            )
        }

        return WorkoutMonthSnapshot(month: month, year: year, generatedAt: generatedAt, days: days)
    }

    /// Returns a copy with the Workout Metrics detail fields (VO₂max, power,
    /// cadence, swim strokes) stripped from every workout, for when the user
    /// disables the Workout Metrics permission. Preserves the month identity and
    /// `generatedAt` so a re-saved snapshot stays change-deduped on disk.
    func removingWorkoutMetrics(calendar: Calendar = .bodyGregorian) -> WorkoutMonthSnapshot {
        WorkoutMonthSnapshot.make(
            month: month,
            year: year,
            workouts: days.flatMap(\.workouts).map { $0.removingWorkoutMetrics() },
            calendar: calendar,
            generatedAt: generatedAt
        )
    }

    static var placeholder: WorkoutMonthSnapshot {
        makePlaceholder(generatedAt: Date(), calendar: .bodyGregorian)
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
    static var bodyGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        return calendar
    }
}
