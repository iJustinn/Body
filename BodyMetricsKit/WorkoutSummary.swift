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
    let heartRateSamples: [WorkoutHeartRateSample]?
    let elevationAscendedMeters: Double?
    let averagePowerWatts: Double?
    let averageStepCadenceSPM: Double?
    let averageCyclingCadenceRPM: Double?
    let swimmingStrokeCount: Double?
    let cardioFitnessVO2Max: Double?
    let sourceName: String

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
        heartRateSamples: [WorkoutHeartRateSample] = [],
        elevationAscendedMeters: Double? = nil,
        averagePowerWatts: Double? = nil,
        averageStepCadenceSPM: Double? = nil,
        averageCyclingCadenceRPM: Double? = nil,
        swimmingStrokeCount: Double? = nil,
        cardioFitnessVO2Max: Double? = nil,
        sourceName: String = "Apple Health"
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
        self.heartRateSamples = heartRateSamples
        self.elevationAscendedMeters = elevationAscendedMeters
        self.averagePowerWatts = averagePowerWatts
        self.averageStepCadenceSPM = averageStepCadenceSPM
        self.averageCyclingCadenceRPM = averageCyclingCadenceRPM
        self.swimmingStrokeCount = swimmingStrokeCount
        self.cardioFitnessVO2Max = cardioFitnessVO2Max
        self.sourceName = sourceName
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
    }

    let kind: Kind
    let title: String
    let value: String
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
            descriptor = "Easy"
            intensity = .easy
        case ..<7:
            descriptor = "Moderate"
            intensity = .moderate
        case ..<9:
            descriptor = "Hard"
            intensity = .hard
        default:
            descriptor = "All Out"
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
    let timeRangeText: String
    let durationClockText: String
    let compactDurationText: String
    let activeEnergyText: String?
    let totalEnergyText: String?
    let averageHeartRateText: String?
    let distanceText: String?
    let effortText: String
    let effortPresentation: WorkoutEffortPresentation?
    let detailMetrics: [WorkoutDetailMetric]
    let heartRateSamples: [WorkoutHeartRateSample]
    let sourceText: String

    init(
        workout: WorkoutSummary,
        calendar: Calendar = .bodyGregorian,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        unitPreference: BodyValueFormat.UnitPreference = .system,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference? = nil,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference = .kilocalories
    ) {
        let endDate = workout.startDate.addingTimeInterval(max(0, workout.duration))

        title = workout.type.displayName
        dateTitle = Self.formattedDate(
            workout.startDate,
            dateFormat: "EEE, MMM d",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        timeRangeText = [
            Self.formattedDate(
                workout.startDate,
                dateFormat: "HH:mm",
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            Self.formattedDate(
                endDate,
                dateFormat: "HH:mm",
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
        effortText = effortPresentation.map { "\($0.valueText) \($0.descriptor)" } ?? "No Saved Effort"
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

        var metrics: [WorkoutDetailMetric] = []

        // Performance metrics first, then a generic Distance tile for any positive distance.
        if let distanceText {
            metrics.append(WorkoutDetailMetric(kind: .distance, title: "Distance", value: distanceText))
        }
        if canDeriveDistanceRate {
            switch workout.type.paceStyle {
            case .distancePace:
                metrics.append(WorkoutDetailMetric(
                    kind: .pace,
                    title: "Avg Pace",
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
                    title: "Avg Speed",
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
                    title: "Avg Pace",
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
                title: "Elevation Gain",
                value: BodyValueFormat.elevationText(
                    meters: elevation,
                    distanceUnitPreference: resolvedDistancePreference,
                    locale: locale
                )
            ))
        }

        metrics.append(WorkoutDetailMetric(kind: .activeEnergy, title: "Active \(energyUnitPreference.detailTitleUnit)", value: activeEnergyText ?? "No Data"))
        metrics.append(WorkoutDetailMetric(kind: .totalEnergy, title: "Total \(energyUnitPreference.detailTitleUnit)", value: totalEnergyText ?? "No Data"))
        metrics.append(WorkoutDetailMetric(kind: .avgHeartRate, title: "Avg Heart Rate", value: averageHeartRateText ?? "No Data"))
        if let maxHeartRate = workout.maximumHeartRateBeatsPerMinute {
            metrics.append(WorkoutDetailMetric(
                kind: .maxHeartRate,
                title: "Max Heart Rate",
                value: BodyValueFormat.heartRateText(beatsPerMinute: maxHeartRate, locale: locale)
            ))
        }

        // Form metrics — best-effort, shown only when the recording source provided them.
        if let stepCadence = workout.averageStepCadenceSPM, stepCadence > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .stepCadence,
                title: "Cadence",
                value: BodyValueFormat.cadenceText(stepCadence, unit: "SPM", locale: locale)
            ))
        }
        if let cyclingCadence = workout.averageCyclingCadenceRPM, cyclingCadence > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .cyclingCadence,
                title: "Cadence",
                value: BodyValueFormat.cadenceText(cyclingCadence, unit: "RPM", locale: locale)
            ))
        }
        if let power = workout.averagePowerWatts, power > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .power,
                title: "Avg Power",
                value: BodyValueFormat.powerText(watts: power, locale: locale)
            ))
        }
        if let vo2Max = workout.cardioFitnessVO2Max, vo2Max > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .cardioFitness,
                title: "Cardio Fitness",
                value: BodyValueFormat.vo2MaxText(vo2Max, locale: locale)
            ))
        }
        if let strokeCount = workout.swimmingStrokeCount, strokeCount > 0 {
            metrics.append(WorkoutDetailMetric(
                kind: .strokeCount,
                title: "Swim Strokes",
                value: BodyValueFormat.strokeCountText(strokeCount, locale: locale)
            ))
        }

        detailMetrics = metrics
    }

    private static func formattedDate(
        _ date: Date,
        dateFormat: String,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        BodyDateFormatterCache.formatter(
            dateFormat: dateFormat,
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
                return "System"
            case .metric:
                return "Metric"
            case .imperial:
                return "Imperial"
            }
        }

        var selectionSubtitle: String {
            switch self {
            case .system:
                return "Device"
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
                return "Kilograms"
            case .pounds:
                return "Pounds"
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
                return "Kilometers"
            case .miles:
                return "Miles"
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
                return "Kilocalories"
            case .kilojoules:
                return "Kilojoules"
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

        var detailTitleUnit: String {
            switch self {
            case .kilocalories:
                return "Kcal"
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
                return "Celsius"
            case .fahrenheit:
                return "Fahrenheit"
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

    private static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0, remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        }

        return "\(remainingMinutes)m"
    }

    static func workoutCountText(_ count: Int) -> String {
        let label = count == 1 ? "workout" : "workouts"
        return "\(count) \(label)"
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

    static func distanceText(
        meters: Double,
        locale: Locale = .current,
        distanceUnitPreference: DistanceUnitPreference
    ) -> String {
        if distanceUnitPreference == .miles {
            let miles = Measurement(value: meters, unit: UnitLength.meters)
                .converted(to: .miles)
                .value
            return numberText(miles, decimals: 1, locale: locale) + " mi"
        }

        let kilometers = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: .kilometers)
            .value
        return numberText(kilometers, decimals: 1, locale: locale) + " km"
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

    /// Cadence with an activity-specific unit ("SPM" for foot, "RPM" for cycling).
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
