//
//  WatchWorkoutSpansTests.swift
//  BodyTests
//
//  Locks the workouts the watch's own compute read
//  (`WatchMetricsSnapshot.workoutSpans`), which let the watch set aside a High
//  Heart Rate warning a workout covers before the iPhone has that workout, and
//  the schema of the three watch warning fields that came with them
//  (`warningSettings`, `warningChecks`, `workoutSpans`). The rules:
//  * the compute builds them from a workout read that succeeded (an empty
//    one included) and carries no field without one
//    (`WatchComputeAssembly.workoutSpans(delta:now:calendar:)`);
//  * a workout counts while it plus its 30 minute recovery grace reaches
//    today, so last night's late workout still counts, and one starting
//    after `now` doesn't;
//  * a compute's spans replace the displayed ones, an empty read clears them
//    and is never persisted, and a compute that didn't read keeps them;
//  * a Clear-Cache tombstone is never repopulated;
//  * a phone push, which never carries them, keeps them, and the
//    settings-change mode and a permission or data source change (the
//    provenance strip) drop them.
//

import XCTest
@testable import Body

final class WatchWorkoutSpansTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_001_200)
    private let t3 = Date(timeIntervalSince1970: 1_001_800)

    // MARK: - Fixtures

    /// `hour:minute` on 2026-10-05, today, or on `day` of that October.
    private func at(day: Int = 5, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(15) }

    private func workout(from start: Date, to end: Date) -> WorkoutSummary {
        WorkoutSummary(type: .running, startDate: start, duration: end.timeIntervalSince(start), endDate: end)
    }

    private func span(from start: Date, to end: Date) -> WatchWorkoutSpan {
        WatchWorkoutSpan(start: start, end: end)
    }

    /// The spans a run whose workout read found `workouts` carries.
    private func spans(_ workouts: [WorkoutSummary]) -> [WatchWorkoutSpan]? {
        var delta = WatchComputeDelta()
        delta.workouts = .success(workouts)
        return WatchComputeAssembly.workoutSpans(delta: delta, now: now, calendar: calendar)
    }

    /// The displayed snapshot, or a phone push (which never carries spans).
    private func snapshot(
        generatedAt: Date? = nil,
        workoutSpans: [WatchWorkoutSpan]? = nil,
        isReset: Bool? = nil
    ) -> WatchMetricsSnapshot {
        var snapshot = WatchMetricsSnapshot(
            generatedAt: generatedAt ?? t0,
            lastRefreshDate: generatedAt ?? t0,
            metrics: [],
            source: "phone",
            publisherEpoch: "epoch-A",
            revision: 7,
            isReset: isReset
        )
        snapshot.workoutSpans = workoutSpans
        return snapshot
    }

    /// A compute that carries these spans and nothing else, so no other rule
    /// can move the snapshot.
    private func computed(_ workoutSpans: [WatchWorkoutSpan]?) -> WatchComputeResult {
        var computed = WatchMetricsSnapshot(generatedAt: t2, lastRefreshDate: t2, metrics: [])
        computed.source = "watch"
        computed.workoutSpans = workoutSpans
        return WatchComputeResult(snapshot: computed, dataAsOf: [:], coverage: t2, generation: 3)
    }

    /// This morning's run, displayed.
    private var displayedSpans: [WatchWorkoutSpan] {
        [span(from: at(7), to: at(7, 45))]
    }

    // MARK: - Schema evolution

    func testSnapshotWithoutTheWatchWarningKeysStillDecodes() throws {
        // What an older watch cached, and what an older iPhone publishes.
        let json = """
        {
          "generatedAt": "2026-10-05T07:00:00Z",
          "metrics": []
        }
        """

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: Data(json.utf8)))

        XCTAssertNil(decoded.warningSettings)
        XCTAssertNil(decoded.warningChecks)
        XCTAssertNil(decoded.workoutSpans)
    }

    /// The iPhone never sets the checks or the spans, and an older iPhone no
    /// settings, so their push carries no key for them and stays the size it
    /// was.
    func testNilWatchWarningFieldsWriteNoKey() throws {
        let snapshot = WatchMetricsSnapshot(generatedAt: t0, lastRefreshDate: t0, metrics: [])
        let json = String(decoding: try XCTUnwrap(snapshot.encoded()), as: UTF8.self)

        for key in ["warningSettings", "warningChecks", "workoutSpans"] {
            XCTAssertFalse(json.contains(key), key)
        }
    }

    func testEncodeDecodeRoundTripsTheWatchWarningFields() throws {
        var original = WatchMetricsSnapshot(generatedAt: t0, lastRefreshDate: t0, metrics: [])
        original.warningSettings = WatchWarningSettings(
            thresholds: ["lowHeartRate": 40, "highHeartRate": 152, "highWristTemperature": 37.5],
            enabledKinds: ["lowHeartRate", "highHeartRate"],
            notifies: true,
            notifiedDays: ["lowHeartRate": "2026-10-05"]
        )
        original.warningChecks = [
            WatchWarningCheck(
                kind: "lowHeartRate",
                checkedAt: at(14, 30),
                threshold: 40,
                episode: WatchWarningCheck.Episode(startDate: at(3), endDate: at(3, 20), extremeValue: 36)
            ),
            WatchWarningCheck(kind: "highWristTemperature", checkedAt: at(14, 30), threshold: 37.5, episode: nil)
        ]
        original.workoutSpans = [span(from: at(day: 4, 23), to: at(0, 30)), span(from: at(7), to: at(7, 45))]
        let data = try XCTUnwrap(original.encoded())

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: data))

        XCTAssertEqual(decoded.warningSettings, original.warningSettings)
        XCTAssertEqual(decoded.warningChecks, original.warningChecks)
        XCTAssertEqual(decoded.workoutSpans, original.workoutSpans)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - The compute's spans

    func testTodaysWorkoutsAreCarriedInStartOrder() {
        XCTAssertEqual(
            spans([workout(from: at(12), to: at(12, 30)), workout(from: at(7), to: at(7, 45))]),
            [span(from: at(7), to: at(7, 45)), span(from: at(12), to: at(12, 30))]
        )
    }

    /// What has to reach today is the workout's recovery grace, not the
    /// workout: last night's run past midnight counts, and so does one that
    /// ended less than 30 minutes before it.
    func testLastNightsWorkoutCountsWhileItsRecoveryReachesToday() {
        XCTAssertEqual(
            spans([workout(from: at(day: 4, 23), to: at(0, 30))]),
            [span(from: at(day: 4, 23), to: at(0, 30))],
            "past midnight"
        )
        XCTAssertEqual(
            spans([workout(from: at(day: 4, 22), to: at(day: 4, 23, 45))]),
            [span(from: at(day: 4, 22), to: at(day: 4, 23, 45))],
            "its recovery runs to 00:15"
        )
        XCTAssertEqual(
            spans([workout(from: at(day: 4, 22), to: at(day: 4, 23, 30))]),
            [span(from: at(day: 4, 22), to: at(day: 4, 23, 30))],
            "its recovery ends right at midnight"
        )
    }

    /// A workout whose recovery ended before today, like the rest of the
    /// week the read reaches back over, is not carried.
    func testAWorkoutEndedMoreThanThirtyMinutesBeforeMidnightIsDropped() {
        XCTAssertEqual(
            spans([workout(from: at(day: 4, 21), to: at(day: 4, 23, 20)), workout(from: at(day: 2, 8), to: at(day: 2, 9))]),
            [],
            "the evening's recovery ended at 23:50"
        )
    }

    func testAWorkoutStartingAfterNowIsDropped() {
        XCTAssertEqual(spans([workout(from: now.addingTimeInterval(600), to: now.addingTimeInterval(2_400))]), [])
    }

    /// A failed or skipped read carries no spans, the merge's "keep"; a read
    /// that found nothing carries an empty list, its "clear".
    func testAFailedReadCarriesNoSpansAndAnEmptyReadAnEmptyList() {
        var delta = WatchComputeDelta()
        XCTAssertNil(WatchComputeAssembly.workoutSpans(delta: delta, now: now, calendar: calendar))

        delta.workouts = .success([])
        XCTAssertEqual(WatchComputeAssembly.workoutSpans(delta: delta, now: now, calendar: calendar), [])
    }

    /// The wiring: the snapshot `assemble` returns carries exactly what
    /// `workoutSpans(delta:now:calendar:)` builds from the run's read.
    func testTheComputedSnapshotCarriesTheSpansTheRunRead() throws {
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
            settingsSignature: "sig-workout-spans"
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
        delta.workouts = .success([workout(from: at(7), to: at(7, 45))])
        XCTAssertEqual(try assembled(delta).workoutSpans, [span(from: at(7), to: at(7, 45))])
        XCTAssertNil(try assembled(WatchComputeDelta()).workoutSpans, "no read, no field")
    }

    // MARK: - Compute → displayed

    func testAComputesSpansReplaceTheDisplayedOnes() {
        let read = [span(from: at(7), to: at(7, 30)), span(from: at(12), to: at(12, 30))]

        XCTAssertEqual(
            WatchComputeMerge.mergingComputed(computed(read), into: snapshot(workoutSpans: displayedSpans)).workoutSpans,
            read
        )
        XCTAssertEqual(WatchComputeMerge.mergingComputed(computed(read), into: snapshot()).workoutSpans, read)
    }

    /// A read that found no workout reaching today clears the spans rather
    /// than storing an empty list, so a persisted snapshot never carries one.
    func testAnEmptyReadClearsTheSpansAndIsNeverPersisted() {
        XCTAssertNil(
            WatchComputeMerge.mergingComputed(computed([]), into: snapshot(workoutSpans: displayedSpans)).workoutSpans
        )
        XCTAssertNil(WatchComputeMerge.mergingComputed(computed([]), into: snapshot()).workoutSpans)
    }

    /// A compute whose workout read failed or was skipped carries no field
    /// and moves nothing.
    func testAComputeWithoutAWorkoutReadKeepsTheSpans() {
        XCTAssertEqual(
            WatchComputeMerge.mergingComputed(computed(nil), into: snapshot(workoutSpans: displayedSpans)).workoutSpans,
            displayedSpans
        )
    }

    func testComputeNeverRepopulatesAResetTombstone() {
        let merged = WatchComputeMerge.mergingComputed(computed(displayedSpans), into: snapshot(isReset: true))

        XCTAssertNil(merged.workoutSpans)
        XCTAssertEqual(merged.isReset, true)
    }

    // MARK: - Phone push → displayed

    /// The phone never sends spans, so an ordinary push keeps the local ones.
    func testAPushKeepsTheLocalSpans() {
        let push = snapshot(generatedAt: t3)
        XCTAssertNil(push.workoutSpans)

        XCTAssertEqual(
            WatchComputeMerge.merging(push, over: snapshot(workoutSpans: displayedSpans)).workoutSpans,
            displayedSpans
        )
    }

    /// Belt and braces: the settings change path strips the spans before it
    /// merges, and the mode drops them on its own too.
    func testTheSettingsChangeModeDropsTheSpans() {
        let merged = WatchComputeMerge.merging(
            snapshot(generatedAt: t3),
            over: snapshot(workoutSpans: displayedSpans),
            treatingBlanksAsAuthoritative: true
        )

        XCTAssertNil(merged.workoutSpans)
    }

    /// A permission or data source change strips the local provenance before
    /// the push resolves, and no push brings the spans back: they wait for
    /// the next compute.
    func testStrippingLocalProvenanceDropsTheSpans() {
        let stripped = WatchComputeMerge.strippingLocalProvenance(from: snapshot(workoutSpans: displayedSpans))
        XCTAssertNil(stripped.workoutSpans)

        let push = snapshot(generatedAt: t3)
        XCTAssertNil(WatchComputeMerge.merging(push, over: stripped).workoutSpans)
        XCTAssertNil(WatchComputeMerge.merging(push, over: stripped, treatingBlanksAsAuthoritative: true).workoutSpans)
    }
}
