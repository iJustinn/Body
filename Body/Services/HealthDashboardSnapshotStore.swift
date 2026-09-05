//
//  HealthDashboardSnapshotStore.swift
//  Body
//

import Foundation
import os

enum HealthDashboardSnapshotStore {
    static let healthDashboardSnapshotKey = "lastHealthDashboardSnapshot"
    static let healthDashboardSnapshotFileName = "lastHealthDashboardSnapshot.json"
    static let healthDashboardDaySamplesFileName = "lastHealthDashboardDaySamples.json"

    /// `JSONEncoder` randomizes keyed-container key order between encode
    /// calls, so the save-if-changed byte compare needs `.sortedKeys` to be
    /// deterministic — without it every save rewrites the file (and triggers
    /// downstream side effects) even when nothing changed.
    static func makeSnapshotEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    static let secondarySelectionSignatureKey = "lastHealthDashboardSecondarySelectionSignature"
    static let lastSuccessfulRefreshDateKey = "lastHealthDashboardSuccessfulRefreshDate"
    static let lastWorkoutsWeekCoverageDateKey = "lastHealthDashboardWorkoutsWeekCoverageDate"
    static let activityRingBackfillCompletedKey = "lastHealthDashboardActivityRingBackfillCompleted"
    static let initialHealthDataLoadCompletedKey = "lastHealthDashboardInitialLoadCompleted"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "HealthDashboardSnapshotStore")

    static func saveSecondarySelectionSignature(_ signature: String, defaults: UserDefaults = .standard) {
        defaults.set(signature, forKey: secondarySelectionSignatureKey)
    }

    static func loadSecondarySelectionSignature(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: secondarySelectionSignatureKey)
    }

    /// Legacy timestamp helpers. Cold start now trusts only envelope freshness;
    /// a separate defaults key cannot prove that its dashboard reached disk.
    static func saveLastSuccessfulRefreshDate(_ date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastSuccessfulRefreshDateKey)
    }

    static func loadLastSuccessfulRefreshDate(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastSuccessfulRefreshDateKey) as? Date
    }

    static func clearLastSuccessfulRefreshDate(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastSuccessfulRefreshDateKey)
    }

    /// Persisted watermark for the watch's weekly workout-minutes bars: the
    /// last time a fetch covered EVERY month the trailing 7-day window touches.
    /// Deliberately its own key rather than restoring from
    /// `lastSuccessfulRefreshDate` — an early-month passive refresh persists a
    /// success date while fetching only the current month, so reusing it would
    /// relaunch with a coverage claim the fetch never earned and let a stale
    /// mixed-month week overwrite a newer watch-computed one.
    static func saveLastWorkoutsWeekCoverageDate(_ date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastWorkoutsWeekCoverageDateKey)
    }

    static func loadLastWorkoutsWeekCoverageDate(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastWorkoutsWeekCoverageDateKey) as? Date
    }

    static func clearLastWorkoutsWeekCoverageDate(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastWorkoutsWeekCoverageDateKey)
    }

    /// Whether the user has already been through the first-launch Health load.
    /// Unlike `lastSuccessfulRefreshDate` this is stamped by ANY completed full
    /// refresh — including a partial one that hit query failures, or one that
    /// found no data at all — because a user who denied some read permissions
    /// would otherwise never clear the first-launch overlay or onboarding and
    /// be stuck on "Try Again" forever.
    static func saveInitialHealthDataLoadCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: initialHealthDataLoadCompletedKey)
    }

    static func loadInitialHealthDataLoadCompleted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: initialHealthDataLoadCompletedKey)
    }

    static func clearInitialHealthDataLoadCompleted(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: initialHealthDataLoadCompletedKey)
    }

    /// The phone's discovered source universe per watch-compute kind (see
    /// `HealthKitFetchEngine.watchComputeExpectedSourceIDs`), persisted so a
    /// relaunch restores it together with `lastSuccessfulRefreshDate`: the
    /// restored refresh date makes `publishWatchSnapshot` attach a compute
    /// seed before this session has run source discovery, and a seed shipped
    /// with NO expected-source lists tells the watch its unfiltered
    /// All-Sources reads are phone-equivalent — discarding coverage the last
    /// session had already established.
    static let watchExpectedSourceIDsKey = "lastHealthDashboardWatchExpectedSourceIDs"

    static func saveWatchExpectedSourceIDs(_ idsByKind: [String: [String]], defaults: UserDefaults = .standard) {
        defaults.set(idsByKind, forKey: watchExpectedSourceIDsKey)
    }

    static func loadWatchExpectedSourceIDs(defaults: UserDefaults = .standard) -> [String: [String]] {
        defaults.object(forKey: watchExpectedSourceIDsKey) as? [String: [String]] ?? [:]
    }

    static func clearWatchExpectedSourceIDs(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: watchExpectedSourceIDsKey)
    }

    /// The compute seed's Training Load piece (dense day-indexed loads + its
    /// own data-coverage watermark), persisted for the same reason as the
    /// expected-source lists above: the seed's `dataThrough` survives a
    /// relaunch, so a workout-only publish inside the refresh TTL would
    /// otherwise replace the watch's complete seed with one carrying NO
    /// Training Load arrays — and with the Training Load / Readiness cards
    /// hidden on the phone, no later full refresh ever rebuilds them.
    /// `through` is stored alongside so the honesty gate (the watch refuses
    /// loads whose coverage doesn't reach its delta window) keeps working on
    /// the restored copy.
    static let watchTrainingLoadSeedKey = "lastHealthDashboardWatchTrainingLoadSeed"

    static func saveWatchTrainingLoadSeed(startDay: Date, loads: [Double], through: Date, defaults: UserDefaults = .standard) {
        defaults.set(
            ["startDay": startDay, "loads": loads, "through": through] as [String: Any],
            forKey: watchTrainingLoadSeedKey
        )
    }

    static func loadWatchTrainingLoadSeed(defaults: UserDefaults = .standard) -> (startDay: Date, loads: [Double], through: Date)? {
        guard let stored = defaults.dictionary(forKey: watchTrainingLoadSeedKey),
              let startDay = stored["startDay"] as? Date,
              let loads = stored["loads"] as? [Double],
              let through = stored["through"] as? Date else {
            return nil
        }
        return (startDay: startDay, loads: loads, through: through)
    }

    static func clearWatchTrainingLoadSeed(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: watchTrainingLoadSeedKey)
    }

    /// Progress of the first-load activity-ring backfill (up to ten years,
    /// walked newest-first in chunks). A Boolean "completed" flag could only
    /// say "done" or "start over": a walk cut short by a deadline or by a quit
    /// restarted from today every time, and a HealthKit denial re-issued the
    /// whole ten-year scan on every single refresh forever.
    ///
    /// - `pending` carries the checkpoint the next chunk resumes from (`nil`
    ///   → start at today).
    /// - `completed` is stamped ONLY when the walk genuinely reached the start
    ///   of history, never because one partial chunk came back with data.
    /// - `suppressed` records a denied read so the heavy scan stays parked
    ///   until a later cheap read (or the user re-enabling Activity in Body's
    ///   own permission selection) proves access is back.
    enum ActivityRingBackfillState: Codable, Equatable {
        case pending(resumeFrom: Date?)
        case completed
        case suppressed(lastProbe: Date)
    }

    /// Legacy checkpoint keys, retained for cleanup and compatibility tests.
    /// Production restores only the checkpoint bound to the dashboard envelope.
    static let activityRingBackfillResumeDateKey = "lastHealthDashboardActivityRingBackfillResumeDate"
    static let activityRingBackfillSuppressedDateKey = "lastHealthDashboardActivityRingBackfillSuppressedDate"

    static func saveActivityRingBackfillState(
        _ state: ActivityRingBackfillState,
        defaults: UserDefaults = .standard
    ) {
        switch state {
        case .completed:
            defaults.set(true, forKey: activityRingBackfillCompletedKey)
            defaults.removeObject(forKey: activityRingBackfillResumeDateKey)
            defaults.removeObject(forKey: activityRingBackfillSuppressedDateKey)
        case .pending(let resumeFrom):
            defaults.removeObject(forKey: activityRingBackfillCompletedKey)
            defaults.removeObject(forKey: activityRingBackfillSuppressedDateKey)
            if let resumeFrom {
                defaults.set(resumeFrom, forKey: activityRingBackfillResumeDateKey)
            } else {
                defaults.removeObject(forKey: activityRingBackfillResumeDateKey)
            }
        case .suppressed(let lastProbe):
            defaults.removeObject(forKey: activityRingBackfillCompletedKey)
            defaults.removeObject(forKey: activityRingBackfillResumeDateKey)
            defaults.set(lastProbe, forKey: activityRingBackfillSuppressedDateKey)
        }
    }

    static func loadActivityRingBackfillState(defaults: UserDefaults = .standard) -> ActivityRingBackfillState {
        if defaults.bool(forKey: activityRingBackfillCompletedKey) {
            return .completed
        }
        if let lastProbe = defaults.object(forKey: activityRingBackfillSuppressedDateKey) as? Date {
            return .suppressed(lastProbe: lastProbe)
        }
        return .pending(resumeFrom: defaults.object(forKey: activityRingBackfillResumeDateKey) as? Date)
    }

    /// Back to `.pending(resumeFrom: nil)`. Cleared with the cache, and
    /// whenever the cached ring history is purged, so a wiped snapshot gets
    /// backfilled again from today.
    static func clearActivityRingBackfillState(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: activityRingBackfillCompletedKey)
        defaults.removeObject(forKey: activityRingBackfillResumeDateKey)
        defaults.removeObject(forKey: activityRingBackfillSuppressedDateKey)
    }

    static var snapshotFileURL: URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.error("Health dashboard snapshot file URL unavailable.")
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent("HealthDashboardSnapshotStore", isDirectory: true)
            .appendingPathComponent(healthDashboardSnapshotFileName)
    }

    /// The intraday day-sample series live in a sidecar file next to the main
    /// snapshot so cold launch only pays the small main-file decode on the
    /// main thread; the sidecar is decoded off-main via `loadDaySamples`.
    static func daySamplesFileURL(alongside fileURL: URL) -> URL {
        fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(healthDashboardDaySamplesFileName)
    }

    /// Metadata is meaningful only beside the payload in the same atomic file.
    /// Legacy UserDefaults checkpoints and timestamps cannot prove that binding.
    struct PersistenceMetadata: Codable, Equatable {
        var ringBackfill: ActivityRingBackfillState = .pending(resumeFrom: nil)
        var secondarySelectionSignature: String?
        var freshness: Freshness?
        /// Missing in pre-day-identity envelopes. Progress is restarted once;
        /// subsequent partial repair checkpoints remain bound to their payload.
        var ringDayIdentityVersion: Int? = 1
        var ringBackfillResumeDay: ActivityRingDaySummary.CalendarDay?
    }

    struct Freshness: Codable, Equatable {
        let date: Date
        let contextSignature: String
    }

    enum FileSaveOutcome: Equatable {
        case written, unchanged, failed
        // An unhydrated empty sidecar request preserved existing samples; this
        // is not acknowledgment that the incoming raw payload reached disk.
        case preserved

        var isDurable: Bool { self == .written || self == .unchanged }
    }

    struct SaveOutcome: Equatable {
        let main: FileSaveOutcome
        let sidecar: FileSaveOutcome
        var didWrite: Bool { main == .written || sidecar == .written }
    }

    /// Failure/pause injection stays below encoding and atomic replacement.
    /// Production uses the same encode-before-write and byte-dedupe path.
    struct PersistenceIO {
        var encoder: () -> JSONEncoder = { makeSnapshotEncoder() }
        var write: (Data, URL) throws -> Void = { data, url in
            try BodySnapshotDirectory.prepare(url.deletingLastPathComponent())
            // Background reads must work while locked after the first unlock.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Compatibility entry for legacy payload migration and payload-only tests.
    /// Live store saves must use `saveWithOutcome` with captured metadata.
    @discardableResult
    static func save(
        _ snapshot: HealthDashboardSnapshot,
        daySampleSignatures: HealthTrendDaySampleSignatures? = nil,
        summaryContextSignature: String? = nil,
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> Bool {
        saveWithOutcome(snapshot, daySampleSignatures: daySampleSignatures,
                        summaryContextSignature: summaryContextSignature,
                        metadata: PersistenceMetadata(), defaults: defaults, fileURL: fileURL).didWrite
    }

    @discardableResult
    static func saveWithOutcome(
        _ snapshot: HealthDashboardSnapshot,
        daySampleSignatures: HealthTrendDaySampleSignatures? = nil,
        summaryContextSignature: String? = nil,
        metadata: PersistenceMetadata,
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL,
        io: PersistenceIO = PersistenceIO()
    ) -> SaveOutcome {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DashboardSnapshotSave")
        defer { BodyPerformanceSignposts.signposter.endInterval("DashboardSnapshotSave", signpostState) }

        guard let fileURL else {
            logger.error("Health dashboard snapshot file save skipped because file URL is unavailable.")
            return SaveOutcome(main: .failed, sidecar: .failed)
        }

        let mainSnapshot = HealthDashboardSnapshot(
            summary: snapshot.summary,
            trends: snapshot.trends.strippingDaySamples(),
            activityRingHistory: snapshot.activityRingHistory
        )
        let mainOutcome: FileSaveOutcome
        do {
            let data = try io.encoder().encode(
                PersistedDashboardSnapshot(
                    snapshot: mainSnapshot,
                    summaryContextSignature: summaryContextSignature,
                    metadata: metadata
                )
            )
            mainOutcome = writeIfChanged(data, to: fileURL, io: io)
        } catch {
            logger.error("Health dashboard snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            mainOutcome = .failed
        }
        if mainOutcome.isDurable {
            defaults.removeObject(forKey: healthDashboardSnapshotKey)
        }
        let sidecarOutcome = saveDaySamples(
            HealthTrendDaySampleSnapshot(trends: snapshot.trends, signatures: daySampleSignatures),
            alongside: fileURL, io: io
        )
        return SaveOutcome(main: mainOutcome, sidecar: sidecarOutcome)
    }

    private static func saveDaySamples(
        _ daySamples: HealthTrendDaySampleSnapshot,
        alongside fileURL: URL,
        io: PersistenceIO
    ) -> FileSaveOutcome {
        let sidecarURL = daySamplesFileURL(alongside: fileURL)
        if daySamples.isEmpty, !FileManager.default.fileExists(atPath: sidecarURL.path) {
            return .unchanged
        }

        let payload = daySamples
        // An all-empty payload over a populated sidecar is only a no-op when
        // the sidecar's scope already matches the incoming payload exactly
        // (H-17): schemaVersion and all four selection/permission signatures.
        // In that case nothing about the selection changed, so keep the file
        // untouched rather than rewriting it. If any signature differs, the
        // incoming payload reflects a real scope change (e.g. the user
        // deselected the only source whose Day View was loaded), and the
        // empty payload is a legitimate invalidation that must overwrite the
        // sidecar, matching `strippingDaySamples()`/`truncateDaySamples()`.
        if daySamples.isEmpty,
           let existingData = try? Data(contentsOf: sidecarURL),
           let existing = try? JSONDecoder().decode(HealthTrendDaySampleSnapshot.self, from: existingData),
           !existing.isEmpty,
           existing.schemaVersion == daySamples.schemaVersion,
           existing.primarySelectionSignature == daySamples.primarySelectionSignature,
           existing.secondarySelectionSignature == daySamples.secondarySelectionSignature,
           existing.primaryMetricScopes == daySamples.primaryMetricScopes,
           existing.secondaryMetricScopes == daySamples.secondaryMetricScopes,
           existing.permissionSignature == daySamples.permissionSignature,
           existing.combinesHealthDataSourcesByName == daySamples.combinesHealthDataSourcesByName {
            logger.notice("kept the populated day-sample sidecar unchanged; scope signatures already matched")
            return .preserved
        }

        let data: Data
        do {
            data = try io.encoder().encode(payload)
        } catch {
            logger.error("Health dashboard day-sample encode failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
        return writeIfChanged(data, to: sidecarURL, io: io)
    }

    private static func writeIfChanged(_ data: Data, to fileURL: URL, io: PersistenceIO) -> FileSaveOutcome {
        if (try? Data(contentsOf: fileURL)) == data { return .unchanged }
        do {
            try io.write(data, fileURL)
            return .written
        } catch {
            logger.error("Health dashboard file write failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    static func loadDaySamples(fileURL: URL? = snapshotFileURL) -> HealthTrendDaySampleSnapshot? {
        guard let fileURL else {
            return nil
        }

        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DaySamplesSidecarLoad")
        defer { BodyPerformanceSignposts.signposter.endInterval("DaySamplesSidecarLoad", signpostState) }

        let sidecarURL = daySamplesFileURL(alongside: fileURL)
        let data: Data
        do {
            data = try Data(contentsOf: sidecarURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Health dashboard day-sample file read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        do {
            return try JSONDecoder().decode(HealthTrendDaySampleSnapshot.self, from: data)
        } catch {
            logger.error("Health dashboard day-sample decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Both halves of the persisted envelope from a single read + decode. The
    /// launch path needs the snapshot *and* the signature written beside it, and
    /// reading them through two entry points tokenized the largest cache twice
    /// on the main thread before the first frame.
    struct LoadedSnapshot {
        let snapshot: HealthDashboardSnapshot
        let summaryContextSignature: String?
        var metadata: PersistenceMetadata = PersistenceMetadata()

        static let empty = LoadedSnapshot(snapshot: .empty, summaryContextSignature: nil)
    }

    static func loadWithContext(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> LoadedSnapshot? {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DashboardSnapshotLoad")
        defer { BodyPerformanceSignposts.signposter.endInterval("DashboardSnapshotLoad", signpostState) }

        if let loaded = loadFromFile(fileURL: fileURL) {
            return loaded
        }

        guard let legacyData = defaults.data(forKey: healthDashboardSnapshotKey) else {
            return nil
        }

        guard let legacyLoaded = decode(legacyData) else {
            defaults.removeObject(forKey: healthDashboardSnapshotKey)
            return nil
        }

        save(legacyLoaded.snapshot, defaults: defaults, fileURL: fileURL)
        return legacyLoaded
    }

    static func load(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> HealthDashboardSnapshot? {
        loadWithContext(defaults: defaults, fileURL: fileURL)?.snapshot
    }

    static func loadOrEmptyWithContext(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> LoadedSnapshot {
        loadWithContext(defaults: defaults, fileURL: fileURL) ?? .empty
    }

    static func loadOrEmpty(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> HealthDashboardSnapshot {
        load(defaults: defaults, fileURL: fileURL) ?? .empty
    }

    /// The summary-context signature persisted alongside the snapshot (H2a),
    /// read on its own without rebuilding the snapshot object graph. `nil` for a
    /// snapshot written before this field existed (→ conservative empty-on-
    /// failure until the first refresh re-stamps it). The launch restore reads
    /// it out of `loadOrEmptyWithContext`'s single decode instead; this stays
    /// for callers that want the signature alone.
    static func loadSummaryContextSignature(fileURL: URL? = snapshotFileURL) -> String? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return (try? JSONDecoder().decode(SummaryContextSignatureProbe.self, from: data))?
            .summaryContextSignature
    }

    static func exists(fileURL: URL? = snapshotFileURL) -> Bool {
        guard let fileURL else {
            return false
        }

        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func fileSize(at fileURL: URL?) -> Int64 {
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    static var totalDiskSizeBytes: Int64 {
        fileSize(at: snapshotFileURL)
            + fileSize(at: snapshotFileURL.map(daySamplesFileURL(alongside:)))
    }

    /// Removes only the day-sample sidecar, leaving the main snapshot file in
    /// place. Used at the deliberate full-strip sites (a source/combine change
    /// invalidates every cached intraday series) instead of a normal save,
    /// which would now merge an empty payload into the still-populated file
    /// rather than truncate it.
    @discardableResult
    static func truncateDaySamples(fileURL: URL? = snapshotFileURL) -> Bool {
        guard let fileURL else {
            return false
        }

        let sidecarURL = daySamplesFileURL(alongside: fileURL)
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
            return false
        }

        do {
            try FileManager.default.removeItem(at: sidecarURL)
            return true
        } catch {
            logger.error("Health dashboard day-sample sidecar truncate failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func delete(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) {
        defaults.removeObject(forKey: healthDashboardSnapshotKey)

        guard let fileURL else {
            return
        }

        for url in [fileURL, daySamplesFileURL(alongside: fileURL)]
        where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("Health dashboard snapshot file delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func loadFromFile(fileURL: URL?) -> LoadedSnapshot? {
        guard let fileURL else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Health dashboard snapshot file read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        return decode(data)
    }

    /// Decodes through the flat envelope so the snapshot and its
    /// summary-context signature come out of one tokenization pass. A pre-H2a
    /// file (or the legacy `UserDefaults` payload) simply has no signature key
    /// and yields nil for it.
    private static func decode(_ data: Data) -> LoadedSnapshot? {
        do {
            let persisted = try JSONDecoder().decode(PersistedDashboardSnapshot.self, from: data)
            // Refuse a file stamped by a schema this build does not know. Version 1 is
            // still accepted (and is also what a legacy file with no key means) because
            // the 1 to 2 bump changed no bytes on disk.
            let version = persisted.snapshot.schemaVersion ?? 1
            guard version == 1 || version == HealthDashboardSnapshot.currentSchemaVersion else {
                return nil
            }
            return LoadedSnapshot(
                snapshot: persisted.snapshot,
                summaryContextSignature: persisted.summaryContextSignature,
                metadata: persisted.envelopeVersion == 1 ? persisted.metadata : PersistenceMetadata()
            )
        } catch {
            logger.error("Health dashboard snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// On-disk envelope: the dashboard snapshot's own keys plus an optional
/// `summaryContextSignature` sibling, written flat so the signature rides inside
/// the snapshot atomically (H2a) — every save path carries it and `delete()`
/// removes it with the data. `HealthDashboardSnapshot` lives in a package this
/// store can't extend, so the wrapper merges the extra key into the snapshot's
/// top-level container on encode and reads it back on decode. An old file simply
/// lacks the metadata; its history survives, but unprovable progress and
/// freshness restart conservatively. Envelope versioning is independent of the
/// metrics package's payload schema. Identical envelopes still byte-dedupe.
private struct PersistedDashboardSnapshot: Codable {
    let snapshot: HealthDashboardSnapshot
    let summaryContextSignature: String?
    let envelopeVersion: Int?
    let metadata: HealthDashboardSnapshotStore.PersistenceMetadata

    private enum CodingKeys: String, CodingKey {
        case summaryContextSignature, envelopeVersion, metadata
    }

    init(snapshot: HealthDashboardSnapshot, summaryContextSignature: String?,
         metadata: HealthDashboardSnapshotStore.PersistenceMetadata) {
        self.snapshot = snapshot
        self.summaryContextSignature = summaryContextSignature
        self.envelopeVersion = 1
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        snapshot = try HealthDashboardSnapshot(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaryContextSignature = try container.decodeIfPresent(String.self, forKey: .summaryContextSignature)
        envelopeVersion = try? container.decodeIfPresent(Int.self, forKey: .envelopeVersion)
        metadata = (try? container.decodeIfPresent(HealthDashboardSnapshotStore.PersistenceMetadata.self, forKey: .metadata))
            ?? HealthDashboardSnapshotStore.PersistenceMetadata()
    }

    func encode(to encoder: Encoder) throws {
        try snapshot.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(summaryContextSignature, forKey: .summaryContextSignature)
        try container.encodeIfPresent(envelopeVersion, forKey: .envelopeVersion)
        try container.encode(metadata, forKey: .metadata)
    }
}

/// Minimal probe that reads ONLY the summary-context signature from the flat
/// envelope, so the launch-time restore doesn't rebuild the heavy snapshot
/// object graph. Unknown keys (summary/trends/…) are ignored; a missing key
/// decodes as nil.
private struct SummaryContextSignatureProbe: Decodable {
    let summaryContextSignature: String?
}
