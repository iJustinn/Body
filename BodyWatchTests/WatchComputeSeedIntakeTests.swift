//
//  WatchComputeSeedIntakeTests.swift
//  BodyWatchTests
//
//  Locks the two halves of getting a compute seed onto the watch and keeping it
//  honest:
//  * `WatchMetricsModel.seedIntake` — the pure decision made for every received
//    WatchConnectivity context. It runs INDEPENDENTLY of whether the context's
//    snapshot supersedes (a permission-only or same-revision push can still
//    carry a fresher seed), a corrupt or wrong-schema payload keeps the prior
//    seed rather than wiping a good one, and a Clear-Cache tombstone clears.
//  * `WatchComputeSeedStore` — the byte-compare that decides whether a save is
//    a REAL change. The model bumps the compute generation on that signal, so a
//    false positive would discard an in-flight compute on every settings-only
//    republish (the phone re-sends the identical seed each time).
//

import XCTest
@testable import BodyWatch

final class WatchComputeSeedIntakeTests: XCTestCase {
    private let dataThrough = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Fixtures

    private func seed(
        schemaVersion: Int = WatchComputeSeed.currentSchemaVersion,
        settingsSignature: String = "sig"
    ) -> WatchComputeSeed {
        WatchComputeSeed(
            schemaVersion: schemaVersion,
            publishedAt: dataThrough,
            dataThrough: dataThrough,
            lastVitalsRefreshDate: dataThrough,
            summary: .empty,
            trends: .empty,
            seriesRanges: [:],
            settings: WatchComputeSettings(
                idealSleepDurationMinutes: 480,
                followsSystemUnits: true,
                selectedTemperatureUnitRaw: "celsius",
                showSleepScore: true,
                showsSubMinuteAwakeSleepStages: true,
                showsLeadingTrailingAwakeSleepStages: true,
                healthDataSourceSelectionRaw: "{}",
                combinesHealthDataSourcesByName: false
            ),
            settingsSignature: settingsSignature
        )
    }

    private func uniqueFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyWatchSeedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent(WatchComputeSeedStore.seedFileName)
    }

    // MARK: - Intake decisions

    /// `seedIntake` alone has no notion of snapshot ordering, so a test that
    /// only calls it can't actually prove seed intake runs INDEPENDENTLY of
    /// whether the snapshot supersedes — that independence is a property of
    /// `resolution(for:over:)`, which combines the two. Exercised here
    /// directly: a non-superseding snapshot (and, separately, no snapshot key
    /// at all) still yields `.replace` for a valid seed and a nil resolved
    /// snapshot; a superseding snapshot + seed yields both.
    func testSeedIntakeRunsIndependentlyOfWhetherTheSnapshotSupersedes() throws {
        let current = WatchMetricsSnapshot(
            generatedAt: dataThrough, lastRefreshDate: dataThrough, metrics: [],
            publisherEpoch: "epoch-a", revision: 5
        )
        let seedData = try XCTUnwrap(seed().encodedCompressed())
        // `.replace` now carries the seed the intake decoded from these exact
        // bytes; `publishedAt` is deliberately not encoded, so compare against
        // the round-tripped seed rather than the fixture.
        let decodedSeed = try XCTUnwrap(WatchComputeSeed.decoded(from: seedData))

        // Snapshot does NOT supersede `current` (older revision, same epoch):
        // the seed is still adopted; nothing to persist on the display side.
        let nonSupersedingSnapshot = WatchMetricsSnapshot(
            generatedAt: dataThrough.addingTimeInterval(-3_600), lastRefreshDate: dataThrough, metrics: [],
            publisherEpoch: "epoch-a", revision: 4
        )
        let nonSupersedingContext: [String: Any] = [
            "snapshot": try XCTUnwrap(nonSupersedingSnapshot.encoded()),
            WatchComputeSeed.applicationContextKey: seedData
        ]
        let nonSupersedingResolution = WatchMetricsModel.resolution(for: nonSupersedingContext, over: current)
        XCTAssertEqual(nonSupersedingResolution.seedIntake, .replace(seedData, decodedSeed))
        XCTAssertNil(nonSupersedingResolution.resolvedSnapshot)

        // No "snapshot" key at all (a permission-only push): same outcome —
        // the seed must still land, or a watch whose snapshot never
        // supersedes stays seedless forever.
        let noSnapshotContext: [String: Any] = [WatchComputeSeed.applicationContextKey: seedData]
        let noSnapshotResolution = WatchMetricsModel.resolution(for: noSnapshotContext, over: current)
        XCTAssertEqual(noSnapshotResolution.seedIntake, .replace(seedData, decodedSeed))
        XCTAssertNil(noSnapshotResolution.resolvedSnapshot)

        // A SUPERSEDING snapshot + seed: both a seed replacement AND a
        // resolved snapshot to persist.
        let supersedingSnapshot = WatchMetricsSnapshot(
            generatedAt: dataThrough.addingTimeInterval(3_600), lastRefreshDate: dataThrough, metrics: [],
            publisherEpoch: "epoch-a", revision: 6
        )
        let supersedingContext: [String: Any] = [
            "snapshot": try XCTUnwrap(supersedingSnapshot.encoded()),
            WatchComputeSeed.applicationContextKey: seedData
        ]
        let supersedingResolution = WatchMetricsModel.resolution(for: supersedingContext, over: current)
        XCTAssertEqual(supersedingResolution.seedIntake, .replace(seedData, decodedSeed))
        XCTAssertNotNil(supersedingResolution.resolvedSnapshot)
    }

    func testMissingSeedKeyKeepsPriorSeed() {
        XCTAssertEqual(
            WatchMetricsModel.seedIntake(from: ["snapshot": Data()], isReset: false),
            .keepPrior
        )
    }

    func testCorruptSeedKeepsPriorSeed() {
        // Undecodable bytes must never wipe a good stored seed.
        let intake = WatchMetricsModel.seedIntake(
            from: [WatchComputeSeed.applicationContextKey: Data([0x00, 0x01, 0x02, 0x03])],
            isReset: false
        )
        XCTAssertEqual(intake, .keepPrior)
    }

    func testUnrecognizedSchemaVersionKeepsPriorSeed() throws {
        let data = try XCTUnwrap(seed(schemaVersion: WatchComputeSeed.currentSchemaVersion + 1).encodedCompressed())
        XCTAssertEqual(
            WatchMetricsModel.seedIntake(from: [WatchComputeSeed.applicationContextKey: data], isReset: false),
            .keepPrior
        )
    }

    func testResetTombstoneClearsTheSeedEvenIfOneIsAttached() throws {
        let data = try XCTUnwrap(seed().encodedCompressed())
        XCTAssertEqual(
            WatchMetricsModel.seedIntake(from: [WatchComputeSeed.applicationContextKey: data], isReset: true),
            .clear
        )
        XCTAssertEqual(WatchMetricsModel.seedIntake(from: [:], isReset: true), .clear)
    }

    // MARK: - Store byte-compare

    func testSaveReportsChangeOnlyWhenTheBytesDiffer() throws {
        let fileURL = try uniqueFileURL()
        let data = try XCTUnwrap(seed().encodedCompressed())

        XCTAssertTrue(WatchComputeSeedStore.save(data, fileURL: fileURL))
        // The republish the phone sends on every settings-only publish carries
        // the same data under a FRESH `publishedAt` — which the seed encoder
        // deliberately omits, so the bytes must still match and the save must
        // NOT read as a change (it would discard in-flight computes over and
        // over).
        var republished = seed()
        republished.publishedAt = dataThrough.addingTimeInterval(3_600)
        let republishedData = try XCTUnwrap(republished.encodedCompressed())
        XCTAssertFalse(WatchComputeSeedStore.save(republishedData, fileURL: fileURL))

        var changedSeed = seed()
        changedSeed.settingsSignature = "sig-2"
        let changedData = try XCTUnwrap(changedSeed.encodedCompressed())
        XCTAssertTrue(WatchComputeSeedStore.save(changedData, fileURL: fileURL))
    }

    /// M-34: the intake already decoded the seed it is saving, so the store
    /// primes its decode memo with it. The compute's next `load()` must then
    /// return that seed without repeating the zlib decompress plus JSON parse.
    func testSaveWithDecodedSeedPrimesTheDecodeMemo() throws {
        let fileURL = try uniqueFileURL()
        let decoded = seed(settingsSignature: "sig-memo")
        let data = try XCTUnwrap(decoded.encodedCompressed())

        XCTAssertTrue(WatchComputeSeedStore.save(data, decoded: decoded, fileURL: fileURL))
        XCTAssertEqual(WatchComputeSeedStore.load(fileURL: fileURL), decoded)

        // A later save of DIFFERENT bytes must not be served from the primed
        // entry: the memo is keyed by the bytes it came from.
        let replacement = seed(settingsSignature: "sig-memo-2")
        let replacementData = try XCTUnwrap(replacement.encodedCompressed())
        XCTAssertTrue(WatchComputeSeedStore.save(replacementData, decoded: replacement, fileURL: fileURL))
        XCTAssertEqual(WatchComputeSeedStore.load(fileURL: fileURL)?.settingsSignature, "sig-memo-2")
    }

    func testStoredSeedRoundTripsAndClearsOnce() throws {
        let fileURL = try uniqueFileURL()
        XCTAssertFalse(WatchComputeSeedStore.hasStoredSeed(fileURL: fileURL))

        let data = try XCTUnwrap(seed().encodedCompressed())
        XCTAssertTrue(WatchComputeSeedStore.save(data, fileURL: fileURL))
        XCTAssertTrue(WatchComputeSeedStore.hasStoredSeed(fileURL: fileURL))

        let loaded = try XCTUnwrap(WatchComputeSeedStore.load(fileURL: fileURL))
        XCTAssertEqual(loaded.dataThrough, dataThrough)
        XCTAssertEqual(loaded.settingsSignature, "sig")

        // Clear reports a real removal once, then nothing — so a repeated
        // tombstone doesn't keep bumping the compute generation.
        XCTAssertTrue(WatchComputeSeedStore.clear(fileURL: fileURL))
        XCTAssertFalse(WatchComputeSeedStore.clear(fileURL: fileURL))
        XCTAssertNil(WatchComputeSeedStore.load(fileURL: fileURL))
    }

    // MARK: - Settings decode across phone vintages

    /// The custom-source group definitions ride on `WatchComputeSettings` as an
    /// OPTIONAL raw string. A phone that predates the feature (or one whose Body
    /// Pro lapsed, which withholds the definitions) simply omits the key, and
    /// that payload has to keep decoding — a throwing decode here would drop the
    /// whole seed and freeze the compute.
    func testSettingsDecodeWithAndWithoutTheCustomGroupsKey() throws {
        let decoder = JSONDecoder()
        let legacyJSON = """
        {
          "idealSleepDurationMinutes": 480,
          "followsSystemUnits": true,
          "selectedTemperatureUnitRaw": "celsius",
          "showSleepScore": true,
          "showsSubMinuteAwakeSleepStages": true,
          "showsLeadingTrailingAwakeSleepStages": true,
          "healthDataSourceSelectionRaw": "{}",
          "combinesHealthDataSourcesByName": false
        }
        """

        let legacy = try decoder.decode(WatchComputeSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(legacy.customHealthSourceGroupsRaw)
        // The rest of the payload still lands (a lenient decode must not silently
        // default everything just because one key is new).
        XCTAssertEqual(legacy.idealSleepDurationMinutes, 480)
        XCTAssertEqual(legacy.healthDataSourceSelectionRaw, "{}")
        // No definitions ⇒ no buckets to rebuild ⇒ a `custom:` selection stays
        // unresolved and the watch keeps its seeded values.
        XCTAssertTrue(BodyCustomHealthSourceGroupStore.groups(from: legacy.customHealthSourceGroupsRaw ?? "").isEmpty)

        let groupsRaw = BodyCustomHealthSourceGroupStore.rawValue(
            from: [
                BodyCustomHealthSourceGroup(
                    id: "custom:11111111-2222-3333-4444-555555555555",
                    name: "Wrist",
                    memberIdentityKeys: [
                        "bundle=com.example.watch|name=watch",
                        "bundle=com.example.phone|name=phone"
                    ]
                )
            ]
        )
        let published = WatchComputeSettings(
            idealSleepDurationMinutes: 480,
            followsSystemUnits: true,
            selectedTemperatureUnitRaw: "celsius",
            showSleepScore: true,
            showsSubMinuteAwakeSleepStages: true,
            showsLeadingTrailingAwakeSleepStages: true,
            healthDataSourceSelectionRaw: "{}",
            combinesHealthDataSourcesByName: false,
            customHealthSourceGroupsRaw: groupsRaw
        )
        let withGroups = try decoder.decode(
            WatchComputeSettings.self,
            from: try JSONEncoder().encode(published)
        )

        XCTAssertEqual(withGroups.customHealthSourceGroupsRaw, groupsRaw)
        let decodedGroups = BodyCustomHealthSourceGroupStore.groups(from: try XCTUnwrap(withGroups.customHealthSourceGroupsRaw))
        XCTAssertEqual(decodedGroups.count, 1)
        XCTAssertEqual(
            decodedGroups.first?.memberIdentityKeys,
            ["bundle=com.example.phone|name=phone", "bundle=com.example.watch|name=watch"]
        )
    }

    // MARK: - Generation token (anti-resurrection)

    func testFinishedComputeIsDiscardedWhenTheGenerationMovedOrTheSnapshotWasReset() {
        let computed = WatchMetricsSnapshot(
            generatedAt: dataThrough,
            lastRefreshDate: dataThrough,
            metrics: []
        )
        let result = WatchComputeResult(snapshot: computed, dataAsOf: [:], coverage: dataThrough, generation: 4)
        let live = WatchMetricsSnapshot(generatedAt: dataThrough, lastRefreshDate: dataThrough, metrics: [])
        var tombstone = live
        tombstone.isReset = true

        XCTAssertTrue(WatchMetricsModel.mayMerge(result, generation: 4, into: live))
        // A seed replacement / permission change / reset bumped the generation
        // while this compute was running.
        XCTAssertFalse(WatchMetricsModel.mayMerge(result, generation: 5, into: live))
        // Even at a matching generation, a tombstone is never repopulated.
        XCTAssertFalse(WatchMetricsModel.mayMerge(result, generation: 4, into: tombstone))
    }

    // MARK: - Settings-signature change detection (local-provenance strip)

    func testSettingsChangedOnlyBetweenTwoKnownDifferentSignatures() throws {
        let newSeed = seed(settingsSignature: "sig-NEW")
        let seedData = try XCTUnwrap(newSeed.encodedCompressed())

        // Prior signature differs -> the local values were derived under a
        // superseded configuration and must be stripped.
        XCTAssertTrue(WatchMetricsModel.settingsChanged(
            intake: .replace(seedData, newSeed), priorSignature: "sig-OLD", seedChanged: true
        ))
        // Same signature -> an ordinary data refresh of the seed.
        XCTAssertFalse(WatchMetricsModel.settingsChanged(
            intake: .replace(seedData, newSeed), priorSignature: "sig-NEW", seedChanged: true
        ))
        // No prior seed -> no old configuration anything local was derived under.
        XCTAssertFalse(WatchMetricsModel.settingsChanged(
            intake: .replace(seedData, newSeed), priorSignature: nil, seedChanged: true
        ))
        // Signature-only push that cleared a mismatched stored seed.
        XCTAssertTrue(WatchMetricsModel.settingsChanged(
            intake: .clearIfSettingsMismatch("sig-NEW"), priorSignature: "sig-OLD", seedChanged: true
        ))
        // Signature-only push whose stored seed already matched (nothing cleared).
        XCTAssertFalse(WatchMetricsModel.settingsChanged(
            intake: .clearIfSettingsMismatch("sig-NEW"), priorSignature: "sig-NEW", seedChanged: false
        ))
        // Tombstones and no-ops never count as settings changes.
        XCTAssertFalse(WatchMetricsModel.settingsChanged(intake: .clear, priorSignature: "sig-OLD", seedChanged: true))
        XCTAssertFalse(WatchMetricsModel.settingsChanged(intake: .keepPrior, priorSignature: "sig-OLD", seedChanged: false))
    }

    func testStoredSeedIsNotInTheAppGroupContainer() throws {
        // Complications never compute, so the seed must not bloat the App Group
        // the widget timeline passes read on every refresh. `XCTSkipIf` (not a
        // silent `guard ... else { return }`) so a missing container is VISIBLE
        // in the results rather than a free pass — but not a failure either: an
        // unsigned test host (`CODE_SIGNING_ALLOWED=NO`) legitimately has no
        // App Group entitlement, and failing there would make the whole suite
        // red on a supported invocation.
        try XCTSkipIf(
            WatchComputeSeedStore.seedFileURL == nil || WatchMetricsSnapshotStore.sharedContainerURL == nil,
            "container URLs unavailable (unsigned test host has no App Group entitlement)"
        )
        let seedURL = try XCTUnwrap(WatchComputeSeedStore.seedFileURL)
        let sharedURL = try XCTUnwrap(WatchMetricsSnapshotStore.sharedContainerURL)
        XCTAssertFalse(seedURL.path.hasPrefix(sharedURL.path))
    }
}
