//
//  WorkoutSnapshotStore.swift
//  Body
//

import Foundation
import os

enum WorkoutSnapshotStore {
    static let appGroupIdentifier = "group.com.zihengthedeveloper.Body"
    /// The two pre-6-month file names. They are no longer written; they stay so
    /// `load(month:year:)` can still answer from a cache written by an older
    /// build (widgets and the watch weekly fallback keep working between the
    /// app update and the first refresh) and so the app can delete them once
    /// the month-keyed files land.
    static let currentMonthSnapshotFileName = "currentMonthWorkoutSnapshot.json"
    static let previousMonthSnapshotFileName = "previousMonthWorkoutSnapshot.json"
    static let monthSnapshotsDirectoryName = "WorkoutMonthSnapshots"
    /// Current month plus five back. The window bounds both what launch seeds
    /// into memory and what `pruneOutsideWindow` keeps on disk.
    static let persistedMonthCount = 6
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WorkoutSnapshotStore")

    static var sharedContainerURL: URL? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return nil
        }
        #endif

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            logger.error("App group container unavailable for \(appGroupIdentifier, privacy: .public)")
            return nil
        }

        return containerURL
    }

    /// One `YYYY-MM.json` file per persisted month.
    static var monthSnapshotsDirectoryURL: URL? {
        sharedContainerURL?.appendingPathComponent(monthSnapshotsDirectoryName, isDirectory: true)
    }

    // MARK: - Month file addressing

    /// - Parameter directoryURL: the month-snapshot directory; injectable so
    ///   tests never touch the real App Group.
    static func fileURL(month: Int, year: Int, directoryURL: URL? = monthSnapshotsDirectoryURL) -> URL? {
        guard let directoryURL else {
            return nil
        }
        return directoryURL.appendingPathComponent(String(format: "%04d-%02d.json", year, month))
    }

    /// Parses a `YYYY-MM.json` file name. Anything else (a stray file, a name
    /// from a future scheme) returns nil and is treated as prunable.
    static func monthKey(fromFileName fileName: String) -> (month: Int, year: Int)? {
        guard fileName.hasSuffix(".json") else {
            return nil
        }
        let stem = String(fileName.dropLast(5))
        let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 4,
              parts[1].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else {
            return nil
        }
        return (month, year)
    }

    /// The legacy pair lives one level up from the month directory (both sit in
    /// the App Group container), so redirecting `directoryURL` in a test
    /// redirects the legacy files with it.
    private static func legacyFileURLs(directoryURL: URL?) -> (current: URL, previous: URL)? {
        guard let directoryURL else {
            return nil
        }
        let containerURL = directoryURL.deletingLastPathComponent()
        return (
            containerURL.appendingPathComponent(currentMonthSnapshotFileName),
            containerURL.appendingPathComponent(previousMonthSnapshotFileName)
        )
    }

    /// The current month's file for `Date()`. Kept as a computed var so the
    /// `exists` / `fileSize` / `delete` / `loadOrEmpty` defaults keep working.
    static var snapshotFileURL: URL? {
        fileURL(for: Date(), monthsBack: 0)
    }

    static var previousSnapshotFileURL: URL? {
        fileURL(for: Date(), monthsBack: 1)
    }

    private static func fileURL(for date: Date, monthsBack: Int, directoryURL: URL? = monthSnapshotsDirectoryURL) -> URL? {
        let calendar = Calendar.bodyGregorian
        guard let anchor = calendar.date(byAdding: .month, value: -monthsBack, to: date) else {
            return nil
        }
        return fileURL(
            month: calendar.component(.month, from: anchor),
            year: calendar.component(.year, from: anchor),
            directoryURL: directoryURL
        )
    }

    /// Newest first: index 0 is the month containing `now`.
    private static func windowKeys(now: Date, calendar: Calendar) -> [(month: Int, year: Int)] {
        (0..<persistedMonthCount).compactMap { offset in
            guard let anchor = calendar.date(byAdding: .month, value: -offset, to: now) else {
                return nil
            }
            return (month: calendar.component(.month, from: anchor), year: calendar.component(.year, from: anchor))
        }
    }

    // MARK: - Save

    @discardableResult
    static func save(_ snapshot: WorkoutMonthSnapshot) -> Bool {
        save(snapshot, fileURL: fileURL(month: snapshot.month, year: snapshot.year))
    }

    @discardableResult
    static func save(_ snapshot: WorkoutMonthSnapshot, fileURL: URL?) -> Bool {
        guard let fileURL else {
            logger.error("Snapshot save skipped because shared snapshot file URL is unavailable.")
            return false
        }

        let data: Data
        do {
            // `.sortedKeys` keeps the encoded bytes deterministic so the
            // save-if-changed compare below actually dedupes writes;
            // `JSONEncoder` randomizes key order between calls otherwise.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(snapshot)
        } catch {
            logger.error("Snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        if let existing = try? Data(contentsOf: fileURL) {
            if existing == data {
                return false
            }
            // A periodic re-save with unchanged content still gets a fresh
            // `generatedAt` from the caller, which would otherwise defeat the
            // byte-compare above and bump `generatedAt` on every call — and
            // `generatedAt` doubles as a cache key (search corpus, clear-cache
            // dedupe). Re-encode the incoming snapshot with the on-disk
            // `generatedAt` substituted in; if that now matches the on-disk
            // bytes, the content is unchanged and the write (and its new
            // timestamp) is skipped.
            if let existingSnapshot = try? JSONDecoder().decode(WorkoutMonthSnapshot.self, from: existing) {
                let restampedSnapshot = WorkoutMonthSnapshot(
                    month: snapshot.month,
                    year: snapshot.year,
                    generatedAt: existingSnapshot.generatedAt,
                    days: snapshot.days,
                    schemaVersion: snapshot.schemaVersion
                )
                let restampedEncoder = JSONEncoder()
                restampedEncoder.outputFormatting = [.sortedKeys]
                if let restamped = try? restampedEncoder.encode(restampedSnapshot), restamped == existing {
                    return false
                }
            }
        }

        do {
            try BodySnapshotDirectory.prepare(fileURL.deletingLastPathComponent())
            // Complete-until-first-unlock protection: the widget timeline and
            // background refresh both read this file while the device may be
            // locked, so `.completeUnlessOpen` would break those reads.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            logger.error("Snapshot file write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Load

    static func load() -> WorkoutMonthSnapshot? {
        load(monthsBack: 0)
    }

    static func loadPrevious() -> WorkoutMonthSnapshot? {
        load(monthsBack: 1)
    }

    private static func load(monthsBack: Int, now: Date = Date()) -> WorkoutMonthSnapshot? {
        let calendar = Calendar.bodyGregorian
        guard let anchor = calendar.date(byAdding: .month, value: -monthsBack, to: now) else {
            return nil
        }
        return load(
            month: calendar.component(.month, from: anchor),
            year: calendar.component(.year, from: anchor)
        )
    }

    /// The month file, falling back to the legacy two-file cache when the month
    /// file is missing: right after an update the legacy files are all there is
    /// until the first refresh writes the month directory. Only a legacy file
    /// whose own `month`/`year` match is accepted, so a stale "current" file
    /// left over from last month can never answer for this month.
    static func load(month: Int, year: Int, directoryURL: URL? = monthSnapshotsDirectoryURL) -> WorkoutMonthSnapshot? {
        if let snapshot = load(fileURL: fileURL(month: month, year: year, directoryURL: directoryURL)) {
            return snapshot
        }
        return loadLegacy(month: month, year: year, directoryURL: directoryURL)
    }

    private static func loadLegacy(month: Int, year: Int, directoryURL: URL?) -> WorkoutMonthSnapshot? {
        guard let legacy = legacyFileURLs(directoryURL: directoryURL) else {
            return nil
        }
        for url in [legacy.current, legacy.previous] {
            if let snapshot = load(fileURL: url), snapshot.month == month, snapshot.year == year {
                return snapshot
            }
        }
        return nil
    }

    /// Every persisted month inside the window, newest first (index 0 is the
    /// month containing `now`). Months with no file, and files outside the
    /// window, are skipped.
    static func loadPersistedMonths(
        now: Date = Date(),
        calendar: Calendar = .bodyGregorian,
        directoryURL: URL? = monthSnapshotsDirectoryURL
    ) -> [WorkoutMonthSnapshot] {
        windowKeys(now: now, calendar: calendar).compactMap {
            load(month: $0.month, year: $0.year, directoryURL: directoryURL)
        }
    }

    /// Memoizes decoded snapshots keyed by file identity (mtime + size) so the
    /// widget extension's repeated timeline passes don't re-read and re-decode
    /// the same App-Group JSON. Lock-protected because widget providers may call
    /// `load` concurrently (project is Swift 5 language mode, no strict
    /// concurrency). Every `load` re-stats the file, so a cross-process rewrite
    /// (atomic write → new mtime) invalidates the entry. Every load funnel
    /// routes through `load(fileURL:)`.
    private final class LoadCache {
        private let lock = NSLock()
        private var entries: [URL: (modificationDate: Date, fileSize: Int, snapshot: WorkoutMonthSnapshot)] = [:]

        func snapshot(for url: URL, modificationDate: Date, fileSize: Int) -> WorkoutMonthSnapshot? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[url],
                  entry.modificationDate == modificationDate,
                  entry.fileSize == fileSize else {
                return nil
            }
            return entry.snapshot
        }

        func store(_ snapshot: WorkoutMonthSnapshot, for url: URL, modificationDate: Date, fileSize: Int) {
            lock.lock()
            entries[url] = (modificationDate, fileSize, snapshot)
            lock.unlock()
        }

        func remove(_ url: URL) {
            lock.lock()
            entries.removeValue(forKey: url)
            lock.unlock()
        }
    }

    private static let loadCache = LoadCache()

    static func load(fileURL: URL?) -> WorkoutMonthSnapshot? {
        guard let fileURL else {
            logger.error("Snapshot load skipped because shared snapshot file URL is unavailable.")
            return nil
        }

        // Stat before reading so a cache hit skips the read+decode, and a store
        // records the identity the decoded bytes actually came from. FileManager
        // (not URL.resourceValues) because URL caches resource values per
        // instance — a stale hit there would mask a rewrite behind the same URL.
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue
        if let modificationDate,
           let fileSize,
           let cached = loadCache.snapshot(for: fileURL, modificationDate: modificationDate, fileSize: fileSize) {
            return cached
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            loadCache.remove(fileURL)
            return nil
        } catch {
            logger.error("Snapshot file read failed: \(error.localizedDescription, privacy: .public)")
            loadCache.remove(fileURL)
            return nil
        }

        do {
            let snapshot = try JSONDecoder().decode(WorkoutMonthSnapshot.self, from: data)
            // A file written by a newer schema can decode without error yet mean
            // something different, so refuse it instead of caching it. A legacy file
            // with no version key is schema 1.
            guard (snapshot.schemaVersion ?? 1) == WorkoutMonthSnapshot.currentSchemaVersion else {
                loadCache.remove(fileURL)
                return nil
            }
            if let modificationDate, let fileSize {
                loadCache.store(snapshot, for: fileURL, modificationDate: modificationDate, fileSize: fileSize)
            }
            return snapshot
        } catch {
            logger.error("Snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            loadCache.remove(fileURL)
            return nil
        }
    }

    /// A truthful "no data yet" load for production init: the cached
    /// current-month snapshot when present, otherwise an honest empty
    /// snapshot — unlike `.placeholder`, never fabricated sample workouts. Use
    /// this for default init values that can outlive HealthKit authorization
    /// (e.g. a fresh install with no cache), so the user never sees sample
    /// workouts presented as their real history.
    static func loadOrEmpty(fileURL: URL? = snapshotFileURL) -> WorkoutMonthSnapshot {
        load(fileURL: fileURL) ?? .makeEmpty()
    }

    /// - Parameter usePlaceholderWhenEmpty: `true` (widget gallery /
    ///   `context.isPreview` only) keeps the representative cascade — current
    ///   file with data, else previous-month file with data, else the
    ///   fabricated sample `.placeholder`. `false` (live timelines) always
    ///   returns the real current month for `now`: the on-disk "current" file
    ///   only when its month/year match, else an honest empty snapshot — so
    ///   right after a month rolls over, neither a stale current file (still
    ///   last month's data until the app refreshes) nor the previous-month
    ///   file can present old workouts as this month, and a fresh install
    ///   never renders sample workouts as if they were real.
    /// - Parameter now: anchors which month counts as "current"; injectable
    ///   for tests.
    /// - Parameters currentFileURL/previousFileURL: overridable for tests;
    ///   production callers use the shared App Group files.
    static func loadCurrentOrPreviousIfEmpty(
        usePlaceholderWhenEmpty: Bool,
        now: Date = Date(),
        currentFileURL: URL? = snapshotFileURL,
        previousFileURL: URL? = previousSnapshotFileURL
    ) -> WorkoutMonthSnapshot {
        let calendar = Calendar.bodyGregorian
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        let current = loadAllowingLegacy(fileURL: currentFileURL, month: currentMonth, year: currentYear)

        if usePlaceholderWhenEmpty {
            if let current, current.workoutCount > 0 {
                return current
            }
            let previousAnchor = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let previous = loadAllowingLegacy(
                fileURL: previousFileURL,
                month: calendar.component(.month, from: previousAnchor),
                year: calendar.component(.year, from: previousAnchor)
            )
            if let previous, previous.workoutCount > 0 {
                return previous
            }
            return current ?? .makePlaceholder(generatedAt: now, calendar: calendar)
        }

        if let current,
           current.month == currentMonth,
           current.year == currentYear {
            return current
        }
        return .makeEmpty(generatedAt: now, calendar: calendar)
    }

    /// Reads `fileURL`, and when that misses and the URL is the production month
    /// file for this month, falls back to the legacy pair. Tests that inject
    /// their own scratch URLs get the plain file read.
    private static func loadAllowingLegacy(fileURL url: URL?, month: Int, year: Int) -> WorkoutMonthSnapshot? {
        if let snapshot = load(fileURL: url) {
            return snapshot
        }
        guard url == fileURL(month: month, year: year) else {
            return nil
        }
        return loadLegacy(month: month, year: year, directoryURL: monthSnapshotsDirectoryURL)
    }

    // MARK: - Maintenance

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
        diskSizeBytes(directoryURL: monthSnapshotsDirectoryURL)
    }

    /// Every month file plus any legacy file still on disk, so Settings reports
    /// the whole workout cache during the window where both exist.
    static func diskSizeBytes(directoryURL: URL?) -> Int64 {
        var total = directoryContents(directoryURL: directoryURL).reduce(Int64(0)) { $0 + fileSize(at: $1) }
        if let legacy = legacyFileURLs(directoryURL: directoryURL) {
            total += fileSize(at: legacy.current) + fileSize(at: legacy.previous)
        }
        return total
    }

    private static func directoryContents(directoryURL: URL?) -> [URL] {
        guard let directoryURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }
        return contents
    }

    static func delete(fileURL: URL? = snapshotFileURL) {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
            // The memoized decode outlives the file otherwise: a later save can
            // land on the same mtime+size and serve the pre-delete snapshot.
            loadCache.remove(fileURL)
        } catch {
            logger.error("Snapshot file delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops month files outside the persisted window, plus any file whose name
    /// isn't a `YYYY-MM.json` key. An in-window file is never removed just
    /// because memory lacks that month.
    static func pruneOutsideWindow(
        now: Date = Date(),
        calendar: Calendar = .bodyGregorian,
        directoryURL: URL? = monthSnapshotsDirectoryURL
    ) {
        let keep = Set(windowKeys(now: now, calendar: calendar).map { "\($0.year)-\($0.month)" })
        for url in directoryContents(directoryURL: directoryURL) {
            guard let key = monthKey(fromFileName: url.lastPathComponent) else {
                delete(fileURL: url)
                continue
            }
            if !keep.contains("\(key.year)-\(key.month)") {
                delete(fileURL: url)
            }
        }
    }

    /// Load-modify-writes every month file on disk (permission strip, opt-out
    /// "emptied" rewrite). Returns whether any write actually changed bytes,
    /// so the caller can skip a widget reload when nothing moved.
    @discardableResult
    static func mapPersistedMonths(
        directoryURL: URL? = monthSnapshotsDirectoryURL,
        _ transform: (WorkoutMonthSnapshot) -> WorkoutMonthSnapshot
    ) -> Bool {
        var changed = false
        for url in directoryContents(directoryURL: directoryURL) {
            guard monthKey(fromFileName: url.lastPathComponent) != nil,
                  let snapshot = load(fileURL: url) else {
                continue
            }
            if save(transform(snapshot), fileURL: url) {
                changed = true
            }
        }
        return changed
    }

    /// Removes the pre-6-month pair. Called only after the month-keyed writes
    /// land, so the fallback in `load(month:year:)` is never the only copy.
    static func deleteLegacyFiles(directoryURL: URL? = monthSnapshotsDirectoryURL) {
        guard let legacy = legacyFileURLs(directoryURL: directoryURL) else {
            return
        }
        delete(fileURL: legacy.current)
        delete(fileURL: legacy.previous)
    }

    /// Clear Cache: every month file, the month directory itself, and the
    /// legacy pair.
    static func deleteAll(directoryURL: URL? = monthSnapshotsDirectoryURL) {
        // Delete the files first so their memoized decodes are evicted, then
        // drop the (now empty) directory.
        for url in directoryContents(directoryURL: directoryURL) {
            delete(fileURL: url)
        }
        if let directoryURL, FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.removeItem(at: directoryURL)
            } catch {
                logger.error("Snapshot directory delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        deleteLegacyFiles(directoryURL: directoryURL)
    }
}
