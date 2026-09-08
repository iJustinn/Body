//
//  BodyProStore.swift
//  Body
//

import Foundation

/// Owns the Body Pro purchase and the app's reactive entitlement, backed by a
/// `BodyPurchasesClient` (RevenueCat in production).
///
/// SwiftUI gates read `isPro` from this `@Observable` store via the environment. Deep
/// clamps that can't reach the environment (the widget process, the plain
/// `HealthKitWorkoutStore`) read the cached `BodyProEntitlement` flag instead, which this
/// store keeps in sync from the purchase provider's entitlement updates.
@MainActor
@Observable
final class BodyProStore {
    /// The single non-consumable that unlocks Body Pro for life. RevenueCat maps this App
    /// Store product to the Pro entitlement; we also fetch it by id for the display price.
    nonisolated static let lifetimeProductID = "com.zihengthedeveloper.body.pro.lifetime"

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
    /// flashes the locked UI before the entitlement resolves.
    private(set) var isPro: Bool
    /// `false` until the first async entitlement refresh completes — lets the paywall
    /// show "checking…" rather than "buy" during a reinstall's resolve window.
    private(set) var hasResolved = false
    private(set) var product: BodyProProduct?
    /// `true` once a `loadProduct()` attempt has completed without resolving a product —
    /// distinguishes "still loading" from "failed", so the paywall never shows a guessed
    /// price. Cleared at the start of every retry.
    private(set) var productLoadFailed = false
    var purchaseState: PurchaseState = .idle

    private let client: any BodyPurchasesClient
    private let entitlementDefaults: UserDefaults?
    private let requestWidgetReload: @MainActor () -> Void

    // Retained for the store's (app) lifetime. The `[weak self]` capture lets the loop
    // no-op once the store is gone, so an explicit deinit cancel isn't needed.
    private var updatesTask: Task<Void, Never>?

    init(
        client: any BodyPurchasesClient = RevenueCatPurchasesClient.makeIfConfigured(),
        entitlementDefaults: UserDefaults? = nil,
        requestWidgetReload: @escaping @MainActor () -> Void = { BodyWidgetReloadCoalescer.shared.requestReload() }
    ) {
        self.client = client
        self.entitlementDefaults = entitlementDefaults
        self.requestWidgetReload = requestWidgetReload
        isPro = BodyProEntitlement.isUnlocked(defaults: entitlementDefaults)

        updatesTask = Task { [weak self] in
            guard let updates = self?.client.entitlementUpdates else { return }
            for await unlocked in updates {
                self?.applyEntitlement(unlocked)
            }
        }

        // Independent: `loadProduct` writes `product`/`productLoadFailed`, `refreshEntitlement`
        // writes `isPro`/`purchaseState`/`hasResolved`, so neither reads the other's state.
        Task { [weak self] in
            guard let self else { return }
            async let product: Void = loadProduct()
            async let entitlement: Void = refreshEntitlement()
            _ = await (product, entitlement)
        }
    }

    /// `nil` until the product resolves — the paywall shows a loading placeholder rather
    /// than a guessed price.
    var displayPrice: String? {
        product?.displayPrice
    }

    /// Fetch the product by id; the paywall shows its localized price. Non-fatal on failure:
    /// `productLoadFailed` lets the paywall offer a retry, and a purchase attempt reports
    /// `.unavailable` on its own.
    func loadProduct() async {
        productLoadFailed = false
        product = await client.product(id: Self.lifetimeProductID)
        productLoadFailed = product == nil
    }

    func purchase() async {
        purchaseState = .purchasing
        do {
            switch try await client.purchase(productID: Self.lifetimeProductID) {
            case .cancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            case .unavailable:
                purchaseState = .failed(String(localized: "Body Pro is temporarily unavailable. Please try again."))
            case .completed(let isProActive):
                applyEntitlement(isProActive)
                purchaseState = isPro ? .idle : .completedNotUnlocked
            }
        } catch {
            purchaseState = .failed(String(localized: "Purchase could not be completed."))
        }
    }

    func restore() async {
        purchaseState = .restoring
        do {
            switch try await client.restorePurchases() {
            case .unlocked:
                applyEntitlement(true)
                purchaseState = .idle
            case .ownedButInactive:
                applyEntitlement(false)
                purchaseState = .completedNotUnlocked
            case .nothingToRestore:
                applyEntitlement(false)
                // A restore that resolves no purchase at all is not a success — say so
                // rather than dropping silently back to the buy card.
                purchaseState = .failed(String(localized: "No purchases to restore."))
            }
        } catch {
            purchaseState = .failed(String(localized: "Restore could not be completed."))
        }
    }

    /// Recompute entitlement from the provider's current state and publish any change.
    /// Called on launch and from BodyApp's foreground (`.active`) hook so refunds and
    /// other-device purchases — which RevenueCat does not push — stay in sync.
    func refreshEntitlement() async {
        do {
            applyEntitlement(try await client.currentEntitlement())
        } catch {
            // Keep the cached value; still mark resolved so the paywall leaves "checking".
        }
        hasResolved = true
    }

    /// After an App Store code redemption, force a StoreKit sync so RevenueCat ingests the
    /// redeemed transaction, then apply the resulting entitlement.
    func refreshAfterRedemption() async {
        do {
            applyEntitlement(try await client.syncPurchases())
        } catch {
            await refreshEntitlement()
        }
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
        // HealthKitWorkoutStore pick up the change. This store is the single owner of the
        // Pro widget refresh, so it fires regardless of any view's lifecycle, and only
        // when the entitlement actually flips.
        BodyProEntitlement.setUnlocked(unlocked, defaults: entitlementDefaults)
        if didChange {
            requestWidgetReload()
        }
    }
}
