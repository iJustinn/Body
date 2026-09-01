//
//  WatchMetricWeeklyRewoundTests.swift
//  BodyTests
//
//  `WatchMetric.weeklyRewound` keeps the weekly workout time complication's
//  rightmost bar on today: a snapshot cached across midnight must shift its
//  elapsed days out and append empty slots instead of holding yesterday's
//  window (the cache is only rewritten when the phone pushes).
//

import XCTest

@testable import Body

final class WatchMetricWeeklyRewoundTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func metric(weekly: [Double?]?) -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.workoutMinutes,
            title: "Weekly Workout Time",
            displayValue: "38",
            unit: "",
            score: nil,
            fillFraction: 0,
            weekly: weekly
        )
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    func testFreshSnapshotPassesThroughUnchanged() {
        let weekly: [Double?] = [12, 30, nil, 45, 22, 0, 38]
        let rewound = metric(weekly: weekly).weeklyRewound(from: date(28), to: date(28, hour: 23), calendar: calendar)
        XCTAssertEqual(rewound, weekly)
    }

    func testSnapshotFromYesterdayShiftsOneDayOutAndAppendsAnEmptySlot() {
        let rewound = metric(weekly: [12, 30, nil, 45, 22, 0, 38]).weeklyRewound(from: date(27, hour: 23), to: date(28, hour: 0), calendar: calendar)
        XCTAssertEqual(rewound, [30, nil, 45, 22, 0, 38, nil])
    }

    func testWeekOldSnapshotYieldsSevenEmptySlots() {
        let rewound = metric(weekly: [12, 30, nil, 45, 22, 0, 38]).weeklyRewound(from: date(1), to: date(28), calendar: calendar)
        XCTAssertEqual(rewound, Array(repeating: nil, count: 7))
    }

    func testShortOrMissingWeeklyNormalizesToSevenSlots() {
        XCTAssertEqual(metric(weekly: [5, 7]).weeklyRewound(from: date(28), to: date(28), calendar: calendar), [nil, nil, nil, nil, nil, 5, 7])
        XCTAssertEqual(metric(weekly: nil).weeklyRewound(from: date(28), to: date(28), calendar: calendar), Array(repeating: nil, count: 7))
    }

    func testClockRolledBackwardDoesNotShift() {
        let weekly: [Double?] = [12, 30, nil, 45, 22, 0, 38]
        let rewound = metric(weekly: weekly).weeklyRewound(from: date(28), to: date(27), calendar: calendar)
        XCTAssertEqual(rewound, weekly)
    }

    // MARK: - Legacy `exerciseMinutes` fallback
    //
    // The complication reads `workoutMinutes` and falls back to the legacy
    // activity-ring kind (`ExerciseWeekComplication.weekly`, whose two-line
    // selection is pinned by `ProjectConfigurationTests`). A watch paired to an
    // older phone build keeps serving that phone's cached snapshot until the
    // next push, so the fallback has to survive a real decode.

    /// A snapshot as an older phone build wrote it: only the legacy metric, no
    /// `workoutMinutes` key anywhere in the payload.
    private func legacySnapshotData() -> Data {
        Data("""
        {
          "generatedAt": "2026-08-28T09:00:00Z",
          "lastRefreshDate": "2026-08-28T09:00:00Z",
          "source": "phone",
          "metrics": [
            {
              "kind": "exerciseMinutes",
              "title": "Exercise Minutes",
              "displayValue": "38",
              "unit": "",
              "fillFraction": 0,
              "weekly": [12, 30, null, 45, 22, 0, 38]
            }
          ]
        }
        """.utf8)
    }

    func testLegacySnapshotWithoutWorkoutMinutesStillDecodesAndCarriesItsWeek() throws {
        let snapshot = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: legacySnapshotData()))

        // The new kind is genuinely absent, so the complication's `??` is the
        // only thing standing between this payload and seven empty bars.
        XCTAssertNil(snapshot.metric(forKind: WatchMetricKindKey.workoutMinutes))
        let legacy = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.exerciseMinutes))
        XCTAssertEqual(legacy.weekly, [12, 30, nil, 45, 22, 0, 38])
        // And it still re-windows: an older phone's snapshot is exactly the one
        // most likely to be a day or more old by the time it is drawn. Anchored
        // to the decoded date rather than a literal, so the payload's UTC
        // stamp can't land on a different local day than the expectation.
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: snapshot.generatedAt))
        XCTAssertEqual(
            legacy.weeklyRewound(from: snapshot.generatedAt, to: nextDay, calendar: calendar),
            [30, nil, 45, 22, 0, 38, nil]
        )
    }

    func testCurrentSnapshotCarriesWorkoutMinutesSoTheFallbackIsNeverReached() {
        // The placeholder is the shape every current build publishes: the
        // fallback above must be dead code for it, or a phone/watch pair on the
        // same build would silently draw the legacy activity-ring bars.
        XCTAssertNotNil(WatchMetricsSnapshot.placeholder.metric(forKind: WatchMetricKindKey.workoutMinutes))
        XCTAssertNil(WatchMetricsSnapshot.placeholder.metric(forKind: WatchMetricKindKey.exerciseMinutes))
        XCTAssertEqual(
            WatchMetricsSnapshot.placeholder.metric(forKind: WatchMetricKindKey.workoutMinutes)?.weekly,
            [12, 30, 0, 45, 22, 0, 38]
        )
    }
}
