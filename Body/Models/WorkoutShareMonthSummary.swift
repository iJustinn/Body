//
//  WorkoutShareMonthSummary.swift
//  Body
//

import Foundation

/// Which chart the month-summary card draws. Mirrors the Workouts page's own toggle
/// (and borrows its glyphs), but the share sheet holds its own copy: changing the
/// card's chart must never move the page underneath it, so nothing here is stored.
enum WorkoutSummaryChartStyle: String, CaseIterable, Identifiable {
    case calendar
    case bar

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .calendar: return "square.grid.2x2"
        case .bar: return "chart.bar.yaxis"
        }
    }

    var localizedName: String {
        switch self {
        case .calendar: return String(localized: "Calendar")
        case .bar: return String(localized: "Bar Chart")
        }
    }
}

/// One selectable metric on the month-summary card. Leaner than
/// `WorkoutShareMetricOption`: a month has no Details tile behind it, so there is no
/// `kind` and one title serves every layout.
struct WorkoutShareSummaryMetricOption: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

/// Everything a month can put on the summary card, in the card's own display order —
/// which is also the pool order every selection helper resolves back to.
///
/// The first three are offered *even when they read zero*: the card's contract is one
/// to five metrics, and a month with no workouts would otherwise leave an empty pool
/// and nothing to draw. The rest are dropped when the month has no such data, so a
/// shared image never carries an empty distance or a blank activity.
enum WorkoutShareSummaryMetricsBuilder {
    static let workoutsID = "summaryWorkouts"
    static let activeDaysID = "summaryActiveDays"
    static let durationID = "summaryDuration"
    static let activeEnergyID = "summaryActiveEnergy"
    static let distanceID = "summaryDistance"
    static let longestID = "summaryLongest"
    static let topActivityID = "summaryTopActivity"

    /// The automatic pick — the three a month is usually read by. Every one of them
    /// is always in the pool, so the defaults never resolve to nothing.
    static let defaultIDs = [workoutsID, durationID, activeEnergyID]

    static func availableMetrics(
        snapshot: WorkoutMonthSnapshot,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        locale: Locale = .current
    ) -> [WorkoutShareSummaryMetricOption] {
        var options: [WorkoutShareSummaryMetricOption] = [
            WorkoutShareSummaryMetricOption(
                id: workoutsID,
                title: String(localized: "Workouts"),
                value: BodyValueFormat.numberText(Double(snapshot.workoutCount), decimals: 0, locale: locale)
            ),
            WorkoutShareSummaryMetricOption(
                id: activeDaysID,
                title: String(localized: "Active Days"),
                value: BodyValueFormat.numberText(Double(snapshot.activeDayCount), decimals: 0, locale: locale)
            ),
            WorkoutShareSummaryMetricOption(
                id: durationID,
                title: String(localized: "Time"),
                value: BodyValueFormat.durationText(for: snapshot.totalDuration)
            )
        ]

        let energy = snapshot.totalEnergyKilocalories
        if energy > 0 {
            options.append(
                WorkoutShareSummaryMetricOption(
                    id: activeEnergyID,
                    title: String(localized: "Active Energy"),
                    value: BodyValueFormat.energyText(
                        kilocalories: energy,
                        locale: locale,
                        energyUnitPreference: energyUnitPreference
                    )
                )
            )
        }

        let distance = snapshot.totalDistanceMeters
        if distance > 0 {
            options.append(
                WorkoutShareSummaryMetricOption(
                    id: distanceID,
                    title: String(localized: "Distance"),
                    value: BodyValueFormat.distanceText(
                        meters: distance,
                        locale: locale,
                        distanceUnitPreference: distanceUnitPreference
                    )
                )
            )
        }

        let longest = snapshot.days.flatMap(\.workouts).map(\.duration).max() ?? 0
        if longest > 0 {
            options.append(
                WorkoutShareSummaryMetricOption(
                    id: longestID,
                    title: String(localized: "Longest"),
                    value: BodyValueFormat.durationText(for: longest)
                )
            )
        }

        if let topType = snapshot.workoutTypeBreakdown.first?.type {
            options.append(
                WorkoutShareSummaryMetricOption(
                    id: topActivityID,
                    title: String(localized: "Top Activity"),
                    value: topType.displayName
                )
            )
        }

        return options
    }
}

/// One month, packaged for the share sheet: the filtered snapshot the Workouts page
/// is showing, plus the chart that page had on when Share was tapped.
struct WorkoutShareMonthSummary: Equatable {
    let snapshot: WorkoutMonthSnapshot
    let initialChartStyle: WorkoutSummaryChartStyle

    var title: String { snapshot.monthTitle }

    /// The month's leading activity tints the whole card. `.other` is the explicit
    /// neutral for a month with no workouts at all — there is no type to borrow, and
    /// falling back to a real one would colour an empty month as if it had trained.
    var tintType: BodyWorkoutType {
        snapshot.workoutTypeBreakdown.first?.type ?? .other
    }

    /// The stand-in the share sheet holds in its non-optional `workout` slot. Zero
    /// duration and dated to the first of the month: nothing on a summary card reads
    /// it except the tint, and a *real* workout there would put a second activity's
    /// colour on screen.
    var syntheticWorkout: WorkoutSummary {
        let calendar = Calendar.bodyGregorian
        let firstOfMonth = calendar.date(
            from: DateComponents(year: snapshot.year, month: snapshot.month, day: 1, hour: 12)
        ) ?? snapshot.generatedAt
        return WorkoutSummary(type: tintType, startDate: firstOfMonth, duration: 0)
    }
}
