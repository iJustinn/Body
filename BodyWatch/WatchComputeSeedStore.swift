//
//  WatchComputeSeedStore.swift
//  BodyWatch
//
//  On-watch cache for the phone's compute seed (`WatchComputeSeed`, delivered
//  compressed in the WatchConnectivity context). Mirrors
//  `WatchMetricsSnapshotStore`'s pattern — deterministic bytes, save-if-changed
//  — with one deliberate difference: this lives in the WATCH APP's OWN
//  container, not the App Group.
//
//  The App Group exists so the widget extension can read the display snapshot;
//  the complications never compute anything, so they never read the seed, and
//  putting a ~30 KB blob in the shared container would only enlarge what every
//  complication timeline pass has to stat around. Application Support (not
//  Caches) because a purge would silently disable on-watch compute until the
//  next phone publish.
//
//  The stored bytes are the compressed payload exactly as received, so the
//  change check is a straight byte compare against what the phone sent — no
//  re-encode, and no risk of a re-encode changing bytes that were equal.
//

import Foundation
import os

enum WatchComputeSeedStore {
    static let seedFileName = "watchComputeSeed.zlib"
    private static let logger = Logger(
        subsystem: "com.zihengthedeveloper.Body",
        category: "WatchComputeSeedStore"
    )

    /// The watch app's own Application Support directory (created on demand).
    static var containerURL: URL? {
        guard let containerURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.error("Application Support container unavailable.")
            return nil
        }
        return containerURL
    }

    static var seedFileURL: URL? {
        containerURL?.appendingPathComponent(seedFileName)
    }

    /// Whether a seed is on disk. Cheap enough (a stat) for the recompute gate
    /// to consult on the main actor before handing off to the coordinator,
    /// which does the read + decompress + decode off it.
    static func hasStoredSeed(fileURL: URL? = seedFileURL) -> Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Persists the compressed seed payload. Returns `true` only when the bytes
    /// CHANGED — the caller bumps the compute generation on that signal, so an
    /// identical republish (the phone re-sends the same seed on every
    /// settings-only publish) doesn't discard an in-flight compute.
    ///
    /// `decoded` is the seed the intake ALREADY decoded from these exact bytes.
    /// Passing it primes the decode memo below, so the compute's next `load()`
    /// hits instead of repeating the zlib decompress plus JSON parse the intake
    /// just did (M-34).
    @discardableResult
    static func save(_ data: Data, decoded: WatchComputeSeed? = nil, fileURL: URL? = seedFileURL) -> Bool {
        guard let fileURL else {
            logger.error("Save skipped: seed file URL unavailable.")
            return false
        }

        if let existing = try? Data(contentsOf: fileURL), existing == data {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            if let decoded {
                decodeMemoLock.lock()
                memoizedSeedData = data
                memoizedSeed = decoded
                decodeMemoLock.unlock()
            }
            return true
        } catch {
            logger.error("Seed file write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func loadData(fileURL: URL? = seedFileURL) -> Data? {
        guard let fileURL else { return nil }
        do {
            return try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Seed file read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Last decode, keyed by the exact bytes it came from. The live HR/HRV path
    /// resolves its source predicate from the seed's settings on EVERY refresh
    /// (`WatchHealthStore.liveSourceReads`), and a full decode is a zlib
    /// decompression plus a JSON parse of ~70 days of trends — far too much to
    /// repeat for two `HKSource` predicates. Keyed by bytes rather than
    /// invalidated by hand so a replaced seed can never be served from here:
    /// different bytes simply miss.
    private static let decodeMemoLock = NSLock()
    private static var memoizedSeedData: Data?
    private static var memoizedSeed: WatchComputeSeed?

    /// The stored seed, or `nil` when there is none, it can't be decoded, or it
    /// was written by an incompatible schema. The schema check mirrors the
    /// intake's (`WatchMetricsModel.seedIntake`) — a seed already on disk from
    /// an older/newer build must be refused at the same boundary the incoming
    /// one is, or the compute would run against a shape it can't reproduce.
    static func load(fileURL: URL? = seedFileURL) -> WatchComputeSeed? {
        guard let data = loadData(fileURL: fileURL) else { return nil }

        decodeMemoLock.lock()
        if memoizedSeedData == data, let memoizedSeed {
            defer { decodeMemoLock.unlock() }
            return memoizedSeed
        }
        decodeMemoLock.unlock()

        guard let seed = WatchComputeSeed.decoded(from: data),
              seed.schemaVersion == WatchComputeSeed.currentSchemaVersion else {
            return nil
        }

        decodeMemoLock.lock()
        memoizedSeedData = data
        memoizedSeed = seed
        decodeMemoLock.unlock()
        return seed
    }

    /// Removes the stored seed (Clear Cache / reset tombstone). Returns whether
    /// a file was actually removed — informational; the caller bumps the compute
    /// generation on a tombstone regardless, because a compute already in flight
    /// is holding its own decoded copy of the seed that deleting the file can't
    /// reach.
    @discardableResult
    static func clear(fileURL: URL? = seedFileURL) -> Bool {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            logger.error("Seed file removal failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
