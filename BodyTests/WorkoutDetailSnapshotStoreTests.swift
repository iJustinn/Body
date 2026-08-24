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
            powerWatts: nativeSeries,
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

    // MARK: - Split fixtures

    private let splitBase = Date(timeIntervalSince1970: 1_700_000_000)

    private func distanceSample(_ start: TimeInterval, _ end: TimeInterval, _ meters: Double) -> WorkoutDistanceSample {
        WorkoutDistanceSample(
            startDate: splitBase.addingTimeInterval(start),
            endDate: splitBase.addingTimeInterval(end),
            meters: meters
        )
    }

    private func stepSample(_ start: TimeInterval, _ end: TimeInterval, _ count: Double) -> WorkoutStepSample {
        WorkoutStepSample(
            startDate: splitBase.addingTimeInterval(start),
            endDate: splitBase.addingTimeInterval(end),
            count: count
        )
    }

    private func timeSegment(_ start: TimeInterval, _ end: TimeInterval) -> WorkoutTimeSegment {
        WorkoutTimeSegment(startDate: splitBase.addingTimeInterval(start), endDate: splitBase.addingTimeInterval(end))
    }

    private func makeSplitData() -> WorkoutSplitData {
        WorkoutSplitData(
            distanceSamples: [
                distanceSample(0, 10, 30),
                distanceSample(10, 20, 30),
                distanceSample(20, 30, 30),
            ],
            segments: [timeSegment(0, 30)],
            stepSamples: [
                stepSample(0, 10, 15),
                stepSample(10, 20, 15),
                stepSample(20, 30, 15),
            ]
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
        XCTAssertEqual(series.powerWatts, expectedSeries.powerWatts)
        XCTAssertFalse(series.hadReadFailure)
        XCTAssertEqual(
            try XCTUnwrap(loaded.metricSeries).seriesVersion,
            PersistedWorkoutMetricSeries.currentSeriesVersion
        )
        XCTAssertEqual(PersistedWorkoutMetricSeries.currentSeriesVersion, 2)

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

    /// A pre-power (v1) payload predates `seriesVersion`, so it decodes with nil —
    /// the store's seed gate compares against `currentSeriesVersion` and re-reads
    /// such a bundle live instead of pinning an incomplete one.
    func testLegacyMetricSeriesPayloadDecodesWithoutSeriesVersion() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let workoutID = UUID()
        let fileURL = directoryURL.appendingPathComponent("\(workoutID.uuidString).json")
        let legacyJSON = """
        {"schemaVersion":1,"workoutID":"\(workoutID.uuidString)","metricSeries":{"bucketSeconds":30,"startDate":0,"endDate":1800,"bucketActiveSeconds":{"0":30},"distanceMeters":{"0":50},"steps":{"0":40},"cyclingCadenceRPM":{"buckets":[{"index":0,"average":80,"minimum":70,"maximum":90}],"sessionAverage":80,"sessionMax":90}}}
        """
        try legacyJSON.data(using: .utf8)!.write(to: fileURL)

        let loaded = try XCTUnwrap(WorkoutDetailSnapshotStore.load(workoutID: workoutID, directoryURL: directoryURL))
        let series = try XCTUnwrap(loaded.metricSeries)
        XCTAssertNil(series.seriesVersion)
        XCTAssertNotEqual(series.seriesVersion, PersistedWorkoutMetricSeries.currentSeriesVersion)
        XCTAssertNil(series.powerWatts)
        XCTAssertNotNil(series.cyclingCadenceRPM)
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

        WorkoutDetailSnapshotStore.stripWorkoutMetricsPayloads(directoryURL: directoryURL)

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
        WorkoutDetailSnapshotStore.stripWorkoutMetricsPayloads(directoryURL: directoryURL)
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

    // MARK: - Splits: round-trip

    func testSplitDataRoundTripPreservesAllSampleKinds() throws {
        let workoutID = UUID()
        let model = makeSplitData()
        let persisted = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: model))
        let snapshot = WorkoutDetailSnapshot(workoutID: workoutID, splitData: persisted)

        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))
        let loaded = try XCTUnwrap(WorkoutDetailSnapshotStore.load(workoutID: workoutID, directoryURL: directoryURL))
        XCTAssertEqual(loaded, snapshot)

        let loadedModel = try XCTUnwrap(loaded.splitData).toModel()
        XCTAssertEqual(loadedModel, model)
    }

    // MARK: - Splits: downsampler

    func testDownsamplerReducesCountPreservesTotalsAndOrder() throws {
        let count = 5_000
        let distances = (0..<count).map { distanceSample(Double($0), Double($0 + 1), 3.0) }
        let steps = (0..<count).map { stepSample(Double($0), Double($0 + 1), 2.0) }
        let model = WorkoutSplitData(distanceSamples: distances, segments: [], stepSamples: steps)

        let persisted = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: model))

        XCTAssertLessThanOrEqual(persisted.distanceSamples.count, 1_000)
        XCTAssertGreaterThan(persisted.distanceSamples.count, 0)
        XCTAssertEqual(
            persisted.distanceSamples.reduce(0.0) { $0 + $1.meters },
            distances.reduce(0.0) { $0 + $1.meters }
        )
        XCTAssertEqual(
            persisted.stepSamples.reduce(0.0) { $0 + $1.count },
            steps.reduce(0.0) { $0 + $1.count }
        )

        var previousEnd = Date.distantPast
        for sample in persisted.distanceSamples {
            XCTAssertGreaterThanOrEqual(sample.startDate, previousEnd)
            XCTAssertLessThanOrEqual(sample.meters, 50.0)
            XCTAssertLessThanOrEqual(sample.endDate.timeIntervalSince(sample.startDate), 120.0)
            previousEnd = sample.endDate
        }
    }

    func testDownsamplerBreaksRunsAcrossGapsOver15Seconds() throws {
        let firstHalf = (0..<600).map { distanceSample(Double($0), Double($0 + 1), 3.0) }
        let secondHalf = (0..<600).map { distanceSample(620 + Double($0), 620 + Double($0 + 1), 3.0) }
        let model = WorkoutSplitData(distanceSamples: firstHalf + secondHalf, segments: [], stepSamples: [])

        let persisted = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: model))

        for sample in persisted.distanceSamples {
            let start = sample.startDate.timeIntervalSince(splitBase)
            let end = sample.endDate.timeIntervalSince(splitBase)
            XCTAssertFalse(start < 600 && end > 620, "merged sample \(start)-\(end) spans the 20s gap")
        }
    }

    func testDownsamplerBreaksRunsWhenAccumulatedGapExceeds30Seconds() throws {
        let count = 5_000
        let distances = (0..<count).map { i -> WorkoutDistanceSample in
            let start = Double(i) * 11
            return distanceSample(start, start + 1, 3.0)
        }
        let model = WorkoutSplitData(distanceSamples: distances, segments: [], stepSamples: [])

        let persisted = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: model))

        for sample in persisted.distanceSamples {
            let span = sample.endDate.timeIntervalSince(sample.startDate)
            // Each original sample covers exactly 1s of active time per 3m, so the
            // merged sample's internal gap is whatever span isn't accounted for by
            // the active seconds its summed meters imply.
            let activeSeconds = sample.meters / 3.0
            let internalGap = span - activeSeconds
            XCTAssertLessThanOrEqual(internalGap, 30.0 + 0.001)
        }
    }

    func testDownsamplerNeverMergesAcrossSegmentBoundaries() throws {
        let count = 3_000
        let distances = (0..<count).map { distanceSample(Double($0), Double($0 + 1), 3.0) }
        let segments = [timeSegment(777, 1_533)]
        let model = WorkoutSplitData(distanceSamples: distances, segments: segments, stepSamples: [])

        let persisted = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: model))

        XCTAssertEqual(persisted.segments.map { $0.toModel() }, segments)

        let boundaries: [TimeInterval] = [777, 1_533]
        for sample in persisted.distanceSamples {
            let start = sample.startDate.timeIntervalSince(splitBase)
            let end = sample.endDate.timeIntervalSince(splitBase)
            for boundary in boundaries {
                XCTAssertFalse(start < boundary && boundary < end, "sample \(start)-\(end) straddles boundary \(boundary)")
            }
        }
    }

    func testDownsamplerReturnsNilPastHardCapOrWhenEmpty() throws {
        // 2,000 samples each separated by a 20s gap: the gap rule forbids merging
        // any of them, so the output count matches the input count and blows past
        // the 1,500 hard cap.
        let distances = (0..<2_000).map { i -> WorkoutDistanceSample in
            let start = Double(i) * 21
            return distanceSample(start, start + 1, 3.0)
        }
        let model = WorkoutSplitData(distanceSamples: distances, segments: [], stepSamples: [])
        XCTAssertNil(PersistedWorkoutSplitData.downsampled(from: model))

        let empty = WorkoutSplitData(distanceSamples: [], segments: [], stepSamples: [stepSample(0, 1, 1)])
        XCTAssertNil(PersistedWorkoutSplitData.downsampled(from: empty))
    }

    func testDownsamplerPassesThroughSmallInputUnchanged() throws {
        let distances = (0..<50).map { distanceSample(Double($0) * 2, Double($0) * 2 + 1, 5.0) }
        let steps = (0..<50).map { stepSample(Double($0) * 2, Double($0) * 2 + 1, 3.0) }
        let model = WorkoutSplitData(distanceSamples: distances, segments: [], stepSamples: steps)

        let persisted = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: model))

        XCTAssertEqual(persisted.distanceSamples.count, 50)
        XCTAssertEqual(persisted.distanceSamples.map { $0.toModel() }, distances)
        XCTAssertEqual(persisted.stepSamples.count, 50)
        XCTAssertEqual(persisted.stepSamples.map { $0.toModel() }, steps)
    }

    // MARK: - Splits: fidelity regression

    func testDownsampledSplitsMatchOriginalWithinTolerance() throws {
        let sampleWidth = 0.4
        let sampleMeters = 4.0
        let count = 2_500
        let distances = (0..<count).map { i -> WorkoutDistanceSample in
            let start = Double(i) * sampleWidth
            return distanceSample(start, start + sampleWidth, sampleMeters)
        }
        let workoutStart = splitBase
        let workoutEnd = splitBase.addingTimeInterval(Double(count) * sampleWidth)
        let model = WorkoutSplitData(distanceSamples: distances, segments: [], stepSamples: [])

        let persisted = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: model))
        let downsampledModel = persisted.toModel()

        let originalSplits = WorkoutSplitCalculator.splits(
            samples: distances,
            unitMeters: 1_000,
            workoutStart: workoutStart,
            workoutEnd: workoutEnd
        )
        let downsampledSplits = WorkoutSplitCalculator.splits(
            samples: downsampledModel.distanceSamples,
            unitMeters: 1_000,
            workoutStart: workoutStart,
            workoutEnd: workoutEnd
        )

        XCTAssertEqual(originalSplits.count, downsampledSplits.count)
        XCTAssertEqual(
            originalSplits.reduce(0.0) { $0 + $1.distanceMeters },
            downsampledSplits.reduce(0.0) { $0 + $1.distanceMeters },
            accuracy: 0.001
        )
        for (original, downsampled) in zip(originalSplits, downsampledSplits) {
            XCTAssertEqual(original.durationSeconds, downsampled.durationSeconds, accuracy: 5.0)
        }
    }

    // MARK: - Splits: strip

    func testStripWorkoutMetricsPayloadsAlsoRemovesSplitData() throws {
        let workoutID = UUID()
        let splitData = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: makeSplitData()))
        let snapshot = WorkoutDetailSnapshot(
            workoutID: workoutID,
            route: PersistedWorkoutRoute(model: makeRoute()),
            splitData: splitData,
            metricSeries: PersistedWorkoutMetricSeries(model: makeMetricSeries()),
            heartRateRecoveryBPM: 22.5
        )
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(snapshot, directoryURL: directoryURL))

        WorkoutDetailSnapshotStore.stripWorkoutMetricsPayloads(directoryURL: directoryURL)

        let loaded = try XCTUnwrap(WorkoutDetailSnapshotStore.load(workoutID: workoutID, directoryURL: directoryURL))
        XCTAssertNotNil(loaded.route)
        XCTAssertNotNil(loaded.heartRateRecoveryBPM)
        XCTAssertNil(loaded.metricSeries)
        XCTAssertNil(loaded.splitData)
    }

    func testStripDeletesFileWhenSplitDataWasTheOnlyPayload() throws {
        let splitOnlyID = UUID()
        let splitData = try XCTUnwrap(PersistedWorkoutSplitData.downsampled(from: makeSplitData()))
        let splitOnlySnapshot = WorkoutDetailSnapshot(
            workoutID: splitOnlyID,
            route: nil,
            splitData: splitData,
            metricSeries: nil,
            heartRateRecoveryBPM: nil
        )
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(splitOnlySnapshot, directoryURL: directoryURL))
        WorkoutDetailSnapshotStore.stripWorkoutMetricsPayloads(directoryURL: directoryURL)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: splitOnlyID, directoryURL: directoryURL))
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
