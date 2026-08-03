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

    func testWorkoutLoadOrEmptyReturnsHonestEmptySnapshotWhenFileAbsent() throws {
        let fileURL = try uniqueFileURL()

        let result = WorkoutSnapshotStore.loadOrEmpty(fileURL: fileURL)

        XCTAssertEqual(result.workoutCount, 0)
        XCTAssertFalse(result.days.flatMap(\.workouts).contains { $0.sourceName == "Preview" })
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

    // MARK: - loadCurrentOrPreviousIfEmpty (M16: live timelines must never see fabricated data)

    func testLoadCurrentOrPreviousIfEmptyReturnsHonestEmptySnapshotWhenFilesAbsentLive() throws {
        let currentFileURL = try uniqueFileURL()
        let previousFileURL = try uniqueFileURL()
        let now = try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 7, day: 15)))

        let result = WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty(
            usePlaceholderWhenEmpty: false,
            now: now,
            currentFileURL: currentFileURL,
            previousFileURL: previousFileURL
        )

        XCTAssertEqual(result.workoutCount, 0)
        XCTAssertEqual(result.month, 7)
        XCTAssertEqual(result.year, 2026)
        XCTAssertNotEqual(result.workoutCount, WorkoutMonthSnapshot.placeholder.workoutCount)
    }

    func testLoadCurrentOrPreviousIfEmptyReturnsPlaceholderOnlyWhenExplicitlyRequestedForPreview() throws {
        let currentFileURL = try uniqueFileURL()
        let previousFileURL = try uniqueFileURL()

        let result = WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty(
            usePlaceholderWhenEmpty: true,
            currentFileURL: currentFileURL,
            previousFileURL: previousFileURL
        )

        XCTAssertEqual(result.workoutCount, WorkoutMonthSnapshot.placeholder.workoutCount)
        XCTAssertGreaterThan(result.workoutCount, 0)
    }

    private func makePopulatedMay2026Snapshot() throws -> WorkoutMonthSnapshot {
        WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [
                WorkoutSummary(
                    id: UUID(),
                    type: .running,
                    startDate: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 9))),
                    duration: 1_800,
                    activeEnergyKilocalories: 200,
                    distanceMeters: 3_000,
                    sourceName: "Test"
                )
            ],
            calendar: .bodyGregorian
        )
    }

    func testLoadCurrentOrPreviousIfEmptyLiveKeepsEmptyCurrentMonthInsteadOfPreviousFallback() throws {
        let currentFileURL = try uniqueFileURL()
        let previousFileURL = try uniqueFileURL()
        let now = try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 15)))

        let emptyCurrent = WorkoutMonthSnapshot.make(month: 6, year: 2026, workouts: [], calendar: .bodyGregorian)
        WorkoutSnapshotStore.save(emptyCurrent, fileURL: currentFileURL)
        WorkoutSnapshotStore.save(try makePopulatedMay2026Snapshot(), fileURL: previousFileURL)

        let result = WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty(
            usePlaceholderWhenEmpty: false,
            now: now,
            currentFileURL: currentFileURL,
            previousFileURL: previousFileURL
        )

        XCTAssertEqual(result, emptyCurrent)
    }

    func testLoadCurrentOrPreviousIfEmptyLiveReplacesStaleCurrentFileWithNewEmptyMonth() throws {
        let currentFileURL = try uniqueFileURL()
        let previousFileURL = try uniqueFileURL()
        let now = try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 0, minute: 5)))

        // The app hasn't refreshed since May: the on-disk "current" file still
        // holds last month's populated snapshot.
        WorkoutSnapshotStore.save(try makePopulatedMay2026Snapshot(), fileURL: currentFileURL)

        let result = WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty(
            usePlaceholderWhenEmpty: false,
            now: now,
            currentFileURL: currentFileURL,
            previousFileURL: previousFileURL
        )

        XCTAssertEqual(result.month, 6)
        XCTAssertEqual(result.year, 2026)
        XCTAssertEqual(result.workoutCount, 0)
    }

    func testLoadCurrentOrPreviousIfEmptyPreviewStillFallsBackToPreviousMonth() throws {
        let currentFileURL = try uniqueFileURL()
        let previousFileURL = try uniqueFileURL()
        let now = try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 15)))

        let emptyCurrent = WorkoutMonthSnapshot.make(month: 6, year: 2026, workouts: [], calendar: .bodyGregorian)
        let populatedPrevious = try makePopulatedMay2026Snapshot()
        WorkoutSnapshotStore.save(emptyCurrent, fileURL: currentFileURL)
        WorkoutSnapshotStore.save(populatedPrevious, fileURL: previousFileURL)

        let result = WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty(
            usePlaceholderWhenEmpty: true,
            now: now,
            currentFileURL: currentFileURL,
            previousFileURL: previousFileURL
        )

        XCTAssertEqual(result, populatedPrevious)
    }
}
