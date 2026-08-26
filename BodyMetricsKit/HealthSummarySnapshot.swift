//
//  HealthSummarySnapshot.swift
//  Body
//

import Foundation

enum HealthMetricKind: String, CaseIterable, Identifiable {
    case readiness
    case stress
    case sleep
    case basics
    case heartRate
    case restingHeartRate
    case bodyMass
    case bodyFatPercentage
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case bodyMassIndex
    case activeEnergy
    case restingEnergy
    case exerciseMinutes
    case trainingLoad
    case wristTemperature
    case timeInDaylight
    case steps
    case vitals
    case cardioFitness

    var id: String {
        rawValue
    }

    var detailHelpText: HealthMetricDetailHelpText? {
        switch self {
        case .readiness:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Readiness", table: "BodyMetricsKit"),
                body: String(localized: "Readiness combines your recent heart, sleep, training, and overnight vital signs against your own baseline. It is a readiness estimate, not a diagnosis. The strongest signal comes from sustained patterns across HRV, resting heart rate, sleep quality, and recent load rather than one isolated reading.\nToday's live score updates through the day and drops after a workout, while the trend chart keeps the value from shortly after you wake, so the current score can read lower than today's point on the chart.", table: "BodyMetricsKit")
            )
        case .stress:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Stress", table: "BodyMetricsKit"),
                body: String(localized: "Stress scores quiet moments through the day by comparing your heart rate and heart rate variability with your own baseline. The variability measure is RMSSD (root mean square of successive differences), computed from the beat to beat heartbeat recordings your Apple Watch saves, with SDNN used as a fallback when those recordings are not available. Your baseline is built from your own history using a robust median and a MAD (median absolute deviation) comparison, so a level reflects how far a moment sits from your normal rather than from anyone else. Movement drives heart rate on its own, so workouts and active stretches are masked out rather than scored, and stretches without enough heart rate data are left blank instead of counted as calm.\nIt is an estimate of physiological arousal, the load your body is under, not a measure of psychological stress, and not a diagnosis. Exercise, caffeine, illness, heat, and excitement can all raise it. It takes about two weeks of data to learn your baseline before any level appears.", table: "BodyMetricsKit")
            )
        case .sleep:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Sleep", table: "BodyMetricsKit"),
                body: String(localized: "Sleep combines your recent sleep duration, stage breakdown, and sleep score into one view. Your own baseline matters more than a single night. Use the trend to spot repeated short sleep, fragmented nights, or shifts in deep and REM sleep that may line up with stress, travel, training, or illness.", table: "BodyMetricsKit")
            )
        case .basics:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Basics", table: "BodyMetricsKit"),
                body: String(localized: "Basics tracks weight, body fat, and BMI together so changes are easier to compare in context. Daily movement can reflect hydration, meals, measurement timing, or device differences. Longer trends are usually more useful than single readings.", table: "BodyMetricsKit")
            )
        case .heartRate:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Heart Rate", table: "BodyMetricsKit"),
                body: String(localized: "Heart rate is the number of beats per minute measured throughout the day. Daily ranges can shift with sleep, workouts, stress, caffeine, illness, heat, and readiness. Compare the range with your sleep and workout timing before judging a single spike.", table: "BodyMetricsKit")
            )
        case .restingHeartRate:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Resting Heart Rate", table: "BodyMetricsKit"),
                body: String(localized: "Resting heart rate is the number of beats per minute while your body is at rest. A lower value can come with better aerobic fitness, but your own baseline matters most. Watch for sustained changes from your usual range, especially if they happen with symptoms, illness, stress, dehydration, or medication changes.", table: "BodyMetricsKit")
            )
        case .bodyMass:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Weight", table: "BodyMetricsKit"),
                body: String(localized: "Weight is your recorded body mass from Apple Health or connected devices. Short-term changes often come from hydration, food, sodium, exercise, or measurement timing. Compare readings taken under similar conditions and focus on the direction over weeks.", table: "BodyMetricsKit")
            )
        case .bodyFatPercentage:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Body Fat", table: "BodyMetricsKit"),
                body: String(localized: "Body fat percentage estimates how much of your body mass is fat tissue. Consumer scales and devices can vary with hydration, skin temperature, and measurement timing, so the trend is more useful than one reading. Compare it alongside weight and how you feel.", table: "BodyMetricsKit")
            )
        case .heartRateVariability:
            return HealthMetricDetailHelpText(
                title: String(localized: "About HRV", table: "BodyMetricsKit"),
                body: String(localized: "Heart rate variability measures the small timing changes between heartbeats. Higher than your usual baseline often points to better readiness and lower strain; lower than usual can follow hard training, poor sleep, alcohol, illness, or stress. Compare trends over weeks instead of judging one day by itself.", table: "BodyMetricsKit")
            )
        case .respiratoryRate:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Respiratory Rate", table: "BodyMetricsKit"),
                body: String(localized: "Respiratory rate is breaths per minute, often measured during sleep or quiet periods. A stable personal baseline is usually the most useful signal. Sustained increases or drops can reflect illness, altitude, stress, alcohol, or sleep disruption; check with a clinician if the change is unusual for you.", table: "BodyMetricsKit")
            )
        case .oxygenSaturation:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Blood Oxygen", table: "BodyMetricsKit"),
                body: String(localized: "Blood oxygen estimates the percentage of oxygen carried by your blood. It is usually fairly steady at rest, and fit or motion can affect readings. Repeated low readings, sudden drops, or low values with shortness of breath, chest pain, or confusion need medical attention.", table: "BodyMetricsKit")
            )
        case .bodyMassIndex:
            return HealthMetricDetailHelpText(
                title: String(localized: "About BMI", table: "BodyMetricsKit"),
                body: String(localized: "BMI is a weight-to-height calculation used as a broad screening measure. It does not distinguish fat, muscle, bone, or body shape, so it is best treated as context rather than a diagnosis. Compare it with weight, body fat, activity, and your personal goals.", table: "BodyMetricsKit")
            )
        case .activeEnergy:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Active Energy", table: "BodyMetricsKit"),
                body: String(localized: "Active Energy estimates calories you burn through movement and workouts, above your resting needs. More is not automatically better; useful context comes from matching activity to your goals and checking how sleep, appetite, soreness, and readiness respond.", table: "BodyMetricsKit")
            )
        case .restingEnergy:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Resting Energy", table: "BodyMetricsKit"),
                body: String(localized: "Resting Energy estimates calories your body uses for basic functions while minimally active. It tends to change slowly with body size, age, sex, and lean mass. Day-to-day jumps are often measurement or model changes, so treat the trend as context rather than a target.", table: "BodyMetricsKit")
            )
        case .exerciseMinutes:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Exercise Minutes", table: "BodyMetricsKit"),
                body: String(localized: "Exercise Minutes count time Apple Health classifies as brisk activity or workouts. The value can differ from workout duration because intensity, heart rate, and motion all matter. Use it to see whether your recent activity is consistently reaching meaningful effort.", table: "BodyMetricsKit")
            )
        case .trainingLoad:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Training Load", table: "BodyMetricsKit"),
                body: String(localized: "Training Load compares acute training load with chronic training load. Acute load is a 7-day exponentially weighted average of workout strain, while chronic load is a 42-day weighted average that reflects your adapted baseline. Values near 0.80-1.30 are usually the most sustainable; sustained values above that range can point to higher readiness demand.", table: "BodyMetricsKit")
            )
        case .wristTemperature:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Skin Temperature", table: "BodyMetricsKit"),
                body: String(localized: "Skin Temperature shows changes captured during sleep from supported devices. It is most useful as a trend against your own baseline. Shifts can follow room temperature, illness, alcohol, menstrual cycle changes, travel, or wearable fit.", table: "BodyMetricsKit")
            )
        case .timeInDaylight:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Time In Daylight", table: "BodyMetricsKit"),
                body: String(localized: "Time In Daylight estimates how long supported devices detected outdoor daylight exposure. Daylight can support circadian rhythm, mood, and sleep timing, but readings depend on device support and whether the device was worn.", table: "BodyMetricsKit")
            )
        case .steps:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Steps", table: "BodyMetricsKit"),
                body: String(localized: "Steps estimate your walking and running step count from Apple Health sources. Phones and wearables can count differently depending on where they are worn or carried. The trend is best used to compare your usual activity level over time.", table: "BodyMetricsKit")
            )
        case .vitals:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Vitals", table: "BodyMetricsKit"),
                body: String(localized: "Vitals reviews overnight measurements of sleeping heart rate, respiratory rate, skin temperature, blood oxygen, and sleep duration. Each one is compared against your personal typical range, learned from about eight weeks of your own sleep data. Outliers can follow illness, alcohol, travel, or hard training, and they are not a diagnosis. It takes about two weeks of sleep data to calibrate.\nVitals follows the data sources you select for Sleep and for each individual vital, so choosing a single source may limit how many nights have data and how far back the charts reach.", table: "BodyMetricsKit")
            )
        case .cardioFitness:
            return HealthMetricDetailHelpText(
                title: String(localized: "About Cardio Fitness", table: "BodyMetricsKit"),
                body: String(localized: "Cardio fitness is a measurement of your VO₂ max, the maximum amount of oxygen your body can use during exercise. It is one of the strongest single indicators of long-term health, and most people can raise it by increasing the intensity and frequency of cardiovascular exercise.\nApple Watch does not measure this continuously. It records one estimate after an Outdoor Walk, Outdoor Run, or Hike on relatively flat ground, when GPS and heart-rate signal are good and you work hard enough. Indoor and gym-equipment workouts do not count, and your first qualifying workout will not produce a reading, because Apple Watch needs about a day of wear first. That is why readings arrive every few days or weeks rather than daily, and why short ranges here are often empty.\nYour level compares your VO₂ max against people of the same age and sex, using normative data from the Fitness Registry and the Importance of Exercise National Database (FRIEND). Levels are available from age 20 through 79. Medications and conditions that limit your heart rate can cause an overestimate.", table: "BodyMetricsKit")
            )
        }
    }

    var detailDataSourceText: HealthMetricDetailDataSourceText? {
        switch self {
        case .readiness,
             .stress,
             .sleep,
             .basics,
             .heartRate,
             .restingHeartRate,
             .heartRateVariability,
             .respiratoryRate,
             .oxygenSaturation,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .steps,
             .vitals,
             .cardioFitness:
            return HealthMetricDetailDataSourceText(sourceText: "Apple Health")
        case .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex:
            return nil
        }
    }

    /// Whether this metric's trend line should plot each reading on its own day
    /// instead of averaging readings into the range's fixed buckets.
    ///
    /// Only Cardio Fitness: Apple Watch writes one VO₂ max estimate per
    /// qualifying outdoor workout, so a month often holds two readings. Bucket
    /// averaging would stamp those at the bucket's end date — up to 11 days from
    /// when they were measured on the year range — and report an average of
    /// readings that were never averaged. Every other metric here has a reading
    /// most days, where bucketing is what keeps a long range readable.
    var usesSparseTrendReadings: Bool {
        self == .cardioFitness
    }
}

struct HealthMetricDetailHelpText: Equatable {
    var title: String
    var body: String
}

struct HealthMetricDetailDataSourceText: Equatable {
    var sourceText: String
}

struct HealthSummarySnapshot: Codable, Equatable {
    var activityRings: ActivityRingSummary
    var readiness: ReadinessSummary
    var sleep: SleepSummary
    var heartRate: HealthMetricSummary
    var restingHeartRate: HealthMetricSummary
    var bodyMass: HealthMetricSummary
    var bodyFatPercentage: HealthMetricSummary
    var heartRateVariability: HealthMetricSummary
    var respiratoryRate: HealthMetricSummary
    var oxygenSaturation: HealthMetricSummary
    var bodyMassIndex: HealthMetricSummary
    var activeEnergy: HealthMetricSummary
    var restingEnergy: HealthMetricSummary
    var exerciseMinutes: HealthMetricSummary
    var trainingLoad: HealthMetricSummary
    var wristTemperature: HealthMetricSummary
    var timeInDaylight: HealthMetricSummary
    var steps: HealthMetricSummary
    var cardioFitness: HealthMetricSummary
    /// Age + sex behind the cardio fitness level, persisted with the reading so
    /// the home card can classify on cold launch before a fetch lands. `nil`
    /// when the characteristics are unreadable or the permission is off, which
    /// every band UI renders as unclassified.
    var cardioFitnessProfile: CardioFitnessProfile?
    /// Today's stress rollup, recomputed from the cached intraday samples by
    /// `HealthDashboardSnapshot.recalculatingStress`. `nil` until the quiet-HR
    /// baseline calibrates (or when the Heart permission is off).
    var stress: StressDaySummary?
    /// The most recent scored window's rounded score, when it is recent enough to
    /// still describe RIGHT NOW (`stressCurrentScoreMaxAge`). `nil` once it goes
    /// stale, so the home card falls back to the day average rather than
    /// presenting an hours-old reading as the current band.
    ///
    /// Deliberately NOT persisted (no CodingKeys entry): the value carries no
    /// timestamp, so a decoded score can't be re-checked against
    /// `stressCurrentScoreMaxAge` — a snapshot reopened hours later would present
    /// an arbitrarily old reading as current until the first recompute. It
    /// repopulates on the next `recalculatingStress`.
    var stressCurrentScore: Int?
    /// Today's earliest past-threshold episode per warning kind, fetched with the
    /// summary so the home card can flag it without the intraday samples. Kinds
    /// with nothing past their threshold today are simply absent.
    var metricWarnings: [MetricWarningEvent]

    /// Today's episode for one warning kind, if any.
    func warning(_ kind: MetricWarningKind) -> MetricWarningEvent? {
        metricWarnings.first { $0.kind == kind }
    }

    /// Swaps in a freshly detected set of warnings for one metric, leaving the
    /// other metrics' warnings untouched.
    func replacingWarnings(
        for metric: HealthMetricKind,
        with warnings: [MetricWarningEvent]
    ) -> HealthSummarySnapshot {
        var next = self
        next.metricWarnings = metricWarnings.filter { $0.kind.metric != metric } + warnings
        return next
    }

    init(
        activityRings: ActivityRingSummary,
        readiness: ReadinessSummary = .unavailable,
        sleep: SleepSummary,
        heartRate: HealthMetricSummary = HealthMetricSummary(value: nil),
        restingHeartRate: HealthMetricSummary,
        bodyMass: HealthMetricSummary,
        bodyFatPercentage: HealthMetricSummary,
        heartRateVariability: HealthMetricSummary,
        respiratoryRate: HealthMetricSummary,
        oxygenSaturation: HealthMetricSummary,
        bodyMassIndex: HealthMetricSummary,
        activeEnergy: HealthMetricSummary,
        restingEnergy: HealthMetricSummary,
        exerciseMinutes: HealthMetricSummary = HealthMetricSummary(value: nil),
        trainingLoad: HealthMetricSummary = HealthMetricSummary(value: nil),
        wristTemperature: HealthMetricSummary = HealthMetricSummary(value: nil),
        timeInDaylight: HealthMetricSummary = HealthMetricSummary(value: nil),
        steps: HealthMetricSummary = HealthMetricSummary(value: nil),
        cardioFitness: HealthMetricSummary = HealthMetricSummary(value: nil),
        cardioFitnessProfile: CardioFitnessProfile? = nil,
        stress: StressDaySummary? = nil,
        stressCurrentScore: Int? = nil,
        metricWarnings: [MetricWarningEvent] = []
    ) {
        self.activityRings = activityRings
        self.readiness = readiness
        self.sleep = sleep
        self.heartRate = heartRate
        self.restingHeartRate = restingHeartRate
        self.bodyMass = bodyMass
        self.bodyFatPercentage = bodyFatPercentage
        self.heartRateVariability = heartRateVariability
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.bodyMassIndex = bodyMassIndex
        self.activeEnergy = activeEnergy
        self.restingEnergy = restingEnergy
        self.exerciseMinutes = exerciseMinutes
        self.trainingLoad = trainingLoad
        self.wristTemperature = wristTemperature
        self.timeInDaylight = timeInDaylight
        self.steps = steps
        self.cardioFitness = cardioFitness
        self.cardioFitnessProfile = cardioFitnessProfile
        self.stress = stress
        self.stressCurrentScore = stressCurrentScore
        self.metricWarnings = metricWarnings
    }

    var isEmpty: Bool {
        activityRings.isEmpty &&
            readiness.score == nil &&
            sleep.duration == nil &&
            sleep.stageSnapshot.isEmpty &&
            sleep.vitals.isEmpty &&
            heartRate.value == nil &&
            restingHeartRate.value == nil &&
            bodyMass.value == nil &&
            bodyFatPercentage.value == nil &&
            heartRateVariability.value == nil &&
            respiratoryRate.value == nil &&
            oxygenSaturation.value == nil &&
            bodyMassIndex.value == nil &&
            activeEnergy.value == nil &&
            restingEnergy.value == nil &&
            exerciseMinutes.value == nil &&
            trainingLoad.value == nil &&
            wristTemperature.value == nil &&
            timeInDaylight.value == nil &&
            steps.value == nil &&
            // Deliberately the VO₂ value only, never `cardioFitnessProfile`:
            // this gates first-load behavior, and age + sex alone is
            // demographics, not dashboard data the user can read.
            cardioFitness.value == nil &&
            stress == nil &&
            stressCurrentScore == nil
    }

    static let empty = HealthSummarySnapshot(
        activityRings: .empty,
        readiness: .unavailable,
        sleep: SleepSummary(duration: nil),
        heartRate: HealthMetricSummary(value: nil),
        restingHeartRate: HealthMetricSummary(value: nil),
        bodyMass: HealthMetricSummary(value: nil),
        bodyFatPercentage: HealthMetricSummary(value: nil),
        heartRateVariability: HealthMetricSummary(value: nil),
        respiratoryRate: HealthMetricSummary(value: nil),
        oxygenSaturation: HealthMetricSummary(value: nil),
        bodyMassIndex: HealthMetricSummary(value: nil),
        activeEnergy: HealthMetricSummary(value: nil),
        restingEnergy: HealthMetricSummary(value: nil),
        exerciseMinutes: HealthMetricSummary(value: nil),
        trainingLoad: HealthMetricSummary(value: nil),
        wristTemperature: HealthMetricSummary(value: nil),
        timeInDaylight: HealthMetricSummary(value: nil),
        steps: HealthMetricSummary(value: nil),
        cardioFitness: HealthMetricSummary(value: nil),
        cardioFitnessProfile: nil
    )

    static let placeholder = HealthSummarySnapshot(
        activityRings: ActivityRingSummary(
            move: ActivityRingMetric(value: 670, goal: 500),
            exercise: ActivityRingMetric(value: 76, goal: 40),
            stand: ActivityRingMetric(value: 8, goal: 10)
        ),
        readiness: ReadinessSummary(
            score: 82,
            status: .high,
            confidence: .medium,
            components: [
                ReadinessComponent(
                    kind: .autonomic,
                    score: 88,
                    weight: 30,
                    message: String(localized: "Heart signals compared with your baseline.", table: "BodyMetricsKit")
                ),
                ReadinessComponent(
                    kind: .sleep,
                    score: 78,
                    weight: 30,
                    message: String(localized: "Sleep amount and continuity.", table: "BodyMetricsKit")
                ),
                ReadinessComponent(
                    kind: .training,
                    score: 86,
                    weight: 25,
                    message: String(localized: "Recent load relative to your longer baseline.", table: "BodyMetricsKit")
                )
            ],
            drivers: [
                ReadinessDriver(
                    kind: .mostlyTypical,
                    message: String(localized: "Readiness signals are mostly typical.", table: "BodyMetricsKit"),
                    impact: 0
                )
            ]
        ),
        sleep: SleepSummary(
            duration: 28_740,
            vitals: SleepVitalsSummary(
                heartRate: 58,
                heartRateVariability: 62,
                respiratoryRate: 14,
                oxygenSaturation: 97,
                wristTemperatureCelsius: 36.4
            )
        ),
        heartRate: HealthMetricSummary(value: 82),
        restingHeartRate: HealthMetricSummary(value: 60),
        bodyMass: HealthMetricSummary(value: 69.3),
        bodyFatPercentage: HealthMetricSummary(value: 13.1),
        heartRateVariability: HealthMetricSummary(value: 38.4),
        respiratoryRate: HealthMetricSummary(value: 14),
        oxygenSaturation: HealthMetricSummary(value: 97),
        bodyMassIndex: HealthMetricSummary(value: 22.1),
        activeEnergy: HealthMetricSummary(value: 520),
        restingEnergy: HealthMetricSummary(value: 1_690),
        exerciseMinutes: HealthMetricSummary(value: 77),
        trainingLoad: HealthMetricSummary(value: 1.08),
        wristTemperature: HealthMetricSummary(value: 36.4),
        timeInDaylight: HealthMetricSummary(value: 32),
        steps: HealthMetricSummary(value: 1_212),
        cardioFitness: HealthMetricSummary(value: 40.1),
        cardioFitnessProfile: CardioFitnessProfile(ageYears: 34, sex: .male)
    )

    private enum CodingKeys: String, CodingKey {
        case activityRings
        case readiness
        case sleep
        case heartRate
        case restingHeartRate
        case bodyMass
        case bodyFatPercentage
        case heartRateVariability
        case respiratoryRate
        case oxygenSaturation
        case bodyMassIndex
        case activeEnergy
        case restingEnergy
        case exerciseMinutes
        case trainingLoad
        case wristTemperature
        case timeInDaylight
        case steps
        case cardioFitness
        case cardioFitnessProfile
        case stress
        case metricWarnings
    }

    /// Snapshots written before `metricWarnings` carried the low heart rate
    /// episode under its own key. Read-only: new saves write `metricWarnings`.
    private enum LegacyCodingKeys: String, CodingKey {
        case lowHeartRateEvent
    }

    private struct LegacyLowHeartRateEvent: Decodable {
        var startDate: Date
        var endDate: Date
        var minimumBPM: Double
        var sampleCount: Int
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityRings = (try? container.decodeIfPresent(ActivityRingSummary.self, forKey: .activityRings)) ?? .empty
        readiness = (try? container.decodeIfPresent(ReadinessSummary.self, forKey: .readiness)) ?? .unavailable
        sleep = (try? container.decodeIfPresent(SleepSummary.self, forKey: .sleep)) ?? SleepSummary(duration: nil)
        heartRate = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .heartRate) ?? HealthMetricSummary(value: nil)
        restingHeartRate = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .restingHeartRate) ?? HealthMetricSummary(value: nil)
        bodyMass = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .bodyMass) ?? HealthMetricSummary(value: nil)
        bodyFatPercentage = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .bodyFatPercentage) ?? HealthMetricSummary(value: nil)
        heartRateVariability = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .heartRateVariability) ?? HealthMetricSummary(value: nil)
        respiratoryRate = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .respiratoryRate) ?? HealthMetricSummary(value: nil)
        oxygenSaturation = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .oxygenSaturation) ?? HealthMetricSummary(value: nil)
        bodyMassIndex = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .bodyMassIndex) ?? HealthMetricSummary(value: nil)
        activeEnergy = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .activeEnergy) ?? HealthMetricSummary(value: nil)
        restingEnergy = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .restingEnergy) ?? HealthMetricSummary(value: nil)
        exerciseMinutes = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .exerciseMinutes) ?? HealthMetricSummary(value: nil)
        trainingLoad = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .trainingLoad) ?? HealthMetricSummary(value: nil)
        wristTemperature = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .wristTemperature) ?? HealthMetricSummary(value: nil)
        timeInDaylight = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .timeInDaylight) ?? HealthMetricSummary(value: nil)
        steps = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .steps) ?? HealthMetricSummary(value: nil)
        cardioFitness = try container.decodeIfPresent(HealthMetricSummary.self, forKey: .cardioFitness) ?? HealthMetricSummary(value: nil)
        cardioFitnessProfile = try container.decodeIfPresent(CardioFitnessProfile.self, forKey: .cardioFitnessProfile)
        stress = try container.decodeIfPresent(StressDaySummary.self, forKey: .stress)
        // `stressCurrentScore` is transient — see its declaration.
        stressCurrentScore = nil
        if let warnings = try container.decodeIfPresent([MetricWarningEvent].self, forKey: .metricWarnings) {
            metricWarnings = warnings
        } else {
            let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let legacy = try legacyContainer.decodeIfPresent(LegacyLowHeartRateEvent.self, forKey: .lowHeartRateEvent)
            metricWarnings = legacy.map {
                [MetricWarningEvent(
                    kind: .lowHeartRate,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    extremeValue: $0.minimumBPM,
                    sampleCount: $0.sampleCount
                )]
            } ?? []
        }
    }

    func filtered(by selection: BodyHealthPermissionSelection) -> HealthSummarySnapshot {
        var filtered = self

        if !selection.includes(.activityRings) {
            filtered.activityRings = .empty
        }
        if !selection.includes(.sleep) {
            filtered.sleep = HealthSummarySnapshot.empty.sleep
        }
        if !selection.includes(.heart) {
            filtered.heartRate = HealthSummarySnapshot.empty.heartRate
            filtered.restingHeartRate = HealthSummarySnapshot.empty.restingHeartRate
            filtered.heartRateVariability = HealthSummarySnapshot.empty.heartRateVariability
            filtered.sleep.vitals.heartRate = nil
            filtered.sleep.vitals.heartRateVariability = nil
            filtered.metricWarnings.removeAll { $0.kind.metric == .heartRate }
            // Stress is heart-derived end to end (quiet HR + HRV), so it rides
            // the Heart toggle with no permission of its own.
            filtered.stress = nil
            filtered.stressCurrentScore = nil
        }
        if !selection.includes(.workouts) {
            // Warnings that exclude in-workout readings need workout coverage;
            // without it a cached one would keep the Home glyph up unrefreshed.
            filtered.metricWarnings.removeAll(where: \.kind.excludesWorkouts)
        }
        if !selection.includes(.basics) {
            filtered.bodyMass = HealthSummarySnapshot.empty.bodyMass
            filtered.bodyFatPercentage = HealthSummarySnapshot.empty.bodyFatPercentage
            filtered.bodyMassIndex = HealthSummarySnapshot.empty.bodyMassIndex
        }
        if !selection.includes(.bloodOxygen) {
            filtered.oxygenSaturation = HealthSummarySnapshot.empty.oxygenSaturation
            filtered.sleep.vitals.oxygenSaturation = nil
            filtered.metricWarnings.removeAll { $0.kind.metric == .oxygenSaturation }
        }
        if !selection.includes(.respiratory) {
            filtered.respiratoryRate = HealthSummarySnapshot.empty.respiratoryRate
            filtered.sleep.vitals.respiratoryRate = nil
        }
        if !selection.includes(.energy) {
            filtered.activeEnergy = HealthSummarySnapshot.empty.activeEnergy
            filtered.restingEnergy = HealthSummarySnapshot.empty.restingEnergy
        }
        if !selection.includes(.exerciseMinutes) {
            filtered.exerciseMinutes = HealthSummarySnapshot.empty.exerciseMinutes
        }
        if !selection.includes(.workouts) {
            filtered.trainingLoad = HealthSummarySnapshot.empty.trainingLoad
        }
        if !selection.includes(.wristTemperature) {
            filtered.wristTemperature = HealthSummarySnapshot.empty.wristTemperature
            filtered.sleep.vitals.wristTemperatureCelsius = nil
        }
        if !selection.includes(.timeInDaylight) {
            filtered.timeInDaylight = HealthSummarySnapshot.empty.timeInDaylight
        }
        if !selection.includes(.steps) {
            filtered.steps = HealthSummarySnapshot.empty.steps
        }
        if !selection.includes(.cardioFitness) {
            // The profile is demographics read solely to classify this metric,
            // so it clears with the reading — a revoke must never leave age and
            // sex behind on their own.
            filtered.cardioFitness = HealthSummarySnapshot.empty.cardioFitness
            filtered.cardioFitnessProfile = HealthSummarySnapshot.empty.cardioFitnessProfile
        }

        return filtered
    }

    func replacingMetric(_ kind: HealthMetricKind, with refreshed: HealthSummarySnapshot) -> HealthSummarySnapshot {
        var next = self

        switch kind {
        case .readiness:
            next.readiness = refreshed.readiness
        case .stress:
            next.stress = refreshed.stress
            next.stressCurrentScore = refreshed.stressCurrentScore
        case .sleep:
            next.sleep = refreshed.sleep
        case .basics:
            next.bodyMass = refreshed.bodyMass
            next.bodyFatPercentage = refreshed.bodyFatPercentage
            next.bodyMassIndex = refreshed.bodyMassIndex
        case .heartRate:
            next.heartRate = refreshed.heartRate
            next = next.replacingWarnings(
                for: .heartRate,
                with: refreshed.metricWarnings.filter { $0.kind.metric == .heartRate }
            )
        case .restingHeartRate:
            next.restingHeartRate = refreshed.restingHeartRate
        case .bodyMass:
            next.bodyMass = refreshed.bodyMass
        case .bodyFatPercentage:
            next.bodyFatPercentage = refreshed.bodyFatPercentage
        case .heartRateVariability:
            next.heartRateVariability = refreshed.heartRateVariability
        case .respiratoryRate:
            next.respiratoryRate = refreshed.respiratoryRate
        case .oxygenSaturation:
            next.oxygenSaturation = refreshed.oxygenSaturation
            next = next.replacingWarnings(
                for: .oxygenSaturation,
                with: refreshed.metricWarnings.filter { $0.kind.metric == .oxygenSaturation }
            )
        case .bodyMassIndex:
            next.bodyMassIndex = refreshed.bodyMassIndex
        case .activeEnergy:
            next.activeEnergy = refreshed.activeEnergy
        case .restingEnergy:
            next.restingEnergy = refreshed.restingEnergy
        case .exerciseMinutes:
            next.exerciseMinutes = refreshed.exerciseMinutes
        case .trainingLoad:
            next.trainingLoad = refreshed.trainingLoad
        case .wristTemperature:
            next.wristTemperature = refreshed.wristTemperature
        case .timeInDaylight:
            next.timeInDaylight = refreshed.timeInDaylight
        case .steps:
            next.steps = refreshed.steps
        case .vitals:
            next.sleep = refreshed.sleep
        case .cardioFitness:
            // Reading and profile move together: a value classified against a
            // stale age or sex is worse than an unclassified one.
            next.cardioFitness = refreshed.cardioFitness
            next.cardioFitnessProfile = refreshed.cardioFitnessProfile
        }

        return next
    }
}

// Activity Rings models live in `Body/Models/ActivityRings.swift`.

// Sleep models (summary, stages, vitals, score) live in
// `Body/Models/Sleep.swift`.

struct HealthMetricSummary: Codable, Equatable {
    var value: Double?
    /// The `endDate` of the sample behind `value`, for latest-sample headline
    /// metrics (HR, Resting HR, HRV) — the value's EVENT watermark, carried so
    /// the watch merge can compare measurements event-to-event instead of
    /// against the phone's query time (which, under HealthKit replication lag,
    /// rejects a genuinely newer reading that synced only to the watch). nil
    /// for aggregate-style metrics and snapshots persisted before this field.
    var measuredAt: Date? = nil
}

struct HealthDashboardSnapshot: Codable, Equatable {
    /// Bumped when the persisted shape changes in a way that requires a
    /// migration on load. Optional on decode so existing on-disk snapshots
    /// (which predate this field) load as `nil` and are treated as the
    /// implicit baseline ("v0 / unversioned"). New saves write the current
    /// value. When the structure evolves, branch on `schemaVersion` in
    /// `init(from:)` to migrate.
    static let currentSchemaVersion = 2

    var summary: HealthSummarySnapshot
    var trends: HealthTrendSnapshot
    var activityRingHistory: ActivityRingHistorySnapshot
    var schemaVersion: Int?

    init(
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        activityRingHistory: ActivityRingHistorySnapshot = .empty,
        schemaVersion: Int? = HealthDashboardSnapshot.currentSchemaVersion
    ) {
        self.summary = summary
        self.trends = trends
        self.activityRingHistory = activityRingHistory
        self.schemaVersion = schemaVersion
    }

    static let empty = HealthDashboardSnapshot(
        summary: .empty,
        trends: .empty,
        activityRingHistory: .empty
    )

    var isEmpty: Bool {
        summary.isEmpty && trends.isEmpty && activityRingHistory.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case trends
        case activityRingHistory
        case schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(HealthSummarySnapshot.self, forKey: .summary)
        trends = try container.decode(HealthTrendSnapshot.self, forKey: .trends)
        activityRingHistory = try container.decodeIfPresent(
            ActivityRingHistorySnapshot.self,
            forKey: .activityRingHistory
        ) ?? .empty
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
    }

    func filtered(
        by selection: BodyHealthPermissionSelection,
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration,
        recordedReadinessContext: String? = nil
    ) -> HealthDashboardSnapshot {
        filteredWithoutReadinessRecompute(by: selection)
            .recalculatingReadiness(
                idealSleepDuration: idealSleepDuration,
                calendar: .bodyGregorian,
                recordedReadinessContext: recordedReadinessContext
            )
    }

    func filteredWithoutReadinessRecompute(by selection: BodyHealthPermissionSelection) -> HealthDashboardSnapshot {
        HealthDashboardSnapshot(
            summary: summary.filtered(by: selection),
            trends: trends.filtered(by: selection),
            activityRingHistory: selection.includes(.activityRings) ? activityRingHistory : .empty
        )
    }

    /// Recomputes readiness end to end: today's live tile (`summary.readiness`)
    /// and the full history series (`trends.readiness`).
    ///
    /// The live tile = a fresh recompute **minus** the same-day activity drain
    /// (display only). The history series prefers the frozen morning record per
    /// day, falling back to the deterministic recompute where no record exists.
    /// When `freezesRecordedReadiness` is set and the wake+10 window is open, the
    /// day's undrained morning score is frozen once into `trends.recordedReadiness`.
    /// A record frozen before today's sleep synced (no `.sleep` component) is
    /// replaced once, same-day, by the first score that includes one; nil-flag
    /// legacy records are upgradeable the same way. Once a record carries sleep it
    /// is never replaced again.
    func recalculatingReadiness(
        on date: Date = Date(),
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration,
        calendar: Calendar = .bodyGregorian,
        todaysWorkouts: [WorkoutSummary] = [],
        wakeTime: Date? = nil,
        now: Date = Date(),
        freezesRecordedReadiness: Bool = false,
        recordedReadinessContext: String? = nil
    ) -> HealthDashboardSnapshot {
        var next = self
        let scoreDay = calendar.startOfDay(for: date)

        // Drop frozen records captured under a different readiness input context
        // (a permission, source, or grouping change). The signature persists with
        // the records, so this also fires once on the first recompute after the
        // context changed while the app was backgrounded or a refresh failed.
        if let recordedReadinessContext, next.trends.recordedReadinessContext != recordedReadinessContext {
            next.trends.recordedReadiness = []
            next.trends.recordedReadinessContext = recordedReadinessContext
        }

        // Fresh, undrained recompute of today's summary.
        let undrained = ReadinessScoreCalculator.summary(
            on: date,
            healthSummary: next.summary,
            trends: next.trends,
            idealSleepDuration: idealSleepDuration,
            calendar: calendar,
            today: now
        )

        // Freeze the morning record from the UNDRAINED score, before any drain.
        next.trends.recordedReadiness = Self.freezingRecordedReadiness(
            next.trends.recordedReadiness,
            undrainedScore: undrained.score,
            coverage: next.readinessCoverage(on: date, calendar: calendar, today: now),
            scoreDay: scoreDay,
            wakeTime: wakeTime,
            now: now,
            freezes: freezesRecordedReadiness,
            calendar: calendar
        )

        // Live tile = undrained − same-day activity drain (display only).
        next.summary.readiness = Self.draining(undrained, with: todaysWorkouts)

        // History series: deterministic recompute overlaid with frozen records.
        let oldestTrendDate = next.trends.readinessSourceSeries.compactMap { series in
            series.points.map { calendar.startOfDay(for: $0.date) }.min()
        }.min()
        let startDate = oldestTrendDate ?? scoreDay
        next.trends.readiness = ReadinessScoreCalculator.dailySeries(
            healthSummary: next.summary,
            trends: next.trends,
            startDate: startDate,
            endDate: scoreDay,
            idealSleepDuration: idealSleepDuration,
            calendar: calendar,
            today: now
        ).applyingRecordedOverrides(next.trends.recordedReadiness, calendar: calendar)

        next.trends.recordedReadiness = Self.pruningRecordedReadiness(
            next.trends.recordedReadiness,
            before: scoreDay,
            calendar: calendar
        )
        return next
    }

    /// Lightweight re-application of the morning freeze + activity drain WITHOUT
    /// rebuilding the full daily series. Used after the workout fetch lands so the
    /// live tile reflects today's just-fetched workouts (the main recompute at the
    /// start of a refresh runs before workouts are available). Re-overlays the
    /// frozen records onto the existing history series.
    func reapplyingActivityReadiness(
        on date: Date = Date(),
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration,
        calendar: Calendar = .bodyGregorian,
        todaysWorkouts: [WorkoutSummary] = [],
        wakeTime: Date? = nil,
        now: Date = Date(),
        freezesRecordedReadiness: Bool = false,
        recordedReadinessContext: String? = nil
    ) -> HealthDashboardSnapshot {
        var next = self
        let scoreDay = calendar.startOfDay(for: date)

        if let recordedReadinessContext, next.trends.recordedReadinessContext != recordedReadinessContext {
            next.trends.recordedReadiness = []
            next.trends.recordedReadinessContext = recordedReadinessContext
        }

        let undrained = ReadinessScoreCalculator.summary(
            on: date,
            healthSummary: next.summary,
            trends: next.trends,
            idealSleepDuration: idealSleepDuration,
            calendar: calendar,
            today: now
        )
        next.trends.recordedReadiness = Self.freezingRecordedReadiness(
            next.trends.recordedReadiness,
            undrainedScore: undrained.score,
            coverage: next.readinessCoverage(on: date, calendar: calendar, today: now),
            scoreDay: scoreDay,
            wakeTime: wakeTime,
            now: now,
            freezes: freezesRecordedReadiness,
            calendar: calendar
        )
        next.summary.readiness = Self.draining(undrained, with: todaysWorkouts)
        next.trends.readiness = next.trends.readiness.applyingRecordedOverrides(
            next.trends.recordedReadiness,
            calendar: calendar
        )
        next.trends.recordedReadiness = Self.pruningRecordedReadiness(
            next.trends.recordedReadiness,
            before: scoreDay,
            calendar: calendar
        )
        return next
    }

    /// How far back the intraday day-sample cache is scanned for stress days.
    /// The cache itself reaches ~32 days (`intradayDaySampleInterval`); the
    /// slightly wider bound keeps the scan whole-day aligned. Bounds the whole
    /// recompute at ≤ 34 days × ≤ 100 windows, inside the refresh deadline.
    private static let stressComputedDayLimit = 34
    /// Recorded days outlive the day-sample cache and carry the baseline
    /// aggregates, so they are kept far longer — but still pruned. Wide enough
    /// for the Year chart (365 days) plus a baseline halo of older days, which
    /// is what lets the progressive history backfill score its oldest year day
    /// against real prior history rather than leaving it uncalibrated.
    static let stressRecordedDayRetention = 400

    /// First day the per-refresh recompute covers. The history backfill stops
    /// here: everything from this day on is rescanned from the intraday cache on
    /// every refresh, so walking into it would only overwrite richer records
    /// (the backfill fetches no beat-to-beat RMSSD) with poorer ones.
    static func stressComputedWindowStart(scoreDay: Date, calendar: Calendar) -> Date {
        calendar.date(
            byAdding: .day,
            value: -(stressComputedDayLimit - 1),
            to: calendar.startOfDay(for: scoreDay)
        ) ?? calendar.startOfDay(for: scoreDay)
    }

    /// Recomputes Stress end to end: today's rollup (`summary.stress`), the daily
    /// history series (`trends.stress`), and the recorded per-day entries whose
    /// baseline aggregates outlive the ~32-day intraday day-sample cache.
    ///
    /// `workouts` is passed explicitly — the snapshot holds no workout months,
    /// as with `recalculatingReadiness(todaysWorkouts:)`. Stress needs them
    /// across the whole scanned window rather than just today: workouts are the
    /// fine activity mask, and a masked window is never scored.
    ///
    /// Baseline inputs are reduced ONCE into a single `StressDailySeriesContext`
    /// (quiet-HR medians: recorded days unioned with freshly computed ones, fresh
    /// winning; SDNN from the long-range daily series; RMSSD from recorded daily
    /// medians unioned with the beat-to-beat day samples), then every scanned day
    /// is scored against it.
    func recalculatingStress(
        on date: Date = Date(),
        workouts: [WorkoutSummary] = [],
        calendar: Calendar = .bodyGregorian,
        now: Date = Date(),
        recordedStressContext: String? = nil
    ) -> HealthDashboardSnapshot {
        var next = self
        let scoreDay = calendar.startOfDay(for: date)

        // Recorded days captured under different inputs (a permission or source
        // change) no longer describe the same signal, so drop them. The signature
        // persists with the records, so this also fires on the first recompute
        // after a context change that happened while a refresh was failing.
        if let recordedStressContext, next.trends.recordedStressContext != recordedStressContext {
            next.trends.recordedStressDays = []
            next.trends.recordedStressContext = recordedStressContext
            // The backfill's marker describes the days it just dropped, so it
            // has to go with them: leaving it behind would report a completed
            // history walk over records that no longer exist.
            next.trends.stressBackfillScannedThrough = nil
            next.trends.stressBackfillComplete = false
        }

        let inputs = next.stressDayInputs(through: scoreDay, workouts: workouts, calendar: calendar)
        guard !inputs.isEmpty || !next.trends.recordedStressDays.isEmpty else {
            next.summary.stress = nil
            next.summary.stressCurrentScore = nil
            next.trends.stress = .empty
            next.trends.stressRanges = .empty
            return next
        }

        // Every scanned day is analysed exactly once here; the quiet-HR prepass,
        // the day summaries, and today's current reading all read that one scan.
        let analyses = inputs.map { StressDayAnalysis(input: $0, calendar: calendar, now: now) }
        let context = StressDailySeriesContext(
            quietHeartRateDailyMedians: Self.stressQuietHeartRateDailyMedians(
                recorded: next.trends.recordedStressDays,
                computed: analyses,
                calendar: calendar
            ),
            sdnnSamples: next.trends.heartRateVariability.points,
            rmssdSamples: Self.stressRMSSDDailyMedians(
                recorded: next.trends.recordedStressDays,
                daySamples: next.trends.heartbeatRMSSDDaySamples,
                calendar: calendar
            ),
            calendar: calendar
        )

        // Freshly computed days replace their recorded counterparts same-day;
        // every other day comes from the records.
        let summaries = StressScoreCalculator.daySummaries(
            recorded: next.trends.recordedStressDays,
            computedWindowDays: analyses,
            context: context,
            calendar: calendar
        )

        next.trends.recordedStressDays = Self.pruningRecordedStressDays(summaries, before: scoreDay, calendar: calendar)
        // Built from the merged summaries rather than a second `dailySeries` call
        // so the windows are scored exactly once per recompute.
        Self.applyStressSeries(to: &next.trends, calendar: calendar)
        next.summary.stress = next.trends.recordedStressDays.last {
            calendar.startOfDay(for: $0.date) == scoreDay
        }
        next.summary.stressCurrentScore = analyses
            .first { $0.date == scoreDay }
            .flatMap {
                Self.stressCurrentScore(
                    windows: $0.windows(baselines: context.baselines(for: scoreDay)),
                    now: now
                )
            }

        return next
    }

    /// A reading older than this is history, not "right now": the home card must
    /// not present it as the current band. Four 15-minute windows.
    static let stressCurrentScoreMaxAge: TimeInterval = 60 * 60

    /// The latest scored window's rounded score, or `nil` when that window ended
    /// more than `stressCurrentScoreMaxAge` ago (the watch came off, a long
    /// masked stretch, or the app is being opened on a stale cache).
    private static func stressCurrentScore(windows: [StressWindow], now: Date) -> Int? {
        guard let latest = windows.last(where: \.isScored),
              let score = latest.score,
              now.timeIntervalSince(latest.interval.end) <= stressCurrentScoreMaxAge else {
            return nil
        }

        return Int(score.rounded())
    }

    /// Recorded days older than `stressRecordedDayRetention` dropped, sorted.
    private static func pruningRecordedStressDays(
        _ summaries: [StressDaySummary],
        before scoreDay: Date,
        calendar: Calendar
    ) -> [StressDaySummary] {
        let cutoff = calendar.date(byAdding: .day, value: -stressRecordedDayRetention, to: scoreDay) ?? scoreDay
        return summaries
            .filter { calendar.startOfDay(for: $0.date) >= cutoff }
            .sorted { $0.date < $1.date }
    }

    /// Rebuilds `stress` and `stressRanges` from `recordedStressDays`. They are
    /// separate stored fields, so anything that changes the records — the
    /// per-refresh recompute and the history backfill alike — has to run this or
    /// the charts keep rendering the previous set of days.
    private static func applyStressSeries(to trends: inout HealthTrendSnapshot, calendar: Calendar) {
        trends.stress = HealthTrendSeries(
            points: trends.recordedStressDays.compactMap { summary in
                summary.averageScore.map {
                    HealthTrendDataPoint(date: calendar.startOfDay(for: summary.date), value: Double($0))
                }
            }
        )
        // Range points only for days with a scored min and max — a day with
        // neither never contributes a zero-width band.
        trends.stressRanges = HealthTrendRangeSeries(
            points: trends.recordedStressDays.compactMap { summary -> HealthTrendRangeDataPoint? in
                guard let minScore = summary.minScore, let maxScore = summary.maxScore else {
                    return nil
                }

                return HealthTrendRangeDataPoint(
                    date: calendar.startOfDay(for: summary.date),
                    lowValue: Double(minScore),
                    highValue: Double(maxScore),
                    averageValue: summary.averageScore.map(Double.init)
                )
            }
        )
    }

    // MARK: - History backfill

    /// The baseline context one chunk of the progressive history backfill scores
    /// against: exactly the reduction `recalculatingStress` performs, with the
    /// chunk's own days folded into the quiet-HR medians.
    ///
    /// Folding the whole chunk in at once is what makes the FORWARD walk work.
    /// `robustBaseline` only ever reads values dated strictly before the day it
    /// is scoring, so a chunk's later days score against its earlier ones while
    /// its earlier days score against the records the previous chunks left
    /// behind — and never against days that are still in the future for them.
    ///
    /// SDNN comes from the year-long daily series already in the trends (the
    /// backfill's transient per-chunk samples would only ever bootstrap 30 days
    /// of it). RMSSD baselines stay live-window only: backfilled days carry no
    /// beat-to-beat medians, so historical days score on HR + SDNN.
    func stressBackfillContext(
        chunkInputs: [StressDayInput],
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> StressDailySeriesContext {
        stressBackfillContext(
            chunkAnalyses: chunkInputs.map { StressDayAnalysis(input: $0, calendar: calendar, now: now) },
            calendar: calendar
        )
    }

    /// The analysis-taking form the backfill itself uses: the chunk's days are
    /// scanned once and the same analyses go on to be summarised.
    func stressBackfillContext(
        chunkAnalyses: [StressDayAnalysis],
        calendar: Calendar = .bodyGregorian
    ) -> StressDailySeriesContext {
        StressDailySeriesContext(
            quietHeartRateDailyMedians: Self.stressQuietHeartRateDailyMedians(
                recorded: trends.recordedStressDays,
                computed: chunkAnalyses,
                calendar: calendar
            ),
            sdnnSamples: trends.heartRateVariability.points,
            rmssdSamples: Self.stressRMSSDDailyMedians(
                recorded: trends.recordedStressDays,
                daySamples: trends.heartbeatRMSSDDaySamples,
                calendar: calendar
            ),
            calendar: calendar
        )
    }

    /// Folds one backfilled chunk into the snapshot: recorded days upserted (a
    /// day the live recompute already owns is left alone — it was scored with
    /// beat-to-beat RMSSD this walk does not fetch), the two stress series
    /// rebuilt from the result, and the walk marker advanced.
    ///
    /// One call so the store publishes and persists all three together: a marker
    /// that outran its records would leave a permanent hole in the history.
    /// Never touches `summary.stress` — the backfill only ever scores days older
    /// than the live computed window.
    func mergingStressBackfillChunk(
        _ summaries: [StressDaySummary],
        scannedThrough: Date,
        complete: Bool,
        on date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> HealthDashboardSnapshot {
        var next = self
        var summariesByDay: [Date: StressDaySummary] = [:]
        for summary in summaries {
            summariesByDay[calendar.startOfDay(for: summary.date)] = summary
        }
        for entry in next.trends.recordedStressDays {
            summariesByDay[calendar.startOfDay(for: entry.date)] = entry
        }

        next.trends.recordedStressDays = Self.pruningRecordedStressDays(
            Array(summariesByDay.values),
            before: calendar.startOfDay(for: date),
            calendar: calendar
        )
        Self.applyStressSeries(to: &next.trends, calendar: calendar)
        next.trends.stressBackfillScannedThrough = scannedThrough
        next.trends.stressBackfillComplete = complete
        return next
    }

    /// Intraday Stress windows for one calendar day, scored against the same
    /// baseline context `recalculatingStress` uses. Read-only — unlike
    /// `recalculatingStress` it never mutates `trends.recordedStressDays` — so
    /// the detail day view can call it freely for whichever day is selected,
    /// including one outside the ~34-day computed window (which simply scores
    /// no windows, same as a day with no heart-rate coverage at all).
    func stressWindows(
        for day: Date,
        workouts: [WorkoutSummary] = [],
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> [StressWindow] {
        let scoreDay = calendar.startOfDay(for: now)
        let inputs = stressDayInputs(through: scoreDay, workouts: workouts, calendar: calendar)
        let analyses = inputs.map { StressDayAnalysis(input: $0, calendar: calendar, now: now) }
        guard let analysis = analyses.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) else {
            return []
        }

        let context = StressDailySeriesContext(
            quietHeartRateDailyMedians: Self.stressQuietHeartRateDailyMedians(
                recorded: trends.recordedStressDays,
                computed: analyses,
                calendar: calendar
            ),
            sdnnSamples: trends.heartRateVariability.points,
            rmssdSamples: Self.stressRMSSDDailyMedians(
                recorded: trends.recordedStressDays,
                daySamples: trends.heartbeatRMSSDDaySamples,
                calendar: calendar
            ),
            calendar: calendar
        )

        return analysis.windows(baselines: context.baselines(for: day))
    }

    /// One quiet-HR median per distinct day. Recorded days carry the history
    /// (the day samples only reach ~32 days back); a freshly computed day wins,
    /// because its samples may have grown since the record was written.
    ///
    /// Takes analyses, not inputs: the median must be the one the day's own
    /// summary records, and a recompute here would both rescan the day and let
    /// the two drift apart.
    private static func stressQuietHeartRateDailyMedians(
        recorded: [StressDaySummary],
        computed: [StressDayAnalysis],
        calendar: Calendar
    ) -> [ReadinessScoreCalculator.DailyValue] {
        var mediansByDay: [Date: Double] = [:]
        for entry in recorded {
            guard let median = entry.quietHRMedian else {
                continue
            }
            mediansByDay[calendar.startOfDay(for: entry.date)] = median
        }
        for analysis in computed {
            guard let median = analysis.quietHRMedian else {
                continue
            }
            mediansByDay[analysis.date] = median
        }

        return mediansByDay
            .map { ReadinessScoreCalculator.DailyValue(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// The same union for RMSSD: persisted daily medians extended by whatever the
    /// beat-to-beat day samples currently hold, the fresh samples winning.
    private static func stressRMSSDDailyMedians(
        recorded: [StressDaySummary],
        daySamples: HealthTrendSeries,
        calendar: Calendar
    ) -> [HealthTrendDataPoint] {
        var mediansByDay: [Date: Double] = [:]
        for entry in recorded {
            guard let median = entry.rmssdDailyMedian else {
                continue
            }
            mediansByDay[calendar.startOfDay(for: entry.date)] = median
        }
        for value in StressScoreCalculator.dailyMedians(of: daySamples.points, calendar: calendar) {
            mediansByDay[calendar.startOfDay(for: value.date)] = value.value
        }

        return mediansByDay
            .map { HealthTrendDataPoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// One `StressDayInput` per scanned calendar day that actually has heart-rate
    /// coverage — days without it would only produce empty window scans.
    private func stressDayInputs(
        through scoreDay: Date,
        workouts: [WorkoutSummary],
        calendar: Calendar
    ) -> [StressDayInput] {
        let windowStart = Self.stressComputedWindowStart(scoreDay: scoreDay, calendar: calendar)
        let heartRateByDay = Self.stressPointsByDay(
            trends.heartRateDaySamples.points,
            from: windowStart,
            through: scoreDay,
            calendar: calendar
        )
        guard !heartRateByDay.isEmpty else {
            return []
        }

        let sdnnByDay = Self.stressPointsByDay(
            trends.heartRateVariabilityDaySamples.points,
            from: windowStart,
            through: scoreDay,
            calendar: calendar
        )
        let rmssdByDay = Self.stressPointsByDay(
            trends.heartbeatRMSSDDaySamples.points,
            from: windowStart,
            through: scoreDay,
            calendar: calendar
        )
        let stepsByDay = Self.stressPointsByDay(
            trends.stepsDaySamples.points,
            from: windowStart,
            through: scoreDay,
            calendar: calendar
        )
        let energyByDay = Self.stressPointsByDay(
            trends.activeEnergyDaySamples.points,
            from: windowStart,
            through: scoreDay,
            calendar: calendar
        )
        let workoutsByDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.startDate) }

        return heartRateByDay.keys.sorted().map { day in
            // A session started before midnight still masks the next day's first
            // windows, so each day also takes the previous day's workouts.
            let previousDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let dayWorkouts = (workoutsByDay[day] ?? []) + (workoutsByDay[previousDay] ?? [])

            return StressDayInput(
                date: day,
                heartRateSamples: heartRateByDay[day] ?? [],
                sdnnSamples: sdnnByDay[day] ?? [],
                rmssdSamples: rmssdByDay[day] ?? [],
                hourlySteps: stepsByDay[day] ?? [],
                hourlyActiveEnergy: energyByDay[day] ?? [],
                workoutIntervals: StressDayInput.workoutIntervals(for: dayWorkouts),
                sleepInterval: stressSleepInterval(on: day, scoreDay: scoreDay, calendar: calendar)
            )
        }
    }

    /// The day's main sleep session — rest context only. Today's session has not
    /// reached the sleep history yet, so it comes off the live summary.
    private func stressSleepInterval(on day: Date, scoreDay: Date, calendar: Calendar) -> DateInterval? {
        if let recorded = trends.sleepHistory.summary(on: day, calendar: calendar)?.summary
            .stageSnapshot.mainSessionInterval {
            return recorded
        }

        return day == scoreDay ? summary.sleep.stageSnapshot.mainSessionInterval : nil
    }

    private static func stressPointsByDay(
        _ points: [HealthTrendDataPoint],
        from windowStart: Date,
        through scoreDay: Date,
        calendar: Calendar
    ) -> [Date: [HealthTrendDataPoint]] {
        var byDay: [Date: [HealthTrendDataPoint]] = [:]
        for point in points where point.value.isFinite {
            let day = calendar.startOfDay(for: point.date)
            guard day >= windowStart, day <= scoreDay else {
                continue
            }
            byDay[day, default: []].append(point)
        }

        return byDay
    }

    /// The atomic readiness inputs present for `date`, used to compare the
    /// richness of two same-day frozen readiness records (H11). Component kinds
    /// (`.autonomic`/`.sleep`/`.vitals`) stay identical while HRV, resting HR,
    /// sleep continuity, or an individual vital arrive late, so coverage tracks
    /// the finer, per-input presence instead.
    ///
    /// Each input mirrors the value `ReadinessScoreCalculator` reads for the
    /// score day: the whole-day metric (top-level summary field or that day's
    /// trend point) unioned with the overnight reading (the resolved sleep
    /// summary's vitals). Presence — not baseline sufficiency — is what matters,
    /// since a late-arriving reading is exactly the H11 upgrade signal.
    func readinessCoverage(on date: Date, calendar: Calendar, today: Date = Date()) -> ReadinessCoverage {
        let resolvedSleep = trends.sleepHistory.summary(on: date, calendar: calendar)?.summary
            ?? currentDaySleepInput(for: date, today: today, calendar: calendar)
        let overnightVitals = resolvedSleep?.vitals

        var coverage: ReadinessCoverage = []
        if summary.heartRateVariability.value != nil
            || overnightVitals?.heartRateVariability != nil
            || hasTrendValue(trends.heartRateVariability, on: date, calendar: calendar) {
            coverage.insert(.hrv)
        }
        if summary.restingHeartRate.value != nil
            || overnightVitals?.heartRate != nil
            || hasTrendValue(trends.restingHeartRate, on: date, calendar: calendar) {
            coverage.insert(.restingHeartRate)
        }
        if let duration = resolvedSleep?.duration, duration > 0 {
            coverage.insert(.sleepDuration)
        }
        if resolvedSleep?.stageSnapshot.dateInterval != nil {
            coverage.insert(.sleepContinuity)
        }
        if summary.trainingLoad.value != nil
            || hasTrendValue(trends.trainingLoad, on: date, calendar: calendar) {
            coverage.insert(.trainingLoad)
        }
        if summary.respiratoryRate.value != nil
            || overnightVitals?.respiratoryRate != nil
            || hasTrendValue(trends.respiratoryRate, on: date, calendar: calendar) {
            coverage.insert(.respiratoryRate)
        }
        if summary.oxygenSaturation.value != nil
            || overnightVitals?.oxygenSaturation != nil
            || hasTrendValue(trends.oxygenSaturation, on: date, calendar: calendar) {
            coverage.insert(.oxygenSaturation)
        }
        if summary.wristTemperature.value != nil
            || overnightVitals?.wristTemperatureCelsius != nil
            || hasTrendValue(trends.wristTemperature, on: date, calendar: calendar) {
            coverage.insert(.wristTemperature)
        }
        return coverage
    }

    /// Today's sleep summary when it applies to `date`, mirroring the gating in
    /// `ReadinessScoreCalculator.currentDaySleepSummary`.
    private func currentDaySleepInput(for date: Date, today: Date, calendar: Calendar) -> SleepSummary? {
        let sleep = summary.sleep
        guard sleep.duration != nil || !sleep.stageSnapshot.isEmpty || !sleep.vitals.isEmpty else {
            return nil
        }
        if let stageDate = sleep.stageSnapshot.date {
            return calendar.isDate(stageDate, inSameDayAs: date) ? sleep : nil
        }
        return calendar.isDate(date, inSameDayAs: today) ? sleep : nil
    }

    private func hasTrendValue(
        _ series: HealthTrendSeries,
        on date: Date,
        calendar: Calendar
    ) -> Bool {
        series.points.contains { calendar.isDate($0.date, inSameDayAs: date) && $0.value.isFinite }
    }

    /// Freezes today's morning record when freezing is enabled, the score exists,
    /// and `now` is within the freeze window `[freezeMoment, end of scoreDay]`.
    /// `freezeMoment` is `wake + 10 min`, or 10:00 local on the score day when wake
    /// is unknown.
    ///
    /// With no record for the day, appends one tagged with the atomic readiness
    /// inputs (`coverage`) that were present. When a new-format record already
    /// exists, it is replaced same-day only by a score whose coverage is a strict
    /// superset — i.e. a genuinely richer read once a late input (e.g. HRV or sleep
    /// continuity) syncs. A legacy record (nil coverage) preserves the original
    /// one-shot sleep upgrade: replaced once by the first sleep-inclusive score if
    /// it was frozen without sleep; coverage is never fabricated from the legacy
    /// `includedSleep` flag (a legacy record may already carry other inputs).
    private static func freezingRecordedReadiness(
        _ records: [RecordedReadinessEntry],
        undrainedScore: Int?,
        coverage: ReadinessCoverage,
        scoreDay: Date,
        wakeTime: Date?,
        now: Date,
        freezes: Bool,
        calendar: Calendar
    ) -> [RecordedReadinessEntry] {
        guard freezes, let score = undrainedScore else {
            return records
        }

        let freezeMoment: Date
        if let wakeTime {
            freezeMoment = wakeTime.addingTimeInterval(600)
        } else {
            freezeMoment = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: scoreDay) ?? scoreDay
        }
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: scoreDay)
            ?? scoreDay.addingTimeInterval(86_400)
        guard now >= freezeMoment, now < windowEnd else {
            return records
        }

        let includesSleep = coverage.contains(.sleepDuration)
        let replacement = RecordedReadinessEntry(
            date: scoreDay,
            score: score,
            includedSleep: includesSleep,
            coverage: coverage
        )

        var updated = records
        if let index = updated.firstIndex(where: { calendar.startOfDay(for: $0.date) == scoreDay }) {
            let existing = updated[index]
            if let existingCoverage = existing.coverage {
                // New-format record: replace only when strictly richer, so a late
                // input upgrades the day while an equal or poorer read is ignored.
                if coverage.isStrictSuperset(of: existingCoverage) {
                    updated[index] = replacement
                }
            } else if existing.includedSleep != true, includesSleep {
                // Legacy record: preserve the original one-shot sleep upgrade.
                updated[index] = replacement
            }
        } else {
            updated.append(replacement)
        }
        return updated
    }

    /// Returns the summary with the same-day activity drain subtracted from the live
    /// score. The very low end is softened (`ActivityReadinessImpact.displayedScore`):
    /// once the raw score reaches 0 we show 5% and ease toward 0% only past a −25
    /// deficit, capped so drain never lifts an already-low baseline. Status recomputed.
    /// Display only. `internal` (not `private`) so tests can exercise the cap directly.
    static func draining(
        _ summary: ReadinessSummary,
        with workouts: [WorkoutSummary]
    ) -> ReadinessSummary {
        guard let score = summary.score else {
            return summary
        }
        let drain = ActivityReadinessImpact.drainPoints(workouts: workouts)
        guard drain >= 0.5 else {
            return summary
        }
        var drained = summary
        // Soften the very low end: once the raw (possibly negative) score reaches 0 we
        // show 5% and ease 1% per further 5% of deficit, hitting 0% only at −25 or lower.
        // Cap at the undrained score so drain can never lift an already-low baseline.
        let roundedDrain = Int(drain.rounded())
        let raw = score - roundedDrain
        let newScore = min(score, ActivityReadinessImpact.displayedScore(forRawScore: raw))
        drained.score = newScore
        drained.status = ReadinessStatus.status(for: newScore)
        // Record the pre-drain score (for the pre-drain band) and the actual drain magnitude,
        // so the hero sizes the drop from the real effort even when the display clamps the score
        // (a hard session on an already-low morning would otherwise look like a light activity).
        drained.activityDrainMorningScore = score
        drained.activityDrainPoints = roundedDrain
        return drained
    }

    /// Drops records older than the chart's reach (~450 days) to bound growth.
    private static func pruningRecordedReadiness(
        _ records: [RecordedReadinessEntry],
        before scoreDay: Date,
        calendar: Calendar
    ) -> [RecordedReadinessEntry] {
        let cutoff = calendar.date(byAdding: .day, value: -450, to: scoreDay) ?? scoreDay
        return records.filter { calendar.startOfDay(for: $0.date) >= cutoff }
    }
}


// Trend models (HealthTrendSnapshot, HealthTrendSeries / Range / Calendar /
// Hourly variants, BasicsTrendSummary, HealthTrendDataPoint) live in
// `Body/Models/HealthTrend.swift`.
