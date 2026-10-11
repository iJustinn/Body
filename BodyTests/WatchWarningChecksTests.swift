//
//  WatchWarningChecksTests.swift
//  BodyTests
//
//  Locks the warnings the watch checks itself (`WatchMetricsSnapshot.warningChecks`):
//  how the compute turns today's readings into one check per kind
//  (`WatchComputeAssembly.warningChecks(delta:settings:permission:now:calendar:)`)
//  and how the checks move through the watch's merges (`WatchComputeMerge`).
//  The rules:
//  * only the kinds with a watch card are checked, each only under the
//    iPhone's threshold for it and with a reading that succeeded;
//  * High Heart Rate also needs Workouts and a workout read that succeeded,
//    and leaves out the readings inside today's workouts and their 30 minute
//    recovery grace, the iPhone's rule;
//  * a check carries its compute's time, the threshold it used and the day's
//    earliest episode, or none when nothing was past the threshold, and a
//    compute that checked nothing carries no field;
//  * a compute's checks replace the displayed ones kind by kind, keep the
//    kinds it didn't check, and stay in kind order;
//  * a Clear-Cache tombstone is never repopulated;
//  * a phone push, which never carries them, keeps them, and the
//    settings-change mode and a permission or data source change (the
//    provenance strip) drop them;
//  * the iPhone's settings (`warningSettings`) follow the push alone.
//

import XCTest
@testable import Body

final class WatchWarningChecksTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_001_200)
    private let t3 = Date(timeIntervalSince1970: 1_001_800)

    private let lowHeartRate = MetricWarningKind.lowHeartRate.rawValue
    private let highHeartRate = MetricWarningKind.highHeartRate.rawValue
    private let lowBloodOxygen = MetricWarningKind.lowBloodOxygen.rawValue
    private let highSkinTemperature = MetricWarningKind.highWristTemperature.rawValue

    // MARK: - Fixtures

    /// `hour:minute` on 2026-10-05, today, or on `day` of that October.
    private func at(day: Int = 5, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(15) }

    /// The limits the iPhone ships by default.
    private var defaultThresholds: [String: Double] {
        [lowHeartRate: 40, highHeartRate: 120, lowBloodOxygen: 90, highSkinTemperature: 38]
    }

    /// The iPhone's settings with these limits. The selection, the switch and
    /// the ledger play no part in a check.
    private func settings(_ thresholds: [String: Double]) -> WatchWarningSettings {
        WatchWarningSettings(
            thresholds: thresholds,
            enabledKinds: [lowHeartRate, highHeartRate, lowBloodOxygen, highSkinTemperature],
            notifies: true,
            notifiedDays: [:]
        )
    }

    private func reading(_ date: Date, _ value: Double) -> HealthTrendDataPoint {
        HealthTrendDataPoint(date: date, value: value)
    }

    private func workout(from start: Date, to end: Date) -> WorkoutSummary {
        WorkoutSummary(type: .running, startDate: start, duration: end.timeIntervalSince(start), endDate: end)
    }

    private func episode(_ start: Date, _ end: Date, extreme: Double) -> WatchWarningCheck.Episode {
        WatchWarningCheck.Episode(startDate: start, endDate: end, extremeValue: extreme)
    }

    /// A check this test's compute (at `now`) made.
    private func check(_ kind: String, threshold: Double, episode: WatchWarningCheck.Episode?) -> WatchWarningCheck {
        WatchWarningCheck(kind: kind, checkedAt: now, threshold: threshold, episode: episode)
    }

    /// The checks a run with these reads makes, under the default limits, a
    /// workout read that found nothing and every permission, unless told.
    private func checks(
        _ readings: [MetricWarningKind: WatchFetchOutcome<[HealthTrendDataPoint]>],
        workouts: WatchFetchOutcome<[WorkoutSummary]> = .success([]),
        thresholds: [String: Double]? = nil,
        permission: BodyHealthPermissionSelection = .defaultValue
    ) -> [WatchWarningCheck]? {
        var delta = WatchComputeDelta()
        delta.warningReadings = readings
        delta.workouts = workouts
        return WatchComputeAssembly.warningChecks(
            delta: delta,
            settings: settings(thresholds ?? defaultThresholds),
            permission: permission,
            now: now,
            calendar: calendar
        )
    }

    /// The displayed snapshot, or a phone push (which never carries checks).
    private func snapshot(
        generatedAt: Date? = nil,
        warningChecks: [WatchWarningCheck]? = nil,
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
        snapshot.warningChecks = warningChecks
        return snapshot
    }

    /// A compute that carries these checks and nothing else, so no other
    /// rule can move the snapshot.
    private func computed(_ warningChecks: [WatchWarningCheck]?) -> WatchComputeResult {
        var computed = WatchMetricsSnapshot(generatedAt: t2, lastRefreshDate: t2, metrics: [])
        computed.source = "watch"
        computed.warningChecks = warningChecks
        return WatchComputeResult(snapshot: computed, dataAsOf: [:], coverage: t2, generation: 3)
    }

    /// Low Heart Rate and High Skin Temperature, checked by the compute
    /// before this one.
    private var displayedChecks: [WatchWarningCheck] {
        [
            WatchWarningCheck(kind: lowHeartRate, checkedAt: at(9), threshold: 40, episode: nil),
            WatchWarningCheck(
                kind: highSkinTemperature,
                checkedAt: at(9),
                threshold: 38,
                episode: episode(at(4), at(4), extreme: 38.4)
            )
        ]
    }

    // MARK: - The compute's checks

    /// The iPhone's detection: readings past the limit no more than 30
    /// minutes apart make one episode, the lowest its extreme, and the day's
    /// earliest episode is the one carried. A reading at the limit itself
    /// isn't past it.
    func testALowHeartRateEpisodeIsTheDaysEarliest() {
        let readings = [
            reading(at(3), 38),
            reading(at(3, 10), 36),
            reading(at(3, 25), 39),
            reading(at(3, 40), 40),
            reading(at(9), 37)
        ]

        XCTAssertEqual(
            checks([.lowHeartRate: .success(readings)]),
            [check(lowHeartRate, threshold: 40, episode: episode(at(3), at(3, 25), extreme: 36))]
        )
    }

    /// The iPhone's rule: a reading inside one of today's workouts, or in
    /// the 30 minutes after it, isn't counted, last night's workout that ran
    /// past midnight included, while a reading after the grace is.
    func testHighHeartRateLeavesOutWorkoutsAndTheirRecoveryGrace() {
        let workouts = [workout(from: at(day: 4, 23, 30), to: at(0, 15)), workout(from: at(10), to: at(11))]
        let readings = [
            reading(at(0, 40), 128),
            reading(at(10, 30), 165),
            reading(at(11, 20), 131),
            reading(at(11, 45), 126)
        ]

        XCTAssertEqual(
            checks([.highHeartRate: .success(readings)], workouts: .success(workouts)),
            [check(highHeartRate, threshold: 120, episode: episode(at(11, 45), at(11, 45), extreme: 126))]
        )
    }

    /// Without Workouts the iPhone skips High Heart Rate, and with a workout
    /// list it couldn't read it keeps the last result: nothing would tell a
    /// run from a resting rise. The other kinds are still checked.
    func testHighHeartRateIsCheckedOnlyWithWorkoutsAndAWorkoutRead() {
        let readings: [MetricWarningKind: WatchFetchOutcome<[HealthTrendDataPoint]>] = [
            .lowHeartRate: .success([]),
            .highHeartRate: .success([reading(at(9), 130)])
        ]
        let workoutsOff = BodyHealthPermissionSelection.defaultValue.setting(.workouts, isEnabled: false)

        XCTAssertEqual(checks(readings)?.map(\.kind), [lowHeartRate, highHeartRate])
        XCTAssertEqual(checks(readings, permission: workoutsOff)?.map(\.kind), [lowHeartRate], "Workouts off")
        XCTAssertEqual(checks(readings, workouts: .failure)?.map(\.kind), [lowHeartRate], "the workout read failed")
    }

    /// A kind is checked only under the iPhone's limit for it (High Heart
    /// Rate has none until the iPhone has resolved its birth date default)
    /// and with a reading that succeeded: a failed read, or none at all,
    /// keeps the last check.
    func testAKindNeedsTheIPhonesThresholdAndASuccessfulReading() {
        let readings: [MetricWarningKind: WatchFetchOutcome<[HealthTrendDataPoint]>] = [
            .lowHeartRate: .failure,
            .highHeartRate: .success([reading(at(9), 130)]),
            .highWristTemperature: .success([reading(at(4), 38.4)])
        ]

        XCTAssertEqual(
            checks(readings, thresholds: [lowHeartRate: 40, highSkinTemperature: 38])?.map(\.kind),
            [highSkinTemperature]
        )
        XCTAssertNil(
            checks([.highWristTemperature: .success([reading(at(4), 38.4)])], thresholds: [lowHeartRate: 40]),
            "a threshold without a reading, or a reading without a threshold, checks nothing"
        )
    }

    /// Respiratory Rate has no watch card, so the watch never checks it,
    /// whatever it is handed.
    func testOnlyTheKindsWithAWatchCardAreChecked() {
        XCTAssertEqual(
            WatchComputeAssembly.checkedWarningKinds,
            [.lowHeartRate, .highHeartRate, .lowBloodOxygen, .highWristTemperature]
        )
        XCTAssertEqual(
            WatchComputeAssembly.checkedWarningKinds,
            MetricWarningKind.allCases.filter(WatchComputeAssembly.checkedWarningKinds.contains),
            "in kind order"
        )
        XCTAssertNil(checks(
            [.highRespiratoryRate: .success([reading(at(3), 26)])],
            thresholds: [MetricWarningKind.highRespiratoryRate.rawValue: 20]
        ))
    }

    /// Low Blood Oxygen, in percent like its limit: readings under it no more
    /// than 30 minutes apart make one episode, the lowest its extreme. A
    /// workout sets aside only High Heart Rate's readings.
    func testLowBloodOxygenIsChecked() {
        let readings = [reading(at(2, 10), 95), reading(at(3), 88), reading(at(3, 20), 87), reading(at(5), 96)]

        XCTAssertEqual(
            checks([.lowBloodOxygen: .success(readings)], workouts: .success([workout(from: at(2, 50), to: at(3, 30))])),
            [check(lowBloodOxygen, threshold: 90, episode: episode(at(3), at(3, 20), extreme: 87))]
        )
        XCTAssertEqual(
            checks([.lowBloodOxygen: .success([reading(at(3), 90), reading(at(4), 97)])]),
            [check(lowBloodOxygen, threshold: 90, episode: nil)],
            "a reading at the limit itself isn't under it"
        )
    }

    /// High Skin Temperature, in °C like its limit. A workout sets aside only
    /// High Heart Rate's readings.
    func testHighSkinTemperatureIsChecked() {
        let readings = [reading(at(4, 30), 37.6), reading(at(6, 10), 38.3)]

        XCTAssertEqual(
            checks([.highWristTemperature: .success(readings)], workouts: .success([workout(from: at(6), to: at(7))])),
            [check(highSkinTemperature, threshold: 38, episode: episode(at(6, 10), at(6, 10), extreme: 38.3))]
        )
    }

    /// A check carries the compute's time and the limit it ran against (here
    /// the user's own), so a limit changed on the iPhone afterwards can set
    /// it aside until the next compute.
    func testACheckCarriesTheComputeTimeAndTheThresholdItUsed() throws {
        let result = try XCTUnwrap(checks([.lowHeartRate: .success([reading(at(3), 44)])], thresholds: [lowHeartRate: 45]))

        XCTAssertEqual(result.map(\.checkedAt), [now])
        XCTAssertEqual(result.map(\.threshold), [45])
        XCTAssertEqual(result.first?.episode, episode(at(3), at(3), extreme: 44), "44 is past the user's 45")
    }

    /// Nothing past the limit today is a check without an episode, which
    /// clears the kind, not a missing check, which would keep the last one.
    func testNothingPastTheThresholdIsACheckWithoutAnEpisode() {
        XCTAssertEqual(
            checks([.lowHeartRate: .success([reading(at(3), 44), reading(at(4), 41)])]),
            [check(lowHeartRate, threshold: 40, episode: nil)]
        )
        XCTAssertEqual(
            checks([.lowHeartRate: .success([])]),
            [check(lowHeartRate, threshold: 40, episode: nil)],
            "the heart rate read asks HealthKit for past-threshold readings only, so this is the common case"
        )
    }

    /// A compute that checked nothing carries no field: no settings from the
    /// iPhone (an older iPhone), or no reading at all.
    func testNothingCheckedCarriesNoField() {
        var delta = WatchComputeDelta()
        delta.workouts = .success([])
        XCTAssertNil(WatchComputeAssembly.warningChecks(
            delta: delta, settings: settings(defaultThresholds), permission: .defaultValue, now: now, calendar: calendar
        ))

        delta.warningReadings = [.lowHeartRate: .success([reading(at(3), 35)])]
        XCTAssertNil(
            WatchComputeAssembly.warningChecks(delta: delta, settings: nil, permission: .defaultValue, now: now, calendar: calendar),
            "readings without the iPhone's settings check nothing"
        )
    }

    /// The wiring: the snapshot `assemble` returns carries exactly what
    /// `warningChecks(delta:settings:permission:now:calendar:)` builds from
    /// the run's reads, in kind order, under the settings it is handed.
    func testTheComputedSnapshotCarriesTheChecksTheRunMade() throws {
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
            settingsSignature: "sig-warning-checks"
        )
        func assembled(_ delta: WatchComputeDelta, settings: WatchWarningSettings?) throws -> WatchMetricsSnapshot {
            try XCTUnwrap(WatchComputeAssembly.assemble(
                seed: seed,
                delta: delta,
                permission: .defaultValue,
                generation: 1,
                windowStart: WatchDeltaSplicer.deltaStart(dataThrough: now, calendar: calendar),
                now: now,
                calendar: calendar,
                warningSettings: settings
            )).snapshot
        }

        var delta = WatchComputeDelta()
        delta.workouts = .success([])
        delta.warningReadings = [
            .highWristTemperature: .success([reading(at(4), 38.4)]),
            .lowBloodOxygen: .success([reading(at(2), 89)]),
            .highHeartRate: .success([]),
            .lowHeartRate: .success([reading(at(3), 38)])
        ]
        XCTAssertEqual(try assembled(delta, settings: settings(defaultThresholds)).warningChecks, [
            check(lowHeartRate, threshold: 40, episode: episode(at(3), at(3), extreme: 38)),
            check(highHeartRate, threshold: 120, episode: nil),
            check(lowBloodOxygen, threshold: 90, episode: episode(at(2), at(2), extreme: 89)),
            check(highSkinTemperature, threshold: 38, episode: episode(at(4), at(4), extreme: 38.4))
        ])
        XCTAssertNil(try assembled(delta, settings: nil).warningChecks, "an older iPhone sent no settings")
        XCTAssertNil(
            try assembled(WatchComputeDelta(), settings: settings(defaultThresholds)).warningChecks,
            "no read, no field"
        )
    }

    // MARK: - Compute → displayed

    /// Each kind the compute checked replaces its displayed check, every
    /// other kind keeps its own, and the list comes out in kind order
    /// whatever order either side held.
    func testAComputeReplacesTheKindsItCheckedAndKeepsTheRest() {
        let displayed = snapshot(warningChecks: Array(displayedChecks.reversed()))
        let lowHeartRateNow = check(lowHeartRate, threshold: 40, episode: episode(at(3), at(3, 25), extreme: 36))
        let highHeartRateNow = check(highHeartRate, threshold: 120, episode: nil)

        let merged = WatchComputeMerge.mergingComputed(computed([highHeartRateNow, lowHeartRateNow]), into: displayed)

        XCTAssertEqual(merged.warningChecks, [lowHeartRateNow, highHeartRateNow, displayedChecks[1]])
    }

    /// A compute that checked nothing carries no field and moves nothing;
    /// over a snapshot without checks the compute's are adopted, and an
    /// empty list is never stored.
    func testAComputeWithoutChecksKeepsThemAndAnEmptyListIsNeverStored() {
        XCTAssertEqual(
            WatchComputeMerge.mergingComputed(computed(nil), into: snapshot(warningChecks: displayedChecks)).warningChecks,
            displayedChecks
        )
        XCTAssertEqual(
            WatchComputeMerge.mergingComputed(computed(displayedChecks), into: snapshot()).warningChecks,
            displayedChecks
        )
        XCTAssertNil(WatchComputeMerge.mergingComputed(computed([]), into: snapshot()).warningChecks)
    }

    func testComputeNeverRepopulatesAResetTombstone() {
        let merged = WatchComputeMerge.mergingComputed(computed(displayedChecks), into: snapshot(isReset: true))

        XCTAssertNil(merged.warningChecks)
        XCTAssertEqual(merged.isReset, true)
    }

    // MARK: - Phone push → displayed

    /// The phone never sends checks, so an ordinary push keeps the local ones.
    func testAPushKeepsTheLocalChecks() {
        let push = snapshot(generatedAt: t3)
        XCTAssertNil(push.warningChecks)

        XCTAssertEqual(
            WatchComputeMerge.merging(push, over: snapshot(warningChecks: displayedChecks)).warningChecks,
            displayedChecks
        )
    }

    /// Belt and braces: the settings change path strips the checks before it
    /// merges, and the mode drops them on its own too.
    func testTheSettingsChangeModeDropsTheChecks() {
        let merged = WatchComputeMerge.merging(
            snapshot(generatedAt: t3),
            over: snapshot(warningChecks: displayedChecks),
            treatingBlanksAsAuthoritative: true
        )

        XCTAssertNil(merged.warningChecks)
    }

    /// A permission or data source change strips the local provenance before
    /// the push resolves, and no push brings the checks back: they wait for
    /// the next compute.
    func testStrippingLocalProvenanceDropsTheChecks() {
        let stripped = WatchComputeMerge.strippingLocalProvenance(from: snapshot(warningChecks: displayedChecks))
        XCTAssertNil(stripped.warningChecks)

        let push = snapshot(generatedAt: t3)
        XCTAssertNil(WatchComputeMerge.merging(push, over: stripped).warningChecks)
        XCTAssertNil(WatchComputeMerge.merging(push, over: stripped, treatingBlanksAsAuthoritative: true).warningChecks)
    }

    // MARK: - The iPhone's settings

    /// No merge rule of their own: a push brings them, in either mode, and
    /// an older iPhone's push without them clears them, while a compute and
    /// the provenance strip leave them as they are.
    func testTheSettingsFollowThePushAlone() {
        var displayed = snapshot()
        displayed.warningSettings = settings(defaultThresholds)
        var push = snapshot(generatedAt: t3)
        push.warningSettings = settings([lowHeartRate: 45])

        XCTAssertEqual(WatchComputeMerge.merging(push, over: displayed).warningSettings, push.warningSettings)
        XCTAssertEqual(
            WatchComputeMerge.merging(push, over: displayed, treatingBlanksAsAuthoritative: true).warningSettings,
            push.warningSettings
        )
        XCTAssertNil(WatchComputeMerge.merging(snapshot(generatedAt: t3), over: displayed).warningSettings)

        var computedSnapshot = WatchMetricsSnapshot(generatedAt: t2, lastRefreshDate: t2, metrics: [])
        computedSnapshot.warningSettings = settings([lowHeartRate: 50])
        let result = WatchComputeResult(snapshot: computedSnapshot, dataAsOf: [:], coverage: t2, generation: 3)
        XCTAssertEqual(WatchComputeMerge.mergingComputed(result, into: displayed).warningSettings, displayed.warningSettings)
        XCTAssertEqual(WatchComputeMerge.strippingLocalProvenance(from: displayed).warningSettings, displayed.warningSettings)
    }
}
