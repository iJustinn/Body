//
//  WatchComputeMergeTests.swift
//  BodyTests
//
//  Locks the freshest-wins-per-metric merge that lets the watch compute its own
//  metrics without ever fighting the iPhone (`WatchComputeMerge`).
//
//  The rules under test are the ones that made the June 2026 standalone-compute
//  attempt unsafe:
//  * anti-laundering — only kinds the compute genuinely re-read (present in
//    `dataAsOf`) may be adopted or re-stamped; a seed-carried value must never
//    be presented as freshly measured;
//  * a phone push that lands mid-compute wins;
//  * the phone's publication line (`generatedAt`/`publisherEpoch`/`revision`)
//    is never advanced by a local compute;
//  * a Clear-Cache tombstone is never repopulated.
//
//  This is the BodyTests MIRROR of `BodyWatchTests/WatchComputeMergeTests`:
//  `WatchComputeMerge` lives in `BodyWatchSnapshotKit` and compiles into both
//  apps, and the watch test scheme is unproven from CLI, so the critical
//  semantics run in the iOS suite too (precedent:
//  `BodyTests/WatchMetricHasValueTests`). Keep the two files in step.
//

import XCTest
@testable import Body

final class WatchComputeMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_600)
    private let t2 = Date(timeIntervalSince1970: 1_001_200)
    private let t3 = Date(timeIntervalSince1970: 1_001_800)

    // MARK: - Fixtures

    private func metric(
        _ kind: String,
        displayValue: String,
        rawValue: Double?,
        score: Int? = nil,
        fillFraction: Double = 0.5,
        levelMin: Double? = nil,
        levelMax: Double? = nil,
        tint: WatchMetricColor? = nil,
        weekly: [Double?]? = nil,
        statusBand: WatchStatusBand? = nil,
        weeklyCurrentValue: Double? = nil,
        liveUpdatedAt: Date? = nil,
        computedAt: Date? = nil,
        measuredAt: Date? = nil
    ) -> WatchMetric {
        WatchMetric(
            kind: kind,
            title: kind,
            displayValue: displayValue,
            unit: "bpm",
            score: score,
            fillFraction: fillFraction,
            rawValue: rawValue,
            rangeMin: 40,
            rangeMax: 100,
            levelMin: levelMin,
            levelMax: levelMax,
            liveUpdatedAt: liveUpdatedAt,
            computedAt: computedAt,
            measuredAt: measuredAt,
            tint: tint,
            weekly: weekly,
            statusBand: statusBand,
            weeklyCurrentValue: weeklyCurrentValue
        )
    }

    private func snapshot(
        metrics: [WatchMetric],
        generatedAt: Date,
        lastRefreshDate: Date?,
        sleepNight: Date? = nil,
        sleepStages: [WatchSleepStageSegment]? = nil,
        isReset: Bool? = nil
    ) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(
            generatedAt: generatedAt,
            lastRefreshDate: lastRefreshDate,
            metrics: metrics,
            source: "phone",
            sleepNight: sleepNight,
            sleepStages: sleepStages,
            publisherEpoch: "epoch-A",
            revision: 7,
            isReset: isReset
        )
    }

    /// A one-segment stage bar, distinguished by its `stage` so the assertions
    /// can tell the phone's night from the watch's.
    private func stages(_ stage: String) -> [WatchSleepStageSegment] {
        [WatchSleepStageSegment(stage: stage, startDate: t0, endDate: t1)]
    }

    private func result(
        metrics: [WatchMetric],
        dataAsOf: [String: Date],
        chartDataAsOf: [String: Date] = [:],
        sleepNight: Date? = nil,
        sleepStages: [WatchSleepStageSegment]? = nil,
        coverage: Date? = nil,
        generation: UInt64 = 3
    ) -> WatchComputeResult {
        var computed = WatchMetricsSnapshot(
            generatedAt: t2,
            lastRefreshDate: t2,
            metrics: metrics,
            sleepNight: sleepNight,
            sleepStages: sleepStages
        )
        computed.source = "watch"
        // Default coverage `t2`: "the compute's queries ran at t2" — the
        // information cutoff compared against PHONE-derived stamps.
        return WatchComputeResult(
            snapshot: computed,
            dataAsOf: dataAsOf,
            chartDataAsOf: chartDataAsOf,
            coverage: coverage ?? t2,
            generation: generation
        )
    }

    // MARK: - Anti-laundering: only kinds in `dataAsOf` are candidates

    func testKindAbsentFromDataAsOfIsNeverAdopted() {
        // The compute re-emitted a Training Load value that came entirely from
        // the seed (no watch workouts in the window), so it carries no
        // watermark and must not touch the displayed card.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.trainingLoad, displayValue: "1.05", rawValue: 1.05, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.trainingLoad, displayValue: "1.42", rawValue: 1.42)],
                dataAsOf: [:]
            ),
            into: current
        )

        let trainingLoad = merged.metric(forKind: WatchMetricKindKey.trainingLoad)
        XCTAssertEqual(trainingLoad?.rawValue, 1.05)
        XCTAssertEqual(trainingLoad?.computedAt, t0, "A seed-carried value must not be re-stamped as fresh.")
    }

    func testKindInDataAsOfIsAdoptedAndStampedWithItsWatermark() {
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "71", rawValue: 71)],
                dataAsOf: [WatchMetricKindKey.heartRate: t1]
            ),
            into: current
        )

        let heartRate = merged.metric(forKind: WatchMetricKindKey.heartRate)
        XCTAssertEqual(heartRate?.rawValue, 71)
        XCTAssertEqual(heartRate?.displayValue, "71")
        // Stamped with the DATA's watermark, never `now` — that's what keeps the
        // per-kind staleness comparison honest across repeated computes.
        XCTAssertEqual(heartRate?.liveUpdatedAt, t1)
        XCTAssertEqual(heartRate?.computedAt, t1)
    }

    func testAdoptionCarriesTheFullDisplayFieldSet() {
        let current = snapshot(
            metrics: [
                metric(
                    WatchMetricKindKey.readiness,
                    displayValue: "55", rawValue: 55, score: 55, fillFraction: 0.55,
                    levelMin: 50, levelMax: 64,
                    tint: WatchMetricColor(red: 1, green: 0, blue: 0),
                    weekly: [50, 51, 52, 53, 54, 55, 55],
                    statusBand: WatchStatusBand(min: 50, max: 64, label: "Fair"),
                    weeklyCurrentValue: 48,
                    computedAt: t0
                )
            ],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [
                    metric(
                        WatchMetricKindKey.readiness,
                        displayValue: "84", rawValue: 84, score: 84, fillFraction: 0.84,
                        levelMin: 80, levelMax: 94,
                        tint: WatchMetricColor(red: 0, green: 1, blue: 0),
                        weekly: [60, 62, 70, 75, 80, 82, 84],
                        statusBand: WatchStatusBand(min: 80, max: 94, label: "High"),
                        weeklyCurrentValue: 79
                    )
                ],
                dataAsOf: [WatchMetricKindKey.readiness: t1]
            ),
            into: current
        )

        // Score, band, level bounds and tint are computed together and must
        // travel together, or the ring reads one status and the label another.
        let readiness = merged.metric(forKind: WatchMetricKindKey.readiness)
        XCTAssertEqual(readiness?.score, 84)
        XCTAssertEqual(readiness?.fillFraction, 0.84)
        XCTAssertEqual(readiness?.levelMin, 80)
        XCTAssertEqual(readiness?.levelMax, 94)
        XCTAssertEqual(readiness?.statusBand?.label, "High")
        XCTAssertEqual(readiness?.tint, WatchMetricColor(red: 0, green: 1, blue: 0))
        XCTAssertEqual(readiness?.weekly?.last, 84)
        XCTAssertEqual(readiness?.weeklyCurrentValue, 79)
    }

    func testAdoptionWithoutADrainedValueClearsTheStaleDot() {
        // The candidate's nil is "no drain per this compute": keeping the
        // replaced payload's drained value would pin a stale dot under the
        // adopted score.
        let current = snapshot(
            metrics: [
                metric(
                    WatchMetricKindKey.readiness,
                    displayValue: "55", rawValue: 55, score: 55, fillFraction: 0.55,
                    weeklyCurrentValue: 48,
                    computedAt: t0
                )
            ],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [
                    metric(
                        WatchMetricKindKey.readiness,
                        displayValue: "84", rawValue: 84, score: 84, fillFraction: 0.84
                    )
                ],
                dataAsOf: [WatchMetricKindKey.readiness: t1]
            ),
            into: current
        )

        let readiness = merged.metric(forKind: WatchMetricKindKey.readiness)
        XCTAssertEqual(readiness?.score, 84)
        XCTAssertNil(readiness?.weeklyCurrentValue)
    }

    // MARK: - Blank preserve

    func testBlankComputedValueNeverOverwritesAGoodDisplayedOne() {
        // On the watch a blank means "no local data", not an authoritative
        // clear — the deliberate asymmetry against the phone-push rule.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 32m", rawValue: 85, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.sleep, displayValue: "--", rawValue: nil)],
                dataAsOf: [WatchMetricKindKey.sleep: t1]
            ),
            into: current
        )

        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.sleep)?.displayValue, "7h 32m")
    }

    // MARK: - Staleness / mid-compute phone push

    func testComputedValueOlderThanWhatIsDisplayedIsSkipped() {
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62, liveUpdatedAt: t2)],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "58", rawValue: 58)],
                dataAsOf: [WatchMetricKindKey.heartRate: t1]
            ),
            into: current
        )

        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.heartRate)?.rawValue, 62)
        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.heartRate)?.liveUpdatedAt, t2)
    }

    func testPhonePushThatLandedMidComputeWins() {
        // The push (computedAt t2) arrived while the compute (coverage t1,
        // i.e. its queries ran BEFORE the push) was in flight; the merge must
        // not roll the card back — the push's stamp is newer than the
        // compute's information cutoff.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.restingHeartRate, displayValue: "54", rawValue: 54, computedAt: t2)],
            generatedAt: t2,
            lastRefreshDate: t2
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.restingHeartRate, displayValue: "60", rawValue: 60)],
                dataAsOf: [WatchMetricKindKey.restingHeartRate: t1],
                coverage: t1
            ),
            into: current
        )

        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.restingHeartRate)?.rawValue, 54)
    }

    func testUnstampedDisplayedMetricFallsBackToSnapshotRefreshDate() {
        // A legacy metric with no per-kind stamps is dated by the snapshot's
        // own `lastRefreshDate`, so a compute older than the push still loses.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62)],
            generatedAt: t2,
            lastRefreshDate: t2
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "58", rawValue: 58)],
                dataAsOf: [WatchMetricKindKey.heartRate: t1]
            ),
            into: current
        )

        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.heartRate)?.rawValue, 62)
    }

    // MARK: - The phone's publication line is never advanced

    func testPublicationLineAndSnapshotIdentityAreUntouched() {
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "71", rawValue: 71)],
                dataAsOf: [WatchMetricKindKey.heartRate: t1]
            ),
            into: current
        )

        XCTAssertEqual(merged.generatedAt, t0)
        XCTAssertEqual(merged.lastRefreshDate, t0)
        XCTAssertEqual(merged.publisherEpoch, "epoch-A")
        XCTAssertEqual(merged.revision, 7)
        XCTAssertEqual(merged.source, "phone")
        XCTAssertNil(merged.isReset)
        // A later phone publish must still supersede the merged snapshot.
        let laterPush = snapshot(metrics: [], generatedAt: t2, lastRefreshDate: t2)
        var withHigherRevision = laterPush
        withHigherRevision.revision = 8
        XCTAssertTrue(withHigherRevision.supersedes(merged))
    }

    // MARK: - Appending kinds the displayed snapshot lacks

    func testMissingKindIsAppendedOnlyWhenItHasAWatermark() {
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [
                    metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62),
                    metric(WatchMetricKindKey.restingHeartRate, displayValue: "54", rawValue: 54),
                    metric(WatchMetricKindKey.heartRateVariability, displayValue: "48", rawValue: 48)
                ],
                dataAsOf: [WatchMetricKindKey.restingHeartRate: t1]
            ),
            into: current
        )

        XCTAssertNotNil(merged.metric(forKind: WatchMetricKindKey.restingHeartRate))
        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.restingHeartRate)?.computedAt, t1)
        XCTAssertNil(
            merged.metric(forKind: WatchMetricKindKey.heartRateVariability),
            "A kind without a watermark must not be appended."
        )
    }

    func testBlankMissingKindIsNotAppended() {
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.sleep, displayValue: "--", rawValue: nil)],
                dataAsOf: [WatchMetricKindKey.sleep: t1]
            ),
            into: current
        )

        XCTAssertNil(merged.metric(forKind: WatchMetricKindKey.sleep))
    }

    // MARK: - sleepNight ownership

    func testSleepNightMovesOnlyWithTheSleepMetric() {
        let phoneNight = t0
        let watchNight = t2
        let current = snapshot(
            metrics: [
                metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62, computedAt: t0),
                metric(WatchMetricKindKey.sleep, displayValue: "7h 32m", rawValue: 85, computedAt: t2)
            ],
            generatedAt: t0,
            lastRefreshDate: t0,
            sleepNight: phoneNight
        )

        // Sleep is NOT adopted (its displayed stamp is newer) — the night stays.
        let withoutSleep = WatchComputeMerge.mergingComputed(
            result(
                metrics: [
                    metric(WatchMetricKindKey.heartRate, displayValue: "71", rawValue: 71),
                    metric(WatchMetricKindKey.sleep, displayValue: "6h 02m", rawValue: 70)
                ],
                dataAsOf: [WatchMetricKindKey.heartRate: t1, WatchMetricKindKey.sleep: t1],
                sleepNight: watchNight
            ),
            into: current
        )
        XCTAssertEqual(withoutSleep.metric(forKind: WatchMetricKindKey.heartRate)?.rawValue, 71)
        XCTAssertEqual(withoutSleep.sleepNight, phoneNight)

        // Sleep IS adopted — the night moves with it, so the midnight guard in
        // `sanitized(asOf:)` judges the night that's actually on the card.
        let currentWithOlderSleep = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 32m", rawValue: 85, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0,
            sleepNight: phoneNight
        )
        let withSleep = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.sleep, displayValue: "6h 02m", rawValue: 70)],
                dataAsOf: [WatchMetricKindKey.sleep: t1],
                sleepNight: watchNight
            ),
            into: currentWithOlderSleep
        )
        XCTAssertEqual(withSleep.sleepNight, watchNight)
    }

    func testSleepStagesMoveOnlyWithTheSleepMetric() {
        let current = snapshot(
            metrics: [
                metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62, computedAt: t0),
                metric(WatchMetricKindKey.sleep, displayValue: "7h 32m", rawValue: 85, computedAt: t2)
            ],
            generatedAt: t0,
            lastRefreshDate: t0,
            sleepNight: t0,
            sleepStages: stages("core")
        )

        // Sleep is NOT adopted (its displayed stamp is newer) — the bar stays
        // the one belonging to the card on screen.
        let withoutSleep = WatchComputeMerge.mergingComputed(
            result(
                metrics: [
                    metric(WatchMetricKindKey.heartRate, displayValue: "71", rawValue: 71),
                    metric(WatchMetricKindKey.sleep, displayValue: "6h 02m", rawValue: 70)
                ],
                dataAsOf: [WatchMetricKindKey.heartRate: t1, WatchMetricKindKey.sleep: t1],
                sleepNight: t2,
                sleepStages: stages("rem")
            ),
            into: current
        )
        XCTAssertEqual(withoutSleep.sleepStages, stages("core"))

        // Sleep IS adopted — the bar moves with it, so the complication draws
        // the night the card actually shows.
        let currentWithOlderSleep = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 32m", rawValue: 85, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0,
            sleepNight: t0,
            sleepStages: stages("core")
        )
        let withSleep = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.sleep, displayValue: "6h 02m", rawValue: 70)],
                dataAsOf: [WatchMetricKindKey.sleep: t1],
                sleepNight: t2,
                sleepStages: stages("rem")
            ),
            into: currentWithOlderSleep
        )
        XCTAssertEqual(withSleep.sleepStages, stages("rem"))
    }

    // MARK: - Phone push: the night and its bar follow the surviving sleep card

    func testPushKeepsTheLocalNightAndStagesBehindAPreservedSleepCard() {
        // Blank-preserve: the phone had no trusted night to publish, so its
        // card is "--" and its night/stages are nil. The local reading stands —
        // and must keep its own night, or `sanitized(asOf:)` would blank the
        // very value that was just preserved.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 32m", rawValue: 85, computedAt: t1)],
            generatedAt: t1,
            lastRefreshDate: t1,
            sleepNight: t1,
            sleepStages: stages("core")
        )
        let push = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "--", rawValue: nil, computedAt: t2)],
            generatedAt: t2,
            lastRefreshDate: t2
        )

        let merged = WatchComputeMerge.merging(push, over: current)

        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.sleep)?.rawValue, 85)
        XCTAssertEqual(merged.sleepNight, t1)
        XCTAssertEqual(merged.sleepStages, stages("core"))
    }

    func testPushKeepsTheLocalNightAndStagesBehindAFresherWatchComputedSleepCard() {
        let current = snapshot(
            metrics: [
                metric(
                    WatchMetricKindKey.sleep,
                    displayValue: "7h 32m", rawValue: 85,
                    liveUpdatedAt: t2, computedAt: t2
                )
            ],
            generatedAt: t1,
            lastRefreshDate: t1,
            sleepNight: t2,
            sleepStages: stages("rem")
        )
        let push = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "6h 02m", rawValue: 70, computedAt: t1)],
            generatedAt: t1,
            lastRefreshDate: t1,
            sleepNight: t0,
            sleepStages: stages("core")
        )

        let merged = WatchComputeMerge.merging(push, over: current)

        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.sleep)?.rawValue, 85)
        XCTAssertEqual(merged.sleepNight, t2)
        XCTAssertEqual(merged.sleepStages, stages("rem"))
    }

    func testPushOwnsTheNightAndStagesWhenItsSleepCardWins() {
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 32m", rawValue: 85, computedAt: t0)],
            generatedAt: t0,
            lastRefreshDate: t0,
            sleepNight: t0,
            sleepStages: stages("rem")
        )
        let push = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "6h 02m", rawValue: 70, computedAt: t2)],
            generatedAt: t2,
            lastRefreshDate: t2,
            sleepNight: t2,
            sleepStages: stages("core")
        )

        let merged = WatchComputeMerge.merging(push, over: current)

        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.sleep)?.rawValue, 70)
        XCTAssertEqual(merged.sleepNight, t2)
        XCTAssertEqual(merged.sleepStages, stages("core"))
    }

    // MARK: - Watermark domains (coverage vs event)

    func testEventOlderThanPhoneRefreshStillAdoptsWhenComputeCoverageIsNewer() {
        // The reviewer scenario the coverage compare exists for: the night
        // ended at t0, the phone refreshed at t1 WITHOUT that night (it hadn't
        // synced) and pushed a blank card stamped t1, then the watch computed
        // at t2 and found the night locally. Event t0 < phone stamp t1, but the
        // compute's information cutoff t2 is newer — the offline sleep update
        // must land, stamped with the night's own end.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "--", rawValue: nil, computedAt: t1)],
            generatedAt: t1,
            lastRefreshDate: t1
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 30m", rawValue: 27_000)],
                dataAsOf: [WatchMetricKindKey.sleep: t0],
                sleepNight: t0,
                coverage: t2
            ),
            into: current
        )

        let sleep = merged.metric(forKind: WatchMetricKindKey.sleep)
        XCTAssertEqual(sleep?.rawValue, 27_000)
        XCTAssertEqual(sleep?.liveUpdatedAt, t0, "stamped with the EVENT watermark, not the coverage")
        XCTAssertEqual(sleep?.computedAt, t0)
    }

    func testOlderEventNeverRollsBackANonblankPhoneCardEvenWithNewerCoverage() {
        // HealthKit replication lag: the phone refreshed at t1 having seen a
        // sample the watch hasn't replicated yet; the watch's own "latest"
        // (event t0) is older. Coverage t2 is newer than the phone stamp, but
        // a NONBLANK phone card must not roll back to the older reading —
        // the phone's refresh saw everything synced by t1.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.restingHeartRate, displayValue: "52", rawValue: 52, computedAt: t1)],
            generatedAt: t1,
            lastRefreshDate: t1
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.restingHeartRate, displayValue: "57", rawValue: 57)],
                dataAsOf: [WatchMetricKindKey.restingHeartRate: t0],
                coverage: t2
            ),
            into: current
        )

        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.restingHeartRate)?.rawValue, 52)
    }

    func testFullerNightDisplacesANonblankPhoneSleepCardWhenItsNightEndsLater() {
        // The phone refreshed at t2 before the watch's full night had synced
        // over, so its NONBLANK card shows a partial night ending t0. The
        // watch computed the full night (event end t1, still older than the
        // phone's query stamp t2): the query-time compare would pin the
        // partial night for the rest of the day — no newer sleep event
        // arrives until tomorrow — but sleep ships its event watermark, so
        // t1 > t0 wins event-to-event.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "4h 10m", rawValue: 15_000, computedAt: t2, measuredAt: t0)],
            generatedAt: t2,
            lastRefreshDate: t2,
            sleepNight: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 30m", rawValue: 27_000, measuredAt: t1)],
                dataAsOf: [WatchMetricKindKey.sleep: t1],
                sleepNight: t1,
                coverage: t3
            ),
            into: current
        )

        let sleep = merged.metric(forKind: WatchMetricKindKey.sleep)
        XCTAssertEqual(sleep?.rawValue, 27_000)
        XCTAssertEqual(sleep?.liveUpdatedAt, t1)
        XCTAssertEqual(merged.sleepNight, t1)
        XCTAssertEqual(sleep?.measuredAt, t1, "the event watermark moves with the adopted value")
    }

    func testSameNightEndNeverDisplacesANonblankPhoneSleepCard() {
        // Equal event ends mean both devices describe the same night — there
        // is no newer sleep information, so the phone's card stands.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 30m", rawValue: 27_000, computedAt: t2, measuredAt: t1)],
            generatedAt: t2,
            lastRefreshDate: t2,
            sleepNight: t1
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 10m", rawValue: 26_000, measuredAt: t1)],
                dataAsOf: [WatchMetricKindKey.sleep: t1],
                sleepNight: t1,
                coverage: t3
            ),
            into: current
        )
        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.sleep)?.rawValue, 27_000)
    }

    func testNewerWatchSampleDisplacesANonblankPhoneVitalsCardWithAnOlderMeasurement() {
        // Replication lag, vitals edition: the phone's refresh at t2 shipped a
        // reading MEASURED at t0; the watch's own sample (event t1) is newer
        // than that measurement but older than the phone's query. The
        // event-to-event compare through `measuredAt` adopts it — the
        // query-time compare would reject the genuinely newer measurement.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.restingHeartRate, displayValue: "52", rawValue: 52, computedAt: t2, measuredAt: t0)],
            generatedAt: t2,
            lastRefreshDate: t2
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.restingHeartRate, displayValue: "57", rawValue: 57, measuredAt: t1)],
                dataAsOf: [WatchMetricKindKey.restingHeartRate: t1],
                coverage: t3
            ),
            into: current
        )

        let restingHeartRate = merged.metric(forKind: WatchMetricKindKey.restingHeartRate)
        XCTAssertEqual(restingHeartRate?.rawValue, 57)
        XCTAssertEqual(restingHeartRate?.measuredAt, t1)
    }

    func testWatchSampleOlderThanThePhonesMeasurementStillNeverRollsBack() {
        // The phone's reading was measured at t1; the watch's latest is t0 —
        // genuinely older information stays rejected even with newer coverage.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.restingHeartRate, displayValue: "52", rawValue: 52, computedAt: t2, measuredAt: t1)],
            generatedAt: t2,
            lastRefreshDate: t2
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.restingHeartRate, displayValue: "57", rawValue: 57, measuredAt: t0)],
                dataAsOf: [WatchMetricKindKey.restingHeartRate: t0],
                coverage: t3
            ),
            into: current
        )
        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.restingHeartRate)?.rawValue, 52)
    }

    func testNonblankSleepWithoutANightEndKeepsTheQueryTimeCompare() {
        // Legacy payload (no `measuredAt`): the conservative rule stands —
        // an event older than the phone's query stamp cannot displace a
        // nonblank card.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.sleep, displayValue: "6h 0m", rawValue: 21_600, computedAt: t1)],
            generatedAt: t1,
            lastRefreshDate: t1,
            sleepNight: t0
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.sleep, displayValue: "7h 30m", rawValue: 27_000)],
                dataAsOf: [WatchMetricKindKey.sleep: t0],
                sleepNight: t0,
                coverage: t2
            ),
            into: current
        )
        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.sleep)?.rawValue, 21_600)
    }

    // MARK: - Chart-only channel (Skin Temperature deviation)

    func testChartOnlyKindAdoptsWeeklyAndRangeButNeverTheHeadlineOrStamps() {
        let current = snapshot(
            metrics: [
                metric(
                    WatchMetricKindKey.wristTemperature,
                    displayValue: "36.2", rawValue: 36.2, fillFraction: 0.4,
                    weekly: [36.0, 36.1, 36.2, 36.1, 36.0, 36.2, 36.2],
                    computedAt: t0
                )
            ],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let freshWeekly: [Double?] = [36.1, 36.2, 36.3, 36.2, 36.1, 36.3, 36.5]
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [
                    metric(
                        WatchMetricKindKey.wristTemperature,
                        displayValue: "36.2", rawValue: 36.2, fillFraction: 0.4,
                        weekly: freshWeekly
                    )
                ],
                dataAsOf: [:],
                chartDataAsOf: [WatchMetricKindKey.wristTemperature: t2],
                coverage: t2
            ),
            into: current
        )

        let wrist = merged.metric(forKind: WatchMetricKindKey.wristTemperature)
        XCTAssertEqual(wrist?.weekly, freshWeekly, "the freshly spliced trend must reach the card")
        XCTAssertEqual(wrist?.displayValue, "36.2")
        XCTAssertEqual(wrist?.computedAt, t0, "chart adoption makes no provenance claim")
        XCTAssertNil(wrist?.liveUpdatedAt)
    }

    func testChartOnlyKindIsSkippedWhenThePhoneStampIsNewerThanCoverage() {
        // A push landed mid-compute: its stamp (t2) is newer than this
        // compute's cutoff (t1), so even the chart must not roll back.
        let current = snapshot(
            metrics: [
                metric(
                    WatchMetricKindKey.wristTemperature,
                    displayValue: "36.4", rawValue: 36.4,
                    weekly: [36.4, 36.4, 36.4, 36.4, 36.4, 36.4, 36.4],
                    computedAt: t2
                )
            ],
            generatedAt: t2,
            lastRefreshDate: t2
        )
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.wristTemperature, displayValue: "36.2", rawValue: 36.2, weekly: [1, 2, 3, 4, 5, 6, 7])],
                dataAsOf: [:],
                chartDataAsOf: [WatchMetricKindKey.wristTemperature: t1],
                coverage: t1
            ),
            into: current
        )

        let keptWeekly: [Double?] = [36.4, 36.4, 36.4, 36.4, 36.4, 36.4, 36.4]
        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.wristTemperature)?.weekly, keptWeekly)
    }

    // MARK: - Reset refusal

    func testComputeNeverRepopulatesAResetTombstone() {
        let tombstone = snapshot(metrics: [], generatedAt: t0, lastRefreshDate: nil, isReset: true)
        let merged = WatchComputeMerge.mergingComputed(
            result(
                metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "71", rawValue: 71)],
                dataAsOf: [WatchMetricKindKey.heartRate: t2]
            ),
            into: tombstone
        )

        XCTAssertTrue(merged.metrics.isEmpty)
        XCTAssertEqual(merged.isReset, true)
    }

    // MARK: - Extended phone-push merge

    func testPhonePushPreservesTheFullDisplaySetForAWatchComputedLocalMetric() {
        let local = metric(
            WatchMetricKindKey.readiness,
            displayValue: "84", rawValue: 84, score: 84, fillFraction: 0.84,
            levelMin: 80, levelMax: 94,
            tint: WatchMetricColor(red: 0, green: 1, blue: 0),
            weekly: [60, 62, 70, 75, 80, 82, 84],
            statusBand: WatchStatusBand(min: 80, max: 94, label: "High"),
            liveUpdatedAt: t2,
            computedAt: t2
        )
        let current = snapshot(metrics: [local], generatedAt: t2, lastRefreshDate: t2)
        let stalePush = snapshot(
            metrics: [
                metric(
                    WatchMetricKindKey.readiness,
                    displayValue: "55", rawValue: 55, score: 55, fillFraction: 0.55,
                    levelMin: 50, levelMax: 64,
                    tint: WatchMetricColor(red: 1, green: 0, blue: 0),
                    statusBand: WatchStatusBand(min: 50, max: 64, label: "Fair"),
                    computedAt: t0
                )
            ],
            generatedAt: t0,
            lastRefreshDate: t0
        )

        let merged = WatchComputeMerge.merging(stalePush, over: current)
        let readiness = merged.metric(forKind: WatchMetricKindKey.readiness)
        XCTAssertEqual(readiness?.score, 84)
        XCTAssertEqual(readiness?.levelMin, 80)
        XCTAssertEqual(readiness?.levelMax, 94)
        XCTAssertEqual(readiness?.statusBand?.label, "High")
        XCTAssertEqual(readiness?.tint, WatchMetricColor(red: 0, green: 1, blue: 0))
        XCTAssertEqual(readiness?.liveUpdatedAt, t2)
        XCTAssertEqual(readiness?.computedAt, t2, "The kept value keeps its own provenance.")
    }

    func testPhonePushKeepsOnlyTheValueSubsetForALiveOnlyLocalReading() {
        // The local HR came from the cheap live read: `liveUpdatedAt` moved but
        // `computedAt` is still the phone's older stamp, and its weekly series /
        // band / tint are just the PREVIOUS push's. The local value must win,
        // but the incoming push's newer weekly + band must not be discarded.
        let local = metric(
            WatchMetricKindKey.heartRate,
            displayValue: "71", rawValue: 71, fillFraction: 0.71,
            levelMin: 40, levelMax: 60,
            tint: WatchMetricColor(red: 1, green: 0, blue: 0),
            weekly: [50, 51, 52, 53, 54, 55, 55],
            statusBand: WatchStatusBand(min: 50, max: 64, label: "Stale"),
            liveUpdatedAt: t2,
            computedAt: t0
        )
        let current = snapshot(metrics: [local], generatedAt: t0, lastRefreshDate: t0)
        let push = snapshot(
            metrics: [
                metric(
                    WatchMetricKindKey.heartRate,
                    displayValue: "58", rawValue: 58, fillFraction: 0.58,
                    levelMin: 60, levelMax: 80,
                    tint: WatchMetricColor(red: 0, green: 0, blue: 1),
                    weekly: [60, 62, 70, 75, 80, 82, 84],
                    statusBand: WatchStatusBand(min: 80, max: 94, label: "Fresh"),
                    computedAt: t1
                )
            ],
            generatedAt: t1,
            lastRefreshDate: t1
        )

        let heartRate = WatchComputeMerge.merging(push, over: current)
            .metric(forKind: WatchMetricKindKey.heartRate)
        // Locally measured: value, unit and ring fill.
        XCTAssertEqual(heartRate?.rawValue, 71)
        XCTAssertEqual(heartRate?.displayValue, "71")
        XCTAssertEqual(heartRate?.fillFraction, 0.71)
        XCTAssertEqual(heartRate?.liveUpdatedAt, t2)
        // Everything the live read never computed comes from the push.
        XCTAssertEqual(heartRate?.weekly?.last, 84)
        XCTAssertEqual(heartRate?.statusBand?.label, "Fresh")
        XCTAssertEqual(heartRate?.levelMin, 60)
        XCTAssertEqual(heartRate?.tint, WatchMetricColor(red: 0, green: 0, blue: 1))
        XCTAssertEqual(heartRate?.computedAt, t1)
    }

    func testPhonePushComparisonUsesThePerMetricStampWhenPresent() {
        // Snapshot-level `lastRefreshDate` says the push is fresh, but this
        // metric's own `computedAt` says its data is older than the local
        // reading — the per-metric stamp decides.
        let local = metric(WatchMetricKindKey.heartRate, displayValue: "71", rawValue: 71, liveUpdatedAt: t1)
        let current = snapshot(metrics: [local], generatedAt: t1, lastRefreshDate: t1)
        let push = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "58", rawValue: 58, computedAt: t0)],
            generatedAt: t2,
            lastRefreshDate: t2
        )

        XCTAssertEqual(
            WatchComputeMerge.merging(push, over: current).metric(forKind: WatchMetricKindKey.heartRate)?.rawValue,
            71
        )
    }

    func testPhonePushWithNewerQueryButOlderMeasurementKeepsTheLocalReading() {
        // The push's query ran at t2 — after the local live reading at t1 —
        // but the sample it carries was measured at t0. The event-to-event
        // compare keeps the local reading; the query-time compare would
        // overwrite the newer measurement with the older one.
        let local = metric(WatchMetricKindKey.heartRate, displayValue: "71", rawValue: 71, liveUpdatedAt: t1, measuredAt: t1)
        let current = snapshot(metrics: [local], generatedAt: t1, lastRefreshDate: t1)
        let push = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "58", rawValue: 58, computedAt: t2, measuredAt: t0)],
            generatedAt: t2,
            lastRefreshDate: t2
        )

        let heartRate = WatchComputeMerge.merging(push, over: current).metric(forKind: WatchMetricKindKey.heartRate)
        XCTAssertEqual(heartRate?.rawValue, 71)
        XCTAssertEqual(heartRate?.measuredAt, t1, "the kept local value keeps its own event watermark")
    }

    func testPhonePushWithFresherPerMetricStampReplacesTheLocalValue() {
        let local = metric(WatchMetricKindKey.heartRate, displayValue: "71", rawValue: 71, liveUpdatedAt: t0)
        let current = snapshot(metrics: [local], generatedAt: t0, lastRefreshDate: t0)
        let push = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "58", rawValue: 58, computedAt: t2)],
            generatedAt: t2,
            lastRefreshDate: t2
        )

        XCTAssertEqual(
            WatchComputeMerge.merging(push, over: current).metric(forKind: WatchMetricKindKey.heartRate)?.rawValue,
            58
        )
    }

    func testPhonePushBlankPreserveAndReadinessClearAreUnchanged() {
        let current = snapshot(
            metrics: [
                metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62),
                metric(WatchMetricKindKey.readiness, displayValue: "80", rawValue: 80)
            ],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let push = snapshot(
            metrics: [
                metric(WatchMetricKindKey.heartRate, displayValue: "--", rawValue: nil),
                metric(WatchMetricKindKey.readiness, displayValue: "--", rawValue: nil)
            ],
            generatedAt: t2,
            lastRefreshDate: t2
        )

        let merged = WatchComputeMerge.merging(push, over: current)
        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.heartRate)?.rawValue, 62)
        XCTAssertNil(
            merged.metric(forKind: WatchMetricKindKey.readiness)?.rawValue,
            "A phone readiness blank is authoritative and must clear."
        )
    }

    func testSettingsChangePushClearsALocalValueBehindAnAuthoritativeBlank() {
        // The settings-change intake re-resolves with authoritative blanks:
        // the push was built under the NEW source selection, so its "--" means
        // the new configuration produces no value. The ordinary blank-preserve
        // rule would keep the OLD source's reading behind it forever — later
        // blank watch computes never displace a displayed value.
        let current = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62)],
            generatedAt: t0,
            lastRefreshDate: t0
        )
        let push = snapshot(
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "--", rawValue: nil)],
            generatedAt: t2,
            lastRefreshDate: t2
        )

        XCTAssertNil(
            WatchComputeMerge.merging(push, over: current, treatingBlanksAsAuthoritative: true)
                .metric(forKind: WatchMetricKindKey.heartRate)?.rawValue
        )
    }
}
