//
//  BodyProStore.swift
//  Body
//

import Foundation

/// Owns the Body Pro purchases and the app's reactive entitlement, backed by a
/// `BodyPurchasesClient` (RevenueCat in production).
///
/// SwiftUI gates read `isPro` from this `@Observable` store via the environment. Deep
/// clamps that can't reach the environment (the widget process, the plain
/// `HealthKitWorkoutStore`) read the cached `BodyProEntitlement` flag instead, which this
/// store keeps in sync from the purchase provider's entitlement updates.
@MainActor
@Observable
final class BodyProStore {
    // The App Store products that unlock Body Pro, one per `BodyProPlan`. RevenueCat maps
    // each to the Pro entitlement; we also fetch them by id for the display prices.

    /// Non-consumable that unlocks Body Pro for life.
    nonisolated static let lifetimeProductID = "com.zihengthedeveloper.body.pro.lifetime"
    /// The same lifetime unlock with Family Sharing on.
    nonisolated static let lifetimeFamilyProductID = "com.zihengthedeveloper.body.pro.lifetime.family"
    /// Auto-renewable subscriptions in the "Body Pro" group. Yearly carries the free trial.
    nonisolated static let yearlyProductID = "com.zihengthedeveloper.body.pro.yearly"
    nonisolated static let monthlyProductID = "com.zihengthedeveloper.body.pro.monthly"

    /// The purchases that never expire, so owning one with an inactive entitlement is a
    /// recovery state rather than "nothing to restore".
    nonisolated static let lifetimeProductIDs: Set<String> = [lifetimeProductID, lifetimeFamilyProductID]

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
    /// The plans the App Store resolved, keyed by plan. A plan the store could not load is
    /// simply absent, so the paywall only ever offers what can actually be bought.
    private(set) var products: [BodyProPlan: BodyProProduct] = [:]
    /// `true` once a `loadProducts()` attempt has completed without resolving any product —
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

        // Independent: `loadProducts` writes `products`/`productLoadFailed`, `refreshEntitlement`
        // writes `isPro`/`purchaseState`/`hasResolved`, so neither reads the other's state.
        Task { [weak self] in
            guard let self else { return }
            async let products: Void = loadProducts()
            async let entitlement: Void = refreshEntitlement()
            _ = await (products, entitlement)
        }
    }

    /// Fetch every plan's product by id; the paywall shows their localized prices. Non-fatal
    /// on failure: `productLoadFailed` lets the paywall offer a retry, and a purchase attempt
    /// reports `.unavailable` on its own.
    func loadProducts() async {
        productLoadFailed = false
        let loaded = await client.products(ids: BodyProPlan.allCases.map(\.productID))
        var products: [BodyProPlan: BodyProProduct] = [:]
        for product in loaded {
            if let plan = BodyProPlan(productID: product.id) {
                products[plan] = product
            }
        }
        self.products = products
        productLoadFailed = products.isEmpty
    }

    func purchase(_ plan: BodyProPlan) async {
        purchaseState = .purchasing
        do {
            switch try await client.purchase(productID: plan.productID) {
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

    #if DEBUG
    /// Previews snapshot before the launch tasks resolve, so they settle the store up front.
    /// Leaves the shared entitlement cache alone.
    func settleForPreview(isPro: Bool, products: [BodyProProduct]) {
        self.isPro = isPro
        self.products = Dictionary(uniqueKeysWithValues: products.compactMap { product in
            BodyProPlan(productID: product.id).map { ($0, product) }
        })
        hasResolved = true
    }
    #endif

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
