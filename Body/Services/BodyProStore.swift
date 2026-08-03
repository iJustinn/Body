//
//  BodyProStore.swift
//  Body
//

import Foundation
import RevenueCat
import WidgetKit

/// Owns the Body Pro purchase and the app's reactive entitlement, backed by RevenueCat.
///
/// SwiftUI gates read `isPro` from this `@Observable` store via the environment. Deep
/// clamps that can't reach the environment (the widget process, the plain
/// `HealthKitWorkoutStore`) read the cached `BodyProEntitlement` flag instead, which this
/// store keeps in sync from RevenueCat's `CustomerInfo`.
@MainActor
@Observable
final class BodyProStore {
    /// The single non-consumable that unlocks Body Pro for life. RevenueCat maps this App
    /// Store product to the Pro entitlement; we also fetch it by id for the display price.
    static let lifetimeProductID = "com.zihengthedeveloper.body.pro.lifetime"

    /// RevenueCat entitlement identifier that unlocks Body Pro.
    static let entitlementID = RevenueCatConfiguration.proEntitlementID

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case restoring
        /// Ask-to-Buy / SCA — the purchase is awaiting external approval.
        case pending
        /// The App Store purchase completed but the Pro entitlement is not active —
        /// RevenueCat propagation delay or a dashboard misconfiguration. Cleared once the
        /// entitlement unlocks, like `.pending`.
        case completedNotUnlocked
        case failed(String)
    }

    /// Seeded synchronously from the cached entitlement so a returning Pro user never
    /// flashes the locked UI before RevenueCat resolves.
    private(set) var isPro: Bool = BodyProEntitlement.isUnlocked
    /// `false` until the first async entitlement refresh completes — lets the paywall
    /// show "checking…" rather than "buy" during a reinstall's resolve window.
    private(set) var hasResolved = false
    private(set) var product: StoreProduct?
    /// `true` once a `loadProduct()` attempt has completed without resolving a product —
    /// distinguishes "still loading" from "failed", so the paywall never shows a guessed
    /// price. Cleared at the start of every retry.
    private(set) var productLoadFailed = false
    var purchaseState: PurchaseState = .idle

    // Retained for the store's (app) lifetime. The `[weak self]` capture lets the loop
    // no-op once the store is gone, so an explicit deinit cancel isn't needed.
    private var updatesTask: Task<Void, Never>?

    init() {
        // Skip all RevenueCat work when the SDK isn't configured — e.g. SwiftUI previews,
        // which don't run `BodyApp.init`. `Purchases.shared` fatal-errors if unconfigured, so
        // touching it here would crash previews; `isPro` stays seeded from the cached flag.
        guard Purchases.isConfigured else { return }

        // Long-lived listener for entitlement changes RevenueCat surfaces after its own
        // calls (this-device purchases, restores, cache refreshes). RevenueCat does not
        // push backend changes, so refunds / other-device buys are additionally picked up
        // by the foreground `refreshEntitlement()` hook in BodyApp.
        updatesTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(customerInfo: info)
            }
        }

        Task { [weak self] in
            await self?.loadProduct()
            await self?.refreshEntitlement()
        }
    }

    /// `nil` until the product resolves — the paywall shows a loading placeholder rather
    /// than a guessed price.
    var displayPrice: String? {
        product?.localizedPriceString
    }

    /// Fetch the product directly by id (no Offering dependency); the paywall shows its
    /// localized price. Non-fatal on failure: `productLoadFailed` lets the paywall offer a
    /// retry, and `purchase()` retries the load itself.
    func loadProduct() async {
        productLoadFailed = false
        product = await Purchases.shared.products([Self.lifetimeProductID]).first
        productLoadFailed = product == nil
    }

    func purchase() async {
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            purchaseState = .failed(String(localized: "Body Pro is temporarily unavailable. Please try again."))
            return
        }

        purchaseState = .purchasing
        do {
            let result = try await Purchases.shared.purchase(product: product)
            if result.userCancelled {
                purchaseState = .idle
            } else {
                // Apply the returned CustomerInfo directly — don't wait on the stream.
                apply(customerInfo: result.customerInfo)
                if !isPro {
                    // The purchase completed but the entitlement isn't active yet. One
                    // bounded network re-check (no retry loop — the UI stays on `.purchasing`
                    // for its duration, and the stream / foreground refresh still clears
                    // `.completedNotUnlocked` later if this attempt is too early).
                    if let info = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) {
                        apply(customerInfo: info)
                    }
                }
                purchaseState = isPro ? .idle : .completedNotUnlocked
            }
        } catch {
            // Ask-to-Buy / SCA deferrals surface as `.paymentPendingError`: do not unlock.
            // The entitlement arrives later via the customerInfoStream / foreground refresh,
            // which clears `.pending`. `error as? RevenueCat.ErrorCode` is RevenueCat's
            // documented way to inspect the failure; adjust if the SDK version differs.
            if let errorCode = error as? RevenueCat.ErrorCode, errorCode == .paymentPendingError {
                purchaseState = .pending
            } else {
                purchaseState = .failed(String(localized: "Purchase could not be completed."))
            }
        }
    }

    func restore() async {
        purchaseState = .restoring
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            if isPro {
                purchaseState = .idle
            } else if info.allPurchasedProductIdentifiers.contains(Self.lifetimeProductID) {
                // The lifetime purchase exists but its entitlement didn't resolve —
                // that's the same recovery state as a just-completed purchase, not
                // "nothing to restore" (which would falsely tell a paying customer
                // their purchase doesn't exist).
                purchaseState = .completedNotUnlocked
            } else {
                // A restore that resolves no purchase at all is not a success — say so
                // rather than dropping silently back to the buy card.
                purchaseState = .failed(String(localized: "No purchases to restore."))
            }
        } catch {
            purchaseState = .failed(String(localized: "Restore could not be completed."))
        }
    }

    /// Recompute entitlement from RevenueCat's current `CustomerInfo` and publish any change.
    /// Called on launch and from BodyApp's foreground (`.active`) hook so refunds and
    /// other-device purchases — which RevenueCat does not push — stay in sync.
    func refreshEntitlement() async {
        do {
            // `.fetchCurrent` forces a network fetch. `customerInfo()`'s default policy is
            // `.cachedOrFetched`, which returns cached CustomerInfo even when stale — so it
            // would miss exactly what this explicit launch/foreground refresh exists to catch:
            // refunds, revocations, and other-device purchases that RevenueCat does not push.
            let info = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            apply(customerInfo: info)
        } catch {
            // Keep the cached value; still mark resolved so the paywall leaves "checking".
        }
        hasResolved = true
    }

    /// After an App Store code redemption, force a StoreKit sync so RevenueCat ingests the
    /// redeemed transaction, then apply the resulting entitlement.
    func refreshAfterRedemption() async {
        do {
            let info = try await Purchases.shared.syncPurchases()
            apply(customerInfo: info)
        } catch {
            await refreshEntitlement()
        }
    }

    /// Map RevenueCat's `CustomerInfo` to our single unlock flag. RevenueCat verifies the
    /// transaction and encodes revocation into `isActive`, so this is the whole check.
    private func apply(customerInfo: CustomerInfo) {
        applyEntitlement(customerInfo.entitlements[Self.entitlementID]?.isActive == true)
    }

    private func applyEntitlement(_ unlocked: Bool) {
        let didChange = isPro != unlocked
        isPro = unlocked
        // A pending purchase (Ask-to-Buy / SCA) only clears once the entitlement actually
        // unlocks — otherwise the paywall stays stuck on `.pending` after the approval
        // arrives, leaving Restore / Redeem disabled.
        if unlocked && purchaseState == .pending {
            purchaseState = .idle
        }
        // Same for a purchase that completed before the entitlement propagated: the late
        // unlock is what resolves it.
        if unlocked && purchaseState == .completedNotUnlocked {
            purchaseState = .idle
        }
        // A failure message ("No purchases to restore.") must not linger under the owned
        // card once a later refresh unlocks Pro.
        if unlocked, case .failed = purchaseState {
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
