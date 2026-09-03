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
        case .readiness: return String(localized: "Readiness", table: "BodyShared")
        case .heartRate: return String(localized: "Heart Rate", table: "BodyShared")
        case .restingHeartRate: return String(localized: "Resting Heart Rate", table: "BodyShared")
        case .heartRateVariability: return String(localized: "HRV", table: "BodyShared")
        case .respiratoryRate: return String(localized: "Respiratory Rate", table: "BodyShared")
        case .oxygenSaturation: return String(localized: "Blood Oxygen", table: "BodyShared")
        case .sleep: return String(localized: "Sleep", table: "BodyShared")
        case .wristTemperature: return String(localized: "Skin Temperature", table: "BodyShared")
        case .steps: return String(localized: "Steps", table: "BodyShared")
        case .activeEnergy: return String(localized: "Active Energy", table: "BodyShared")
        case .restingEnergy: return String(localized: "Resting Energy", table: "BodyShared")
        case .exerciseMinutes: return String(localized: "Exercise Minutes", table: "BodyShared")
        case .trainingLoad: return String(localized: "Training Load", table: "BodyShared")
        case .timeInDaylight: return String(localized: "Time In Daylight", table: "BodyShared")
        case .bodyMass: return String(localized: "Weight", table: "BodyShared")
        case .bodyFatPercentage: return String(localized: "Body Fat", table: "BodyShared")
        }
    }

    /// The app-side metric kind backing this widget metric.
    var healthMetricKind: HealthMetricKind {
        switch self {
        case .readiness: return .readiness
        case .heartRate: return .heartRate
        case .restingHeartRate: return .restingHeartRate
        case .heartRateVariability: return .heartRateVariability
        case .respiratoryRate: return .respiratoryRate
        case .oxygenSaturation: return .oxygenSaturation
        case .sleep: return .sleep
        case .wristTemperature: return .wristTemperature
        case .steps: return .steps
        case .activeEnergy: return .activeEnergy
        case .restingEnergy: return .restingEnergy
        case .exerciseMinutes: return .exerciseMinutes
        case .trainingLoad: return .trainingLoad
        case .timeInDaylight: return .timeInDaylight
        case .bodyMass: return .bodyMass
        case .bodyFatPercentage: return .bodyFatPercentage
        }
    }

    /// Styling and formatting come from the shared metric table, so a widget
    /// looks like the Home card it mirrors. Every case has a row; the fallbacks
    /// below are unreachable and pinned by `HealthMetricPresentationTests`.
    var presentation: HealthMetricPresentation? {
        HealthMetricPresentation.presentation(for: healthMetricKind)
    }

    var symbolName: String {
        presentation?.symbolName ?? "questionmark.circle"
    }

    var tintColor: Color {
        presentation?.tint ?? .secondary
    }

    var chartStyle: HealthWidgetChartStyle {
        switch presentation?.chartStyle {
        case .bar: return .bar
        case .line, nil: return .line
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
        case .week: return String(localized: "Week", table: "BodyShared")
        case .month: return String(localized: "Month", table: "BodyShared")
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

extension HealthWidgetPoint {
    /// Re-windows a cached week of points so the rightmost point is always
    /// `today`: points older than `today - 6 days` are dropped and any
    /// missing trailing days are padded with nil-valued points. A lock
    /// screen/complication snapshot is only rewritten when the app runs, so a
    /// cache written yesterday (or earlier) would otherwise keep showing a
    /// stale "this week" once midnight passes; this re-aligns it at entry
    /// load without needing a fresh app launch. Always returns exactly 7
    /// points, oldest first.
    static func rewindingWeek(
        _ points: [HealthWidgetPoint],
        to today: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [HealthWidgetPoint] {
        let startOfToday = calendar.startOfDay(for: today)
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) else {
            return points
        }

        var pointsByDay: [Date: HealthWidgetPoint] = [:]
        for point in points {
            pointsByDay[calendar.startOfDay(for: point.date)] = point
        }

        return (0...6).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: windowStart) ?? windowStart
            return pointsByDay[day] ?? HealthWidgetPoint(date: day, value: nil)
        }
    }
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
/// "85"/"pts". Most metrics have one; Sleep and Skin Temp have two (matching
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
        case .awake: return String(localized: "Awake", table: "BodyShared")
        case .rem: return String(localized: "REM", table: "BodyShared")
        case .core: return String(localized: "Core", table: "BodyShared")
        case .deep: return String(localized: "Deep", table: "BodyShared")
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

    /// True when `night` is missing or isn't the same calendar day as `date` —
    /// i.e. these stages can't be trusted as belonging to `date`'s night and
    /// must not be displayed as if they were "tonight's" sleep. A snapshot
    /// persisted to the App Group before midnight still holds a legitimately
    /// current "last night" at write time; the widget timeline just re-reads
    /// that cache every ~30 min without rebuilding, so staleness must be
    /// re-checked again at load/display time. A nil `night` is treated as
    /// stale, matching how `SleepSummary.matchesDay` never trusts a missing
    /// date (BodyMetricsKit/Sleep.swift).
    func isStale(asOf date: Date, calendar: Calendar = .bodyGregorian) -> Bool {
        guard let night else { return true }
        return !calendar.isDate(night, inSameDayAs: date)
    }
}

// MARK: - Snapshot

struct HealthWidgetSnapshot: Codable, Equatable {
    /// Bumped when the persisted shape changes in a way this build cannot read.
    /// Optional on decode so a file written before this field existed loads as
    /// `nil` and is treated as version 1.
    static let currentSchemaVersion = 1

    var generatedDate: Date
    var metricTrends: [HealthWidgetMetricTrend]
    var sleep: HealthWidgetSleepStages
    var schemaVersion: Int?

    init(
        generatedDate: Date = Date(),
        metricTrends: [HealthWidgetMetricTrend] = [],
        sleep: HealthWidgetSleepStages = .empty,
        schemaVersion: Int? = HealthWidgetSnapshot.currentSchemaVersion
    ) {
        self.generatedDate = generatedDate
        self.metricTrends = metricTrends
        self.sleep = sleep
        self.schemaVersion = schemaVersion
    }

    func trend(for metric: HealthWidgetMetric) -> HealthWidgetMetricTrend? {
        metricTrends.first { $0.metric == metric }
    }

    var isEmpty: Bool {
        metricTrends.allSatisfy { !$0.hasAnyData } && sleep.isEmpty
    }

    /// Blanks sleep data that's gone stale since this snapshot was persisted.
    /// `HealthWidgetSnapshotBuilder` already guards against carrying over a
    /// stale night when the phone rebuilds the snapshot (`SleepSummary.asOf`),
    /// but a snapshot written to the App Group before midnight still holds a
    /// valid "last night" at write time — the widget timeline just re-reads
    /// that cache every ~30 min without rebuilding it. Widget providers call
    /// this with the current `Date()` at entry-build time so widgets never
    /// keep showing yesterday's sleep after midnight. Only blanks the
    /// "current sleep" style displays (`sleep` stages, the `.sleep` metric's
    /// `displayValues`, and the trend series' `latestText` footer label); the
    /// week/month trend series' plotted points are per-day dated history, not
    /// stale carry-over, and are left untouched.
    func sanitizingStaleSleep(asOf date: Date, calendar: Calendar = .bodyGregorian) -> HealthWidgetSnapshot {
        guard sleep.isStale(asOf: date, calendar: calendar) else { return self }
        var sanitized = self
        sanitized.sleep = .empty
        if let index = sanitized.metricTrends.firstIndex(where: { $0.metric == .sleep }) {
            sanitized.metricTrends[index].displayValues = sanitized.metricTrends[index].displayValues.map { _ in
                HealthWidgetDisplayValue(value: "--", unit: "")
            }
            sanitized.metricTrends[index].week.latestText = "--"
            sanitized.metricTrends[index].month.latestText = "--"
        }
        return sanitized
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
