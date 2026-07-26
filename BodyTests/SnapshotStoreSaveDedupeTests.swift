//
//  SnapshotStoreSaveDedupeTests.swift
//  BodyTests
//
//  M10: `save` re-encodes the incoming snapshot with the on-disk timestamp
//  substituted in before deciding whether the content actually changed, so a
//  periodic re-save that only refreshes `generatedAt`/`generatedDate` skips
//  the write — preserving the on-disk timestamp, which doubles as a cache key
//  (BodyWorkoutsView search corpus, clear-cache dedupe rewrites).
//

import XCTest
@testable import Body

final class SnapshotStoreSaveDedupeTests: XCTestCase {
    private func uniqueFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("snapshot.json")
    }

    // MARK: - WorkoutSnapshotStore

    func testWorkoutSnapshotSaveSkipsWriteWhenOnlyGeneratedAtChanges() throws {
        let fileURL = try uniqueFileURL()
        let firstStamp = Date(timeIntervalSince1970: 1_700_000_000)
        let secondStamp = firstStamp.addingTimeInterval(3_600)

        let snapshotA = WorkoutMonthSnapshot.make(
            month: 5, year: 2026, workouts: [], calendar: .bodyGregorian, generatedAt: firstStamp
        )
        XCTAssertTrue(WorkoutSnapshotStore.save(snapshotA, fileURL: fileURL))

        let snapshotB = WorkoutMonthSnapshot.make(
            month: 5, year: 2026, workouts: [], calendar: .bodyGregorian, generatedAt: secondStamp
        )
        XCTAssertFalse(WorkoutSnapshotStore.save(snapshotB, fileURL: fileURL))

        let loaded = try XCTUnwrap(WorkoutSnapshotStore.load(fileURL: fileURL))
        XCTAssertEqual(loaded.generatedAt, firstStamp)
    }

    func testWorkoutSnapshotSaveWritesFreshStampWhenContentChanges() throws {
        let fileURL = try uniqueFileURL()
        let firstStamp = Date(timeIntervalSince1970: 1_700_000_000)
        let secondStamp = firstStamp.addingTimeInterval(3_600)

        let snapshotA = WorkoutMonthSnapshot.make(
            month: 5, year: 2026, workouts: [], calendar: .bodyGregorian, generatedAt: firstStamp
        )
        XCTAssertTrue(WorkoutSnapshotStore.save(snapshotA, fileURL: fileURL))

        let workout = WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 9))),
            duration: 1_800,
            activeEnergyKilocalories: 200,
            distanceMeters: 3_000,
            sourceName: "Test"
        )
        let snapshotB = WorkoutMonthSnapshot.make(
            month: 5, year: 2026, workouts: [workout], calendar: .bodyGregorian, generatedAt: secondStamp
        )
        XCTAssertTrue(WorkoutSnapshotStore.save(snapshotB, fileURL: fileURL))

        let loaded = try XCTUnwrap(WorkoutSnapshotStore.load(fileURL: fileURL))
        XCTAssertEqual(loaded.generatedAt, secondStamp)
        XCTAssertEqual(loaded.workoutCount, 1)
    }

    // MARK: - HealthWidgetSnapshotStore

    func testHealthWidgetSnapshotSaveSkipsWriteWhenOnlyGeneratedDateChanges() throws {
        let fileURL = try uniqueFileURL()
        let firstStamp = Date(timeIntervalSince1970: 1_700_000_000)
        let secondStamp = firstStamp.addingTimeInterval(3_600)

        let snapshotA = HealthWidgetSnapshot(generatedDate: firstStamp)
        XCTAssertTrue(HealthWidgetSnapshotStore.save(snapshotA, fileURL: fileURL))

        let snapshotB = HealthWidgetSnapshot(generatedDate: secondStamp)
        XCTAssertFalse(HealthWidgetSnapshotStore.save(snapshotB, fileURL: fileURL))

        let loaded = try XCTUnwrap(HealthWidgetSnapshotStore.load(fileURL: fileURL))
        XCTAssertEqual(loaded.generatedDate, firstStamp)
    }

    func testHealthWidgetSnapshotSaveWritesFreshStampWhenContentChanges() throws {
        let fileURL = try uniqueFileURL()
        let firstStamp = Date(timeIntervalSince1970: 1_700_000_000)
        let secondStamp = firstStamp.addingTimeInterval(3_600)

        let snapshotA = HealthWidgetSnapshot(generatedDate: firstStamp)
        XCTAssertTrue(HealthWidgetSnapshotStore.save(snapshotA, fileURL: fileURL))

        var snapshotB = HealthWidgetSnapshot.placeholder
        snapshotB.generatedDate = secondStamp
        XCTAssertTrue(HealthWidgetSnapshotStore.save(snapshotB, fileURL: fileURL))

        let loaded = try XCTUnwrap(HealthWidgetSnapshotStore.load(fileURL: fileURL))
        XCTAssertEqual(loaded.generatedDate, secondStamp)
        XCTAssertFalse(loaded.isEmpty)
    }
}
