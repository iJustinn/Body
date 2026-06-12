//
//  HealthDashboardDaySamplesTests.swift
//  BodyTests
//
//  Covers the day-sample sidecar split: the launch-critical main snapshot
//  file must stay free of intraday samples, while the sidecar round-trips
//  them and legacy combined files keep decoding.
//

import XCTest
@testable import Body

final class HealthDashboardDaySamplesTests: XCTestCase {
    private func temporarySnapshotFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests.\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(HealthDashboardSnapshotStore.healthDashboardSnapshotFileName)
    }

    private func makeSnapshot(
        heartRateDaySamples: HealthTrendSeries,
        stepsDaySamples: HealthTrendSeries = .empty
    ) throws -> HealthDashboardSnapshot {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9)))
        let trends = HealthTrendSnapshot(
            sleep: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 7)]),
            restingHeartRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 61)]),
            bodyMass: .empty,
            bodyFatPercentage: .empty,
            heartRateVariability: .empty,
            respiratoryRate: .empty,
            oxygenSaturation: .empty,
            bodyMassIndex: .empty,
            activeEnergy: .empty,
            restingEnergy: .empty,
            heartRateDaySamples: heartRateDaySamples,
            stepsDaySamples: stepsDaySamples
        )
        return HealthDashboardSnapshot(summary: .empty, trends: trends)
    }

    private func sampleSeries(count: Int, baseValue: Double) -> HealthTrendSeries {
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return HealthTrendSeries(
            points: (0..<count).map { offset in
                HealthTrendDataPoint(
                    date: base.addingTimeInterval(Double(offset) * 300),
                    value: baseValue + Double(offset % 9)
                )
            }
        )
    }

    func testSaveSplitsDaySamplesIntoSidecarAndLoadStaysSlim() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let fileURL = temporarySnapshotFileURL()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        let daySamples = sampleSeries(count: 48, baseValue: 70)
        let snapshot = try makeSnapshot(heartRateDaySamples: daySamples)

        XCTAssertTrue(HealthDashboardSnapshotStore.save(snapshot, defaults: defaults, fileURL: fileURL))

        let loaded = try XCTUnwrap(HealthDashboardSnapshotStore.load(defaults: defaults, fileURL: fileURL))
        XCTAssertEqual(loaded.trends.heartRateDaySamples, .empty)
        XCTAssertEqual(loaded.trends.sleep, snapshot.trends.sleep)
        XCTAssertEqual(loaded.summary, snapshot.summary)

        let sidecar = try XCTUnwrap(HealthDashboardSnapshotStore.loadDaySamples(fileURL: fileURL))
        XCTAssertEqual(sidecar.heartRateDaySamples, daySamples)
        XCTAssertEqual(sidecar.stepsDaySamples, .empty)
    }

    func testLegacyCombinedSnapshotFileStillLoadsDaySamples() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let fileURL = temporarySnapshotFileURL()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        let snapshot = try makeSnapshot(heartRateDaySamples: sampleSeries(count: 12, baseValue: 64))
        let legacyData = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try legacyData.write(to: fileURL)

        let loaded = try XCTUnwrap(HealthDashboardSnapshotStore.load(defaults: defaults, fileURL: fileURL))
        XCTAssertEqual(loaded, snapshot)
    }

    func testMergingMissingDaySamplesFillsOnlyEmptyFields() throws {
        let cachedHeartRate = sampleSeries(count: 6, baseValue: 75)
        let sidecarHeartRate = sampleSeries(count: 4, baseValue: 60)
        let sidecarSteps = sampleSeries(count: 3, baseValue: 1_000)

        let sidecarSource = try makeSnapshot(
            heartRateDaySamples: sidecarHeartRate,
            stepsDaySamples: sidecarSteps
        )
        let sidecar = HealthTrendDaySampleSnapshot(trends: sidecarSource.trends)

        let liveTrends = try makeSnapshot(heartRateDaySamples: cachedHeartRate).trends
        let merged = liveTrends.mergingMissingDaySamples(from: sidecar)

        XCTAssertEqual(merged.heartRateDaySamples, cachedHeartRate)
        XCTAssertEqual(merged.stepsDaySamples, sidecarSteps)
        XCTAssertEqual(merged.sleep, liveTrends.sleep)
    }

    func testStrippingDaySamplesClearsAllDaySampleFields() throws {
        let snapshot = try makeSnapshot(
            heartRateDaySamples: sampleSeries(count: 5, baseValue: 70),
            stepsDaySamples: sampleSeries(count: 5, baseValue: 900)
        )

        let stripped = snapshot.trends.strippingDaySamples()

        XCTAssertEqual(stripped.heartRateDaySamples, .empty)
        XCTAssertEqual(stripped.stepsDaySamples, .empty)
        XCTAssertEqual(stripped.sleep, snapshot.trends.sleep)
        XCTAssertTrue(HealthTrendDaySampleSnapshot(trends: stripped).isEmpty)
        XCTAssertFalse(HealthTrendDaySampleSnapshot(trends: snapshot.trends).isEmpty)
    }

    func testSnapshotEncoderIsByteStableAcrossEncodes() throws {
        // `JSONEncoder` randomizes key order between calls; the store's
        // encoder must be deterministic or the save-if-changed byte compare
        // can never report "unchanged".
        let snapshot = try makeSnapshot(heartRateDaySamples: sampleSeries(count: 8, baseValue: 62))

        XCTAssertEqual(
            try HealthDashboardSnapshotStore.makeSnapshotEncoder().encode(snapshot),
            try HealthDashboardSnapshotStore.makeSnapshotEncoder().encode(snapshot)
        )
    }

    func testSaveReturnsTrueWhenOnlyDaySamplesChangeAndDeleteRemovesSidecar() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let fileURL = temporarySnapshotFileURL()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        let first = try makeSnapshot(heartRateDaySamples: sampleSeries(count: 8, baseValue: 62))

        XCTAssertTrue(HealthDashboardSnapshotStore.save(first, defaults: defaults, fileURL: fileURL))
        XCTAssertFalse(HealthDashboardSnapshotStore.save(first, defaults: defaults, fileURL: fileURL))

        let updated = try makeSnapshot(heartRateDaySamples: sampleSeries(count: 9, baseValue: 62))
        XCTAssertTrue(HealthDashboardSnapshotStore.save(updated, defaults: defaults, fileURL: fileURL))

        let sidecarURL = HealthDashboardSnapshotStore.daySamplesFileURL(alongside: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))

        HealthDashboardSnapshotStore.delete(defaults: defaults, fileURL: fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
        XCTAssertNil(HealthDashboardSnapshotStore.loadDaySamples(fileURL: fileURL))
    }
}
