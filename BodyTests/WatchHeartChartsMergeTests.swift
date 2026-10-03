//
//  WatchHeartChartsMergeTests.swift
//  BodyTests
//
//  Locks how the Heart Rate and HRV chart complications' slots
//  (`WatchMetricsSnapshot.heartCharts`) are built by the watch compute
//  (`WatchComputeAssembly.heartCharts(delta:permission:)`) and move through
//  the watch's merges (`WatchComputeMerge`). Only a watch compute writes the
//  field, so the rules are:
//  * the compute carries a chart for every kind it read, an EMPTY one
//    included ("read fine, found nothing"), and no key for a read that
//    failed or was skipped; nothing without Heart or without a read;
//  * a computed chart is adopted per kind only when its window ends strictly
//    later than the displayed one's;
//  * an empty chart removes the kind and is never persisted, including the
//    no-source-on-this-watch read (`WatchSourceRead.unavailable`), the one
//    path that deletes a displayed chart without new data;
//  * a kind the compute brought no chart for keeps its chart;
//  * a Clear-Cache tombstone is never repopulated;
//  * a phone push, which never carries the field, keeps each local chart
//    while it carries that kind's card, and the settings-change mode and a
//    permission or data source change (the provenance strip) drop them all.
//

import XCTest
@testable import Body

final class WatchHeartChartsMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_600)
    private let t2 = Date(timeIntervalSince1970: 1_001_200)
    private let t3 = Date(timeIntervalSince1970: 1_001_800)

    private let heartRate = WatchMetricKindKey.heartRate
    private let hrv = WatchMetricKindKey.heartRateVariability

    // MARK: - Fixtures

    /// A chart read at `end` over the 8 hours before it, whose one slot's
    /// average tells the assertions which read it came from. A nil `average`
    /// is a read that found nothing.
    private func chart(endingAt end: Date, average: Double?) -> WatchIntradayChart {
        let window = WatchIntradayWindow.endingAt(end)
        let buckets = average.map {
            [WatchIntradayBucket(start: window.start, minimum: $0 - 5, maximum: $0 + 5, average: $0)]
        } ?? []
        return WatchIntradayChart(window: window, buckets: buckets)
    }

    private func card(_ kind: String) -> WatchMetric {
        WatchMetric(kind: kind, title: kind, displayValue: "62", unit: "bpm", score: nil, fillFraction: 0.5, rawValue: 62)
    }

    /// The displayed snapshot, or a phone push (which never carries charts).
    private func snapshot(
        metrics: [WatchMetric] = [],
        generatedAt: Date? = nil,
        heartCharts: [String: WatchIntradayChart]? = nil,
        isReset: Bool? = nil
    ) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(
            generatedAt: generatedAt ?? t0,
            lastRefreshDate: generatedAt ?? t0,
            metrics: metrics,
            source: "phone",
            heartCharts: heartCharts,
            publisherEpoch: "epoch-A",
            revision: 7,
            isReset: isReset
        )
    }

    /// A compute that carries these charts and nothing else, so no other
    /// rule can move the snapshot.
    private func computed(_ heartCharts: [String: WatchIntradayChart]?) -> WatchComputeResult {
        var computed = WatchMetricsSnapshot(generatedAt: t2, lastRefreshDate: t2, metrics: [])
        computed.source = "watch"
        computed.heartCharts = heartCharts
        return WatchComputeResult(snapshot: computed, dataAsOf: [:], coverage: t2, generation: 3)
    }

    /// Both kinds displayed, read at `t1`.
    private var displayedCharts: [String: WatchIntradayChart] {
        [heartRate: chart(endingAt: t1, average: 62), hrv: chart(endingAt: t1, average: 48)]
    }

    // MARK: - The compute's charts

    func testTheComputeCarriesEveryReadAnEmptyOneIncluded() {
        let read = chart(endingAt: t2, average: 70)
        let empty = chart(endingAt: t2, average: nil)
        var delta = WatchComputeDelta()
        delta.heartRateIntraday = .success(read)
        delta.heartRateVariabilityIntraday = .success(empty)

        XCTAssertEqual(
            WatchComputeAssembly.heartCharts(delta: delta, permission: .defaultValue),
            [heartRate: read, hrv: empty],
            "an empty read is carried: it is the merge's removal"
        )

        delta.heartRateVariabilityIntraday = .failure
        XCTAssertEqual(
            WatchComputeAssembly.heartCharts(delta: delta, permission: .defaultValue),
            [heartRate: read],
            "a failed or skipped read carries no key"
        )
    }

    func testTheComputeCarriesNoFieldWithoutHeartOrWithoutARead() {
        var delta = WatchComputeDelta()
        XCTAssertNil(
            WatchComputeAssembly.heartCharts(delta: delta, permission: .defaultValue),
            "every read failed (the default): no field, so a compute without chart reads changes nothing"
        )

        delta.heartRateIntraday = .success(chart(endingAt: t2, average: 70))
        delta.heartRateVariabilityIntraday = .success(chart(endingAt: t2, average: 48))
        let heartOff = BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false)
        XCTAssertNil(WatchComputeAssembly.heartCharts(delta: delta, permission: heartOff))
    }

    /// The wiring: the snapshot `assemble` returns carries exactly what
    /// `heartCharts(delta:permission:)` builds from the run's reads.
    func testTheComputedSnapshotCarriesTheChartsTheRunRead() throws {
        let now = Date(timeIntervalSince1970: 1_788_500_000)
        let calendar = Calendar.bodyGregorian
        let seed = WatchComputeSeed(
            publishedAt: now,
            dataThrough: now,
            summary: .placeholder,
            trends: .empty,
            seriesRanges: [:],
            settings: WatchComputeSettings(
                idealSleepDurationMinutes: 480,
                followsSystemUnits: true,
                selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.celsius.rawValue,
                showSleepScore: true,
                showsSubMinuteAwakeSleepStages: true,
                showsLeadingTrailingAwakeSleepStages: true,
                healthDataSourceSelectionRaw: "all",
                combinesHealthDataSourcesByName: false
            ),
            settingsSignature: "sig-heart-charts"
        )
        func assembled(_ delta: WatchComputeDelta) throws -> WatchMetricsSnapshot {
            try XCTUnwrap(WatchComputeAssembly.assemble(
                seed: seed,
                delta: delta,
                permission: .defaultValue,
                generation: 1,
                windowStart: WatchDeltaSplicer.deltaStart(dataThrough: now, calendar: calendar),
                now: now,
                calendar: calendar
            )).snapshot
        }

        var delta = WatchComputeDelta()
        delta.heartRateIntraday = .success(chart(endingAt: now, average: 70))
        XCTAssertEqual(try assembled(delta).heartCharts, [heartRate: chart(endingAt: now, average: 70)])
        XCTAssertNil(try assembled(WatchComputeDelta()).heartCharts, "no read, no field: the parity tests' case")
    }

    // MARK: - Compute → displayed: adoption by window

    func testANewerWindowIsAdoptedAndAnOlderOrEqualOneIgnored() {
        let displayed = snapshot(heartCharts: [heartRate: chart(endingAt: t1, average: 62)])
        func merged(_ candidate: WatchIntradayChart) -> WatchIntradayChart? {
            WatchComputeMerge.mergingComputed(computed([heartRate: candidate]), into: displayed)
                .heartCharts?[heartRate]
        }

        XCTAssertEqual(merged(chart(endingAt: t2, average: 70)), chart(endingAt: t2, average: 70))
        XCTAssertEqual(merged(chart(endingAt: t1, average: 70)), chart(endingAt: t1, average: 62), "an equal window is not newer")
        XCTAssertEqual(merged(chart(endingAt: t0, average: 70)), chart(endingAt: t1, average: 62))
    }

    /// Each kind moves on its own window, and over a snapshot without charts
    /// the compute's are adopted.
    func testEachKindIsAdoptedOnItsOwnWindow() {
        let displayed = snapshot(heartCharts: [heartRate: chart(endingAt: t2, average: 62)])
        let merged = WatchComputeMerge.mergingComputed(
            computed([heartRate: chart(endingAt: t1, average: 70), hrv: chart(endingAt: t1, average: 48)]),
            into: displayed
        )
        XCTAssertEqual(merged.heartCharts, [heartRate: chart(endingAt: t2, average: 62), hrv: chart(endingAt: t1, average: 48)])

        let bare = WatchComputeMerge.mergingComputed(computed([hrv: chart(endingAt: t1, average: 48)]), into: snapshot())
        XCTAssertEqual(bare.heartCharts, [hrv: chart(endingAt: t1, average: 48)])
    }

    // MARK: - Compute → displayed: an empty read removes

    /// "Read fine, found nothing" (the watch off the wrist all window)
    /// removes the kind rather than storing an empty chart, and the field
    /// goes nil once no kind is left, so a persisted snapshot never carries
    /// an empty chart.
    func testAnEmptyReadRemovesTheKindAndIsNeverPersisted() {
        let oneLeft = WatchComputeMerge.mergingComputed(
            computed([heartRate: chart(endingAt: t2, average: nil)]),
            into: snapshot(heartCharts: displayedCharts)
        )
        XCTAssertEqual(oneLeft.heartCharts, [hrv: chart(endingAt: t1, average: 48)])

        let noneLeft = WatchComputeMerge.mergingComputed(computed([hrv: chart(endingAt: t2, average: nil)]), into: oneLeft)
        XCTAssertNil(noneLeft.heartCharts)

        let bare = WatchComputeMerge.mergingComputed(computed([heartRate: chart(endingAt: t2, average: nil)]), into: snapshot())
        XCTAssertNil(bare.heartCharts, "over nothing, an empty read stores nothing")

        // An empty read must still be newer to remove anything.
        let older = WatchComputeMerge.mergingComputed(
            computed([heartRate: chart(endingAt: t0, average: nil)]),
            into: snapshot(heartCharts: displayedCharts)
        )
        XCTAssertEqual(older.heartCharts, displayedCharts)
    }

    /// No source for the kind on this watch at all
    /// (`WatchSourceRead.unavailable`): `WatchDeltaFetcher.intradayChart`
    /// answers an empty chart, the page's `[]`. That is the only path that
    /// deletes a displayed chart without new data, so it is followed here
    /// from the delta through the compute's map to the merge.
    func testANoSourceReadRemovesTheDisplayedChart() throws {
        var delta = WatchComputeDelta()
        delta.heartRateIntraday = .success(WatchIntradayChart(window: WatchIntradayWindow.endingAt(t2), buckets: []))
        delta.carriedKinds = [.heartRate]
        let charts = try XCTUnwrap(WatchComputeAssembly.heartCharts(delta: delta, permission: .defaultValue))
        XCTAssertEqual(charts[heartRate]?.buckets, [])

        let merged = WatchComputeMerge.mergingComputed(
            computed(charts),
            into: snapshot(heartCharts: [heartRate: chart(endingAt: t1, average: 62)])
        )
        XCTAssertNil(merged.heartCharts)
    }

    // MARK: - Compute → displayed: a failed or skipped read keeps

    func testAKindAbsentFromTheComputeKeepsItsChart() {
        let displayed = snapshot(heartCharts: displayedCharts)

        // HRV's read failed: only Heart Rate moves.
        let merged = WatchComputeMerge.mergingComputed(computed([heartRate: chart(endingAt: t2, average: 70)]), into: displayed)
        XCTAssertEqual(merged.heartCharts, [heartRate: chart(endingAt: t2, average: 70), hrv: chart(endingAt: t1, average: 48)])

        // A compute that read no chart at all carries no field and moves nothing.
        XCTAssertEqual(WatchComputeMerge.mergingComputed(computed(nil), into: displayed).heartCharts, displayedCharts)
    }

    // MARK: - Reset refusal

    func testComputeNeverRepopulatesAResetTombstone() {
        let merged = WatchComputeMerge.mergingComputed(
            computed([heartRate: chart(endingAt: t2, average: 70)]),
            into: snapshot(isReset: true)
        )
        XCTAssertNil(merged.heartCharts)
        XCTAssertEqual(merged.isReset, true)
    }

    // MARK: - Phone push → displayed

    /// The phone never sends charts, so an ordinary push keeps the local
    /// ones while it carries each kind's card.
    func testAPushKeepsTheLocalCharts() {
        let displayed = snapshot(metrics: [card(heartRate), card(hrv)], heartCharts: displayedCharts)
        let push = snapshot(metrics: [card(heartRate), card(hrv)], generatedAt: t3)
        XCTAssertNil(push.heartCharts)

        XCTAssertEqual(WatchComputeMerge.merging(push, over: displayed).heartCharts, displayedCharts)
    }

    /// A push without a kind's card takes that kind's chart and only that
    /// one; without either card (Heart turned off) the field goes nil.
    func testAPushWithoutTheHeartRateCardDropsOnlyItsChart() {
        let displayed = snapshot(metrics: [card(heartRate), card(hrv)], heartCharts: displayedCharts)

        let withoutHeartRate = snapshot(metrics: [card(hrv)], generatedAt: t3)
        XCTAssertEqual(
            WatchComputeMerge.merging(withoutHeartRate, over: displayed).heartCharts,
            [hrv: chart(endingAt: t1, average: 48)]
        )

        let heartOff = snapshot(metrics: [card(WatchMetricKindKey.readiness)], generatedAt: t3)
        XCTAssertNil(WatchComputeMerge.merging(heartOff, over: displayed).heartCharts)
    }

    /// The settings-change push was built under the new source selection,
    /// while the charts were read under the old one.
    func testTheSettingsChangeModeDropsEveryChart() {
        let displayed = snapshot(metrics: [card(heartRate), card(hrv)], heartCharts: displayedCharts)
        let push = snapshot(metrics: [card(heartRate), card(hrv)], generatedAt: t3)

        XCTAssertNil(WatchComputeMerge.merging(push, over: displayed, treatingBlanksAsAuthoritative: true).heartCharts)
    }

    /// A permission or data source change strips the local provenance before
    /// the push resolves, and no push brings the charts back: they wait for
    /// the next compute.
    func testStrippingLocalProvenanceDropsEveryChart() {
        let displayed = snapshot(metrics: [card(heartRate), card(hrv)], heartCharts: displayedCharts)
        let stripped = WatchComputeMerge.strippingLocalProvenance(from: displayed)
        XCTAssertNil(stripped.heartCharts)

        let push = snapshot(metrics: [card(heartRate), card(hrv)], generatedAt: t3)
        XCTAssertNil(WatchComputeMerge.merging(push, over: stripped).heartCharts)
        XCTAssertNil(WatchComputeMerge.merging(push, over: stripped, treatingBlanksAsAuthoritative: true).heartCharts)
    }
}
