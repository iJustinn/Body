//
//  WatchBaselineSyncTests.swift
//  BodyWatchTests
//
//  The Settings page's Sync Baseline row: when a received seed counts as a
//  sync (`WatchMetricsModel.recordBaselineIntake`), how the iPhone's reply
//  moves a pending request (`baselineSyncState(afterReply:)`), and where the
//  last sync date comes from after a relaunch. The activation replay case is
//  the one that matters most: the watch re-reads `receivedApplicationContext`
//  on every launch, and counting that as a sync would make the footer read the
//  last app launch.
//

import XCTest
@testable import BodyWatch

@MainActor
final class WatchBaselineSyncTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    }

    private final class NoChanges: WatchWorkoutChangeDetecting, @unchecked Sendable {
        func detectChanges(now: Date) async -> Bool { false }
        func commitDetectedChanges() async {}
    }

    private let seedData = Data([1, 2, 3])

    private var replace: WatchMetricsModel.WatchComputeSeedIntake {
        .replace(
            seedData,
            WatchComputeSeed(
                publishedAt: .distantPast,
                dataThrough: Date(timeIntervalSinceReferenceDate: 799_000_000),
                summary: .empty,
                trends: .empty,
                seriesRanges: [:],
                settings: WatchComputeSettings(
                    idealSleepDurationMinutes: 480,
                    followsSystemUnits: true,
                    selectedTemperatureUnitRaw: "celsius",
                    showSleepScore: true,
                    showsSubMinuteAwakeSleepStages: true,
                    showsLeadingTrailingAwakeSleepStages: true,
                    healthDataSourceSelectionRaw: "{}",
                    combinesHealthDataSourcesByName: false
                ),
                settingsSignature: "sig"
            )
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "WatchBaselineSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeModel(clock: Clock, defaults: UserDefaults) -> WatchMetricsModel {
        let environment = WatchComputeEnvironment(
            isEligible: { false },
            loadPermission: { BodyHealthPermissionSelection.load() },
            isAuthorizationSettled: { _ in true },
            requestAuthorization: { _ in },
            compute: { _, _, _ in nil },
            changeTracker: NoChanges(),
            scheduleBackgroundRefresh: { _ in },
            defaults: defaults,
            now: { clock.now }
        )
        return WatchMetricsModel(persistSnapshot: { _ in true }, reloadTimelines: {}, environment: environment)
    }

    /// A model whose last sync is already recorded at `clock.now`, then the
    /// clock moved an hour on, so a later record is distinguishable.
    private func makeSyncedModel() -> (WatchMetricsModel, Clock, Date, UserDefaults) {
        let clock = Clock()
        let defaults = makeDefaults()
        let model = makeModel(clock: clock, defaults: defaults)
        model.recordBaselineIntake(replace, seedChanged: true, isReplay: false)
        let synced = clock.now
        clock.now = synced.addingTimeInterval(3_600)
        return (model, clock, synced, defaults)
    }

    // MARK: - Recording intakes

    func testLiveReplaceRecordsEvenWithUnchangedBytes() {
        let (model, clock, _, defaults) = makeSyncedModel()

        model.recordBaselineIntake(replace, seedChanged: false, isReplay: false)

        XCTAssertEqual(model.lastBaselineSyncDate, clock.now)
        XCTAssertEqual(
            defaults.double(forKey: "watchBaselineLastSyncDate"),
            clock.now.timeIntervalSinceReferenceDate
        )
    }

    func testReplayWithUnchangedBytesLeavesTheDate() {
        let (model, _, synced, _) = makeSyncedModel()

        model.recordBaselineIntake(replace, seedChanged: false, isReplay: true)

        XCTAssertEqual(model.lastBaselineSyncDate, synced)
    }

    func testReplayThatChangedTheSeedRecords() {
        let (model, clock, _, _) = makeSyncedModel()

        model.recordBaselineIntake(replace, seedChanged: true, isReplay: true)

        XCTAssertEqual(model.lastBaselineSyncDate, clock.now)
    }

    func testResetClearsTheDate() {
        let (model, _, _, defaults) = makeSyncedModel()

        model.recordBaselineIntake(.clear, seedChanged: true, isReplay: false)

        XCTAssertNil(model.lastBaselineSyncDate)
        XCTAssertNil(defaults.object(forKey: "watchBaselineLastSyncDate"))
    }

    func testSettingsMismatchClearsOnlyWhenTheSeedWasCleared() {
        let (model, _, synced, _) = makeSyncedModel()

        model.recordBaselineIntake(.clearIfSettingsMismatch("sig"), seedChanged: false, isReplay: false)
        XCTAssertEqual(model.lastBaselineSyncDate, synced)

        model.recordBaselineIntake(.clearIfSettingsMismatch("other"), seedChanged: true, isReplay: false)
        XCTAssertNil(model.lastBaselineSyncDate)
    }

    func testKeepPriorLeavesTheDate() {
        let (model, _, synced, _) = makeSyncedModel()

        model.recordBaselineIntake(.keepPrior, seedChanged: false, isReplay: false)

        XCTAssertEqual(model.lastBaselineSyncDate, synced)
    }

    func testLiveReplaceEndsAPendingOrFailedSync() {
        let (model, _, _, _) = makeSyncedModel()

        for state: WatchMetricsModel.BaselineSyncState in [.syncing, .failed(.unavailable), .failed(.noArrival)] {
            model.setBaselineSyncForTesting(state)
            model.recordBaselineIntake(replace, seedChanged: false, isReplay: false)
            XCTAssertEqual(model.baselineSync, .idle, "from \(state)")
        }
    }

    func testReplayWithUnchangedBytesKeepsAPendingSync() {
        let (model, _, _, _) = makeSyncedModel()
        model.setBaselineSyncForTesting(.syncing)

        model.recordBaselineIntake(replace, seedChanged: false, isReplay: true)

        XCTAssertEqual(model.baselineSync, .syncing)
    }

    // MARK: - Reply

    func testReplyMapping() {
        XCTAssertEqual(WatchMetricsModel.baselineSyncState(afterReply: "unavailable"), .failed(.unavailable))
        // `sent` waits for the seed itself; so does a reply from a newer
        // iPhone build this watch doesn't know, or none at all.
        XCTAssertNil(WatchMetricsModel.baselineSyncState(afterReply: "sent"))
        XCTAssertNil(WatchMetricsModel.baselineSyncState(afterReply: "future"))
        XCTAssertNil(WatchMetricsModel.baselineSyncState(afterReply: nil))
    }

    func testReplyKeysMatchThePhone() {
        // Spelled out: these ride between two separately shipped binaries.
        XCTAssertEqual(WatchBaselineSync.requestKey, "baselineSyncRequest")
        XCTAssertEqual(WatchBaselineSync.replyKey, "baselineSyncReply")
        XCTAssertEqual(WatchBaselineSync.Reply.sent.rawValue, "sent")
        XCTAssertEqual(WatchBaselineSync.Reply.unavailable.rawValue, "unavailable")
    }

    // MARK: - Relaunch

    func testDateSurvivesARelaunch() {
        let (_, clock, synced, defaults) = makeSyncedModel()

        let relaunched = makeModel(clock: clock, defaults: defaults)

        XCTAssertEqual(relaunched.lastBaselineSyncDate, synced)
    }

    func testFallsBackToTheSeedFileDateOnlyWithoutARecordedDate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyWatchBaselineSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(WatchComputeSeedStore.seedFileName)
        let defaults = makeDefaults()

        XCTAssertNil(WatchMetricsModel.loadLastBaselineSyncDate(defaults: defaults, seedFileURL: fileURL))
        XCTAssertNil(WatchComputeSeedStore.storedSeedModificationDate(fileURL: fileURL))

        XCTAssertTrue(WatchComputeSeedStore.save(seedData, fileURL: fileURL))
        let modified = try XCTUnwrap(WatchComputeSeedStore.storedSeedModificationDate(fileURL: fileURL))
        XCTAssertEqual(WatchMetricsModel.loadLastBaselineSyncDate(defaults: defaults, seedFileURL: fileURL), modified)

        let recorded = Date(timeIntervalSinceReferenceDate: 790_000_000)
        defaults.set(recorded.timeIntervalSinceReferenceDate, forKey: "watchBaselineLastSyncDate")
        XCTAssertEqual(WatchMetricsModel.loadLastBaselineSyncDate(defaults: defaults, seedFileURL: fileURL), recorded)
    }
}
