//
//  HealthSummarySnapshot.swift
//  Body
//

import Foundation
import os

enum HealthMetricKind: String, CaseIterable, Identifiable {
    case sleep
    case basics
    case restingHeartRate
    case bodyMass
    case bodyFatPercentage
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case bodyMassIndex
    case activeEnergy
    case restingEnergy
    case exerciseMinutes
    case wristTemperature
    case timeInDaylight
    case steps

    var id: String {
        rawValue
    }

    var detailHelpText: HealthMetricDetailHelpText? {
        switch self {
        case .sleep:
            return HealthMetricDetailHelpText(
                title: "About Sleep",
                body: "Sleep combines your recent sleep duration, stage breakdown, and sleep score into one view. Your own baseline matters more than a single night. Use the trend to spot repeated short sleep, fragmented nights, or shifts in deep and REM sleep that may line up with stress, travel, training, or illness."
            )
        case .basics:
            return HealthMetricDetailHelpText(
                title: "About Basics",
                body: "Basics tracks weight, body fat, and BMI together so changes are easier to compare in context. Daily movement can reflect hydration, meals, measurement timing, or device differences. Longer trends are usually more useful than single readings."
            )
        case .restingHeartRate:
            return HealthMetricDetailHelpText(
                title: "About Resting Heart Rate",
                body: "Resting heart rate is the number of beats per minute while your body is at rest. A lower value can come with better aerobic fitness, but your own baseline matters most. Watch for sustained changes from your usual range, especially if they happen with symptoms, illness, stress, dehydration, or medication changes."
            )
        case .bodyMass:
            return HealthMetricDetailHelpText(
                title: "About Weight",
                body: "Weight is your recorded body mass from Apple Health or connected devices. Short-term changes often come from hydration, food, sodium, exercise, or measurement timing. Compare readings taken under similar conditions and focus on the direction over weeks."
            )
        case .bodyFatPercentage:
            return HealthMetricDetailHelpText(
                title: "About Body Fat",
                body: "Body fat percentage estimates how much of your body mass is fat tissue. Consumer scales and devices can vary with hydration, skin temperature, and measurement timing, so the trend is more useful than one reading. Compare it alongside weight and how you feel."
            )
        case .heartRateVariability:
            return HealthMetricDetailHelpText(
                title: "About HRV",
                body: "Heart rate variability measures the small timing changes between heartbeats. Higher than your usual baseline often points to better recovery and lower strain; lower than usual can follow hard training, poor sleep, alcohol, illness, or stress. Compare trends over weeks instead of judging one day by itself."
            )
        case .respiratoryRate:
            return HealthMetricDetailHelpText(
                title: "About Respiratory Rate",
                body: "Respiratory rate is breaths per minute, often measured during sleep or quiet periods. A stable personal baseline is usually the most useful signal. Sustained increases or drops can reflect illness, altitude, stress, alcohol, or sleep disruption; check with a clinician if the change is unusual for you."
            )
        case .oxygenSaturation:
            return HealthMetricDetailHelpText(
                title: "About Blood Oxygen",
                body: "Blood oxygen estimates the percentage of oxygen carried by your blood. It is usually fairly steady at rest, and fit or motion can affect readings. Repeated low readings, sudden drops, or low values with shortness of breath, chest pain, or confusion need medical attention."
            )
        case .bodyMassIndex:
            return HealthMetricDetailHelpText(
                title: "About BMI",
                body: "BMI is a weight-to-height calculation used as a broad screening measure. It does not distinguish fat, muscle, bone, or body shape, so it is best treated as context rather than a diagnosis. Compare it with weight, body fat, activity, and your personal goals."
            )
        case .activeEnergy:
            return HealthMetricDetailHelpText(
                title: "About Active Energy",
                body: "Active Energy estimates calories you burn through movement and workouts, above your resting needs. More is not automatically better; useful context comes from matching activity to your goals and checking how sleep, appetite, soreness, and recovery respond."
            )
        case .restingEnergy:
            return HealthMetricDetailHelpText(
                title: "About Resting Energy",
                body: "Resting Energy estimates calories your body uses for basic functions while minimally active. It tends to change slowly with body size, age, sex, and lean mass. Day-to-day jumps are often measurement or model changes, so treat the trend as context rather than a target."
            )
        case .exerciseMinutes:
            return HealthMetricDetailHelpText(
                title: "About Exercise Minutes",
                body: "Exercise Minutes count time Apple Health classifies as brisk activity or workouts. The value can differ from workout duration because intensity, heart rate, and motion all matter. Use it to see whether your recent activity is consistently reaching meaningful effort."
            )
        case .wristTemperature:
            return HealthMetricDetailHelpText(
                title: "About Wrist Temperature",
                body: "Wrist Temperature shows changes captured during sleep from supported devices. It is most useful as a trend against your own baseline. Shifts can follow room temperature, illness, alcohol, menstrual cycle changes, travel, or wearable fit."
            )
        case .timeInDaylight:
            return HealthMetricDetailHelpText(
                title: "About Time In Daylight",
                body: "Time In Daylight estimates how long supported devices detected outdoor daylight exposure. Daylight can support circadian rhythm, mood, and sleep timing, but readings depend on device support and whether the device was worn."
            )
        case .steps:
            return HealthMetricDetailHelpText(
                title: "About Steps",
                body: "Steps estimate your walking and running step count from Apple Health sources. Phones and wearables can count differently depending on where they are worn or carried. The trend is best used to compare your usual activity level over time."
            )
        }
    }

    var detailDataSourceText: HealthMetricDetailDataSourceText? {
        switch self {
        case .sleep,
             .basics,
             .restingHeartRate,
             .heartRateVariability,
             .respiratoryRate,
             .oxygenSaturation,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .wristTemperature,
             .timeInDaylight,
             .steps:
            return HealthMetricDetailDataSourceText(sourceText: "Apple Health")
        case .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex:
            return nil
        }
    }
}

struct HealthMetricDetailHelpText: Equatable {
    var title: String
    var body: String
}

struct HealthMetricDetailDataSourceText: Equatable {
    var sourceText: String
}

struct HealthSummarySnapshot: Codable, Equatable {
    var activityRings: ActivityRingSummary
    var sleep: SleepSummary
    var restingHeartRate: HealthMetricSummary
    var bodyMass: HealthMetricSummary
    var bodyFatPercentage: HealthMetricSummary
    var heartRateVariability: HealthMetricSummary
    var respiratoryRate: HealthMetricSummary
    var oxygenSaturation: HealthMetricSummary
    var bodyMassIndex: HealthMetricSummary
    var activeEnergy: HealthMetricSummary
    var restingEnergy: HealthMetricSummary
    var exerciseMinutes: HealthMetricSummary
    var wristTemperature: HealthMetricSummary
    var timeInDaylight: HealthMetricSummary
    var steps: HealthMetricSummary

    init(
        activityRings: ActivityRingSummary,
        sleep: SleepSummary,
        restingHeartRate: HealthMetricSummary,
        bodyMass: HealthMetricSummary,
        bodyFatPercentage: HealthMetricSummary,
        heartRateVariability: HealthMetricSummary,
        respiratoryRate: HealthMetricSummary,
        oxygenSaturation: HealthMetricSummary,
        bodyMassIndex: HealthMetricSummary,
        activeEnergy: HealthMetricSummary,
        restingEnergy: HealthMetricSummary,
        exerciseMinutes: HealthMetricSummary = HealthMetricSummary(value: nil),
        wristTemperature: HealthMetricSummary = HealthMetricSummary(value: nil),
        timeInDaylight: HealthMetricSummary = HealthMetricSummary(value: nil),
        steps: HealthMetricSummary = HealthMetricSummary(value: nil)
    ) {
        self.activityRings = activityRings
        self.sleep = sleep
        self.restingHeartRate = restingHeartRate
        self.bodyMass = bodyMass
        self.bodyFatPercentage = bodyFatPercentage
        self.heartRateVariability = heartRateVariability
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.bodyMassIndex = bodyMassIndex
        self.activeEnergy = activeEnergy
        self.restingEnergy = restingEnergy
        self.exerciseMinutes = exerciseMinutes
        self.wristTemperature = wristTemperature
        self.timeInDaylight = timeInDaylight
        self.steps = steps
    }

    var isEmpty: Bool {
        activityRings.isEmpty &&
            sleep.duration == nil &&
            sleep.stageSnapshot.isEmpty &&
            sleep.vitals.isEmpty &&
            restingHeartRate.value == nil &&
            bodyMass.value == nil &&
            bodyFatPercentage.value == nil &&
            heartRateVariability.value == nil &&
            respiratoryRate.value == nil &&
            oxygenSaturation.value == nil &&
            bodyMassIndex.value == nil &&
            activeEnergy.value == nil &&
            restingEnergy.value == nil &&
            exerciseMinutes.value == nil &&
            wristTemperature.value == nil &&
            timeInDaylight.value == nil &&
            steps.value == nil
    }

    static let empty = HealthSummarySnapshot(
        activityRings: .empty,
        sleep: SleepSummary(duration: nil),
        restingHeartRate: HealthMetricSummary(value: nil),
        bodyMass: HealthMetricSummary(value: nil),
        bodyFatPercentage: HealthMetricSummary(value: nil),
        heartRateVariability: HealthMetricSummary(value: nil),
        respiratoryRate: HealthMetricSummary(value: nil),
        oxygenSaturation: HealthMetricSummary(value: nil),
        bodyMassIndex: HealthMetricSummary(value: nil),
        activeEnergy: HealthMetricSummary(value: nil),
        restingEnergy: HealthMetricSummary(value: nil),
        exerciseMinutes: HealthMetricSummary(value: nil),
        wristTemperature: HealthMetricSummary(value: nil),
        timeInDaylight: HealthMetricSummary(value: nil),
        steps: HealthMetricSummary(value: nil)
    )

    static let placeholder = HealthSummarySnapshot(
        activityRings: ActivityRingSummary(
            move: ActivityRingMetric(value: 670, goal: 500),
            exercise: ActivityRingMetric(value: 76, goal: 40),
            stand: ActivityRingMetric(value: 8, goal: 10)
        ),
        sleep: SleepSummary(
            duration: 28_740,
            vitals: SleepVitalsSummary(
                heartRate: 58,
                heartRateVariability: 62,
                respiratoryRate: 14,
                oxygenSaturation: 97,
                wristTemperatureCelsius: 36.4
            )
        ),
        restingHeartRate: HealthMetricSummary(value: 60),
        bodyMass: HealthMetricSummary(value: 69.3),
        bodyFatPercentage: HealthMetricSummary(value: 13.1),
        heartRateVariability: HealthMetricSummary(value: 38.4),
        respiratoryRate: HealthMetricSummary(value: 14),
        oxygenSaturation: HealthMetricSummary(value: 97),
        bodyMassIndex: HealthMetricSummary(value: 22.1),
        activeEnergy: HealthMetricSummary(value: 520),
        restingEnergy: HealthMetricSummary(value: 1_690),
        exerciseMinutes: HealthMetricSummary(value: 77),
        wristTemperature: HealthMetricSummary(value: 36.4),
        timeInDaylight: HealthMetricSummary(value: 32),
        steps: HealthMetricSummary(value: 1_212)
    )

    private enum CodingKeys: String, CodingKey {
        case activityRings
        case sleep
        case restingHeartRate
        case bodyMass
        case bodyFatPercentage
        case heartRateVariability
        case respiratoryRate
        case oxygenSaturation
        case bodyMassIndex
        case activeEnergy
        case restingEnergy
        case exerciseMinutes
        case wristTemperature
        case timeInDaylight
        case steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityRings = try container.decodeIfPresent(ActivityRingSummary.self, forKey: .activityRings) ?? .empty
        sleep = try container.decodeIfPresent(SleepSummary.self, forKey: .sleep) ?? SleepSummary(duration: nil)
        restingHeartRate = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .restingHeartRate) ?? HealthMetricSummary(value: nil)
        bodyMass = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .bodyMass) ?? HealthMetricSummary(value: nil)
        bodyFatPercentage = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .bodyFatPercentage) ?? HealthMetricSummary(value: nil)
        heartRateVariability = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .heartRateVariability) ?? HealthMetricSummary(value: nil)
        respiratoryRate = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .respiratoryRate) ?? HealthMetricSummary(value: nil)
        oxygenSaturation = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .oxygenSaturation) ?? HealthMetricSummary(value: nil)
        bodyMassIndex = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .bodyMassIndex) ?? HealthMetricSummary(value: nil)
        activeEnergy = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .activeEnergy) ?? HealthMetricSummary(value: nil)
        restingEnergy = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .restingEnergy) ?? HealthMetricSummary(value: nil)
        exerciseMinutes = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .exerciseMinutes) ?? HealthMetricSummary(value: nil)
        wristTemperature = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .wristTemperature) ?? HealthMetricSummary(value: nil)
        timeInDaylight = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .timeInDaylight) ?? HealthMetricSummary(value: nil)
        steps = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .steps) ?? HealthMetricSummary(value: nil)
    }

    func filtered(by selection: BodyHealthPermissionSelection) -> HealthSummarySnapshot {
        var filtered = self

        if !selection.includes(.activityRings) {
            filtered.activityRings = .empty
        }
        if !selection.includes(.sleep) {
            filtered.sleep = HealthSummarySnapshot.empty.sleep
        }
        if !selection.includes(.heart) {
            filtered.restingHeartRate = HealthSummarySnapshot.empty.restingHeartRate
            filtered.heartRateVariability = HealthSummarySnapshot.empty.heartRateVariability
            filtered.sleep.vitals.heartRate = nil
            filtered.sleep.vitals.heartRateVariability = nil
        }
        if !selection.includes(.basics) {
            filtered.bodyMass = HealthSummarySnapshot.empty.bodyMass
            filtered.bodyFatPercentage = HealthSummarySnapshot.empty.bodyFatPercentage
            filtered.bodyMassIndex = HealthSummarySnapshot.empty.bodyMassIndex
        }
        if !selection.includes(.bloodOxygen) {
            filtered.oxygenSaturation = HealthSummarySnapshot.empty.oxygenSaturation
            filtered.sleep.vitals.oxygenSaturation = nil
        }
        if !selection.includes(.respiratory) {
            filtered.respiratoryRate = HealthSummarySnapshot.empty.respiratoryRate
            filtered.sleep.vitals.respiratoryRate = nil
        }
        if !selection.includes(.energy) {
            filtered.activeEnergy = HealthSummarySnapshot.empty.activeEnergy
            filtered.restingEnergy = HealthSummarySnapshot.empty.restingEnergy
        }
        if !selection.includes(.exerciseMinutes) {
            filtered.exerciseMinutes = HealthSummarySnapshot.empty.exerciseMinutes
        }
        if !selection.includes(.wristTemperature) {
            filtered.wristTemperature = HealthSummarySnapshot.empty.wristTemperature
            filtered.sleep.vitals.wristTemperatureCelsius = nil
        }
        if !selection.includes(.timeInDaylight) {
            filtered.timeInDaylight = HealthSummarySnapshot.empty.timeInDaylight
        }
        if !selection.includes(.steps) {
            filtered.steps = HealthSummarySnapshot.empty.steps
        }

        return filtered
    }
}

struct ActivityRingSummary: Codable, Equatable {
    var move: ActivityRingMetric
    var exercise: ActivityRingMetric
    var stand: ActivityRingMetric

    var isCompleted: Bool {
        move.progress >= 1 &&
            exercise.progress >= 1 &&
            stand.progress >= 1
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
        completionProgress.truncatingRemainder(dividingBy: 1)
    }

    var showsFullStartMarker: Bool {
        completionProgress <= 0
    }

    static let empty = ActivityRingMetric(value: nil, goal: nil)
}

struct ActivityRingDaySummary: Codable, Equatable, Identifiable {
    var date: Date
    var summary: ActivityRingSummary

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
}

struct ActivityRingCalendarPaginationGate: Equatable {
    private(set) var scrollToken = 0
    private var lastLoadToken = 0

    mutating func recordUserScroll() {
        scrollToken += 1
    }

    mutating func consumeLoadIfNeeded(isOldestVisible: Bool) -> Bool {
        guard isOldestVisible, scrollToken > lastLoadToken else {
            return false
        }

        lastLoadToken = scrollToken
        return true
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

    var isEmpty: Bool {
        days.isEmpty
    }

    static let empty = ActivityRingHistorySnapshot(days: [])

    init(days: [ActivityRingDaySummary], loadedMonthKeys: [ActivityRingMonthKey] = []) {
        self.days = days.sorted { $0.date < $1.date }
        self.loadedMonthKeys = Self.sortedUniqueMonthKeys(loadedMonthKeys)
    }

    private enum CodingKeys: String, CodingKey {
        case days
        case loadedMonthKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decode([ActivityRingDaySummary].self, forKey: .days)
            .sorted { $0.date < $1.date }
        loadedMonthKeys = Self.sortedUniqueMonthKeys(
            try container.decodeIfPresent([ActivityRingMonthKey].self, forKey: .loadedMonthKeys) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(days, forKey: .days)
        try container.encode(loadedMonthKeys, forKey: .loadedMonthKeys)
    }

    func calendarMonths(
        calendar: Calendar = .bodyGregorian,
        date: Date = Date(),
        visibleLoadedMonthCount: Int? = nil
    ) -> [ActivityRingCalendarMonth] {
        let today = calendar.startOfDay(for: date)
        var summariesByDay: [Date: ActivityRingSummary] = [:]
        for day in days.sorted(by: { $0.date < $1.date }) {
            summariesByDay[calendar.startOfDay(for: day.date)] = day.summary
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
        let dayMonthKeys = days.map { ActivityRingMonthKey(date: $0.date, calendar: calendar) }
        return Self.sortedUniqueMonthKeys(loadedMonthKeys + dayMonthKeys)
    }

    func filteringDaysToLoadedMonths(calendar: Calendar = .bodyGregorian) -> ActivityRingHistorySnapshot {
        let loadedKeys = Set(loadedMonthKeys)
        guard !loadedKeys.isEmpty else {
            return self
        }

        return ActivityRingHistorySnapshot(
            days: days.filter { loadedKeys.contains(ActivityRingMonthKey(date: $0.date, calendar: calendar)) },
            loadedMonthKeys: loadedMonthKeys
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
            ActivityRingMonthKey(date: day.date, calendar: calendar)
        }
        let truncatedKeys = explicitLoadedKeys.filter { key in
            guard
                let monthStart = key.startDate(calendar: calendar),
                monthStart < currentMonthStart,
                let monthDays = daysByMonth[key],
                monthDays.count == 1,
                let onlyDay = monthDays.first
            else {
                return false
            }

            return calendar.component(.day, from: onlyDay.date) == 1
        }

        guard !truncatedKeys.isEmpty else {
            return self
        }

        return ActivityRingHistorySnapshot(
            days: days.filter { !truncatedKeys.contains(ActivityRingMonthKey(date: $0.date, calendar: calendar)) },
            loadedMonthKeys: loadedMonthKeys.filter { !truncatedKeys.contains($0) }
        )
    }

    func merging(
        _ other: ActivityRingHistorySnapshot,
        calendar: Calendar = .bodyGregorian
    ) -> ActivityRingHistorySnapshot {
        var summariesByDay: [Date: ActivityRingSummary] = [:]
        for day in days {
            summariesByDay[calendar.startOfDay(for: day.date)] = day.summary
        }
        for day in other.days {
            summariesByDay[calendar.startOfDay(for: day.date)] = day.summary
        }

        let mergedDays = summariesByDay
            .map { ActivityRingDaySummary(date: $0.key, summary: $0.value) }
            .sorted { $0.date < $1.date }
        return ActivityRingHistorySnapshot(
            days: mergedDays,
            loadedMonthKeys: loadedMonthKeySet(calendar: calendar) + other.loadedMonthKeySet(calendar: calendar)
        )
    }

    func replacingLoadedMonths(
        with other: ActivityRingHistorySnapshot,
        calendar: Calendar = .bodyGregorian
    ) -> ActivityRingHistorySnapshot {
        let otherLoadedKeys = other.loadedMonthKeys.isEmpty
            ? other.loadedMonthKeySet(calendar: calendar)
            : other.loadedMonthKeys
        let replacementKeys = Set(otherLoadedKeys)
        let retainedDays = days.filter { day in
            !replacementKeys.contains(ActivityRingMonthKey(date: day.date, calendar: calendar))
        }

        return ActivityRingHistorySnapshot(
            days: retainedDays + other.days,
            loadedMonthKeys: loadedMonthKeys + otherLoadedKeys
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

struct SleepSummary: Codable, Equatable {
    var duration: TimeInterval?
    var stageSnapshot: SleepStageSnapshot
    var vitals: SleepVitalsSummary

    init(
        duration: TimeInterval?,
        stageSnapshot: SleepStageSnapshot = .empty,
        vitals: SleepVitalsSummary = .empty
    ) {
        self.duration = duration
        self.stageSnapshot = stageSnapshot
        self.vitals = vitals
    }

    var score: SleepScoreSummary? {
        SleepScoreSummary(sleep: self)
    }
}

struct SleepDaySummary: Codable, Equatable, Identifiable {
    var date: Date
    var summary: SleepSummary

    var id: Date {
        date
    }
}

struct SleepHistorySnapshot: Codable, Equatable {
    var days: [SleepDaySummary]

    var isEmpty: Bool {
        days.isEmpty
    }

    var durationSeries: HealthTrendSeries {
        HealthTrendSeries(
            points: days.compactMap { day in
                guard let duration = day.summary.duration, duration > 0 else {
                    return nil
                }

                return HealthTrendDataPoint(date: day.date, value: duration / 3_600)
            }
        )
    }

    static let empty = SleepHistorySnapshot(days: [])

    init(days: [SleepDaySummary]) {
        self.days = days.sorted { $0.date < $1.date }
    }

    func summary(on date: Date, calendar: Calendar = .bodyGregorian) -> SleepDaySummary? {
        let dayStart = calendar.startOfDay(for: date)
        return days.first { calendar.startOfDay(for: $0.date) == dayStart }
    }

    static func datePickerDates(
        endingAt date: Date = Date(),
        dayCount: Int = 30,
        futureDayCount: Int = 0,
        calendar: Calendar = .bodyGregorian
    ) -> [Date] {
        let currentDayStart = calendar.startOfDay(for: date)
        let oldestPastOffset = max(dayCount, 1) - 1
        let newestFutureOffset = -max(futureDayCount, 0)

        return stride(from: oldestPastOffset, through: newestFutureOffset, by: -1).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: currentDayStart)
        }
    }
}

struct SleepVitalsSummary: Codable, Equatable {
    var heartRate: Double?
    var heartRateVariability: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
    var wristTemperatureCelsius: Double?

    init(
        heartRate: Double? = nil,
        heartRateVariability: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturation: Double? = nil,
        wristTemperatureCelsius: Double? = nil
    ) {
        self.heartRate = heartRate
        self.heartRateVariability = heartRateVariability
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.wristTemperatureCelsius = wristTemperatureCelsius
    }

    var isEmpty: Bool {
        heartRate == nil &&
            heartRateVariability == nil &&
            respiratoryRate == nil &&
            oxygenSaturation == nil &&
            wristTemperatureCelsius == nil
    }

    static let empty = SleepVitalsSummary(
        heartRate: nil,
        heartRateVariability: nil,
        respiratoryRate: nil,
        oxygenSaturation: nil,
        wristTemperatureCelsius: nil
    )
}

enum SleepVitalRegion: Equatable {
    case low
    case typical
    case high
}

enum SleepVitalStatusTitle {
    static func text(for regions: [SleepVitalRegion]) -> String {
        let outlierCount = regions.filter { $0 != .typical }.count

        switch outlierCount {
        case 0:
            return "Typical"
        case 1:
            return "1 Outlier"
        default:
            return "\(outlierCount) Outliers"
        }
    }
}

struct SleepVitalReferenceRange: Equatable {
    var typicalLowerBound: Double
    var typicalUpperBound: Double

    func region(for value: Double) -> SleepVitalRegion {
        if value < typicalLowerBound {
            return .low
        }

        if value > typicalUpperBound {
            return .high
        }

        return .typical
    }

    func markerPosition(for value: Double) -> Double {
        let typicalSpan = max(typicalUpperBound - typicalLowerBound, 1)
        let lowerBound = typicalLowerBound - typicalSpan
        let upperBound = typicalUpperBound + typicalSpan
        let totalSpan = upperBound - lowerBound

        guard totalSpan > 0, value.isFinite else {
            return 0.5
        }

        return min(max((value - lowerBound) / totalSpan, 0), 1)
    }
}

struct SleepStageSnapshot: Codable, Equatable {
    var date: Date?
    var segments: [SleepStageSegment]

    var isEmpty: Bool {
        segments.isEmpty
    }

    var dateInterval: DateInterval? {
        guard let startDate = segments.map(\.startDate).min(),
              let endDate = segments.map(\.endDate).max(),
              endDate > startDate else {
            return nil
        }

        return DateInterval(start: startDate, end: endDate)
    }

    func duration(for stage: SleepStage) -> TimeInterval {
        segments
            .filter { $0.stage == stage }
            .reduce(0) { partialResult, segment in
                partialResult + max(0, segment.endDate.timeIntervalSince(segment.startDate))
            }
    }

    var awakeDuration: TimeInterval {
        duration(for: .awake)
    }

    var asleepDuration: TimeInterval {
        SleepStage.sleepStages.reduce(0) { partialResult, stage in
            partialResult + duration(for: stage)
        }
    }

    var hasDetailedStages: Bool {
        segments.contains { $0.stage == .rem || $0.stage == .deep }
    }

    static let empty = SleepStageSnapshot(date: nil, segments: [])
}

struct SleepScoreSummary: Equatable {
    let total: Int
    let categories: [SleepScoreCategory]

    init?(sleep: SleepSummary) {
        guard let duration = sleep.duration, duration > 0 else {
            return nil
        }

        var categoryScores = [
            Self.category(
                kind: .duration,
                progress: Self.durationProgress(duration),
                maximumPoints: 25,
                valueDescription: BodyValueFormat.sleepDurationText(for: duration)
            )
        ]

        if let continuityCategory = Self.continuityCategory(sleep: sleep) {
            categoryScores.append(continuityCategory)
        }

        if sleep.stageSnapshot.hasDetailedStages {
            categoryScores.append(Self.stagePercentageCategory(
                kind: .deep,
                stageDuration: sleep.stageSnapshot.duration(for: .deep),
                sleepDuration: duration,
                targetPercentage: 0.20,
                maximumPoints: 15
            ))
            categoryScores.append(Self.stagePercentageCategory(
                kind: .rem,
                stageDuration: sleep.stageSnapshot.duration(for: .rem),
                sleepDuration: duration,
                targetPercentage: 0.22,
                maximumPoints: 10
            ))
        }

        if let heartRateVariability = sleep.vitals.heartRateVariability, heartRateVariability > 0 {
            categoryScores.append(Self.category(
                kind: .pressure,
                progress: Self.targetProgress(value: heartRateVariability, target: 80),
                maximumPoints: 15,
                valueDescription: "\(Int(heartRateVariability.rounded())) ms"
            ))
        }

        if let vitalsCategory = Self.vitalsCategory(vitals: sleep.vitals) {
            categoryScores.append(vitalsCategory)
        }

        if let temperatureCategory = Self.temperatureCategory(vitals: sleep.vitals) {
            categoryScores.append(temperatureCategory)
        }

        categories = categoryScores
        let availablePoints = categoryScores.reduce(0) { $0 + $1.maximumPoints }
        guard availablePoints > 0 else {
            return nil
        }
        let earnedPoints = categoryScores.reduce(0) { $0 + $1.points }
        total = min(max(Int((Double(earnedPoints) / Double(availablePoints) * 100).rounded()), 0), 100)
    }

    func category(for kind: SleepScoreCategory.Kind) -> SleepScoreCategory? {
        categories.first { $0.kind == kind }
    }

    var comment: String {
        Self.comment(for: total)
    }

    static func comment(for total: Int) -> String {
        switch total {
        case 90...:
            return "Excellent sleep recovery for this day."
        case 80..<90:
            return "Strong sleep with small room to improve."
        case 70..<80:
            return "Decent sleep, but key areas can improve."
        case 60..<70:
            return "Mixed sleep signals for this day."
        default:
            return "Low sleep score; prioritize recovery tonight."
        }
    }

    private static func category(
        kind: SleepScoreCategory.Kind,
        progress: Double,
        maximumPoints: Int,
        valueDescription: String? = nil
    ) -> SleepScoreCategory {
        let clampedProgress = min(max(progress, 0), 1)
        return SleepScoreCategory(
            kind: kind,
            points: Int((clampedProgress * Double(maximumPoints)).rounded()),
            maximumPoints: maximumPoints,
            progress: clampedProgress,
            valueDescription: valueDescription
        )
    }

    private static func continuityCategory(sleep: SleepSummary) -> SleepScoreCategory? {
        guard let interval = sleep.stageSnapshot.dateInterval else {
            return nil
        }

        let inSleepWindowDuration = max(interval.duration, sleep.duration ?? 0)
        guard inSleepWindowDuration > 0 else {
            return nil
        }

        let awakeDuration = sleep.stageSnapshot.awakeDuration
        let sleepEfficiency = min(max(1 - (awakeDuration / inSleepWindowDuration), 0), 1)
        let progress = min(max((sleepEfficiency - 0.78) / 0.18, 0), 1)
        return category(
            kind: .continuity,
            progress: progress,
            maximumPoints: 20,
            valueDescription: "\(Int((sleepEfficiency * 100).rounded()))%"
        )
    }

    private static func stagePercentageCategory(
        kind: SleepScoreCategory.Kind,
        stageDuration: TimeInterval,
        sleepDuration: TimeInterval,
        targetPercentage: Double,
        maximumPoints: Int
    ) -> SleepScoreCategory {
        let percentage = sleepDuration > 0 ? stageDuration / sleepDuration : 0
        return category(
            kind: kind,
            progress: Self.targetProgress(value: percentage, target: targetPercentage),
            maximumPoints: maximumPoints,
            valueDescription: "\(Int((percentage * 100).rounded()))%"
        )
    }

    private static func vitalsCategory(vitals: SleepVitalsSummary) -> SleepScoreCategory? {
        var progressValues: [Double] = []

        if let heartRate = vitals.heartRate {
            progressValues.append(Self.rangeProgress(value: heartRate, lowerBound: 45, upperBound: 65, tolerance: 20))
        }

        if let respiratoryRate = vitals.respiratoryRate {
            progressValues.append(Self.rangeProgress(value: respiratoryRate, lowerBound: 12, upperBound: 20, tolerance: 6))
        }

        if let oxygenSaturation = vitals.oxygenSaturation {
            progressValues.append(Self.increasingRangeProgress(value: oxygenSaturation, lowerBound: 90, target: 95))
        }

        guard !progressValues.isEmpty else {
            return nil
        }

        return category(
            kind: .vitals,
            progress: progressValues.reduce(0, +) / Double(progressValues.count),
            maximumPoints: 10
        )
    }

    private static func temperatureCategory(vitals: SleepVitalsSummary) -> SleepScoreCategory? {
        guard let wristTemperatureCelsius = vitals.wristTemperatureCelsius else {
            return nil
        }

        return category(
            kind: .temperature,
            progress: Self.rangeProgress(value: wristTemperatureCelsius, lowerBound: 35.8, upperBound: 37.2, tolerance: 0.8),
            maximumPoints: 5,
            valueDescription: "\(BodyValueFormat.numberText(wristTemperatureCelsius, decimals: 1))C"
        )
    }

    private static func durationProgress(_ duration: TimeInterval) -> Double {
        let hours = duration / 3_600

        if hours <= 8 {
            return min(max((hours - 5) / 3, 0), 1)
        }

        if hours <= 9 {
            return min(max(1 - ((hours - 8) * 0.1), 0), 1)
        }

        return min(max(0.9 - ((hours - 9) / 3 * 0.5), 0.4), 1)
    }

    private static func targetProgress(value: Double, target: Double) -> Double {
        guard value.isFinite, target > 0 else {
            return 0
        }

        return min(max(value / target, 0), 1)
    }

    private static func increasingRangeProgress(value: Double, lowerBound: Double, target: Double) -> Double {
        guard value.isFinite, target > lowerBound else {
            return 0
        }

        return min(max((value - lowerBound) / (target - lowerBound), 0), 1)
    }

    private static func rangeProgress(
        value: Double,
        lowerBound: Double,
        upperBound: Double,
        tolerance: Double
    ) -> Double {
        guard value.isFinite, lowerBound <= upperBound, tolerance > 0 else {
            return 0
        }

        if (lowerBound...upperBound).contains(value) {
            return 1
        }

        if value < lowerBound {
            return min(max(1 - ((lowerBound - value) / tolerance), 0), 1)
        }

        return min(max(1 - ((value - upperBound) / tolerance), 0), 1)
    }
}

struct SleepScoreCategory: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case duration
        case continuity
        case rem
        case deep
        case pressure
        case vitals
        case temperature

        var displayName: String {
            switch self {
            case .duration:
                return "Amount"
            case .continuity:
                return "Continuity"
            case .rem:
                return "REM"
            case .deep:
                return "Deep"
            case .pressure:
                return "Pressure"
            case .vitals:
                return "Vitals"
            case .temperature:
                return "Temperature"
            }
        }
    }

    let kind: Kind
    let points: Int
    let maximumPoints: Int
    let progress: Double
    let valueDescription: String?

    var id: Kind {
        kind
    }
}

struct SleepStageSegment: Codable, Equatable, Identifiable {
    var stage: SleepStage
    var startDate: Date
    var endDate: Date

    var id: String {
        "\(stage.rawValue)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)"
    }
}

enum SleepStage: String, CaseIterable, Codable, Equatable, Identifiable {
    case awake
    case rem
    case core
    case deep

    static let sleepStages: [SleepStage] = [.rem, .core, .deep]

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .awake:
            return "Awake"
        case .rem:
            return "REM"
        case .core:
            return "Core"
        case .deep:
            return "Deep"
        }
    }

    var chartPosition: Double {
        switch self {
        case .awake:
            return 4
        case .rem:
            return 3
        case .core:
            return 2
        case .deep:
            return 1
        }
    }

    static func stage(at position: Double) -> SleepStage? {
        allCases.first { $0.chartPosition == position }
    }
}

struct HealthMetricSummary: Codable, Equatable {
    var value: Double?
}

struct HealthDashboardSnapshot: Codable, Equatable {
    var summary: HealthSummarySnapshot
    var trends: HealthTrendSnapshot
    var activityRingHistory: ActivityRingHistorySnapshot

    init(
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        activityRingHistory: ActivityRingHistorySnapshot = .empty
    ) {
        self.summary = summary
        self.trends = trends
        self.activityRingHistory = activityRingHistory
    }

    static let empty = HealthDashboardSnapshot(
        summary: .empty,
        trends: .empty,
        activityRingHistory: .empty
    )

    private enum CodingKeys: String, CodingKey {
        case summary
        case trends
        case activityRingHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(HealthSummarySnapshot.self, forKey: .summary)
        trends = try container.decode(HealthTrendSnapshot.self, forKey: .trends)
        activityRingHistory = try container.decodeIfPresent(
            ActivityRingHistorySnapshot.self,
            forKey: .activityRingHistory
        ) ?? .empty
    }

    func filtered(by selection: BodyHealthPermissionSelection) -> HealthDashboardSnapshot {
        HealthDashboardSnapshot(
            summary: summary.filtered(by: selection),
            trends: trends.filtered(by: selection),
            activityRingHistory: selection.includes(.activityRings) ? activityRingHistory : .empty
        )
    }
}

enum HealthDashboardSnapshotStore {
    static let healthDashboardSnapshotKey = "lastHealthDashboardSnapshot"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "HealthDashboardSnapshotStore")

    static func save(_ snapshot: HealthDashboardSnapshot, defaults: UserDefaults = .standard) {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            logger.error("Health dashboard snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        defaults.set(data, forKey: healthDashboardSnapshotKey)
    }

    static func load(defaults: UserDefaults = .standard) -> HealthDashboardSnapshot? {
        guard let data = defaults.data(forKey: healthDashboardSnapshotKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(HealthDashboardSnapshot.self, from: data)
        } catch {
            logger.error("Health dashboard snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func loadOrEmpty(defaults: UserDefaults = .standard) -> HealthDashboardSnapshot {
        load(defaults: defaults) ?? .empty
    }
}

struct HealthTrendSnapshot: Codable, Equatable {
    var sleep: HealthTrendSeries
    var restingHeartRate: HealthTrendSeries
    var bodyMass: HealthTrendSeries
    var bodyFatPercentage: HealthTrendSeries
    var heartRateVariability: HealthTrendSeries
    var respiratoryRate: HealthTrendSeries
    var oxygenSaturation: HealthTrendSeries
    var bodyMassIndex: HealthTrendSeries
    var activeEnergy: HealthTrendSeries
    var restingEnergy: HealthTrendSeries
    var exerciseMinutes: HealthTrendSeries
    var wristTemperature: HealthTrendSeries
    var timeInDaylight: HealthTrendSeries
    var steps: HealthTrendSeries
    var sleepHistory: SleepHistorySnapshot
    var restingHeartRateDaySamples: HealthTrendSeries
    var heartRateVariabilityDaySamples: HealthTrendSeries
    var respiratoryRateDaySamples: HealthTrendSeries
    var oxygenSaturationDaySamples: HealthTrendSeries

    static let empty = HealthTrendSnapshot(
        sleep: .empty,
        restingHeartRate: .empty,
        bodyMass: .empty,
        bodyFatPercentage: .empty,
        heartRateVariability: .empty,
        respiratoryRate: .empty,
        oxygenSaturation: .empty,
        bodyMassIndex: .empty,
        activeEnergy: .empty,
        restingEnergy: .empty,
        exerciseMinutes: .empty,
        wristTemperature: .empty,
        timeInDaylight: .empty,
        steps: .empty,
        sleepHistory: .empty,
        restingHeartRateDaySamples: .empty,
        heartRateVariabilityDaySamples: .empty,
        respiratoryRateDaySamples: .empty,
        oxygenSaturationDaySamples: .empty
    )

    init(
        sleep: HealthTrendSeries,
        restingHeartRate: HealthTrendSeries,
        bodyMass: HealthTrendSeries,
        bodyFatPercentage: HealthTrendSeries,
        heartRateVariability: HealthTrendSeries,
        respiratoryRate: HealthTrendSeries,
        oxygenSaturation: HealthTrendSeries,
        bodyMassIndex: HealthTrendSeries,
        activeEnergy: HealthTrendSeries,
        restingEnergy: HealthTrendSeries,
        exerciseMinutes: HealthTrendSeries = .empty,
        wristTemperature: HealthTrendSeries = .empty,
        timeInDaylight: HealthTrendSeries = .empty,
        steps: HealthTrendSeries = .empty,
        sleepHistory: SleepHistorySnapshot = .empty,
        restingHeartRateDaySamples: HealthTrendSeries = .empty,
        heartRateVariabilityDaySamples: HealthTrendSeries = .empty,
        respiratoryRateDaySamples: HealthTrendSeries = .empty,
        oxygenSaturationDaySamples: HealthTrendSeries = .empty
    ) {
        self.sleep = sleep
        self.restingHeartRate = restingHeartRate
        self.bodyMass = bodyMass
        self.bodyFatPercentage = bodyFatPercentage
        self.heartRateVariability = heartRateVariability
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.bodyMassIndex = bodyMassIndex
        self.activeEnergy = activeEnergy
        self.restingEnergy = restingEnergy
        self.exerciseMinutes = exerciseMinutes
        self.wristTemperature = wristTemperature
        self.timeInDaylight = timeInDaylight
        self.steps = steps
        self.sleepHistory = sleepHistory
        self.restingHeartRateDaySamples = restingHeartRateDaySamples
        self.heartRateVariabilityDaySamples = heartRateVariabilityDaySamples
        self.respiratoryRateDaySamples = respiratoryRateDaySamples
        self.oxygenSaturationDaySamples = oxygenSaturationDaySamples
    }

    private enum CodingKeys: String, CodingKey {
        case sleep
        case restingHeartRate
        case bodyMass
        case bodyFatPercentage
        case heartRateVariability
        case respiratoryRate
        case oxygenSaturation
        case bodyMassIndex
        case activeEnergy
        case restingEnergy
        case exerciseMinutes
        case wristTemperature
        case timeInDaylight
        case steps
        case sleepHistory
        case restingHeartRateDaySamples
        case heartRateVariabilityDaySamples
        case respiratoryRateDaySamples
        case oxygenSaturationDaySamples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sleep = try container.decode(HealthTrendSeries.self, forKey: .sleep)
        restingHeartRate = try container.decode(HealthTrendSeries.self, forKey: .restingHeartRate)
        bodyMass = try container.decode(HealthTrendSeries.self, forKey: .bodyMass)
        bodyFatPercentage = try container.decode(HealthTrendSeries.self, forKey: .bodyFatPercentage)
        heartRateVariability = try container.decode(HealthTrendSeries.self, forKey: .heartRateVariability)
        respiratoryRate = try container.decode(HealthTrendSeries.self, forKey: .respiratoryRate)
        oxygenSaturation = try container.decode(HealthTrendSeries.self, forKey: .oxygenSaturation)
        bodyMassIndex = try container.decode(HealthTrendSeries.self, forKey: .bodyMassIndex)
        activeEnergy = try container.decode(HealthTrendSeries.self, forKey: .activeEnergy)
        restingEnergy = try container.decode(HealthTrendSeries.self, forKey: .restingEnergy)
        exerciseMinutes = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .exerciseMinutes) ?? .empty
        wristTemperature = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .wristTemperature) ?? .empty
        timeInDaylight = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .timeInDaylight) ?? .empty
        steps = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .steps) ?? .empty
        sleepHistory = try container.decodeIfPresent(SleepHistorySnapshot.self, forKey: .sleepHistory) ?? .empty
        restingHeartRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingHeartRateDaySamples
        ) ?? .empty
        heartRateVariabilityDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateVariabilityDaySamples
        ) ?? .empty
        respiratoryRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .respiratoryRateDaySamples
        ) ?? .empty
        oxygenSaturationDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .oxygenSaturationDaySamples
        ) ?? .empty
    }

    func series(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .sleep:
            return sleep
        case .basics:
            return .empty
        case .restingHeartRate:
            return restingHeartRate
        case .bodyMass:
            return bodyMass
        case .bodyFatPercentage:
            return bodyFatPercentage
        case .heartRateVariability:
            return heartRateVariability
        case .respiratoryRate:
            return respiratoryRate
        case .oxygenSaturation:
            return oxygenSaturation
        case .bodyMassIndex:
            return bodyMassIndex
        case .activeEnergy:
            return activeEnergy
        case .restingEnergy:
            return restingEnergy
        case .exerciseMinutes:
            return exerciseMinutes
        case .wristTemperature:
            return wristTemperature
        case .timeInDaylight:
            return timeInDaylight
        case .steps:
            return steps
        }
    }

    func daySeries(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .restingHeartRate:
            return restingHeartRateDaySamples
        case .heartRateVariability:
            return heartRateVariabilityDaySamples
        case .respiratoryRate:
            return respiratoryRateDaySamples
        case .oxygenSaturation:
            return oxygenSaturationDaySamples
        case .sleep,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .wristTemperature,
             .timeInDaylight,
             .steps:
            return .empty
        }
    }

    func filtered(by selection: BodyHealthPermissionSelection) -> HealthTrendSnapshot {
        var filtered = self

        if !selection.includes(.sleep) {
            filtered.sleep = .empty
            filtered.sleepHistory = .empty
        }
        if !selection.includes(.heart) {
            filtered.restingHeartRate = .empty
            filtered.heartRateVariability = .empty
            filtered.restingHeartRateDaySamples = .empty
            filtered.heartRateVariabilityDaySamples = .empty
        }
        if !selection.includes(.basics) {
            filtered.bodyMass = .empty
            filtered.bodyFatPercentage = .empty
            filtered.bodyMassIndex = .empty
        }
        if !selection.includes(.bloodOxygen) {
            filtered.oxygenSaturation = .empty
            filtered.oxygenSaturationDaySamples = .empty
        }
        if !selection.includes(.respiratory) {
            filtered.respiratoryRate = .empty
            filtered.respiratoryRateDaySamples = .empty
        }
        if !selection.includes(.energy) {
            filtered.activeEnergy = .empty
            filtered.restingEnergy = .empty
        }
        if !selection.includes(.exerciseMinutes) {
            filtered.exerciseMinutes = .empty
        }
        if !selection.includes(.wristTemperature) {
            filtered.wristTemperature = .empty
        }
        if !selection.includes(.timeInDaylight) {
            filtered.timeInDaylight = .empty
        }
        if !selection.includes(.steps) {
            filtered.steps = .empty
        }

        return filtered
    }
}

struct BasicsTrendSummary: Equatable {
    var weight: HealthTrendSeries
    var bodyFat: HealthTrendSeries
    var bodyMassIndex: HealthTrendSeries

    var isEmpty: Bool {
        weight.isEmpty && bodyFat.isEmpty && bodyMassIndex.isEmpty
    }

    static let empty = BasicsTrendSummary(weight: .empty, bodyFat: .empty, bodyMassIndex: .empty)

    var weightHalfSpread: Double? {
        halfSpread(for: weight)
    }

    var bodyFatHalfSpread: Double? {
        halfSpread(for: bodyFat)
    }

    var bodyMassIndexHalfSpread: Double? {
        halfSpread(for: bodyMassIndex)
    }

    var weightAverage: Double? {
        weight.averageValue
    }

    var bodyFatAverage: Double? {
        bodyFat.averageValue
    }

    private func halfSpread(for series: HealthTrendSeries) -> Double? {
        let values = series.points.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return nil
        }

        return (maximum - minimum) / 2
    }

    func limited(to range: BodyHealthTrendRange, calendar: Calendar = .bodyGregorian, date: Date = Date()) -> BasicsTrendSummary {
        BasicsTrendSummary(
            weight: weight.limited(to: range, calendar: calendar, date: date),
            bodyFat: bodyFat.limited(to: range, calendar: calendar, date: date),
            bodyMassIndex: bodyMassIndex.limited(to: range, calendar: calendar, date: date)
        )
    }

    func nearestDate(to date: Date) -> Date? {
        let dates = weight.points.map(\.date) + bodyFat.points.map(\.date)
        return dates.min { first, second in
            abs(first.timeIntervalSince(date)) < abs(second.timeIntervalSince(date))
        }
    }

    func selectionDate(for selectedDate: Date?) -> Date? {
        guard let selectedDate else {
            return nil
        }

        return nearestDate(to: selectedDate)
    }
}

struct HealthTrendSeries: Codable, Equatable {
    var points: [HealthTrendDataPoint]

    var isEmpty: Bool {
        points.isEmpty
    }

    var averageValue: Double? {
        let finiteValues = points.map(\.value).filter(\.isFinite)
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }

    static let empty = HealthTrendSeries(points: [])

    func mapValues(_ transform: (Double) -> Double) -> HealthTrendSeries {
        HealthTrendSeries(
            points: points.map {
                HealthTrendDataPoint(date: $0.date, value: transform($0.value))
            }
        )
    }

    func limited(to range: BodyHealthTrendRange, calendar: Calendar = .bodyGregorian, date: Date = Date()) -> HealthTrendSeries {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        return HealthTrendSeries(
            points: points.filter { point in
                point.date >= startDate && point.date < endDate
            }
        )
    }

    func calendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let pointsByDay = Dictionary(grouping: points.filter { point in
            point.date >= startDate && point.date < endDate
        }) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<range.dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            let value = pointsByDay[day]?
                .sorted { $0.date < $1.date }
                .last?
                .value
            return HealthTrendCalendarPoint(
                date: day,
                value: value?.isFinite == true ? value : nil
            )
        }
    }

    func chartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        let dailyPoints = calendarPoints(to: range, calendar: calendar, date: date)
        let aggregationDayCount = range.chartAggregationDayCount
        guard aggregationDayCount > 1 else {
            return dailyPoints
        }

        return stride(from: 0, to: dailyPoints.count, by: aggregationDayCount).compactMap { startIndex in
            let endIndex = min(startIndex + aggregationDayCount, dailyPoints.count)
            let bucket = dailyPoints[startIndex..<endIndex]
            guard let bucketStartDate = bucket.first?.date,
                  let bucketEndDate = bucket.last?.date else {
                return nil
            }

            let finiteValues = bucket.compactMap(\.value).filter(\.isFinite)
            let averageValue = finiteValues.isEmpty
                ? nil
                : finiteValues.reduce(0, +) / Double(finiteValues.count)
            return HealthTrendCalendarPoint(
                date: bucketEndDate,
                value: averageValue,
                startDate: bucketStartDate,
                endDate: bucketEndDate
            )
        }
    }

    func chartSeries(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> HealthTrendSeries {
        HealthTrendSeries(
            points: chartCalendarPoints(to: range, calendar: calendar, date: date).compactMap { point in
                guard let value = point.value, value.isFinite else {
                    return nil
                }

                return HealthTrendDataPoint(date: point.date, value: value)
            }
        )
    }

    func nearestPoint(to date: Date) -> HealthTrendDataPoint? {
        points.min { first, second in
            abs(first.date.timeIntervalSince(date)) < abs(second.date.timeIntervalSince(date))
        }
    }

    func selectionPoint(for selectedDate: Date?) -> HealthTrendDataPoint? {
        guard let selectedDate else {
            return nil
        }

        return nearestPoint(to: selectedDate)
    }

    func point(on date: Date) -> HealthTrendDataPoint? {
        points.first { $0.date == date }
    }

    func points(on date: Date, calendar: Calendar = .bodyGregorian) -> HealthTrendSeries {
        let dayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)

        return HealthTrendSeries(
            points: points
                .filter { point in
                    point.date >= dayStart && point.date < nextDayStart
                }
                .sorted { $0.date < $1.date }
        )
    }

    func hourlyAverageBuckets(on date: Date, calendar: Calendar = .bodyGregorian) -> [HealthTrendHourlyBucket] {
        let dayPoints = points(on: date, calendar: calendar).points.filter { $0.value.isFinite }
        let pointsByHour = Dictionary(grouping: dayPoints) { point in
            calendar.dateInterval(of: .hour, for: point.date)?.start ?? point.date
        }

        return pointsByHour.compactMap { hourStart, samples -> HealthTrendHourlyBucket? in
            let sortedSamples = samples.sorted { $0.date < $1.date }
            guard !sortedSamples.isEmpty else {
                return nil
            }

            let averageValue = sortedSamples.reduce(0) { $0 + $1.value } / Double(sortedSamples.count)
            return HealthTrendHourlyBucket(
                hourStart: hourStart,
                averageValue: averageValue,
                samples: sortedSamples
            )
        }
        .sorted { $0.hourStart < $1.hourStart }
    }
}

struct HealthTrendDataPoint: Codable, Equatable, Identifiable {
    var date: Date
    var value: Double

    var id: Date {
        date
    }
}

struct HealthTrendCalendarPoint: Equatable, Identifiable {
    var date: Date
    var value: Double?
    var startDate: Date
    var endDate: Date

    init(date: Date, value: Double?, startDate: Date? = nil, endDate: Date? = nil) {
        self.date = date
        self.value = value
        self.startDate = startDate ?? date
        self.endDate = endDate ?? date
    }

    var id: Date {
        date
    }

    var hasValue: Bool {
        value != nil
    }

    var representsDateRange: Bool {
        startDate != endDate
    }
}

struct HealthTrendHourlyBucket: Equatable, Identifiable {
    var hourStart: Date
    var averageValue: Double
    var samples: [HealthTrendDataPoint]

    var id: Date {
        hourStart
    }

    var plotDate: Date {
        hourStart.addingTimeInterval(30 * 60)
    }
}
