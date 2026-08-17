//
//  WorkoutSummary.swift
//  Body
//

import Foundation

struct WorkoutHeartRateSample: Codable, Equatable, Hashable, Identifiable {
    let date: Date
    let beatsPerMinute: Double

    var id: String {
        "\(date.timeIntervalSince1970)-\(beatsPerMinute)"
    }
}

/// One heart-rate zone row for the workout-detail breakdown: its index (0 = recovery …
/// 5 = max effort), bpm bounds (nil = open-ended), and the time/share spent in it.
struct WorkoutHeartRateZone: Equatable, Identifiable {
    let zone: Int
    let lowerBound: Int?
    let upperBound: Int?
    let duration: TimeInterval
    let fraction: Double

    var id: Int { zone }

    /// "≤122", "123–142", or "≥183".
    var bpmRangeText: String {
        switch (lowerBound, upperBound) {
        case let (nil, upper?):
            return "≤\(upper)"
        case let (lower?, nil):
            return "≥\(lower)"
        case let (lower?, upper?):
            return "\(lower)–\(upper)"
        case (nil, nil):
            return ""
        }
    }
}

enum WorkoutHeartRateZones {
    /// Zone lower bounds as a fraction of max HR: Zone 1 starts at 50% … Zone 5 at 90%.
    /// Zone 0 (recovery) is everything below Zone 1.
    static let lowerBoundFractions: [Double] = [0.50, 0.60, 0.70, 0.80, 0.90]

    /// A gap larger than this between consecutive HR samples is treated as a pause and
    /// capped, so a mid-workout stop doesn't dump minutes into whatever zone preceded it.
    static let maxSampleGap: TimeInterval = 60

    /// Time-in-zone breakdown ordered 5→0 (matching the card's top-down layout) from the
    /// workout's HR samples and the athlete's max HR. Returns nil without enough samples
    /// or a positive max HR to anchor the bands.
    static func zones(
        samples: [WorkoutHeartRateSample],
        maxHeartRate: Double
    ) -> [WorkoutHeartRateZone]? {
        guard maxHeartRate > 0, samples.count >= 2 else {
            return nil
        }

        let thresholds = lowerBoundFractions.map { Int((maxHeartRate * $0).rounded()) }
        let sorted = samples.sorted { $0.date < $1.date }

        var durations = [TimeInterval](repeating: 0, count: 6)
        for index in 0..<(sorted.count - 1) {
            let gap = sorted[index + 1].date.timeIntervalSince(sorted[index].date)
            guard gap > 0 else { continue }
            let zone = zoneIndex(forBPM: sorted[index].beatsPerMinute, thresholds: thresholds)
            durations[zone] += min(gap, maxSampleGap)
        }

        let total = durations.reduce(0, +)
        guard total > 0 else {
            return nil
        }

        return (0...5).reversed().map { zone in
            WorkoutHeartRateZone(
                zone: zone,
                lowerBound: zone == 0 ? nil : thresholds[zone - 1],
                upperBound: zone == 5 ? nil : thresholds[zone] - 1,
                duration: durations[zone],
                fraction: durations[zone] / total
            )
        }
    }

    private static func zoneIndex(forBPM bpm: Double, thresholds: [Int]) -> Int {
        for (index, threshold) in thresholds.enumerated() where bpm < Double(threshold) {
            return index
        }
        return thresholds.count
    }
}

struct WorkoutSummary: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let type: BodyWorkoutType
    let startDate: Date
    let duration: TimeInterval
    let activeEnergyKilocalories: Double?
    let totalEnergyKilocalories: Double?
    let distanceMeters: Double?
    let averageHeartRateBeatsPerMinute: Double?
    let maximumHeartRateBeatsPerMinute: Double?
    let effortLevel: Double?
    /// `true` when the effort lookup FAILED for a workout that had no cached
    /// score (H12) — its `effortLevel` is neither a real rating nor a trustworthy
    /// default, so `TrainingLoadCalculator.load` excludes it rather than counting
    /// it as the default effort. Optional so old persisted snapshots decode `nil`
    /// (genuinely unrated / resolved), and so the M10 byte-dedupe only sees a
    /// change when the flag actually flips.
    let effortUnresolved: Bool?
    let heartRateSamples: [WorkoutHeartRateSample]?
    let elevationAscendedMeters: Double?
    let averagePowerWatts: Double?
    let averageStepCadenceSPM: Double?
    let averageCyclingCadenceRPM: Double?
    let swimmingStrokeCount: Double?
    let cardioFitnessVO2Max: Double?
    let sourceName: String
    /// HealthKit's authoritative end. `duration` excludes paused time, so
    /// `startDate + duration` can land before the workout really ended; optional
    /// so snapshots persisted before it was recorded decode `nil`.
    let endDate: Date?
    /// Weather the watch recorded with the workout (`HKMetadataKeyWeatherTemperature`),
    /// in °C. Workout metadata rather than a separate sample type, so it rides the
    /// Workouts permission and isn't cleared by `removingWorkoutMetrics()`.
    let weatherTemperatureCelsius: Double?
    /// Recorded relative humidity as a percentage (0…100); HealthKit stores it as a
    /// 0…1 fraction.
    let weatherHumidityPercent: Double?
    /// `HKMetadataKeyAverageMETs` in kcal/(kg·hr) — the workout's average metabolic
    /// equivalent.
    let averageMETs: Double?
    /// The workout's 1-minute heart-rate recovery in BPM, read from the statistics
    /// already attached to the `HKWorkout` (no extra query). Optional so snapshots
    /// persisted before it existed decode `nil`, and so a workout whose recovery
    /// sample hasn't synced yet falls back to the detail sheet's lazy read. Rides
    /// the Heart permission like the other heart fields.
    let heartRateRecoveryBPM: Double?

    /// The workout's end for interval maths: HealthKit's `endDate` when recorded,
    /// otherwise the pre-existing `startDate + duration` approximation.
    var effectiveEndDate: Date {
        endDate ?? startDate.addingTimeInterval(max(0, duration))
    }

    init(
        id: UUID = UUID(),
        type: BodyWorkoutType,
        startDate: Date,
        duration: TimeInterval,
        activeEnergyKilocalories: Double? = nil,
        totalEnergyKilocalories: Double? = nil,
        distanceMeters: Double? = nil,
        averageHeartRateBeatsPerMinute: Double? = nil,
        maximumHeartRateBeatsPerMinute: Double? = nil,
        effortLevel: Double? = nil,
        effortUnresolved: Bool? = nil,
        heartRateSamples: [WorkoutHeartRateSample] = [],
        elevationAscendedMeters: Double? = nil,
        averagePowerWatts: Double? = nil,
        averageStepCadenceSPM: Double? = nil,
        averageCyclingCadenceRPM: Double? = nil,
        swimmingStrokeCount: Double? = nil,
        cardioFitnessVO2Max: Double? = nil,
        sourceName: String = "Apple Health",
        endDate: Date? = nil,
        weatherTemperatureCelsius: Double? = nil,
        weatherHumidityPercent: Double? = nil,
        averageMETs: Double? = nil,
        heartRateRecoveryBPM: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.duration = duration
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.totalEnergyKilocalories = totalEnergyKilocalories
        self.distanceMeters = distanceMeters
        self.averageHeartRateBeatsPerMinute = averageHeartRateBeatsPerMinute
        self.maximumHeartRateBeatsPerMinute = maximumHeartRateBeatsPerMinute
        self.effortLevel = effortLevel
        self.effortUnresolved = effortUnresolved
        self.heartRateSamples = heartRateSamples
        self.elevationAscendedMeters = elevationAscendedMeters
        self.averagePowerWatts = averagePowerWatts
        self.averageStepCadenceSPM = averageStepCadenceSPM
        self.averageCyclingCadenceRPM = averageCyclingCadenceRPM
        self.swimmingStrokeCount = swimmingStrokeCount
        self.cardioFitnessVO2Max = cardioFitnessVO2Max
        self.sourceName = sourceName
        self.endDate = endDate
        self.weatherTemperatureCelsius = weatherTemperatureCelsius
        self.weatherHumidityPercent = weatherHumidityPercent
        self.averageMETs = averageMETs
        self.heartRateRecoveryBPM = heartRateRecoveryBPM
    }

    /// A copy with the Workout Metrics detail fields cleared — used when the user
    /// disables the `.workoutMetrics` permission so already-cached summaries stop
    /// surfacing those values. Distance, energy, and heart rate are preserved (they
    /// ride other toggles); only VO₂max, power, both cadences, and swim strokes drop.
    /// The detail tile builder omits any tile whose value is nil.
    func removingWorkoutMetrics() -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            type: type,
            startDate: startDate,
            duration: duration,
            activeEnergyKilocalories: activeEnergyKilocalories,
            totalEnergyKilocalories: totalEnergyKilocalories,
            distanceMeters: distanceMeters,
            averageHeartRateBeatsPerMinute: averageHeartRateBeatsPerMinute,
            maximumHeartRateBeatsPerMinute: maximumHeartRateBeatsPerMinute,
            effortLevel: effortLevel,
            effortUnresolved: effortUnresolved,
            heartRateSamples: heartRateSamples ?? [],
            elevationAscendedMeters: elevationAscendedMeters,
            averagePowerWatts: nil,
            averageStepCadenceSPM: nil,
            averageCyclingCadenceRPM: nil,
            swimmingStrokeCount: nil,
            cardioFitnessVO2Max: nil,
            sourceName: sourceName,
            endDate: endDate,
            // Weather and METs are workout metadata, not Workout Metrics samples —
            // they ride the Workouts permission and survive the opt-out.
            weatherTemperatureCelsius: weatherTemperatureCelsius,
            weatherHumidityPercent: weatherHumidityPercent,
            averageMETs: averageMETs,
            // Heart-rate recovery rides the Heart permission, not Workout Metrics.
            heartRateRecoveryBPM: heartRateRecoveryBPM
        )
    }

    /// A copy with heart-rate recovery cleared — used when the user disables the
    /// `.heart` permission so an already-cached summary stops surfacing the tile
    /// (and its comparison) before the next refetch. Everything else is preserved.
    func removingHeartRateRecovery() -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            type: type,
            startDate: startDate,
            duration: duration,
            activeEnergyKilocalories: activeEnergyKilocalories,
            totalEnergyKilocalories: totalEnergyKilocalories,
            distanceMeters: distanceMeters,
            averageHeartRateBeatsPerMinute: averageHeartRateBeatsPerMinute,
            maximumHeartRateBeatsPerMinute: maximumHeartRateBeatsPerMinute,
            effortLevel: effortLevel,
            effortUnresolved: effortUnresolved,
            heartRateSamples: heartRateSamples ?? [],
            elevationAscendedMeters: elevationAscendedMeters,
            averagePowerWatts: averagePowerWatts,
            averageStepCadenceSPM: averageStepCadenceSPM,
            averageCyclingCadenceRPM: averageCyclingCadenceRPM,
            swimmingStrokeCount: swimmingStrokeCount,
            cardioFitnessVO2Max: cardioFitnessVO2Max,
            sourceName: sourceName,
            endDate: endDate,
            weatherTemperatureCelsius: weatherTemperatureCelsius,
            weatherHumidityPercent: weatherHumidityPercent,
            averageMETs: averageMETs,
            heartRateRecoveryBPM: nil
        )
    }
}

struct WorkoutDetailMetric: Equatable {
    enum Kind {
        case activeEnergy
        case totalEnergy
        case avgHeartRate
        case maxHeartRate
        case distance
        case pace
        case speed
        case swimPace
        case elevation
        case stepCadence
        case cyclingCadence
        case power
        case cardioFitness
        case strokeCount
        case humidity
        case averageMETs
        case heartRateRecovery
    }

    let kind: Kind
    let title: String
    let value: String
    let comparison: WorkoutMetricComparison?

    init(kind: Kind, title: String, value: String, comparison: WorkoutMetricComparison? = nil) {
        self.kind = kind
        self.title = title
        self.value = value
        self.comparison = comparison
    }
}

/// A compact comparison badge shown above a metric's unit. `badgeText` is the visual
/// token (e.g. "↑12%", "↓3%", "≈0%"); `accessibilityLabel` is the spoken VoiceOver form
/// so the arrow glyph isn't read literally. The "vs 30-day avg" frame lives once in the
/// section header, not in every badge. `badgeText` may also be a "0%" stand-in — see
/// `WorkoutMetricComparisonBuilder.placeholder(for:availability:current:locale:)` — whose
/// spoken form says why there is no number yet.
struct WorkoutMetricComparison: Equatable {
    let badgeText: String
    let accessibilityLabel: String
}

/// What the "Details" card's comparison legend says, and whether its tiles carry
/// measured percentages or "0%" stand-ins. Held once per card rather than derived per
/// tile, so the legend never disagrees with the badges under it.
enum WorkoutMetricComparisonAvailability: Equatable {
    /// At least one metric has a measured delta.
    case ready
    /// A spanned month is still loading, so the numbers are on their way.
    case calculating
    /// The window loaded (or gave up) with too little history to compare against.
    case insufficientHistory
}

/// Builds the "↑ 12% vs 30-day avg" caption for a single detail metric against the
/// same workout type's recent history. Pure and unit-agnostic: the percentage is
/// computed on one raw scalar per metric, so it needs no unit preferences. Eligibility
/// mirrors each tile's display guard so a prior the UI treats as absent never skews the
/// baseline, and the math is hardened against near-zero baselines before any `Int(...)`.
enum WorkoutMetricComparisonBuilder {
    /// Minimum eligible prior samples before a comparison is shown.
    static let minimumSampleCount = 3
    /// Distance floors below which pace/speed are too noisy to compare.
    static let minComparableDistanceMeters = 400.0
    static let minComparableSwimDistanceMeters = 100.0
    /// Percent magnitude is clamped to this before `Int(...)` to avoid overflow traps
    /// (`Int(inf/NaN)` and `abs(Int.min)` both crash).
    static let maxDisplayPercent = 999.0

    /// A compact badge for the metric — "↑12%", "↓3%", or "≈0%" — or nil when there is
    /// nothing to show: while months are still loading, when the current metric isn't
    /// displayable, or when there are fewer than `minimumSampleCount` eligible priors.
    /// The "vs 30-day avg" reference frame is shown once in the section header, not here.
    static func comparison(
        for kind: WorkoutDetailMetric.Kind,
        current: WorkoutSummary,
        priors: [WorkoutSummary],
        isComplete: Bool,
        locale: Locale
    ) -> WorkoutMetricComparison? {
        // No caption at all until every spanned month has loaded. A partial window can
        // still hold 3+ priors (from already-loaded months or the launch-seeded snapshot),
        // so gating only the under-sampled fallback would leak an inaccurate average.
        guard isComplete else { return nil }

        guard let currentScalar = scalar(for: kind, from: current) else {
            return nil
        }

        let baseline: Double?
        let sampleCount: Int
        if isRateMetric(kind) {
            let totals = rateTotals(for: kind, from: priors)
            sampleCount = totals.count
            baseline = totals.count > 0 && totals.distance > 0 && totals.duration > 0
                ? rateValue(for: kind, distance: totals.distance, duration: totals.duration)
                : nil
        } else {
            let priorScalars = priors.compactMap { scalar(for: kind, from: $0) }
            sampleCount = priorScalars.count
            baseline = priorScalars.isEmpty
                ? nil
                : priorScalars.reduce(0, +) / Double(priorScalars.count)
        }

        guard sampleCount >= minimumSampleCount, let baseline else {
            return nil
        }

        return caption(current: currentScalar, baseline: baseline, locale: locale)
    }

    // MARK: - Availability

    /// The card-level state behind the legend beside "Details", or nil when this
    /// workout has no comparable metric at all (a strength session whose every tile
    /// reads "No Data" gets no legend and no stand-ins, exactly as before).
    ///
    /// `isSettled` is what stops "Calculating" from lasting forever: `isComplete` can
    /// never turn true when the months simply cannot load — Workouts permission off,
    /// Apple Health unavailable, a failed month fetch — so once the caller has awaited
    /// the load, an incomplete window means there is nothing more coming.
    static func availability(
        for kinds: [WorkoutDetailMetric.Kind],
        current: WorkoutSummary,
        hasComparison: Bool,
        isComplete: Bool,
        isSettled: Bool
    ) -> WorkoutMetricComparisonAvailability? {
        guard kinds.contains(where: { scalar(for: $0, from: current) != nil }) else {
            return nil
        }

        if hasComparison {
            return .ready
        }

        return isComplete || isSettled ? .insufficientHistory : .calculating
    }

    /// The "0%" stand-in for a metric with no measured delta. It is a real badge rather
    /// than an absence so the digits can roll over in place when the measurement lands —
    /// a badge that appears from nothing can only pop.
    ///
    /// Gated on the same display scalar the baseline uses, so a tile that has no value
    /// of its own never sprouts a 0% claiming it matched the average.
    ///
    /// Only while `.calculating`. The stand-in exists so digits can roll into place when
    /// a measurement lands — once loading has settled there is no measurement coming, so
    /// a "0%" would be a synthetic number presented as a result. That applies to both
    /// settled states: under `.ready` the legend reads "vs 30-day avg" and the zero looks
    /// measured, and under `.insufficientHistory` there is nothing left to roll into.
    static func placeholder(
        for kind: WorkoutDetailMetric.Kind,
        availability: WorkoutMetricComparisonAvailability?,
        current: WorkoutSummary,
        locale: Locale
    ) -> WorkoutMetricComparison? {
        guard availability == .calculating, scalar(for: kind, from: current) != nil else {
            return nil
        }

        let accessibilityLabel = String(
            localized: "Calculating the 30-day comparison",
            table: "BodyMetricsKit"
        )

        return WorkoutMetricComparison(
            // Localized digits, so the stand-in matches the shape of the number that
            // replaces it (Arabic/Hindi digits included).
            badgeText: "\(BodyValueFormat.numberText(0, decimals: 0, locale: locale))%",
            accessibilityLabel: accessibilityLabel
        )
    }

    // MARK: - Scalars

    /// The comparable scalar for a metric, or nil when the metric would read as absent
    /// for this workout (mirrors the detail tile's `> 0` display guards). Positive-only
    /// so a zero-valued prior never depresses the baseline or fills the sample floor.
    static func scalar(for kind: WorkoutDetailMetric.Kind, from workout: WorkoutSummary) -> Double? {
        switch kind {
        case .activeEnergy: return positive(workout.activeEnergyKilocalories)
        case .totalEnergy: return positive(workout.totalEnergyKilocalories)
        case .avgHeartRate: return positive(displayedAverageHeartRate(for: workout))
        case .maxHeartRate: return positive(workout.maximumHeartRateBeatsPerMinute)
        case .distance: return positive(workout.distanceMeters)
        case .elevation: return positive(workout.elevationAscendedMeters)
        case .stepCadence: return positive(workout.averageStepCadenceSPM)
        case .cyclingCadence: return positive(workout.averageCyclingCadenceRPM)
        case .power: return positive(workout.averagePowerWatts)
        case .cardioFitness: return positive(workout.cardioFitnessVO2Max)
        case .strokeCount: return positive(workout.swimmingStrokeCount)
        // Humidity is a 0…100 percentage where zero is a real reading, so it uses
        // the bounded helper rather than the positive-only one; METs and recovery
        // are positive-only like the performance metrics above.
        case .humidity: return bounded(workout.weatherHumidityPercent, to: 0...100)
        case .averageMETs: return positive(workout.averageMETs)
        case .heartRateRecovery: return positive(workout.heartRateRecoveryBPM)
        case .pace, .swimPace, .speed:
            guard let distance = workout.distanceMeters,
                  distance >= distanceFloor(for: kind),
                  workout.duration > 0 else {
                return nil
            }
            return rateValue(for: kind, distance: distance, duration: workout.duration)
        }
    }

    private static func isRateMetric(_ kind: WorkoutDetailMetric.Kind) -> Bool {
        switch kind {
        case .pace, .swimPace, .speed: return true
        default: return false
        }
    }

    private static func distanceFloor(for kind: WorkoutDetailMetric.Kind) -> Double {
        kind == .swimPace ? minComparableSwimDistanceMeters : minComparableDistanceMeters
    }

    /// Rate as displayed: pace/swim pace are seconds per meter (lower = faster), speed is
    /// meters per second. The percentage is identical in any consistent unit.
    private static func rateValue(for kind: WorkoutDetailMetric.Kind, distance: Double, duration: Double) -> Double {
        switch kind {
        case .speed: return distance / duration
        default: return duration / distance
        }
    }

    /// Distance and duration totals over priors clearing the per-style floor — an
    /// aggregate ratio of totals, not a mean of per-workout rates (which would let a
    /// 100 m workout weigh the same as a 10 km one).
    private static func rateTotals(
        for kind: WorkoutDetailMetric.Kind,
        from priors: [WorkoutSummary]
    ) -> (distance: Double, duration: Double, count: Int) {
        let floor = distanceFloor(for: kind)
        var distance = 0.0
        var duration = 0.0
        var count = 0
        for workout in priors {
            guard let dist = workout.distanceMeters, dist >= floor, workout.duration > 0 else {
                continue
            }
            distance += dist
            duration += workout.duration
            count += 1
        }
        return (distance, duration, count)
    }

    /// The average heart rate the detail tile actually shows: the stored average, else
    /// the mean of the workout's heart-rate samples (mirrors `WorkoutDetailPresentation`'s
    /// `storedHeartRate ?? computedHeartRate`). Reading only the stored field would drop a
    /// samples-only workout from the current comparison and under-count such priors.
    /// Internal (not private) so `WorkoutEffortEstimator` scores the same average.
    static func displayedAverageHeartRate(for workout: WorkoutSummary) -> Double? {
        if let stored = workout.averageHeartRateBeatsPerMinute {
            return stored
        }
        let samples = workout.heartRateSamples ?? []
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.beatsPerMinute } / Double(samples.count)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// A finite value inside `range`, zero included — for metrics whose zero is a
    /// measurement rather than an absence (humidity).
    private static func bounded(_ value: Double?, to range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    // MARK: - Caption

    private static func caption(
        current: Double,
        baseline: Double,
        locale: Locale
    ) -> WorkoutMetricComparison? {
        // Guard near-zero baselines and non-finite results BEFORE Int(): Int(inf/NaN)
        // and abs(Int.min) trap. An unusable baseline shows no badge.
        guard current.isFinite, baseline.isFinite, abs(baseline) > 1e-9 else {
            return nil
        }
        let percent = (current - baseline) / baseline * 100
        guard percent.isFinite else {
            return nil
        }
        let clamped = max(-maxDisplayPercent, min(maxDisplayPercent, percent))
        let rounded = Int(clamped.rounded())
        if rounded == 0 {
            return WorkoutMetricComparison(
                badgeText: "≈0%",
                accessibilityLabel: String(localized: "About the same as the 30-day average", table: "BodyMetricsKit")
            )
        }
        let magnitude = BodyValueFormat.numberText(Double(abs(rounded)), decimals: 0, locale: locale)
        let arrow = rounded > 0 ? "↑" : "↓"
        let accessibilityLabel = rounded > 0
            ? String(localized: "\(magnitude) percent higher than 30-day average", table: "BodyMetricsKit")
            : String(localized: "\(magnitude) percent lower than 30-day average", table: "BodyMetricsKit")
        return WorkoutMetricComparison(
            badgeText: "\(arrow)\(magnitude)%",
            accessibilityLabel: accessibilityLabel
        )
    }
}

enum WorkoutEffortIntensity: Equatable {
    case easy
    case moderate
    case hard
    case allOut
}

struct WorkoutEffortPresentation: Equatable {
    let normalizedScore: Double
    let valueText: String
    let descriptor: String
    let intensity: WorkoutEffortIntensity
    let segmentFills: [Double]

    init?(score: Double, locale: Locale = .current) {
        guard score.isFinite else {
            return nil
        }

        let normalizedScore = min(max(score, 1), 10)
        let roundedScore = Int(normalizedScore.rounded())
        let valueText: String
        self.normalizedScore = normalizedScore

        if abs(normalizedScore - Double(roundedScore)) < 0.05 {
            valueText = "\(roundedScore)"
        } else {
            valueText = BodyValueFormat.numberText(normalizedScore, decimals: 1, locale: locale)
        }
        self.valueText = valueText

        switch normalizedScore {
        case ..<4:
            descriptor = String(localized: "Easy", table: "BodyMetricsKit")
            intensity = .easy
        case ..<7:
            descriptor = String(localized: "Moderate", table: "BodyMetricsKit")
            intensity = .moderate
        case ..<9:
            descriptor = String(localized: "Hard", table: "BodyMetricsKit")
            intensity = .hard
        default:
            descriptor = String(localized: "All Out", table: "BodyMetricsKit")
            intensity = .allOut
        }

        segmentFills = (0..<5).map { index in
            min(max((normalizedScore - Double(index * 2)) / 2, 0), 1)
        }
    }
}

struct WorkoutDetailPresentation: Equatable {
    let title: String
    let dateTitle: String
    /// The start time alone — what the detail page's header shows.
    let startTimeText: String
    /// Start-end, still used by the share card.
    let timeRangeText: String
    let durationClockText: String
    let compactDurationText: String
    let activeEnergyText: String?
    let totalEnergyText: String?
    let averageHeartRateText: String?
    let distanceText: String?
    let heroDistanceValue: String?
    let heroDistanceUnit: String?
    let effortText: String
    let effortPresentation: WorkoutEffortPresentation?
    let detailMetrics: [WorkoutDetailMetric]
    /// Drives the legend beside the "Details" heading. nil when the comparison feature
    /// is off (previews, the share card) or nothing about this workout is comparable,
    /// so those keep showing no legend at all.
    let comparisonAvailability: WorkoutMetricComparisonAvailability?
    let heartRateSamples: [WorkoutHeartRateSample]
    let sourceText: String

    init(
        workout: WorkoutSummary,
        calendar: Calendar = .bodyGregorian,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        unitPreference: BodyValueFormat.UnitPreference = .system,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference? = nil,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference = .kilocalories,
        comparisonWorkouts: [WorkoutSummary]? = nil,
        comparisonDataComplete: Bool = true,
        comparisonLoadSettled: Bool = true
    ) {
        let endDate = workout.startDate.addingTimeInterval(max(0, workout.duration))

        title = workout.type.displayName
        dateTitle = Self.formattedDate(
            workout.startDate,
            template: "EEEMMMd",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        startTimeText = Self.formattedDate(
            workout.startDate,
            template: "jm",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        timeRangeText = [
            startTimeText,
            Self.formattedDate(
                endDate,
                template: "jm",
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        ].joined(separator: "-")
        durationClockText = BodyValueFormat.stopwatchDurationText(for: workout.duration)
        compactDurationText = BodyValueFormat.durationText(for: workout.duration)
        activeEnergyText = workout.activeEnergyKilocalories.map {
            BodyValueFormat.energyText(
                kilocalories: $0,
                locale: locale,
                energyUnitPreference: energyUnitPreference
            )
        }
        totalEnergyText = workout.totalEnergyKilocalories.map {
            BodyValueFormat.energyText(
                kilocalories: $0,
                locale: locale,
                energyUnitPreference: energyUnitPreference
            )
        }
        let storedHeartRate = workout.averageHeartRateBeatsPerMinute
        let sortedHeartRateSamples = (workout.heartRateSamples ?? [])
            .sorted { $0.date < $1.date }
        let computedHeartRate = Self.averageHeartRate(from: sortedHeartRateSamples)
        averageHeartRateText = (storedHeartRate ?? computedHeartRate).map {
            BodyValueFormat.heartRateText(beatsPerMinute: $0, locale: locale)
        }
        distanceText = workout.distanceMeters.flatMap { distanceMeters in
            guard distanceMeters > 0 else {
                return nil
            }

            if let distanceUnitPreference {
                return BodyValueFormat.distanceText(
                    meters: distanceMeters,
                    locale: locale,
                    distanceUnitPreference: distanceUnitPreference
                )
            }

            return BodyValueFormat.distanceText(meters: distanceMeters, locale: locale, unitPreference: unitPreference)
        }
        sourceText = workout.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Apple Health"
            : workout.sourceName
        effortPresentation = workout.effortLevel.flatMap {
            WorkoutEffortPresentation(score: $0, locale: locale)
        }
        effortText = effortPresentation.map { "\($0.valueText) \($0.descriptor)" } ?? String(localized: "No Saved Effort", table: "BodyMetricsKit")
        heartRateSamples = sortedHeartRateSamples

        // Mirror the distance tile's resolution so pace/speed/elevation agree with
        // it: an explicit distance preference wins, else fall back to the unit
        // preference (metric/imperial/system), not to locale alone.
        let resolvedDistancePreference: BodyValueFormat.DistanceUnitPreference = distanceUnitPreference ?? {
            switch unitPreference {
            case .imperial:
                return .miles
            case .metric:
                return .kilometers
            case .system:
                return .systemValue(locale: locale)
            }
        }()
        let distanceMeters = workout.distanceMeters ?? 0
        let canDeriveDistanceRate = distanceMeters > 0 && workout.duration > 0

        // Distance-tracking activities promote distance to the hero header instead of a Details
        // tile (every paced activity plus snow sports); non-distance activities keep the tile.
        let promotesDistanceToHero = workout.type.promotesDistanceToHero && distanceMeters > 0
        let heroDistance = promotesDistanceToHero
            ? BodyValueFormat.distanceComponents(
                meters: distanceMeters,
                locale: locale,
                distanceUnitPreference: resolvedDistancePreference
              )
            : nil
        heroDistanceValue = heroDistance?.value
        heroDistanceUnit = heroDistance?.unit

        var metrics: [WorkoutDetailMetric] = []

        // Performance metrics first, then a generic Distance tile for any positive distance
        // (suppressed when distance is shown in the hero instead).
        if let distanceText, !promotesDistanceToHero {
            metrics.append(WorkoutDetailMetric(kind: .distance, title: String(localized: "Distance", table: "BodyMetricsKit"), value: distanceText))
        }
        if canDeriveDistanceRate {
            switch workout.type.paceStyle {
            case .distancePace:
                metrics.append(WorkoutDetailMetric(
                    kind: .pace,
                    title: String(localized: "Avg Pace", table: "BodyMetricsKit"),
                    value: BodyValueFormat.paceText(
                        meters: distanceMeters,
                        seconds: workout.duration,
                        distanceUnitPreference: resolvedDistancePreference,
                        locale: locale
                    )
                ))
            case .speed:
                metrics.append(WorkoutDetailMetric(
                    kind: .speed,
                    title: String(localized: "Avg Speed", table: "BodyMetricsKit"),
                    value: BodyValueFormat.speedText(
                        meters: distanceMeters,
                        seconds: workout.duration,
                        distanceUnitPreference: resolvedDistancePreference,
                        locale: locale
                    )
                ))
            case .swimPace:
                metrics.append(WorkoutDetailMetric(
                    kind: .swimPace,
                    title: String(localized: "Avg Pace", table: "BodyMetricsKit"),
                    value: BodyValueFormat.swimPaceText(
                        meters: distanceMeters,
                        seconds: workout.duration,
                        distanceUnitPreference: resolvedDistancePreference,
                        locale: locale
                    )
                ))
            case .none:
                break
            }
        }
        if let elevation = workout.elevationAscendedMeters, elevation > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .elevation,
                title: String(localized: "Elevation Gain", table: "BodyMetricsKit"),
                value: BodyValueFormat.elevationText(
                    meters: elevation,
                    distanceUnitPreference: resolvedDistancePreference,
                    locale: locale
                )
            ))
        }

        metrics.append(WorkoutDetailMetric(kind: .activeEnergy, title: String(localized: "Active \(energyUnitPreference.unitLabel)", table: "BodyMetricsKit"), value: activeEnergyText ?? String(localized: "No Data", table: "BodyMetricsKit")))
        metrics.append(WorkoutDetailMetric(kind: .totalEnergy, title: String(localized: "Total \(energyUnitPreference.unitLabel)", table: "BodyMetricsKit"), value: totalEnergyText ?? String(localized: "No Data", table: "BodyMetricsKit")))
        metrics.append(WorkoutDetailMetric(kind: .avgHeartRate, title: String(localized: "Avg Heart Rate", table: "BodyMetricsKit"), value: averageHeartRateText ?? String(localized: "No Data", table: "BodyMetricsKit")))
        if let maxHeartRate = workout.maximumHeartRateBeatsPerMinute {
            metrics.append(WorkoutDetailMetric(
                kind: .maxHeartRate,
                title: String(localized: "Max Heart Rate", table: "BodyMetricsKit"),
                value: BodyValueFormat.heartRateText(beatsPerMinute: maxHeartRate, locale: locale)
            ))
        }

        // Form metrics — best-effort, shown only when the recording source provided them.
        if let stepCadence = workout.averageStepCadenceSPM, stepCadence > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .stepCadence,
                title: String(localized: "Step Cadence", table: "BodyMetricsKit"),
                value: BodyValueFormat.cadenceText(stepCadence, unit: "spm", locale: locale)
            ))
        }
        if let cyclingCadence = workout.averageCyclingCadenceRPM, cyclingCadence > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .cyclingCadence,
                title: String(localized: "Cycling Cadence", table: "BodyMetricsKit"),
                value: BodyValueFormat.cadenceText(cyclingCadence, unit: "rpm", locale: locale)
            ))
        }
        if let power = workout.averagePowerWatts, power > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .power,
                title: String(localized: "Avg Power", table: "BodyMetricsKit"),
                value: BodyValueFormat.powerText(watts: power, locale: locale)
            ))
        }
        if let vo2Max = workout.cardioFitnessVO2Max, vo2Max > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .cardioFitness,
                title: String(localized: "Cardio Fitness", table: "BodyMetricsKit"),
                value: BodyValueFormat.vo2MaxText(vo2Max, locale: locale)
            ))
        }
        if let strokeCount = workout.swimmingStrokeCount, strokeCount > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .strokeCount,
                title: String(localized: "Swim Strokes", table: "BodyMetricsKit"),
                value: BodyValueFormat.strokeCountText(strokeCount, locale: locale)
            ))
        }

        // Session context the watch recorded alongside the workout. Weather and METs
        // come from workout metadata, so they show whenever the recording source
        // saved them — no Workout Metrics opt-in involved.
        if let humidity = workout.weatherHumidityPercent, humidity.isFinite {
            metrics.append(WorkoutDetailMetric(
                kind: .humidity,
                title: String(localized: "Humidity", table: "BodyMetricsKit"),
                value: BodyValueFormat.numberText(humidity.rounded(), decimals: 0, locale: locale) + " %"
            ))
        }
        if let averageMETs = workout.averageMETs, averageMETs > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .averageMETs,
                title: String(localized: "Avg METs", table: "BodyMetricsKit"),
                value: BodyValueFormat.numberText(averageMETs, decimals: 1, locale: locale) + " METs"
            ))
        }

        // Recovery straight from the workout's attached statistics. When it's absent
        // here (not synced yet, or no attached statistics) the detail sheet appends
        // the same tile from its lazy read instead — never both.
        if let recovery = workout.heartRateRecoveryBPM, recovery > 0 {
            metrics.append(Self.heartRateRecoveryMetric(bpm: recovery, locale: locale))
        }

        // Attach the 30-day comparison caption to each metric when comparison data was
        // provided (nil == feature off, so existing callers/previews are unchanged).
        if let comparisonWorkouts {
            let comparisons = metrics.map { metric in
                WorkoutMetricComparisonBuilder.comparison(
                    for: metric.kind,
                    current: workout,
                    priors: comparisonWorkouts,
                    isComplete: comparisonDataComplete,
                    locale: locale
                )
            }
            let availability = WorkoutMetricComparisonBuilder.availability(
                for: metrics.map(\.kind),
                current: workout,
                hasComparison: comparisons.contains { $0 != nil },
                isComplete: comparisonDataComplete,
                isSettled: comparisonLoadSettled
            )

            metrics = zip(metrics, comparisons).map { metric, comparison in
                WorkoutDetailMetric(
                    kind: metric.kind,
                    title: metric.title,
                    value: metric.value,
                    // Every comparable tile keeps a badge in every state — a measured
                    // delta, or the "0%" stand-in — so the number rolls into place when
                    // the history lands rather than popping in.
                    comparison: comparison ?? WorkoutMetricComparisonBuilder.placeholder(
                        for: metric.kind,
                        availability: availability,
                        current: workout,
                        locale: locale
                    )
                )
            }
            comparisonAvailability = availability
        } else {
            comparisonAvailability = nil
        }

        detailMetrics = metrics
    }

    /// The 1-minute heart-rate recovery tile. Built separately from `init` because
    /// the value is a follow-up HealthKit read (gated on the Heart permission), not
    /// part of the workout summary — the detail sheet appends it once it lands.
    static func heartRateRecoveryMetric(bpm: Double, locale: Locale = .current) -> WorkoutDetailMetric {
        WorkoutDetailMetric(
            kind: .heartRateRecovery,
            title: String(localized: "HR Recovery", table: "BodyMetricsKit"),
            value: BodyValueFormat.heartRateText(beatsPerMinute: bpm, locale: locale)
        )
    }

    private static func formattedDate(
        _ date: Date,
        template: String,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        BodyDateFormatterCache.formatter(
            template: template,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        ).string(from: date)
    }

    private static func averageHeartRate(from samples: [WorkoutHeartRateSample]) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }

        let total = samples.reduce(0) { $0 + $1.beatsPerMinute }
        return total / Double(samples.count)
    }

}

enum BodyValueFormat {
    enum UnitPreference: String, CaseIterable, Identifiable {
        case system
        case metric
        case imperial

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .system:
                return String(localized: "System", table: "BodyMetricsKit")
            case .metric:
                return String(localized: "Metric", table: "BodyMetricsKit")
            case .imperial:
                return String(localized: "Imperial", table: "BodyMetricsKit")
            }
        }

        var selectionSubtitle: String {
            switch self {
            case .system:
                return String(localized: "Device", table: "BodyMetricsKit")
            case .metric:
                return "kg / km"
            case .imperial:
                return "lb / mi"
            }
        }

        static let defaultValue: UnitPreference = .system

        static func storedValue(from rawValue: String) -> UnitPreference {
            UnitPreference(rawValue: rawValue) ?? defaultValue
        }
    }

    enum WeightUnitPreference: String, CaseIterable, Identifiable {
        case kilograms
        case pounds

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .kilograms:
                return String(localized: "Kilograms", table: "BodyMetricsKit")
            case .pounds:
                return String(localized: "Pounds", table: "BodyMetricsKit")
            }
        }

        var unitLabel: String {
            switch self {
            case .kilograms:
                return "kg"
            case .pounds:
                return "lb"
            }
        }

        static let defaultValue: WeightUnitPreference = .kilograms

        static func storedValue(from rawValue: String) -> WeightUnitPreference {
            WeightUnitPreference(rawValue: rawValue) ?? defaultValue
        }

        static func systemValue(locale: Locale) -> WeightUnitPreference {
            BodyValueFormat.usesImperialMeasurementSystem(locale: locale) ? .pounds : .kilograms
        }
    }

    enum DistanceUnitPreference: String, CaseIterable, Identifiable {
        case kilometers
        case miles

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .kilometers:
                return String(localized: "Kilometers", table: "BodyMetricsKit")
            case .miles:
                return String(localized: "Miles", table: "BodyMetricsKit")
            }
        }

        var unitLabel: String {
            switch self {
            case .kilometers:
                return "km"
            case .miles:
                return "mi"
            }
        }

        static let defaultValue: DistanceUnitPreference = .kilometers

        static func storedValue(from rawValue: String) -> DistanceUnitPreference {
            DistanceUnitPreference(rawValue: rawValue) ?? defaultValue
        }

        static func systemValue(locale: Locale) -> DistanceUnitPreference {
            BodyValueFormat.usesImperialMeasurementSystem(locale: locale) ? .miles : .kilometers
        }
    }

    enum EnergyUnitPreference: String, CaseIterable, Identifiable {
        case kilocalories
        case kilojoules

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .kilocalories:
                return String(localized: "Kilocalories", table: "BodyMetricsKit")
            case .kilojoules:
                return String(localized: "Kilojoules", table: "BodyMetricsKit")
            }
        }

        var unitLabel: String {
            switch self {
            case .kilocalories:
                return "kcal"
            case .kilojoules:
                return "kJ"
            }
        }

        static let defaultValue: EnergyUnitPreference = .kilocalories

        static func storedValue(from rawValue: String) -> EnergyUnitPreference {
            EnergyUnitPreference(rawValue: rawValue) ?? defaultValue
        }

        static func systemValue(locale: Locale) -> EnergyUnitPreference {
            .kilocalories
        }
    }

    enum TemperatureUnitPreference: String, CaseIterable, Identifiable {
        case celsius
        case fahrenheit

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .celsius:
                return String(localized: "Celsius", table: "BodyMetricsKit")
            case .fahrenheit:
                return String(localized: "Fahrenheit", table: "BodyMetricsKit")
            }
        }

        var unitLabel: String {
            switch self {
            case .celsius:
                return "C"
            case .fahrenheit:
                return "F"
            }
        }

        static let defaultValue: TemperatureUnitPreference = .celsius

        static func storedValue(from rawValue: String) -> TemperatureUnitPreference {
            TemperatureUnitPreference(rawValue: rawValue) ?? defaultValue
        }

        static func systemValue(locale: Locale) -> TemperatureUnitPreference {
            BodyValueFormat.usesImperialMeasurementSystem(locale: locale) ? .fahrenheit : .celsius
        }
    }

    static func durationText(for duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        return durationText(minutes: minutes)
    }

    static func sleepDurationText(for duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded(.up)))
        return durationText(minutes: minutes)
    }

    static func stopwatchDurationText(for duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }

        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// Elapsed time as a fixed-width `HH:mm:ss` clock (`00:30:31`, `01:01:02`),
    /// for chart axes where labels must stay the same width regardless of length.
    static func paddedStopwatchDurationText(for duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(
            format: "%02d:%02d:%02d",
            totalSeconds / 3_600,
            (totalSeconds % 3_600) / 60,
            totalSeconds % 60
        )
    }

    private static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0, remainingMinutes > 0 {
            return String(localized: "\(hours)h \(remainingMinutes)m", table: "BodyMetricsKit")
        } else if hours > 0 {
            return String(localized: "\(hours)h", table: "BodyMetricsKit")
        }

        return String(localized: "\(remainingMinutes)m", table: "BodyMetricsKit")
    }

    static func workoutCountText(_ count: Int) -> String {
        count == 1
            ? String(localized: "\(count) workout", table: "BodyMetricsKit")
            : String(localized: "\(count) workouts", table: "BodyMetricsKit")
    }

    static func massDisplay(
        kilograms: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system,
        decimals: Int = 1
    ) -> (value: String, unit: String) {
        let display = massValue(kilograms: kilograms, locale: locale, unitPreference: unitPreference)
        return (numberText(display.value, decimals: decimals, locale: locale), display.unit)
    }

    static func massDisplay(
        kilograms: Double,
        locale: Locale = .current,
        weightUnitPreference: WeightUnitPreference,
        decimals: Int = 1
    ) -> (value: String, unit: String) {
        let display = massValue(kilograms: kilograms, locale: locale, weightUnitPreference: weightUnitPreference)
        return (numberText(display.value, decimals: decimals, locale: locale), display.unit)
    }

    static func massValue(
        kilograms: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system
    ) -> (value: Double, unit: String) {
        massValue(
            kilograms: kilograms,
            locale: locale,
            weightUnitPreference: weightUnitPreference(from: unitPreference, locale: locale)
        )
    }

    static func massValue(
        kilograms: Double,
        locale: Locale = .current,
        weightUnitPreference: WeightUnitPreference
    ) -> (value: Double, unit: String) {
        if weightUnitPreference == .pounds {
            let pounds = Measurement(value: kilograms, unit: UnitMass.kilograms)
                .converted(to: .pounds)
                .value
            return (pounds, "lb")
        }

        return (kilograms, "kg")
    }

    static func distanceText(
        meters: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system
    ) -> String {
        distanceText(
            meters: meters,
            locale: locale,
            distanceUnitPreference: distanceUnitPreference(from: unitPreference, locale: locale)
        )
    }

    static func distanceComponents(
        meters: Double,
        locale: Locale = .current,
        distanceUnitPreference: DistanceUnitPreference
    ) -> (value: String, unit: String) {
        let unit: UnitLength = distanceUnitPreference == .miles ? .miles : .kilometers
        let converted = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: unit)
            .value
        return (numberText(converted, decimals: 2, locale: locale), distanceUnitPreference.unitLabel)
    }

    static func distanceText(
        meters: Double,
        locale: Locale = .current,
        distanceUnitPreference: DistanceUnitPreference
    ) -> String {
        let components = distanceComponents(
            meters: meters,
            locale: locale,
            distanceUnitPreference: distanceUnitPreference
        )
        return components.value + " " + components.unit
    }

    /// Average pace as M:SS per km (or per mile), from total distance and elapsed time.
    static func paceText(
        meters: Double,
        seconds: Double,
        distanceUnitPreference: DistanceUnitPreference,
        locale: Locale = .current
    ) -> String {
        guard meters > 0, seconds > 0 else { return "—" }
        let useMiles = distanceUnitPreference == .miles
        let unitMeters = useMiles ? 1_609.344 : 1_000.0
        let secondsPerUnit = seconds / (meters / unitMeters)
        return clockText(seconds: secondsPerUnit) + (useMiles ? " /mi" : " /km")
    }

    /// Average speed as km/h (or mph), from total distance and elapsed time.
    static func speedText(
        meters: Double,
        seconds: Double,
        distanceUnitPreference: DistanceUnitPreference,
        locale: Locale = .current
    ) -> String {
        guard meters > 0, seconds > 0 else { return "—" }
        let metersPerSecond = meters / seconds
        if distanceUnitPreference == .miles {
            let mph = Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
                .converted(to: .milesPerHour)
                .value
            return numberText(mph, decimals: 1, locale: locale) + " mph"
        }
        let kmh = Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .converted(to: .kilometersPerHour)
            .value
        return numberText(kmh, decimals: 1, locale: locale) + " km/h"
    }

    /// Swim pace as M:SS per 100 m (or per 100 yd).
    static func swimPaceText(
        meters: Double,
        seconds: Double,
        distanceUnitPreference: DistanceUnitPreference,
        locale: Locale = .current
    ) -> String {
        guard meters > 0, seconds > 0 else { return "—" }
        let useYards = distanceUnitPreference == .miles
        let unitMeters = useYards ? 91.44 : 100.0
        let secondsPerUnit = seconds / (meters / unitMeters)
        return clockText(seconds: secondsPerUnit) + (useYards ? " /100yd" : " /100m")
    }

    /// Elevation gain as whole meters (or feet).
    static func elevationText(
        meters: Double,
        distanceUnitPreference: DistanceUnitPreference,
        locale: Locale = .current
    ) -> String {
        if distanceUnitPreference == .miles {
            let feet = Measurement(value: meters, unit: UnitLength.meters)
                .converted(to: .feet)
                .value
            return numberText(feet.rounded(), decimals: 0, locale: locale) + " ft"
        }
        return numberText(meters.rounded(), decimals: 0, locale: locale) + " m"
    }

    static func powerText(watts: Double, locale: Locale = .current) -> String {
        numberText(watts.rounded(), decimals: 0, locale: locale) + " W"
    }

    /// Cadence with an activity-specific unit ("spm" for foot, "rpm" for cycling).
    static func cadenceText(_ cadence: Double, unit: String, locale: Locale = .current) -> String {
        numberText(cadence.rounded(), decimals: 0, locale: locale) + " " + unit
    }

    static func vo2MaxText(_ value: Double, locale: Locale = .current) -> String {
        numberText(value, decimals: 1, locale: locale) + " ml/kg·min"
    }

    static func strokeCountText(_ count: Double, locale: Locale = .current) -> String {
        numberText(count.rounded(), decimals: 0, locale: locale)
    }

    private static func clockText(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    static func energyText(
        kilocalories: Double,
        locale: Locale = .current,
        energyUnitPreference: EnergyUnitPreference = .kilocalories
    ) -> String {
        let display = energyValue(kilocalories: kilocalories, energyUnitPreference: energyUnitPreference)
        return numberText(display.value, decimals: 0, locale: locale) + " " + display.unit
    }

    static func energyValue(
        kilocalories: Double,
        energyUnitPreference: EnergyUnitPreference = .kilocalories
    ) -> (value: Double, unit: String) {
        switch energyUnitPreference {
        case .kilocalories:
            return (kilocalories, "kcal")
        case .kilojoules:
            let kilojoules = Measurement(value: kilocalories, unit: UnitEnergy.kilocalories)
                .converted(to: .kilojoules)
                .value
            return (kilojoules, "kJ")
        }
    }

    static func heartRateText(beatsPerMinute: Double, locale: Locale = .current) -> String {
        numberText(beatsPerMinute.rounded(), decimals: 0, locale: locale) + " BPM"
    }

    static func respiratoryRateText(breathsPerMinute: Double, locale: Locale = .current) -> String {
        numberText(breathsPerMinute.rounded(), decimals: 0, locale: locale) + " br/min"
    }

    static func temperatureDisplay(
        celsius: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system
    ) -> (value: String, unit: String) {
        let display = temperatureValue(celsius: celsius, locale: locale, unitPreference: unitPreference)
        return (numberText(display.value, decimals: 1, locale: locale), display.unit)
    }

    static func temperatureDisplay(
        celsius: Double,
        locale: Locale = .current,
        temperatureUnitPreference: TemperatureUnitPreference
    ) -> (value: String, unit: String) {
        let display = temperatureValue(
            celsius: celsius,
            locale: locale,
            temperatureUnitPreference: temperatureUnitPreference
        )
        return (numberText(display.value, decimals: 1, locale: locale), display.unit)
    }

    static func temperatureValue(
        celsius: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system
    ) -> (value: Double, unit: String) {
        temperatureValue(
            celsius: celsius,
            locale: locale,
            temperatureUnitPreference: temperatureUnitPreference(from: unitPreference, locale: locale)
        )
    }

    static func temperatureValue(
        celsius: Double,
        locale: Locale = .current,
        temperatureUnitPreference: TemperatureUnitPreference
    ) -> (value: Double, unit: String) {
        if temperatureUnitPreference == .fahrenheit {
            let fahrenheit = Measurement(value: celsius, unit: UnitTemperature.celsius)
                .converted(to: .fahrenheit)
                .value
            return (fahrenheit, "F")
        }

        return (celsius, "C")
    }

    /// The workout hero line's temperature, e.g. "21°C" / "70°F" — whole degrees, no
    /// space before the degree sign (the hero row is tight). `nil` for a non-finite
    /// reading so the row is simply omitted.
    static func temperatureHeroText(
        celsius: Double,
        locale: Locale = .current,
        temperatureUnitPreference: TemperatureUnitPreference
    ) -> String? {
        guard celsius.isFinite else {
            return nil
        }

        let display = temperatureValue(
            celsius: celsius,
            locale: locale,
            temperatureUnitPreference: temperatureUnitPreference
        )
        let rounded = display.value.rounded()
        // `-0.4` rounds to negative zero, which formats as "-0"; a temperature at
        // freezing reads "0°C".
        let normalized = rounded == 0 ? 0 : rounded
        return "\(numberText(normalized, decimals: 0, locale: locale))°\(display.unit)"
    }

    static func numberText(_ value: Double, decimals: Int, locale: Locale = .current) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(decimals))
                .locale(locale)
        )
    }

    private static func weightUnitPreference(from unitPreference: UnitPreference, locale: Locale) -> WeightUnitPreference {
        switch unitPreference {
        case .imperial:
            return .pounds
        case .metric:
            return .kilograms
        case .system:
            return WeightUnitPreference.systemValue(locale: locale)
        }
    }

    private static func distanceUnitPreference(from unitPreference: UnitPreference, locale: Locale) -> DistanceUnitPreference {
        switch unitPreference {
        case .imperial:
            return .miles
        case .metric:
            return .kilometers
        case .system:
            return DistanceUnitPreference.systemValue(locale: locale)
        }
    }

    private static func temperatureUnitPreference(from unitPreference: UnitPreference, locale: Locale) -> TemperatureUnitPreference {
        switch unitPreference {
        case .imperial:
            return .fahrenheit
        case .metric:
            return .celsius
        case .system:
            return TemperatureUnitPreference.systemValue(locale: locale)
        }
    }

    private static func usesImperialMeasurementSystem(locale: Locale) -> Bool {
        locale.measurementSystem == .us
    }
}
