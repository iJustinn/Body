//
//  HealthKitWorkoutStoreObservationTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

/// `monthSnapshotsGeneration` is the memo key `BodyHealthMetricDetailView`'s cached
/// workout index is built on, and nothing else reads it. If a `monthSnapshots` write
/// ever stops bumping it, that memo freezes on the first month it saw while the rest of
/// the app moves on — and the whole suite stays green, because no other test observes
/// the counter. These two cases are that observation.
///
/// Under `@Observable` the counter can no longer ride a `didSet`: the macro rewrites the
/// property the observer would hang off. So every write goes through `setMonthSnapshots`
/// or `mutateMonthSnapshots`, and the pair below checks both halves of that: the
/// behavioural case exercises the whole-dictionary setter end to end, and the source
/// case pins that no fourth write path exists, since the subscript and `removeValue`
/// writers sit behind `HealthKitFetchEngine.fetchWorkouts`, which resolves its query
/// through `execute` and so cannot be driven by `FakeHealthStore`.
final class HealthKitWorkoutStoreObservationTests: XCTestCase {

    /// Clear Cache is the one `monthSnapshots` writer reachable without HealthKit: it
    /// replaces the whole dictionary with the current month's empty snapshot.
    @MainActor
    func testMonthSnapshotsGenerationAdvancesWhenTheDictionaryIsReplaced() async throws {
        // The clear's file path writes to the App Group container, which is unavailable
        // in this unsigned target; point it at a scratch directory.
        let snapshotDirectoryURL = temporaryMonthSnapshotDirectoryURL()
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = snapshotDirectoryURL
        addTeardownBlock {
            HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = nil
            try? FileManager.default.removeItem(at: snapshotDirectoryURL.deletingLastPathComponent())
        }

        let calendar = Calendar.bodyGregorian
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let month = try XCTUnwrap(components.month)
        let year = try XCTUnwrap(components.year)

        let workout = WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: now,
            duration: 1_800,
            activeEnergyKilocalories: 200,
            distanceMeters: 3_000,
            sourceName: "Tests"
        )
        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [WorkoutMonthSnapshot.make(
                month: month,
                year: year,
                workouts: [workout],
                calendar: calendar
            )],
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .defaultValue,
            engineHealthStore: FakeHealthStore()
        )

        let generationBeforeClear = store.monthSnapshotsGeneration
        await store.clearLocalCache(date: now)

        XCTAssertGreaterThan(
            store.monthSnapshotsGeneration,
            generationBeforeClear,
            "A monthSnapshots write has to move the memo key with it, or the derived workout index freezes."
        )
        XCTAssertEqual(store.monthSnapshots[BodyWorkoutMonthKey(month: month, year: year)]?.workoutCount, 0)
    }

    /// The subscript and `removeValue` writers live behind a HealthKit fetch this target
    /// cannot drive, so they are pinned here instead: `monthSnapshots` must be written
    /// only by the two helpers that bump the counter, plus the one direct assignment in
    /// `init` (a method call is illegal before every stored property is initialized, and
    /// an initial value has no memo to invalidate).
    func testEveryMonthSnapshotsWriteGoesThroughAGenerationBumpingHelper() throws {
        let storeSource = try BodyTestSupport.sourceText(at: "Body/Services/HealthKitWorkoutStore.swift")

        // The two helpers exist and each bumps the counter.
        for helper in [
            "private func setMonthSnapshots(_ snapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot]) {",
            "private func mutateMonthSnapshots(_ mutate: (inout [BodyWorkoutMonthKey: WorkoutMonthSnapshot]) -> Void) {"
        ] {
            let start = try XCTUnwrap(storeSource.range(of: helper)?.lowerBound)
            let block = String(storeSource[start...].prefix(220))
            XCTAssertTrue(
                block.contains("monthSnapshotsGeneration &+= 1"),
                "\(helper) must bump the generation."
            )
        }

        // `didSet` cannot carry the bump under `@Observable`, so it must not come back.
        XCTAssertFalse(storeSource.contains("didSet { monthSnapshotsGeneration"))

        // No write outside the helpers and the single `init` assignment.
        var directWrites: [String] = []
        for line in storeSource.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("monthSnapshots[")
                || trimmed.hasPrefix("self.monthSnapshots")
                || trimmed.hasPrefix("monthSnapshots.removeValue")
                || trimmed.hasPrefix("monthSnapshots.removeAll")
                || trimmed.hasPrefix("monthSnapshots.merge(")
                || trimmed.hasPrefix("monthSnapshots.updateValue(")
                || trimmed.hasPrefix("monthSnapshots = ") else {
                continue
            }
            // `setMonthSnapshots`' own assignment, which bumps the counter on the
            // next line, is the one write that is supposed to look like this.
            guard trimmed != "monthSnapshots = snapshots" else {
                continue
            }
            directWrites.append(trimmed)
        }
        XCTAssertEqual(
            directWrites.count,
            1,
            "Only `init` may write monthSnapshots directly; route new writes through setMonthSnapshots / mutateMonthSnapshots. Found: \(directWrites)"
        )
        XCTAssertEqual(directWrites.first, "monthSnapshots = [BodyWorkoutMonthKey: WorkoutMonthSnapshot](")
    }

    private func temporaryMonthSnapshotDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(WorkoutSnapshotStore.monthSnapshotsDirectoryName, isDirectory: true)
    }
}
