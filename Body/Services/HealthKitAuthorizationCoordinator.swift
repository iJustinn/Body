//
//  HealthKitAuthorizationCoordinator.swift
//  Body
//

import Foundation

/// Serializes every HealthKit permission-sheet transaction in the app.
///
/// `HealthKitFetchEngine` is an actor, but each `requestAuthorization` bridges
/// through a continuation: awaiting it releases the actor, so a second caller
/// (an effort-score write, say, racing a read-permission refresh) can enter and
/// present a second sheet on top of the first. This coordinator gives those
/// transactions a single FIFO lane.
actor HealthKitAuthorizationCoordinator {
    private var chain: Task<Void, Never> = Task {}

    /// Number of transactions currently enqueued or running, so callers can tell
    /// whether a sheet is (or is about to be) on screen.
    private(set) var inFlightCount = 0

    var isBusy: Bool { inFlightCount > 0 }

    /// Runs `operation` strictly after every previously enqueued operation (FIFO),
    /// whether or not those threw. Put the whole "check status → present sheet →
    /// re-check" transaction inside `operation` so a waiter re-evaluates status after
    /// the prior sheet instead of presenting blindly.
    ///
    /// The chain is deliberately id-less and never cleared: the tail task swallows
    /// failures (`try?`), so a throwing operation hands the lane to the next waiter
    /// instead of wedging it.
    func run<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        inFlightCount += 1
        defer { inFlightCount -= 1 }

        let previous = chain
        let mine = Task { () throws -> T in
            await previous.value
            return try await operation()
        }
        chain = Task { _ = try? await mine.value }
        return try await mine.value
    }
}
