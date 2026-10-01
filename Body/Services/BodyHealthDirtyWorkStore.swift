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
        /// Set while a sleep read is deferred (a daytime vital delivery). The
        /// entry stays pending and generation-fenced; only immediate work skips
        /// it until the coordinator's drain rules make it ordinary again.
        /// Optional so envelopes written before it decode unchanged.
        var deferredAt: Date?
    }
    struct Envelope: Codable, Equatable, Sendable {
        var schema = 2
        var resetID = UUID()
        var revision: UInt64 = 0
        var entries: [String: Entry] = [:]
    }
    struct Receipt: Equatable, Sendable {
        let resetID: UUID
        let domain: String
        let generation: UInt64
        let context: BodyHealthObserverContext
    }

    private let file: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private var envelope: Envelope
    private var needsSave: Bool

    /// Missing or invalid storage conservatively dirties every admitted domain.
    /// The caller supplies the current eligibility set; no health values persist.
    init(file: URL, domains: Set<HealthMetricKind>, context observerContext: BodyHealthObserverContext,
         write: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.file = file
        self.write = write
        let context = observerContext.signature
        let allowed = Set(domains.map(\.rawValue))
        if let bytes = try? Data(contentsOf: file),
           var loaded = try? JSONDecoder().decode(Envelope.self, from: bytes),
           [1, 2].contains(loaded.schema), loaded.revision < UInt64.max,
           loaded.entries.values.allSatisfy({ $0.generation > 0 && $0.generation <= loaded.revision }) {
            let previous = loaded
            #if DEBUG
            let differences = Set(loaded.entries.values.map {
                BodyObserverRefreshDiagnostics.contextDifference(from: $0.context, to: context)
            }).sorted().joined(separator: ";")
            BodyObserverRefreshDiagnostics.log("ledger initialization contextDifference=[\(differences)]")
            #endif
            loaded.entries = loaded.entries.filter { allowed.contains($0.key) }
            if loaded.schema == 1 {
                // Project only recognized legacy scopes. Preserve every pending
                // flag and generation where fetch provenance still matches.
                // Unknown/mismatched provenance takes the conservative repair below.
                for domain in allowed {
                    guard var entry = loaded.entries[domain],
                          let legacy = HealthDashboardCacheScope(signature: entry.context),
                          BodyHealthObserverContext(scope: legacy) == observerContext else { continue }
                    entry.context = context
                    loaded.entries[domain] = entry
                }
                loaded.schema = 2
                loaded.resetID = UUID()
            }
            let changed = allowed.filter { loaded.entries[$0]?.context != context }
            if !changed.isEmpty {
                loaded.revision += 1
                for domain in changed {
                    loaded.entries[domain] = Entry(generation: loaded.revision, context: context)
                }
            }
            envelope = loaded
            needsSave = loaded != previous
        } else {
            envelope = Envelope(revision: 1, entries: Dictionary(uniqueKeysWithValues:
                allowed.map { ($0, Entry(generation: 1, context: context)) }))
            needsSave = true
        }
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("ledger reason=initialization needsSave=\(needsSave) pending=[\(BodyObserverRefreshDiagnostics.pending(envelope))]")
        #endif
    }

    func snapshot() -> Envelope { envelope }

    func receipt(for kind: HealthMetricKind) -> Receipt? {
        guard let entry = envelope.entries[kind.rawValue],
              let context = BodyHealthObserverContext(signature: entry.context) else { return nil }
        return Receipt(resetID: envelope.resetID, domain: kind.rawValue,
                       generation: entry.generation, context: context)
    }

    /// Memory retains failed writes; a later capture/flush can retry. Callers
    /// must still complete observer callbacks, and force foreground reconciliation
    /// after failure instead of assuming HealthKit will redeliver the event.
    /// A kind in `deferring` is recorded as a deferred obligation instead of
    /// immediate work. One already pending and not deferred only gets the new
    /// generation: it will be read anyway, and the bump rejects a read already
    /// in flight so this batch is read again. Every other kind clears any deferral.
    @discardableResult
    func mark(_ kinds: Set<HealthMetricKind>, deferring: Set<HealthMetricKind> = [],
              context observerContext: BodyHealthObserverContext, reason: String = "delivery",
              now: Date = Date()) -> Bool {
        let context = observerContext.signature
        guard !kinds.isEmpty else { return flush() }
        if envelope.revision == .max {
            envelope.resetID = UUID()
            envelope.revision = 1
            envelope.entries = envelope.entries.mapValues { Entry(generation: 1, context: $0.context) }
        } else {
            envelope.revision += 1
        }
        for kind in kinds {
            let existing = envelope.entries[kind.rawValue]
            guard deferring.contains(kind) else {
                envelope.entries[kind.rawValue] = Entry(generation: envelope.revision, context: context)
                continue
            }
            if var entry = existing, entry.context == context, entry.currentPending, entry.deferredAt == nil {
                entry.generation = envelope.revision
                envelope.entries[kind.rawValue] = entry
            } else {
                // The limit counts from the first deferral of a still pending obligation.
                var entry = Entry(generation: envelope.revision, context: context)
                entry.deferredAt = existing?.deferredAt ?? now
                envelope.entries[kind.rawValue] = entry
            }
        }
        needsSave = true
        let durable = flush()
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("ledger reason=\(reason) durable=\(durable) pending=[\(BodyObserverRefreshDiagnostics.pending(envelope))]")
        #endif
        return durable
    }

    /// Payload must already be durably saved under this receipt's context.
    /// A concurrent newer event/reset/context leaves its obligation untouched.
    @discardableResult
    func acknowledge(_ receipt: Receipt, current: Bool, history: Bool) -> Bool {
        // A delivery can fail to persist while a read is in flight. Retry once,
        // then recheck every fence below; durability never substitutes for receipt
        // ownership, and a newer delivery must not be consumed by the old read.
        if needsSave { _ = flush() }
        #if DEBUG
        let rejection: String?
        if needsSave { rejection = "dirtyLedgerNotDurable" }
        else if receipt.resetID != envelope.resetID { rejection = "reset" }
        else if envelope.entries[receipt.domain] == nil { rejection = "removedDomain" }
        else if envelope.entries[receipt.domain]?.generation != receipt.generation { rejection = "newerGeneration" }
        else if envelope.entries[receipt.domain]?.context != receipt.context.signature { rejection = "contextMismatch" }
        else { rejection = nil }
        if let rejection {
            BodyObserverRefreshDiagnostics.log("ack kind=\(receipt.domain) generation=\(receipt.generation) accepted=false reason=\(rejection)")
        }
        #endif
        guard !needsSave, receipt.resetID == envelope.resetID,
              var entry = envelope.entries[receipt.domain],
              entry.generation == receipt.generation, entry.context == receipt.context.signature else { return false }
        if current { entry.currentPending = false }
        if history { entry.historyPending = false }
        // A settled entry owes nothing, so a later deferral starts its own limit.
        if !entry.currentPending, !entry.historyPending { entry.deferredAt = nil }
        var next = envelope
        next.entries[receipt.domain] = entry
        guard save(next) else {
            #if DEBUG
            BodyObserverRefreshDiagnostics.log("ack kind=\(receipt.domain) generation=\(receipt.generation) accepted=false reason=ledgerWriteFailure")
            #endif
            return false
        }
        envelope = next
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("ack kind=\(receipt.domain) generation=\(receipt.generation) accepted=true current=\(current) history=\(history)")
        #endif
        return true
    }

    func synchronize(domains: Set<HealthMetricKind>, context observerContext: BodyHealthObserverContext) -> Bool {
        let context = observerContext.signature
        let allowed = Set(domains.map(\.rawValue))
        let previous = envelope
        envelope.entries = envelope.entries.filter { allowed.contains($0.key) }
        let changed = domains.filter { envelope.entries[$0.rawValue]?.context != context }
        #if DEBUG
        let differences = Set(changed.map {
            BodyObserverRefreshDiagnostics.contextDifference(from: previous.entries[$0.rawValue]?.context, to: context)
        }).sorted().joined(separator: ";")
        BodyObserverRefreshDiagnostics.log("ledger synchronization contextDifference=[\(differences)] changedDomains=\(changed.count)")
        #endif
        if envelope != previous { needsSave = true }
        return mark(changed, context: observerContext, reason: "contextSynchronization")
    }

    @discardableResult
    func reset(domains: Set<HealthMetricKind>, context observerContext: BodyHealthObserverContext) -> Bool {
        let context = observerContext.signature
        envelope = Envelope(revision: 1, entries: Dictionary(uniqueKeysWithValues:
            domains.map { ($0.rawValue, Entry(generation: 1, context: context)) }))
        needsSave = true
        let durable = flush()
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("ledger reason=reset durable=\(durable) pending=[\(BodyObserverRefreshDiagnostics.pending(envelope))]")
        #endif
        return durable
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
