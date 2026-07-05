//
//  SnapshotStoreLoadCacheTests.swift
//  BodyTests
//
//  Exercises the in-process load memoization added to the snapshot stores.
//  The cache is keyed by file identity (mtime + size), so these tests use a
//  unique temp-file URL per test to keep the process-wide static cache from
//  bleeding between cases.
//

import XCTest
@testable import Body

final class SnapshotStoreLoadCacheTests: XCTestCase {
    private func uniqueFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("snapshot.json")
    }

    // MARK: - HealthWidgetSnapshotStore

    func testHealthWidgetLoadInvalidatesOnRewrite() throws {
        let fileURL = try uniqueFileURL()
        let snapshotA = HealthWidgetSnapshot.empty
        let snapshotB = HealthWidgetSnapshot.placeholder

        HealthWidgetSnapshotStore.save(snapshotA, fileURL: fileURL)
        XCTAssertEqual(HealthWidgetSnapshotStore.load(fileURL: fileURL), snapshotA)

        HealthWidgetSnapshotStore.save(snapshotB, fileURL: fileURL)
        XCTAssertEqual(HealthWidgetSnapshotStore.load(fileURL: fileURL), snapshotB)
    }

    func testHealthWidgetRepeatedLoadReturnsEqualResult() throws {
        let fileURL = try uniqueFileURL()
        let snapshot = HealthWidgetSnapshot.placeholder

        HealthWidgetSnapshotStore.save(snapshot, fileURL: fileURL)

        let first = HealthWidgetSnapshotStore.load(fileURL: fileURL)
        let second = HealthWidgetSnapshotStore.load(fileURL: fileURL)

        XCTAssertEqual(first, snapshot)
        XCTAssertEqual(first, second)
    }

    func testHealthWidgetLoadReturnsNilAfterDelete() throws {
        let fileURL = try uniqueFileURL()

        HealthWidgetSnapshotStore.save(.placeholder, fileURL: fileURL)
        XCTAssertNotNil(HealthWidgetSnapshotStore.load(fileURL: fileURL))

        HealthWidgetSnapshotStore.delete(fileURL: fileURL)
        XCTAssertNil(HealthWidgetSnapshotStore.load(fileURL: fileURL))
    }

    func testHealthWidgetLoadReturnsNilForGarbageBytesRepeatedly() throws {
        let fileURL = try uniqueFileURL()

        HealthWidgetSnapshotStore.save(.placeholder, fileURL: fileURL)
        XCTAssertNotNil(HealthWidgetSnapshotStore.load(fileURL: fileURL))

        try Data("not json at all".utf8).write(to: fileURL, options: [.atomic])

        XCTAssertNil(HealthWidgetSnapshotStore.load(fileURL: fileURL))
        XCTAssertNil(HealthWidgetSnapshotStore.load(fileURL: fileURL))
    }

    // MARK: - WorkoutSnapshotStore

    func testWorkoutLoadInvalidatesOnRewrite() throws {
        let fileURL = try uniqueFileURL()
        let snapshotA = WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)
        let snapshotB = WorkoutMonthSnapshot.make(month: 6, year: 2026, workouts: [], calendar: .bodyGregorian)

        WorkoutSnapshotStore.save(snapshotA, fileURL: fileURL)
        XCTAssertEqual(WorkoutSnapshotStore.load(fileURL: fileURL), snapshotA)

        WorkoutSnapshotStore.save(snapshotB, fileURL: fileURL)
        XCTAssertEqual(WorkoutSnapshotStore.load(fileURL: fileURL), snapshotB)
    }

    func testWorkoutRepeatedLoadReturnsEqualResult() throws {
        let fileURL = try uniqueFileURL()
        let snapshot = WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)

        WorkoutSnapshotStore.save(snapshot, fileURL: fileURL)

        let first = WorkoutSnapshotStore.load(fileURL: fileURL)
        let second = WorkoutSnapshotStore.load(fileURL: fileURL)

        XCTAssertEqual(first, snapshot)
        XCTAssertEqual(first, second)
    }

    func testWorkoutLoadReturnsNilAfterDelete() throws {
        let fileURL = try uniqueFileURL()
        let snapshot = WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)

        WorkoutSnapshotStore.save(snapshot, fileURL: fileURL)
        XCTAssertNotNil(WorkoutSnapshotStore.load(fileURL: fileURL))

        WorkoutSnapshotStore.delete(fileURL: fileURL)
        XCTAssertNil(WorkoutSnapshotStore.load(fileURL: fileURL))
    }

    func testWorkoutLoadReturnsNilForGarbageBytesRepeatedly() throws {
        let fileURL = try uniqueFileURL()
        let snapshot = WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)

        WorkoutSnapshotStore.save(snapshot, fileURL: fileURL)
        XCTAssertNotNil(WorkoutSnapshotStore.load(fileURL: fileURL))

        try Data("not json at all".utf8).write(to: fileURL, options: [.atomic])

        XCTAssertNil(WorkoutSnapshotStore.load(fileURL: fileURL))
        XCTAssertNil(WorkoutSnapshotStore.load(fileURL: fileURL))
    }
}
