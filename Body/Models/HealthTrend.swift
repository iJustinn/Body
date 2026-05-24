//
//  HealthTrend.swift
//  Body
//

import Foundation

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
