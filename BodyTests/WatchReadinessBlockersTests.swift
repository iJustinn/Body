//
//  WatchReadinessBlockersTests.swift
//  BodyTests
//
//  The on-watch Readiness gate: every permitted input must succeed in one
//  compute, except an input this watch holds no HealthKit source for at all
//  (Blood Oxygen computed on the iPhone), which is carried from the seed.
//

import XCTest
@testable import Body

final class WatchReadinessBlockersTests: XCTestCase {
    private let permission = BodyHealthPermissionSelection.defaultValue

    private func delta(failing: Set<HealthMetricKind> = [], carried: Set<HealthMetricKind> = []) -> WatchComputeDelta {
        func series(_ kind: HealthMetricKind) -> WatchFetchOutcome<HealthTrendSeries> {
            failing.contains(kind) || carried.contains(kind) ? .failure : .success(HealthTrendSeries(points: []))
        }
        var delta = WatchComputeDelta()
        delta.heartRateSeries = series(.heartRate)
        delta.restingHeartRateSeries = series(.restingHeartRate)
        delta.heartRateVariabilitySeries = series(.heartRateVariability)
        delta.respiratoryRateSeries = series(.respiratoryRate)
        delta.oxygenSaturationSeries = series(.oxygenSaturation)
        delta.wristTemperatureSeries = series(.wristTemperature)
        delta.sleepNights = failing.contains(.sleep) || carried.contains(.sleep) ? .failure : .success([])
        delta.workouts = .success([])
        delta.carriedKinds = carried
        return delta
    }

    private func blockers(_ delta: WatchComputeDelta) -> [String] {
        WatchComputeAssembly.readinessBlockers(delta: delta, replayedTrainingLoad: true, permission: permission)
    }

    func testEveryInputSucceedingLeavesNoBlocker() {
        XCTAssertEqual(blockers(delta()), [])
    }

    func testFailedInputBlocks() {
        XCTAssertEqual(blockers(delta(failing: [.oxygenSaturation])), [HealthMetricKind.oxygenSaturation.rawValue])
    }

    func testInputWithNoLocalSourceIsCarriedAndDoesNotBlock() {
        let carried = delta(carried: [.oxygenSaturation])
        XCTAssertEqual(blockers(carried), [])
        XCTAssertEqual(
            WatchComputeAssembly.readinessCarriedInputs(delta: carried),
            [HealthMetricKind.oxygenSaturation.rawValue]
        )
    }

    func testCarriedInputDoesNotExcuseAnotherFailedInput() {
        XCTAssertEqual(
            blockers(delta(failing: [.sleep], carried: [.oxygenSaturation])),
            [HealthMetricKind.sleep.rawValue]
        )
    }

    func testEveryInputCarriedStillBlocks() {
        let all: Set<HealthMetricKind> = [
            .heartRate, .restingHeartRate, .heartRateVariability,
            .respiratoryRate, .oxygenSaturation, .wristTemperature, .sleep
        ]
        XCTAssertEqual(blockers(delta(carried: all)).count, all.count)
    }

    func testFailedWorkoutQueryStillBlocks() {
        var failed = delta(carried: [.oxygenSaturation])
        failed.workouts = .failure
        XCTAssertEqual(blockers(failed), ["workouts"])
    }
}
