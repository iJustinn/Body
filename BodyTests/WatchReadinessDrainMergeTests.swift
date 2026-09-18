//
//  WatchReadinessDrainMergeTests.swift
//  BodyTests
//
//  Locks the rule that keeps a watch-recorded workout's readiness drain on the
//  watch while HealthKit has not replicated that workout to the phone yet (and
//  the mirror case): `WatchComputeMerge` still picks the winner by freshness,
//  but the displayed score is the winner's undrained score minus the UNION of
//  both devices' drain reports (`WatchReadinessDrainReconciler`).
//
//  Fixtures are built the way a real publisher builds them (the shared builder
//  mapping plus `ActivityReadinessImpact.drainedScore`), so an expected score
//  here is what a full recompute over the same workouts would show.
//

import XCTest
@testable import Body

final class WatchReadinessDrainMergeTests: XCTestCase {
    private let wake = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ minutes: Double) -> Date { wake.addingTimeInterval(minutes * 60) }

    private typealias Contribution = WatchReadinessDrainReport.Contribution
    private var a: Contribution { Contribution(id: "A", start: at(60), points: 10) }
    private var b: Contribution { Contribution(id: "B", start: at(120), points: 8) }
    private var c: Contribution { Contribution(id: "C", start: at(180), points: 6) }

    // MARK: - Fixtures

    /// A readiness metric exactly as one publisher would emit it.
    private func readiness(
        undrained: Int,
        cycleStart: Date? = nil,
        workouts: [Contribution]?,
        computedAt: Date,
        watchComputed: Bool = false
    ) -> WatchMetric {
        let drained = ActivityReadinessImpact.drainedScore(
            undrained: undrained,
            contributionPoints: (workouts ?? []).reduce(0) { $0 + $1.points }
        )
        var metric = WatchMetricsSnapshotBuilder.readinessMetric(
            score: drained?.score ?? undrained,
            isDrained: drained != nil
        )
        if let workouts {
            metric.drain = WatchReadinessDrainReport(
                undrainedScore: undrained,
                cycleStart: cycleStart ?? wake,
                contributions: workouts
            )
        }
        metric.computedAt = computedAt
        // `mergingComputed` stamps both from one watermark: the compute's signature.
        metric.liveUpdatedAt = watchComputed ? computedAt : nil
        return metric
    }

    private var blankReadiness: WatchMetric {
        WatchMetricsSnapshotBuilder.readinessMetric(score: nil, isDrained: false)
    }

    private func snapshot(_ metric: WatchMetric, at date: Date) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(generatedAt: date, lastRefreshDate: date, metrics: [metric], source: "phone")
    }

    private func computeResult(_ metric: WatchMetric, at date: Date, stamped: Bool = true) -> WatchComputeResult {
        WatchComputeResult(
            snapshot: snapshot(metric, at: date),
            dataAsOf: stamped ? [WatchMetricKindKey.readiness: date] : [:],
            coverage: date,
            generation: 0
        )
    }

    /// The displayed snapshot after a stamped watch compute over `phone`.
    private func displayed(
        afterWatchCompute watch: WatchMetric,
        at date: Date,
        over phone: WatchMetricsSnapshot
    ) -> WatchMetricsSnapshot {
        WatchComputeMerge.mergingComputed(computeResult(watch, at: date), into: phone)
    }

    private func readiness(in snapshot: WatchMetricsSnapshot) throws -> WatchMetric {
        try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.readiness))
    }

    // MARK: - A push that has not seen the watch's workout

    func testLaterPushMissingAWatchWorkoutKeepsThatWorkoutsDrain() throws {
        // Morning push, no workouts. The watch then computes {A, B}.
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a, b], computedAt: at(130), watchComputed: true),
            at: at(130), over: morning
        )
        XCTAssertEqual(try readiness(in: onWatch).score, 62)

        // A later phone refresh has replicated only B. Same max end date as the
        // watch's set, which is why a date watermark could not catch this.
        let push = snapshot(readiness(undrained: 82, workouts: [b], computedAt: at(140)), at: at(140))
        let merged = try readiness(in: WatchComputeMerge.merging(push, over: onWatch))

        XCTAssertEqual(merged.score, 82 - 18, "phone's fresher base score, both workouts' drain")
        XCTAssertEqual(merged.displayValue, "64")
        XCTAssertEqual(merged.weeklyCurrentValue, 64)
        XCTAssertEqual(merged.computedAt, at(140), "the phone push still WON; only the drain was reconciled")
        XCTAssertNil(merged.liveUpdatedAt)
        XCTAssertEqual(merged.drain?.contributions, [b], "the winner's own report is kept as published")
        XCTAssertEqual(merged.statusBand?.label, ReadinessStatus.status(for: 64).title)
    }

    func testDisjointWorkoutSetsDrainBoth() throws {
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: morning
        )
        // The phone saw a later workout C (another device) but not A.
        let push = snapshot(readiness(undrained: 82, workouts: [c], computedAt: at(200)), at: at(200))
        let merged = try readiness(in: WatchComputeMerge.merging(push, over: onWatch))
        XCTAssertEqual(merged.score, 82 - 16)
    }

    func testSameWorkoutWithChangedDrainFollowsTheFresherSide() throws {
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: morning
        )
        // Same workout identity, re-rated harder, in a NEWER phone publish.
        var rerated = a
        rerated.points = 20
        let newerPush = snapshot(readiness(undrained: 80, workouts: [rerated], computedAt: at(90)), at: at(90))
        XCTAssertEqual(try readiness(in: WatchComputeMerge.merging(newerPush, over: onWatch)).score, 60)

        // The same re-rating in an OLDER publish loses: the watch's value stands.
        let olderPush = snapshot(readiness(undrained: 80, workouts: [rerated], computedAt: at(60)), at: at(60))
        let kept = try readiness(in: WatchComputeMerge.merging(olderPush, over: onWatch))
        XCTAssertEqual(kept.score, 70)
        XCTAssertEqual(kept.liveUpdatedAt, at(70))
    }

    // MARK: - A watch compute that has not seen the phone's workout

    func testWatchComputeKeepsAPhoneOnlyWorkoutsDrain() throws {
        let phone = WatchComputeMerge.merging(
            snapshot(readiness(undrained: 80, workouts: [c], computedAt: at(190)), at: at(190)),
            over: snapshot(blankReadiness, at: at(0))
        )
        let merged = try readiness(in: displayed(
            afterWatchCompute: readiness(undrained: 78, workouts: [a], computedAt: at(200), watchComputed: true),
            at: at(200), over: phone
        ))
        XCTAssertEqual(merged.score, 78 - 16)
        XCTAssertEqual(merged.liveUpdatedAt, at(200), "the watch compute still won")
    }

    func testUnstampedComputeDoesNotReplaceTheWatchReport() throws {
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: morning
        )
        // A later compute whose workout query failed reports nothing, and is
        // unstamped. It must neither be adopted nor read as "A was deleted".
        let failed = computeResult(
            readiness(undrained: 80, workouts: nil, computedAt: at(100), watchComputed: true),
            at: at(100), stamped: false
        )
        let merged = try readiness(in: WatchComputeMerge.mergingComputed(failed, into: onWatch))
        XCTAssertEqual(merged.score, 70)
        XCTAssertEqual(merged.drainReports?.watch?.contributions, [a])
        XCTAssertNil(merged.drainReports?.watchRemovedIDs)
    }

    // MARK: - Deletion

    func testWorkoutDeletedOnTheWatchStopsDrainingWhileThePhoneStillListsIt() throws {
        // Both devices knew A.
        let phone = WatchComputeMerge.merging(
            snapshot(readiness(undrained: 80, workouts: [a], computedAt: at(65)), at: at(65)),
            over: snapshot(blankReadiness, at: at(0))
        )
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: phone
        )
        XCTAssertEqual(try readiness(in: onWatch).score, 70)

        // A is deleted on the watch; the phone is offline and keeps listing it.
        let afterDelete = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [], computedAt: at(90), watchComputed: true),
            at: at(90), over: onWatch
        )
        XCTAssertEqual(try readiness(in: afterDelete).score, 80)
        XCTAssertEqual(try readiness(in: afterDelete).drainReports?.watchRemovedIDs, ["A"])
        XCTAssertNil(try readiness(in: afterDelete).weeklyCurrentValue)

        // The phone comes back before the deletion replicated to it.
        let stalePush = snapshot(readiness(undrained: 81, workouts: [a], computedAt: at(100)), at: at(100))
        let afterStalePush = WatchComputeMerge.merging(stalePush, over: afterDelete)
        XCTAssertEqual(try readiness(in: afterStalePush).score, 81, "a deleted workout is not resurrected")

        // Once the phone drops it too, the removal record has nothing left to guard.
        let caughtUp = snapshot(readiness(undrained: 81, workouts: [], computedAt: at(110)), at: at(110))
        let converged = try readiness(in: WatchComputeMerge.merging(caughtUp, over: afterStalePush))
        XCTAssertEqual(converged.score, 81)
        XCTAssertNil(converged.drainReports?.watchRemovedIDs)
    }

    func testWorkoutMissingFromAPhoneReportIsNotTreatedAsDeleted() throws {
        let phone = WatchComputeMerge.merging(
            snapshot(readiness(undrained: 80, workouts: [a], computedAt: at(65)), at: at(65)),
            over: snapshot(blankReadiness, at: at(0))
        )
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: phone
        )
        // e.g. a phone publish built before its workout month had loaded.
        let push = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(80)), at: at(80))
        XCTAssertEqual(try readiness(in: WatchComputeMerge.merging(push, over: onWatch)).score, 70)
    }

    // MARK: - Wake cycle expiry

    func testEveningDrainSurvivesMidnightWithoutANewWakeCycle() throws {
        // Workout at 23:45 relative to a 07:00 wake; the push lands at 00:10,
        // a new CALENDAR day, with nobody having slept.
        let evening = Contribution(id: "E", start: at(16 * 60 + 45), points: 10)
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [evening], computedAt: at(16 * 60 + 50), watchComputed: true),
            at: at(16 * 60 + 50), over: morning
        )
        let afterMidnight = snapshot(
            readiness(undrained: 79, cycleStart: wake, workouts: [], computedAt: at(17 * 60 + 10)),
            at: at(17 * 60 + 10)
        )
        XCTAssertEqual(try readiness(in: WatchComputeMerge.merging(afterMidnight, over: onWatch)).score, 69)
    }

    func testNewWakeCycleExpiresTheOldDrainEvenOnTheSameDay() throws {
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: morning
        )
        // A sleep ended after workout A: the phone reports a later cycle start.
        let newCycle = snapshot(
            readiness(undrained: 85, cycleStart: at(240), workouts: [], computedAt: at(250)),
            at: at(250)
        )
        let merged = try readiness(in: WatchComputeMerge.merging(newCycle, over: onWatch))
        XCTAssertEqual(merged.score, 85)
        XCTAssertNil(merged.weeklyCurrentValue)
    }

    // MARK: - Authoritative clears

    func testLaterBlankReadinessPushClearsADrainedWatchScore() throws {
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: morning
        )
        var blank = blankReadiness
        blank.computedAt = at(90)
        let merged = try readiness(in: WatchComputeMerge.merging(snapshot(blank, at: at(90)), over: onWatch))
        XCTAssertFalse(merged.hasValue, "a drain report must never resurrect a score behind an authoritative blank")
        XCTAssertNil(merged.score)
    }

    func testProvenanceStripDropsTheDrainReports() throws {
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: morning
        )
        XCTAssertNotNil(try readiness(in: onWatch).drainReports)
        let stripped = WatchComputeMerge.strippingLocalProvenance(from: onWatch)
        XCTAssertNil(try readiness(in: stripped).drainReports)

        // The settings-change push then wins outright, with no watch drain.
        let push = snapshot(readiness(undrained: 82, workouts: [], computedAt: at(60)), at: at(60))
        let merged = try readiness(in: WatchComputeMerge.merging(push, over: stripped, treatingBlanksAsAuthoritative: true))
        XCTAssertEqual(merged.score, 82)
    }

    // MARK: - Payloads from before the drain report

    func testPayloadWithoutDrainFieldsDecodesAndMergesAsBefore() throws {
        let legacyJSON = """
        {"kind":"readiness","title":"Readiness","displayValue":"80","unit":"%","score":80,
         "fillFraction":0.8,"rawValue":80,"rangeMin":0,"rangeMax":100}
        """
        var legacy = try JSONDecoder().decode(WatchMetric.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(legacy.drain)
        XCTAssertNil(legacy.drainReports)
        legacy.computedAt = at(140)

        // A watch that HAS a drain report, receiving a push from an older phone
        // build: unknown, so the push wins exactly as it used to.
        let morning = snapshot(readiness(undrained: 80, workouts: [], computedAt: at(10)), at: at(10))
        let onWatch = displayed(
            afterWatchCompute: readiness(undrained: 80, workouts: [a], computedAt: at(70), watchComputed: true),
            at: at(70), over: morning
        )
        let merged = try readiness(in: WatchComputeMerge.merging(snapshot(legacy, at: at(140)), over: onWatch))
        XCTAssertEqual(merged.score, 80)

        // And with no reports anywhere nothing is added to the metric at all.
        let older = snapshot(legacy, at: at(140))
        var newer = legacy
        newer.computedAt = at(150)
        let untouched = try readiness(in: WatchComputeMerge.merging(snapshot(newer, at: at(150)), over: older))
        XCTAssertEqual(untouched, newer)
    }
}
