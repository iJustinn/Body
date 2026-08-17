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
        // A pre-H2a file has no summary-context signature key → nil restore.
        XCTAssertNil(HealthDashboardSnapshotStore.loadSummaryContextSignature(fileURL: fileURL))
    }

    func testSaveRoundTripsSummaryContextSignatureAndDedupes() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let fileURL = temporarySnapshotFileURL()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        let snapshot = try makeSnapshot(heartRateDaySamples: .empty)

        // A signature-less save persists no signature key; the restore reads nil.
        XCTAssertTrue(HealthDashboardSnapshotStore.save(snapshot, defaults: defaults, fileURL: fileURL))
        XCTAssertNil(HealthDashboardSnapshotStore.loadSummaryContextSignature(fileURL: fileURL))

        // Stamping a signature rewrites the file, round-trips, and the main
        // snapshot still decodes with the sibling key present (H2a).
        XCTAssertTrue(HealthDashboardSnapshotStore.save(
            snapshot, summaryContextSignature: "SIG-1", defaults: defaults, fileURL: fileURL
        ))
        XCTAssertEqual(HealthDashboardSnapshotStore.loadSummaryContextSignature(fileURL: fileURL), "SIG-1")
        let loaded = try XCTUnwrap(HealthDashboardSnapshotStore.load(defaults: defaults, fileURL: fileURL))
        XCTAssertEqual(loaded.summary, snapshot.summary)

        // Re-saving the same snapshot + signature is a no-op (byte dedupe);
        // changing only the signature still rewrites.
        XCTAssertFalse(HealthDashboardSnapshotStore.save(
            snapshot, summaryContextSignature: "SIG-1", defaults: defaults, fileURL: fileURL
        ))
        XCTAssertTrue(HealthDashboardSnapshotStore.save(
            snapshot, summaryContextSignature: "SIG-2", defaults: defaults, fileURL: fileURL
        ))
        XCTAssertEqual(HealthDashboardSnapshotStore.loadSummaryContextSignature(fileURL: fileURL), "SIG-2")
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

    func testStrippingPrimaryDaySamplesClearsOnlyThatKindsPrimarySeries() {
        let trends = makeDaySampleTrends(
            heartRateDaySamples: sampleSeries(count: 5, baseValue: 70),
            heartRateDaySamplesSecondary: sampleSeries(count: 5, baseValue: 58),
            stepsDaySamples: sampleSeries(count: 5, baseValue: 900)
        )

        let stripped = trends.strippingPrimaryDaySamples(for: .heartRate)

        // Only heart rate's PRIMARY intraday series is cleared; its secondary
        // comparison series and unrelated charts (steps) survive (H6a scope).
        XCTAssertEqual(stripped.heartRateDaySamples, .empty)
        XCTAssertEqual(stripped.heartRateDaySamplesSecondary, trends.heartRateDaySamplesSecondary)
        XCTAssertEqual(stripped.stepsDaySamples, trends.stepsDaySamples)
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

    // MARK: - Source/permission-scoped sidecar (H6 + L10)

    private func makeDaySampleTrends(
        heartRateDaySamples: HealthTrendSeries = .empty,
        heartRateDaySamplesSecondary: HealthTrendSeries = .empty,
        oxygenSaturationDaySamplesSecondary: HealthTrendSeries = .empty,
        stepsDaySamples: HealthTrendSeries = .empty
    ) -> HealthTrendSnapshot {
        HealthTrendSnapshot(
            sleep: .empty,
            restingHeartRate: .empty,
            bodyMass: .empty,
            bodyFatPercentage: .empty,
            heartRateVariability: .empty,
            respiratoryRate: .empty,
            oxygenSaturation: .empty,
            bodyMassIndex: .empty,
            activeEnergy: .empty,
            restingEnergy: .empty,
            heartRateDaySamples: heartRateDaySamples,
            heartRateDaySamplesSecondary: heartRateDaySamplesSecondary,
            oxygenSaturationDaySamplesSecondary: oxygenSaturationDaySamplesSecondary,
            stepsDaySamples: stepsDaySamples
        )
    }

    func testLegacyDaySampleSidecarDecodesWithoutSignatures() throws {
        // A legacy sidecar carries only the 13 series fields and no stamps.
        // Encoding a nil-signature sidecar reproduces that on-disk shape.
        let legacy = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(heartRateDaySamples: sampleSeries(count: 6, baseValue: 61))
        )
        let data = try HealthDashboardSnapshotStore.makeSnapshotEncoder().encode(legacy)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("schemaVersion"))
        XCTAssertFalse(json.contains("primarySelectionSignature"))

        let decoded = try JSONDecoder().decode(HealthTrendDaySampleSnapshot.self, from: data)
        XCTAssertNil(decoded.schemaVersion)
        XCTAssertNil(decoded.primarySelectionSignature)
        XCTAssertNil(decoded.secondarySelectionSignature)
        XCTAssertNil(decoded.permissionSignature)
        XCTAssertNil(decoded.combinesHealthDataSourcesByName)
        XCTAssertEqual(decoded.heartRateDaySamples, legacy.heartRateDaySamples)
    }

    func testScopedSidecarRoundTripsSignatures() throws {
        let signatures = HealthTrendDaySampleSignatures(
            primarySelectionSignature: "P1",
            secondarySelectionSignature: "S1",
            permissionSignature: "sleep,heart,steps",
            combinesHealthDataSourcesByName: true
        )
        let sidecar = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(heartRateDaySamples: sampleSeries(count: 4, baseValue: 70)),
            signatures: signatures
        )
        let data = try HealthDashboardSnapshotStore.makeSnapshotEncoder().encode(sidecar)
        let decoded = try JSONDecoder().decode(HealthTrendDaySampleSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, HealthTrendDaySampleSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.primarySelectionSignature, "P1")
        XCTAssertEqual(decoded.secondarySelectionSignature, "S1")
        XCTAssertEqual(decoded.permissionSignature, "sleep,heart,steps")
        XCTAssertEqual(decoded.combinesHealthDataSourcesByName, true)
        XCTAssertEqual(decoded, sidecar)
    }

    /// The session memoizes ONE sidecar load, so an invalidation that only touches
    /// `healthTrends` and the file is undone the next time hydration runs. The
    /// entitlement handler re-points that memo through this, keeping the primary
    /// scope (so a later hydration still restores it) and dropping every comparison
    /// series — the lapse → unlock case, where the live gate has reopened and the
    /// unchanged signatures would otherwise accept the pre-lapse payload.
    func testStrippingSecondaryDaySamplesClearsComparisonScopeOnly() throws {
        let primarySamples = sampleSeries(count: 5, baseValue: 72)
        let secondarySamples = sampleSeries(count: 5, baseValue: 58)
        let sidecar = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(
                heartRateDaySamples: primarySamples,
                heartRateDaySamplesSecondary: secondarySamples,
                oxygenSaturationDaySamplesSecondary: secondarySamples,
                stepsDaySamples: primarySamples
            ),
            signatures: HealthTrendDaySampleSignatures(
                primarySelectionSignature: "P1",
                secondarySelectionSignature: "S1",
                permissionSignature: BodyHealthPermissionSelection.defaultValue.rawValue,
                combinesHealthDataSourcesByName: false
            )
        )

        let stripped = sidecar.strippingSecondaryDaySamples()

        XCTAssertEqual(stripped.heartRateDaySamplesSecondary, .empty)
        XCTAssertEqual(stripped.restingHeartRateDaySamplesSecondary, .empty)
        XCTAssertEqual(stripped.heartRateVariabilityDaySamplesSecondary, .empty)
        XCTAssertEqual(stripped.oxygenSaturationDaySamplesSecondary, .empty)
        XCTAssertEqual(stripped.activeEnergyDaySamplesSecondary, .empty)
        XCTAssertEqual(stripped.stepsDaySamplesSecondary, .empty)
        // Primary scope survives — losing or regaining Pro says nothing about the
        // user's own source, and a session that hasn't hydrated yet still needs it.
        XCTAssertEqual(stripped.heartRateDaySamples, primarySamples)
        XCTAssertEqual(stripped.stepsDaySamples, primarySamples)
        // Signatures are untouched, so the primary scope still matches on hydration.
        XCTAssertEqual(stripped.primarySelectionSignature, "P1")
        XCTAssertEqual(stripped.secondarySelectionSignature, "S1")
    }

    /// Body Pro lapsing — and a primary source changed to match the secondary —
    /// collapse the comparison to No Comparison WITHOUT touching the stored
    /// secondary selection, so the sidecar's own signatures still match and can't
    /// express the change. Hydration must drop those series from the live state
    /// instead, per-kind: otherwise the entitlement handler's
    /// `clearingSecondarySeries()` is silently undone by the very next
    /// `hydratePersistedDaySamplesIfNeeded()` inside its own corrective refresh
    /// (which reuses the memoized pre-change sidecar), and the samples get
    /// re-persisted.
    func testScopedHydrationDropsComparisonSeriesTheCurrentSelectionResolvesAway() throws {
        let primarySamples = sampleSeries(count: 5, baseValue: 72)
        let secondarySamples = sampleSeries(count: 5, baseValue: 58)
        let sidecar = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(
                heartRateDaySamples: primarySamples,
                heartRateDaySamplesSecondary: secondarySamples,
                oxygenSaturationDaySamplesSecondary: secondarySamples
            ),
            signatures: HealthTrendDaySampleSignatures(
                primarySelectionSignature: "P1",
                secondarySelectionSignature: "S1",
                permissionSignature: BodyHealthPermissionSelection.defaultValue.rawValue,
                combinesHealthDataSourcesByName: false
            )
        )

        // Signatures match on both scopes — only the live gate can drop these.
        let allDisabled = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: [.heartRate, .oxygenSaturation]
        )
        XCTAssertEqual(allDisabled.heartRateDaySamplesSecondary, .empty)
        XCTAssertEqual(allDisabled.oxygenSaturationDaySamplesSecondary, .empty)
        // The primary series is untouched: losing Pro doesn't invalidate the
        // user's own source, only the comparison against a second one.
        XCTAssertEqual(allDisabled.heartRateDaySamples, primarySamples)

        // Per-kind, not all-or-nothing: changing Heart Rate's primary source to
        // match its secondary collapses that kind alone.
        let oneDisabled = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: [.heartRate]
        )
        XCTAssertEqual(oneDisabled.heartRateDaySamplesSecondary, .empty)
        XCTAssertEqual(oneDisabled.oxygenSaturationDaySamplesSecondary, secondarySamples)

        // Nothing disabled → the existing signature scoping decides, unchanged.
        let noneDisabled = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(noneDisabled.heartRateDaySamplesSecondary, secondarySamples)
        XCTAssertEqual(noneDisabled.oxygenSaturationDaySamplesSecondary, secondarySamples)
    }

    func testScopedHydrationMismatchClearsOnlyMismatchedScope() throws {
        let primarySamples = sampleSeries(count: 5, baseValue: 72)
        let secondarySamples = sampleSeries(count: 5, baseValue: 58)
        let sidecar = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(
                heartRateDaySamples: primarySamples,
                heartRateDaySamplesSecondary: secondarySamples
            ),
            signatures: HealthTrendDaySampleSignatures(
                primarySelectionSignature: "P1",
                secondarySelectionSignature: "S1",
                permissionSignature: BodyHealthPermissionSelection.defaultValue.rawValue,
                combinesHealthDataSourcesByName: false
            )
        )

        // Primary source switched, secondary unchanged → drop only primary.
        let primaryChanged = sidecar.scopedForHydration(
            currentPrimarySignature: "P2",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(primaryChanged.heartRateDaySamples, .empty)
        XCTAssertEqual(primaryChanged.heartRateDaySamplesSecondary, secondarySamples)

        // Secondary source switched, primary unchanged → drop only secondary.
        let secondaryChanged = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S2",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(secondaryChanged.heartRateDaySamples, primarySamples)
        XCTAssertEqual(secondaryChanged.heartRateDaySamplesSecondary, .empty)

        // Both match → everything survives.
        let bothMatch = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(bothMatch.heartRateDaySamples, primarySamples)
        XCTAssertEqual(bothMatch.heartRateDaySamplesSecondary, secondarySamples)
    }

    func testLegacyAndV1SidecarsFailClosedAndAreDropped() throws {
        let primarySamples = sampleSeries(count: 5, baseValue: 72)
        let secondarySamples = sampleSeries(count: 5, baseValue: 58)

        // Legacy (nil-schema, pre-scoping) sidecar: no stamps at all. Under the
        // exact-v2 gate it fails closed for BOTH scopes and is dropped one-time,
        // even when the caller's signatures would otherwise have matched (H6b).
        let legacy = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(
                heartRateDaySamples: primarySamples,
                heartRateDaySamplesSecondary: secondarySamples
            )
        )
        XCTAssertNil(legacy.schemaVersion)
        let scopedLegacy = legacy.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(scopedLegacy.heartRateDaySamples, .empty)
        XCTAssertEqual(scopedLegacy.heartRateDaySamplesSecondary, .empty)

        // A round-1 (schemaVersion 1) sidecar carries source stamps but no
        // combine flag; it also fails closed under the exact-v2 gate and drops.
        let v1 = try makeV1Sidecar(
            primary: primarySamples,
            secondary: secondarySamples,
            primarySignature: "P1",
            secondarySignature: "S1",
            permissionSignature: BodyHealthPermissionSelection.defaultValue.rawValue
        )
        XCTAssertEqual(v1.schemaVersion, 1)
        let scopedV1 = v1.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(scopedV1.heartRateDaySamples, .empty)
        XCTAssertEqual(scopedV1.heartRateDaySamplesSecondary, .empty)
    }

    func testCombineFlagFlipInvalidatesBothScopesButMatchKeeps() throws {
        let primarySamples = sampleSeries(count: 5, baseValue: 72)
        let secondarySamples = sampleSeries(count: 5, baseValue: 58)
        // Stamped under combines = false (current schema, v2).
        let sidecar = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(
                heartRateDaySamples: primarySamples,
                heartRateDaySamplesSecondary: secondarySamples
            ),
            signatures: HealthTrendDaySampleSignatures(
                primarySelectionSignature: "P1",
                secondarySelectionSignature: "S1",
                permissionSignature: BodyHealthPermissionSelection.defaultValue.rawValue,
                combinesHealthDataSourcesByName: false
            )
        )

        // Source signatures still match, but the combine flag flipped → both
        // scopes drop (a combine change re-merges every per-source series, H6b).
        let flipped = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: true,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(flipped.heartRateDaySamples, .empty)
        XCTAssertEqual(flipped.heartRateDaySamplesSecondary, .empty)

        // Same combine flag and matching signatures → everything survives.
        let matched = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(matched.heartRateDaySamples, primarySamples)
        XCTAssertEqual(matched.heartRateDaySamplesSecondary, secondarySamples)
    }

    /// Builds a genuine round-1 (schemaVersion 1, no combine flag) sidecar by
    /// stamping a current sidecar, then rewriting the encoded JSON into the v1
    /// on-disk shape and decoding it back — so the fail-closed path is exercised
    /// against a real legacy payload rather than a synthetic in-memory object.
    private func makeV1Sidecar(
        primary: HealthTrendSeries,
        secondary: HealthTrendSeries,
        primarySignature: String,
        secondarySignature: String,
        permissionSignature: String
    ) throws -> HealthTrendDaySampleSnapshot {
        let current = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(
                heartRateDaySamples: primary,
                heartRateDaySamplesSecondary: secondary
            ),
            signatures: HealthTrendDaySampleSignatures(
                primarySelectionSignature: primarySignature,
                secondarySelectionSignature: secondarySignature,
                permissionSignature: permissionSignature,
                combinesHealthDataSourcesByName: false
            )
        )
        let data = try HealthDashboardSnapshotStore.makeSnapshotEncoder().encode(current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "combinesHealthDataSourcesByName")
        let v1Data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(HealthTrendDaySampleSnapshot.self, from: v1Data)
    }

    func testScopedHydrationStripsFieldsForDisabledPermission() throws {
        let heartSamples = sampleSeries(count: 5, baseValue: 72)
        let stepsSamples = sampleSeries(count: 5, baseValue: 900)
        let sidecar = HealthTrendDaySampleSnapshot(
            trends: makeDaySampleTrends(
                heartRateDaySamples: heartSamples,
                stepsDaySamples: stepsSamples
            ),
            signatures: HealthTrendDaySampleSignatures(
                primarySelectionSignature: "P1",
                secondarySelectionSignature: "S1",
                permissionSignature: BodyHealthPermissionSelection.defaultValue.rawValue,
                combinesHealthDataSourcesByName: false
            )
        )

        // Heart permission is now off; scope still matches. Heart samples must
        // be stripped, steps (still permitted) preserved.
        let scoped = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false),
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(scoped.heartRateDaySamples, .empty)
        XCTAssertEqual(scoped.stepsDaySamples, stepsSamples)
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

    /// The lazily fetched intraday series are persisted so the next launch can
    /// render the metric detail Day View from cache. Full disk round trip: the
    /// stamps written by `save` must survive to the sidecar and still gate
    /// hydration, so day samples fetched under one selection can never hydrate
    /// under another.
    func testSavedDaySampleSignaturesGateHydrationOnNextLaunch() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let fileURL = temporarySnapshotFileURL()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        let daySamples = sampleSeries(count: 24, baseValue: 68)
        let snapshot = try makeSnapshot(heartRateDaySamples: daySamples)

        XCTAssertTrue(HealthDashboardSnapshotStore.save(
            snapshot,
            daySampleSignatures: HealthTrendDaySampleSignatures(
                primarySelectionSignature: "P1",
                secondarySelectionSignature: "S1",
                permissionSignature: BodyHealthPermissionSelection.defaultValue.rawValue,
                combinesHealthDataSourcesByName: false
            ),
            defaults: defaults,
            fileURL: fileURL
        ))

        let sidecar = try XCTUnwrap(HealthDashboardSnapshotStore.loadDaySamples(fileURL: fileURL))
        XCTAssertEqual(sidecar.heartRateDaySamples, daySamples)

        // Same selection next launch → the day chart hydrates from the sidecar.
        let matched = sidecar.scopedForHydration(
            currentPrimarySignature: "P1",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(matched.heartRateDaySamples, daySamples)

        // Primary source switched while the app was closed → drop the samples
        // instead of rendering another source's intraday points.
        let switched = sidecar.scopedForHydration(
            currentPrimarySignature: "P2",
            currentSecondarySignature: "S1",
            currentCombinesByName: false,
            permission: .defaultValue,
            comparisonDisabledKinds: []
        )
        XCTAssertEqual(switched.heartRateDaySamples, .empty)
    }
}
