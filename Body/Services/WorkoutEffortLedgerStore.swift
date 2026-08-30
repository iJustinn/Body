//
//  WorkoutEffortLedgerStore.swift
//  Body
//
//  The per-workout effort-score ledger, as a single JSON file under app-private
//  Application Support. App-private rather than the App Group container because
//  only the phone app's fetch engine reads it — the watch runs its own effort
//  query against HealthKit and never sees this file.
//
//  Mutations are serialized on the store's own persist queue (`enqueueSave`,
//  `deleteAll`), so the actor that owns the in-memory ledger never blocks on
//  disk and writes keep FIFO order with the delete a cache clear enqueues.
//

import Foundation
import os

/// One workout's remembered effort outcome. `effort` is `nil` for a workout
/// confirmed to carry no score, which is exactly as valuable to remember as a
/// found score: both let the next launch skip the per-workout query.
struct WorkoutEffortLedgerEntry: Codable, Equatable {
    var startDate: Date
    var endDate: Date
    var effort: Double?
}

/// The dates of a workout whose effort outcome is cached, kept alongside the
/// in-memory effort maps so entries can be scoped by month (the pull-to-refresh
/// clear) and by age (what may be persisted, and what has aged out of the
/// training-load window).
struct WorkoutEffortDateRange: Codable, Equatable {
    var startDate: Date
    var endDate: Date
}

struct WorkoutEffortLedger: Codable, Equatable {
    /// Bump when the stored shape changes; a mismatch on load discards and rescans.
    static let currentSchemaVersion = 1

    private(set) var schemaVersion: Int
    var entries: [UUID: WorkoutEffortLedgerEntry]

    init(entries: [UUID: WorkoutEffortLedgerEntry] = [:]) {
        schemaVersion = Self.currentSchemaVersion
        self.entries = entries
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case entries
    }

    /// `entries` persists as an array sorted by UUID string: a dictionary keyed
    /// by UUID encodes in hash order, which is not stable across launches and
    /// would defeat the byte-comparison dedupe on write.
    private struct StoredEntry: Codable {
        let id: UUID
        let entry: WorkoutEffortLedgerEntry

        enum CodingKeys: String, CodingKey {
            case id
            case startDate
            case endDate
            case effort
        }

        init(id: UUID, entry: WorkoutEffortLedgerEntry) {
            self.id = id
            self.entry = entry
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            entry = try WorkoutEffortLedgerEntry(from: decoder)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try entry.encode(to: encoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let stored = try container.decode([StoredEntry].self, forKey: .entries)
        entries = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.entry) })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        let stored = entries
            .map { StoredEntry(id: $0.key, entry: $0.value) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        try container.encode(stored, forKey: .entries)
    }
}

enum WorkoutEffortLedgerStore {
    private static let directoryName = "WorkoutEffort"
    private static let fileName = "ledger.json"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WorkoutEffortLedgerStore")

    /// Serial, so a save enqueued by one refresh and the delete enqueued by a
    /// cache clear land in the order they were requested.
    private static let persistQueue = DispatchQueue(label: "com.body.workoutEffortPersist", qos: .utility)

    static var defaultDirectoryURL: URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.error("Workout effort ledger directory unavailable.")
            return nil
        }

        return applicationSupportURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Fire-and-forget write on the persist queue. Callers hold the ledger on an
    /// actor and must not block it on disk; an unchanged ledger skips the write
    /// entirely inside `save`.
    static func enqueueSave(_ ledger: WorkoutEffortLedger) {
        persistQueue.async {
            save(ledger)
        }
    }

    /// Enqueues the delete and waits for it, so a caller clearing its in-memory
    /// maps can guarantee no earlier save is still queued behind the wipe.
    static func deleteAllAndWait() async {
        await withCheckedContinuation { continuation in
            persistQueue.async {
                deleteAll()
                continuation.resume()
            }
        }
    }

    /// Returns whether bytes were actually written — a refresh that learned
    /// nothing new skips the write entirely.
    @discardableResult
    static func save(_ ledger: WorkoutEffortLedger, directoryURL: URL? = defaultDirectoryURL) -> Bool {
        guard let directoryURL else {
            return false
        }

        let data: Data
        do {
            // `.sortedKeys` plus the ledger's UUID-sorted entry array make the
            // encoded bytes deterministic, so the byte-compare below actually
            // dedupes writes instead of rewriting the file every refresh.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(ledger)
        } catch {
            logger.error("Workout effort ledger encode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let fileURL = fileURL(in: directoryURL)
        if let existing = try? Data(contentsOf: fileURL), existing == data {
            return false
        }

        do {
            try createDirectoryIfNeeded(directoryURL)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            logger.error("Workout effort ledger write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// `nil` when there is nothing usable at rest — no file, unreadable bytes, or
    /// a ledger written by a different schema. The caller starts empty and
    /// re-queries rather than trusting a shape it no longer understands.
    static func load(directoryURL: URL? = defaultDirectoryURL) -> WorkoutEffortLedger? {
        guard let directoryURL else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL(in: directoryURL))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Workout effort ledger read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let ledger = try? JSONDecoder().decode(WorkoutEffortLedger.self, from: data),
              ledger.schemaVersion == WorkoutEffortLedger.currentSchemaVersion else {
            return nil
        }
        return ledger
    }

    static func deleteAll(directoryURL: URL? = defaultDirectoryURL) {
        guard let directoryURL, FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: directoryURL)
        } catch {
            logger.error("Workout effort ledger delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func totalDiskSizeBytes(directoryURL: URL? = defaultDirectoryURL) -> Int64 {
        guard let directoryURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: directoryURL,
                  includingPropertiesForKeys: [.fileSizeKey]
              ) else {
            return 0
        }

        return contents.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
    }

    private static func fileURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    /// Excluded from backup on creation: every entry is rebuildable from
    /// HealthKit, so the ledger shouldn't ride along into iCloud backups.
    private static func createDirectoryIfNeeded(_ directoryURL: URL) throws {
        if FileManager.default.fileExists(atPath: directoryURL.path) { return }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var url = directoryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
