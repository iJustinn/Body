//
//  WorkoutElevationProfile.swift
//  Body
//
//  Turns a workout route's raw altitude samples into everything the Elevation
//  card draws: the area outline in unit-square fractions, axis labels in the
//  user's distance unit, and the localized headline strings.
//

import Foundation

/// Everything the Elevation card renders for one workout.
///
/// `init?` returns nil when the route can't support a readable profile — too few
/// altitude samples, no duration, or a climb small enough that the line would be
/// sensor noise drawn full height.
struct WorkoutElevationProfilePresentation: Equatable {
    /// One point of the profile line, in fractions of the plot rect (`yFraction`
    /// measured from the axis floor upwards).
    struct Point: Equatable {
        let xFraction: Double
        let yFraction: Double
    }

    /// One x-axis tick, positioned by `fraction` of the timeline.
    struct TimeMark: Identifiable, Equatable {
        let id: Double
        let fraction: Double
        let label: String
    }

    let points: [Point]
    let timeMarks: [TimeMark]
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

    private static let axisFractions: [Double] = [0, 1.0 / 3.0, 2.0 / 3.0, 1]
    /// Fewer samples than this can't describe a profile — a straight line between
    /// two fixes says nothing about the terrain between them.
    private static let minimumSamples = 10
    /// A route flatter than this is level ground measured by a noisy barometer.
    private static let minimumSpanMeters: Double = 3
    /// Climbing counts only once the line has risen this far above the last low
    /// point, so barometric jitter doesn't accumulate into a fake ascent.
    private static let ascentHysteresisMeters: Double = 3

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
        guard samples.count >= Self.minimumSamples else { return nil }

        let smoothed = Self.medianSmoothed(samples.map(\.meters))
        guard let lowestMeters = smoothed.min(), let highestMeters = smoothed.max() else { return nil }
        guard highestMeters - lowestMeters >= Self.minimumSpanMeters else { return nil }

        let useFeet = distanceUnitPreference == .miles
        let display: (Double) -> Double = { meters in
            useFeet
                ? Measurement(value: meters, unit: UnitLength.meters).converted(to: .feet).value
                : meters
        }

        // Nice round bounds in the display unit, widened to a minimum span so a
        // gentle rise doesn't fill the plot as if it were a mountain.
        let step: Double = useFeet ? 50 : 10
        let minimumAxisSpan: Double = useFeet ? 50 : 20
        let axisMinimum = (display(lowestMeters) / step).rounded(.down) * step
        let axisMaximum = max(
            (display(highestMeters) / step).rounded(.up) * step,
            axisMinimum + minimumAxisSpan
        )
        let axisSpan = axisMaximum - axisMinimum

        points = zip(samples, smoothed).map { sample, meters in
            Point(
                xFraction: min(1, max(0, sample.offset / workoutDuration)),
                yFraction: min(1, max(0, (display(meters) - axisMinimum) / axisSpan))
            )
        }

        timeMarks = [0, 0.5, 1].map { fraction in
            TimeMark(
                id: fraction,
                fraction: fraction,
                label: BodyValueFormat.paddedStopwatchDurationText(for: workoutDuration * fraction)
            )
        }

        yAxisFractions = Self.axisFractions
        yAxisLabels = Self.axisFractions.map {
            BodyValueFormat.numberText(axisMinimum + axisSpan * $0, decimals: 0, locale: locale)
        }

        // The workout's own ascent metadata is the watch's barometric total; the
        // smoothed profile only stands in when the summary didn't carry one.
        let ascent: Double
        if let ascentMeters, ascentMeters.isFinite, ascentMeters >= 0 {
            ascent = ascentMeters
        } else {
            ascent = Self.accumulatedAscent(of: smoothed)
        }

        unitText = useFeet ? "ft" : "m"
        ascentText = BodyValueFormat.numberText(display(ascent).rounded(), decimals: 0, locale: locale)
        maxElevationText = BodyValueFormat.numberText(
            display(highestMeters).rounded(),
            decimals: 0,
            locale: locale
        )
        title = String(localized: "Elevation")
        ascentCaption = String(localized: "Ascent")
        maxCaption = String(localized: "Max Elevation")
        accessibilitySummary = String(
            format: String(localized: "Elevation, ascent %@ %@, maximum %@ %@"),
            ascentText,
            unitText,
            maxElevationText,
            unitText
        )
    }

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
    private static func accumulatedAscent(of values: [Double]) -> Double {
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
}
