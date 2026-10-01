//
//  BodyPurchasesClient.swift
//  Body
//

import Foundation

/// The ways to buy Body Pro. Every plan unlocks the same Pro entitlement; they differ only
/// in how the customer pays. `allCases` is the paywall's display order.
enum BodyProPlan: String, CaseIterable, Identifiable, Sendable {
    case yearly
    case monthly
    case lifetime
    /// The lifetime purchase with Family Sharing turned on in App Store Connect.
    case lifetimeFamily

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .yearly:
            return BodyProStore.yearlyProductID
        case .monthly:
            return BodyProStore.monthlyProductID
        case .lifetime:
            return BodyProStore.lifetimeProductID
        case .lifetimeFamily:
            return BodyProStore.lifetimeFamilyProductID
        }
    }

    init?(productID: String) {
        guard let plan = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }

    /// Auto-renewable plans, which carry the renewal disclosure and can have a free trial.
    var isSubscription: Bool {
        switch self {
        case .yearly, .monthly:
            return true
        case .lifetime, .lifetimeFamily:
            return false
        }
    }
}

/// A free trial the customer can still start, reduced from the product's introductory offer.
struct BodyProFreeTrial: Equatable, Sendable {
    enum Unit: Equatable, Sendable {
        case day
        case week
        case month
        case year
    }

    let value: Int
    let unit: Unit

    /// "7 days", "1 month": the trial length in the customer's language. Weeks are spelled
    /// out as days, since a one week trial is sold as a 7 day trial.
    var localizedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        var components = DateComponents()
        switch unit {
        case .day:
            formatter.allowedUnits = [.day]
            components.day = value
        case .week:
            formatter.allowedUnits = [.day]
            components.day = value * 7
        case .month:
            formatter.allowedUnits = [.month]
            components.month = value
        case .year:
            formatter.allowedUnits = [.year]
            components.year = value
        }
        return formatter.string(from: components) ?? ""
    }

    /// When a trial started at `start` ends and the first payment is taken.
    func endDate(from start: Date, calendar: Calendar = .current) -> Date {
        switch unit {
        case .day:
            return calendar.date(byAdding: .day, value: value, to: start) ?? start
        case .week:
            return calendar.date(byAdding: .day, value: value * 7, to: start) ?? start
        case .month:
            return calendar.date(byAdding: .month, value: value, to: start) ?? start
        case .year:
            return calendar.date(byAdding: .year, value: value, to: start) ?? start
        }
    }
}

/// A product the paywall sells, reduced to what the UI needs. Keeping the store off
/// RevenueCat's `StoreProduct` (which has no public initializer) is what lets the purchase
/// flow be exercised by tests.
struct BodyProProduct: Equatable, Sendable {
    let id: String
    let displayPrice: String
    /// Only compared between plans (the yearly saving), never shown.
    var price: Decimal = 0
    /// The yearly price spread over twelve months ("$0.83"); `nil` for other products.
    var displayPricePerMonth: String?
    /// Set only when the product has a free trial and this customer is still eligible for it,
    /// so the paywall never promises a trial the App Store will not give.
    var freeTrial: BodyProFreeTrial?

    /// Whole percent this yearly price saves over twelve payments of `monthly`, rounded down
    /// so the badge never overstates it. `nil` when there is no real saving, which happens in
    /// storefronts where Apple's price tiers round the two plans differently.
    func yearlySavingsPercent(comparedWith monthly: BodyProProduct) -> Int? {
        let twelveMonths = monthly.price * 12
        guard twelveMonths > 0 else { return nil }
        var saving = (twelveMonths - price) / twelveMonths * 100
        var wholePercent = Decimal()
        NSDecimalRound(&wholePercent, &saving, 0, .down)
        let percent = NSDecimalNumber(decimal: wholePercent).intValue
        return percent >= 1 ? percent : nil
    }
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
    /// A lifetime product is owned but the entitlement is not active yet.
    case ownedButInactive
    case nothingToRestore
}

/// The purchase provider `BodyProStore` talks to. `RevenueCatPurchasesClient` is the only
/// production conformance; tests inject a scripted fake.
protocol BodyPurchasesClient: Sendable {
    /// The requested products the store could resolve; ids it could not are left out.
    func products(ids: [String]) async -> [BodyProProduct]
    func purchase(productID: String) async throws -> BodyPurchaseOutcome
    func restorePurchases() async throws -> BodyRestoreOutcome
    /// Forces a network fetch of the entitlement, never a cached read.
    func currentEntitlement() async throws -> Bool
    func syncPurchases() async throws -> Bool
    /// Long-lived entitlement updates. One shared stream per client, not a fresh one per
    /// access, so a second reader cannot silently steal the first one's events.
    var entitlementUpdates: AsyncStream<Bool> { get }
}
