//
//  HealthWidgetSnapshot.swift
//  Body
//
//  Self-contained snapshot shared between the app and the widget extension.
//  Lives in BodyShared so it compiles into both targets; it must not reference
//  any Body-target-only types (HealthDashboardSnapshot, HealthTrendSnapshot,
//  SleepStageSnapshot, etc.). The app converts its richer types into these
//  slim types (see HealthWidgetSnapshotBuilder) and writes them to the App
//  Group container; the widgets read them back.
//

import SwiftUI

// MARK: - Metric

/// The metrics that can be charted in the trend widget. Mirrors the home
/// screen trend cards so the widget stays visually consistent with the app.
enum HealthWidgetMetric: String, Codable, CaseIterable, Identifiable {
    case readiness
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case sleep
    case wristTemperature
    case steps
    case activeEnergy
    case restingEnergy
    case exerciseMinutes
    case trainingLoad
    case timeInDaylight
    case bodyMass
    case bodyFatPercentage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readiness: return "Readiness"
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .heartRateVariability: return "HRV"
        case .respiratoryRate: return "Respiratory Rate"
        case .oxygenSaturation: return "Blood Oxygen"
        case .sleep: return "Sleep"
        case .wristTemperature: return "Skin Temperature"
        case .steps: return "Steps"
        case .activeEnergy: return "Active Energy"
        case .restingEnergy: return "Resting Energy"
        case .exerciseMinutes: return "Exercise Minutes"
        case .trainingLoad: return "Training Load"
        case .timeInDaylight: return "Time In Daylight"
        case .bodyMass: return "Weight"
        case .bodyFatPercentage: return "Body Fat"
        }
    }

    var symbolName: String {
        switch self {
        case .readiness: return "bolt.heart.fill"
        case .heartRate, .restingHeartRate: return "heart.fill"
        case .heartRateVariability: return "waveform.path.ecg"
        case .respiratoryRate: return "lungs.fill"
        case .oxygenSaturation: return "drop.fill"
        case .sleep: return "bed.double.fill"
        case .wristTemperature: return "thermometer.medium"
        case .steps: return "figure.walk"
        case .activeEnergy: return "flame.fill"
        case .restingEnergy: return "leaf.fill"
        case .exerciseMinutes: return "figure.run"
        case .trainingLoad: return "figure.strengthtraining.traditional"
        case .timeInDaylight: return "sun.max.fill"
        case .bodyMass: return "scalemass.fill"
        case .bodyFatPercentage: return "percent"
        }
    }

    var tintColor: Color {
        switch self {
        case .readiness: return Color(red: 0.12, green: 0.68, blue: 0.55)
        case .heartRate, .restingHeartRate, .heartRateVariability:
            return Color(red: 1.00, green: 0.25, blue: 0.45)
        case .respiratoryRate, .oxygenSaturation, .wristTemperature:
            return Color(red: 0.00, green: 0.75, blue: 0.85)
        case .sleep: return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .steps, .activeEnergy, .exerciseMinutes, .trainingLoad:
            return Color(red: 1.00, green: 0.38, blue: 0.12)
        case .restingEnergy: return Color(red: 0.14, green: 0.72, blue: 0.42)
        case .timeInDaylight: return Color(red: 0.10, green: 0.58, blue: 1.00)
        case .bodyMass: return Color(red: 0.50, green: 0.34, blue: 1.00)
        case .bodyFatPercentage: return Color(red: 1.00, green: 0.68, blue: 0.08)
        }
    }

    var chartStyle: HealthWidgetChartStyle {
        switch self {
        case .steps, .activeEnergy, .restingEnergy, .exerciseMinutes, .timeInDaylight:
            return .bar
        case .readiness, .heartRate, .restingHeartRate, .heartRateVariability,
             .respiratoryRate, .oxygenSaturation, .sleep, .wristTemperature, .trainingLoad,
             .bodyMass, .bodyFatPercentage:
            return .line
        }
    }
}

enum HealthWidgetChartStyle: String, Codable {
    case line
    case bar
}

/// The ranges the trend widget can display. Matches the app's "Week" / "Month".
enum HealthWidgetTrendRange: String, Codable, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    var chartTitle: String {
        switch self {
        case .week: return "Last 7 Days"
        case .month: return "Last 30 Days"
        }
    }
}

// MARK: - Trend data

/// A single charted point. `value` is optional so gaps (days without data) are
/// preserved for the line/bar plot.
struct HealthWidgetPoint: Codable, Equatable, Identifiable {
    var date: Date
    var value: Double?

    var id: Date { date }
}

struct HealthWidgetTrendSeries: Codable, Equatable {
    var points: [HealthWidgetPoint]
    /// Pre-formatted average over the range (computed app-side where unit
    /// preferences are available), e.g. "62 BPM" or "7h 12m".
    var averageText: String?
    /// Pre-formatted most-recent (today/now) value in the range, e.g. "64 BPM".
    var latestText: String?

    init(points: [HealthWidgetPoint], averageText: String? = nil, latestText: String? = nil) {
        self.points = points
        self.averageText = averageText
        self.latestText = latestText
    }

    var isEmpty: Bool {
        points.allSatisfy { $0.value == nil }
    }

    /// Numeric average over the range, used to position the reference line.
    /// Matches the value `averageText` formats.
    var average: Double? {
        let values = points.compactMap(\.value).filter(\.isFinite)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The most recent finite value in the range. Matches `latestText`.
    var latest: Double? {
        points.reversed().compactMap(\.value).first { $0.isFinite }
    }

    static let empty = HealthWidgetTrendSeries(points: [])
}

/// A single value + unit shown on a metric preview card, e.g. "62"/"bpm" or
/// "85"/"PTS". Most metrics have one; Sleep and Skin Temp have two (matching
/// the app's prominent cards).
struct HealthWidgetDisplayValue: Codable, Equatable {
    var value: String
    var unit: String
}

struct HealthWidgetMetricTrend: Codable, Equatable, Identifiable {
    var metric: HealthWidgetMetric
    var primarySourceName: String?
    var week: HealthWidgetTrendSeries
    var month: HealthWidgetTrendSeries
    /// The value(s) shown on the home preview card (from the latest summary
    /// reading), pre-formatted. One element for most metrics; two for the
    /// prominent Sleep (score + duration) and Skin Temp (deviation + actual)
    /// cards. Used by the small metric widget.
    var displayValues: [HealthWidgetDisplayValue]

    private enum CodingKeys: String, CodingKey {
        case metric
        case primarySourceName
        case week
        case month
        case displayValues
    }

    var id: String { metric.rawValue }

    func series(for range: HealthWidgetTrendRange) -> HealthWidgetTrendSeries {
        switch range {
        case .week: return week
        case .month: return month
        }
    }

    var hasAnyData: Bool {
        !week.isEmpty || !month.isEmpty
    }
}

extension HealthWidgetMetricTrend {
    /// Tolerant decoder for snapshots written by older builds. Previously
    /// `week`/`month` were `{ primary, secondary }` range trends and
    /// `displayValues` did not exist; accepting that shape keeps an existing
    /// on-disk cache from failing to decode (which would blank the widget until
    /// the app rewrites it). The `displayValues` default also lets a freshly
    /// updated widget extension read a snapshot the app hasn't refreshed yet.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            metric: try container.decode(HealthWidgetMetric.self, forKey: .metric),
            primarySourceName: try container.decodeIfPresent(String.self, forKey: .primarySourceName),
            week: Self.decodeSeries(from: container, forKey: .week),
            month: Self.decodeSeries(from: container, forKey: .month),
            displayValues: (try? container.decode([HealthWidgetDisplayValue].self, forKey: .displayValues)) ?? []
        )
    }

    private static func decodeSeries(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> HealthWidgetTrendSeries {
        if let series = try? container.decode(HealthWidgetTrendSeries.self, forKey: key) {
            return series
        }
        // Legacy `{ primary, secondary }` range-trend shape: keep the primary.
        if let legacy = try? container.decode(LegacyRangeTrend.self, forKey: key) {
            return legacy.primary
        }
        return .empty
    }

    private struct LegacyRangeTrend: Decodable {
        var primary: HealthWidgetTrendSeries
    }
}

// MARK: - Sleep stages

enum HealthWidgetSleepStage: String, Codable, CaseIterable, Identifiable {
    case awake
    case rem
    case core
    case deep

    var id: String { rawValue }

    /// Stages that count as "asleep" (used for totals).
    static let sleepStages: [HealthWidgetSleepStage] = [.rem, .core, .deep]

    var displayName: String {
        switch self {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Core"
        case .deep: return "Deep"
        }
    }

    /// Vertical position in the hypnogram (Deep lowest → Awake highest).
    var chartPosition: Double {
        switch self {
        case .awake: return 4
        case .rem: return 3
        case .core: return 2
        case .deep: return 1
        }
    }

    var color: Color {
        switch self {
        case .awake: return Color(red: 1.00, green: 0.31, blue: 0.22)
        case .rem: return Color(red: 0.42, green: 0.80, blue: 1.00)
        case .core: return Color(red: 0.24, green: 0.56, blue: 1.00)
        case .deep: return Color(red: 0.25, green: 0.25, blue: 0.82)
        }
    }
}

struct HealthWidgetSleepSegment: Codable, Equatable, Identifiable {
    var stage: HealthWidgetSleepStage
    var startDate: Date
    var endDate: Date

    var id: String {
        "\(stage.rawValue)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)"
    }

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }
}

struct HealthWidgetSleepStages: Codable, Equatable {
    /// The night the stages belong to (start of the relevant day).
    var night: Date?
    var sourceName: String?
    var segments: [HealthWidgetSleepSegment]

    var isEmpty: Bool {
        segments.isEmpty
    }

    func duration(for stage: HealthWidgetSleepStage) -> TimeInterval {
        segments
            .filter { $0.stage == stage }
            .reduce(0) { $0 + $1.duration }
    }

    var asleepDuration: TimeInterval {
        HealthWidgetSleepStage.sleepStages.reduce(0) { $0 + duration(for: $1) }
    }

    /// True when REM/Deep are present (Apple Watch style detailed staging).
    var hasDetailedStages: Bool {
        segments.contains { $0.stage == .rem || $0.stage == .deep }
    }

    static let empty = HealthWidgetSleepStages(night: nil, sourceName: nil, segments: [])
}

// MARK: - Snapshot

struct HealthWidgetSnapshot: Codable, Equatable {
    var generatedDate: Date
    var metricTrends: [HealthWidgetMetricTrend]
    var sleep: HealthWidgetSleepStages

    init(
        generatedDate: Date = Date(),
        metricTrends: [HealthWidgetMetricTrend] = [],
        sleep: HealthWidgetSleepStages = .empty
    ) {
        self.generatedDate = generatedDate
        self.metricTrends = metricTrends
        self.sleep = sleep
    }

    func trend(for metric: HealthWidgetMetric) -> HealthWidgetMetricTrend? {
        metricTrends.first { $0.metric == metric }
    }

    var isEmpty: Bool {
        metricTrends.allSatisfy { !$0.hasAnyData } && sleep.isEmpty
    }

    static let empty = HealthWidgetSnapshot()

    static let placeholder = HealthWidgetSnapshot(
        metricTrends: HealthWidgetMetric.allCases.map { HealthWidgetPlaceholder.metricTrend(for: $0) },
        sleep: HealthWidgetPlaceholder.sleepStages()
    )
}

// MARK: - Placeholder generation

private enum HealthWidgetPlaceholder {
    /// A plausible baseline + variation per metric so previews look realistic.
    static func metricTrend(for metric: HealthWidgetMetric) -> HealthWidgetMetricTrend {
        let (base, spread): (Double, Double) = {
            switch metric {
            case .readiness: return (80, 9)
            case .heartRate: return (78, 10)
            case .restingHeartRate: return (58, 4)
            case .heartRateVariability: return (52, 14)
            case .respiratoryRate: return (14, 2)
            case .oxygenSaturation: return (97, 2)
            case .sleep: return (7.4, 1.1)
            case .wristTemperature: return (36.4, 0.5)
            case .steps: return (9_500, 3_500)
            case .activeEnergy: return (520, 180)
            case .restingEnergy: return (1_680, 90)
            case .exerciseMinutes: return (44, 22)
            case .trainingLoad: return (1.05, 0.25)
            case .timeInDaylight: return (62, 30)
            case .bodyMass: return (70, 1.5)
            case .bodyFatPercentage: return (18, 2)
            }
        }()
        return metricTrend(for: metric, base: base, spread: spread)
    }

    static func metricTrend(
        for metric: HealthWidgetMetric,
        base: Double,
        spread: Double
    ) -> HealthWidgetMetricTrend {
        HealthWidgetMetricTrend(
            metric: metric,
            primarySourceName: nil,
            week: series(base: base, spread: spread, dayCount: 7),
            month: series(base: base, spread: spread, dayCount: 30),
            displayValues: [
                HealthWidgetDisplayValue(value: BodyValueFormat.numberText(base, decimals: 0), unit: "")
            ]
        )
    }

    private static func series(base: Double, spread: Double, dayCount: Int) -> HealthWidgetTrendSeries {
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        let points: [HealthWidgetPoint] = (0..<dayCount).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let wave = sin(Double(offset) / 2.4) * spread * 0.5
            return HealthWidgetPoint(date: date, value: base + wave)
        }
        var series = HealthWidgetTrendSeries(points: points, averageText: nil)
        series.averageText = series.average.map { BodyValueFormat.numberText($0, decimals: 0) }
        series.latestText = series.latest.map { BodyValueFormat.numberText($0, decimals: 0) }
        return series
    }

    static func sleepStages() -> HealthWidgetSleepStages {
        let calendar = Calendar.bodyGregorian
        let night = calendar.startOfDay(for: Date())
        var start = calendar.date(byAdding: .hour, value: -7, to: night) ?? night
        let pattern: [(HealthWidgetSleepStage, Int)] = [
            (.awake, 8), (.core, 42), (.deep, 38), (.core, 30), (.rem, 26),
            (.core, 44), (.deep, 22), (.core, 28), (.rem, 34), (.awake, 6),
            (.core, 36), (.rem, 30)
        ]
        var segments: [HealthWidgetSleepSegment] = []
        for (stage, minutes) in pattern {
            let end = start.addingTimeInterval(TimeInterval(minutes) * 60)
            segments.append(HealthWidgetSleepSegment(stage: stage, startDate: start, endDate: end))
            start = end
        }
        return HealthWidgetSleepStages(night: night, sourceName: nil, segments: segments)
    }
}
