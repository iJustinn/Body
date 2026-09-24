//
//  BodySiriIndexCoordinator.swift
//  Body
//
//  Owns Body's Spotlight copy of today's metric values. One actor serializes
//  every write, so a refresh, a Siri reindex and a cache clear can never
//  interleave into a half-written index.
//

import CoreSpotlight
import Foundation
import os

// MARK: - Client

/// The Spotlight seam, so the coordinator can be tested without an index.
protocol BodySiriIndexClient: Sendable {
    func deleteAll() async throws
    func index(_ entities: [BodyHealthMetricEntity]) async throws
}

/// The named index uses the same protection class as Body's snapshot files.
struct BodySiriSpotlightIndexClient: BodySiriIndexClient {

    /// `CSSearchableIndex` is not `Sendable` but is safe to use from any
    /// thread, and only the coordinator actor ever reaches this one.
    private nonisolated(unsafe) static let index = CSSearchableIndex(
        name: "BodySiriEntities",
        protectionClass: .completeUntilFirstUserAuthentication
    )

    private var index: CSSearchableIndex { Self.index }

    func deleteAll() async throws {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try await index.deleteAppEntities(ofType: BodyHealthMetricEntity.self)
    }

    func index(_ entities: [BodyHealthMetricEntity]) async throws {
        guard !entities.isEmpty, CSSearchableIndex.isIndexingAvailable() else { return }
        try await index.indexAppEntities(entities)
    }
}

// MARK: - Coordinator

actor BodySiriIndexCoordinator {

    static let shared = BodySiriIndexCoordinator()

    private let client: any BodySiriIndexClient
    private let bundleLoader: @Sendable () -> BodySiriSnapshotBundle
    private let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "BodySiriIndex")

    /// Bumped by every request and by `clear()`: a run whose generation is no
    /// longer current abandons its write.
    private var generation = 0
    private var isRunning = false
    private var hasPending = false
    private var lastIndexedPayload: [String]?
    /// `clear()` callers parked until the in-flight run finishes, so a delete
    /// is never racing a write that is already on its way to Spotlight.
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        client: any BodySiriIndexClient = BodySiriSpotlightIndexClient(),
        bundleLoader: @escaping @Sendable () -> BodySiriSnapshotBundle = { .loadCurrent() }
    ) {
        self.client = client
        self.bundleLoader = bundleLoader
    }

    /// Coalescing entry point: one run in flight, at most one queued behind it.
    func requestReindex() async {
        guard !isRunning else {
            hasPending = true
            return
        }
        isRunning = true
        defer {
            isRunning = false
            let waiters = idleWaiters
            idleWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        repeat {
            hasPending = false
            do {
                try await run(force: false)
            } catch {
                logger.error("Siri reindex failed: \(error.localizedDescription, privacy: .public)")
            }
        } while hasPending
    }

    /// Forced variant for `IndexedEntityQuery`, which wants the error back.
    func reindexNow() async throws {
        try await run(force: true)
    }

    /// Drops the Spotlight copy. The generation bump makes any suspended run
    /// abandon its bookkeeping, and waiting out a run already writing keeps the
    /// delete after that write, so deletion always wins.
    func clear() async {
        generation &+= 1
        lastIndexedPayload = nil
        if isRunning {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
        do {
            try await client.deleteAll()
        } catch {
            logger.error("Siri index clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Work

    private func run(force: Bool) async throws {
        generation &+= 1
        let mine = generation

        let entities = BodyHealthMetricEntity.entities(from: bundleLoader())
        let payload = entities.map(payloadKey)

        if !force, payload == lastIndexedPayload {
            return
        }

        do {
            try await client.deleteAll()
            guard mine == generation else { return }
            try await client.index(entities)
            guard mine == generation else { return }
            lastIndexedPayload = payload
            logger.debug("Siri index updated with \(entities.count, privacy: .public) metrics")
        } catch {
            // Force the next request to retry rather than trust a failed write.
            lastIndexedPayload = nil
            throw error
        }
    }

    private nonisolated func payloadKey(_ entity: BodyHealthMetricEntity) -> String {
        [
            entity.id,
            entity.valueText ?? "",
            entity.unit ?? "",
            entity.status ?? "",
            entity.applicableDate
        ].joined(separator: "|")
    }
}
