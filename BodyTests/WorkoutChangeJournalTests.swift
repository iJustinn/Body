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
}
