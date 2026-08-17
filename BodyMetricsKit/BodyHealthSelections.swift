//
//  BodyHealthSelections.swift
//  BodyMetricsKit
//
//  Foundation/SwiftUI-only health selection + range types shared by the iOS
//  app and the watch app. Extracted from BodyAppearancePreference.swift so the
//  watch can compile the metric calculators (which depend on these) without the
//  iOS-only appearance code.
//

import SwiftUI

enum BodyAppearancePreference {
    static let selectedThemeKey = "selectedTheme"
    static let selectedUnitPreferenceKey = "selectedUnitPreference"
    static let followsSystemUnitsKey = "followsSystemUnits"
    static let selectedWeightUnitKey = "selectedWeightUnit"
    static let selectedDistanceUnitKey = "selectedDistanceUnit"
    static let selectedEnergyUnitKey = "selectedEnergyUnit"
    static let selectedTemperatureUnitKey = "selectedTemperatureUnit"
    static let sleepDurationGoalMinutesKey = "sleepDurationGoalMinutes"
    static let showsSubMinuteAwakeSleepStagesKey = "showsSubMinuteAwakeSleepStages"
    static let showsLeadingTrailingAwakeSleepStagesKey = "showsLeadingTrailingAwakeSleepStages"
    static let showSleepScoreKey = "showSleepScore"
    static let showWorkoutEffortSuggestionsKey = "showWorkoutEffortSuggestions"
    static let autoApplyWorkoutEffortKey = "autoApplyWorkoutEffort"
    static let showReadinessAICommentKey = "showReadinessAIComment"
    static let workoutRouteStyleKey = "workoutRouteStyle"
    static let drawsWorkoutRouteOnLoadKey = "drawsWorkoutRouteOnLoad"
    static let sleepStageBreakdownShowsOptimalRangesKey = "sleepStageBreakdownShowsOptimalRanges"
    static let workoutsChartShowsTypeBreakdownKey = "workoutsChartShowsTypeBreakdown"
    static let homeCardOrderKey = "homeCardOrder"
    static let summaryCardSelectionKey = "summaryCardSelection"
    static let starredMetricKey = "starredMetric"
    static let homeBackgroundColorsKey = "homeBackgroundColors"
    static let homeBackgroundSeparatorsKey = "homeBackgroundSeparators"
    static let homeBackgroundEnabledKey = "homeBackgroundEnabled"
    static let homeBackgroundProfilesKey = "homeBackgroundProfiles"
    static let defaultTrendRangeKey = "defaultTrendRange"
    static let homeTrendCardSelectionKey = "homeTrendCardSelection"
    static let metricDayViewSelectionKey = "metricDayViewSelection"
    static let metricWarningsKey = "metricWarnings"
    static let metricWarningThresholdsKey = "metricWarningThresholds"
    static let healthPermissionSelectionKey = "healthPermissionSelection"
    static let healthPermissionExpandedMigratedKey = "healthPermissionExpandedMigrated"
    static let healthCardioFitnessMigratedKey = "healthCardioFitnessMigrated"
    static let healthDataSourceSelectionKey = "healthDataSourceSelection"
    static let secondaryHealthDataSourceSelectionKey = "secondaryHealthDataSourceSelection"
    static let combinesHealthDataSourcesByNameKey = "combinesHealthDataSourcesByName"
    static let customHealthSourceGroupsKey = "customHealthSourceGroups"
    static let bodyProIconShowsBackKey = "bodyProIconShowsBack"

    static func bodyProIconAssetName(showsBack: Bool) -> String {
        showsBack ? "BodyProIconBack" : "BodyProIcon"
    }
}

enum BodySleepDurationGoal {
    static let minimumMinutes = 4 * 60
    static let maximumMinutes = 12 * 60
    static let stepMinutes = 15
    static let defaultMinutes = 8 * 60
    static let defaultDuration: TimeInterval = 8 * 60 * 60

    static func storedMinutes(from rawValue: Int?) -> Int {
        guard let rawValue else {
            return defaultMinutes
        }

        return min(max(rawValue, minimumMinutes), maximumMinutes)
    }

    static func duration(from minutes: Int) -> TimeInterval {
        TimeInterval(storedMinutes(from: minutes) * 60)
    }

    static func displayText(for minutes: Int) -> String {
        BodyValueFormat.durationText(for: duration(from: minutes))
    }
}

enum BodyHealthPermission: String, CaseIterable, Identifiable {
    case activityRings
    case workouts
    case workoutMetrics
    case sleep
    case heart
    case dateOfBirth
    case basics
    case bloodOxygen
    case respiratory
    case energy
    case exerciseMinutes
    case wristTemperature
    case timeInDaylight
    case steps
    case cardioFitness

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .activityRings:
            return String(localized: "Activity Rings", table: "BodyMetricsKit")
        case .workouts:
            return String(localized: "Workouts", table: "BodyMetricsKit")
        case .workoutMetrics:
            return String(localized: "Workout Metrics", table: "BodyMetricsKit")
        case .sleep:
            return String(localized: "Sleep", table: "BodyMetricsKit")
        case .heart:
            return String(localized: "Heart", table: "BodyMetricsKit")
        case .dateOfBirth:
            return String(localized: "Date of Birth", table: "BodyMetricsKit")
        case .basics:
            return String(localized: "Basics", table: "BodyMetricsKit")
        case .bloodOxygen:
            return String(localized: "Blood Oxygen", table: "BodyMetricsKit")
        case .respiratory:
            return String(localized: "Respiratory", table: "BodyMetricsKit")
        case .energy:
            return String(localized: "Energy", table: "BodyMetricsKit")
        case .exerciseMinutes:
            return String(localized: "Exercise Minutes", table: "BodyMetricsKit")
        case .wristTemperature:
            return String(localized: "Skin Temperature", table: "BodyMetricsKit")
        case .timeInDaylight:
            return String(localized: "Time in Daylight", table: "BodyMetricsKit")
        case .steps:
            return String(localized: "Steps", table: "BodyMetricsKit")
        case .cardioFitness:
            return String(localized: "Cardio Fitness", table: "BodyMetricsKit")
        }
    }

    var subtitle: String {
        switch self {
        case .activityRings:
            return String(localized: "Move, Exercise, and Stand rings", table: "BodyMetricsKit")
        case .workouts:
            return String(localized: "Workout history, effort, and details", table: "BodyMetricsKit")
        case .workoutMetrics:
            return String(localized: "VO₂max, power, cadence, running form, and swim strokes", table: "BodyMetricsKit")
        case .sleep:
            return String(localized: "Sleep duration, stages, and score", table: "BodyMetricsKit")
        case .heart:
            return String(localized: "Heart rate, HRV, and recovery", table: "BodyMetricsKit")
        case .dateOfBirth:
            return String(localized: "Anchors workout HR zones (max HR)", table: "BodyMetricsKit")
        case .basics:
            return String(localized: "Weight, body fat, and BMI", table: "BodyMetricsKit")
        case .bloodOxygen:
            return String(localized: "Blood oxygen readings", table: "BodyMetricsKit")
        case .respiratory:
            return String(localized: "Breathing rate readings", table: "BodyMetricsKit")
        case .energy:
            return String(localized: "Active and resting calories", table: "BodyMetricsKit")
        case .exerciseMinutes:
            return String(localized: "Exercise minute totals", table: "BodyMetricsKit")
        case .wristTemperature:
            return String(localized: "Sleeping skin temperature", table: "BodyMetricsKit")
        case .timeInDaylight:
            return String(localized: "Daylight exposure time", table: "BodyMetricsKit")
        case .steps:
            return String(localized: "Step count totals", table: "BodyMetricsKit")
        case .cardioFitness:
            return String(localized: "VO₂ max and fitness level", table: "BodyMetricsKit")
        }
    }

    var iconName: String {
        switch self {
        case .activityRings:
            return "circle.circle.fill"
        case .workouts:
            return "figure.strengthtraining.traditional"
        case .workoutMetrics:
            return "speedometer"
        case .sleep:
            return "bed.double.fill"
        case .heart:
            return "heart.fill"
        case .dateOfBirth:
            return "birthday.cake.fill"
        case .basics:
            return "scalemass.fill"
        case .bloodOxygen:
            return "drop.fill"
        case .respiratory:
            return "lungs.fill"
        case .energy:
            return "bolt.fill"
        case .exerciseMinutes:
            return "figure.run"
        case .wristTemperature:
            return "thermometer.medium"
        case .timeInDaylight:
            return "sun.max.fill"
        case .steps:
            return "figure.walk"
        case .cardioFitness:
            return "heart.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .activityRings:
            return .pink
        case .workouts:
            return .orange
        case .workoutMetrics:
            return .indigo
        case .sleep:
            return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .heart,
             .cardioFitness:
            return Color(red: 1.00, green: 0.25, blue: 0.45)
        case .dateOfBirth:
            return .brown
        case .basics:
            return .purple
        case .bloodOxygen,
             .respiratory,
             .wristTemperature:
            return Color(red: 0.00, green: 0.75, blue: 0.85)
        case .energy,
             .exerciseMinutes:
            return Color(red: 1.00, green: 0.38, blue: 0.12)
        case .timeInDaylight:
            return .blue
        case .steps:
            return .green
        }
    }
}

struct BodyHealthPermissionSelection: Equatable {
    static let defaultValue = BodyHealthPermissionSelection(
        enabledPermissions: Set(BodyHealthPermission.allCases)
    )
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var enabledPermissions: Set<BodyHealthPermission>

    var rawValue: String {
        guard !enabledPermissions.isEmpty else {
            return "none"
        }

        return BodyHealthPermission.allCases
            .filter { enabledPermissions.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    var enabledCount: Int {
        enabledPermissions.count
    }

    func includes(_ permission: BodyHealthPermission) -> Bool {
        enabledPermissions.contains(permission)
    }

    func setting(_ permission: BodyHealthPermission, isEnabled: Bool) -> BodyHealthPermissionSelection {
        var nextPermissions = enabledPermissions
        if isEnabled {
            nextPermissions.insert(permission)
        } else {
            nextPermissions.remove(permission)
        }

        return BodyHealthPermissionSelection(enabledPermissions: nextPermissions)
    }

    static func storedValue(from rawValue: String) -> BodyHealthPermissionSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return defaultValue
        }

        guard trimmedValue != "none" else {
            return BodyHealthPermissionSelection(enabledPermissions: [])
        }

        let permissions = Set(trimmedValue.split(separator: ",").compactMap {
            BodyHealthPermission(rawValue: String($0))
        })

        guard !permissions.isEmpty else {
            return defaultValue
        }

        return BodyHealthPermissionSelection(enabledPermissions: permissions)
    }

    static func load(defaults: UserDefaults = .standard) -> BodyHealthPermissionSelection {
        let stored = storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.healthPermissionSelectionKey)
                ?? defaultRawValue
        )
        let expanded = migratingExpandedPermissionsIfNeeded(stored, defaults: defaults)
        // Chained AFTER the expanded migration on purpose: that one can insert
        // `.workoutMetrics` for a selection that predates the category, and the
        // cardio fitness gate below reads it.
        return migratingCardioFitnessPermissionIfNeeded(expanded, defaults: defaults)
    }

    /// One-time migration for users whose saved selection predates the `.workoutMetrics`
    /// and `.dateOfBirth` categories (previously bundled under `.workouts` and `.heart`).
    /// Adds each new category when its parent is still enabled so prior behavior is
    /// preserved, then records a flag so a later intentional opt-out is never re-enabled.
    /// Idempotent and per-`defaults` domain; fresh installs already default to all cases.
    private static func migratingExpandedPermissionsIfNeeded(
        _ selection: BodyHealthPermissionSelection,
        defaults: UserDefaults
    ) -> BodyHealthPermissionSelection {
        guard !defaults.bool(forKey: BodyAppearancePreference.healthPermissionExpandedMigratedKey) else {
            return selection
        }

        var migrated = selection
        if selection.includes(.workouts) {
            migrated.enabledPermissions.insert(.workoutMetrics)
        }
        if selection.includes(.heart) {
            migrated.enabledPermissions.insert(.dateOfBirth)
        }

        if migrated != selection {
            migrated.save(defaults: defaults)
        }
        defaults.set(true, forKey: BodyAppearancePreference.healthPermissionExpandedMigratedKey)
        return migrated
    }

    /// One-time migration for users whose saved selection predates the
    /// `.cardioFitness` category. Deliberately carries its OWN key rather than
    /// extending the migration above: that one early-returns on
    /// `healthPermissionExpandedMigratedKey` and sets it permanently, so every
    /// user who has already launched the app would skip anything added to it.
    ///
    /// The gate is `.workouts` AND `.workoutMetrics` because that pair is the
    /// exact condition under which VO₂max was already readable
    /// (`BodyHealthReadTypes.readObjectTypes`). Enabling the new category only
    /// there preserves prior access without silently broadening the read set for
    /// someone who had turned those categories off. Records its own flag so a
    /// later intentional opt-out is never re-enabled; idempotent and per-`defaults`
    /// domain, and fresh installs already default to all cases.
    private static func migratingCardioFitnessPermissionIfNeeded(
        _ selection: BodyHealthPermissionSelection,
        defaults: UserDefaults
    ) -> BodyHealthPermissionSelection {
        guard !defaults.bool(forKey: BodyAppearancePreference.healthCardioFitnessMigratedKey) else {
            return selection
        }

        var migrated = selection
        if selection.includes(.workouts) && selection.includes(.workoutMetrics) {
            migrated.enabledPermissions.insert(.cardioFitness)
        }

        if migrated != selection {
            migrated.save(defaults: defaults)
        }
        defaults.set(true, forKey: BodyAppearancePreference.healthCardioFitnessMigratedKey)
        return migrated
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: BodyAppearancePreference.healthPermissionSelectionKey)
    }
}

enum BodyWorkoutRouteStyle: String, CaseIterable, Identifiable {
    case map
    case plain
    /// Oblique, elevation-extruded ribbon when the route carries altitude; falls back to Plain otherwise.
    case threeD = "3d"

    static let defaultValue: BodyWorkoutRouteStyle = .map

    var id: String {
        rawValue
    }

    /// Whether the workout detail hero can draw this style's route in as it loads.
    /// Map can't: its route is composited into the map snapshot by Core Graphics rather
    /// than stroked by the hero, so there is no path to grow. Route Style offers the
    /// Draw Route switch only for the styles that stroke their own trace.
    var supportsRouteDraw: Bool {
        self != .map
    }

    var title: String {
        switch self {
        case .map:
            return String(localized: "Map", table: "BodyMetricsKit")
        case .plain:
            return String(localized: "Plain", table: "BodyMetricsKit")
        case .threeD:
            return String(localized: "3D", table: "BodyMetricsKit")
        }
    }

    var subtitle: String {
        switch self {
        case .map:
            return String(localized: "Apple Maps", table: "BodyMetricsKit")
        case .plain:
            return String(localized: "Route Only", table: "BodyMetricsKit")
        case .threeD:
            return String(localized: "Elevation Ribbon", table: "BodyMetricsKit")
        }
    }

    static func storedValue(from rawValue: String) -> BodyWorkoutRouteStyle {
        BodyWorkoutRouteStyle(rawValue: rawValue) ?? defaultValue
    }
}

enum BodyHealthTrendRange: String, CaseIterable, Identifiable {
    case recentWeek
    case recentMonth
    case recentSixMonths
    case recentYear

    static let defaultValue: BodyHealthTrendRange = .recentWeek
    static let bodyFatWeightLineChartMaximumPointCount = 20

    static var maximumDayCount: Int {
        allCases.map(\.dayCount).max() ?? defaultValue.dayCount
    }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .recentWeek:
            return String(localized: "Week", table: "BodyMetricsKit")
        case .recentMonth:
            return String(localized: "Month", table: "BodyMetricsKit")
        case .recentSixMonths:
            return String(localized: "6 Months", table: "BodyMetricsKit")
        case .recentYear:
            return String(localized: "Year", table: "BodyMetricsKit")
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .recentWeek:
            return String(localized: "7 days", table: "BodyMetricsKit")
        case .recentMonth:
            return String(localized: "30 days", table: "BodyMetricsKit")
        case .recentSixMonths:
            return String(localized: "range.subtitle.sixMonths", defaultValue: "6 months", table: "BodyMetricsKit")
        case .recentYear:
            return String(localized: "1 year", table: "BodyMetricsKit")
        }
    }

    var iconName: String {
        switch self {
        case .recentWeek:
            return "calendar.day.timeline.leading"
        case .recentMonth:
            return "calendar.badge.clock"
        case .recentSixMonths:
            return "calendar.badge.plus"
        case .recentYear:
            return "calendar"
        }
    }

    var tintColor: Color {
        switch self {
        case .recentWeek:
            return .blue
        case .recentMonth:
            return .green
        case .recentSixMonths:
            return .orange
        case .recentYear:
            return .purple
        }
    }

    var chartTitle: String {
        switch self {
        case .recentWeek:
            return String(localized: "Last 7 Days", table: "BodyMetricsKit")
        case .recentMonth:
            return String(localized: "Last 30 Days", table: "BodyMetricsKit")
        case .recentSixMonths:
            return String(localized: "Last 6 Months", table: "BodyMetricsKit")
        case .recentYear:
            return String(localized: "Last Year", table: "BodyMetricsKit")
        }
    }

    var dayCount: Int {
        switch self {
        case .recentWeek:
            return 7
        case .recentMonth:
            return 30
        case .recentSixMonths:
            return 183
        case .recentYear:
            return 365
        }
    }

    var axisStrideDayCount: Int {
        switch self {
        case .recentWeek:
            return 1
        case .recentMonth:
            return 7
        case .recentSixMonths:
            return 30
        case .recentYear:
            return 60
        }
    }

    var chartAggregationDayCount: Int {
        switch self {
        case .recentWeek,
             .recentMonth:
            return 1
        case .recentSixMonths:
            return 6
        case .recentYear:
            return 12
        }
    }

    var chartCalendarPointCount: Int {
        let fullBucketCount = dayCount / chartAggregationDayCount
        return max(fullBucketCount, 1)
    }

    static let sourceComparisonBucketDoublingFactor = 2
    static let sourceComparisonBarWidthScale: CGFloat = 1.12
    static let sourceComparisonBucketOffsetFraction: Double = 0.16

    var sourceComparisonChartAggregationDayCount: Int {
        switch self {
        case .recentWeek:
            return chartAggregationDayCount
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return chartAggregationDayCount * Self.sourceComparisonBucketDoublingFactor
        }
    }

    var lineChartMaximumPointCount: Int? {
        switch self {
        case .recentWeek:
            return nil
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return 25
        }
    }

    var chartBarWidth: CGFloat {
        switch self {
        case .recentWeek:
            return 32
        case .recentMonth:
            return 7
        case .recentSixMonths,
             .recentYear:
            return 8
        }
    }

    func chartBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        switch self {
        case .recentSixMonths,
             .recentYear:
            return availableWidth <= 330 ? 5 : chartBarWidth
        case .recentWeek,
             .recentMonth:
            return chartBarWidth
        }
    }

    func sourceComparisonChartBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        let widenedBarWidth = chartBarWidth(forAvailableWidth: availableWidth) * Self.sourceComparisonBarWidthScale
        switch self {
        case .recentWeek:
            return widenedBarWidth / 2
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return widenedBarWidth
        }
    }

    var sourceComparisonChartDateOffset: TimeInterval {
        let secondsPerDay: Double = 24 * 60 * 60
        return Double(sourceComparisonChartAggregationDayCount) * secondsPerDay * Self.sourceComparisonBucketOffsetFraction
    }

    func sourceComparisonRangeChartBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        let widenedBarWidth = heartRateRangeChartBarWidth(forAvailableWidth: availableWidth) * Self.sourceComparisonBarWidthScale
        switch self {
        case .recentWeek:
            return widenedBarWidth / 2
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return widenedBarWidth
        }
    }

    func heartRateRangeChartBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        switch self {
        case .recentWeek:
            return 24
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return chartBarWidth(forAvailableWidth: availableWidth)
        }
    }

    var showsPointMarks: Bool {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return true
        }
    }

    var usesPreviewLineChartStyle: Bool {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return true
        }
    }

    var usesMetricColorLineStroke: Bool {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return true
        }
    }

    var trendLineWidth: CGFloat {
        3
    }

    var linePointDiameter: CGFloat {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return 8
        }
    }

    var lineCurrentPointDiameter: CGFloat {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return 10
        }
    }

    func axisLabel(for date: Date) -> String {
        switch self {
        case .recentWeek:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .recentMonth:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .recentSixMonths,
             .recentYear:
            return date.formatted(.dateTime.month(.abbreviated))
        }
    }

    static func storedValue(from rawValue: String) -> BodyHealthTrendRange {
        BodyHealthTrendRange(rawValue: rawValue) ?? defaultValue
    }
}
