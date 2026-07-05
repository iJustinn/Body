//
//  RevenueCatConfiguration.swift
//  Body
//

import Foundation
import RevenueCat

/// Central RevenueCat setup: the public SDK key and the Pro entitlement identifier live in
/// one auditable place, together with the one-time `configure()` call. `BodyProStore` reads
/// `proEntitlementID`; `BodyApp` calls `configure()` at launch.
enum RevenueCatConfiguration {
    /// RevenueCat *public* app-specific key (RevenueCat dashboard ▸ Project settings ▸
    /// API keys ▸ public app-specific key for Apple). Apple keys start with `appl_`.
    static let publicAPIKey = "appl_PoWnLIjBBShPqMturjPyogVqdEH"

    /// RevenueCat entitlement identifier that unlocks Body Pro — must match the entitlement's
    /// *Identifier* in the dashboard exactly (not its REST API id). A wrong value makes the
    /// entitlement read as inactive, so Pro would silently never unlock.
    static let proEntitlementID = "Body: Health Dashboard Pro"

    /// Configure RevenueCat once, as early as possible in launch and before any
    /// `Purchases.shared` use. Idempotent — RevenueCat documents configuration as a
    /// once-per-process operation.
    static func configure() {
        guard !Purchases.isConfigured else { return }
        Purchases.logLevel = .info // raise to `.debug` during bring-up
        // Rely on the default `purchasesAreCompletedBy: .revenueCat`: RevenueCat finishes
        // transactions and uses StoreKit 2 where available. Do NOT enable observer mode or
        // finish transactions manually.
        Purchases.configure(with: Configuration.Builder(withAPIKey: publicAPIKey).build())
    }
}
