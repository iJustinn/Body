//
//  WorkoutDetailSnapshotStoreTests.swift
//  BodyTests
//
//  Coverage for WorkoutDetailSnapshot's DTO round-trip and
//  WorkoutDetailSnapshotStore's save/load/prune/strip/delete behavior.
//

import XCTest
@testable import Body

final class WorkoutDetailSnapshotStoreTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutDetailSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
        directoryURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func makeRoute() -> WorkoutRoute {
        WorkoutRoute(
            coordinates: [
                RouteCoordinate(latitude: 37.7749, longitude: -122.4194, speed: 2.5, altitude: 12.3),
                RouteCoordinate(latitude: 37.7750, longitude: -122.4195, speed: 2.6, altitude: nil),
                RouteCoordinate(latitude: 37.7751, longitude: -122.4196, speed: 2.4, altitude: 12.9),
            ],
            locality: "San Francisco",
            elevationProfile: [
                WorkoutElevationSample(offset: 0, meters: 10.0),
                WorkoutElevationSample(offset: 60, meters: 14.5),
            ]
        )
    }

    private func makeMetricSeries() -> WorkoutMetricSeriesData {
        let nativeSeries = WorkoutMetricSeriesData.NativeSeries(
            buckets: [
                WorkoutMetricSeriesData.NativeBucket(index: 0, average: 1.1, minimum: 0.9, maximum: 1.3),
                WorkoutMetricSeriesData.NativeBucket(index: 1, average: 1.2, minimum: 1.0, maximum: 1.4),
            ],
            sessionAverage: 1.15,
            sessionMax: 1.4
        )
        return WorkoutMetricSeriesData(
            bucketSeconds: 30,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_001_800),
            bucketActiveSeconds: [0: 30.0, 1: 28.0, 2: 30.0],
            distanceMeters: [0: 50.0, 1: 105.0, 2: 160.0],
            steps: [0: 40.0, 1: 82.0, 2: 121.0],
            strideLengthMeters: nativeSeries,
            groundContactTimeMs: nativeSeries,
            verticalOscillationCm: nativeSeries,
            cyclingCadenceRPM: nativeSeries,
            hadReadFailure: false
        )
    }

    private func makeSnapshot(workoutID: UUID = UUID()) -> WorkoutDetailSnapshot {
        WorkoutDetailSnapshot(
            workoutID: workoutID,
            route: PersistedWorkoutRoute(model: makeRoute()),
            metricSeries: PersistedWorkoutMetricSeries(model: makeMetricSeries()),
            heartRateRecoveryBPM: 22.5
        )
    }

    // MARK: - Round-trip

    func testRoundTripPreservesAllFields() throws {
        let workoutID = UUID()
        let snapshot = makeSnapshot(workoutID: workoutID)

        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))

        let loaded = try XCTUnwrap(WorkoutDetailSnapshotStore.load(workoutID: workoutID, directoryURL: directoryURL))
        XCTAssertEqual(loaded, snapshot)

        let route = try XCTUnwrap(loaded.route).toModel()
        XCTAssertEqual(route, makeRoute())

        let series = try XCTUnwrap(loaded.metricSeries).toModel()
        let expectedSeries = makeMetricSeries()
        XCTAssertEqual(series.bucketSeconds, expectedSeries.bucketSeconds)
        XCTAssertEqual(series.startDate, expectedSeries.startDate)
        XCTAssertEqual(series.endDate, expectedSeries.endDate)
        XCTAssertEqual(series.bucketActiveSeconds, expectedSeries.bucketActiveSeconds)
        XCTAssertEqual(series.distanceMeters, expectedSeries.distanceMeters)
        XCTAssertEqual(series.steps, expectedSeries.steps)
        XCTAssertEqual(series.strideLengthMeters, expectedSeries.strideLengthMeters)
        XCTAssertEqual(series.groundContactTimeMs, expectedSeries.groundContactTimeMs)
        XCTAssertEqual(series.verticalOscillationCm, expectedSeries.verticalOscillationCm)
        XCTAssertEqual(series.cyclingCadenceRPM, expectedSeries.cyclingCadenceRPM)
        XCTAssertFalse(series.hadReadFailure)

        XCTAssertEqual(loaded.heartRateRecoveryBPM, 22.5)
    }

    // MARK: - Byte determinism

    func testEncodedBytesAreDeterministicAcrossSaves() throws {
        let workoutID = UUID()
        let snapshot = makeSnapshot(workoutID: workoutID)
        let fileURL = directoryURL.appendingPathComponent("\(workoutID.uuidString).json")

        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))
        let firstBytes = try Data(contentsOf: fileURL)

        try FileManager.default.removeItem(at: fileURL)
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))
        let secondBytes = try Data(contentsOf: fileURL)

        XCTAssertEqual(firstBytes, secondBytes)

        // Also verify determinism across independent directories, ruling out
        // any directory-specific state influencing the encode.
        let otherDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutDetailSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: otherDirectory) }

        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: otherDirectory))
        let thirdBytes = try Data(contentsOf: otherDirectory.appendingPathComponent("\(workoutID.uuidString).json"))
        XCTAssertEqual(firstBytes, thirdBytes)
    }

    // MARK: - Dedupe

    func testSaveDedupesIdenticalContentAndWritesOnChange() throws {
        let workoutID = UUID()
        let snapshot = makeSnapshot(workoutID: workoutID)

        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))
        XCTAssertFalse(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))

        var mutated = snapshot
        mutated.heartRateRecoveryBPM = 30.0
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(mutated, directoryURL: directoryURL))

        let loaded = try XCTUnwrap(WorkoutDetailSnapshotStore.load(workoutID: workoutID, directoryURL: directoryURL))
        XCTAssertEqual(loaded.heartRateRecoveryBPM, 30.0)
    }

    // MARK: - Schema / corrupt

    func testLoadReturnsNilForSchemaMismatchCorruptOrMissingFile() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let mismatchedID = UUID()
        let mismatchedURL = directoryURL.appendingPathComponent("\(mismatchedID.uuidString).json")
        let mismatchedJSON = """
        {"schemaVersion":999,"workoutID":"\(mismatchedID.uuidString)"}
        """
        try mismatchedJSON.data(using: .utf8)!.write(to: mismatchedURL)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: mismatchedID, directoryURL: directoryURL))

        let corruptID = UUID()
        let corruptURL = directoryURL.appendingPathComponent("\(corruptID.uuidString).json")
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: corruptURL)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: corruptID, directoryURL: directoryURL))

        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: UUID(), directoryURL: directoryURL))
    }

    // MARK: - Prune

    func testPruneKeepsOnlySpecifiedIDsAndRemovesNonUUIDFiles() throws {
        let keptID = UUID()
        let droppedIDA = UUID()
        let droppedIDB = UUID()

        XCTAssertTrue(WorkoutDetailSnapshotStore.save(makeSnapshot(workoutID: keptID), directoryURL: directoryURL))
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(makeSnapshot(workoutID: droppedIDA), directoryURL: directoryURL))
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(makeSnapshot(workoutID: droppedIDB), directoryURL: directoryURL))

        let strayURL = directoryURL.appendingPathComponent("not-a-uuid.json")
        try "{}".data(using: .utf8)!.write(to: strayURL)

        WorkoutDetailSnapshotStore.prune(keeping: [keptID], directoryURL: directoryURL)

        XCTAssertNotNil(WorkoutDetailSnapshotStore.load(workoutID: keptID, directoryURL: directoryURL))
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: droppedIDA, directoryURL: directoryURL))
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: droppedIDB, directoryURL: directoryURL))
        // A file whose name doesn't parse as a UUID is treated as not-kept and removed.
        XCTAssertFalse(FileManager.default.fileExists(atPath: strayURL.path))
    }

    // MARK: - Strips

    func testStripMetricSeriesRemovesOnlySeriesPayload() throws {
        let workoutID = UUID()
        let snapshot = makeSnapshot(workoutID: workoutID)
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))

        WorkoutDetailSnapshotStore.stripMetricSeries(directoryURL: directoryURL)

        let loaded = try XCTUnwrap(WorkoutDetailSnapshotStore.load(workoutID: workoutID, directoryURL: directoryURL))
        XCTAssertNotNil(loaded.route)
        XCTAssertNotNil(loaded.heartRateRecoveryBPM)
        XCTAssertNil(loaded.metricSeries)
    }

    func testStripHeartRateRecoveryRemovesOnlyHRRPayload() throws {
        let workoutID = UUID()
        let snapshot = makeSnapshot(workoutID: workoutID)
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))

        WorkoutDetailSnapshotStore.stripHeartRateRecovery(directoryURL: directoryURL)

        let loaded = try XCTUnwrap(WorkoutDetailSnapshotStore.load(workoutID: workoutID, directoryURL: directoryURL))
        XCTAssertNotNil(loaded.route)
        XCTAssertNotNil(loaded.metricSeries)
        XCTAssertNil(loaded.heartRateRecoveryBPM)
    }

    func testStripDeletesFileWhenStrippedFieldWasTheOnlyPayload() throws {
        let metricOnlyID = UUID()
        let metricOnlySnapshot = WorkoutDetailSnapshot(
            workoutID: metricOnlyID,
            route: nil,
            metricSeries: PersistedWorkoutMetricSeries(model: makeMetricSeries()),
            heartRateRecoveryBPM: nil
        )
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(metricOnlySnapshot, directoryURL: directoryURL))
        WorkoutDetailSnapshotStore.stripMetricSeries(directoryURL: directoryURL)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: metricOnlyID, directoryURL: directoryURL))

        let hrrOnlyID = UUID()
        let hrrOnlySnapshot = WorkoutDetailSnapshot(
            workoutID: hrrOnlyID,
            route: nil,
            metricSeries: nil,
            heartRateRecoveryBPM: 18.0
        )
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(hrrOnlySnapshot, directoryURL: directoryURL))
        WorkoutDetailSnapshotStore.stripHeartRateRecovery(directoryURL: directoryURL)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: hrrOnlyID, directoryURL: directoryURL))
    }

    // MARK: - deleteAll + totalDiskSizeBytes

    func testTotalDiskSizeAndDeleteAll() throws {
        let idA = UUID()
        let idB = UUID()

        XCTAssertTrue(WorkoutDetailSnapshotStore.save(makeSnapshot(workoutID: idA), directoryURL: directoryURL))
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(makeSnapshot(workoutID: idB), directoryURL: directoryURL))

        let sizeA = try Data(contentsOf: directoryURL.appendingPathComponent("\(idA.uuidString).json")).count
        let sizeB = try Data(contentsOf: directoryURL.appendingPathComponent("\(idB.uuidString).json")).count

        let totalSize = WorkoutDetailSnapshotStore.totalDiskSizeBytes(directoryURL: directoryURL)
        XCTAssertGreaterThan(totalSize, 0)
        XCTAssertEqual(totalSize, Int64(sizeA + sizeB))

        WorkoutDetailSnapshotStore.deleteAll(directoryURL: directoryURL)

        XCTAssertEqual(WorkoutDetailSnapshotStore.totalDiskSizeBytes(directoryURL: directoryURL), 0)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: idA, directoryURL: directoryURL))
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: idB, directoryURL: directoryURL))
    }
}
