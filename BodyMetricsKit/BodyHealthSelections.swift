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
    static let showSleepScoreKey = "showSleepScore"
    static let sleepStageBreakdownShowsOptimalRangesKey = "sleepStageBreakdownShowsOptimalRanges"
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
    static let healthPermissionSelectionKey = "healthPermissionSelection"
    static let healthDataSourceSelectionKey = "healthDataSourceSelection"
    static let secondaryHealthDataSourceSelectionKey = "secondaryHealthDataSourceSelection"
    static let combinesHealthDataSourcesByNameKey = "combinesHealthDataSourcesByName"
    static let bodyProIconShowsBackKey = "bodyProIconShowsBack"
    static let creatorSurpriseIconsUnlockedKey = "creatorSurpriseIconsUnlocked"

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
    case sleep
    case heart
    case basics
    case bloodOxygen
    case respiratory
    case energy
    case exerciseMinutes
    case wristTemperature
    case timeInDaylight
    case steps

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .activityRings:
            return "Activity Rings"
        case .workouts:
            return "Workouts"
        case .sleep:
            return "Sleep"
        case .heart:
            return "Heart"
        case .basics:
            return "Basics"
        case .bloodOxygen:
            return "Blood Oxygen"
        case .respiratory:
            return "Respiratory"
        case .energy:
            return "Energy"
        case .exerciseMinutes:
            return "Exercise Minutes"
        case .wristTemperature:
            return "Skin Temperature"
        case .timeInDaylight:
            return "Time in Daylight"
        case .steps:
            return "Steps"
        }
    }

    var subtitle: String {
        switch self {
        case .activityRings:
            return "Move, Exercise, and Stand rings"
        case .workouts:
            return "Workout history, effort, and details"
        case .sleep:
            return "Sleep duration, stages, and score"
        case .heart:
            return "Heart rate and HRV"
        case .basics:
            return "Weight, body fat, and BMI"
        case .bloodOxygen:
            return "Blood oxygen readings"
        case .respiratory:
            return "Breathing rate readings"
        case .energy:
            return "Active and resting calories"
        case .exerciseMinutes:
            return "Exercise minute totals"
        case .wristTemperature:
            return "Sleeping skin temperature"
        case .timeInDaylight:
            return "Daylight exposure time"
        case .steps:
            return "Step count totals"
        }
    }

    var iconName: String {
        switch self {
        case .activityRings:
            return "circle.circle.fill"
        case .workouts:
            return "figure.strengthtraining.traditional"
        case .sleep:
            return "bed.double.fill"
        case .heart:
            return "heart.fill"
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
        }
    }

    var tintColor: Color {
        switch self {
        case .activityRings:
            return .pink
        case .workouts:
            return .orange
        case .sleep:
            return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .heart:
            return Color(red: 1.00, green: 0.25, blue: 0.45)
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
        storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.healthPermissionSelectionKey)
                ?? defaultRawValue
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: BodyAppearancePreference.healthPermissionSelectionKey)
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
            return "Week"
        case .recentMonth:
            return "Month"
        case .recentSixMonths:
            return "6 Months"
        case .recentYear:
            return "Year"
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .recentWeek:
            return "7 days"
        case .recentMonth:
            return "30 days"
        case .recentSixMonths:
            return "6 months"
        case .recentYear:
            return "1 year"
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
            return "Last 7 Days"
        case .recentMonth:
            return "Last 30 Days"
        case .recentSixMonths:
            return "Last 6 Months"
        case .recentYear:
            return "Last Year"
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
