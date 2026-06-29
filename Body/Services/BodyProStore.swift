//
//  BodyProStore.swift
//  Body
//

import Foundation
import StoreKit
import WidgetKit

/// Owns the Body Pro StoreKit 2 purchase and the app's reactive entitlement.
///
/// SwiftUI gates read `isPro` from this `@Observable` store via the environment. Deep
/// clamps that can't reach the environment (the widget process, the plain
/// `HealthKitWorkoutStore`) read the cached `BodyProEntitlement` flag instead, which
/// this store keeps in sync.
@MainActor
@Observable
final class BodyProStore {
    /// The single non-consumable that unlocks Body Pro for life.
    static let lifetimeProductID = "com.zihengthedeveloper.body.pro.lifetime"

    /// Fallback price shown before (or if) the StoreKit product fails to load.
    static let fallbackDisplayPrice = "$9.99"

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case restoring
        /// Ask-to-Buy / SCA — the purchase is awaiting external approval.
        case pending
        case failed(String)
    }

    /// Seeded synchronously from the cached entitlement so a returning Pro user never
    /// flashes the locked UI before StoreKit resolves.
    private(set) var isPro: Bool = BodyProEntitlement.isUnlocked
    /// `false` until the first async entitlement refresh completes — lets the paywall
    /// show "checking…" rather than "buy" during a reinstall's resolve window.
    private(set) var hasResolved = false
    private(set) var product: Product?
    var purchaseState: PurchaseState = .idle

    // Retained for the store's (app) lifetime. The `[weak self]` capture lets the loop
    // no-op once the store is gone, so an explicit deinit cancel isn't needed.
    private var updatesTask: Task<Void, Never>?

    init() {
        // Long-lived listener for entitlement changes that happen outside an explicit
        // purchase: Ask-to-Buy approvals, family sharing, refunds, other-device buys.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verification: update)
            }
        }

        Task { [weak self] in
            await self?.loadProduct()
            await self?.refreshEntitlement()
        }
    }

    var displayPrice: String {
        product?.displayPrice ?? Self.fallbackDisplayPrice
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.lifetimeProductID]).first
        } catch {
            // Non-fatal: the paywall falls back to the static price and purchase() retries.
        }
    }

    func purchase() async {
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            purchaseState = .failed("Body Pro is temporarily unavailable. Please try again.")
            return
        }

        purchaseState = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification: verification)
                purchaseState = .idle
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                // Do not unlock or finish — Transaction.updates delivers it once approved.
                purchaseState = .pending
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed("Purchase could not be completed.")
        }
    }

    func restore() async {
        purchaseState = .restoring
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            purchaseState = .idle
        } catch {
            purchaseState = .failed("Restore could not be completed.")
        }
    }

    /// Recompute entitlement from the user's current entitlements and publish any change.
    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.lifetimeProductID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        applyEntitlement(unlocked)
        hasResolved = true
    }

    /// Verify, unlock if it is our product, then finish the transaction.
    private func handle(verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            // Never trust or finish an unverified transaction.
            return
        }

        if transaction.productID == Self.lifetimeProductID {
            applyEntitlement(transaction.revocationDate == nil)
        }
        await transaction.finish()
    }

    private func applyEntitlement(_ unlocked: Bool) {
        let didChange = isPro != unlocked
        isPro = unlocked
        // A pending purchase (Ask-to-Buy / SCA) only clears once the entitlement actually
        // unlocks — otherwise the paywall stays stuck on `.pending` after the approval
        // arrives via Transaction.updates, leaving Restore / Redeem disabled.
        if unlocked && purchaseState == .pending {
            purchaseState = .idle
        }
        // Writes the shared cache (value-guarded post) so the widget process and
        // HealthKitWorkoutStore pick up the change; refresh widgets only when it flips.
        BodyProEntitlement.setUnlocked(unlocked)
        if didChange {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
