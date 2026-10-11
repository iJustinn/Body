//
//  WatchHeartChartsMergeTests.swift
//  BodyTests
//
//  Locks how the Heart Rate, HRV and Blood Oxygen chart complications' slots
//  (`WatchMetricsSnapshot.heartCharts`) are built by the watch compute
//  (`WatchComputeAssembly.heartCharts(delta:permission:)`) and move through
//  the watch's merges (`WatchComputeMerge`). For Heart Rate and HRV only a
//  watch compute writes the field, so the rules are:
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
//  * a phone push, which never carries their charts, keeps each local chart
//    while it carries that kind's card, and the settings-change mode and a
//    permission or data source change (the provenance strip) drop them all.
//  Blood Oxygen's chart is built by both devices (the iPhone from its own
//  readings, the only source on a watch whose blood oxygen it calculates),
//  so both merges combine its slots instead: the later window, the union of
//  both charts' slots inside it, and the later chart's slot where both have
//  one. Each kind rides its own permission, and a watch with no blood oxygen
//  source carries no Blood Oxygen chart, so the iPhone's stands.
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
    private let oxygen = WatchMetricKindKey.oxygenSaturation

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

    // MARK: - Blood Oxygen: built by both devices, combined

    /// A Blood Oxygen chart read at `minutes` past 16:00 UTC on 2026-06-04
    /// (so on a fixed half hour grid: up to 16:29 the window opens at 08:00,
    /// from 16:30 at 08:30), with one slot per `(slot, average)`, slot `k`
    /// starting `k` half hours after 08:00.
    private func oxygenChart(endingAtMinute minutes: Double, slots: [(slot: Int, average: Double)]) -> WatchIntradayChart {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let base = utc.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 8))!
        let window = WatchIntradayWindow.endingAt(base.addingTimeInterval((8 * 60 + minutes) * 60), calendar: utc)
        return WatchIntradayChart(window: window, buckets: slots.map { slot in
            WatchIntradayBucket(
                start: base.addingTimeInterval(Double(slot.slot) * WatchIntradayWindow.slotLength),
                minimum: slot.average - 1,
                maximum: slot.average + 1,
                average: slot.average
            )
        })
    }

    func testTheComputeGatesEachKindOnItsOwnPermission() {
        let heartRead = chart(endingAt: t2, average: 70)
        let oxygenRead = oxygenChart(endingAtMinute: 40, slots: [(16, 97)])
        var delta = WatchComputeDelta()
        delta.heartRateIntraday = .success(heartRead)
        delta.oxygenSaturationIntraday = .success(oxygenRead)

        XCTAssertEqual(
            WatchComputeAssembly.heartCharts(delta: delta, permission: .defaultValue),
            [heartRate: heartRead, oxygen: oxygenRead]
        )
        let heartOff = BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false)
        XCTAssertEqual(WatchComputeAssembly.heartCharts(delta: delta, permission: heartOff), [oxygen: oxygenRead])
        let oxygenOff = BodyHealthPermissionSelection.defaultValue.setting(.bloodOxygen, isEnabled: false)
        XCTAssertEqual(WatchComputeAssembly.heartCharts(delta: delta, permission: oxygenOff), [heartRate: heartRead])
        XCTAssertNil(WatchComputeAssembly.heartCharts(delta: delta, permission: heartOff.setting(.bloodOxygen, isEnabled: false)))
    }

    /// A watch with no blood oxygen source (one whose readings the iPhone
    /// calculates) reads an empty chart (`WatchSourceRead.unavailable`),
    /// which proves nothing: the compute carries no Blood Oxygen chart, and
    /// the iPhone's stands through the merge.
    func testACarriedBloodOxygenCarriesNoChartAndLeavesThePhones() {
        var delta = WatchComputeDelta()
        delta.oxygenSaturationIntraday = .success(oxygenChart(endingAtMinute: 50, slots: []))
        delta.carriedKinds = [.oxygenSaturation]
        XCTAssertNil(WatchComputeAssembly.heartCharts(delta: delta, permission: .defaultValue))

        delta.heartRateIntraday = .success(chart(endingAt: t2, average: 70))
        let charts = WatchComputeAssembly.heartCharts(delta: delta, permission: .defaultValue)
        XCTAssertEqual(charts?.keys.sorted(), [heartRate])

        let phones = oxygenChart(endingAtMinute: 20, slots: [(3, 95), (15, 96)])
        let merged = WatchComputeMerge.mergingComputed(computed(charts), into: snapshot(heartCharts: [oxygen: phones]))
        XCTAssertEqual(merged.heartCharts?[oxygen], phones)
    }

    /// The compute's slots join the displayed (pushed) ones on the later
    /// window, the compute's winning the slot both read.
    func testAComputeCombinesItsSlotsWithTheDisplayedOnes() {
        let pushed = oxygenChart(endingAtMinute: 35, slots: [(2, 95), (10, 96)])
        let read = oxygenChart(endingAtMinute: 45, slots: [(10, 98), (15, 97)])
        let merged = WatchComputeMerge.mergingComputed(computed([oxygen: read]), into: snapshot(heartCharts: [oxygen: pushed]))

        XCTAssertEqual(merged.heartCharts?[oxygen], WatchIntradayChart(
            window: read.window,
            buckets: oxygenChart(endingAtMinute: 45, slots: [(2, 95), (10, 98), (15, 97)]).buckets
        ))

        // Over nothing, the read is taken as is.
        XCTAssertEqual(WatchComputeMerge.mergingComputed(computed([oxygen: read]), into: snapshot()).heartCharts, [oxygen: read])
    }

    /// The iPhone's push can be built from samples it read a while ago: its
    /// slots join the watch's newer ones rather than replacing them, and the
    /// chart whose window ends later wins a slot both have.
    func testAStalePushKeepsTheWatchsNewerSlots() {
        let watchRead = oxygenChart(endingAtMinute: 50, slots: [(14, 97), (16, 98)])
        let displayed = snapshot(metrics: [card(oxygen)], heartCharts: [oxygen: watchRead])

        let stale = snapshot(
            metrics: [card(oxygen)],
            generatedAt: t3,
            heartCharts: [oxygen: oxygenChart(endingAtMinute: 40, slots: [(3, 94), (14, 95)])]
        )
        XCTAssertEqual(
            WatchComputeMerge.merging(stale, over: displayed).heartCharts?[oxygen],
            WatchIntradayChart(window: watchRead.window, buckets: oxygenChart(endingAtMinute: 50, slots: [(3, 94), (14, 97), (16, 98)]).buckets),
            "the watch's window is later, so its slot 14 stands and the push only adds slot 3"
        )

        let later = snapshot(
            metrics: [card(oxygen)],
            generatedAt: t3,
            heartCharts: [oxygen: oxygenChart(endingAtMinute: 55, slots: [(14, 95)])]
        )
        let laterWindow = oxygenChart(endingAtMinute: 55, slots: []).window
        XCTAssertEqual(
            WatchComputeMerge.merging(later, over: displayed).heartCharts?[oxygen],
            WatchIntradayChart(window: laterWindow, buckets: oxygenChart(endingAtMinute: 55, slots: [(14, 95), (16, 98)]).buckets),
            "a later push wins the shared slot and keeps the watch's other one"
        )
    }

    /// Only the slots inside the later window survive, and an empty read
    /// just moves the window on (nothing left: no chart).
    func testSlotsBeforeTheLaterWindowDropAndAnEmptyReadOnlyMovesTheWindow() {
        let displayed = snapshot(heartCharts: [oxygen: oxygenChart(endingAtMinute: 20, slots: [(0, 96), (1, 97), (12, 95)])])
        let read = oxygenChart(endingAtMinute: 35, slots: [(16, 98)])
        XCTAssertEqual(read.window.start, oxygenChart(endingAtMinute: 0, slots: []).window.start.addingTimeInterval(WatchIntradayWindow.slotLength))

        XCTAssertEqual(
            WatchComputeMerge.mergingComputed(computed([oxygen: read]), into: displayed).heartCharts?[oxygen]?.buckets,
            oxygenChart(endingAtMinute: 35, slots: [(1, 97), (12, 95), (16, 98)]).buckets,
            "slot 0 (08:00) is before the 08:30 window"
        )

        let empty = oxygenChart(endingAtMinute: 35, slots: [])
        XCTAssertEqual(
            WatchComputeMerge.mergingComputed(computed([oxygen: empty]), into: displayed).heartCharts?[oxygen],
            WatchIntradayChart(window: empty.window, buckets: oxygenChart(endingAtMinute: 35, slots: [(1, 97), (12, 95)]).buckets)
        )

        let onlyOld = snapshot(heartCharts: [oxygen: oxygenChart(endingAtMinute: 20, slots: [(0, 96)])])
        XCTAssertNil(WatchComputeMerge.mergingComputed(computed([oxygen: empty]), into: onlyOld).heartCharts, "never stored empty")
        XCTAssertNil(WatchComputeMerge.mergingComputed(computed([oxygen: empty]), into: snapshot()).heartCharts)
    }

    /// A push with Blood Oxygen's chart keeps the local Heart Rate and HRV
    /// charts beside it; one without the Blood Oxygen card drops its chart,
    /// whichever side read it.
    func testAPushCarriesItsBloodOxygenChartBesideTheLocalHeartCharts() {
        let pushedChart = oxygenChart(endingAtMinute: 40, slots: [(5, 96)])
        let displayed = snapshot(metrics: [card(heartRate), card(hrv)], heartCharts: displayedCharts)
        let push = snapshot(metrics: [card(heartRate), card(hrv), card(oxygen)], generatedAt: t3, heartCharts: [oxygen: pushedChart])

        var expected = displayedCharts
        expected[oxygen] = pushedChart
        XCTAssertEqual(WatchComputeMerge.merging(push, over: displayed).heartCharts, expected)
        XCTAssertEqual(WatchComputeMerge.merging(push, over: snapshot()).heartCharts, [oxygen: pushedChart])

        let withLocalOxygen = snapshot(
            metrics: [card(oxygen)],
            heartCharts: [oxygen: oxygenChart(endingAtMinute: 45, slots: [(15, 97)])]
        )
        let withoutCard = snapshot(metrics: [card(heartRate)], generatedAt: t3, heartCharts: [oxygen: pushedChart])
        XCTAssertNil(WatchComputeMerge.merging(withoutCard, over: withLocalOxygen).heartCharts)
        XCTAssertNil(WatchComputeMerge.merging(withoutCard, over: snapshot()).heartCharts)
    }

    /// The settings-change push was built under the new source selection:
    /// the local charts go and the push's Blood Oxygen chart is taken as is,
    /// never an empty one.
    func testTheSettingsChangeModeTakesThePushedBloodOxygenChartAsIs() {
        let displayed = snapshot(
            metrics: [card(heartRate), card(oxygen)],
            heartCharts: [heartRate: chart(endingAt: t1, average: 62), oxygen: oxygenChart(endingAtMinute: 45, slots: [(15, 97)])]
        )
        let pushedChart = oxygenChart(endingAtMinute: 40, slots: [(5, 96)])
        let push = snapshot(metrics: [card(heartRate), card(oxygen)], generatedAt: t3, heartCharts: [oxygen: pushedChart])
        XCTAssertEqual(
            WatchComputeMerge.merging(push, over: displayed, treatingBlanksAsAuthoritative: true).heartCharts,
            [oxygen: pushedChart]
        )

        let emptyPush = snapshot(
            metrics: [card(heartRate), card(oxygen)],
            generatedAt: t3,
            heartCharts: [oxygen: oxygenChart(endingAtMinute: 40, slots: [])]
        )
        XCTAssertNil(WatchComputeMerge.merging(emptyPush, over: displayed, treatingBlanksAsAuthoritative: true).heartCharts)
    }

    /// The wiring: `assemble` puts the Blood Oxygen read in the snapshot
    /// beside Heart Rate's.
    func testTheComputedSnapshotCarriesTheBloodOxygenRead() throws {
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
            settingsSignature: "sig-oxygen-chart"
        )
        let read = oxygenChart(endingAtMinute: 40, slots: [(16, 97)])
        var delta = WatchComputeDelta()
        delta.oxygenSaturationIntraday = .success(read)
        let snapshot = try XCTUnwrap(WatchComputeAssembly.assemble(
            seed: seed,
            delta: delta,
            permission: .defaultValue,
            generation: 1,
            windowStart: WatchDeltaSplicer.deltaStart(dataThrough: now, calendar: calendar),
            now: now,
            calendar: calendar
        )).snapshot
        XCTAssertEqual(snapshot.heartCharts, [oxygen: read])
    }
}
