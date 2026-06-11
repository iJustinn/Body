//
//  Sleep.swift
//  Body
//

import Foundation

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

    func summary(
        on date: Date,
        currentDaySummary: SleepSummary?,
        today: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> SleepSummary? {
        if let historicalSummary = summary(on: date, calendar: calendar)?.summary {
            return historicalSummary
        }

        guard calendar.isDate(date, inSameDayAs: today) else {
            return nil
        }

        return currentDaySummary
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

    var sleepStartDate: Date? {
        segments
            .filter { SleepStage.sleepStages.contains($0.stage) }
            .map(\.startDate)
            .min()
    }

    var hasDetailedStages: Bool {
        segments.contains { $0.stage == .rem || $0.stage == .deep }
    }

    static let empty = SleepStageSnapshot(date: nil, segments: [])
}

struct SleepScoreSummary: Equatable {
    let total: Int
    let categories: [SleepScoreCategory]

    init?(
        sleep: SleepSummary,
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration,
        recentSleepHistory: SleepHistorySnapshot = .empty,
        on date: Date? = nil,
        calendar: Calendar = .bodyGregorian
    ) {
        guard let duration = sleep.duration, duration > 0 else {
            return nil
        }

        var categoryScores = [
            Self.category(
                kind: .duration,
                progress: Self.durationProgress(duration, idealDuration: idealSleepDuration),
                maximumPoints: 25,
                valueDescription: BodyValueFormat.sleepDurationText(for: duration)
            )
        ]

        if let continuityCategory = Self.continuityCategory(sleep: sleep) {
            categoryScores.append(continuityCategory)
        }

        if let startTimeCategory = Self.startTimeCategory(
            sleep: sleep,
            recentSleepHistory: recentSleepHistory,
            on: date,
            calendar: calendar
        ) {
            categoryScores.append(startTimeCategory)
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
            return "Excellent sleep readiness for this day."
        case 80..<90:
            return "Strong sleep with small room to improve."
        case 70..<80:
            return "Decent sleep, but key areas can improve."
        case 60..<70:
            return "Mixed sleep signals for this day."
        default:
            return "Low sleep score; prioritize readiness tonight."
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

    private static func startTimeCategory(
        sleep: SleepSummary,
        recentSleepHistory: SleepHistorySnapshot,
        on date: Date?,
        calendar: Calendar
    ) -> SleepScoreCategory? {
        guard let sleepStartDate = sleep.stageSnapshot.sleepStartDate else {
            return nil
        }

        let scoringDate = date ?? sleep.stageSnapshot.date ?? sleepStartDate
        let scoringDay = calendar.startOfDay(for: scoringDate)
        let oldestBaselineDay = calendar.date(
            byAdding: .day,
            value: -Self.startTimeBaselineDayCount,
            to: scoringDay
        ) ?? scoringDay.addingTimeInterval(-TimeInterval(Self.startTimeBaselineDayCount) * Self.secondsPerDay)
        let baselineStartDates = recentSleepHistory.days.compactMap { day -> Date? in
            let dayDate = calendar.startOfDay(for: day.date)
            guard dayDate < scoringDay, dayDate >= oldestBaselineDay else {
                return nil
            }

            return day.summary.stageSnapshot.sleepStartDate
        }

        guard baselineStartDates.count >= Self.minimumStartTimeBaselineCount,
              let baselineSeconds = circularAverageSeconds(for: baselineStartDates, calendar: calendar) else {
            return nil
        }

        let sleepStartSeconds = secondsSinceStartOfDay(sleepStartDate, calendar: calendar)
        let deviation = circularDeviationSeconds(from: sleepStartSeconds, to: baselineSeconds)
        return category(
            kind: .startTime,
            progress: startTimeProgress(forDeviation: deviation),
            maximumPoints: 10,
            valueDescription: "\(BodyValueFormat.durationText(for: deviation)) off"
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

    private static func durationProgress(_ duration: TimeInterval, idealDuration: TimeInterval) -> Double {
        let hours = duration / 3_600
        let idealHours = max(idealDuration / 3_600, 1)

        if hours <= idealHours {
            return min(max((hours - (idealHours - 3)) / 3, 0), 1)
        }

        if hours <= idealHours + 1 {
            return min(max(1 - ((hours - idealHours) * 0.1), 0), 1)
        }

        return min(max(0.9 - ((hours - (idealHours + 1)) / 3 * 0.5), 0.4), 1)
    }

    private static func startTimeProgress(forDeviation deviation: TimeInterval) -> Double {
        if deviation <= Self.startTimeFullCreditDeviation {
            return 1
        }

        if deviation >= Self.startTimeNoCreditDeviation {
            return 0
        }

        return min(
            max(
                1 - ((deviation - Self.startTimeFullCreditDeviation) /
                    (Self.startTimeNoCreditDeviation - Self.startTimeFullCreditDeviation)),
                0
            ),
            1
        )
    }

    private static func circularAverageSeconds(for dates: [Date], calendar: Calendar) -> TimeInterval? {
        guard !dates.isEmpty else {
            return nil
        }

        let angles = dates.map {
            secondsSinceStartOfDay($0, calendar: calendar) / Self.secondsPerDay * 2 * Double.pi
        }
        let averageX = angles.reduce(0) { $0 + cos($1) } / Double(angles.count)
        let averageY = angles.reduce(0) { $0 + sin($1) } / Double(angles.count)
        guard averageX.isFinite, averageY.isFinite, abs(averageX) + abs(averageY) > 0.000001 else {
            return nil
        }

        let angle = atan2(averageY, averageX)
        let normalizedAngle = angle >= 0 ? angle : angle + 2 * Double.pi
        return normalizedAngle / (2 * Double.pi) * Self.secondsPerDay
    }

    private static func circularDeviationSeconds(from lhs: TimeInterval, to rhs: TimeInterval) -> TimeInterval {
        let absoluteDifference = abs(lhs - rhs)
        return min(absoluteDifference, Self.secondsPerDay - absoluteDifference)
    }

    private static func secondsSinceStartOfDay(_ date: Date, calendar: Calendar) -> TimeInterval {
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hourSeconds = TimeInterval(components.hour ?? 0) * 3_600
        let minuteSeconds = TimeInterval(components.minute ?? 0) * 60
        let secondValue = TimeInterval(components.second ?? 0)
        let nanosecondValue = TimeInterval(components.nanosecond ?? 0) / 1_000_000_000
        return min(max(hourSeconds + minuteSeconds + secondValue + nanosecondValue, 0), Self.secondsPerDay)
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

    private static let startTimeBaselineDayCount = 14
    private static let minimumStartTimeBaselineCount = 3
    private static let startTimeFullCreditDeviation: TimeInterval = 60 * 60
    private static let startTimeNoCreditDeviation: TimeInterval = 3 * 60 * 60
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60
}

struct SleepScoreCategory: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case duration
        case continuity
        case startTime
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
            case .startTime:
                return "Start Time"
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

struct SleepConsistencyNightSlice: Equatable, Identifiable {
    var stage: SleepStage
    var startOffsetHours: Double
    var endOffsetHours: Double

    var id: String {
        "\(stage.rawValue)-\(startOffsetHours)-\(endOffsetHours)"
    }
}

struct SleepConsistencyNight: Equatable, Identifiable {
    var day: Date
    var bedOffsetHours: Double
    var wakeOffsetHours: Double
    var slices: [SleepConsistencyNightSlice]

    var id: Date {
        day
    }
}

/// Day-by-day bed-to-wake bars positioned by time of day, with offsets
/// expressed in hours relative to each wake day's midnight (pre-midnight
/// bedtimes are negative). Offsets use elapsed time from midnight, so the
/// pre-midnight portion of a DST-change night can drift by up to an hour.
struct SleepConsistencyChartModel: Equatable {
    var days: [Date]
    var nights: [SleepConsistencyNight]
    var averageBedOffsetHours: Double?
    var averageWakeOffsetHours: Double?
    var yDomainHours: ClosedRange<Double>
    var gridHourOffsets: [Double]

    static let dayCount = 14

    static func make(
        entries: [(day: Date, snapshot: SleepStageSnapshot?)],
        calendar: Calendar = .bodyGregorian
    ) -> SleepConsistencyChartModel {
        let nights = entries.compactMap { entry -> SleepConsistencyNight? in
            guard let snapshot = entry.snapshot,
                  let interval = snapshot.dateInterval else {
                return nil
            }

            let dayStart = calendar.startOfDay(for: entry.day)
            let bedOffset = interval.start.timeIntervalSince(dayStart) / 3_600
            let wakeOffset = interval.end.timeIntervalSince(dayStart) / 3_600
            let slices = snapshot.segments
                .sorted { $0.startDate < $1.startDate }
                .compactMap { segment -> SleepConsistencyNightSlice? in
                    let start = max(segment.startDate.timeIntervalSince(dayStart) / 3_600, bedOffset)
                    let end = min(segment.endDate.timeIntervalSince(dayStart) / 3_600, wakeOffset)
                    guard end > start else {
                        return nil
                    }

                    return SleepConsistencyNightSlice(
                        stage: segment.stage,
                        startOffsetHours: start,
                        endOffsetHours: end
                    )
                }

            return SleepConsistencyNight(
                day: entry.day,
                bedOffsetHours: bedOffset,
                wakeOffsetHours: wakeOffset,
                slices: slices
            )
        }

        let bedOffsets = nights.map(\.bedOffsetHours)
        let wakeOffsets = nights.map(\.wakeOffsetHours)
        let averageBed = bedOffsets.isEmpty ? nil : bedOffsets.reduce(0, +) / Double(bedOffsets.count)
        let averageWake = wakeOffsets.isEmpty ? nil : wakeOffsets.reduce(0, +) / Double(wakeOffsets.count)

        let domain: ClosedRange<Double>
        if let minBed = bedOffsets.min(), let maxWake = wakeOffsets.max(), maxWake > minBed {
            domain = (minBed - domainPaddingHours)...(maxWake + domainPaddingHours)
        } else {
            domain = 0...1
        }

        return SleepConsistencyChartModel(
            days: entries.map { $0.day },
            nights: nights,
            averageBedOffsetHours: averageBed,
            averageWakeOffsetHours: averageWake,
            yDomainHours: domain,
            gridHourOffsets: gridHourOffsets(
                in: domain,
                suppressingNear: [averageBed, averageWake].compactMap { $0 }
            )
        )
    }

    static func clockDate(
        forOffsetHours offsetHours: Double,
        on day: Date,
        calendar: Calendar = .bodyGregorian
    ) -> Date? {
        let normalized = offsetHours.truncatingRemainder(dividingBy: 24)
        let positiveHours = normalized < 0 ? normalized + 24 : normalized
        let totalMinutes = Int((positiveHours * 60).rounded()) % (24 * 60)
        return calendar.date(
            byAdding: DateComponents(hour: totalMinutes / 60, minute: totalMinutes % 60),
            to: calendar.startOfDay(for: day)
        )
    }

    private static let domainPaddingHours = 0.5
    private static let gridStepHours = 2.0
    private static let gridSuppressionWindowHours = 0.6

    private static func gridHourOffsets(
        in domain: ClosedRange<Double>,
        suppressingNear averages: [Double]
    ) -> [Double] {
        guard domain.upperBound > domain.lowerBound else {
            return []
        }

        let first = (domain.lowerBound / gridStepHours).rounded(.up) * gridStepHours
        return stride(from: first, through: domain.upperBound, by: gridStepHours).filter { offset in
            averages.allSatisfy { abs(offset - $0) >= gridSuppressionWindowHours }
        }
    }
}
