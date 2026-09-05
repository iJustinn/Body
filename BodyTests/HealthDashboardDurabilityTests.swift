import XCTest
@testable import Body

final class HealthDashboardDurabilityTests: XCTestCase {
    private typealias Store = HealthDashboardSnapshotStore
    private enum InjectedFailure: Error { case write, encode }
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent(Store.healthDashboardSnapshotFileName) }
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        suiteName = "BodyTests.Durability.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: directory)
    }

    private func snapshot(value: Double) -> HealthDashboardSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.restingHeartRate = .init(points: [.init(date: day, value: value)])
        trends.heartRateDaySamples = .init(points: [.init(date: day, value: value + 10)])
        return HealthDashboardSnapshot(
            summary: .empty,
            trends: trends,
            activityRingHistory: activityRingChunk(
                days: [day.addingTimeInterval(value * 86_400)],
                loadedMonthKeys: [ActivityRingMonthKey(month: 5, year: 2026)]
            )
        )
    }

    private func metadata(completed: Bool) -> Store.PersistenceMetadata {
        .init(ringBackfill: completed ? .completed : .pending(resumeFrom: day),
              secondarySelectionSignature: completed ? "new source" : "old source",
              freshness: .init(date: day.addingTimeInterval(completed ? 60 : 0), contextSignature: "scope"))
    }

    @discardableResult
    private func save(_ snapshot: HealthDashboardSnapshot, metadata: Store.PersistenceMetadata,
                      io: Store.PersistenceIO = .init()) -> Store.SaveOutcome {
        Store.saveWithOutcome(snapshot, metadata: metadata, defaults: defaults, fileURL: fileURL, io: io)
    }

    private func load() throws -> Store.LoadedSnapshot {
        try XCTUnwrap(Store.loadWithContext(defaults: defaults, fileURL: fileURL))
    }

    func testEnvelopeRoundTripsProgressScopeAndFreshnessAndDeduplicates() throws {
        let payload = snapshot(value: 60)
        let stamp = metadata(completed: true)
        XCTAssertEqual(save(payload, metadata: stamp), .init(main: .written, sidecar: .written))
        let firstBytes = try Data(contentsOf: fileURL)
        XCTAssertEqual(save(payload, metadata: stamp), .init(main: .unchanged, sidecar: .unchanged))
        XCTAssertEqual(try Data(contentsOf: fileURL), firstBytes)
        XCTAssertEqual(try load().metadata, stamp)
        XCTAssertEqual(try load().snapshot.activityRingHistory, payload.activityRingHistory)
        XCTAssertTrue(Store.FileSaveOutcome.unchanged.isDurable)
        XCTAssertFalse(Store.FileSaveOutcome.failed.isDurable)
    }

    func testMainWriteFailureKeepsOldCheckpointAndRetryDoesNotRefetchSidecar() throws {
        let old = snapshot(value: 60), new = snapshot(value: 65)
        save(old, metadata: metadata(completed: false))
        let oldBytes = try Data(contentsOf: fileURL)
        var io = Store.PersistenceIO()
        let write = io.write
        io.write = { [fileURL] data, url in
            if url == fileURL { throw InjectedFailure.write }
            try write(data, url)
        }
        XCTAssertEqual(save(new, metadata: metadata(completed: true), io: io), .init(main: .failed, sidecar: .written))
        XCTAssertEqual(try Data(contentsOf: fileURL), oldBytes)
        XCTAssertEqual(try load().metadata, metadata(completed: false))
        XCTAssertEqual(try load().snapshot.trends.restingHeartRate, old.trends.restingHeartRate)
        XCTAssertEqual(Store.loadDaySamples(fileURL: fileURL)?.heartRateDaySamples, new.trends.heartRateDaySamples)
        XCTAssertEqual(save(new, metadata: metadata(completed: true)), .init(main: .written, sidecar: .unchanged))
        XCTAssertEqual(try load().metadata, metadata(completed: true))
    }

    func testSidecarWriteFailureIsNotAcknowledgedByMainSuccessAndRetryKeepsEnvelope() throws {
        let old = snapshot(value: 60), new = snapshot(value: 65)
        save(old, metadata: metadata(completed: false))
        var io = Store.PersistenceIO()
        let write = io.write
        io.write = { [fileURL] data, url in
            if url != fileURL { throw InjectedFailure.write }
            try write(data, url)
        }
        let result = save(new, metadata: metadata(completed: true), io: io)
        XCTAssertEqual(result, .init(main: .written, sidecar: .failed))
        XCTAssertTrue(result.main.isDurable)
        XCTAssertFalse(result.sidecar.isDurable)
        XCTAssertEqual(try load().metadata, metadata(completed: true))
        XCTAssertEqual(Store.loadDaySamples(fileURL: fileURL)?.heartRateDaySamples, old.trends.heartRateDaySamples)
        let committedMain = try Data(contentsOf: fileURL)
        XCTAssertEqual(save(new, metadata: metadata(completed: true)), .init(main: .unchanged, sidecar: .written))
        XCTAssertEqual(try Data(contentsOf: fileURL), committedMain)
        XCTAssertEqual(Store.loadDaySamples(fileURL: fileURL)?.heartRateDaySamples, new.trends.heartRateDaySamples)
    }

    func testEncodeFailuresLeaveTheirRespectiveFileIntact() throws {
        for failingEncode in [1, 2] {
            let old = snapshot(value: 60), new = snapshot(value: 65)
            save(old, metadata: metadata(completed: false))
            let target = failingEncode == 1 ? fileURL : Store.daySamplesFileURL(alongside: fileURL)
            let bytes = try Data(contentsOf: target)
            var io = Store.PersistenceIO()
            var encodeCount = 0
            io.encoder = {
                encodeCount += 1
                let encoder = Store.makeSnapshotEncoder()
                if encodeCount == failingEncode {
                    encoder.dateEncodingStrategy = .custom { _, _ in throw InjectedFailure.encode }
                }
                return encoder
            }
            XCTAssertEqual(save(new, metadata: metadata(completed: true), io: io),
                           failingEncode == 1 ? .init(main: .failed, sidecar: .written) : .init(main: .written, sidecar: .failed))
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertEqual(try load().metadata, metadata(completed: failingEncode == 2))
        }
    }

    func testReloadAtEachWriteBoundaryNeverSeesNewProgressBesideOldPayload() throws {
        let old = snapshot(value: 60), new = snapshot(value: 65)
        save(old, metadata: metadata(completed: false))
        var io = Store.PersistenceIO()
        let write = io.write
        var boundaries = 0
        io.write = { [self] data, url in
            // Reload before either atomic replacement, exactly where an exit
            // would strand the remaining work. No timing or sleep assumption.
            boundaries += 1
            let reloaded = try load()
            XCTAssertEqual(reloaded.metadata, metadata(completed: url != fileURL))
            XCTAssertEqual(reloaded.snapshot.trends.restingHeartRate,
                           url == fileURL ? old.trends.restingHeartRate : new.trends.restingHeartRate)
            XCTAssertEqual(reloaded.snapshot.activityRingHistory,
                           url == fileURL ? old.activityRingHistory : new.activityRingHistory)
            try write(data, url)
        }
        save(new, metadata: metadata(completed: true), io: io)
        XCTAssertEqual(boundaries, 2)
    }

    func testLegacyAndUnknownEnvelopeKeepHistoryButIgnoreUnprovenDefaults() throws {
        let payload = snapshot(value: 60)
        Store.saveActivityRingBackfillState(.completed, defaults: defaults)
        Store.saveLastSuccessfulRefreshDate(day, defaults: defaults)
        Store.saveSecondarySelectionSignature("unbound", defaults: defaults)
        let legacy = try JSONEncoder().encode(payload)
        try legacy.write(to: fileURL, options: .atomic)
        XCTAssertEqual(try load().snapshot, payload)
        XCTAssertEqual(try load().metadata, .init())
        for version in [1, 99] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
            object["envelopeVersion"] = version
            object["metadata"] = ["ringBackfill": ["completed": [:]], "freshness": "invalid"]
            try JSONSerialization.data(withJSONObject: object).write(to: fileURL, options: .atomic)
            XCTAssertEqual(try load().snapshot, payload)
            XCTAssertEqual(try load().metadata, .init())
        }
        save(payload, metadata: metadata(completed: true))
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        future["envelopeVersion"] = 99
        try JSONSerialization.data(withJSONObject: future).write(to: fileURL, options: .atomic)
        XCTAssertEqual(try load().snapshot.activityRingHistory, payload.activityRingHistory)
        XCTAssertEqual(try load().metadata, .init())
    }

    func testPreservedUnhydratedSidecarDoesNotAcknowledgeEmptyRepair() throws {
        let payload = snapshot(value: 60)
        save(payload, metadata: metadata(completed: false))
        let unhydrated = HealthDashboardSnapshot(summary: payload.summary, trends: payload.trends.strippingDaySamples(),
                                                activityRingHistory: payload.activityRingHistory)
        let result = save(unhydrated, metadata: metadata(completed: false))
        XCTAssertEqual(result, .init(main: .unchanged, sidecar: .preserved))
        XCTAssertFalse(result.sidecar.isDurable)
        XCTAssertEqual(Store.loadDaySamples(fileURL: fileURL)?.heartRateDaySamples, payload.trends.heartRateDaySamples)
    }

    @MainActor
    func testLiveSuccessRequiresSettledTailAndSuccessfulEnvelopeForColdStartFreshness() throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let store = emptyHealthDataStore()
        let payload = snapshot(value: 60)
        let scope = store.currentDashboardCacheScope().signature
        store.markRefreshSucceeded(date: day, refreshedVitals: true, publishesWatch: false)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, day)
        XCTAssertNil(store.currentDashboardPersistenceMetadata().freshness)
        save(payload, metadata: store.currentDashboardPersistenceMetadata())
        XCTAssertNil(try load().metadata.freshness)

        store.stageCompletedDashboardFreshness(date: day)
        let candidate = store.currentDashboardPersistenceMetadata()
        var io = Store.PersistenceIO()
        io.write = { _, _ in throw InjectedFailure.write }
        XCTAssertEqual(save(payload, metadata: candidate, io: io).main, .failed)
        XCTAssertNil(try load().metadata.freshness)
        save(payload, metadata: candidate)
        let durable = try load()
        let restored = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: durable.snapshot,
                                            initialSummaryContextSignature: scope, initialPersistenceMetadata: durable.metadata)
        XCTAssertEqual(restored.lastSuccessfulRefreshDate, day)
        var wrongScope = durable.metadata
        wrongScope.freshness = .init(date: day, contextSignature: "different layout or source")
        let stale = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: durable.snapshot,
                                         initialSummaryContextSignature: scope, initialPersistenceMetadata: wrongScope)
        XCTAssertNil(stale.lastSuccessfulRefreshDate)
    }

    @MainActor
    func testUncommittedRingChunkPaintsImmediatelyButReloadRetainsDurableBoundary() throws {
        let store = activityRingsEnabledStore()
        let firstBoundary = day.addingTimeInterval(-60 * 60 * 24 * 30)
        let oldPayload = snapshot(value: 60)
        let oldMetadata = Store.PersistenceMetadata(ringBackfill: .pending(resumeFrom: day))
        save(oldPayload, metadata: oldMetadata)
        XCTAssertTrue(store.landActivityRingBackfillChunk(
            activityRingBackfillChunk(days: [firstBoundary], loadedMonthKeys: [.init(month: 4, year: 2026)],
                                     nextChunkEndDate: firstBoundary), capturedEpoch: 0))
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [firstBoundary])
        XCTAssertEqual(store.activityRingBackfillState, .pending(resumeFrom: firstBoundary))
        // No commit to this injected disk yet: a new process resumes the old
        // boundary and cannot skip the chunk that is already visible in memory.
        XCTAssertEqual(try load().metadata.ringBackfill, .pending(resumeFrom: day))
        let pending = HealthDashboardSnapshot(summary: store.healthSummary, trends: store.healthTrends,
                                               activityRingHistory: store.activityRingHistory)
        save(pending, metadata: store.currentDashboardPersistenceMetadata())
        XCTAssertEqual(try load().metadata.ringBackfill, .pending(resumeFrom: firstBoundary))
        XCTAssertEqual(try load().snapshot.activityRingHistory, pending.activityRingHistory)
    }
}
