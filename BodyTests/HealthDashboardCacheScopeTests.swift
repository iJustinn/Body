import HealthKit
import XCTest
@testable import Body

final class HealthDashboardCacheScopeTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_780_000_000)

    private func series(_ value: Double) -> HealthTrendSeries {
        HealthTrendSeries(points: [.init(date: day, value: value)])
    }

    private func scope() -> HealthDashboardCacheScope {
        let sources = Dictionary(uniqueKeysWithValues: HealthDashboardCacheScope.leafKinds.map {
            ($0.rawValue, HealthDashboardCacheScope.Source(request: $0.rawValue, members: ["A"]))
        })
        return HealthDashboardCacheScope(primary: sources, secondary: sources, aggregation: "UTC", sleepGoal: 28_800)
    }

    private func snapshot() -> HealthDashboardSnapshot {
        var snapshot = HealthDashboardSnapshot.empty
        snapshot.summary.heartRate = HealthMetricSummary(value: 60)
        snapshot.summary.steps = HealthMetricSummary(value: 1200)
        snapshot.trends.heartRateDaySamples = series(60)
        snapshot.trends.stepsDaySamples = series(1200)
        snapshot.trends.heartRateVariabilityDaySamples = series(50)
        snapshot.trends.heartbeatRMSSDDaySamples = series(40)
        snapshot.trends.steps = series(1200)
        snapshot.trends.heartRateDaySamplesSecondary = series(70)
        snapshot.summary.sleep = SleepSummary(duration: 28_800, vitals: SleepVitalsSummary(
            heartRate: 55, heartRateVariability: 50, respiratoryRate: 14,
            oxygenSaturation: 98, wristTemperatureCelsius: 36
        ))
        snapshot.trends.sleepHistory = SleepHistorySnapshot(days: [.init(date: day, summary: snapshot.summary.sleep)])
        snapshot.trends.recordedReadinessContext = "frozen"
        return snapshot
    }

    func testSourceSwitchClearsOnlyItsFallbackAndNestedSleepVital() {
        let old = scope()
        var next = old
        next.primary[HealthMetricKind.heartRateVariability.rawValue]?.members = ["B"]
        let scoped = next.scoping(snapshot(), from: old)
        XCTAssertTrue(scoped.trends.heartRateVariabilityDaySamples.isEmpty)
        XCTAssertTrue(scoped.trends.heartbeatRMSSDDaySamples.isEmpty)
        XCTAssertEqual(scoped.summary.heartRate.value, 60)
        XCTAssertEqual(scoped.trends.stepsDaySamples, series(1200))
        XCTAssertEqual(scoped.summary.sleep.duration, 28_800)
        XCTAssertNil(scoped.summary.sleep.vitals.heartRateVariability)
        XCTAssertNil(scoped.trends.sleepHistory.days.first?.summary.vitals.heartRateVariability)
        XCTAssertEqual(scoped.summary.sleep.vitals.heartRate, 55)
        XCTAssertNotEqual(scoped.trends.recordedReadinessContext, "frozen")
    }

    func testPrimaryChangeKeepsCompatibleComparison() {
        let old = scope()
        var next = old
        next.primary[HealthMetricKind.heartRate.rawValue]?.members = ["B"]
        let scoped = next.scoping(snapshot(), from: old)
        XCTAssertNil(scoped.summary.heartRate.value)
        XCTAssertTrue(scoped.trends.heartRateDaySamples.isEmpty)
        XCTAssertEqual(scoped.trends.heartRateDaySamplesSecondary, series(70))
        XCTAssertEqual(scoped.summary.steps.value, 1200)
    }

    func testTimezoneChangeKeepsInstantaneousSamplesAndFrozenContext() {
        let old = scope()
        var next = old
        next.aggregation = "America/New_York"
        let scoped = next.scoping(snapshot(), from: old)
        XCTAssertEqual(scoped.trends.heartRateDaySamples, series(60))
        XCTAssertTrue(scoped.trends.stepsDaySamples.isEmpty)
        XCTAssertTrue(scoped.trends.steps.isEmpty)
        XCTAssertEqual(scoped.trends.recordedReadinessContext, "frozen")
    }

    func testLegacyScopeFailsClosedWithoutDroppingFrozenContext() {
        let scoped = scope().scoping(snapshot(), from: nil)
        XCTAssertNil(scoped.summary.heartRate.value)
        XCTAssertTrue(scoped.trends.heartRateDaySamples.isEmpty)
        XCTAssertEqual(scoped.trends.recordedReadinessContext, "frozen")
    }

    func testScopeRoundTripAndDaySamplesHydratePerMetric() throws {
        let old = scope()
        XCTAssertEqual(HealthDashboardCacheScope(signature: old.signature), old)
        var next = old
        next.primary[HealthMetricKind.heartRate.rawValue]?.members = ["B"]
        let signatures = HealthTrendDaySampleSignatures(
            primarySelectionSignature: "old", secondarySelectionSignature: "comparison",
            permissionSignature: "", combinesHealthDataSourcesByName: false,
            primaryMetricScopes: old.rawSignatures(), secondaryMetricScopes: old.rawSignatures(secondary: true)
        )
        let encoded = try JSONEncoder().encode(HealthTrendDaySampleSnapshot(trends: snapshot().trends, signatures: signatures))
        let loaded = try JSONDecoder().decode(HealthTrendDaySampleSnapshot.self, from: encoded)
        let hydrated = loaded.scopedForHydration(
            currentPrimarySignature: "new", currentSecondarySignature: "comparison", currentCombinesByName: false,
            permission: BodyHealthPermissionSelection(enabledPermissions: [.heart, .steps]), comparisonDisabledKinds: [],
            currentPrimaryMetricScopes: next.rawSignatures(), currentSecondaryMetricScopes: next.rawSignatures(secondary: true)
        )
        XCTAssertTrue(hydrated.heartRateDaySamples.isEmpty)
        XCTAssertEqual(hydrated.stepsDaySamples, series(1200))
        XCTAssertEqual(hydrated.heartRateDaySamplesSecondary, series(70))
    }

    func testInvalidatedPublicationCannotBecomeCurrentAgain() {
        let old = HealthDashboardPublicationToken()
        old.invalidate()
        XCTAssertFalse(old.isValid)
        XCTAssertTrue(HealthDashboardPublicationToken().isValid)
        XCTAssertFalse(old.isValid)
    }

    @MainActor
    func testFailedNewSourceCannotReuseOldSourceInHomeOrCompanionInputs() async throws {
        let saved = BodyHealthDataSourceSelection.load()
        let restoreLoadDefaults = preserveInitialHealthLoadDefaults()
        defer { saved.save(); restoreLoadDefaults() }
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        fake.scriptSources(for: type, .failure(nil))
        fake.scriptSamples(for: type, .failure(nil))
        fake.scriptStatistics(for: type, .failure(nil))
        fake.scriptStatisticsCollection(for: type, .failure(nil))
        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [], initialHealthDashboardSnapshot: snapshot(),
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: [.steps]),
            initialHealthDataSourceSelection: BodyHealthDataSourceSelection(selectedOptions: [.steps: .init(id: "source:A", name: "A")]),
            initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [], engineHealthStore: fake
        )
        store.contextRefreshOverride = { _ in }
        XCTAssertEqual(store.healthSummary.steps.value, 1200)
        await store.updateHealthDataSource(for: .steps, option: .allSources)
        let completed = await store.runRefreshWithDeadline(.seconds(5)) {
            await store.performHealthMetricRefresh(.steps, date: Date(), calendar: .bodyGregorian)
        }
        XCTAssertTrue(completed)
        XCTAssertTrue(fake.leafRequests.contains(.statisticsCollection(type.identifier)))
        XCTAssertNil(store.healthSummary.steps.value)
        XCTAssertTrue(store.healthTrends.steps.isEmpty)
        XCTAssertTrue(store.healthTrends.stepsDaySamples.isEmpty)
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        let shared = store.makeSharedPublishInput()
        XCTAssertNil(shared.summary.steps.value, "Widget captures must not relabel A as B")
        let watch = store.makeCompanionPublishInput(shared: shared)
        XCTAssertNil(watch.shared.summary.steps.value)
        XCTAssertNil(watch.dataThrough)
    }

    func testDiskReloadCannotRestoreRejectedSourceSamples() throws {
        let old = scope()
        var next = old
        next.primary[HealthMetricKind.heartRate.rawValue]?.members = ["B"]
        let filtered = next.scoping(snapshot(), from: old)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BodyScopeTests.\(UUID().uuidString)")
        let file = directory.appendingPathComponent("dashboard.json")
        let suite = "BodyScopeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        func signatures(_ scope: HealthDashboardCacheScope) -> HealthTrendDaySampleSignatures {
            .init(primarySelectionSignature: "selection", secondarySelectionSignature: "comparison",
                  permissionSignature: "", combinesHealthDataSourcesByName: false,
                  primaryMetricScopes: scope.rawSignatures(), secondaryMetricScopes: scope.rawSignatures(secondary: true))
        }
        XCTAssertTrue(HealthDashboardSnapshotStore.save(snapshot(), daySampleSignatures: signatures(old), summaryContextSignature: old.signature, defaults: defaults, fileURL: file))
        XCTAssertTrue(HealthDashboardSnapshotStore.save(filtered, daySampleSignatures: signatures(next), summaryContextSignature: next.signature, defaults: defaults, fileURL: file))
        let loaded = try XCTUnwrap(HealthDashboardSnapshotStore.load(defaults: defaults, fileURL: file))
        XCTAssertNil(loaded.summary.heartRate.value)
        XCTAssertEqual(loaded.summary.steps.value, 1200)
        let raw = try XCTUnwrap(HealthDashboardSnapshotStore.loadDaySamples(fileURL: file))
        XCTAssertTrue(raw.heartRateDaySamples.isEmpty)
        XCTAssertEqual(raw.stepsDaySamples, series(1200))
        XCTAssertEqual(HealthDashboardCacheScope(signature: HealthDashboardSnapshotStore.loadSummaryContextSignature(fileURL: file)), next)
    }

    @MainActor
    func testComputeResultRejectedWhenGoalChangesBeforeCommit() async {
        let key = BodyAppearancePreference.sleepDurationGoalMinutesKey
        let prior = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(prior, forKey: key) }
        UserDefaults.standard.set(480, forKey: key)
        let store = makeStore()
        let priorFreshness = store.lastSuccessfulRefreshDate
        store.contextRefreshOverride = { _ in }
        store.beforeDashboardComputeCommit = { UserDefaults.standard.set(540, forKey: key) }
        let accepted = await store.updateHealthDashboardSnapshot(
            summary: snapshot().summary, trends: snapshot().trends, activityRingHistory: .empty,
            recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false
        )
        XCTAssertFalse(accepted)
        XCTAssertNil(store.healthSummary.heartRate.value)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, priorFreshness)
    }

    @MainActor
    func testSourceEditsCoalesceToLatestContext() async {
        let saved = BodyHealthDataSourceSelection.load()
        defer { saved.save() }
        let store = makeStore()
        let corrected = expectation(description: "latest context refresh")
        corrected.assertForOverFulfill = true
        // The store retains this hook. A strong capture keeps the fixture and
        // its entitlement observer alive into later tests, where another input
        // change can fulfill this already-finished test's expectation again.
        store.contextRefreshOverride = { [weak store] intent in
            XCTAssertEqual(intent, .userInitiated)
            XCTAssertEqual(store?.healthDataSourceSelection.option(for: .heartRate).id, "source:C")
            corrected.fulfill()
        }
        defer { store.contextRefreshOverride = nil }
        await store.withRefreshSlotHeld {
            await store.updateHealthDataSource(for: .heartRate, option: .init(id: "source:B", name: "B"))
            await store.updateHealthDataSource(for: .heartRate, option: .init(id: "source:C", name: "C"))
            // Let the corrective owner reach the occupied slot. The settings
            // calls above must return without waiting for that slot themselves.
            try? await Task.sleep(for: .milliseconds(400))
        }
        await fulfillment(of: [corrected], timeout: 3)
    }

    @MainActor
    func testPermissionChangeDuringComputeRejectsResult() async {
        let saved = BodyHealthPermissionSelection.load()
        defer { saved.save() }
        let store = makeStore()
        store.contextRefreshOverride = { _ in }
        store.beforeDashboardComputeCommit = { [weak store] in
            await store?.updateHealthPermission(.heart, isEnabled: false)
        }
        let accepted = await store.updateHealthDashboardSnapshot(
            summary: snapshot().summary, trends: snapshot().trends, activityRingHistory: .empty,
            recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false
        )
        XCTAssertFalse(accepted)
        XCTAssertNil(store.healthSummary.heartRate.value)
        XCTAssertTrue(store.healthTrends.heartRateDaySamples.isEmpty)
        XCTAssertFalse(store.permissionSelection.includes(.heart))
    }

    func testDiscoveryCannotInstallBucketsAfterGroupingChanges() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        fake.scriptSources(for: type, .delay(.milliseconds(200), then: .sources([])))
        let engine = HealthKitFetchEngine(
            permission: BodyHealthPermissionSelection(enabledPermissions: [.steps]),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: fake
        )
        let pending = Task { await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian) }
        for _ in 0..<100 where fake.leafRequests.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(fake.leafRequests.isEmpty)
        await engine.setCombinesHealthDataSourcesByName(true)
        let stale = await pending.value
        XCTAssertNil(stale)
        let identities = await engine.cacheSourceIdentities()
        XCTAssertTrue(identities.isEmpty)
        fake.scriptSources(for: type, .sources([]))
        let retry = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian)
        XCTAssertNotNil(retry)
    }

    @MainActor
    func testGoalOnlyCorrectionDoesNotFetchHealthKit() async {
        let key = BodyAppearancePreference.sleepDurationGoalMinutesKey
        let prior = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(prior, forKey: key) }
        UserDefaults.standard.set(480, forKey: key)
        let fake = FakeHealthStore()
        let store = makeStore(fake: fake)
        let computed = expectation(description: "cached-input correction")
        store.beforeDashboardComputeCommit = { computed.fulfill() }
        UserDefaults.standard.set(540, forKey: key)
        store.republishCompanionSnapshots()
        await fulfillment(of: [computed], timeout: 3)
        _ = await store.awaitRefreshSlotFree()
        XCTAssertTrue(fake.leafRequests.isEmpty)
        XCTAssertTrue(fake.executedQueries.isEmpty)
    }

    @MainActor
    func testRejectedDashboardCommitReleasesAnchorOnBothRefreshPaths() async {
        let saved = BodyHealthDataSourceSelection.load()
        defer { saved.save() }
        for recentMonths in [true, false] {
            let store = HealthKitWorkoutStore(
                initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
                initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: []),
                initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
                initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
                engineHealthStore: FakeHealthStore()
            )
            store.contextRefreshOverride = { _ in }
            var reachedCommit = false
            store.beforeDashboardComputeCommit = { [weak store] in
                reachedCommit = true
                await store?.updateHealthDataSource(for: .heartRate, option: .init(id: "source:B", name: "B"))
            }
            await store.withRefreshSlotHeld {
                let completed = await store.runRefreshWithDeadline(.seconds(5)) {
                    if recentMonths {
                        await store.refreshRecentMonths(date: self.day)
                    } else {
                        await store.refresh(month: 5, year: 2026, calendar: .bodyGregorian, updatesHealthSummary: true)
                    }
                }
                XCTAssertTrue(completed)
            }
            XCTAssertTrue(reachedCommit)
            let anchor = await store.engine.healthTrendAnchorDate
            XCTAssertNil(anchor, "A rejected commit must release the refresh's anchor and training-load memo")
        }
    }

    @MainActor
    func testAbandonedDashboardCannotClearNewerRefreshAnchor() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }
        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: []),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore()
        )
        let reachedCommit = expectation(description: "dashboard computation suspended")
        let oldBodyFinished = expectation(description: "abandoned body finished")
        var resumeCommit: CheckedContinuation<Void, Never>?
        store.beforeDashboardComputeCommit = {
            await withCheckedContinuation { continuation in
                resumeCommit = continuation
                reachedCommit.fulfill()
            }
        }
        let refresh = Task { @MainActor in
            await store.runRefreshWithDeadline(.seconds(1)) {
                await store.refreshRecentMonths(date: self.day)
                oldBodyFinished.fulfill()
            }
        }
        await fulfillment(of: [reachedCommit], timeout: 3)
        let completed = await refresh.value
        XCTAssertFalse(completed)
        let releasedAnchor = await store.engine.healthTrendAnchorDate
        XCTAssertNil(releasedAnchor)
        let newerAnchor = day.addingTimeInterval(86_400)
        await store.engine.setHealthTrendAnchorDate(newerAnchor)
        resumeCommit?.resume()
        await fulfillment(of: [oldBodyFinished], timeout: 3)
        let retainedAnchor = await store.engine.healthTrendAnchorDate
        XCTAssertEqual(retainedAnchor, newerAnchor)
        await store.engine.setHealthTrendAnchorDate(nil)
    }

    @MainActor
    func testExplicitSourceAndSleepEditsKeepUserInitiatedRefreshIntent() async {
        let savedPrimary = BodyHealthDataSourceSelection.load()
        let savedSecondary = BodyHealthSecondaryDataSourceSelection.load()
        let defaults = UserDefaults.standard
        let keys = [BodyAppearancePreference.combinesHealthDataSourcesByNameKey,
                    BodyAppearancePreference.customHealthSourceGroupsKey,
                    BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            savedPrimary.save(); savedSecondary.save()
            for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
        }
        let edits: [@MainActor (HealthKitWorkoutStore) async -> Void] = [
            { await $0.updateDefaultHealthDataSource(option: .init(id: "source:B", name: "B")) },
            { await $0.updateHealthDataSource(for: .heartRate, option: .init(id: "source:B", name: "B")) },
            { await $0.updateDefaultSecondaryHealthDataSource(option: .init(id: "source:B", name: "B")) },
            { await $0.updateSecondaryHealthDataSource(for: .heartRate, option: .init(id: "source:B", name: "B")) },
            { await $0.updateCombinesHealthDataSourcesByName(true) },
            { await $0.addCustomHealthSourceGroup(name: "B", memberIdentityKeys: ["source:B"]) },
            {
                defaults.set(!BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
                             forKey: BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey)
                await $0.refetchAfterSleepDisplayPreferenceChange()
            }
        ]
        for edit in edits {
            let store = makeStore()
            let corrected = expectation(description: "explicit settings correction")
            store.contextRefreshOverride = { intent in
                XCTAssertEqual(intent, .userInitiated)
                corrected.fulfill()
            }
            await edit(store)
            // A later passive observation must not downgrade the queued action.
            _ = store.captureRefreshInputs()
            await fulfillment(of: [corrected], timeout: 3)
        }
    }

    @MainActor
    func testPermissionDisableFinishesDiskStripBeforeCorrectiveRefresh() async throws {
        try await assertPermissionCorrectionWaitsForCleanup(pausesDiskStrip: true)
    }

    @MainActor
    func testPermissionEnableFinishesCachedFilterBeforeCorrectiveRefresh() async throws {
        try await assertPermissionCorrectionWaitsForCleanup(pausesDiskStrip: false)
    }

    @MainActor
    private func assertPermissionCorrectionWaitsForCleanup(pausesDiskStrip: Bool) async throws {
        let savedPermission = BodyHealthPermissionSelection.load()
        let savedSource = BodyHealthDataSourceSelection.load()
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { savedPermission.save(); savedSource.save(); restoreDefaults() }
        let fake = FakeHealthStore()
        let stepType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        fake.scriptSamples(for: stepType, .samples([
            HKQuantitySample(type: stepType, quantity: HKQuantity(unit: .count(), doubleValue: 2400),
                             start: day, end: day)
        ]))
        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [], initialHealthDashboardSnapshot: snapshot(),
            initialPermissionSelection: BodyHealthPermissionSelection(
                enabledPermissions: pausesDiskStrip ? [.heart, .steps] : [.steps]
            ),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [], engineHealthStore: fake
        )
        let paused = expectation(description: "permission cleanup paused")
        let corrected = expectation(description: "permission correction completed")
        corrected.assertForOverFulfill = true
        var releaseCleanup: CheckedContinuation<Void, Never>?
        let pause: @MainActor () async -> Void = {
            await withCheckedContinuation { continuation in
                releaseCleanup = continuation
                paused.fulfill()
            }
        }
        if pausesDiskStrip {
            store.beforePermissionDiskStrip = pause
        } else {
            store.beforePermissionSnapshotCommit = pause
        }
        var correctionCount = 0
        store.contextRefreshOverride = { [weak store] intent in
            guard let store else { return }
            correctionCount += 1
            XCTAssertEqual(intent, .userInitiated, "The earlier source action must retain its explicit intent")
            let outcome = await BodyHealthQuantityFetch.latestQuantitySample(
                store: fake, quantityType: stepType, predicate: nil, onFailure: { _ in XCTFail("scripted read failed") }
            )
            guard case .success(let sample) = outcome, let sample else {
                corrected.fulfill()
                return XCTFail("the corrective read must return the fresh sample")
            }
            var summary = store.healthSummary
            summary.steps = HealthMetricSummary(value: sample.quantity.doubleValue(for: .count()))
            let accepted = await store.updateHealthDashboardSnapshot(
                summary: summary, trends: store.healthTrends, activityRingHistory: store.activityRingHistory,
                recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false
            )
            XCTAssertTrue(accepted)
            corrected.fulfill()
        }
        defer {
            store.beforePermissionDiskStrip = nil
            store.beforePermissionSnapshotCommit = nil
            store.contextRefreshOverride = nil
        }
        // Arm the corrective owner before the permission transaction begins.
        await store.updateHealthDataSource(for: .heartRate, option: .init(id: "source:B", name: "B"))
        let toggle = Task { @MainActor in
            await store.updateHealthPermission(.heart, isEnabled: !pausesDiskStrip)
        }
        await fulfillment(of: [paused], timeout: 3)
        XCTAssertTrue(store.isRefreshing, "Permission cleanup must own the refresh slot")
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(correctionCount, 0, "The 300 ms debounce must not outrun permission cleanup")
        XCTAssertTrue(fake.leafRequests.isEmpty)
        releaseCleanup?.resume()
        await toggle.value
        await fulfillment(of: [corrected], timeout: 3)
        XCTAssertEqual(correctionCount, 1)
        XCTAssertEqual(store.healthSummary.steps.value, 2400, "A pre-refresh filtered copy must not overwrite the corrective result")
        XCTAssertEqual(store.makeSharedPublishInput().summary.steps.value, 2400)
        XCTAssertFalse(fake.leafRequests.isEmpty)
    }

    @MainActor
    func testOverlappingPermissionChangesFinishBeforeOneCorrection() async {
        let saved = BodyHealthPermissionSelection.load()
        defer { saved.save() }
        let store = makeStore()
        let firstStrip = expectation(description: "first permission strip")
        let secondStrip = expectation(description: "second permission strip")
        let corrected = expectation(description: "one correction after both permissions")
        corrected.assertForOverFulfill = true
        var releases: [CheckedContinuation<Void, Never>] = []
        store.beforePermissionDiskStrip = {
            await withCheckedContinuation { continuation in
                releases.append(continuation)
                (releases.count == 1 ? firstStrip : secondStrip).fulfill()
            }
        }
        var correctionCount = 0
        store.contextRefreshOverride = { [weak store] _ in
            correctionCount += 1
            XCTAssertFalse(store?.permissionSelection.includes(.heart) ?? true)
            XCTAssertFalse(store?.permissionSelection.includes(.steps) ?? true)
            corrected.fulfill()
        }
        defer { store.beforePermissionDiskStrip = nil; store.contextRefreshOverride = nil }
        let first = Task { @MainActor in await store.updateHealthPermission(.heart, isEnabled: false) }
        await fulfillment(of: [firstStrip], timeout: 3)
        let second = Task { @MainActor in await store.updateHealthPermission(.steps, isEnabled: false) }
        for _ in 0..<100 where store.permissionSelection.includes(.steps) { await Task.yield() }
        XCTAssertFalse(store.permissionSelection.includes(.steps), "Input invalidation must not wait for cleanup")
        releases.first?.resume()
        await fulfillment(of: [secondStrip], timeout: 3)
        try? await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(correctionCount, 0)
        XCTAssertTrue(store.isRefreshing)
        if releases.count == 2 { releases[1].resume() }
        await first.value
        await second.value
        await fulfillment(of: [corrected], timeout: 3)
        XCTAssertEqual(correctionCount, 1)
    }

    @MainActor
    func testCancelledPermissionCallerStillFinishesPrivacyCleanup() async {
        let saved = BodyHealthPermissionSelection.load()
        defer { saved.save() }
        let store = makeStore()
        let corrected = expectation(description: "correction after cancelled settings caller")
        var stripped = false
        store.beforePermissionDiskStrip = { stripped = true }
        store.contextRefreshOverride = { _ in
            XCTAssertTrue(stripped)
            corrected.fulfill()
        }
        defer { store.beforePermissionDiskStrip = nil; store.contextRefreshOverride = nil }
        var toggle: Task<Void, Never>?
        await store.withRefreshSlotHeld {
            toggle = Task { @MainActor in await store.updateHealthPermission(.heart, isEnabled: false) }
            for _ in 0..<100 where store.permissionSelection.includes(.heart) { await Task.yield() }
            XCTAssertFalse(store.permissionSelection.includes(.heart))
            toggle?.cancel()
            XCTAssertFalse(stripped, "Cleanup must first wait for the occupied refresh slot")
        }
        await toggle?.value
        await fulfillment(of: [corrected], timeout: 3)
        XCTAssertTrue(stripped)
        XCTAssertFalse(store.permissionSelection.includes(.heart))
    }

    @MainActor
    private func makeStore(fake: FakeHealthStore = FakeHealthStore()) -> HealthKitWorkoutStore {
        HealthKitWorkoutStore(
            initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: [.heart, .steps]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [], engineHealthStore: fake
        )
    }
}
