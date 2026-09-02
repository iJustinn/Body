//
//  BodySnapshotDirectory.swift
//  Body
//

import Foundation

/// Shared directory preparation for on-disk snapshot caches (workout month
/// snapshots, widget snapshots, health dashboard snapshots, workout detail
/// files). Every cache directory is excluded from device backups: the
/// contents are all rebuildable from HealthKit, so there's no reason for
/// them to ride along into an iCloud or iTunes backup. Usable from the app,
/// the widget extension, and any target that links BodyShared.
enum BodySnapshotDirectory {
    /// Creates `directory` if missing, then ensures it is excluded from
    /// backups. Runs the backup-exclusion check on every call (not just on
    /// creation) so a directory created by an older build, which predates
    /// this exclusion, gets the flag retroactively.
    static func prepare(_ directory: URL) throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var url = directory
        let isExcluded = (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup
        if isExcluded != true {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }
}
