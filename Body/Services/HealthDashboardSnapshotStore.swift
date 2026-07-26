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
    static let activityRingBackfillCompletedKey = "lastHealthDashboardActivityRingBackfillCompleted"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "HealthDashboardSnapshotStore")

    static func saveSecondarySelectionSignature(_ signature: String, defaults: UserDefaults = .standard) {
        defaults.set(signature, forKey: secondarySelectionSignatureKey)
    }

    static func loadSecondarySelectionSignature(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: secondarySelectionSignatureKey)
    }

    /// Persisted timestamp of the last successful HealthKit refresh. Loaded at
    /// launch so the cold-start sync path can route through the same tiered
    /// TTL as a warm scene-phase resume: < 60 s → skip, < 5 min → current-month
    /// only, ≥ 5 min → full refresh. Without persistence, every cold start
    /// looked like "never refreshed before" and always paid the full refresh
    /// cost even when the on-disk snapshot was seconds old.
    static func saveLastSuccessfulRefreshDate(_ date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastSuccessfulRefreshDateKey)
    }

    static func loadLastSuccessfulRefreshDate(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastSuccessfulRefreshDateKey) as? Date
    }

    static func clearLastSuccessfulRefreshDate(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastSuccessfulRefreshDateKey)
    }

    /// One-shot marker for the first-load activity-ring backfill (up to ten
    /// years in one scan). While unset, the dashboard refresh fetches the
    /// full backfill window instead of the recent chart months; set only
    /// once that fetch succeeds. Cleared with the cache so a wiped snapshot
    /// gets backfilled again.
    static func saveActivityRingBackfillCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: activityRingBackfillCompletedKey)
    }

    static func loadActivityRingBackfillCompleted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: activityRingBackfillCompletedKey)
    }

    static func clearActivityRingBackfillCompleted(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: activityRingBackfillCompletedKey)
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

    @discardableResult
    static func save(
        _ snapshot: HealthDashboardSnapshot,
        daySampleSignatures: HealthTrendDaySampleSignatures? = nil,
        summaryContextSignature: String? = nil,
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> Bool {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DashboardSnapshotSave")
        defer { BodyPerformanceSignposts.signposter.endInterval("DashboardSnapshotSave", signpostState) }

        guard let fileURL else {
            logger.error("Health dashboard snapshot file save skipped because file URL is unavailable.")
            return false
        }

        let mainSnapshot = HealthDashboardSnapshot(
            summary: snapshot.summary,
            trends: snapshot.trends.strippingDaySamples(),
            activityRingHistory: snapshot.activityRingHistory
        )
        let data: Data
        do {
            data = try makeSnapshotEncoder().encode(
                PersistedDashboardSnapshot(
                    snapshot: mainSnapshot,
                    summaryContextSignature: summaryContextSignature
                )
            )
        } catch {
            logger.error("Health dashboard snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        var didWrite = false
        if (try? Data(contentsOf: fileURL)) != data {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: [.atomic])
                didWrite = true
            } catch {
                logger.error("Health dashboard snapshot file write failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        defaults.removeObject(forKey: healthDashboardSnapshotKey)

        if saveDaySamples(
            HealthTrendDaySampleSnapshot(trends: snapshot.trends, signatures: daySampleSignatures),
            alongside: fileURL
        ) {
            didWrite = true
        }
        return didWrite
    }

    private static func saveDaySamples(
        _ daySamples: HealthTrendDaySampleSnapshot,
        alongside fileURL: URL
    ) -> Bool {
        let sidecarURL = daySamplesFileURL(alongside: fileURL)
        if daySamples.isEmpty, !FileManager.default.fileExists(atPath: sidecarURL.path) {
            return false
        }

        let data: Data
        do {
            data = try makeSnapshotEncoder().encode(daySamples)
        } catch {
            logger.error("Health dashboard day-sample encode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        if let existing = try? Data(contentsOf: sidecarURL), existing == data {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: sidecarURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: sidecarURL, options: [.atomic])
            return true
        } catch {
            logger.error("Health dashboard day-sample file write failed: \(error.localizedDescription, privacy: .public)")
            return false
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

    static func load(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> HealthDashboardSnapshot? {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DashboardSnapshotLoad")
        defer { BodyPerformanceSignposts.signposter.endInterval("DashboardSnapshotLoad", signpostState) }

        if let snapshot = loadFromFile(fileURL: fileURL) {
            return snapshot
        }

        guard let legacyData = defaults.data(forKey: healthDashboardSnapshotKey) else {
            return nil
        }

        guard let legacySnapshot = decode(legacyData) else {
            defaults.removeObject(forKey: healthDashboardSnapshotKey)
            return nil
        }

        save(legacySnapshot, defaults: defaults, fileURL: fileURL)
        return legacySnapshot
    }

    static func loadOrEmpty(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> HealthDashboardSnapshot {
        load(defaults: defaults, fileURL: fileURL) ?? .empty
    }

    /// The summary-context signature persisted alongside the snapshot (H2a),
    /// restored into the store's summary-reuse gate at launch so a cold-start
    /// failed summary leaf can reuse the persisted value only while the current
    /// selection/prefs still match the ones it was saved under. `nil` for a
    /// snapshot written before this field existed (→ conservative empty-on-
    /// failure until the first refresh re-stamps it).
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

    private static func loadFromFile(fileURL: URL?) -> HealthDashboardSnapshot? {
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

    private static func decode(_ data: Data) -> HealthDashboardSnapshot? {
        do {
            return try JSONDecoder().decode(HealthDashboardSnapshot.self, from: data)
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
/// top-level container on encode and reads it back on decode. An old file (and
/// the plain `HealthDashboardSnapshot` decode in `load`) simply lacks/ignores the
/// key; the signature decodes as nil. With a nil signature `encodeIfPresent`
/// omits the key, so the bytes stay identical to the pre-H2a format (the
/// save-if-changed compare still reports "unchanged").
private struct PersistedDashboardSnapshot: Codable {
    let snapshot: HealthDashboardSnapshot
    let summaryContextSignature: String?

    private enum CodingKeys: String, CodingKey {
        case summaryContextSignature
    }

    init(snapshot: HealthDashboardSnapshot, summaryContextSignature: String?) {
        self.snapshot = snapshot
        self.summaryContextSignature = summaryContextSignature
    }

    init(from decoder: Decoder) throws {
        snapshot = try HealthDashboardSnapshot(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaryContextSignature = try container.decodeIfPresent(String.self, forKey: .summaryContextSignature)
    }

    func encode(to encoder: Encoder) throws {
        try snapshot.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(summaryContextSignature, forKey: .summaryContextSignature)
    }
}

/// Minimal probe that reads ONLY the summary-context signature from the flat
/// envelope, so the launch-time restore doesn't rebuild the heavy snapshot
/// object graph. Unknown keys (summary/trends/…) are ignored; a missing key
/// decodes as nil.
private struct SummaryContextSignatureProbe: Decodable {
    let summaryContextSignature: String?
}
