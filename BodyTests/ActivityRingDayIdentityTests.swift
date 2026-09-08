import XCTest
@testable import Body

final class ActivityRingDayIdentityTests: XCTestCase {
    private let closed = ActivityRingSummary(move: .init(value: 500, goal: 500),
                                             exercise: .init(value: 30, goal: 30), stand: .init(value: 12, goal: 12))
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private func day(_ month: Int, _ day: Int, calendar: Calendar) -> ActivityRingDaySummary {
        .init(date: calendar.date(from: DateComponents(year: 2026, month: month, day: day))!,
              summary: closed, calendar: calendar)
    }
    private func legacy(_ entries: [ActivityRingDaySummary]) throws -> ActivityRingHistorySnapshot {
        // An actual pre-amendment JSON shape, not a test-only migration setter.
        let encoded = try JSONEncoder().encode(ActivityRingHistorySnapshot(days: entries))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "validatedMonthKeys")
        object.removeValue(forKey: "unattributedDays")
        object["days"] = (object["days"] as! [[String: Any]]).map { entry in
            var entry = entry
            entry.removeValue(forKey: "calendarDay")
            return entry
        }
        return try JSONDecoder().decode(ActivityRingHistorySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testCalendarDaySurvivesTravelAndMonthBoundaryReplacement() throws {
        for (from, to) in [("America/New_York", "America/Los_Angeles"),
                           ("America/Los_Angeles", "America/New_York"),
                           ("Pacific/Kiritimati", "Pacific/Pago_Pago"),
                           ("Pacific/Pago_Pago", "Pacific/Kiritimati")] {
            let original = calendar(from), display = calendar(to)
            let august = day(8, 31, calendar: original), september = day(9, 1, calendar: original)
            let history = ActivityRingHistorySnapshot(days: [august, september],
                                                      loadedMonthKeys: [.init(month: 8, year: 2026), .init(month: 9, year: 2026)])
            let loaded = try JSONDecoder().decode(ActivityRingHistorySnapshot.self, from: JSONEncoder().encode(history))
            let months = loaded.calendarMonths(calendar: display, date: day(9, 5, calendar: display).date)
            XCTAssertEqual(months.first { $0.month == 8 }?.completedRingCount, 1)
            XCTAssertEqual(months.first { $0.month == 9 }?.days.first?.summary, closed)
            XCTAssertEqual(loaded.days.map(\.date), history.days.map(\.date), "Keep original instants too")
            let repaired = loaded.replacingLoadedMonths(with: .init(days: [], loadedMonthKeys: [.init(month: 9, year: 2026)]), calendar: display)
            XCTAssertEqual(repaired.days, [august], "A September repair must not replace August after travel")
        }
    }

    func testDSTDaysRetainTheirLabels() {
        let ny = calendar("America/New_York"), la = calendar("America/Los_Angeles")
        for (month, date, hours) in [(3, 8, 23), (11, 1, 25)] {
            let entry = day(month, date, calendar: ny)
            let next = ny.date(byAdding: .day, value: 1, to: entry.date)!
            XCTAssertEqual(next.timeIntervalSince(entry.date), Double(hours) * 3600)
            XCTAssertEqual(la.component(.day, from: entry.date(in: la)!), date)
        }
    }

    func testUnknownLegacyAttributionIsArchivedUntilAllPossibleMonthsValidate() throws {
        let entry = day(9, 1, calendar: calendar("America/New_York"))
        let old = try legacy([entry])
        XCTAssertTrue(old.days.isEmpty)
        XCTAssertFalse(old.isEmpty, "Unproven history is retained, not deleted")
        XCTAssertEqual(old.unattributedDays.first?.date, entry.date)
        XCTAssertEqual(old.unattributedDays.first?.summary, closed)
        XCTAssertEqual(Set(old.pendingDayIdentityMonthKeys), [.init(month: 8, year: 2026), .init(month: 9, year: 2026)])
        XCTAssertEqual(old.calendarMonths(date: entry.date).reduce(0) { $0 + $1.completedRingCount }, 0)

        let partial = old.replacingLoadedMonths(with: .init(days: [entry], loadedMonthKeys: [.init(month: 9, year: 2026)]))
        XCTAssertEqual(partial.unattributedDays.count, 1, "An adjacent-day guess must not discard the legacy record")
        let reloaded = try JSONDecoder().decode(ActivityRingHistorySnapshot.self, from: JSONEncoder().encode(partial))
        XCTAssertEqual(reloaded, partial)
        XCTAssertEqual(reloaded.replacingLoadedMonths(with: .empty), reloaded, "Failure/absent coverage cannot repair history")
        let repaired = reloaded.replacingLoadedMonths(with: .init(days: [], loadedMonthKeys: [],
                                                                 validatedMonthKeys: [.init(month: 8, year: 2026)]))
        XCTAssertTrue(repaired.unattributedDays.isEmpty)
        XCTAssertEqual(repaired.days, [entry])
        XCTAssertEqual(repaired.loadedMonthKeys, [.init(month: 9, year: 2026)], "Empty backfill coverage need not create a visible empty month")
    }

    func testVerifiedFirstDayOfMonthIsNotDiscardedAsLegacyTruncation() {
        let cal = calendar("America/New_York"), entry = day(8, 1, calendar: cal)
        let history = ActivityRingHistorySnapshot(days: [entry], loadedMonthKeys: [.init(month: 8, year: 2026)])
        XCTAssertEqual(history.removingLikelyBoundaryTruncatedLoadedMonths(date: day(9, 5, calendar: cal).date, calendar: cal), history)
    }

    func testEmptyValidatedChunkReplacesOnlyItsProvenWindow() {
        let cal = calendar("America/New_York")
        let august = day(8, 15, calendar: cal), september = day(9, 1, calendar: cal)
        let history = ActivityRingHistorySnapshot(days: [august, september])
        let emptyAugust = ActivityRingHistorySnapshot(days: [], validatedMonthKeys: [.init(month: 8, year: 2026)])
        XCTAssertEqual(history.replacingLoadedMonths(with: emptyAugust, calendar: cal).days, [september])
        XCTAssertEqual(history.replacingLoadedMonths(with: .empty, calendar: cal).days, [august, september])
    }

    func testExclusiveResumeDaySurvivesTravelAndMetadataRoundTrip() throws {
        let ny = calendar("America/New_York"), la = calendar("America/Los_Angeles")
        let checkpoint = day(9, 1, calendar: ny)
        let metadata = HealthDashboardSnapshotStore.PersistenceMetadata(ringBackfill: .pending(resumeFrom: checkpoint.date),
                                                                        ringBackfillResumeDay: checkpoint.calendarDay)
        let loaded = try JSONDecoder().decode(HealthDashboardSnapshotStore.PersistenceMetadata.self, from: JSONEncoder().encode(metadata))
        let end = try XCTUnwrap(HealthKitFetchEngine.activityRingBackfillWalkEnd(date: day(9, 5, calendar: la).date,
                                                                               resumeFrom: loaded.ringBackfillResumeDay?.date(in: la), calendar: la))
        XCTAssertEqual(la.component(.day, from: end), 31)
        XCTAssertEqual(la.component(.month, from: end), 8)
        XCTAssertEqual(loaded.ringDayIdentityVersion, 1)
    }

    func testFailedAtomicRepairKeepsArchivedHistoryAndCoverageForRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BodyRingIdentity.\(UUID().uuidString)")
        let file = directory.appendingPathComponent("dashboard.json")
        let suiteName = "BodyRingIdentity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suiteName) }
        var snapshot = HealthDashboardSnapshot.empty
        snapshot.activityRingHistory = try legacy([day(8, 15, calendar: calendar("America/New_York"))])
        let original = snapshot
        XCTAssertEqual(HealthDashboardSnapshotStore.saveWithOutcome(snapshot, metadata: .init(), defaults: defaults, fileURL: file).main, .written)
        snapshot.activityRingHistory = snapshot.activityRingHistory.replacingLoadedMonths(with: .init(days: [], loadedMonthKeys: [.init(month: 8, year: 2026)]))
        XCTAssertTrue(snapshot.activityRingHistory.unattributedDays.isEmpty)
        var failedIO = HealthDashboardSnapshotStore.PersistenceIO()
        failedIO.write = { _, _ in throw NSError(domain: "InjectedRingWrite", code: 1) }
        XCTAssertEqual(HealthDashboardSnapshotStore.saveWithOutcome(snapshot, metadata: .init(), defaults: defaults, fileURL: file, io: failedIO).main, .failed)
        XCTAssertEqual(HealthDashboardSnapshotStore.load(defaults: defaults, fileURL: file)?.activityRingHistory, original.activityRingHistory)
        XCTAssertEqual(HealthDashboardSnapshotStore.saveWithOutcome(snapshot, metadata: .init(), defaults: defaults, fileURL: file).main, .written)
        XCTAssertEqual(HealthDashboardSnapshotStore.load(defaults: defaults, fileURL: file)?.activityRingHistory, snapshot.activityRingHistory)
        XCTAssertEqual(HealthDashboardSnapshotStore.saveWithOutcome(snapshot, metadata: .init(), defaults: defaults, fileURL: file).main, .unchanged)
    }

    @MainActor
    func testLegacyCheckpointRestartsOnceWhileNewPartialRepairResumes() throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let old = try JSONDecoder().decode(HealthDashboardSnapshotStore.PersistenceMetadata.self,
                                           from: Data(#"{"ringBackfill":{"completed":{}}}"#.utf8))
        XCTAssertNil(old.ringDayIdentityVersion)
        let legacyStore = store(metadata: old)
        XCTAssertEqual(legacyStore.activityRingBackfillState, .pending(resumeFrom: nil))
        let cal = calendar("America/New_York"), checkpoint = day(9, 1, calendar: cal)
        let partial = HealthDashboardSnapshotStore.PersistenceMetadata(ringBackfill: .pending(resumeFrom: checkpoint.date),
                                                                       ringBackfillResumeDay: checkpoint.calendarDay)
        let newStore = store(metadata: partial)
        XCTAssertEqual(newStore.activityRingBackfillState, partial.ringBackfill)
        XCTAssertEqual(newStore.currentDashboardPersistenceMetadata().ringBackfillResumeDay, checkpoint.calendarDay)
        XCTAssertEqual(store(metadata: .init(ringBackfill: .completed)).activityRingBackfillState, .completed)
    }

    @MainActor
    func testArchiveRepairRemainsReachableAtHistoryEndWithoutRearmingPaginationOrInventingGaps() throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let cal = Calendar.bodyGregorian
        let january = day(1, 15, calendar: cal), june = day(6, 15, calendar: cal)
        let store = store(metadata: .init(), history: try legacy([january, june]))
        let oldEmpty = ActivityRingMonthKey(month: 12, year: 2025)
        let juneKey = ActivityRingMonthKey(month: 6, year: 2026)
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        XCTAssertTrue(store.applyActivityRingArchiveRepair(.init(days: [], loadedMonthKeys: [oldEmpty]), capturedEpoch: 0))
        store.noteActivityRingHistoryExhausted()
        XCTAssertFalse(store.hasMoreActivityRingHistory)
        XCTAssertTrue(store.canLoadEarlierActivityRings, "The view must still admit archived months")
        XCTAssertTrue(store.applyActivityRingArchiveRepair(.init(days: [], loadedMonthKeys: [juneKey]), capturedEpoch: 0))
        XCTAssertFalse(store.hasMoreActivityRingHistory)
        XCTAssertEqual(store.exhaustedActivityRingMonthKeys, [oldEmpty, juneKey])
        XCTAssertTrue(store.activityRingHistory.loadedMonthKeys.isEmpty, "Scattered empty repairs are coverage, not visible gap months")
        XCTAssertTrue(store.canLoadEarlierActivityRings)
        XCTAssertTrue(store.applyActivityRingArchiveRepair(.init(days: [january], loadedMonthKeys: [januaryKey]), capturedEpoch: 0))
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [januaryKey])
        XCTAssertEqual(store.exhaustedActivityRingMonthKeys, [oldEmpty, juneKey])
        XCTAssertFalse(store.hasMoreActivityRingHistory)
        XCTAssertFalse(store.canLoadEarlierActivityRings, "Completing repair must not reopen exhausted history")

        let view = try BodyTestSupport.sourceText(at: "Body/Views/BodyActivityRingsDetailView.swift")
        XCTAssertEqual(view.components(separatedBy: "workoutStore.canLoadEarlierActivityRings").count - 1, 2,
                       "Both the caller admission and loading indicator must share the archive-aware predicate")
    }

    @MainActor
    func testFailedOrObsoleteArchiveRepairPreservesHistoryAndPaginationState() throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let history = try legacy([day(6, 15, calendar: .bodyGregorian)])
        let store = store(metadata: .init(), history: history)
        store.noteActivityRingHistoryExhausted()
        XCTAssertFalse(store.applyActivityRingArchiveRepair(.empty, capturedEpoch: 0))
        XCTAssertFalse(store.applyActivityRingArchiveRepair(.init(days: [], loadedMonthKeys: [.init(month: 6, year: 2026)]), capturedEpoch: -1))
        XCTAssertEqual(store.activityRingHistory, history)
        XCTAssertTrue(store.exhaustedActivityRingMonthKeys.isEmpty)
        XCTAssertFalse(store.hasMoreActivityRingHistory)
        XCTAssertTrue(store.canLoadEarlierActivityRings)
    }

    @MainActor
    func testPendingRepairCacheTracksInitialLoadCoverageAndNewArchive() throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let history = try legacy([day(9, 1, calendar: calendar("America/New_York"))])
        let store = store(metadata: .init(), history: history)
        let august = ActivityRingMonthKey(month: 8, year: 2026)
        let september = ActivityRingMonthKey(month: 9, year: 2026)
        XCTAssertEqual(store.pendingActivityRingRepairMonthKeys, [august, september])
        XCTAssertTrue(store.applyActivityRingArchiveRepair(.init(days: [], loadedMonthKeys: [september]), capturedEpoch: 0))
        XCTAssertEqual(store.pendingActivityRingRepairMonthKeys, [august])
        XCTAssertTrue(store.applyActivityRingArchiveRepair(.init(days: [], loadedMonthKeys: [august]), capturedEpoch: 0))
        XCTAssertTrue(store.pendingActivityRingRepairMonthKeys.isEmpty)
        let older = try legacy([day(1, 15, calendar: .bodyGregorian)])
        XCTAssertTrue(store.applyActivityRingHistoryChunk(older, capturedEpoch: 0))
        XCTAssertEqual(store.pendingActivityRingRepairMonthKeys, [.init(month: 1, year: 2026)])
        XCTAssertEqual(store.pendingActivityRingRepairMonthKeys, store.activityRingHistory.pendingDayIdentityMonthKeys)
    }

    @MainActor
    func testLegacyArchiveAdmissionReadCost() throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let cal = calendar("America/New_York")
        let start = day(1, 15, calendar: cal).date
        let entries = (0..<3650).map { offset in
            ActivityRingDaySummary(date: start.addingTimeInterval(Double(-offset) * 86400),
                                   summary: closed, calendar: cal)
        }
        let store = store(metadata: .init(), history: try legacy(entries))
        store.noteActivityRingHistoryExhausted()
        for run in 1...3 {
            let start = ContinuousClock.now
            var admitted = 0
            for _ in 0..<30 {
                if store.canLoadEarlierActivityRings { admitted += 1 }
            }
            let elapsed = start.duration(to: .now)
            XCTAssertEqual(admitted, 30)
            print("Ring archive admission: 3650 days, 30 reads, run \(run): \(elapsed)")
        }
    }

    @MainActor
    private func store(metadata: HealthDashboardSnapshotStore.PersistenceMetadata,
                       history: ActivityRingHistorySnapshot = .empty) -> HealthKitWorkoutStore {
        HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .init(summary: .empty, trends: .empty, activityRingHistory: history),
                              initialPersistenceMetadata: metadata, initialPermissionSelection: .init(enabledPermissions: [.activityRings]),
                              initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
                              initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [], engineHealthStore: FakeHealthStore())
    }
}
