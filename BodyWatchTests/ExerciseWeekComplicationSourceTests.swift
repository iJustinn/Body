//
//  ExerciseWeekComplicationSourceTests.swift
//  BodyWatchTests
//
//  Locks the metric the exercise week complication charts: the published
//  `workoutMinutes` metric, falling back to the legacy `exerciseMinutes` kind
//  only when a snapshot pushed by an older phone build carries no
//  `workoutMinutes`.
//

import XCTest
@testable import BodyWatch

final class ExerciseWeekComplicationSourceTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 780_000_000)

    private func metric(kind: String, displayValue: String) -> WatchMetric {
        WatchMetric(
            kind: kind,
            title: "Workout Time",
            displayValue: displayValue,
            unit: "",
            score: nil,
            fillFraction: 0,
            rawValue: nil
        )
    }

    private func snapshot(metrics: [WatchMetric]) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(generatedAt: now, lastRefreshDate: now, metrics: metrics)
    }

    func testPrefersWorkoutMinutesWhenBothKindsArePresent() throws {
        let source = snapshot(metrics: [
            metric(kind: WatchMetricKindKey.exerciseMinutes, displayValue: "legacy"),
            metric(kind: WatchMetricKindKey.workoutMinutes, displayValue: "current")
        ])

        let selected = try XCTUnwrap(WatchComplicationTimeline.exerciseWeekMetric(in: source))

        XCTAssertEqual(selected.kind, WatchMetricKindKey.workoutMinutes)
        XCTAssertEqual(selected.displayValue, "current")
    }

    func testFallsBackToExerciseMinutesWhenWorkoutMinutesIsMissing() throws {
        let source = snapshot(metrics: [
            metric(kind: WatchMetricKindKey.exerciseMinutes, displayValue: "legacy")
        ])

        let selected = try XCTUnwrap(WatchComplicationTimeline.exerciseWeekMetric(in: source))

        XCTAssertEqual(selected.kind, WatchMetricKindKey.exerciseMinutes)
        XCTAssertEqual(selected.displayValue, "legacy")
    }

    func testReturnsNilWhenNeitherKindIsCarried() {
        let source = snapshot(metrics: [metric(kind: WatchMetricKindKey.sleep, displayValue: "7h")])

        XCTAssertNil(WatchComplicationTimeline.exerciseWeekMetric(in: source))
    }
}
