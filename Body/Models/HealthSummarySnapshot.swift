//
//  HealthSummarySnapshot.swift
//  Body
//

import Foundation

enum HealthMetricKind: String, CaseIterable, Identifiable {
    case readiness
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

    var id: String {
        rawValue
    }

    var detailHelpText: HealthMetricDetailHelpText? {
        switch self {
        case .readiness:
            return HealthMetricDetailHelpText(
                title: "About Readiness",
                body: "Readiness combines your recent heart, sleep, training, and overnight vital signs against your own baseline. It is a readiness estimate, not a diagnosis. The strongest signal comes from sustained patterns across HRV, resting heart rate, sleep quality, and recent load rather than one isolated reading."
            )
        case .sleep:
            return HealthMetricDetailHelpText(
                title: "About Sleep",
                body: "Sleep combines your recent sleep duration, stage breakdown, and sleep score into one view. Your own baseline matters more than a single night. Use the trend to spot repeated short sleep, fragmented nights, or shifts in deep and REM sleep that may line up with stress, travel, training, or illness."
            )
        case .basics:
            return HealthMetricDetailHelpText(
                title: "About Basics",
                body: "Basics tracks weight, body fat, and BMI together so changes are easier to compare in context. Daily movement can reflect hydration, meals, measurement timing, or device differences. Longer trends are usually more useful than single readings."
            )
        case .heartRate:
            return HealthMetricDetailHelpText(
                title: "About Heart Rate",
                body: "Heart rate is the number of beats per minute measured throughout the day. Daily ranges can shift with sleep, workouts, stress, caffeine, illness, heat, and readiness. Compare the range with your sleep and workout timing before judging a single spike."
            )
        case .restingHeartRate:
            return HealthMetricDetailHelpText(
                title: "About Resting Heart Rate",
                body: "Resting heart rate is the number of beats per minute while your body is at rest. A lower value can come with better aerobic fitness, but your own baseline matters most. Watch for sustained changes from your usual range, especially if they happen with symptoms, illness, stress, dehydration, or medication changes."
            )
        case .bodyMass:
            return HealthMetricDetailHelpText(
                title: "About Weight",
                body: "Weight is your recorded body mass from Apple Health or connected devices. Short-term changes often come from hydration, food, sodium, exercise, or measurement timing. Compare readings taken under similar conditions and focus on the direction over weeks."
            )
        case .bodyFatPercentage:
            return HealthMetricDetailHelpText(
                title: "About Body Fat",
                body: "Body fat percentage estimates how much of your body mass is fat tissue. Consumer scales and devices can vary with hydration, skin temperature, and measurement timing, so the trend is more useful than one reading. Compare it alongside weight and how you feel."
            )
        case .heartRateVariability:
            return HealthMetricDetailHelpText(
                title: "About HRV",
                body: "Heart rate variability measures the small timing changes between heartbeats. Higher than your usual baseline often points to better readiness and lower strain; lower than usual can follow hard training, poor sleep, alcohol, illness, or stress. Compare trends over weeks instead of judging one day by itself."
            )
        case .respiratoryRate:
            return HealthMetricDetailHelpText(
                title: "About Respiratory Rate",
                body: "Respiratory rate is breaths per minute, often measured during sleep or quiet periods. A stable personal baseline is usually the most useful signal. Sustained increases or drops can reflect illness, altitude, stress, alcohol, or sleep disruption; check with a clinician if the change is unusual for you."
            )
        case .oxygenSaturation:
            return HealthMetricDetailHelpText(
                title: "About Blood Oxygen",
                body: "Blood oxygen estimates the percentage of oxygen carried by your blood. It is usually fairly steady at rest, and fit or motion can affect readings. Repeated low readings, sudden drops, or low values with shortness of breath, chest pain, or confusion need medical attention."
            )
        case .bodyMassIndex:
            return HealthMetricDetailHelpText(
                title: "About BMI",
                body: "BMI is a weight-to-height calculation used as a broad screening measure. It does not distinguish fat, muscle, bone, or body shape, so it is best treated as context rather than a diagnosis. Compare it with weight, body fat, activity, and your personal goals."
            )
        case .activeEnergy:
            return HealthMetricDetailHelpText(
                title: "About Active Energy",
                body: "Active Energy estimates calories you burn through movement and workouts, above your resting needs. More is not automatically better; useful context comes from matching activity to your goals and checking how sleep, appetite, soreness, and readiness respond."
            )
        case .restingEnergy:
            return HealthMetricDetailHelpText(
                title: "About Resting Energy",
                body: "Resting Energy estimates calories your body uses for basic functions while minimally active. It tends to change slowly with body size, age, sex, and lean mass. Day-to-day jumps are often measurement or model changes, so treat the trend as context rather than a target."
            )
        case .exerciseMinutes:
            return HealthMetricDetailHelpText(
                title: "About Exercise Minutes",
                body: "Exercise Minutes count time Apple Health classifies as brisk activity or workouts. The value can differ from workout duration because intensity, heart rate, and motion all matter. Use it to see whether your recent activity is consistently reaching meaningful effort."
            )
        case .trainingLoad:
            return HealthMetricDetailHelpText(
                title: "About Training Load",
                body: "Training Load compares acute training load with chronic training load. Acute load is a 7-day exponentially weighted average of workout strain, while chronic load is a 42-day weighted average that reflects your adapted baseline. Values near 0.80-1.30 are usually the most sustainable; sustained values above that range can point to higher readiness demand."
            )
        case .wristTemperature:
            return HealthMetricDetailHelpText(
                title: "About Wrist Temperature",
                body: "Wrist Temperature shows changes captured during sleep from supported devices. It is most useful as a trend against your own baseline. Shifts can follow room temperature, illness, alcohol, menstrual cycle changes, travel, or wearable fit."
            )
        case .timeInDaylight:
            return HealthMetricDetailHelpText(
                title: "About Time In Daylight",
                body: "Time In Daylight estimates how long supported devices detected outdoor daylight exposure. Daylight can support circadian rhythm, mood, and sleep timing, but readings depend on device support and whether the device was worn."
            )
        case .steps:
            return HealthMetricDetailHelpText(
                title: "About Steps",
                body: "Steps estimate your walking and running step count from Apple Health sources. Phones and wearables can count differently depending on where they are worn or carried. The trend is best used to compare your usual activity level over time."
            )
        }
    }

    var detailDataSourceText: HealthMetricDetailDataSourceText? {
        switch self {
        case .readiness,
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
             .steps:
            return HealthMetricDetailDataSourceText(sourceText: "Apple Health")
        case .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex:
            return nil
        }
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
        steps: HealthMetricSummary = HealthMetricSummary(value: nil)
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
            steps.value == nil
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
        steps: HealthMetricSummary(value: nil)
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
                    message: "Heart signals compared with your baseline."
                ),
                ReadinessComponent(
                    kind: .sleep,
                    score: 78,
                    weight: 30,
                    message: "Sleep amount and continuity."
                ),
                ReadinessComponent(
                    kind: .training,
                    score: 86,
                    weight: 25,
                    message: "Recent load relative to your longer baseline."
                )
            ],
            drivers: [
                ReadinessDriver(
                    kind: .mostlyTypical,
                    message: "Readiness signals are mostly typical.",
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
        steps: HealthMetricSummary(value: 1_212)
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityRings = (try? container.decodeIfPresent(ActivityRingSummary.self, forKey: .activityRings)) ?? .empty
        readiness = try container.decodeIfPresent(ReadinessSummary.self, forKey: .readiness) ?? .unavailable
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
        }
        if !selection.includes(.basics) {
            filtered.bodyMass = HealthSummarySnapshot.empty.bodyMass
            filtered.bodyFatPercentage = HealthSummarySnapshot.empty.bodyFatPercentage
            filtered.bodyMassIndex = HealthSummarySnapshot.empty.bodyMassIndex
        }
        if !selection.includes(.bloodOxygen) {
            filtered.oxygenSaturation = HealthSummarySnapshot.empty.oxygenSaturation
            filtered.sleep.vitals.oxygenSaturation = nil
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

        return filtered
    }

    func replacingMetric(_ kind: HealthMetricKind, with refreshed: HealthSummarySnapshot) -> HealthSummarySnapshot {
        var next = self

        switch kind {
        case .readiness:
            next.readiness = refreshed.readiness
        case .sleep:
            next.sleep = refreshed.sleep
        case .basics:
            next.bodyMass = refreshed.bodyMass
            next.bodyFatPercentage = refreshed.bodyFatPercentage
            next.bodyMassIndex = refreshed.bodyMassIndex
        case .heartRate:
            next.heartRate = refreshed.heartRate
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
        }

        return next
    }
}

// Activity Rings models live in `Body/Models/ActivityRings.swift`.

// Sleep models (summary, stages, vitals, score) live in
// `Body/Models/Sleep.swift`.

struct HealthMetricSummary: Codable, Equatable {
    var value: Double?
}

struct HealthDashboardSnapshot: Codable, Equatable {
    /// Bumped when the persisted shape changes in a way that requires a
    /// migration on load. Optional on decode so existing on-disk snapshots
    /// (which predate this field) load as `nil` and are treated as the
    /// implicit baseline ("v0 / unversioned"). New saves write the current
    /// value. When the structure evolves, branch on `schemaVersion` in
    /// `init(from:)` to migrate.
    static let currentSchemaVersion = 1

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
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration
    ) -> HealthDashboardSnapshot {
        filteredWithoutReadinessRecompute(by: selection)
            .recalculatingReadiness(idealSleepDuration: idealSleepDuration, calendar: .bodyGregorian)
    }

    func filteredWithoutReadinessRecompute(by selection: BodyHealthPermissionSelection) -> HealthDashboardSnapshot {
        HealthDashboardSnapshot(
            summary: summary.filtered(by: selection),
            trends: trends.filtered(by: selection),
            activityRingHistory: selection.includes(.activityRings) ? activityRingHistory : .empty
        )
    }

    func recalculatingReadiness(
        on date: Date = Date(),
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration,
        calendar: Calendar = .bodyGregorian
    ) -> HealthDashboardSnapshot {
        var next = self
        next.summary.readiness = ReadinessScoreCalculator.summary(
            on: date,
            healthSummary: next.summary,
            trends: next.trends,
            idealSleepDuration: idealSleepDuration,
            calendar: calendar
        )

        let scoreDay = calendar.startOfDay(for: date)
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
            calendar: calendar
        )

        return next
    }
}

struct HealthTrendSnapshot: Codable, Equatable {
    var sleep: HealthTrendSeries
    var sleepSecondary: HealthTrendSeries
    var readiness: HealthTrendSeries
    var heartRate: HealthTrendSeries
    var heartRateRanges: HealthTrendRangeSeries
    var heartRateRangesSecondary: HealthTrendRangeSeries
    var restingHeartRate: HealthTrendSeries
    var restingHeartRateSecondary: HealthTrendSeries
    var bodyMass: HealthTrendSeries
    var bodyFatPercentage: HealthTrendSeries
    var heartRateVariability: HealthTrendSeries
    var heartRateVariabilityRanges: HealthTrendRangeSeries
    var heartRateVariabilityRangesSecondary: HealthTrendRangeSeries
    var respiratoryRate: HealthTrendSeries
    var respiratoryRateRanges: HealthTrendRangeSeries
    var oxygenSaturation: HealthTrendSeries
    var oxygenSaturationRanges: HealthTrendRangeSeries
    var oxygenSaturationRangesSecondary: HealthTrendRangeSeries
    var bodyMassIndex: HealthTrendSeries
    var activeEnergy: HealthTrendSeries
    var activeEnergySecondary: HealthTrendSeries
    var restingEnergy: HealthTrendSeries
    var restingEnergySecondary: HealthTrendSeries
    var exerciseMinutes: HealthTrendSeries
    var exerciseMinutesSecondary: HealthTrendSeries
    var trainingLoad: HealthTrendSeries
    var wristTemperature: HealthTrendSeries
    var timeInDaylight: HealthTrendSeries
    var steps: HealthTrendSeries
    var stepsSecondary: HealthTrendSeries
    var sleepHistory: SleepHistorySnapshot
    var heartRateDaySamples: HealthTrendSeries
    var heartRateDaySamplesSecondary: HealthTrendSeries
    var restingHeartRateDaySamples: HealthTrendSeries
    var restingHeartRateDaySamplesSecondary: HealthTrendSeries
    var heartRateVariabilityDaySamples: HealthTrendSeries
    var heartRateVariabilityDaySamplesSecondary: HealthTrendSeries
    var respiratoryRateDaySamples: HealthTrendSeries
    var oxygenSaturationDaySamples: HealthTrendSeries
    var oxygenSaturationDaySamplesSecondary: HealthTrendSeries
    var activeEnergyDaySamples: HealthTrendSeries
    var activeEnergyDaySamplesSecondary: HealthTrendSeries
    var stepsDaySamples: HealthTrendSeries
    var stepsDaySamplesSecondary: HealthTrendSeries

    static let empty = HealthTrendSnapshot(
        sleep: .empty,
        sleepSecondary: .empty,
        readiness: .empty,
        heartRate: .empty,
        heartRateRanges: .empty,
        heartRateRangesSecondary: .empty,
        restingHeartRate: .empty,
        restingHeartRateSecondary: .empty,
        bodyMass: .empty,
        bodyFatPercentage: .empty,
        heartRateVariability: .empty,
        heartRateVariabilityRanges: .empty,
        heartRateVariabilityRangesSecondary: .empty,
        respiratoryRate: .empty,
        respiratoryRateRanges: .empty,
        oxygenSaturation: .empty,
        oxygenSaturationRanges: .empty,
        oxygenSaturationRangesSecondary: .empty,
        bodyMassIndex: .empty,
        activeEnergy: .empty,
        activeEnergySecondary: .empty,
        restingEnergy: .empty,
        restingEnergySecondary: .empty,
        exerciseMinutes: .empty,
        exerciseMinutesSecondary: .empty,
        trainingLoad: .empty,
        wristTemperature: .empty,
        timeInDaylight: .empty,
        steps: .empty,
        stepsSecondary: .empty,
        sleepHistory: .empty,
        heartRateDaySamples: .empty,
        heartRateDaySamplesSecondary: .empty,
        restingHeartRateDaySamples: .empty,
        restingHeartRateDaySamplesSecondary: .empty,
        heartRateVariabilityDaySamples: .empty,
        heartRateVariabilityDaySamplesSecondary: .empty,
        respiratoryRateDaySamples: .empty,
        oxygenSaturationDaySamples: .empty,
        oxygenSaturationDaySamplesSecondary: .empty,
        activeEnergyDaySamples: .empty,
        activeEnergyDaySamplesSecondary: .empty,
        stepsDaySamples: .empty,
        stepsDaySamplesSecondary: .empty
    )

    var isEmpty: Bool {
        sleep.isEmpty &&
            sleepSecondary.isEmpty &&
            readiness.isEmpty &&
            heartRate.isEmpty &&
            heartRateRanges.isEmpty &&
            heartRateRangesSecondary.isEmpty &&
            restingHeartRate.isEmpty &&
            restingHeartRateSecondary.isEmpty &&
            bodyMass.isEmpty &&
            bodyFatPercentage.isEmpty &&
            heartRateVariability.isEmpty &&
            heartRateVariabilityRanges.isEmpty &&
            heartRateVariabilityRangesSecondary.isEmpty &&
            respiratoryRate.isEmpty &&
            respiratoryRateRanges.isEmpty &&
            oxygenSaturation.isEmpty &&
            oxygenSaturationRanges.isEmpty &&
            oxygenSaturationRangesSecondary.isEmpty &&
            bodyMassIndex.isEmpty &&
            activeEnergy.isEmpty &&
            activeEnergySecondary.isEmpty &&
            restingEnergy.isEmpty &&
            restingEnergySecondary.isEmpty &&
            exerciseMinutes.isEmpty &&
            exerciseMinutesSecondary.isEmpty &&
            trainingLoad.isEmpty &&
            wristTemperature.isEmpty &&
            timeInDaylight.isEmpty &&
            steps.isEmpty &&
            stepsSecondary.isEmpty &&
            sleepHistory.isEmpty &&
            heartRateDaySamples.isEmpty &&
            heartRateDaySamplesSecondary.isEmpty &&
            restingHeartRateDaySamples.isEmpty &&
            restingHeartRateDaySamplesSecondary.isEmpty &&
            heartRateVariabilityDaySamples.isEmpty &&
            heartRateVariabilityDaySamplesSecondary.isEmpty &&
            respiratoryRateDaySamples.isEmpty &&
            oxygenSaturationDaySamples.isEmpty &&
            oxygenSaturationDaySamplesSecondary.isEmpty &&
            activeEnergyDaySamples.isEmpty &&
            activeEnergyDaySamplesSecondary.isEmpty &&
            stepsDaySamples.isEmpty &&
            stepsDaySamplesSecondary.isEmpty
    }

    init(
        sleep: HealthTrendSeries,
        sleepSecondary: HealthTrendSeries = .empty,
        readiness: HealthTrendSeries = .empty,
        heartRate: HealthTrendSeries = .empty,
        heartRateRanges: HealthTrendRangeSeries = .empty,
        heartRateRangesSecondary: HealthTrendRangeSeries = .empty,
        restingHeartRate: HealthTrendSeries,
        restingHeartRateSecondary: HealthTrendSeries = .empty,
        bodyMass: HealthTrendSeries,
        bodyFatPercentage: HealthTrendSeries,
        heartRateVariability: HealthTrendSeries,
        heartRateVariabilityRanges: HealthTrendRangeSeries = .empty,
        heartRateVariabilityRangesSecondary: HealthTrendRangeSeries = .empty,
        respiratoryRate: HealthTrendSeries,
        respiratoryRateRanges: HealthTrendRangeSeries = .empty,
        oxygenSaturation: HealthTrendSeries,
        oxygenSaturationRanges: HealthTrendRangeSeries = .empty,
        oxygenSaturationRangesSecondary: HealthTrendRangeSeries = .empty,
        bodyMassIndex: HealthTrendSeries,
        activeEnergy: HealthTrendSeries,
        activeEnergySecondary: HealthTrendSeries = .empty,
        restingEnergy: HealthTrendSeries,
        restingEnergySecondary: HealthTrendSeries = .empty,
        exerciseMinutes: HealthTrendSeries = .empty,
        exerciseMinutesSecondary: HealthTrendSeries = .empty,
        trainingLoad: HealthTrendSeries = .empty,
        wristTemperature: HealthTrendSeries = .empty,
        timeInDaylight: HealthTrendSeries = .empty,
        steps: HealthTrendSeries = .empty,
        stepsSecondary: HealthTrendSeries = .empty,
        sleepHistory: SleepHistorySnapshot = .empty,
        heartRateDaySamples: HealthTrendSeries = .empty,
        heartRateDaySamplesSecondary: HealthTrendSeries = .empty,
        restingHeartRateDaySamples: HealthTrendSeries = .empty,
        restingHeartRateDaySamplesSecondary: HealthTrendSeries = .empty,
        heartRateVariabilityDaySamples: HealthTrendSeries = .empty,
        heartRateVariabilityDaySamplesSecondary: HealthTrendSeries = .empty,
        respiratoryRateDaySamples: HealthTrendSeries = .empty,
        oxygenSaturationDaySamples: HealthTrendSeries = .empty,
        oxygenSaturationDaySamplesSecondary: HealthTrendSeries = .empty,
        activeEnergyDaySamples: HealthTrendSeries = .empty,
        activeEnergyDaySamplesSecondary: HealthTrendSeries = .empty,
        stepsDaySamples: HealthTrendSeries = .empty,
        stepsDaySamplesSecondary: HealthTrendSeries = .empty
    ) {
        self.sleep = sleep
        self.sleepSecondary = sleepSecondary
        self.readiness = readiness
        self.heartRate = heartRate
        self.heartRateRanges = heartRateRanges
        self.heartRateRangesSecondary = heartRateRangesSecondary
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateSecondary = restingHeartRateSecondary
        self.bodyMass = bodyMass
        self.bodyFatPercentage = bodyFatPercentage
        self.heartRateVariability = heartRateVariability
        self.heartRateVariabilityRanges = heartRateVariabilityRanges
        self.heartRateVariabilityRangesSecondary = heartRateVariabilityRangesSecondary
        self.respiratoryRate = respiratoryRate
        self.respiratoryRateRanges = respiratoryRateRanges
        self.oxygenSaturation = oxygenSaturation
        self.oxygenSaturationRanges = oxygenSaturationRanges
        self.oxygenSaturationRangesSecondary = oxygenSaturationRangesSecondary
        self.bodyMassIndex = bodyMassIndex
        self.activeEnergy = activeEnergy
        self.activeEnergySecondary = activeEnergySecondary
        self.restingEnergy = restingEnergy
        self.restingEnergySecondary = restingEnergySecondary
        self.exerciseMinutes = exerciseMinutes
        self.exerciseMinutesSecondary = exerciseMinutesSecondary
        self.trainingLoad = trainingLoad
        self.wristTemperature = wristTemperature
        self.timeInDaylight = timeInDaylight
        self.steps = steps
        self.stepsSecondary = stepsSecondary
        self.sleepHistory = sleepHistory
        self.heartRateDaySamples = heartRateDaySamples
        self.heartRateDaySamplesSecondary = heartRateDaySamplesSecondary
        self.restingHeartRateDaySamples = restingHeartRateDaySamples
        self.restingHeartRateDaySamplesSecondary = restingHeartRateDaySamplesSecondary
        self.heartRateVariabilityDaySamples = heartRateVariabilityDaySamples
        self.heartRateVariabilityDaySamplesSecondary = heartRateVariabilityDaySamplesSecondary
        self.respiratoryRateDaySamples = respiratoryRateDaySamples
        self.oxygenSaturationDaySamples = oxygenSaturationDaySamples
        self.oxygenSaturationDaySamplesSecondary = oxygenSaturationDaySamplesSecondary
        self.activeEnergyDaySamples = activeEnergyDaySamples
        self.activeEnergyDaySamplesSecondary = activeEnergyDaySamplesSecondary
        self.stepsDaySamples = stepsDaySamples
        self.stepsDaySamplesSecondary = stepsDaySamplesSecondary
    }

    private enum CodingKeys: String, CodingKey {
        case sleep
        case sleepSecondary
        case readiness
        case heartRate
        case heartRateRanges
        case heartRateRangesSecondary
        case restingHeartRate
        case restingHeartRateSecondary
        case bodyMass
        case bodyFatPercentage
        case heartRateVariability
        case heartRateVariabilityRanges
        case heartRateVariabilityRangesSecondary
        case respiratoryRate
        case respiratoryRateRanges
        case oxygenSaturation
        case oxygenSaturationRanges
        case oxygenSaturationRangesSecondary
        case bodyMassIndex
        case activeEnergy
        case activeEnergySecondary
        case restingEnergy
        case restingEnergySecondary
        case exerciseMinutes
        case exerciseMinutesSecondary
        case trainingLoad
        case wristTemperature
        case timeInDaylight
        case steps
        case stepsSecondary
        case sleepHistory
        case heartRateDaySamples
        case heartRateDaySamplesSecondary
        case restingHeartRateDaySamples
        case restingHeartRateDaySamplesSecondary
        case heartRateVariabilityDaySamples
        case heartRateVariabilityDaySamplesSecondary
        case respiratoryRateDaySamples
        case oxygenSaturationDaySamples
        case oxygenSaturationDaySamplesSecondary
        case activeEnergyDaySamples
        case activeEnergyDaySamplesSecondary
        case stepsDaySamples
        case stepsDaySamplesSecondary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sleep = try container.decode(HealthTrendSeries.self, forKey: .sleep)
        sleepSecondary = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .sleepSecondary) ?? .empty
        readiness = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .readiness) ?? .empty
        heartRate = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .heartRate) ?? .empty
        heartRateRanges = try container.decodeIfPresent(HealthTrendRangeSeries.self, forKey: .heartRateRanges) ?? .empty
        heartRateRangesSecondary = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .heartRateRangesSecondary
        ) ?? .empty
        restingHeartRate = try container.decode(HealthTrendSeries.self, forKey: .restingHeartRate)
        restingHeartRateSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingHeartRateSecondary
        ) ?? .empty
        bodyMass = try container.decode(HealthTrendSeries.self, forKey: .bodyMass)
        bodyFatPercentage = try container.decode(HealthTrendSeries.self, forKey: .bodyFatPercentage)
        heartRateVariability = try container.decode(HealthTrendSeries.self, forKey: .heartRateVariability)
        heartRateVariabilityRanges = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .heartRateVariabilityRanges
        ) ?? .empty
        heartRateVariabilityRangesSecondary = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .heartRateVariabilityRangesSecondary
        ) ?? .empty
        respiratoryRate = try container.decode(HealthTrendSeries.self, forKey: .respiratoryRate)
        respiratoryRateRanges = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .respiratoryRateRanges
        ) ?? .empty
        oxygenSaturation = try container.decode(HealthTrendSeries.self, forKey: .oxygenSaturation)
        oxygenSaturationRanges = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .oxygenSaturationRanges
        ) ?? .empty
        oxygenSaturationRangesSecondary = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .oxygenSaturationRangesSecondary
        ) ?? .empty
        bodyMassIndex = try container.decode(HealthTrendSeries.self, forKey: .bodyMassIndex)
        activeEnergy = try container.decode(HealthTrendSeries.self, forKey: .activeEnergy)
        activeEnergySecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .activeEnergySecondary
        ) ?? .empty
        restingEnergy = try container.decode(HealthTrendSeries.self, forKey: .restingEnergy)
        restingEnergySecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingEnergySecondary
        ) ?? .empty
        exerciseMinutes = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .exerciseMinutes) ?? .empty
        exerciseMinutesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .exerciseMinutesSecondary
        ) ?? .empty
        trainingLoad = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .trainingLoad) ?? .empty
        wristTemperature = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .wristTemperature) ?? .empty
        timeInDaylight = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .timeInDaylight) ?? .empty
        steps = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .steps) ?? .empty
        stepsSecondary = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .stepsSecondary) ?? .empty
        sleepHistory = try container.decodeIfPresent(SleepHistorySnapshot.self, forKey: .sleepHistory) ?? .empty
        heartRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateDaySamples
        ) ?? .empty
        heartRateDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateDaySamplesSecondary
        ) ?? .empty
        restingHeartRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingHeartRateDaySamples
        ) ?? .empty
        restingHeartRateDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingHeartRateDaySamplesSecondary
        ) ?? .empty
        heartRateVariabilityDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateVariabilityDaySamples
        ) ?? .empty
        heartRateVariabilityDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateVariabilityDaySamplesSecondary
        ) ?? .empty
        respiratoryRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .respiratoryRateDaySamples
        ) ?? .empty
        oxygenSaturationDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .oxygenSaturationDaySamples
        ) ?? .empty
        oxygenSaturationDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .oxygenSaturationDaySamplesSecondary
        ) ?? .empty
        activeEnergyDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .activeEnergyDaySamples
        ) ?? .empty
        activeEnergyDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .activeEnergyDaySamplesSecondary
        ) ?? .empty
        stepsDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .stepsDaySamples
        ) ?? .empty
        stepsDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .stepsDaySamplesSecondary
        ) ?? .empty
    }

    func series(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .readiness:
            return readiness
        case .sleep:
            return sleep
        case .basics:
            return .empty
        case .heartRate:
            return heartRate
        case .restingHeartRate:
            return restingHeartRate
        case .bodyMass:
            return bodyMass
        case .bodyFatPercentage:
            return bodyFatPercentage
        case .heartRateVariability:
            return heartRateVariability
        case .respiratoryRate:
            return respiratoryRate
        case .oxygenSaturation:
            return oxygenSaturation
        case .bodyMassIndex:
            return bodyMassIndex
        case .activeEnergy:
            return activeEnergy
        case .restingEnergy:
            return restingEnergy
        case .exerciseMinutes:
            return exerciseMinutes
        case .trainingLoad:
            return trainingLoad
        case .wristTemperature:
            return wristTemperature
        case .timeInDaylight:
            return timeInDaylight
        case .steps:
            return steps
        }
    }

    func secondarySeries(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .sleep:
            return sleepSecondary
        case .restingHeartRate:
            return restingHeartRateSecondary
        case .activeEnergy:
            return activeEnergySecondary
        case .restingEnergy:
            return restingEnergySecondary
        case .exerciseMinutes:
            return exerciseMinutesSecondary
        case .steps:
            return stepsSecondary
        case .basics,
             .readiness,
             .heartRate,
             .bodyMass,
             .bodyFatPercentage,
             .heartRateVariability,
             .respiratoryRate,
             .oxygenSaturation,
             .bodyMassIndex,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight:
            return .empty
        }
    }

    func rangeSeries(for kind: HealthMetricKind) -> HealthTrendRangeSeries {
        switch kind {
        case .heartRate:
            return heartRateRanges
        case .heartRateVariability:
            return heartRateVariabilityRanges
        case .respiratoryRate:
            return respiratoryRateRanges
        case .oxygenSaturation:
            return oxygenSaturationRanges
        case .sleep,
             .readiness,
             .basics,
             .restingHeartRate,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .steps:
            return .empty
        }
    }

    func secondaryRangeSeries(for kind: HealthMetricKind) -> HealthTrendRangeSeries {
        switch kind {
        case .heartRate:
            return heartRateRangesSecondary
        case .heartRateVariability:
            return heartRateVariabilityRangesSecondary
        case .oxygenSaturation:
            return oxygenSaturationRangesSecondary
        case .sleep,
             .readiness,
             .basics,
             .restingHeartRate,
             .bodyMass,
             .bodyFatPercentage,
             .respiratoryRate,
             .bodyMassIndex,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .steps:
            return .empty
        }
    }

    func daySeries(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .heartRate:
            return heartRateDaySamples
        case .restingHeartRate:
            return restingHeartRateDaySamples
        case .heartRateVariability:
            return heartRateVariabilityDaySamples
        case .respiratoryRate:
            return respiratoryRateDaySamples
        case .oxygenSaturation:
            return oxygenSaturationDaySamples
        case .activeEnergy:
            return activeEnergyDaySamples
        case .steps:
            return stepsDaySamples
        case .sleep,
             .readiness,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight:
            return .empty
        }
    }

    func secondaryDaySeries(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .heartRate:
            return heartRateDaySamplesSecondary
        case .restingHeartRate:
            return restingHeartRateDaySamplesSecondary
        case .heartRateVariability:
            return heartRateVariabilityDaySamplesSecondary
        case .oxygenSaturation:
            return oxygenSaturationDaySamplesSecondary
        case .activeEnergy:
            return activeEnergyDaySamplesSecondary
        case .steps:
            return stepsDaySamplesSecondary
        case .sleep,
             .readiness,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .respiratoryRate,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight:
            return .empty
        }
    }

    func replacingMetric(_ kind: HealthMetricKind, with refreshed: HealthTrendSnapshot) -> HealthTrendSnapshot {
        var next = self

        switch kind {
        case .readiness:
            next.readiness = refreshed.readiness
        case .sleep:
            next.sleep = refreshed.sleep
            next.sleepSecondary = refreshed.sleepSecondary
            next.sleepHistory = refreshed.sleepHistory
        case .basics:
            next.bodyMass = refreshed.bodyMass
            next.bodyFatPercentage = refreshed.bodyFatPercentage
            next.bodyMassIndex = refreshed.bodyMassIndex
        case .heartRate:
            next.heartRate = refreshed.heartRate
            next.heartRateRanges = refreshed.heartRateRanges
            next.heartRateRangesSecondary = refreshed.heartRateRangesSecondary
            next.heartRateDaySamples = refreshed.heartRateDaySamples
            next.heartRateDaySamplesSecondary = refreshed.heartRateDaySamplesSecondary
        case .restingHeartRate:
            next.restingHeartRate = refreshed.restingHeartRate
            next.restingHeartRateSecondary = refreshed.restingHeartRateSecondary
            next.restingHeartRateDaySamples = refreshed.restingHeartRateDaySamples
            next.restingHeartRateDaySamplesSecondary = refreshed.restingHeartRateDaySamplesSecondary
        case .bodyMass:
            next.bodyMass = refreshed.bodyMass
        case .bodyFatPercentage:
            next.bodyFatPercentage = refreshed.bodyFatPercentage
        case .heartRateVariability:
            next.heartRateVariability = refreshed.heartRateVariability
            next.heartRateVariabilityRanges = refreshed.heartRateVariabilityRanges
            next.heartRateVariabilityRangesSecondary = refreshed.heartRateVariabilityRangesSecondary
            next.heartRateVariabilityDaySamples = refreshed.heartRateVariabilityDaySamples
            next.heartRateVariabilityDaySamplesSecondary = refreshed.heartRateVariabilityDaySamplesSecondary
        case .respiratoryRate:
            next.respiratoryRate = refreshed.respiratoryRate
            next.respiratoryRateRanges = refreshed.respiratoryRateRanges
            next.respiratoryRateDaySamples = refreshed.respiratoryRateDaySamples
        case .oxygenSaturation:
            next.oxygenSaturation = refreshed.oxygenSaturation
            next.oxygenSaturationRanges = refreshed.oxygenSaturationRanges
            next.oxygenSaturationRangesSecondary = refreshed.oxygenSaturationRangesSecondary
            next.oxygenSaturationDaySamples = refreshed.oxygenSaturationDaySamples
            next.oxygenSaturationDaySamplesSecondary = refreshed.oxygenSaturationDaySamplesSecondary
        case .bodyMassIndex:
            next.bodyMassIndex = refreshed.bodyMassIndex
        case .activeEnergy:
            next.activeEnergy = refreshed.activeEnergy
            next.activeEnergySecondary = refreshed.activeEnergySecondary
            next.activeEnergyDaySamples = refreshed.activeEnergyDaySamples
            next.activeEnergyDaySamplesSecondary = refreshed.activeEnergyDaySamplesSecondary
        case .restingEnergy:
            next.restingEnergy = refreshed.restingEnergy
            next.restingEnergySecondary = refreshed.restingEnergySecondary
        case .exerciseMinutes:
            next.exerciseMinutes = refreshed.exerciseMinutes
            next.exerciseMinutesSecondary = refreshed.exerciseMinutesSecondary
        case .trainingLoad:
            next.trainingLoad = refreshed.trainingLoad
        case .wristTemperature:
            next.wristTemperature = refreshed.wristTemperature
        case .timeInDaylight:
            next.timeInDaylight = refreshed.timeInDaylight
        case .steps:
            next.steps = refreshed.steps
            next.stepsSecondary = refreshed.stepsSecondary
            next.stepsDaySamples = refreshed.stepsDaySamples
            next.stepsDaySamplesSecondary = refreshed.stepsDaySamplesSecondary
        }

        return next
    }

    var readinessSourceSeries: [HealthTrendSeries] {
        [
            heartRateVariability,
            restingHeartRate,
            sleep,
            trainingLoad,
            respiratoryRate,
            oxygenSaturation,
            wristTemperature
        ]
    }

    func filtered(by selection: BodyHealthPermissionSelection) -> HealthTrendSnapshot {
        var filtered = self

        if !selection.includes(.sleep) {
            filtered.sleep = .empty
            filtered.sleepSecondary = .empty
            filtered.sleepHistory = .empty
        }
        if !selection.includes(.heart) {
            filtered.heartRate = .empty
            filtered.heartRateRanges = .empty
            filtered.heartRateRangesSecondary = .empty
            filtered.restingHeartRate = .empty
            filtered.restingHeartRateSecondary = .empty
            filtered.heartRateVariability = .empty
            filtered.heartRateVariabilityRanges = .empty
            filtered.heartRateVariabilityRangesSecondary = .empty
            filtered.heartRateDaySamples = .empty
            filtered.heartRateDaySamplesSecondary = .empty
            filtered.restingHeartRateDaySamples = .empty
            filtered.restingHeartRateDaySamplesSecondary = .empty
            filtered.heartRateVariabilityDaySamples = .empty
            filtered.heartRateVariabilityDaySamplesSecondary = .empty
        }
        if !selection.includes(.basics) {
            filtered.bodyMass = .empty
            filtered.bodyFatPercentage = .empty
            filtered.bodyMassIndex = .empty
        }
        if !selection.includes(.bloodOxygen) {
            filtered.oxygenSaturation = .empty
            filtered.oxygenSaturationRanges = .empty
            filtered.oxygenSaturationRangesSecondary = .empty
            filtered.oxygenSaturationDaySamples = .empty
            filtered.oxygenSaturationDaySamplesSecondary = .empty
        }
        if !selection.includes(.respiratory) {
            filtered.respiratoryRate = .empty
            filtered.respiratoryRateRanges = .empty
            filtered.respiratoryRateDaySamples = .empty
        }
        if !selection.includes(.energy) {
            filtered.activeEnergy = .empty
            filtered.activeEnergySecondary = .empty
            filtered.activeEnergyDaySamples = .empty
            filtered.activeEnergyDaySamplesSecondary = .empty
            filtered.restingEnergy = .empty
            filtered.restingEnergySecondary = .empty
        }
        if !selection.includes(.exerciseMinutes) {
            filtered.exerciseMinutes = .empty
            filtered.exerciseMinutesSecondary = .empty
        }
        if !selection.includes(.workouts) {
            filtered.trainingLoad = .empty
        }
        if !selection.includes(.wristTemperature) {
            filtered.wristTemperature = .empty
        }
        if !selection.includes(.timeInDaylight) {
            filtered.timeInDaylight = .empty
        }
        if !selection.includes(.steps) {
            filtered.steps = .empty
            filtered.stepsSecondary = .empty
            filtered.stepsDaySamples = .empty
            filtered.stepsDaySamplesSecondary = .empty
        }

        return filtered
    }

    func clearingSecondarySeries() -> HealthTrendSnapshot {
        var cleared = self
        cleared.sleepSecondary = .empty
        cleared.heartRateRangesSecondary = .empty
        cleared.heartRateDaySamplesSecondary = .empty
        cleared.restingHeartRateSecondary = .empty
        cleared.restingHeartRateDaySamplesSecondary = .empty
        cleared.heartRateVariabilityRangesSecondary = .empty
        cleared.heartRateVariabilityDaySamplesSecondary = .empty
        cleared.oxygenSaturationRangesSecondary = .empty
        cleared.oxygenSaturationDaySamplesSecondary = .empty
        cleared.activeEnergySecondary = .empty
        cleared.activeEnergyDaySamplesSecondary = .empty
        cleared.restingEnergySecondary = .empty
        cleared.exerciseMinutesSecondary = .empty
        cleared.stepsSecondary = .empty
        cleared.stepsDaySamplesSecondary = .empty
        return cleared
    }
}

struct BasicsTrendSummary: Equatable {
    var weight: HealthTrendSeries
    var bodyFat: HealthTrendSeries
    var bodyMassIndex: HealthTrendSeries

    var isEmpty: Bool {
        weight.isEmpty && bodyFat.isEmpty && bodyMassIndex.isEmpty
    }

    static let empty = BasicsTrendSummary(weight: .empty, bodyFat: .empty, bodyMassIndex: .empty)

    var weightHalfSpread: Double? {
        halfSpread(for: weight)
    }

    var bodyFatHalfSpread: Double? {
        halfSpread(for: bodyFat)
    }

    var bodyMassIndexHalfSpread: Double? {
        halfSpread(for: bodyMassIndex)
    }

    var weightAverage: Double? {
        weight.averageValue
    }

    var bodyFatAverage: Double? {
        bodyFat.averageValue
    }

    private func halfSpread(for series: HealthTrendSeries) -> Double? {
        let values = series.points.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return nil
        }

        return (maximum - minimum) / 2
    }

    func limited(to range: BodyHealthTrendRange, calendar: Calendar = .bodyGregorian, date: Date = Date()) -> BasicsTrendSummary {
        BasicsTrendSummary(
            weight: weight.limited(to: range, calendar: calendar, date: date),
            bodyFat: bodyFat.limited(to: range, calendar: calendar, date: date),
            bodyMassIndex: bodyMassIndex.limited(to: range, calendar: calendar, date: date)
        )
    }

    func nearestDate(to date: Date) -> Date? {
        let dates = weight.points.map(\.date) + bodyFat.points.map(\.date)
        return dates.min { first, second in
            abs(first.timeIntervalSince(date)) < abs(second.timeIntervalSince(date))
        }
    }

    func selectionDate(for selectedDate: Date?) -> Date? {
        guard let selectedDate else {
            return nil
        }

        return nearestDate(to: selectedDate)
    }
}

private func bodyTrendAggregationBuckets<Point>(
    from points: [Point],
    aggregationDayCount: Int
) -> [ArraySlice<Point>] {
    var ranges = stride(from: 0, to: points.count, by: aggregationDayCount).map { startIndex in
        startIndex..<min(startIndex + aggregationDayCount, points.count)
    }

    if let finalRange = ranges.last,
       finalRange.count < aggregationDayCount,
       ranges.count > 1 {
        ranges.removeLast()
    }

    return ranges.map { points[$0] }
}

struct HealthTrendRangeSeries: Codable, Equatable {
    var points: [HealthTrendRangeDataPoint]

    var isEmpty: Bool {
        points.isEmpty
    }

    var averageValue: Double? {
        let finiteValues = points.compactMap(\.averageValue).filter(\.isFinite)
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }

    var valueRange: ClosedRange<Double>? {
        let lows = points.map(\.lowValue).filter(\.isFinite)
        let highs = points.map(\.highValue).filter(\.isFinite)
        guard let low = lows.min(), let high = highs.max() else {
            return nil
        }

        return low...high
    }

    static let empty = HealthTrendRangeSeries(points: [])

    func limited(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> HealthTrendRangeSeries {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        return HealthTrendRangeSeries(
            points: points.filter { point in
                point.date >= startDate && point.date < endDate
            }
        )
    }

    func calendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendRangeCalendarPoint] {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let pointsByDay = Dictionary(grouping: points.filter { point in
            point.date >= startDate && point.date < endDate
        }) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<range.dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            let point = pointsByDay[day]?
                .sorted { $0.date < $1.date }
                .last
            return HealthTrendRangeCalendarPoint(
                date: day,
                lowValue: point?.lowValue.isFinite == true ? point?.lowValue : nil,
                highValue: point?.highValue.isFinite == true ? point?.highValue : nil,
                averageValue: point?.averageValue?.isFinite == true ? point?.averageValue : nil
            )
        }
    }

    func chartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendRangeCalendarPoint] {
        aggregatedChartCalendarPoints(
            to: range,
            aggregationDayCount: range.chartAggregationDayCount,
            calendar: calendar,
            date: date
        )
    }

    func sourceComparisonChartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendRangeCalendarPoint] {
        aggregatedChartCalendarPoints(
            to: range,
            aggregationDayCount: range.sourceComparisonChartAggregationDayCount,
            calendar: calendar,
            date: date
        )
    }

    private func aggregatedChartCalendarPoints(
        to range: BodyHealthTrendRange,
        aggregationDayCount: Int,
        calendar: Calendar,
        date: Date
    ) -> [HealthTrendRangeCalendarPoint] {
        let dailyPoints = calendarPoints(to: range, calendar: calendar, date: date)
        guard aggregationDayCount > 1 else {
            return dailyPoints
        }

        return bodyTrendAggregationBuckets(
            from: dailyPoints,
            aggregationDayCount: aggregationDayCount
        ).compactMap { bucket in
            guard let bucketStartDate = bucket.first?.date,
                  let bucketEndDate = bucket.last?.date else {
                return nil
            }

            let lows = bucket.compactMap(\.lowValue).filter(\.isFinite)
            let highs = bucket.compactMap(\.highValue).filter(\.isFinite)
            let averages = bucket.compactMap(\.averageValue).filter(\.isFinite)
            let averageValue = averages.isEmpty ? nil : averages.reduce(0, +) / Double(averages.count)
            return HealthTrendRangeCalendarPoint(
                date: bucketEndDate,
                lowValue: lows.min(),
                highValue: highs.max(),
                averageValue: averageValue,
                startDate: bucketStartDate,
                endDate: bucketEndDate
            )
        }
    }
}

struct HealthTrendRangeDataPoint: Codable, Equatable, Identifiable {
    var date: Date
    var lowValue: Double
    var highValue: Double
    var averageValue: Double?

    var id: Date {
        date
    }
}

struct HealthTrendRangeCalendarPoint: Equatable, Identifiable {
    var date: Date
    var lowValue: Double?
    var highValue: Double?
    var averageValue: Double?
    var startDate: Date
    var endDate: Date

    init(
        date: Date,
        lowValue: Double?,
        highValue: Double?,
        averageValue: Double?,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.date = date
        self.lowValue = lowValue
        self.highValue = highValue
        self.averageValue = averageValue
        self.startDate = startDate ?? date
        self.endDate = endDate ?? date
    }

    var id: Date {
        date
    }

    var hasValue: Bool {
        lowValue != nil && highValue != nil
    }

    var representsDateRange: Bool {
        startDate != endDate
    }
}

struct HealthTrendSeries: Codable, Equatable {
    var points: [HealthTrendDataPoint]

    var isEmpty: Bool {
        points.isEmpty
    }

    var averageValue: Double? {
        let finiteValues = points.map(\.value).filter(\.isFinite)
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }

    static let empty = HealthTrendSeries(points: [])

    func mapValues(_ transform: (Double) -> Double) -> HealthTrendSeries {
        HealthTrendSeries(
            points: points.map {
                HealthTrendDataPoint(date: $0.date, value: transform($0.value))
            }
        )
    }

    func limited(to range: BodyHealthTrendRange, calendar: Calendar = .bodyGregorian, date: Date = Date()) -> HealthTrendSeries {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        return HealthTrendSeries(
            points: points.filter { point in
                point.date >= startDate && point.date < endDate
            }
        )
    }

    func calendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let pointsByDay = Dictionary(grouping: points.filter { point in
            point.date >= startDate && point.date < endDate
        }) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<range.dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            let value = pointsByDay[day]?
                .sorted { $0.date < $1.date }
                .last?
                .value
            return HealthTrendCalendarPoint(
                date: day,
                value: value?.isFinite == true ? value : nil
            )
        }
    }

    func chartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        aggregatedChartCalendarPoints(
            to: range,
            aggregationDayCount: range.chartAggregationDayCount,
            calendar: calendar,
            date: date
        )
    }

    func sourceComparisonChartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        aggregatedChartCalendarPoints(
            to: range,
            aggregationDayCount: range.sourceComparisonChartAggregationDayCount,
            calendar: calendar,
            date: date
        )
    }

    private func aggregatedChartCalendarPoints(
        to range: BodyHealthTrendRange,
        aggregationDayCount: Int,
        calendar: Calendar,
        date: Date
    ) -> [HealthTrendCalendarPoint] {
        let dailyPoints = calendarPoints(to: range, calendar: calendar, date: date)
        guard aggregationDayCount > 1 else {
            return dailyPoints
        }

        return bodyTrendAggregationBuckets(
            from: dailyPoints,
            aggregationDayCount: aggregationDayCount
        ).compactMap { bucket in
            guard let bucketStartDate = bucket.first?.date,
                  let bucketEndDate = bucket.last?.date else {
                return nil
            }

            let finiteValues = bucket.compactMap(\.value).filter(\.isFinite)
            let averageValue = finiteValues.isEmpty
                ? nil
                : finiteValues.reduce(0, +) / Double(finiteValues.count)
            return HealthTrendCalendarPoint(
                date: bucketEndDate,
                value: averageValue,
                startDate: bucketStartDate,
                endDate: bucketEndDate
            )
        }
    }

    func lineChartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date(),
        maximumPointCount: Int? = nil
    ) -> [HealthTrendCalendarPoint] {
        let chartPoints = chartCalendarPoints(to: range, calendar: calendar, date: date)
        let effectiveMaximumPointCount = maximumPointCount ?? range.lineChartMaximumPointCount
        guard let effectiveMaximumPointCount else {
            return chartPoints
        }

        return chartPoints.compressedStableLineChartPoints(maximumCount: effectiveMaximumPointCount)
    }

    func chartSeries(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> HealthTrendSeries {
        HealthTrendSeries(
            points: chartCalendarPoints(to: range, calendar: calendar, date: date).compactMap { point in
                guard let value = point.value, value.isFinite else {
                    return nil
                }

                return HealthTrendDataPoint(date: point.date, value: value)
            }
        )
    }

    func lineChartSeries(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date(),
        maximumPointCount: Int? = nil
    ) -> HealthTrendSeries {
        HealthTrendSeries(
            points: lineChartCalendarPoints(
                to: range,
                calendar: calendar,
                date: date,
                maximumPointCount: maximumPointCount
            ).compactMap { point in
                guard let value = point.value, value.isFinite else {
                    return nil
                }

                return HealthTrendDataPoint(date: point.date, value: value)
            }
        )
    }

    func nearestPoint(to date: Date) -> HealthTrendDataPoint? {
        points.min { first, second in
            abs(first.date.timeIntervalSince(date)) < abs(second.date.timeIntervalSince(date))
        }
    }

    func selectionPoint(for selectedDate: Date?) -> HealthTrendDataPoint? {
        guard let selectedDate else {
            return nil
        }

        return nearestPoint(to: selectedDate)
    }

    func point(on date: Date) -> HealthTrendDataPoint? {
        points.first { $0.date == date }
    }

    func points(on date: Date, calendar: Calendar = .bodyGregorian) -> HealthTrendSeries {
        let dayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)

        return HealthTrendSeries(
            points: points
                .filter { point in
                    point.date >= dayStart && point.date < nextDayStart
                }
                .sorted { $0.date < $1.date }
        )
    }

    func hourlyAverageBuckets(on date: Date, calendar: Calendar = .bodyGregorian) -> [HealthTrendHourlyBucket] {
        let dayPoints = points(on: date, calendar: calendar).points.filter { $0.value.isFinite }
        let pointsByHour = Dictionary(grouping: dayPoints) { point in
            calendar.dateInterval(of: .hour, for: point.date)?.start ?? point.date
        }

        return pointsByHour.compactMap { hourStart, samples -> HealthTrendHourlyBucket? in
            let sortedSamples = samples.sorted { $0.date < $1.date }
            guard !sortedSamples.isEmpty else {
                return nil
            }

            let averageValue = sortedSamples.reduce(0) { $0 + $1.value } / Double(sortedSamples.count)
            return HealthTrendHourlyBucket(
                hourStart: hourStart,
                averageValue: averageValue,
                samples: sortedSamples
            )
        }
        .sorted { $0.hourStart < $1.hourStart }
    }
}

struct HealthTrendDataPoint: Codable, Equatable, Identifiable {
    var date: Date
    var value: Double

    var id: Date {
        date
    }
}



struct HealthTrendCalendarPoint: Equatable, Identifiable {
    var date: Date
    var value: Double?
    var startDate: Date
    var endDate: Date

    init(date: Date, value: Double?, startDate: Date? = nil, endDate: Date? = nil) {
        self.date = date
        self.value = value
        self.startDate = startDate ?? date
        self.endDate = endDate ?? date
    }

    var id: Date {
        date
    }

    var hasValue: Bool {
        value != nil
    }

    var representsDateRange: Bool {
        startDate != endDate
    }
}

private struct HealthTrendStableLineBucket {
    var points: [HealthTrendCalendarPoint]

    var averageValue: Double? {
        let finiteValues = points.compactMap(\.value).filter(\.isFinite)
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }

    func merged(with other: HealthTrendStableLineBucket) -> HealthTrendStableLineBucket {
        HealthTrendStableLineBucket(points: points + other.points)
    }

    var calendarPoint: HealthTrendCalendarPoint? {
        guard let firstPoint = points.first, let lastPoint = points.last else {
            return nil
        }

        return HealthTrendCalendarPoint(
            date: lastPoint.date,
            value: averageValue,
            startDate: firstPoint.startDate,
            endDate: lastPoint.endDate
        )
    }
}

private struct HealthTrendStableLineMergeCandidate {
    let index: Int
    let valueDelta: Double
    let combinedPointCount: Int

    func isBetter(than other: HealthTrendStableLineMergeCandidate) -> Bool {
        guard valueDelta == other.valueDelta else {
            return valueDelta < other.valueDelta
        }

        guard combinedPointCount == other.combinedPointCount else {
            return combinedPointCount < other.combinedPointCount
        }

        return index < other.index
    }
}

private extension Array where Element == HealthTrendCalendarPoint {
    func compressedStableLineChartPoints(maximumCount: Int) -> [HealthTrendCalendarPoint] {
        guard maximumCount > 0 else {
            return []
        }

        let finitePoints = filter { point in
            point.value?.isFinite == true
        }
        guard finitePoints.count > maximumCount else {
            return self
        }

        var buckets = finitePoints.map { point in
            HealthTrendStableLineBucket(points: [point])
        }

        while buckets.count > maximumCount {
            var bestCandidate: HealthTrendStableLineMergeCandidate?

            for index in buckets.indices.dropLast() {
                let candidate = mergeCandidate(at: index, in: buckets)
                if bestCandidate.map({ candidate.isBetter(than: $0) }) ?? true {
                    bestCandidate = candidate
                }
            }

            guard let bestCandidate else {
                break
            }

            buckets[bestCandidate.index] = buckets[bestCandidate.index].merged(with: buckets[bestCandidate.index + 1])
            buckets.remove(at: bestCandidate.index + 1)
        }

        return buckets.compactMap(\.calendarPoint)
    }

    private func mergeCandidate(
        at index: Int,
        in buckets: [HealthTrendStableLineBucket]
    ) -> HealthTrendStableLineMergeCandidate {
        let firstBucket = buckets[index]
        let secondBucket = buckets[index + 1]
        let valueDelta: Double
        if let firstAverage = firstBucket.averageValue,
           let secondAverage = secondBucket.averageValue {
            valueDelta = abs(firstAverage - secondAverage)
        } else {
            valueDelta = .greatestFiniteMagnitude
        }

        return HealthTrendStableLineMergeCandidate(
            index: index,
            valueDelta: valueDelta,
            combinedPointCount: firstBucket.points.count + secondBucket.points.count
        )
    }
}

struct HealthTrendHourlyBucket: Equatable, Identifiable {
    var hourStart: Date
    var averageValue: Double
    var samples: [HealthTrendDataPoint]

    static let sampleWindowDuration: TimeInterval = 10 * 60

    var id: Date {
        hourStart
    }

    var plotDate: Date {
        hourStart.addingTimeInterval(30 * 60)
    }

    func sampleWindows(duration: TimeInterval = sampleWindowDuration) -> [HealthTrendHourlySampleWindow] {
        let hourEnd = hourStart.addingTimeInterval(60 * 60)
        let windowDuration = min(max(duration, 0), 60 * 60)
        guard windowDuration > 0 else {
            return []
        }

        let sortedSamples = samples
            .filter { sample in
                sample.value.isFinite && sample.date >= hourStart && sample.date < hourEnd
            }
            .sorted { $0.date < $1.date }
        let samplesByWindowStart = Dictionary(grouping: sortedSamples) { sample in
            let offset = sample.date.timeIntervalSince(hourStart)
            let windowIndex = floor(offset / windowDuration)
            return hourStart.addingTimeInterval(windowIndex * windowDuration)
        }

        return samplesByWindowStart.keys.sorted().compactMap { startDate in
            guard let samples = samplesByWindowStart[startDate], !samples.isEmpty else {
                return nil
            }

            let endDate = min(startDate.addingTimeInterval(windowDuration), hourEnd)
            let averageValue = samples.reduce(0) { $0 + $1.value } / Double(samples.count)
            return HealthTrendHourlySampleWindow(
                startDate: startDate,
                endDate: endDate,
                averageValue: averageValue,
                samples: samples
            )
        }
    }
}

struct HealthTrendHourlySampleWindow: Equatable, Identifiable {
    var startDate: Date
    var endDate: Date
    var averageValue: Double
    var samples: [HealthTrendDataPoint]

    var id: Date {
        startDate
    }
}
