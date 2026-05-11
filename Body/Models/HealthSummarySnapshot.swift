//
//  HealthSummarySnapshot.swift
//  Body
//

import Foundation

struct HealthSummarySnapshot: Equatable {
    var sleep: SleepSummary
    var restingHeartRate: HealthMetricSummary
    var bodyMass: HealthMetricSummary
    var bodyFatPercentage: HealthMetricSummary
    var heartRateVariability: HealthMetricSummary
    var oxygenSaturation: HealthMetricSummary
    var vo2Max: HealthMetricSummary
    var bodyMassIndex: HealthMetricSummary

    var isEmpty: Bool {
        sleep.duration == nil &&
            restingHeartRate.value == nil &&
            bodyMass.value == nil &&
            bodyFatPercentage.value == nil &&
            heartRateVariability.value == nil &&
            oxygenSaturation.value == nil &&
            vo2Max.value == nil &&
            bodyMassIndex.value == nil
    }

    static let empty = HealthSummarySnapshot(
        sleep: SleepSummary(duration: nil),
        restingHeartRate: HealthMetricSummary(value: nil),
        bodyMass: HealthMetricSummary(value: nil),
        bodyFatPercentage: HealthMetricSummary(value: nil),
        heartRateVariability: HealthMetricSummary(value: nil),
        oxygenSaturation: HealthMetricSummary(value: nil),
        vo2Max: HealthMetricSummary(value: nil),
        bodyMassIndex: HealthMetricSummary(value: nil)
    )

    static let placeholder = HealthSummarySnapshot(
        sleep: SleepSummary(duration: 28_740),
        restingHeartRate: HealthMetricSummary(value: 60),
        bodyMass: HealthMetricSummary(value: 69.3),
        bodyFatPercentage: HealthMetricSummary(value: 13.1),
        heartRateVariability: HealthMetricSummary(value: 38.4),
        oxygenSaturation: HealthMetricSummary(value: 97),
        vo2Max: HealthMetricSummary(value: 41.0),
        bodyMassIndex: HealthMetricSummary(value: 22.1)
    )
}

struct SleepSummary: Equatable {
    var duration: TimeInterval?
}

struct HealthMetricSummary: Equatable {
    var value: Double?
}
