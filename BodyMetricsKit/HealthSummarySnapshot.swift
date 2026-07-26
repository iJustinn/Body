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
                title: String(localized: "About Readiness", table: "BodyMetricsKit"),
                body: String(localized: "Readiness combines your recent heart, sleep, training, and overnight vital signs against your own baseline. It is a readiness estimate, not a diagnosis. The strongest signal comes from sustained patterns across HRV, resting heart rate, sleep quality, and recent load rather than one isolated reading.\nToday's live score updates through the day and drops after a workout, while the trend chart keeps the value from shortly after you wake, so the current score can read lower than today's point on the chart.", table: "BodyMetricsKit")
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
