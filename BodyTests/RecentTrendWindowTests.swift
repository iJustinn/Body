//
//  RecentTrendWindowTests.swift
//  BodyTests
//
//  Locks the single boundary that keeps a metric's headline value and its own
//  chart telling the same story: a "latest reading" older than the daily trend
//  window is treated as no data, not as a current value.
//
//  Two independent enforcement points are covered, because the phone and the
//  watch clear a stale value in different places:
//  * the phone bounds the QUERY (`latestQuantity` runs inside
//    `recentHealthTrendInterval`), so an out-of-window metric resolves to a
//    genuine absence and its cached headline clears;
//  * the watch clears at DISPLAY time (`WatchMetricsSnapshot.sanitized`),
//    because a persisted snapshot can outlive the window its value was fetched
//    in and `WatchComputeMerge` deliberately preserves a good local value when
//    an incoming push is blank.
//

import XCTest
@testable import Body

final class RecentTrendWindowTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func anchor() throws -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 10
        components.timeZone = TimeZone.current
        return try XCTUnwrap(calendar.date(from: components))
    }

    // MARK: - The boundary itself

    func testWindowStartIsMaximumRangeDayCountBeforeTheAnchorsDayStart() throws {
        let anchor = try anchor()
        let start = BodyHealthTrendRange.recentTrendWindowStart(anchor: anchor, calendar: calendar)

        // Calendar arithmetic, not 86_400 multiplication, so the assertion stays
        // correct across a DST transition inside the window.
        let expected = try XCTUnwrap(
            calendar.date(
                byAdding: .day,
                value: -(BodyHealthTrendRange.maximumDayCount - 1),
                to: calendar.startOfDay(for: anchor)
            )
        )
        XCTAssertEqual(start, expected)
        XCTAssertEqual(start, calendar.startOfDay(for: start))
    }

    func testWindowStartMatchesTheIntervalEveryTrendQueryRunsOver() throws {
        let anchor = try anchor()
        let interval = HealthKitFetchEngine.recentHealthTrendInterval(calendar: calendar, anchor: anchor)

        // The card's latest-sample query and the chart's trend query must derive
        // the same start, or a card can outrun its own chart again.
        XCTAssertEqual(
            interval.start,
            BodyHealthTrendRange.recentTrendWindowStart(anchor: anchor, calendar: calendar)
        )
        XCTAssertEqual(interval.end, anchor)
    }

    func testWindowSpansExactlyTheLongestSelectableRange() throws {
        let anchor = try anchor()
        let start = BodyHealthTrendRange.recentTrendWindowStart(anchor: anchor, calendar: calendar)
        let days = try XCTUnwrap(
            calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: anchor)).day
        )
        XCTAssertEqual(days, BodyHealthTrendRange.recentYear.dayCount - 1)
        XCTAssertEqual(BodyHealthTrendRange.recentYear.dayCount, BodyHealthTrendRange.maximumDayCount)
    }

    // MARK: - Watch display-time clearing

    private func watchMetric(
        _ kind: String,
        displayValue: String = "62",
        rawValue: Double? = 62,
        measuredAt: Date?,
        computedAt: Date? = nil
    ) -> WatchMetric {
        WatchMetric(
            kind: kind,
            title: kind,
            displayValue: displayValue,
            unit: "bpm",
            fillFraction: 0.5,
            rawValue: rawValue,
            computedAt: computedAt,
            measuredAt: measuredAt
        )
    }

    private func snapshot(_ metrics: [WatchMetric], generatedAt: Date) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(generatedAt: generatedAt, lastRefreshDate: generatedAt, metrics: metrics)
    }

    /// The four cases that define the edge: just outside, exactly on it, just
    /// inside, and comfortably inside.
    func testSanitizedClearsOnlyReadingsBeforeTheWindowStart() throws {
        let now = try anchor()
        let start = WatchMetricsSnapshot.recentTrendWindowStart(asOf: now)
        let dayBefore = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: start))
        let dayAfter = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let recent = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: now))

        let cases: [(Date, Bool, String)] = [
            (dayBefore, true, "a day before the window start"),
            (start, false, "exactly on the window start"),
            (dayAfter, false, "a day after the window start"),
            (recent, false, "three days ago")
        ]

        for (measuredAt, expectsCleared, label) in cases {
            let sanitized = snapshot(
                [watchMetric(WatchMetricKindKey.heartRate, measuredAt: measuredAt)],
                generatedAt: now
            ).sanitized(asOf: now)
            let metric = try XCTUnwrap(sanitized.metric(forKind: WatchMetricKindKey.heartRate))
            XCTAssertEqual(metric.hasValue, !expectsCleared, label)
            if expectsCleared {
                XCTAssertEqual(metric.displayValue, "--", label)
                XCTAssertNil(metric.rawValue, label)
                XCTAssertNil(metric.measuredAt, label)
            } else {
                XCTAssertEqual(metric.rawValue, 62, label)
            }
        }
    }

    func testSanitizedClearsEveryLatestSampleKindThatAgedOut() throws {
        let now = try anchor()
        let stale = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -2, to: WatchMetricsSnapshot.recentTrendWindowStart(asOf: now))
        )
        let kinds = [
            WatchMetricKindKey.heartRate,
            WatchMetricKindKey.restingHeartRate,
            WatchMetricKindKey.heartRateVariability
        ]

        let sanitized = snapshot(
            kinds.map { watchMetric($0, measuredAt: stale) },
            generatedAt: now
        ).sanitized(asOf: now)

        for kind in kinds {
            XCTAssertFalse(try XCTUnwrap(sanitized.metric(forKind: kind)).hasValue, kind)
        }
    }

    /// A computed metric carries `computedAt`, not `measuredAt`. The window rule
    /// must not touch it — nil here means "not a latest-sample metric", not
    /// "unverifiable" (which is what it means for Sleep's own guard).
    func testSanitizedLeavesComputedMetricsWithNoMeasurementWatermarkAlone() throws {
        let now = try anchor()
        let longAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -800, to: now))

        let sanitized = snapshot(
            [
                watchMetric(
                    WatchMetricKindKey.readiness,
                    displayValue: "78",
                    rawValue: 78,
                    measuredAt: nil,
                    computedAt: longAgo
                )
            ],
            generatedAt: now
        ).sanitized(asOf: now)

        let readiness = try XCTUnwrap(sanitized.metric(forKind: WatchMetricKindKey.readiness))
        XCTAssertTrue(readiness.hasValue)
        XCTAssertEqual(readiness.rawValue, 78)
    }

    func testSanitizedIsIdentityWhenEveryReadingIsInsideTheWindow() throws {
        let now = try anchor()
        let recent = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: now))
        let original = snapshot([watchMetric(WatchMetricKindKey.heartRate, measuredAt: recent)], generatedAt: now)

        XCTAssertEqual(original.sanitized(asOf: now), original)
    }

    /// The watch widget target links neither `BodyMetricsKit` nor
    /// `BodyWatchSnapshotKit`, so the day count is duplicated in
    /// `BodyWatchShared`. Pin the two together — a silent drift would let the
    /// watch and the phone disagree about what "recent" means.
    func testWatchWindowDayCountMatchesThePhonesTrendRange() {
        XCTAssertEqual(
            WatchMetricsSnapshot.recentTrendWindowDayCount,
            BodyHealthTrendRange.maximumDayCount
        )
    }
}
