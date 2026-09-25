//
//  BodyProStoreTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Test double for the purchase provider. Single-threaded by construction: every property is
/// written by the test before the store reads it, on the main actor, so the `@unchecked
/// Sendable` conformance costs nothing in practice.
final class FakePurchasesClient: BodyPurchasesClient, @unchecked Sendable {
    struct ScriptedError: Error {}

    var scriptedProducts: [BodyProProduct] = []
    var purchaseResult: Result<BodyPurchaseOutcome, Error> = .success(.completed(isProActive: true))
    var restoreResult: Result<BodyRestoreOutcome, Error> = .success(.nothingToRestore)
    var currentEntitlementResult: Result<Bool, Error> = .success(false)
    var syncResult: Result<Bool, Error> = .success(false)

    let entitlementUpdates: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    /// Every product id a purchase was attempted for, in order.
    private(set) var purchasedProductIDs: [String] = []

    init() {
        (entitlementUpdates, continuation) = AsyncStream<Bool>.makeStream()
    }

    /// Push an entitlement change the way the provider's long-lived stream would.
    func emitEntitlement(_ unlocked: Bool) {
        continuation.yield(unlocked)
    }

    func products(ids: [String]) async -> [BodyProProduct] { scriptedProducts.filter { ids.contains($0.id) } }

    func purchase(productID: String) async throws -> BodyPurchaseOutcome {
        purchasedProductIDs.append(productID)
        return try purchaseResult.get()
    }

    func restorePurchases() async throws -> BodyRestoreOutcome { try restoreResult.get() }
    func currentEntitlement() async throws -> Bool { try currentEntitlementResult.get() }
    func syncPurchases() async throws -> Bool { try syncResult.get() }
}

/// Behavioural coverage for the Body Pro state machine: every purchase / restore outcome and
/// every entitlement-stream delivery, against a scripted provider and a throwaway defaults
/// suite, so no test touches RevenueCat or real Pro state.
@MainActor
final class BodyProStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var client: FakePurchasesClient!
    private var reloadCount = 0

    override func setUp() {
        super.setUp()
        suiteName = "BodyTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        client = FakePurchasesClient()
        reloadCount = 0
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Purchase

    func testPurchaseCompletedAndActiveUnlocksWritesCacheAndReloadsWidgetsOnce() async {
        let store = await makeStore()
        client.purchaseResult = .success(.completed(isProActive: true))

        await store.purchase(.yearly)

        XCTAssertEqual(store.purchaseState, .idle)
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(BodyProEntitlement.isUnlocked(defaults: defaults))
        XCTAssertEqual(reloadCount, 1)
    }

    func testPendingPurchaseStaysPendingUntilTheEntitlementStreamUnlocks() async {
        let store = await makeStore()
        client.purchaseResult = .success(.pending)

        await store.purchase(.yearly)

        XCTAssertEqual(store.purchaseState, .pending)
        XCTAssertFalse(store.isPro)

        client.emitEntitlement(true)
        await waitUntil("the pending purchase clears") { store.purchaseState == .idle }
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(reloadCount, 1)
    }

    func testCompletedPurchaseWithoutEntitlementParksAndIsClearedByTheLateUnlock() async {
        let store = await makeStore()
        client.purchaseResult = .success(.completed(isProActive: false))

        await store.purchase(.yearly)

        XCTAssertEqual(store.purchaseState, .completedNotUnlocked)
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(reloadCount, 0)

        client.emitEntitlement(true)
        await waitUntil("the late unlock resolves the purchase") { store.purchaseState == .idle }
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(reloadCount, 1)
    }

    func testCancelledPurchaseReturnsToIdleWithoutTouchingTheEntitlement() async {
        let store = await makeStore()
        client.purchaseResult = .success(.cancelled)

        await store.purchase(.yearly)

        XCTAssertEqual(store.purchaseState, .idle)
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(reloadCount, 0)
    }

    func testUnavailableProductFailsWithTheTemporarilyUnavailableMessage() async {
        let store = await makeStore()
        client.purchaseResult = .success(.unavailable)

        await store.purchase(.yearly)

        XCTAssertEqual(store.purchaseState, .failed("Body Pro is temporarily unavailable. Please try again."))
        XCTAssertFalse(store.isPro)
    }

    func testThrownPurchaseErrorFailsWithTheGenericPurchaseMessage() async {
        let store = await makeStore()
        client.purchaseResult = .failure(FakePurchasesClient.ScriptedError())

        await store.purchase(.yearly)

        XCTAssertEqual(store.purchaseState, .failed("Purchase could not be completed."))
        XCTAssertFalse(store.isPro)
    }

    // MARK: - Entitlement stream

    func testRepeatedUnlockEventsReloadWidgetsOnlyOnTheRealFlip() async {
        let store = await makeStore()

        client.emitEntitlement(true)
        await waitUntil("the first unlock lands") { store.isPro }
        client.emitEntitlement(true)
        await waitUntil("the second, redundant unlock is consumed") { store.hasResolved && store.isPro }
        // Give the loop a further turn so a second reload would have had time to land.
        await Task.yield()

        XCTAssertEqual(reloadCount, 1)
    }

    // MARK: - Restore

    func testRestoreOfAnOwnedButInactivePurchaseParksInTheRecoveryState() async {
        let store = await makeStore()
        client.restoreResult = .success(.ownedButInactive)

        await store.restore()

        XCTAssertEqual(store.purchaseState, .completedNotUnlocked)
        XCTAssertFalse(store.isPro)
    }

    func testRestoreWithNothingToRestoreFails() async {
        let store = await makeStore()
        client.restoreResult = .success(.nothingToRestore)

        await store.restore()

        XCTAssertEqual(store.purchaseState, .failed("No purchases to restore."))
        XCTAssertFalse(store.isPro)
    }

    // MARK: - Products

    func testLoadProductsKeysEveryResolvedPlanAndFailsOnlyWhenNothingLoads() async {
        client.scriptedProducts = [
            BodyProProduct(id: BodyProStore.yearlyProductID, displayPrice: "yearly"),
            BodyProProduct(id: BodyProStore.lifetimeFamilyProductID, displayPrice: "family"),
            // Not a Body Pro plan: never offered.
            BodyProProduct(id: "com.example.unknown", displayPrice: "unknown")
        ]
        let store = await makeStore()

        await store.loadProducts()

        XCTAssertEqual(Set(store.products.keys), [.yearly, .lifetimeFamily])
        XCTAssertEqual(store.products[.lifetimeFamily]?.displayPrice, "family")
        XCTAssertFalse(store.productLoadFailed)

        client.scriptedProducts = []
        await store.loadProducts()

        XCTAssertTrue(store.products.isEmpty)
        XCTAssertTrue(store.productLoadFailed)
    }

    func testPurchaseBuysTheChosenPlansProduct() async {
        let store = await makeStore()

        await store.purchase(.monthly)
        await store.purchase(.lifetimeFamily)

        XCTAssertEqual(client.purchasedProductIDs, [BodyProStore.monthlyProductID, BodyProStore.lifetimeFamilyProductID])
    }

    func testEveryPlanMapsToItsOwnProductAndBack() {
        XCTAssertEqual(Set(BodyProPlan.allCases.map(\.productID)).count, BodyProPlan.allCases.count)
        for plan in BodyProPlan.allCases {
            XCTAssertEqual(BodyProPlan(productID: plan.productID), plan)
        }
        XCTAssertEqual(BodyProStore.lifetimeProductIDs, [BodyProStore.lifetimeProductID, BodyProStore.lifetimeFamilyProductID])
        XCTAssertEqual(BodyProPlan.allCases.filter(\.isSubscription), [.yearly, .monthly])
    }

    // MARK: - Pricing

    func testYearlySavingsRoundDownAndDisappearWithoutARealSaving() throws {
        let monthly = BodyProProduct(id: BodyProStore.monthlyProductID, displayPrice: "", price: try XCTUnwrap(Decimal(string: "0.99")))
        let yearly = BodyProProduct(id: BodyProStore.yearlyProductID, displayPrice: "", price: try XCTUnwrap(Decimal(string: "9.99")))
        // 9.99 against 12 × 0.99 = 11.88 saves 15.9%, shown as 15 so it never overstates.
        XCTAssertEqual(yearly.yearlySavingsPercent(comparedWith: monthly), 15)

        // A storefront where Apple's tiers make yearly cost more than twelve months.
        let pricierYearly = BodyProProduct(id: BodyProStore.yearlyProductID, displayPrice: "", price: try XCTUnwrap(Decimal(string: "12.99")))
        XCTAssertNil(pricierYearly.yearlySavingsPercent(comparedWith: monthly))

        let free = BodyProProduct(id: BodyProStore.monthlyProductID, displayPrice: "", price: 0)
        XCTAssertNil(yearly.yearlySavingsPercent(comparedWith: free))
    }

    func testFreeTrialSpellsWeeksAsDaysAndEndsOnTheBillingDate() throws {
        let week = BodyProFreeTrial(value: 1, unit: .week)
        XCTAssertEqual(week.localizedDuration, BodyProFreeTrial(value: 7, unit: .day).localizedDuration)
        XCTAssertTrue(week.localizedDuration.contains("7"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        XCTAssertEqual(week.endDate(from: start, calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)))
        XCTAssertEqual(
            BodyProFreeTrial(value: 1, unit: .month).endDate(from: start, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))
        )
    }

    // MARK: - Helpers

    /// Builds the store and waits out its launch work (product load + entitlement refresh) so
    /// each test starts from a settled, locked state with no widget reloads recorded.
    private func makeStore() async -> BodyProStore {
        let store = BodyProStore(
            client: client,
            entitlementDefaults: defaults,
            requestWidgetReload: { [self] in reloadCount += 1 }
        )
        await waitUntil("the launch entitlement refresh completes") { store.hasResolved }
        return store
    }

    /// Polls on the main actor until `condition` holds, yielding between checks so the
    /// store's stream loop can run. Deterministic in the passing case and bounded otherwise,
    /// unlike a fixed sleep.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting until \(description)", file: file, line: line)
    }
}
