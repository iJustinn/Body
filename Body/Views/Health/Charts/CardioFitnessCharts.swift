//
//  CardioFitnessCharts.swift
//  Body
//

import Charts
import SwiftUI

enum BodyCardioFitnessLevelPresentation {
    static func make(
        for value: Double?,
        profile: CardioFitnessProfile?
    ) -> BodyHealthMetricTrendHighlightedRange? {
        // Unclassified — no profile, an age outside the norm tables, or no
        // reading — draws no band at all rather than guessing one.
        guard let profile,
              let level = CardioFitnessLevel.level(for: value, profile: profile),
              let bounds = CardioFitnessLevel.bounds(for: level, profile: profile) else {
            return nil
        }

        return BodyHealthMetricTrendHighlightedRange(
            title: level.title,
            lowerBound: bounds.lower,
            upperBound: bounds.upper,
            color: color(for: level)
        )
    }

    /// Training Load's ramp, read in reverse. The two scales run opposite ways —
    /// there the top of the range is the risky end, here it is the good one — so
    /// High borrows Resting's teal and Low borrows High Injury Risk's red, with
    /// the two middle levels taking the colors in between.
    ///
    /// Values are copied from `BodyTrainingLoadIntervalPresentation.color(for:)`
    /// rather than referenced, so retuning one metric's palette never silently
    /// retunes the other's.
    static func color(for level: CardioFitnessLevel) -> Color {
        switch level {
        case .high:
            return Color(red: 0.00, green: 0.88, blue: 0.82)
        case .aboveAverage:
            return Color(red: 0.10, green: 0.82, blue: 0.20)
        case .belowAverage:
            return Color(red: 1.00, green: 0.46, blue: 0.10)
        case .low:
            return Color(red: 1.00, green: 0.17, blue: 0.16)
        }
    }
}

private extension CardioFitnessLevel {
    var symbolName: String {
        switch self {
        case .high:
            return "arrow.up.heart.fill"
        case .aboveAverage:
            return "checkmark.circle.fill"
        case .belowAverage:
            return "exclamationmark.circle.fill"
        case .low:
            return "exclamationmark.triangle.fill"
        }
    }
}

extension CardioFitnessLevelBreakdownEntry: BodyBandBreakdownEntry {
    var tintColor: Color {
        BodyCardioFitnessLevelPresentation.color(for: level)
    }

    var symbolName: String {
        level.symbolName
    }

    var title: String {
        level.title
    }
}

struct BodyCardioFitnessLevelBreakdownChart: View {
    let series: HealthTrendSeries
    let selectedRange: BodyHealthTrendRange
    let profile: CardioFitnessProfile?
    var calendar: Calendar = .bodyGregorian
    let date: Date
    private let entries: [CardioFitnessLevelBreakdownEntry]

    init(
        series: HealthTrendSeries,
        selectedRange: BodyHealthTrendRange,
        profile: CardioFitnessProfile?,
        calendar: Calendar = .bodyGregorian,
        date: Date
    ) {
        self.series = series
        self.selectedRange = selectedRange
        self.profile = profile
        self.calendar = calendar
        self.date = date
        self.entries = CardioFitnessLevelBreakdown.entries(
            for: series,
            range: selectedRange,
            profile: profile,
            calendar: calendar,
            date: date
        )
    }

    private var totalDayCount: Int {
        entries.first?.totalDayCount ?? 0
    }

    /// The range holds readings that simply couldn't be classified — no profile,
    /// or an age outside the norm tables. Worth separating from "no readings at
    /// all", which is the far more common empty state on short ranges.
    private var hasUnclassifiableReadings: Bool {
        totalDayCount == 0 && series
            .calendarPoints(to: selectedRange, calendar: calendar, date: date)
            .contains { ($0.value ?? .nan).isFinite }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Days by Level")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            // All four levels, every range, even when none of them holds a day.
            // Collapsing to an empty state hid the scale itself on exactly the
            // ranges where it is most useful as context — a Week with no
            // qualifying workout is the normal case for this metric, not an
            // error worth replacing the chart for.
            BodyMetricBandBreakdownChart(entries: entries)

            if totalDayCount == 0 {
                emptyNote
            }
        }
    }

    /// Sits under the rows rather than replacing them. Only the unclassified
    /// case says anything: four rows reading "0 days" already tell the user
    /// there were no readings in this range.
    @ViewBuilder
    private var emptyNote: some View {
        if hasUnclassifiableReadings {
            Text("Levels need your Health profile")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}
