import XCTest
@testable import Body

final class HistoricalMonthRepairTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ month: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    @MainActor
    func testUnchangedLedgerPublicationAndEmptyMonthFoldPreserveRepairRevision() {
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [], engineHealthStore: FakeHealthStore())
        store.contextRefreshOverride = { _ in }
        defer { store.contextRefreshOverride = nil }
        var ledger = WorkoutRecordLedger()
        ledger.upsert(WorkoutSummary(id: UUID(), type: .running, startDate: date(5), duration: 1800, distanceMeters: 5000))
        store.publishRecordLedger(ledger)
        let revision = store.recordLedgerRevision
        store.publishRecordLedger(ledger)
        store.foldMonthIntoRecordLedger(key: .init(month: 6, year: 2026), workouts: [], calendar: calendar)
        XCTAssertEqual(store.recordLedgerRevision, revision, "No-op folds must not invalidate suspended repair")
        ledger.scannedThrough = date(6)
        store.publishRecordLedger(ledger)
        XCTAssertEqual(store.recordLedgerRevision, revision + 1, "Real progress must still fence older work")
        ledger.historicalRepair = .completed(month: date(6), now: date(9), earliest: date(5), context: "scope", calendar: calendar)
        store.publishRecordLedger(ledger)
        XCTAssertEqual(store.recordLedgerRevision, revision + 2)
        ledger.reconcile(workouts: [], start: date(5), end: date(6), unvalidatedRecordIDs: [])
        store.publishRecordLedger(ledger)
        XCTAssertEqual(store.recordLedgerRevision, revision + 3, "Deletion must still fence older work")
    }

    func testCursorVisitsOldMonthsAcrossRelaunchAndRestartsAfterCompletedCycle() throws {
        let now = date(9), floor = date(6)
        var progress: HistoricalMonthRepairProgress?
        for (offset, month) in [8, 7, 6].enumerated() {
            let passDate = now.addingTimeInterval(Double(offset) * 300)
            let candidate = try XCTUnwrap(HistoricalMonthRepairProgress.candidate(after: progress,
                now: passDate, earliest: floor, context: "scope", calendar: calendar))
            XCTAssertEqual(candidate, date(month))
            progress = .completed(month: candidate, now: passDate, earliest: floor,
                context: "scope", calendar: calendar)
            progress = try JSONDecoder().decode(HistoricalMonthRepairProgress.self,
                from: JSONEncoder().encode(try XCTUnwrap(progress)))
            XCTAssertNil(HistoricalMonthRepairProgress.candidate(after: progress,
                now: passDate.addingTimeInterval(299), earliest: floor, context: "scope", calendar: calendar))
        }
        XCTAssertNil(progress?.nextMonthStart)
        XCTAssertEqual(HistoricalMonthRepairProgress.candidate(after: progress,
            now: now.addingTimeInterval(86400 + 600), earliest: floor, context: "scope", calendar: calendar), date(8))
    }

    func testScopeChangeAndClockRollbackRestartWithoutTrustingCursor() {
        let now = date(9)
        let progress = HistoricalMonthRepairProgress(nextMonthStart: date(4), validatedAt: now, context: "old")
        XCTAssertEqual(HistoricalMonthRepairProgress.candidate(after: progress, now: now,
            earliest: date(1), context: "new", calendar: calendar), date(8))
        XCTAssertEqual(HistoricalMonthRepairProgress.candidate(after: progress, now: now.addingTimeInterval(-1),
            earliest: date(1), context: "old", calendar: calendar), date(7))
    }

    func testMonthValidationExpiryContextAndMetadataOnlySave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MonthValidation.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("month.json")
        let now = date(9)
        var snapshot = WorkoutMonthSnapshot(month: 8, year: 2026, generatedAt: now, days: [])
        XCTAssertFalse(snapshot.isValidated(now: now, context: "scope"))
        snapshot.validatedAt = now
        snapshot.validationContext = "scope"
        XCTAssertTrue(snapshot.isValidated(now: now.addingTimeInterval(299), context: "scope"))
        XCTAssertFalse(snapshot.isValidated(now: now.addingTimeInterval(300), context: "scope"))
        XCTAssertFalse(snapshot.isValidated(now: now.addingTimeInterval(-1), context: "scope"))
        XCTAssertFalse(snapshot.isValidated(now: now, context: "other"))
        XCTAssertTrue(WorkoutSnapshotStore.save(snapshot, fileURL: file))
        let renewed = WorkoutMonthSnapshot(month: 8, year: 2026, generatedAt: now.addingTimeInterval(300),
            days: [], validatedAt: now.addingTimeInterval(300), validationContext: "scope")
        XCTAssertTrue(WorkoutSnapshotStore.save(renewed, fileURL: file))
        let loaded = try JSONDecoder().decode(WorkoutMonthSnapshot.self, from: Data(contentsOf: file))
        XCTAssertEqual(loaded.generatedAt, now)
        XCTAssertEqual(loaded.validatedAt, renewed.validatedAt)
        XCTAssertFalse(WorkoutSnapshotStore.save(renewed, fileURL: file))
    }

    func testRecordRepairCursorIsDurableWithItsContributionDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecordRepair.\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = WorkoutSummary(id: UUID(), type: .running, startDate: date(6), duration: 1800, distanceMeters: 5000)
        let outside = WorkoutSummary(id: UUID(), type: .running, startDate: date(5), duration: 1800, distanceMeters: 6000)
        var ledger = WorkoutRecordLedger()
        ledger.baselineComplete = true
        ledger.upsert([old, outside])
        XCTAssertTrue(WorkoutRecordLedgerStore.save(ledger, directoryURL: directory))
        ledger.reconcile(workouts: [], start: date(6), end: date(7), unvalidatedRecordIDs: [])
        ledger.historicalRepair = .completed(month: date(6), now: date(9), earliest: date(5),
            context: "scope", calendar: calendar)
        // Before commit, a relaunch still sees both the old payload and old cursor.
        let before = try XCTUnwrap(WorkoutRecordLedgerStore.load(directoryURL: directory))
        XCTAssertNil(before.historicalRepair)
        XCTAssertNotNil(before.contributions[old.id])
        XCTAssertTrue(WorkoutRecordLedgerStore.save(ledger, directoryURL: directory))
        let after = try XCTUnwrap(WorkoutRecordLedgerStore.load(directoryURL: directory))
        XCTAssertEqual(after.historicalRepair, ledger.historicalRepair)
        XCTAssertNil(after.contributions[old.id])
        XCTAssertNotNil(after.contributions[outside.id])
    }

    func testPassiveReusePreservesButDoesNotRenewValidationAndFailureRemainsDirty() {
        let now = date(9)
        let old = WorkoutMonthSnapshot(month: 8, year: 2026, generatedAt: now, days: [],
            validatedAt: now, validationContext: "scope")
        var next = old
        next.recordValidation(at: now.addingTimeInterval(60), context: "scope", previous: old,
            allDetailsValidated: false, hadQueryFailure: false)
        XCTAssertEqual(next.validatedAt, now)
        XCTAssertTrue(next.isValidated(now: now.addingTimeInterval(60), context: "scope"))
        next.recordValidation(at: now.addingTimeInterval(60), context: "scope", previous: old,
            allDetailsValidated: false, hadQueryFailure: true)
        XCTAssertNil(next.validatedAt)
        next.recordValidation(at: now.addingTimeInterval(60), context: "changed", previous: old,
            allDetailsValidated: false, hadQueryFailure: false)
        XCTAssertNil(next.validatedAt)
        next.recordValidation(at: now.addingTimeInterval(60), context: "changed", previous: old,
            allDetailsValidated: true, hadQueryFailure: false)
        XCTAssertEqual(next.validatedAt, now.addingTimeInterval(60))
    }
}
