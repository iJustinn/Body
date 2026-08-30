//
//  WorkoutRecordLedgerStore.swift
//  Body
//
//  The all-time personal-record ledger, as a single JSON file under app-private
//  Application Support. App-private rather than the App Group container because
//  no extension reads records — the badges are phone-app UI only.
//
//  Not thread-safe by design: callers serialize every mutation on the app's
//  persist queue, so the store carries no lock of its own.
//

import Foundation
import os

enum WorkoutRecordLedgerStore {
    private static let directoryName = "WorkoutRecords"
    private static let fileName = "ledger.json"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WorkoutRecordLedgerStore")

    static var defaultDirectoryURL: URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.error("Workout record ledger directory unavailable.")
            return nil
        }

        return applicationSupportURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Returns whether bytes were actually written — an unchanged ledger (a
    /// backfill chunk that contributed nothing) skips the write entirely.
    @discardableResult
    static func save(_ ledger: WorkoutRecordLedger, directoryURL: URL? = defaultDirectoryURL) -> Bool {
        guard let directoryURL else {
            return false
        }

        let data: Data
        do {
            // `.sortedKeys` plus the ledger's UUID-sorted contribution array make
            // the encoded bytes deterministic, so the byte-compare below actually
            // dedupes writes instead of rewriting the whole file every chunk.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(ledger)
        } catch {
            logger.error("Workout record ledger encode failed: \(error.localizedDescription, privacy: .public)")
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
            logger.error("Workout record ledger write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// `nil` when there is nothing usable at rest — no file, unreadable bytes, or
    /// a ledger written by a different schema. The caller starts a fresh ledger
    /// and rescans rather than trusting a shape it no longer understands.
    static func load(directoryURL: URL? = defaultDirectoryURL) -> WorkoutRecordLedger? {
        guard let directoryURL else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL(in: directoryURL))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Workout record ledger read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let ledger = try? JSONDecoder().decode(WorkoutRecordLedger.self, from: data),
              ledger.schemaVersion == WorkoutRecordLedger.currentSchemaVersion else {
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
            logger.error("Workout record ledger delete failed: \(error.localizedDescription, privacy: .public)")
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

    /// Excluded from backup on creation: every contribution is rebuildable from
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
