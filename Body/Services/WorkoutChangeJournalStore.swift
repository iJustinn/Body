import Foundation

/// One owner serializes these calls. Encoding and replacement never suspend.
enum WorkoutChangeJournalStore {
    // Enabled after physical repair acceptance; not a preference or launch argument.
    static let lifecycleEnabled = true
    static var defaultFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WorkoutJournal", isDirectory: true).appendingPathComponent("journal.json")
    }
    enum SaveResult { case written, unchanged, failed }

    static func diskSizeBytes(file: URL?) -> Int64 {
        guard let file, let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return Int64(size)
    }

    static func load(file: URL) -> WorkoutChangeJournal? {
        guard let bytes = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(WorkoutChangeJournal.self, from: bytes),
              value.schema == WorkoutChangeJournal.currentSchema else { return nil }
        return value
    }

    static func save(_ value: WorkoutChangeJournal, file: URL,
        write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) -> SaveResult {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(value)
            if (try? Data(contentsOf: file)) == bytes { return .unchanged }
            var directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try write(bytes, file)
            return .written
        } catch { return .failed }
    }
}
