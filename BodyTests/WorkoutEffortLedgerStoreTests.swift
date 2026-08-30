//
//  WorkoutEffortLedgerStoreTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutEffortLedgerStoreTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutEffortLedgerStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
        directoryURL = nil
        try super.tearDownWithError()
    }

    private func entry(effort: Double?, daysAgo: Double) -> WorkoutEffortLedgerEntry {
        let start = Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(-daysAgo * 24 * 60 * 60)
        return WorkoutEffortLedgerEntry(startDate: start, endDate: start.addingTimeInterval(3_600), effort: effort)
    }

    func testSaveAndLoadRoundTripsScoresAndConfirmedAbsences() throws {
        let rated = UUID()
        let unrated = UUID()
        let stored = WorkoutEffortLedger(entries: [
            rated: entry(effort: 7, daysAgo: 30),
            unrated: entry(effort: nil, daysAgo: 40)
        ])

        XCTAssertTrue(WorkoutEffortLedgerStore.save(stored, directoryURL: directoryURL))

        let loaded = try XCTUnwrap(WorkoutEffortLedgerStore.load(directoryURL: directoryURL))
        XCTAssertEqual(loaded.schemaVersion, WorkoutEffortLedger.currentSchemaVersion)
        XCTAssertEqual(loaded.entries, stored.entries)
    }

    /// The encoded bytes must be stable so an unchanged ledger skips the write —
    /// every refresh rewrites the same entries otherwise.
    func testUnchangedLedgerSkipsTheWrite() {
        let ledger = WorkoutEffortLedger(entries: [
            UUID(): entry(effort: 4, daysAgo: 10),
            UUID(): entry(effort: nil, daysAgo: 11),
            UUID(): entry(effort: 9, daysAgo: 12)
        ])

        XCTAssertTrue(WorkoutEffortLedgerStore.save(ledger, directoryURL: directoryURL))
        XCTAssertFalse(WorkoutEffortLedgerStore.save(ledger, directoryURL: directoryURL))
    }

    func testLedgerFromAnotherSchemaIsDiscarded() throws {
        let ledger = WorkoutEffortLedger(entries: [UUID(): entry(effort: 5, daysAgo: 20)])
        XCTAssertTrue(WorkoutEffortLedgerStore.save(ledger, directoryURL: directoryURL))

        let fileURL = directoryURL.appendingPathComponent("ledger.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        object["schemaVersion"] = WorkoutEffortLedger.currentSchemaVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: fileURL)

        XCTAssertNil(WorkoutEffortLedgerStore.load(directoryURL: directoryURL))
    }

    func testDeleteAllRemovesTheLedger() {
        let ledger = WorkoutEffortLedger(entries: [UUID(): entry(effort: 6, daysAgo: 15)])
        XCTAssertTrue(WorkoutEffortLedgerStore.save(ledger, directoryURL: directoryURL))

        WorkoutEffortLedgerStore.deleteAll(directoryURL: directoryURL)

        XCTAssertNil(WorkoutEffortLedgerStore.load(directoryURL: directoryURL))
    }
}
