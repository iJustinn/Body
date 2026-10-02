//
//  WatchMetricWeeklyRewoundTests.swift
//  BodyTests
//
//  `WatchMetric.weeklyRewound` keeps the weekly workout time complication's
//  rightmost bar on today: a snapshot cached across midnight must shift its
//  elapsed days out and append empty slots instead of holding yesterday's
//  window (the cache is only rewritten when the phone pushes). Also pins the
//  `weeklyRanges` beside the week across phone/watch version skew.
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

    /// An on-watch compute after midnight windows the week on the compute day
    /// while the merge keeps the phone's older `generatedAt`; rewinding from
    /// `generatedAt` shifted such a week one day too far (the Sunday morning
    /// "M T T" bars). The week's own `weeklyAsOf` day wins.
    func testWeekWindowedOnItsOwnDayIsNotRewoundFromAnOlderGeneratedAt() {
        let weekly: [Double?] = [12, 30, nil, 45, 22, 0, 38]
        var computed = metric(weekly: weekly)
        computed.weeklyAsOf = date(28, hour: 1)
        XCTAssertEqual(computed.weeklyRewound(from: date(27, hour: 23), to: date(28, hour: 10), calendar: calendar), weekly)
        // …and a stamped week that IS a day old still shifts, even under a
        // newer generatedAt.
        computed.weeklyAsOf = date(27, hour: 23)
        XCTAssertEqual(computed.weeklyRewound(from: date(28), to: date(28, hour: 10), calendar: calendar), [30, nil, 45, 22, 0, 38, nil])
    }

    func testClockRolledBackwardDoesNotShift() {
        let weekly: [Double?] = [12, 30, nil, 45, 22, 0, 38]
        let rewound = metric(weekly: weekly).weeklyRewound(from: date(28), to: date(27), calendar: calendar)
        XCTAssertEqual(rewound, weekly)
    }

    // MARK: - `weeklyRanges` schema evolution
    //
    // The HR / HRV week chart's daily capsules ride beside `weekly`. An older
    // phone omits them and its week must still decode, as the plain line.

    func testMetricWithoutWeeklyRangesDecodesThemAsNil() throws {
        let snapshot = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: Data("""
        {
          "generatedAt": "2026-08-28T09:00:00Z",
          "metrics": [
            {
              "kind": "heartRate",
              "title": "Heart Rate",
              "displayValue": "62",
              "unit": "bpm",
              "fillFraction": 0.5,
              "weekly": [58, 60, null, 64, 66, 61, 62]
            }
          ]
        }
        """.utf8)))

        let heartRate = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.heartRate))
        XCTAssertEqual(heartRate.weekly, [58, 60, nil, 64, 66, 61, 62])
        XCTAssertNil(heartRate.weeklyRanges)
    }

    func testWeeklyRangesRoundTripWithTheirEmptyDays() throws {
        let heartRate = WatchMetric(
            kind: WatchMetricKindKey.heartRate,
            title: "Heart Rate",
            displayValue: "62",
            unit: "bpm",
            score: nil,
            fillFraction: 0.5,
            weekly: [58, 60, nil, 64, 66, 61, 62],
            weeklyAsOf: date(28),
            weeklyRanges: [
                WatchDayRange(low: 48, high: 92), nil, nil,
                WatchDayRange(low: 50, high: 101), nil, WatchDayRange(low: 47, high: 88), WatchDayRange(low: 52, high: 95)
            ]
        )
        let original = WatchMetricsSnapshot(generatedAt: date(28), lastRefreshDate: date(28), metrics: [heartRate])

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: try XCTUnwrap(original.encoded())))

        XCTAssertEqual(decoded.metrics.first?.weeklyRanges, heartRate.weeklyRanges)
        XCTAssertEqual(decoded, original)
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
