//
//  WorkoutSnapshotStoreMonthFilesTests.swift
//  BodyTests
//
//  Month-keyed workout snapshot storage: `YYYY-MM.json` files in the
//  `WorkoutMonthSnapshots` directory, the legacy two-file fallback that keeps
//  widgets alive between an app update and the first refresh, and the window
//  maintenance (load / prune / map / delete) built on top.
//
//  Every case injects a scratch container directory, so the tests never touch
//  the real App Group.
//

import XCTest
@testable import Body

final class WorkoutSnapshotStoreMonthFilesTests: XCTestCase {
    /// Mirrors the production layout: the month directory sits inside a
    /// container that also holds the legacy pair.
    private func makeContainer() throws -> (containerURL: URL, directoryURL: URL) {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: containerURL)
        }
        return (
            containerURL,
            containerURL.appendingPathComponent(WorkoutSnapshotStore.monthSnapshotsDirectoryName, isDirectory: true)
        )
    }

    private func makeSnapshot(month: Int, year: Int, workoutDay: Int? = nil) throws -> WorkoutMonthSnapshot {
        var workouts: [WorkoutSummary] = []
        if let workoutDay {
            let start = try XCTUnwrap(Calendar.bodyGregorian.date(
                from: DateComponents(year: year, month: month, day: workoutDay, hour: 9)
            ))
            workouts = [
                WorkoutSummary(
                    id: UUID(),
                    type: .running,
                    startDate: start,
                    duration: 1_800,
                    activeEnergyKilocalories: 200,
                    distanceMeters: 3_000,
                    sourceName: "Test"
                )
            ]
        }
        return WorkoutMonthSnapshot.make(month: month, year: year, workouts: workouts, calendar: .bodyGregorian)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private func legacyURL(current: Bool, containerURL: URL) -> URL {
        containerURL.appendingPathComponent(
            current
                ? WorkoutSnapshotStore.currentMonthSnapshotFileName
                : WorkoutSnapshotStore.previousMonthSnapshotFileName
        )
    }

    // MARK: - File naming

    func testMonthFileNameIsZeroPaddedYearAndMonth() throws {
        let (_, directoryURL) = try makeContainer()

        let url = try XCTUnwrap(WorkoutSnapshotStore.fileURL(month: 3, year: 2026, directoryURL: directoryURL))

        XCTAssertEqual(url.lastPathComponent, "2026-03.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, WorkoutSnapshotStore.monthSnapshotsDirectoryName)
    }

    func testMonthKeyParsesOnlyWellFormedFileNames() {
        XCTAssertEqual(WorkoutSnapshotStore.monthKey(fromFileName: "2026-03.json")?.month, 3)
        XCTAssertEqual(WorkoutSnapshotStore.monthKey(fromFileName: "2026-03.json")?.year, 2026)
        XCTAssertNil(WorkoutSnapshotStore.monthKey(fromFileName: "2026-3.json"))
        XCTAssertNil(WorkoutSnapshotStore.monthKey(fromFileName: "2026-13.json"))
        XCTAssertNil(WorkoutSnapshotStore.monthKey(fromFileName: "currentMonthWorkoutSnapshot.json"))
        XCTAssertNil(WorkoutSnapshotStore.monthKey(fromFileName: "2026-03"))
    }

    func testSaveAndLoadRoundTripsThroughTheMonthFile() throws {
        let (_, directoryURL) = try makeContainer()
        let snapshot = try makeSnapshot(month: 5, year: 2026, workoutDay: 11)

        XCTAssertTrue(WorkoutSnapshotStore.save(
            snapshot,
            fileURL: WorkoutSnapshotStore.fileURL(month: 5, year: 2026, directoryURL: directoryURL)
        ))

        XCTAssertEqual(WorkoutSnapshotStore.load(month: 5, year: 2026, directoryURL: directoryURL), snapshot)
        XCTAssertNil(WorkoutSnapshotStore.load(month: 4, year: 2026, directoryURL: directoryURL))
    }

    // MARK: - Legacy fallback

    func testLoadFallsBackToLegacyCurrentFileWhenMonthMatches() throws {
        let (containerURL, directoryURL) = try makeContainer()
        let snapshot = try makeSnapshot(month: 5, year: 2026, workoutDay: 11)

        WorkoutSnapshotStore.save(snapshot, fileURL: legacyURL(current: true, containerURL: containerURL))

        XCTAssertEqual(WorkoutSnapshotStore.load(month: 5, year: 2026, directoryURL: directoryURL), snapshot)
    }

    func testLoadFallsBackToLegacyPreviousFileWhenMonthMatches() throws {
        let (containerURL, directoryURL) = try makeContainer()
        let snapshot = try makeSnapshot(month: 4, year: 2026, workoutDay: 3)

        WorkoutSnapshotStore.save(snapshot, fileURL: legacyURL(current: false, containerURL: containerURL))

        XCTAssertEqual(WorkoutSnapshotStore.load(month: 4, year: 2026, directoryURL: directoryURL), snapshot)
    }

    func testLoadPicksTheMatchingLegacyFileWhenBothArePresent() throws {
        let (containerURL, directoryURL) = try makeContainer()
        let current = try makeSnapshot(month: 5, year: 2026, workoutDay: 11)
        let previous = try makeSnapshot(month: 4, year: 2026, workoutDay: 3)

        WorkoutSnapshotStore.save(current, fileURL: legacyURL(current: true, containerURL: containerURL))
        WorkoutSnapshotStore.save(previous, fileURL: legacyURL(current: false, containerURL: containerURL))

        XCTAssertEqual(WorkoutSnapshotStore.load(month: 5, year: 2026, directoryURL: directoryURL), current)
        XCTAssertEqual(WorkoutSnapshotStore.load(month: 4, year: 2026, directoryURL: directoryURL), previous)
    }

    func testLoadReturnsNilWhenNoLegacyFileMatchesTheRequestedMonth() throws {
        let (containerURL, directoryURL) = try makeContainer()

        WorkoutSnapshotStore.save(
            try makeSnapshot(month: 5, year: 2026, workoutDay: 11),
            fileURL: legacyURL(current: true, containerURL: containerURL)
        )

        XCTAssertNil(WorkoutSnapshotStore.load(month: 3, year: 2026, directoryURL: directoryURL))
        XCTAssertNil(WorkoutSnapshotStore.load(month: 5, year: 2025, directoryURL: directoryURL))
    }

    func testLoadReturnsNilWithNoMonthFileAndNoLegacyFiles() throws {
        let (_, directoryURL) = try makeContainer()

        XCTAssertNil(WorkoutSnapshotStore.load(month: 5, year: 2026, directoryURL: directoryURL))
    }

    func testMonthFileWinsOverAStaleLegacyFileForTheSameMonth() throws {
        let (containerURL, directoryURL) = try makeContainer()
        let stale = try makeSnapshot(month: 5, year: 2026)
        let fresh = try makeSnapshot(month: 5, year: 2026, workoutDay: 11)

        WorkoutSnapshotStore.save(stale, fileURL: legacyURL(current: true, containerURL: containerURL))
        WorkoutSnapshotStore.save(
            fresh,
            fileURL: WorkoutSnapshotStore.fileURL(month: 5, year: 2026, directoryURL: directoryURL)
        )

        XCTAssertEqual(WorkoutSnapshotStore.load(month: 5, year: 2026, directoryURL: directoryURL), fresh)
    }

    // MARK: - Window

    private func writeMonths(_ keys: [(month: Int, year: Int)], directoryURL: URL) throws {
        for key in keys {
            WorkoutSnapshotStore.save(
                try makeSnapshot(month: key.month, year: key.year, workoutDay: 1),
                fileURL: WorkoutSnapshotStore.fileURL(month: key.month, year: key.year, directoryURL: directoryURL)
            )
        }
    }

    /// March 2026 back through October 2025 is the window; September 2025 is not.
    private let windowMonths: [(month: Int, year: Int)] = [
        (3, 2026), (2, 2026), (1, 2026), (12, 2025), (11, 2025), (10, 2025)
    ]

    func testLoadPersistedMonthsReturnsWindowMonthsNewestFirst() throws {
        let (_, directoryURL) = try makeContainer()
        try writeMonths(windowMonths + [(9, 2025)], directoryURL: directoryURL)

        let loaded = WorkoutSnapshotStore.loadPersistedMonths(
            now: try date(2026, 3, 15),
            directoryURL: directoryURL
        )

        XCTAssertEqual(loaded.count, WorkoutSnapshotStore.persistedMonthCount)
        XCTAssertEqual(loaded.map(\.month), windowMonths.map(\.month))
        XCTAssertEqual(loaded.map(\.year), windowMonths.map(\.year))
    }

    func testLoadPersistedMonthsSkipsMonthsWithNoFile() throws {
        let (_, directoryURL) = try makeContainer()
        try writeMonths([(3, 2026), (12, 2025)], directoryURL: directoryURL)

        let loaded = WorkoutSnapshotStore.loadPersistedMonths(
            now: try date(2026, 3, 15),
            directoryURL: directoryURL
        )

        XCTAssertEqual(loaded.map(\.month), [3, 12])
    }

    func testLoadPersistedMonthsUsesTheLegacyFallbackForAnUnwrittenMonth() throws {
        let (containerURL, directoryURL) = try makeContainer()
        let legacy = try makeSnapshot(month: 2, year: 2026, workoutDay: 4)
        WorkoutSnapshotStore.save(legacy, fileURL: legacyURL(current: true, containerURL: containerURL))

        let loaded = WorkoutSnapshotStore.loadPersistedMonths(
            now: try date(2026, 3, 15),
            directoryURL: directoryURL
        )

        XCTAssertEqual(loaded, [legacy])
    }

    func testPruneOutsideWindowKeepsInWindowFilesAndDropsTheRest() throws {
        let (_, directoryURL) = try makeContainer()
        try writeMonths(windowMonths + [(9, 2025), (4, 2026)], directoryURL: directoryURL)
        let strayURL = directoryURL.appendingPathComponent("notAMonth.json")
        try Data("{}".utf8).write(to: strayURL)

        WorkoutSnapshotStore.pruneOutsideWindow(now: try date(2026, 3, 15), directoryURL: directoryURL)

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path))
        XCTAssertEqual(remaining, Set(["2026-03.json", "2026-02.json", "2026-01.json", "2025-12.json", "2025-11.json", "2025-10.json"]))
    }

    func testPruneOutsideWindowLeavesLegacyFilesAlone() throws {
        let (containerURL, directoryURL) = try makeContainer()
        let legacyCurrentURL = legacyURL(current: true, containerURL: containerURL)
        WorkoutSnapshotStore.save(try makeSnapshot(month: 3, year: 2026), fileURL: legacyCurrentURL)
        try writeMonths([(3, 2026)], directoryURL: directoryURL)

        WorkoutSnapshotStore.pruneOutsideWindow(now: try date(2026, 3, 15), directoryURL: directoryURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyCurrentURL.path))
    }

    // MARK: - Map, delete, size

    func testMapPersistedMonthsRewritesEveryMonthFileAndReportsChangedBytes() throws {
        let (_, directoryURL) = try makeContainer()
        try writeMonths([(3, 2026), (2, 2026)], directoryURL: directoryURL)

        let changed = WorkoutSnapshotStore.mapPersistedMonths(directoryURL: directoryURL) { snapshot in
            WorkoutMonthSnapshot.make(
                month: snapshot.month,
                year: snapshot.year,
                workouts: [],
                calendar: .bodyGregorian,
                generatedAt: snapshot.generatedAt
            )
        }

        XCTAssertTrue(changed)
        XCTAssertEqual(WorkoutSnapshotStore.load(month: 3, year: 2026, directoryURL: directoryURL)?.workoutCount, 0)
        XCTAssertEqual(WorkoutSnapshotStore.load(month: 2, year: 2026, directoryURL: directoryURL)?.workoutCount, 0)
    }

    func testMapPersistedMonthsReportsNoChangeWhenTheTransformIsIdentity() throws {
        let (_, directoryURL) = try makeContainer()
        try writeMonths([(3, 2026)], directoryURL: directoryURL)

        XCTAssertFalse(WorkoutSnapshotStore.mapPersistedMonths(directoryURL: directoryURL) { $0 })
    }

    func testDeleteLegacyFilesRemovesOnlyTheLegacyPair() throws {
        let (containerURL, directoryURL) = try makeContainer()
        WorkoutSnapshotStore.save(try makeSnapshot(month: 3, year: 2026), fileURL: legacyURL(current: true, containerURL: containerURL))
        WorkoutSnapshotStore.save(try makeSnapshot(month: 2, year: 2026), fileURL: legacyURL(current: false, containerURL: containerURL))
        try writeMonths([(3, 2026)], directoryURL: directoryURL)

        WorkoutSnapshotStore.deleteLegacyFiles(directoryURL: directoryURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(current: true, containerURL: containerURL).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(current: false, containerURL: containerURL).path))
        XCTAssertNotNil(WorkoutSnapshotStore.load(month: 3, year: 2026, directoryURL: directoryURL))
    }

    func testDeleteAllRemovesTheDirectoryAndTheLegacyFiles() throws {
        let (containerURL, directoryURL) = try makeContainer()
        WorkoutSnapshotStore.save(try makeSnapshot(month: 3, year: 2026), fileURL: legacyURL(current: true, containerURL: containerURL))
        try writeMonths(windowMonths, directoryURL: directoryURL)

        WorkoutSnapshotStore.deleteAll(directoryURL: directoryURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(current: true, containerURL: containerURL).path))
        XCTAssertNil(WorkoutSnapshotStore.load(month: 3, year: 2026, directoryURL: directoryURL))
        XCTAssertEqual(WorkoutSnapshotStore.diskSizeBytes(directoryURL: directoryURL), 0)
    }

    func testDiskSizeCountsMonthFilesAndAnyLegacyFileStillPresent() throws {
        let (containerURL, directoryURL) = try makeContainer()
        try writeMonths([(3, 2026), (2, 2026)], directoryURL: directoryURL)

        let monthsOnly = WorkoutSnapshotStore.diskSizeBytes(directoryURL: directoryURL)
        XCTAssertGreaterThan(monthsOnly, 0)

        let legacyFileURL = legacyURL(current: true, containerURL: containerURL)
        WorkoutSnapshotStore.save(try makeSnapshot(month: 1, year: 2026, workoutDay: 2), fileURL: legacyFileURL)

        XCTAssertEqual(
            WorkoutSnapshotStore.diskSizeBytes(directoryURL: directoryURL),
            monthsOnly + WorkoutSnapshotStore.fileSize(at: legacyFileURL)
        )
    }

    func testDeleteEvictsTheMemoizedSnapshotForThatFile() throws {
        let (_, directoryURL) = try makeContainer()
        let fileURL = try XCTUnwrap(WorkoutSnapshotStore.fileURL(month: 3, year: 2026, directoryURL: directoryURL))
        WorkoutSnapshotStore.save(try makeSnapshot(month: 3, year: 2026, workoutDay: 1), fileURL: fileURL)
        XCTAssertNotNil(WorkoutSnapshotStore.load(fileURL: fileURL))

        WorkoutSnapshotStore.delete(fileURL: fileURL)

        XCTAssertNil(WorkoutSnapshotStore.load(fileURL: fileURL))
        // A later save at the same URL must serve the new content, not the
        // snapshot memoized before the delete.
        let replacement = try makeSnapshot(month: 3, year: 2026)
        WorkoutSnapshotStore.save(replacement, fileURL: fileURL)
        XCTAssertEqual(WorkoutSnapshotStore.load(fileURL: fileURL)?.workoutCount, 0)
    }
}
