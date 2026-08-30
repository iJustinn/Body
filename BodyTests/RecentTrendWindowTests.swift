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

    // MARK: - Two-phase window: how much phase 1 fetches

    private func defaultsWithTrendRange(_ range: BodyHealthTrendRange?) throws -> UserDefaults {
        let suite = "RecentTrendWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if let range {
            defaults.set(range.rawValue, forKey: BodyAppearancePreference.defaultTrendRangeKey)
        }
        return defaults
    }

    /// A stored range shorter than the readiness baseline still fetches 60 days,
    /// so the newest day scores correctly even for the one leaf the merge can't
    /// help: one with no cached history at all.
    func testPhaseOneWindowNeverDropsBelowTheReadinessBaselineReach() throws {
        for range in [BodyHealthTrendRange.recentWeek, .recentMonth] {
            let days = HealthKitFetchEngine.phaseOneTrendWindowDays(
                defaults: try defaultsWithTrendRange(range)
            )
            XCTAssertEqual(days, HealthKitFetchEngine.minimumPhaseOneTrendWindowDays, range.rawValue)
        }
        XCTAssertGreaterThanOrEqual(HealthKitFetchEngine.minimumPhaseOneTrendWindowDays, 57)
    }

    func testPhaseOneWindowFollowsALongerStoredRange() throws {
        XCTAssertEqual(
            HealthKitFetchEngine.phaseOneTrendWindowDays(defaults: try defaultsWithTrendRange(.recentSixMonths)),
            BodyHealthTrendRange.recentSixMonths.dayCount
        )
    }

    /// A user already on Year has nothing to defer: phase 1 fetches everything
    /// and phase 2 must not run.
    func testPhaseOneWindowIsNilWhenTheStoredRangeAlreadySpansTheYear() throws {
        XCTAssertNil(
            HealthKitFetchEngine.phaseOneTrendWindowDays(defaults: try defaultsWithTrendRange(.recentYear))
        )
    }

    func testPhaseOneWindowFallsBackToTheAppDefaultRangeWhenNothingIsStored() throws {
        XCTAssertEqual(
            HealthKitFetchEngine.phaseOneTrendWindowDays(defaults: try defaultsWithTrendRange(nil)),
            max(BodyHealthTrendRange.defaultValue.dayCount, HealthKitFetchEngine.minimumPhaseOneTrendWindowDays)
        )
    }

    /// The clamped start has to land on a day start: the daily buckets are
    /// midnight-anchored, so a mid-day start would both make the oldest bucket a
    /// partial day and collide with the cached full-day point the merge keeps
    /// just outside the boundary.
    func testClampedTrendStartSnapsToADayStartInsideTheWindow() throws {
        let anchor = try anchor()
        let interval = HealthKitFetchEngine.recentHealthTrendInterval(calendar: calendar, anchor: anchor)
        let clamped = HealthKitFetchEngine.clampedTrendStart(
            interval: interval,
            maxDays: 60,
            calendar: calendar
        )

        XCTAssertEqual(clamped, calendar.startOfDay(for: clamped))
        XCTAssertGreaterThan(clamped, interval.start)
        XCTAssertEqual(
            calendar.dateComponents([.day], from: clamped, to: calendar.startOfDay(for: interval.end)).day,
            60
        )
    }

    func testClampedTrendStartIgnoresAClampWiderThanTheWindow() throws {
        let anchor = try anchor()
        let interval = HealthKitFetchEngine.recentHealthTrendInterval(calendar: calendar, anchor: anchor)

        XCTAssertEqual(
            HealthKitFetchEngine.clampedTrendStart(interval: interval, maxDays: nil, calendar: calendar),
            interval.start
        )
        XCTAssertEqual(
            HealthKitFetchEngine.clampedTrendStart(
                interval: interval,
                maxDays: BodyHealthTrendRange.maximumDayCount + 30,
                calendar: calendar
            ),
            interval.start
        )
    }

    // MARK: - Two-phase window: the merge

    private func series(_ dayOffsets: [Int], from anchor: Date, value: Double = 1) throws -> HealthTrendSeries {
        HealthTrendSeries(
            points: try dayOffsets.map { offset in
                HealthTrendDataPoint(
                    date: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: anchor))),
                    value: value
                )
            }
        )
    }

    private func windowStart(_ dayOffset: Int, from anchor: Date) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: anchor)))
    }

    func testMergeWithoutAWindowKeepsOnlyTheFreshSeries() throws {
        let anchor = try anchor()
        let merged = HealthKitFetchEngine.mergeWindowedTrend(
            cached: try series([-300, -200], from: anchor),
            fresh: try series([-5, -1], from: anchor, value: 2),
            windowStart: nil
        )

        XCTAssertEqual(merged, try series([-5, -1], from: anchor, value: 2))
    }

    func testMergeWithAnEmptyCacheKeepsOnlyTheFreshSeries() throws {
        let anchor = try anchor()
        let merged = HealthKitFetchEngine.mergeWindowedTrend(
            cached: .empty,
            fresh: try series([-5, -1], from: anchor),
            windowStart: try windowStart(-59, from: anchor)
        )

        XCTAssertEqual(merged, try series([-5, -1], from: anchor))
    }

    /// The whole point of the merge: the year of chart room survives a query
    /// that only scanned the last 60 days.
    func testMergeKeepsCachedPointsOlderThanTheWindow() throws {
        let anchor = try anchor()
        let merged = HealthKitFetchEngine.mergeWindowedTrend(
            cached: try series([-300, -200, -100], from: anchor),
            fresh: try series([-30, -1], from: anchor, value: 2),
            windowStart: try windowStart(-59, from: anchor)
        )

        XCTAssertEqual(merged.points.map(\.date), try series([-300, -200, -100, -30, -1], from: anchor).points.map(\.date))
        XCTAssertEqual(merged.points.map(\.value), [1, 1, 1, 2, 2])
    }

    /// Inside the window the fresh fetch is the ONLY authority: it re-read those
    /// days from HealthKit, so a cached point it did not return is a deleted
    /// sample and must not be resurrected — and a day both hold takes the fresh
    /// value.
    func testMergeLetsTheFreshFetchOwnTheWholeWindow() throws {
        let anchor = try anchor()
        let start = try windowStart(-59, from: anchor)
        let merged = HealthKitFetchEngine.mergeWindowedTrend(
            // -40 was cached inside the window and is gone from HealthKit; -10
            // is cached at a now-stale value.
            cached: try series([-100, -40, -10], from: anchor),
            fresh: try series([-10], from: anchor, value: 2),
            windowStart: start
        )

        XCTAssertEqual(merged.points.count, 2)
        XCTAssertEqual(merged.points.map(\.date), try series([-100, -10], from: anchor).points.map(\.date))
        XCTAssertEqual(merged.points.last?.value, 2)
        XCTAssertFalse(merged.points.contains { $0.date >= start && $0.value == 1 })
    }

    /// The boundary day itself belongs to the fresh fetch (the query runs from
    /// `windowStart` inclusive), so a cached point on it must not survive.
    func testMergeDropsACachedPointExactlyOnTheWindowStart() throws {
        let anchor = try anchor()
        let start = try windowStart(-59, from: anchor)
        let merged = HealthKitFetchEngine.mergeWindowedTrend(
            cached: try series([-60, -59], from: anchor),
            fresh: .empty,
            windowStart: start
        )

        XCTAssertEqual(merged.points.map(\.date), try series([-60], from: anchor).points.map(\.date))
    }

    func testRangeSeriesMergeFollowsTheSameBoundary() throws {
        let anchor = try anchor()
        func rangePoints(_ offsets: [Int], low: Double) throws -> HealthTrendRangeSeries {
            HealthTrendRangeSeries(
                points: try offsets.map { offset in
                    HealthTrendRangeDataPoint(
                        date: try windowStart(offset, from: anchor),
                        lowValue: low,
                        highValue: low + 10,
                        averageValue: low + 5
                    )
                }
            )
        }

        let merged = HealthKitFetchEngine.mergeWindowedTrendRange(
            cached: try rangePoints([-300, -40], low: 50),
            fresh: try rangePoints([-20], low: 60),
            windowStart: try windowStart(-59, from: anchor)
        )

        XCTAssertEqual(merged.points.map(\.date), try rangePoints([-300, -20], low: 0).points.map(\.date))
        XCTAssertEqual(merged.points.last?.lowValue, 60)
    }

    func testSleepHistoryMergeKeepsNightsOlderThanTheWindow() throws {
        let anchor = try anchor()
        func history(_ offsets: [Int], duration: TimeInterval) throws -> SleepHistorySnapshot {
            SleepHistorySnapshot(
                days: try offsets.map { offset in
                    SleepDaySummary(
                        date: try windowStart(offset, from: anchor),
                        summary: SleepSummary(duration: duration)
                    )
                }
            )
        }

        let merged = HealthKitFetchEngine.mergeWindowedSleepHistory(
            cached: try history([-300, -40], duration: 7 * 3_600),
            fresh: try history([-20], duration: 8 * 3_600),
            windowStart: try windowStart(-59, from: anchor)
        )

        XCTAssertEqual(merged.days.map(\.date), try history([-300, -20], duration: 0).days.map(\.date))
        XCTAssertEqual(merged.days.last?.summary.duration, 8 * 3_600)
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
