//
//  WorkoutElevationSeries.swift
//  BodyMetricsKit
//
//  Turns a workout route's raw altitude samples into the Elevation card's
//  profile line. The smoothing and ascent rules here are the barometer-noise
//  defences the card has always drawn its terrain through.
//

import Foundation

/// The pure altitude maths behind the Elevation card.
enum WorkoutElevationSeries {
    /// Fewer samples than this can't describe a profile — a straight line between
    /// two fixes says nothing about the terrain between them.
    static let minimumSamples = 10
    /// A route flatter than this is level ground measured by a noisy barometer.
    static let minimumSpanMeters: Double = 3
    /// Climbing counts only once the line has risen this far above the last low
    /// point, so barometric jitter doesn't accumulate into a fake ascent.
    static let ascentHysteresisMeters: Double = 3

    /// Median-of-5, which drops single-fix barometric spikes without rounding off
    /// a real summit the way an average would. Edge samples use the neighbours
    /// they have.
    static func medianSmoothed(_ values: [Double]) -> [Double] {
        values.indices.map { index in
            let lower = max(values.startIndex, index - 2)
            let upper = min(values.index(before: values.endIndex), index + 2)
            let window = values[lower...upper].sorted()
            return window[window.count / 2]
        }
    }

    /// Sum of the rises in `values`, counting a climb only once it clears
    /// `ascentHysteresisMeters` above the running low point.
    static func accumulatedAscent(of values: [Double]) -> Double {
        guard var reference = values.first else { return 0 }
        var ascent: Double = 0
        for value in values.dropFirst() {
            if value >= reference + ascentHysteresisMeters {
                ascent += value - reference
                reference = value
            } else if value < reference {
                reference = value
            }
        }
        return ascent
    }

    /// The workout's own ascent metadata is the watch's barometric total; the
    /// smoothed profile only stands in when the summary didn't carry one.
    static func ascentMeters(summary: Double?, smoothed: [Double]) -> Double {
        if let summary, summary.isFinite, summary >= 0 {
            return summary
        }
        return accumulatedAscent(of: smoothed)
    }
}

/// Everything the Elevation card renders for one workout: the smoothed profile
/// line in unit-square fractions, its tight y axis, and the localized headline
/// strings.
///
/// `init?` returns nil when the route can't support a readable profile — too few
/// altitude samples, no duration, or a climb small enough that the line would be
/// sensor noise drawn full height.
struct WorkoutElevationLinePresentation: Equatable {
    /// One smoothed altitude sample. `yFraction` is measured from the bottom of
    /// `axisRange` upwards, so the view only scales it.
    struct Point: Identifiable, Equatable {
        let id: Int
        let xFraction: Double
        let yFraction: Double
        /// The altitude in the display unit, formatted — what a scrub callout reads.
        let valueText: String
        /// Elapsed time at the sample, as `HH:mm:ss`.
        let elapsedText: String
    }

    /// One x-axis tick, positioned by `fraction` of the timeline.
    struct TimeMark: Identifiable, Equatable {
        let id: Double
        let fraction: Double
        let label: String
    }

    let points: [Point]
    let timeMarks: [TimeMark]
    /// The y axis' bounds, in the display unit — tight around the route rather
    /// than anchored at zero.
    let axisRange: ClosedRange<Double>
    /// Y-axis labels for `yAxisFractions`, ordered bottom to top.
    let yAxisLabels: [String]
    /// Fractions of the plot height the y-axis labels and gridlines sit at, bottom to top.
    let yAxisFractions: [Double]
    let unitText: String
    let ascentText: String
    let maxElevationText: String
    let title: String
    let ascentCaption: String
    let maxCaption: String
    let accessibilitySummary: String

    init?(
        profile: [WorkoutElevationSample],
        workoutDuration: TimeInterval,
        ascentMeters: Double?,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference,
        locale: Locale = .current
    ) {
        guard workoutDuration > 0 else { return nil }

        let samples = profile
            .filter { $0.meters.isFinite && $0.offset.isFinite }
            .sorted { $0.offset < $1.offset }
        guard samples.count >= WorkoutElevationSeries.minimumSamples else { return nil }

        let smoothed = WorkoutElevationSeries.medianSmoothed(samples.map(\.meters))
        guard let lowestMeters = smoothed.min(), let highestMeters = smoothed.max() else { return nil }
        guard highestMeters - lowestMeters >= WorkoutElevationSeries.minimumSpanMeters else { return nil }

        let useFeet = distanceUnitPreference == .miles
        // Matching `BodyValueFormat.elevationText`, the units stay unlocalized.
        unitText = useFeet ? "ft" : "m"
        let display: (Double) -> Double = { meters in
            useFeet
                ? Measurement(value: meters, unit: UnitLength.meters).converted(to: .feet).value
                : meters
        }
        let format: (Double) -> String = { value in
            BodyValueFormat.numberText(value, decimals: 0, locale: locale)
        }

        // Nice round bounds in the display unit, padded around the climb and
        // widened to a minimum span so a gentle rise doesn't fill the plot as if
        // it were a mountain. Below sea level stays below sea level.
        let axis = WorkoutChartAxis.niceRange(
            low: display(lowestMeters),
            high: display(highestMeters),
            step: useFeet ? 20 : 5,
            minimumSpan: useFeet ? 20 : 6,
            clampToZero: false
        )
        axisRange = axis.range
        let axisMinimum = axis.range.lowerBound
        let axisSpan = axis.range.upperBound - axisMinimum

        points = zip(samples, smoothed).enumerated().map { index, pair in
            let (sample, meters) = pair
            return Point(
                id: index,
                // A route that kept recording past the workout's end folds onto the
                // last instant rather than running off the chart.
                xFraction: min(1, max(0, sample.offset / workoutDuration)),
                yFraction: min(1, max(0, (display(meters) - axisMinimum) / axisSpan)),
                valueText: format(display(meters)),
                elapsedText: BodyValueFormat.paddedStopwatchDurationText(
                    for: min(workoutDuration, max(0, sample.offset))
                )
            )
        }

        // Elapsed rather than clock time, matching the sibling bucketed charts and
        // the scrub callout's own timestamp.
        timeMarks = [0, 0.5, 1].map { fraction in
            TimeMark(
                id: fraction,
                fraction: fraction,
                label: BodyValueFormat.paddedStopwatchDurationText(for: workoutDuration * fraction)
            )
        }

        yAxisFractions = axis.ticks.map { ($0 - axisMinimum) / axisSpan }
        yAxisLabels = axis.ticks.map(format)

        let ascent = WorkoutElevationSeries.ascentMeters(summary: ascentMeters, smoothed: smoothed)
        ascentText = format(display(ascent).rounded())
        maxElevationText = format(display(highestMeters).rounded())
        title = String(localized: "Elevation", table: "BodyMetricsKit")
        ascentCaption = String(localized: "Ascent", table: "BodyMetricsKit")
        maxCaption = String(localized: "Max Elevation", table: "BodyMetricsKit")
        accessibilitySummary = String(
            format: String(
                localized: "Elevation, ascent %@ %@, maximum %@ %@",
                table: "BodyMetricsKit"
            ),
            ascentText,
            unitText,
            maxElevationText,
            unitText
        )
    }
}
