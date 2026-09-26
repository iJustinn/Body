import XCTest
@testable import Body

final class WorkoutChangeJournalTests: XCTestCase {
    private let scope = WorkoutJournalScope(installationID: UUID(), lowerBound: Date(timeIntervalSince1970: 0), predicateVersion: 1)
    private func entry(id: UUID = UUID(), start: Double = 100) -> WorkoutJournalEntry {
        .init(id: id, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: start + 60),
            activityType: 37, duration: 60, sourceBundleIdentifier: "test")
    }

    func testBootstrapPagesAndAnchorReloadTogetherWithoutPublishingPartialGeneration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("journal.json")
        let old = entry(), new = entry()
        var value = WorkoutChangeJournal(scope: scope)
        value.entries[old.id.uuidString] = old
        value.apply(additions: [new], deletedIDs: [], nextAnchor: Data([1]))
        XCTAssertFalse(value.bootstrapComplete)
        XCTAssertEqual(value.entries[old.id.uuidString], old)
        XCTAssertNil(value.entries[new.id.uuidString])
        XCTAssertEqual(WorkoutChangeJournalStore.save(value, file: file), .written)
        XCTAssertEqual(WorkoutChangeJournalStore.save(value, file: file), .unchanged)
        value = try XCTUnwrap(WorkoutChangeJournalStore.load(file: file))
        XCTAssertEqual(value.anchor, Data([1]))
        XCTAssertEqual(value.staging?[new.id.uuidString], new)
        value.apply(additions: [], deletedIDs: [], nextAnchor: Data([2]))
        XCTAssertTrue(value.bootstrapComplete)
        XCTAssertNil(value.entries[old.id.uuidString])
        XCTAssertEqual(value.entries[new.id.uuidString], new)
        XCTAssertNotNil(value.dirtyIntervals[old.id.uuidString])
    }

    func testFailedAtomicCommitRetainsOldAnchorPayloadAndObligations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("journal.json")
        var value = WorkoutChangeJournal(scope: scope)
        let workout = entry()
        value.apply(additions: [workout], deletedIDs: [], nextAnchor: Data([1]))
        XCTAssertEqual(WorkoutChangeJournalStore.save(value, file: file), .written)
        let before = value
        value.apply(additions: [], deletedIDs: [workout.id], nextAnchor: Data([2]))
        XCTAssertEqual(WorkoutChangeJournalStore.save(value, file: file, write: { _, _ in throw CocoaError(.fileWriteUnknown) }), .failed)
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: file), before)
        XCTAssertEqual(WorkoutChangeJournalStore.save(value, file: file), .written)
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: file), value)
    }

    func testReplayMovedWorkoutUnknownDeletionAndScopeRestart() {
        var value = WorkoutChangeJournal(scope: scope)
        let original = entry(), moved = entry(start: 500)
        value.apply(additions: [original], deletedIDs: [], nextAnchor: Data([1]))
        value.apply(additions: [], deletedIDs: [], nextAnchor: Data([2]))
        value.requiresFullRepair = false
        let edited = entry(id: original.id, start: 500)
        value.apply(additions: [edited, moved], deletedIDs: [], nextAnchor: Data([3]))
        value.apply(additions: [edited, moved], deletedIDs: [], nextAnchor: Data([3]))
        XCTAssertEqual(value.entries.count, 2)
        XCTAssertEqual(value.dirtyIntervals[original.id.uuidString]?.start, original.start)
        XCTAssertEqual(value.dirtyIntervals[original.id.uuidString]?.end, edited.end)
        value.apply(additions: [], deletedIDs: [UUID()], nextAnchor: Data([4]))
        XCTAssertTrue(value.requiresFullRepair)
        let previous = value.entries
        let generation = value.generation
        let changedScope = WorkoutJournalScope(installationID: UUID(), lowerBound: scope.lowerBound, predicateVersion: 1)
        value.restart(scope: changedScope)
        XCTAssertEqual(value.scope, changedScope)
        XCTAssertEqual(value.entries, previous)
        XCTAssertNotEqual(value.generation, generation)
        XCTAssertNil(value.anchor)
        XCTAssertFalse(value.bootstrapComplete)
    }

    // MARK: - A known delta keeps repair progress and marks what it touched

    private func interval(_ entry: WorkoutJournalEntry) -> DateInterval {
        DateInterval(start: entry.start, end: entry.end)
    }

    private func repairing(_ entries: [WorkoutJournalEntry]) -> WorkoutChangeJournal {
        var value = WorkoutChangeJournal(scope: scope)
        value.staging = nil
        value.requiresFullRepair = true
        for entry in entries {
            value.entries[entry.id.uuidString] = entry
            value.dirtyIntervals[entry.id.uuidString] = interval(entry)
        }
        var progress = WorkoutJournalRepairProgress(context: "same")
        progress.completedMonths = ["2001:1", "2001:2"]
        progress.baselineInvalidated = true
        progress.detailsInvalidated = true
        progress.freshnessInvalidated = true
        progress.finalAttempt = .init(count: 2, startedAt: Date(timeIntervalSince1970: 50))
        value.repairProgress = progress
        return value
    }

    func testKnownAdditionEditAndDeletionKeepProgressAndMarkTheirIntervalsUncovered() throws {
        let kept = entry(start: 1_000), other = entry(start: 5_000)
        let base = repairing([kept, other])
        let expected = try XCTUnwrap(base.repairProgress)

        var added = base
        let new = entry(start: 9_000)
        added.apply(additions: [new], deletedIDs: [], nextAnchor: Data([1]))
        var moved = base
        let edit = entry(id: kept.id, start: 3_000)
        moved.apply(additions: [edit], deletedIDs: [], nextAnchor: Data([1]))
        var sameInterval = base
        let relabelled = WorkoutJournalEntry(id: kept.id, start: kept.start, end: kept.end,
            activityType: 52, duration: kept.duration, sourceBundleIdentifier: kept.sourceBundleIdentifier)
        sameInterval.apply(additions: [relabelled], deletedIDs: [], nextAnchor: Data([1]))
        var deleted = base
        deleted.apply(additions: [], deletedIDs: [kept.id], nextAnchor: Data([1]))

        let cases: [(WorkoutChangeJournal, String, DateInterval)] = [
            (added, new.id.uuidString, interval(new)),
            (moved, kept.id.uuidString, DateInterval(start: kept.start, end: edit.end)),
            (sameInterval, kept.id.uuidString, interval(kept)),
            (deleted, kept.id.uuidString, interval(kept)),
        ]
        for (value, key, touched) in cases {
            let progress = try XCTUnwrap(value.repairProgress, "A known delta keeps the repair progress")
            XCTAssertEqual(progress.uncovered, [key: touched])
            XCTAssertEqual(value.dirtyIntervals[key], touched, "The acknowledgement obligation is unchanged")
            XCTAssertEqual(value.dirtyIntervals[other.id.uuidString], interval(other))
            var withoutUncovered = progress
            withoutUncovered.uncovered = nil
            XCTAssertEqual(withoutUncovered, expected, "Only `uncovered` changes; reopening is the pass's job")
            XCTAssertEqual(value.revision, base.revision &+ 1)
        }
        // Equal dirty sets are exactly why the delta itself must mark the workout.
        XCTAssertEqual(sameInterval.dirtyIntervals, base.dirtyIntervals)
        XCTAssertEqual(deleted.dirtyIntervals, base.dirtyIntervals)
        XCTAssertNil(deleted.entries[kept.id.uuidString])
        XCTAssertEqual(sameInterval.entries[kept.id.uuidString], relabelled)
    }

    func testASecondDeltaForAnUncoveredWorkoutUnionsItsInterval() throws {
        let workout = entry(start: 1_000)
        var value = repairing([workout])
        let first = entry(id: workout.id, start: 3_000), second = entry(id: workout.id, start: 500)
        value.apply(additions: [first], deletedIDs: [], nextAnchor: Data([1]))
        XCTAssertEqual(value.repairProgress?.uncovered?[workout.id.uuidString],
                       DateInterval(start: workout.start, end: first.end))
        value.apply(additions: [second], deletedIDs: [], nextAnchor: Data([2]))
        XCTAssertEqual(value.repairProgress?.uncovered?[workout.id.uuidString],
                       DateInterval(start: second.start, end: first.end))
        value.apply(additions: [], deletedIDs: [workout.id], nextAnchor: Data([3]))
        XCTAssertEqual(value.repairProgress?.uncovered?[workout.id.uuidString],
                       DateInterval(start: second.start, end: first.end), "A later deletion stays inside the union")
        XCTAssertEqual(value.repairProgress?.uncovered?.count, 1)
    }

    func testUnknownDeletionAndBootstrapPagesStillDropProgress() {
        let known = entry(start: 1_000)
        var unknown = repairing([known])
        unknown.apply(additions: [entry(start: 2_000)], deletedIDs: [UUID()], nextAnchor: Data([1]))
        XCTAssertNil(unknown.repairProgress, "The old baseline cannot prove absence for an unseen id")
        XCTAssertTrue(unknown.requiresFullRepair)

        var bootstrapping = repairing([known])
        bootstrapping.staging = [:]
        bootstrapping.apply(additions: [entry(start: 2_000)], deletedIDs: [], nextAnchor: Data([1]))
        XCTAssertNil(bootstrapping.repairProgress)
        var draining = repairing([known])
        draining.staging = [:]
        draining.apply(additions: [], deletedIDs: [], nextAnchor: Data([1]))
        XCTAssertNil(draining.repairProgress, "Even the empty page that ends a bootstrap drops progress")
        XCTAssertTrue(draining.bootstrapComplete)

        var caughtUp = repairing([known])
        let before = caughtUp.repairProgress
        caughtUp.apply(additions: [], deletedIDs: [], nextAnchor: Data([1]))
        XCTAssertEqual(caughtUp.repairProgress, before, "An empty page after bootstrap touches nothing")
    }

    func testReopenClearsOnlyTheReopenedMonthsAndTheFinalLadder() {
        var progress = WorkoutJournalRepairProgress(context: "same")
        progress.completedMonths = ["2024:1", "2024:2", "2024:3"]
        progress.baselineInvalidated = true
        progress.detailsInvalidated = true
        progress.freshnessInvalidated = true
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        progress.beginMonthAttempt("2024:2", at: date)
        progress.beginMonthAttempt("2024:4", at: date)
        progress.beginFinalStepAttempt(at: date)
        progress.uncovered = ["id": DateInterval(start: date, duration: 60)]
        progress.reopen(months: ["2024:1", "2024:2", "2024:9"])
        XCTAssertEqual(progress.completedMonths, ["2024:3"])
        XCTAssertEqual(progress.monthAttempts.map { Set($0.keys) }, ["2024:4"])
        XCTAssertTrue(progress.mayAttemptMonth("2024:2", at: date), "A reopened month is eligible at once")
        XCTAssertFalse(progress.mayAttemptMonth("2024:4", at: date))
        XCTAssertNil(progress.finalAttempt, "A delta restarts the final step's ladder")
        XCTAssertTrue(progress.baselineInvalidated)
        XCTAssertTrue(progress.detailsInvalidated)
        XCTAssertEqual(progress.freshnessInvalidated, true)
        XCTAssertNotNil(progress.uncovered, "Only the details checkpoint consumes `uncovered`")
        progress.reopen(months: ["2024:4"])
        XCTAssertNil(progress.monthAttempts)
    }

    func testBuild5ProgressDecodesWithoutUncoveredAndCarriesItAfterADelta() throws {
        let json = #"{"context":"same","completedMonths":["2001:1"],"baselineInvalidated":true,"detailsInvalidated":true,"freshnessInvalidated":true,"finalAttempt":{"count":1,"startedAt":10}}"#
        let legacy = try JSONDecoder().decode(WorkoutJournalRepairProgress.self, from: Data(json.utf8))
        XCTAssertNil(legacy.uncovered)
        XCTAssertEqual(legacy.freshnessInvalidated, true)
        let workout = entry(start: 1_000)
        var value = repairing([workout])
        value.repairProgress = legacy
        value.apply(additions: [], deletedIDs: [workout.id], nextAnchor: Data([1]))
        let carried = try JSONDecoder().decode(WorkoutChangeJournal.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(carried.repairProgress?.uncovered, [workout.id.uuidString: interval(workout)],
                       "The mark is committed with the delta, so a build 5 progress cannot absorb it")
        XCTAssertEqual(carried.repairProgress?.completedMonths, ["2001:1"])
        XCTAssertNotNil(carried.repairProgress?.finalAttempt, "Only the next pass's reopening resets the ladder")
    }

    func testMonthExpansionKeepsPerIntervalAndAggregateBounds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        var keys: Set<BodyWorkoutMonthKey> = []
        XCTAssertTrue(WorkoutJournalRepairPlan.insertMonths(covering: DateInterval(start: start, end: end),
                                                            into: &keys, calendar: calendar))
        XCTAssertEqual(Set(keys.map(WorkoutJournalRepairPlan.identity)), ["2026:1", "2026:2", "2026:3"])
        let ancient = calendar.date(from: DateComponents(year: 1800, month: 1, day: 1))!
        var single: Set<BodyWorkoutMonthKey> = []
        XCTAssertFalse(WorkoutJournalRepairPlan.insertMonths(covering: DateInterval(start: ancient, end: end),
                                                             into: &single, calendar: calendar))
        var crowded = Set((0..<2_401).map { BodyWorkoutMonthKey(month: $0 % 12 + 1, year: 3000 + $0 / 12) })
        XCTAssertFalse(WorkoutJournalRepairPlan.insertMonths(covering: DateInterval(start: start, end: end),
                                                             into: &crowded, calendar: calendar),
                       "The aggregate bound still applies across a shared set")
    }
}
