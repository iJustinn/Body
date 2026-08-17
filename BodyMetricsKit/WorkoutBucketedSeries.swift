//
//  WorkoutBucketedSeries.swift
//  BodyMetricsKit
//
//  Turns the raw per-bucket inputs of one workout (`WorkoutMetricSeriesData`)
//  into everything a detail bar-chart card draws: bar geometry in unit-square
//  fractions, axis labels in the user's units, and the localized headline
//  strings. One `Spec` per metric keeps pace, speed, cadence, stride length,
//  ground contact time and vertical oscillation on a single code path.
//

import Foundation

/// Everything one bucketed-series card renders for one workout.
///
/// `init?` returns nil whenever fewer than three buckets carry a plausible
/// value, which also hides the card for workouts shorter than ~90 s.
struct WorkoutBucketedSeriesPresentation: Equatable {
    /// Which kind of input the series was built from.
    enum Source: Equatable {
        /// Samples the watch recorded for this metric directly.
        case native
        /// Derived per bucket from distance / steps / active time.
        case computed
    }

    /// Whether the headline stat next to the average is the series' maximum or
    /// its minimum (pace is better when smaller).
    enum Extreme: Equatable {
        case max
        case min
    }

    /// One bucket's bar. `xStart`/`xEnd` are fractions of the workout timeline and
    /// the vertical fractions are of `axisTopValue`, so the view only scales them.
    /// Bars without a recorded range have `lowFraction == highFraction == valueFraction`.
    struct Bar: Identifiable, Equatable {
        let id: Int
        let xStart: Double
        let xEnd: Double
        let lowFraction: Double
        let highFraction: Double
        let valueFraction: Double
    }

    /// One x-axis tick, positioned by `fraction` of the timeline.
    struct TimeMark: Identifiable, Equatable {
        let id: Double
        let fraction: Double
        let label: String
    }

    /// One bucket's statistics, in the metric's canonical HealthKit unit.
    struct Bucket: Equatable {
        let index: Int
        let value: Double
        let low: Double
        let high: Double

        init(index: Int, value: Double, low: Double? = nil, high: Double? = nil) {
            self.index = index
            self.value = value
            self.low = low ?? value
            self.high = high ?? value
        }
    }

    /// Everything that differs between the metrics sharing this presentation.
    struct Spec {
        let title: String
        let averageCaption: String
        let extremeCaption: String
        let extreme: Extreme
        let unitText: String
        /// Plausible values, in the **canonical** unit — validated before conversion
        /// so the same buckets survive in metric and imperial units.
        let validRange: ClosedRange<Double>
        /// Canonical unit → display unit.
        let convert: (Double) -> Double
        /// Axis top rounds up to a multiple of this, in the display unit.
        let axisStep: Double
        /// Smallest axis top, in the display unit.
        let axisFloor: Double
        let decimals: Int
        /// Overrides the plain decimal formatting (pace renders `m:ss`).
        let formatValue: ((Double, Locale) -> String)?
        /// `"…%@ %@…%@ %@"` — average, unit, extreme, unit.
        let accessibilityFormat: String
    }

    let source: Source
    let bars: [Bar]
    let timeMarks: [TimeMark]
    /// Top of the y axis, in the display unit.
    let axisTopValue: Double
    /// Y-axis labels for `yAxisFractions`, ordered bottom to top.
    let yAxisLabels: [String]
    /// Fractions of `axisTopValue` the y-axis labels and gridlines sit at, bottom to top.
    let yAxisFractions: [Double]
    let unitText: String
    let averageText: String
    let extremeText: String
    let title: String
    let averageCaption: String
    let extremeCaption: String
    let accessibilitySummary: String

    private static let axisFractions: [Double] = [0, 1.0 / 3.0, 2.0 / 3.0, 1]

    init?(
        spec: Spec,
        buckets: [Bucket],
        sessionAverage: Double?,
        sessionExtreme: Double?,
        bucketSeconds: TimeInterval,
        startDate: Date,
        endDate: Date,
        source: Source,
        locale: Locale = .current
    ) {
        let duration = endDate.timeIntervalSince(startDate)
        guard bucketSeconds > 0, duration > 0 else { return nil }
        let bucketCount = Int((duration / bucketSeconds).rounded(.up))

        // Validation happens in canonical units, before conversion, so switching
        // between metric and imperial never changes which buckets are shown.
        let entries = buckets.compactMap { bucket -> Bucket? in
            guard bucket.index >= 0, bucket.index < bucketCount else { return nil }
            guard Self.isValid(bucket.value, in: spec.validRange) else { return nil }
            var low = Self.clamped(bucket.low, to: spec.validRange) ?? bucket.value
            var high = Self.clamped(bucket.high, to: spec.validRange) ?? bucket.value
            if low > bucket.value { low = bucket.value }
            if high < bucket.value { high = bucket.value }
            return Bucket(index: bucket.index, value: bucket.value, low: low, high: high)
        }
        guard entries.count >= 3 else { return nil }

        self.source = source
        title = spec.title
        averageCaption = spec.averageCaption
        extremeCaption = spec.extremeCaption
        unitText = spec.unitText

        let bucketValues = entries.map(\.value)
        let average = sessionAverage.flatMap { Self.isValid($0, in: spec.validRange) ? $0 : nil }
            ?? bucketValues.reduce(0, +) / Double(bucketValues.count)
        let extreme = sessionExtreme.flatMap { Self.isValid($0, in: spec.validRange) ? $0 : nil }
            ?? (spec.extreme == .max ? (bucketValues.max() ?? 0) : (bucketValues.min() ?? 0))

        // The axis must fit the tallest bar even when the headline stat is a
        // minimum, so a pace chart still scales to its slowest bucket.
        let highestDisplay = (entries.map { spec.convert($0.high) } + [spec.convert(extreme)])
            .max() ?? 0
        let axisTopValue = max(
            spec.axisFloor,
            (highestDisplay * 1.1 / spec.axisStep).rounded(.up) * spec.axisStep
        )
        self.axisTopValue = axisTopValue

        bars = entries.map { entry in
            Bar(
                id: entry.index,
                xStart: min(1, Double(entry.index) * bucketSeconds / duration),
                xEnd: min(1, Double(entry.index + 1) * bucketSeconds / duration),
                lowFraction: Self.fraction(spec.convert(entry.low), of: axisTopValue),
                highFraction: Self.fraction(spec.convert(entry.high), of: axisTopValue),
                valueFraction: Self.fraction(spec.convert(entry.value), of: axisTopValue)
            )
        }

        timeMarks = [0, 0.5, 1].map { fraction in
            TimeMark(
                id: fraction,
                fraction: fraction,
                label: BodyValueFormat.paddedStopwatchDurationText(for: duration * fraction)
            )
        }

        let format: (Double) -> String = { value in
            spec.formatValue?(value, locale)
                ?? BodyValueFormat.numberText(value, decimals: spec.decimals, locale: locale)
        }

        yAxisFractions = Self.axisFractions
        yAxisLabels = Self.axisFractions.map { format(axisTopValue * $0) }
        averageText = format(spec.convert(average))
        extremeText = format(spec.convert(extreme))
        accessibilitySummary = String(
            format: spec.accessibilityFormat,
            averageText,
            spec.unitText,
            extremeText,
            spec.unitText
        )
    }

    private static func isValid(_ value: Double, in range: ClosedRange<Double>) -> Bool {
        value.isFinite && range.contains(value)
    }

    /// Clamps a finite bound into the plausible range; nil when it isn't a number.
    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func fraction(_ value: Double, of top: Double) -> Double {
        guard top > 0 else { return 0 }
        return min(1, max(0, value / top))
    }
}

/// Builds each workout-detail bar chart from the shared per-bucket read.
enum WorkoutMetricSeriesCharts {
    /// A bucket needs this many steps before distance ÷ steps is meaningful.
    private static let minimumBucketSteps: Double = 10
    /// A bucket needs this much active time and distance before a rate is meaningful.
    private static let minimumBucketSeconds: Double = 10
    private static let minimumBucketMeters: Double = 20

    private static let metersPerMile = 1_609.344
    private static let centimetersPerInch = 2.54

    // MARK: - Stride length

    static func strideLength(
        data: WorkoutMetricSeriesData,
        type: BodyWorkoutType,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference,
        locale: Locale = .current
    ) -> WorkoutBucketedSeriesPresentation? {
        guard type.supportsStepCadence else { return nil }
        let useFeet = distanceUnitPreference == .miles
        let spec = WorkoutBucketedSeriesPresentation.Spec(
            title: String(localized: "Stride Length", table: "BodyMetricsKit"),
            averageCaption: String(localized: "Avg Stride Length", table: "BodyMetricsKit"),
            extremeCaption: String(localized: "Max Stride Length", table: "BodyMetricsKit"),
            extreme: .max,
            unitText: useFeet
                ? String(localized: "ft/step", table: "BodyMetricsKit")
                : String(localized: "m/step", table: "BodyMetricsKit"),
            validRange: 0.2...3.0,
            convert: { meters in
                useFeet
                    ? Measurement(value: meters, unit: UnitLength.meters).converted(to: .feet).value
                    : meters
            },
            axisStep: useFeet ? 0.2 : 0.05,
            axisFloor: useFeet ? 1.5 : 0.5,
            decimals: 2,
            formatValue: nil,
            accessibilityFormat: String(
                localized: "Stride length, average %@ %@, maximum %@ %@",
                table: "BodyMetricsKit"
            )
        )

        // Native stride length is the measured value; distance ÷ steps only
        // stands in when the watch didn't record enough of it.
        if let native = data.strideLengthMeters,
           let presentation = presentation(spec: spec, native: native, data: data, locale: locale) {
            return presentation
        }

        let fallback = validBuckets(in: data) { index in
            guard let meters = data.distanceMeters[index], let steps = data.steps[index] else { return nil }
            guard steps >= minimumBucketSteps, meters > 0 else { return nil }
            let stride = meters / steps
            guard stride.isFinite, spec.validRange.contains(stride) else { return nil }
            return (meters, steps)
        }
        guard !fallback.isEmpty else { return nil }
        let totalMeters = fallback.reduce(0) { $0 + $1.first }
        let totalSteps = fallback.reduce(0) { $0 + $1.second }

        return WorkoutBucketedSeriesPresentation(
            spec: spec,
            buckets: fallback.map { .init(index: $0.index, value: $0.first / $0.second) },
            sessionAverage: totalSteps > 0 ? totalMeters / totalSteps : nil,
            sessionExtreme: nil,
            bucketSeconds: data.bucketSeconds,
            startDate: data.startDate,
            endDate: data.endDate,
            source: .computed,
            locale: locale
        )
    }

    // MARK: - Pace / speed

    static func paceOrSpeed(
        data: WorkoutMetricSeriesData,
        type: BodyWorkoutType,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference,
        locale: Locale = .current
    ) -> WorkoutBucketedSeriesPresentation? {
        let useMiles = distanceUnitPreference == .miles
        let rates = validBuckets(in: data) { index in
            guard let meters = data.distanceMeters[index],
                  let seconds = data.bucketActiveSeconds[index] else { return nil }
            guard seconds >= minimumBucketSeconds, meters >= minimumBucketMeters else { return nil }
            return (meters, seconds)
        }
        guard !rates.isEmpty else { return nil }
        let totalMeters = rates.reduce(0) { $0 + $1.first }
        let totalSeconds = rates.reduce(0) { $0 + $1.second }

        switch type.paceStyle {
        case .distancePace:
            // Canonical seconds per meter; displayed as minutes per km / mile.
            let unitMeters = useMiles ? metersPerMile : 1_000
            let spec = WorkoutBucketedSeriesPresentation.Spec(
                title: String(localized: "Pace", table: "BodyMetricsKit"),
                averageCaption: String(localized: "Avg Pace", table: "BodyMetricsKit"),
                extremeCaption: String(localized: "Best Pace", table: "BodyMetricsKit"),
                extreme: .min,
                unitText: useMiles
                    ? String(localized: "min/mi", table: "BodyMetricsKit")
                    : String(localized: "min/km", table: "BodyMetricsKit"),
                validRange: 0.12...1.8,
                convert: { secondsPerMeter in secondsPerMeter * unitMeters / 60 },
                axisStep: 0.5,
                axisFloor: useMiles ? 5 : 3,
                decimals: 0,
                formatValue: { minutes, _ in clockText(minutes: minutes) },
                accessibilityFormat: String(
                    localized: "Pace, average %@ %@, best %@ %@",
                    table: "BodyMetricsKit"
                )
            )
            return WorkoutBucketedSeriesPresentation(
                spec: spec,
                buckets: rates.map { .init(index: $0.index, value: $0.second / $0.first) },
                sessionAverage: totalMeters > 0 ? totalSeconds / totalMeters : nil,
                sessionExtreme: nil,
                bucketSeconds: data.bucketSeconds,
                startDate: data.startDate,
                endDate: data.endDate,
                source: .computed,
                locale: locale
            )
        case .speed:
            let spec = WorkoutBucketedSeriesPresentation.Spec(
                title: String(localized: "Speed", table: "BodyMetricsKit"),
                averageCaption: String(localized: "Avg Speed", table: "BodyMetricsKit"),
                extremeCaption: String(localized: "Max Speed", table: "BodyMetricsKit"),
                extreme: .max,
                unitText: useMiles
                    ? String(localized: "mph", table: "BodyMetricsKit")
                    : String(localized: "km/h", table: "BodyMetricsKit"),
                validRange: 0.8...25,
                convert: { metersPerSecond in
                    Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
                        .converted(to: useMiles ? .milesPerHour : .kilometersPerHour)
                        .value
                },
                axisStep: 5,
                axisFloor: useMiles ? 15 : 20,
                decimals: 1,
                formatValue: nil,
                accessibilityFormat: String(
                    localized: "Speed, average %@ %@, maximum %@ %@",
                    table: "BodyMetricsKit"
                )
            )
            return WorkoutBucketedSeriesPresentation(
                spec: spec,
                buckets: rates.map { .init(index: $0.index, value: $0.first / $0.second) },
                sessionAverage: totalSeconds > 0 ? totalMeters / totalSeconds : nil,
                sessionExtreme: nil,
                bucketSeconds: data.bucketSeconds,
                startDate: data.startDate,
                endDate: data.endDate,
                source: .computed,
                locale: locale
            )
        case .swimPace, .none:
            return nil
        }
    }

    // MARK: - Cadence

    static func cadence(
        data: WorkoutMetricSeriesData,
        type: BodyWorkoutType,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference,
        locale: Locale = .current
    ) -> WorkoutBucketedSeriesPresentation? {
        if type.supportsStepCadence {
            let spec = WorkoutBucketedSeriesPresentation.Spec(
                title: String(localized: "Step Cadence", table: "BodyMetricsKit"),
                averageCaption: String(localized: "Avg Step Cadence", table: "BodyMetricsKit"),
                extremeCaption: String(localized: "Max Step Cadence", table: "BodyMetricsKit"),
                extreme: .max,
                unitText: String(localized: "spm", table: "BodyMetricsKit"),
                validRange: 40...250,
                convert: { $0 },
                axisStep: 10,
                axisFloor: 100,
                decimals: 0,
                formatValue: nil,
                accessibilityFormat: String(
                    localized: "Cadence, average %@ %@, maximum %@ %@",
                    table: "BodyMetricsKit"
                )
            )
            let steps = validBuckets(in: data) { index in
                guard let steps = data.steps[index],
                      let seconds = data.bucketActiveSeconds[index] else { return nil }
                guard steps >= minimumBucketSteps, seconds >= minimumBucketSeconds else { return nil }
                return (steps, seconds)
            }
            guard !steps.isEmpty else { return nil }
            let totalSteps = steps.reduce(0) { $0 + $1.first }
            let totalSeconds = steps.reduce(0) { $0 + $1.second }
            return WorkoutBucketedSeriesPresentation(
                spec: spec,
                buckets: steps.map { .init(index: $0.index, value: $0.first / $0.second * 60) },
                sessionAverage: totalSeconds > 0 ? totalSteps / totalSeconds * 60 : nil,
                sessionExtreme: nil,
                bucketSeconds: data.bucketSeconds,
                startDate: data.startDate,
                endDate: data.endDate,
                source: .computed,
                locale: locale
            )
        }

        guard let native = data.cyclingCadenceRPM else { return nil }
        let spec = WorkoutBucketedSeriesPresentation.Spec(
            title: String(localized: "Cycling Cadence", table: "BodyMetricsKit"),
            averageCaption: String(localized: "Avg Cycling Cadence", table: "BodyMetricsKit"),
            extremeCaption: String(localized: "Max Cycling Cadence", table: "BodyMetricsKit"),
            extreme: .max,
            unitText: String(localized: "rpm", table: "BodyMetricsKit"),
            validRange: 20...200,
            convert: { $0 },
            axisStep: 10,
            axisFloor: 60,
            decimals: 0,
            formatValue: nil,
            accessibilityFormat: String(
                localized: "Cycling cadence, average %@ %@, maximum %@ %@",
                table: "BodyMetricsKit"
            )
        )
        return presentation(spec: spec, native: native, data: data, locale: locale)
    }

    // MARK: - Running form

    static func groundContactTime(
        data: WorkoutMetricSeriesData,
        type: BodyWorkoutType,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference,
        locale: Locale = .current
    ) -> WorkoutBucketedSeriesPresentation? {
        guard let native = data.groundContactTimeMs else { return nil }
        let spec = WorkoutBucketedSeriesPresentation.Spec(
            title: String(localized: "Ground Contact Time", table: "BodyMetricsKit"),
            averageCaption: String(localized: "Avg Ground Contact", table: "BodyMetricsKit"),
            extremeCaption: String(localized: "Max Ground Contact", table: "BodyMetricsKit"),
            extreme: .max,
            unitText: String(localized: "ms", table: "BodyMetricsKit"),
            validRange: 100...600,
            convert: { $0 },
            axisStep: 50,
            axisFloor: 300,
            decimals: 0,
            formatValue: nil,
            accessibilityFormat: String(
                localized: "Ground contact time, average %@ %@, maximum %@ %@",
                table: "BodyMetricsKit"
            )
        )
        return presentation(spec: spec, native: native, data: data, locale: locale)
    }

    static func verticalOscillation(
        data: WorkoutMetricSeriesData,
        type: BodyWorkoutType,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference,
        locale: Locale = .current
    ) -> WorkoutBucketedSeriesPresentation? {
        guard let native = data.verticalOscillationCm else { return nil }
        let useInches = distanceUnitPreference == .miles
        let spec = WorkoutBucketedSeriesPresentation.Spec(
            title: String(localized: "Vertical Oscillation", table: "BodyMetricsKit"),
            averageCaption: String(localized: "Avg Vertical Osc.", table: "BodyMetricsKit"),
            extremeCaption: String(localized: "Max Vertical Osc.", table: "BodyMetricsKit"),
            extreme: .max,
            unitText: useInches
                ? String(localized: "in", table: "BodyMetricsKit")
                : String(localized: "cm", table: "BodyMetricsKit"),
            validRange: 2...20,
            convert: { centimeters in useInches ? centimeters / centimetersPerInch : centimeters },
            axisStep: useInches ? 0.5 : 1,
            axisFloor: useInches ? 4 : 10,
            decimals: 1,
            formatValue: nil,
            accessibilityFormat: String(
                localized: "Vertical oscillation, average %@ %@, maximum %@ %@",
                table: "BodyMetricsKit"
            )
        )
        return presentation(spec: spec, native: native, data: data, locale: locale)
    }

    // MARK: - Shared

    private static func presentation(
        spec: WorkoutBucketedSeriesPresentation.Spec,
        native: WorkoutMetricSeriesData.NativeSeries,
        data: WorkoutMetricSeriesData,
        locale: Locale
    ) -> WorkoutBucketedSeriesPresentation? {
        WorkoutBucketedSeriesPresentation(
            spec: spec,
            buckets: native.buckets.map {
                .init(index: $0.index, value: $0.average, low: $0.minimum, high: $0.maximum)
            },
            sessionAverage: native.sessionAverage,
            sessionExtreme: native.sessionMax,
            bucketSeconds: data.bucketSeconds,
            startDate: data.startDate,
            endDate: data.endDate,
            source: .native,
            locale: locale
        )
    }

    /// Runs `build` over every bucket index of the workout in order, keeping the
    /// two raw components (distance and steps, or distance and active seconds)
    /// each derived metric divides for its bucket value and session average.
    private static func validBuckets(
        in data: WorkoutMetricSeriesData,
        build: (Int) -> (Double, Double)?
    ) -> [(index: Int, first: Double, second: Double)] {
        let duration = data.endDate.timeIntervalSince(data.startDate)
        guard data.bucketSeconds > 0, duration > 0 else { return [] }
        let bucketCount = Int((duration / data.bucketSeconds).rounded(.up))
        return (0..<bucketCount).compactMap { index in
            guard let parts = build(index) else { return nil }
            guard parts.0.isFinite, parts.1.isFinite, parts.0 != 0, parts.1 != 0 else { return nil }
            return (index, parts.0, parts.1)
        }
    }

    /// Minutes as a `m:ss` clock, for pace values and pace axis labels.
    private static func clockText(minutes: Double) -> String {
        let total = max(0, Int((minutes * 60).rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
