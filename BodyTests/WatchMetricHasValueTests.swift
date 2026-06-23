//
//  WatchMetricHasValueTests.swift
//  BodyTests
//
//  Locks `WatchMetric.hasValue`, the contract the watch snapshot merge relies on
//  to avoid blanking a good local metric with an incoming empty one. The sleep
//  metric is the load-bearing case: when the phone's "Show Sleep Score" toggle is
//  off, the snapshot builder sends sleep with a real duration `displayValue` but
//  a nil `score`/`rawValue`. That must still count as "has a value" so the merge
//  replaces the previously-scored metric (honoring the hide) instead of keeping
//  the stale score. Defining "no value" as a nil `rawValue` alone regresses that.
//

import XCTest
@testable import Body

final class WatchMetricHasValueTests: XCTestCase {
    func testScoreHiddenSleepMetricHasValue() {
        // "Show Sleep Score" off: duration present, score/rawValue nil.
        let sleep = WatchMetric(
            kind: WatchMetricKindKey.sleep,
            title: "Sleep",
            displayValue: "7h 32m",
            unit: "",
            score: nil,
            fillFraction: 0,
            rawValue: nil,
            rangeMin: 0,
            rangeMax: 100
        )
        XCTAssertTrue(sleep.hasValue, "A score-hidden sleep metric still carries a real duration and must merge through.")
    }

    func testPlaceholderMetricHasNoValue() {
        let blank = WatchMetric(
            kind: WatchMetricKindKey.sleep,
            title: "Sleep",
            displayValue: "--",
            unit: "",
            score: nil,
            fillFraction: 0,
            rawValue: nil,
            rangeMin: nil,
            rangeMax: nil
        )
        XCTAssertFalse(blank.hasValue, "A `--` placeholder must read as no value so the merge keeps a good local one.")
    }

    func testScoredAndNumericMetricsHaveValue() {
        let readiness = WatchMetric(
            kind: WatchMetricKindKey.readiness, title: "Readiness", displayValue: "78",
            unit: "%", score: 78, fillFraction: 0.78, rawValue: 78, rangeMin: 0, rangeMax: 100
        )
        let heartRate = WatchMetric(
            kind: WatchMetricKindKey.heartRate, title: "Heart Rate", displayValue: "62",
            unit: "bpm", score: nil, fillFraction: 0.4, rawValue: 62, rangeMin: 54, rangeMax: 72
        )
        XCTAssertTrue(readiness.hasValue)
        XCTAssertTrue(heartRate.hasValue)
    }
}
