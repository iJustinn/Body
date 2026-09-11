import Foundation

/// Only quantity/sleep/derived-input domain generations live here. Workout
/// intervals, ring cursors and authoritative sidecar coverage keep their owners.
/// A callback has no interval, so current success cannot erase historical work.
actor BodyHealthDirtyWorkStore {
    struct Entry: Codable, Equatable, Sendable {
        var generation: UInt64
        var context: String
        var currentPending = true
        var historyPending = true
    }
    struct Envelope: Codable, Equatable, Sendable {
        var schema = 1
        var resetID = UUID()
        var revision: UInt64 = 0
        var entries: [String: Entry] = [:]
    }
    struct Receipt: Equatable, Sendable {
        let resetID: UUID
        let domain: String
        let generation: UInt64
        let context: String
    }

    private let file: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private var envelope: Envelope
    private var needsSave: Bool

    /// Missing or invalid storage conservatively dirties every admitted domain.
    /// The caller supplies the current eligibility set; no health values persist.
    init(file: URL, domains: Set<HealthMetricKind>, context: String,
         write: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.file = file
        self.write = write
        let allowed = Set(domains.map(\.rawValue))
        if let bytes = try? Data(contentsOf: file),
           var loaded = try? JSONDecoder().decode(Envelope.self, from: bytes),
           loaded.schema == 1, loaded.revision < UInt64.max,
           loaded.entries.values.allSatisfy({ $0.generation > 0 && $0.generation <= loaded.revision }) {
            let previous = loaded
            loaded.entries = loaded.entries.filter { allowed.contains($0.key) }
            for domain in allowed where loaded.entries[domain]?.context != context {
                loaded.revision += 1
                loaded.entries[domain] = Entry(generation: loaded.revision, context: context)
            }
            envelope = loaded
            needsSave = loaded != previous
        } else {
            envelope = Envelope(revision: 1, entries: Dictionary(uniqueKeysWithValues:
                allowed.map { ($0, Entry(generation: 1, context: context)) }))
            needsSave = true
        }
    }

    func snapshot() -> Envelope { envelope }

    func receipt(for kind: HealthMetricKind) -> Receipt? {
        guard let entry = envelope.entries[kind.rawValue] else { return nil }
        return Receipt(resetID: envelope.resetID, domain: kind.rawValue,
                       generation: entry.generation, context: entry.context)
    }

    /// Memory retains failed writes; a later capture/flush can retry. Callers
    /// must still complete observer callbacks, and force foreground reconciliation
    /// after failure instead of assuming HealthKit will redeliver the event.
    @discardableResult
    func mark(_ kinds: Set<HealthMetricKind>, context: String) -> Bool {
        guard !kinds.isEmpty else { return flush() }
        if envelope.revision == .max {
            envelope.resetID = UUID()
            envelope.revision = 1
            envelope.entries = envelope.entries.mapValues { Entry(generation: 1, context: $0.context) }
        } else {
            envelope.revision += 1
        }
        for kind in kinds {
            envelope.entries[kind.rawValue] = Entry(generation: envelope.revision, context: context)
        }
        needsSave = true
        return flush()
    }

    /// Payload must already be durably saved under this receipt's context.
    /// A concurrent newer event/reset/context leaves its obligation untouched.
    @discardableResult
    func acknowledge(_ receipt: Receipt, current: Bool, history: Bool) -> Bool {
        guard !needsSave, receipt.resetID == envelope.resetID,
              var entry = envelope.entries[receipt.domain],
              entry.generation == receipt.generation, entry.context == receipt.context else { return false }
        if current { entry.currentPending = false }
        if history { entry.historyPending = false }
        var next = envelope
        next.entries[receipt.domain] = entry
        guard save(next) else { return false }
        envelope = next
        return true
    }

    func synchronize(domains: Set<HealthMetricKind>, context: String) -> Bool {
        let allowed = Set(domains.map(\.rawValue))
        let previous = envelope
        envelope.entries = envelope.entries.filter { allowed.contains($0.key) }
        let changed = domains.filter { envelope.entries[$0.rawValue]?.context != context }
        if envelope != previous { needsSave = true }
        return mark(changed, context: context)
    }

    @discardableResult
    func reset(domains: Set<HealthMetricKind>, context: String) -> Bool {
        envelope = Envelope(revision: 1, entries: Dictionary(uniqueKeysWithValues:
            domains.map { ($0.rawValue, Entry(generation: 1, context: context)) }))
        needsSave = true
        return flush()
    }

    @discardableResult
    func flush() -> Bool {
        guard needsSave else { return true }
        guard save(envelope) else { return false }
        needsSave = false
        return true
    }

    private func save(_ value: Envelope) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(value)
            if (try? Data(contentsOf: file)) == bytes { return true }
            var directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try directory.setResourceValues(resources)
            try write(bytes, file)
            return true
        } catch { return false }
    }
}
