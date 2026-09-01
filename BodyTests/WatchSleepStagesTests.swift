//
//  WatchSleepStagesTests.swift
//  BodyTests
//
//  The `sleepStages` payload the watch Sleep Stages complication draws: it is
//  dropped with the Sleep card at display time (`sanitized(asOf:)`), and it
//  survives phone/watch version skew in both directions (an older phone omits
//  the key; a newer one round-trips it).
//

import XCTest
@testable import Body

final class WatchSleepStagesTests: XCTestCase {
    // Same calendar `sanitized` judges the night with.
    private let calendar = Calendar(identifier: .gregorian)

    private func moment(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    private func stages(night: Int) -> [WatchSleepStageSegment] {
        [
            WatchSleepStageSegment(stage: "core", startDate: moment(day: night - 1, hour: 23), endDate: moment(day: night, hour: 2)),
            WatchSleepStageSegment(stage: "deep", startDate: moment(day: night, hour: 2), endDate: moment(day: night, hour: 3)),
            WatchSleepStageSegment(stage: "rem", startDate: moment(day: night, hour: 3), endDate: moment(day: night, hour: 6))
        ]
    }

    private func snapshot(night: Int) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(
            generatedAt: moment(day: night, hour: 7),
            lastRefreshDate: moment(day: night, hour: 7),
            metrics: [
                WatchMetric(
                    kind: WatchMetricKindKey.sleep,
                    title: "Sleep",
                    displayValue: "7h 32m",
                    unit: "",
                    score: 85,
                    fillFraction: 0.85,
                    rawValue: 85
                )
            ],
            sleepNight: moment(day: night, hour: 7),
            sleepStages: stages(night: night)
        )
    }

    // MARK: - Display-time gating

    func testSanitizeDropsTheStageBarWithAStaleNight() {
        let sanitized = snapshot(night: 4).sanitized(asOf: moment(day: 5, hour: 9))

        XCTAssertNil(sanitized.sleepStages, "yesterday's bar must not outlive the card it belongs to")
        XCTAssertEqual(sanitized.metric(forKind: WatchMetricKindKey.sleep)?.displayValue, "--")
    }

    func testSanitizeKeepsTheStageBarForTonightsNight() {
        let built = snapshot(night: 4)
        let sanitized = built.sanitized(asOf: moment(day: 4, hour: 9))

        XCTAssertEqual(sanitized.sleepStages, built.sleepStages)
    }

    // MARK: - Schema evolution

    func testSnapshotWithoutTheSleepStagesKeyStillDecodes() throws {
        // What an older phone publishes: every other field, no `sleepStages`.
        let json = """
        {
          "generatedAt": "2026-06-04T07:00:00Z",
          "sleepNight": "2026-06-04T07:00:00Z",
          "metrics": [
            {
              "kind": "sleep",
              "title": "Sleep",
              "displayValue": "7h 32m",
              "unit": "",
              "fillFraction": 0.85
            }
          ]
        }
        """

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: Data(json.utf8)))

        XCTAssertNil(decoded.sleepStages)
        XCTAssertEqual(decoded.metric(forKind: WatchMetricKindKey.sleep)?.displayValue, "7h 32m")
    }

    func testEncodeDecodeRoundTripsSleepStages() throws {
        let original = snapshot(night: 4)
        let data = try XCTUnwrap(original.encoded())

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: data))

        XCTAssertEqual(decoded.sleepStages, original.sleepStages)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Gallery preview

    func testPlaceholderCarriesAContiguousSampleNight() throws {
        let segments = try XCTUnwrap(WatchMetricsSnapshot.placeholder.sleepStages)
        let first = try XCTUnwrap(segments.first)
        let last = try XCTUnwrap(segments.last)

        for (earlier, later) in zip(segments, segments.dropFirst()) {
            XCTAssertEqual(earlier.endDate, later.startDate, "the bar has no gaps")
        }
        XCTAssertEqual(
            last.endDate.timeIntervalSince(first.startDate),
            7 * 3_600 + 32 * 60,
            "matches the sample Sleep metric's 7h 32m"
        )
        XCTAssertEqual(first.stage, "awake", "the night opens with a short wake, as a real one does")
    }
}
