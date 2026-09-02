//
//  BodyPurchasesClient.swift
//  Body
//

import Foundation

/// The one product the paywall shows, reduced to what the UI needs. Keeping the store off
/// RevenueCat's `StoreProduct` (which has no public initializer) is what lets the purchase
/// flow be exercised by tests.
struct BodyProProduct: Equatable, Sendable {
    let id: String
    let displayPrice: String
}

/// Outcome of a purchase attempt, already normalized away from the SDK's error codes.
enum BodyPurchaseOutcome: Equatable, Sendable {
    /// The App Store purchase completed. `isProActive` is the entitlement state the
    /// provider reported alongside it, which can lag the purchase.
    case completed(isProActive: Bool)
    case cancelled
    /// Ask-to-Buy / SCA: awaiting external approval, never an unlock.
    case pending
    /// The product could not be loaded, so no purchase was attempted.
    case unavailable
}

/// Outcome of a restore, split so a paying customer whose entitlement has not resolved is
/// never told their purchase does not exist.
enum BodyRestoreOutcome: Equatable, Sendable {
    case unlocked
    /// The lifetime product is owned but the entitlement is not active yet.
    case ownedButInactive
    case nothingToRestore
}

/// The purchase provider `BodyProStore` talks to. `RevenueCatPurchasesClient` is the only
/// production conformance; tests inject a scripted fake.
protocol BodyPurchasesClient: Sendable {
    func product(id: String) async -> BodyProProduct?
    func purchase(productID: String) async throws -> BodyPurchaseOutcome
    func restorePurchases() async throws -> BodyRestoreOutcome
    /// Forces a network fetch of the entitlement, never a cached read.
    func currentEntitlement() async throws -> Bool
    func syncPurchases() async throws -> Bool
    /// Long-lived entitlement updates. One shared stream per client, not a fresh one per
    /// access, so a second reader cannot silently steal the first one's events.
    var entitlementUpdates: AsyncStream<Bool> { get }
}
