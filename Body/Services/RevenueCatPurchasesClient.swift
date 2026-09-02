//
//  RevenueCatPurchasesClient.swift
//  Body
//

import Foundation
import RevenueCat

/// The production `BodyPurchasesClient`: the only place in the app that talks to
/// `Purchases.shared`. It translates RevenueCat's `CustomerInfo`, `StoreProduct` and error
/// codes into the small value types `BodyProStore` reasons about, so the store's state
/// machine has no SDK dependency and can be tested.
final class RevenueCatPurchasesClient: BodyPurchasesClient {
    /// Long-lived listener for entitlement changes RevenueCat surfaces after its own calls
    /// (this-device purchases, restores, cache refreshes). RevenueCat does not push backend
    /// changes, so refunds / other-device buys are additionally picked up by the foreground
    /// `refreshEntitlement()` hook in BodyApp.
    let entitlementUpdates: AsyncStream<Bool>

    init() {
        entitlementUpdates = AsyncStream { continuation in
            let task = Task {
                for await info in Purchases.shared.customerInfoStream {
                    continuation.yield(RevenueCatPurchasesClient.isProActive(in: info))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Skip all RevenueCat work when the SDK isn't configured — e.g. SwiftUI previews, which
    /// don't run `BodyApp.init`. `Purchases.shared` fatal-errors if unconfigured, so touching
    /// it there would crash previews.
    static func makeIfConfigured() -> any BodyPurchasesClient {
        Purchases.isConfigured ? RevenueCatPurchasesClient() : NoopPurchasesClient()
    }

    /// Fetch the product directly by id (no Offering dependency); the paywall shows its
    /// localized price.
    func product(id: String) async -> BodyProProduct? {
        guard let product = await Purchases.shared.products([id]).first else { return nil }
        return BodyProProduct(id: product.productIdentifier, displayPrice: product.localizedPriceString)
    }

    func purchase(productID: String) async throws -> BodyPurchaseOutcome {
        guard let product = await Purchases.shared.products([productID]).first else {
            return .unavailable
        }
        do {
            let result = try await Purchases.shared.purchase(product: product)
            if result.userCancelled { return .cancelled }
            var isProActive = Self.isProActive(in: result.customerInfo)
            if !isProActive, let info = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) {
                // The purchase completed but the entitlement isn't active yet. One bounded
                // network re-check (no retry loop — the stream / foreground refresh still
                // clears `.completedNotUnlocked` later if this attempt is too early).
                isProActive = Self.isProActive(in: info)
            }
            return .completed(isProActive: isProActive)
        } catch {
            // Ask-to-Buy / SCA deferrals surface as `.paymentPendingError`: do not unlock.
            // The entitlement arrives later via the customerInfoStream / foreground refresh.
            // `error as? RevenueCat.ErrorCode` is RevenueCat's documented way to inspect the
            // failure; adjust if the SDK version differs.
            if let errorCode = error as? RevenueCat.ErrorCode {
                if errorCode == .paymentPendingError { return .pending }
                if errorCode == .purchaseCancelledError { return .cancelled }
            }
            throw error
        }
    }

    func restorePurchases() async throws -> BodyRestoreOutcome {
        let info = try await Purchases.shared.restorePurchases()
        if Self.isProActive(in: info) { return .unlocked }
        // The lifetime purchase exists but its entitlement didn't resolve — that's the same
        // recovery state as a just-completed purchase, not "nothing to restore" (which would
        // falsely tell a paying customer their purchase doesn't exist).
        if info.allPurchasedProductIdentifiers.contains(BodyProStore.lifetimeProductID) {
            return .ownedButInactive
        }
        return .nothingToRestore
    }

    /// `.fetchCurrent` forces a network fetch. `customerInfo()`'s default policy is
    /// `.cachedOrFetched`, which returns cached CustomerInfo even when stale — so it would
    /// miss exactly what the launch/foreground refresh exists to catch: refunds,
    /// revocations, and other-device purchases that RevenueCat does not push.
    func currentEntitlement() async throws -> Bool {
        Self.isProActive(in: try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent))
    }

    func syncPurchases() async throws -> Bool {
        Self.isProActive(in: try await Purchases.shared.syncPurchases())
    }

    /// Map RevenueCat's `CustomerInfo` to our single unlock flag. RevenueCat verifies the
    /// transaction and encodes revocation into `isActive`, so this is the whole check.
    private static func isProActive(in customerInfo: CustomerInfo) -> Bool {
        customerInfo.entitlements[RevenueCatConfiguration.proEntitlementID]?.isActive == true
    }
}

/// Stand-in used when RevenueCat isn't configured (SwiftUI previews): every call resolves to
/// "nothing owned" and the update stream finishes immediately, so `BodyProStore` keeps its
/// cached entitlement and never touches `Purchases.shared`.
private struct NoopPurchasesClient: BodyPurchasesClient {
    let entitlementUpdates: AsyncStream<Bool> = AsyncStream { $0.finish() }

    func product(id: String) async -> BodyProProduct? { nil }
    func purchase(productID: String) async throws -> BodyPurchaseOutcome { .unavailable }
    func restorePurchases() async throws -> BodyRestoreOutcome { .nothingToRestore }
    func currentEntitlement() async throws -> Bool { false }
    func syncPurchases() async throws -> Bool { false }
}
