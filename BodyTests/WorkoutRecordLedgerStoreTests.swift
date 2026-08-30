//
//  WorkoutRecordLedgerStoreTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutRecordLedgerStoreTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutRecordLedgerStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
        directoryURL = nil
        try super.tearDownWithError()
    }

    private func workout(
        id: UUID = UUID(),
        type: BodyWorkoutType = .running,
        start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        duration: TimeInterval = 1800,
        distance: Double? = 5_000
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            type: type,
            startDate: start,
            duration: duration,
            distanceMeters: distance
        )
    }

    private func ledger(_ workouts: [WorkoutSummary]) -> WorkoutRecordLedger {
        var ledger = WorkoutRecordLedger()
        for workout in workouts {
            ledger.upsert(workout)
        }
        return ledger
    }

    private var fileURL: URL {
        directoryURL.appendingPathComponent("ledger.json")
    }

    func testSaveAndLoadRoundTripsContributionsAndScanState() throws {
        let first = workout(distance: 5_000)
        let second = workout(type: .cycling, duration: 3600, distance: 20_000)
        var stored = ledger([first, second])
        stored.scannedThrough = Date(timeIntervalSince1970: 1_700_100_000)
        stored.baselineComplete = true

        XCTAssertTrue(WorkoutRecordLedgerStore.save(stored, directoryURL: directoryURL))

        let loaded = try XCTUnwrap(WorkoutRecordLedgerStore.load(directoryURL: directoryURL))
        XCTAssertEqual(loaded.schemaVersion, WorkoutRecordLedger.currentSchemaVersion)
        XCTAssertEqual(loaded.scannedThrough, stored.scannedThrough)
        XCTAssertTrue(loaded.baselineComplete)
        XCTAssertEqual(loaded.contributions, stored.contributions)
    }

    /// The derived winner index isn't encoded, so a round trip has to rebuild it —
    /// otherwise a relaunch would show no records at all until the next fold.
    func testLoadedLedgerRebuildsRecordsIndex() throws {
        let winner = workout(duration: 7200, distance: 30_000)
        let others = (1...3).map { index in
            workout(
                start: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400),
                duration: 600,
                distance: 3_000
            )
        }
        var stored = ledger([winner] + others)
        stored.baselineComplete = true
        XCTAssertTrue(WorkoutRecordLedgerStore.save(stored, directoryURL: directoryURL))

        let loaded = try XCTUnwrap(WorkoutRecordLedgerStore.load(directoryURL: directoryURL))
        // Longest and furthest, but not fastest — the short fillers run a better pace.
        XCTAssertEqual(loaded.records(for: winner), [.duration, .distance])
    }

    func testSaveSkipsRewriteWhenBytesAreUnchanged() {
        let stored = ledger([workout(), workout(type: .cycling)])
        XCTAssertTrue(WorkoutRecordLedgerStore.save(stored, directoryURL: directoryURL))
        XCTAssertFalse(WorkoutRecordLedgerStore.save(stored, directoryURL: directoryURL))
    }

    func testLoadReturnsNilForSchemaVersionMismatch() throws {
        let stored = ledger([workout()])
        XCTAssertTrue(WorkoutRecordLedgerStore.save(stored, directoryURL: directoryURL))

        // Rewrite the persisted bytes with a future schema version; the store must
        // discard rather than decode a shape it no longer understands.
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        object["schemaVersion"] = WorkoutRecordLedger.currentSchemaVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: fileURL)

        XCTAssertNil(WorkoutRecordLedgerStore.load(directoryURL: directoryURL))
    }

    func testLoadReturnsNilWhenNothingIsStored() {
        XCTAssertNil(WorkoutRecordLedgerStore.load(directoryURL: directoryURL))
    }

    func testDeleteAllRemovesTheStoredLedger() {
        XCTAssertTrue(WorkoutRecordLedgerStore.save(ledger([workout()]), directoryURL: directoryURL))
        XCTAssertGreaterThan(WorkoutRecordLedgerStore.totalDiskSizeBytes(directoryURL: directoryURL), 0)

        WorkoutRecordLedgerStore.deleteAll(directoryURL: directoryURL)

        XCTAssertNil(WorkoutRecordLedgerStore.load(directoryURL: directoryURL))
        XCTAssertEqual(WorkoutRecordLedgerStore.totalDiskSizeBytes(directoryURL: directoryURL), 0)
    }
}
