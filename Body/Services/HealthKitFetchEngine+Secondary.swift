//
//  HealthKitFetchEngine+Secondary.swift
//  Body
//

import Foundation
import HealthKit

// Secondary-source fetch dispatchers. When the user has chosen a "compare
// to" source for a metric in Settings > Data > Source (or per-metric in a
// detail page), these methods route the per-metric kind to the right HK
// query shape for the *secondary* series. The primary series uses the
// orchestrators in `HealthKitFetchEngine.swift`.
extension HealthKitFetchEngine {
    func fetchSecondaryTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendSeries {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        switch kind {
        case .sleep:
            return await fetchSecondarySleepHistory(calendar: calendar).durationSeries
        case .restingHeartRate:
            return await fetchDailyQuantitySeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .restingHeartRate,
                sourceOption: secondaryOption
            )
        case .activeEnergy:
            return await fetchDailyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy,
                sourceOption: secondaryOption
            )
        case .restingEnergy:
            return await fetchDailyCumulativeQuantitySeries(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy,
                sourceOption: secondaryOption
            )
        case .exerciseMinutes:
            return await fetchDailyCumulativeQuantitySeries(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes,
                sourceOption: secondaryOption
            )
        case .steps:
            return await fetchDailyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps,
                sourceOption: secondaryOption
            )
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

    func fetchSecondarySleepHistory(calendar: Calendar) async -> SleepHistorySnapshot {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: .sleep)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        return await fetchDailySleepHistory(
            calendar: calendar,
            sourceOption: secondaryOption,
            hydrateVitals: false
        )
    }

    func fetchSecondaryDaySamples(
        for kind: HealthMetricKind,
        calendar: Calendar,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> HealthTrendSeries {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        switch kind {
        case .heartRate:
            return await fetchQuantitySampleSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .restingHeartRate:
            return await fetchQuantitySampleSeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .restingHeartRate,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .heartRateVariability:
            return await fetchQuantitySampleSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .oxygenSaturation:
            return await fetchQuantitySampleSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                sourceOption: secondaryOption,
                valueTransform: Self.normalizedPercentDisplayValue,
                startDate: startDate,
                endDate: endDate
            )
        case .activeEnergy:
            return await fetchHourlyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .steps:
            return await fetchHourlyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
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

    func fetchSecondaryRangeTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendRangeSeries {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        switch kind {
        case .heartRate:
            return await fetchDailyQuantityRangeSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate,
                sourceOption: secondaryOption
            )
        case .heartRateVariability:
            return await fetchDailyQuantityRangeSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability,
                sourceOption: secondaryOption
            )
        case .oxygenSaturation:
            return await fetchDailyQuantityRangeSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                sourceOption: secondaryOption,
                valueTransform: Self.normalizedPercentDisplayValue
            )
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
}
