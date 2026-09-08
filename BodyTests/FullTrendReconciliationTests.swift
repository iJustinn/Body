import HealthKit
import XCTest
@testable import Body

final class FullTrendReconciliationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_500_000)
    private func series(_ value: Double, daysAgo: Double = 0) -> HealthTrendSeries {
        .init(points: [.init(date: now.addingTimeInterval(-daysAgo * 86400), value: value)])
    }

    @MainActor
    func testSuccessfulPrimaryReconcilesDespiteFailedComparisonAndKeepsLiveRawAndFrozenData() async throws {
        let wasUnlocked = BodyProEntitlement.isUnlocked
        BodyProEntitlement.setUnlocked(true)
        defer { BodyProEntitlement.setUnlocked(wasUnlocked) }
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .restingHeartRate))
        fake.scriptDailyQuantities(for: type, values: [.init(date: now.addingTimeInterval(-180 * 86400),
            quantity: .init(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 55))])
        let engine = HealthKitFetchEngine(permission: .init(enabledPermissions: [.heart]),
            healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .init(selectedOptions: [.restingHeartRate: .init(id: "source:missing", name: "Missing")]),
            combinesHealthDataSourcesByName: false, healthStore: fake, effortLedgerDirectoryURL: nil)
        await engine.setHealthTrendAnchorDate(now)
        var cached = HealthTrendSnapshot.empty
        cached.restingHeartRate = series(70, daysAgo: 180)
        cached.restingHeartRateSecondary = series(65, daysAgo: 180)
        let selection = BodyDashboardFetchSelection(summaryCards: .init(selectedCards: [.restingHeartRate]),
            trendCards: .init(selectedCards: []))
        let result = await engine.fetchHealthTrends(calendar: .bodyGregorian, cachedTrends: cached, selection: selection)
        XCTAssertTrue(result.hadQueryFailure)
        XCTAssertTrue(result.successfulLeaves.contains(.restingHeartRate))
        XCTAssertFalse(result.successfulLeaves.contains(.restingHeartRateSecondary))
        XCTAssertTrue(fake.leafRequests.contains(.statisticsCollection(type.identifier)))
        var live = cached
        live.heartRateDaySamples = series(90)
        live.recordedReadiness = [.init(date: now.addingTimeInterval(-500 * 86400), score: 42)]
        live.recordedReadinessContext = "frozen"
        live.stress = series(30)
        let repaired = HealthKitWorkoutStore.applyingFullWindowTrendSeries(from: result, to: live,
            capturedRevisions: [:], currentRevisions: [:])
        XCTAssertEqual(repaired.restingHeartRate.points.first?.value, 55)
        XCTAssertEqual(repaired.restingHeartRateSecondary, live.restingHeartRateSecondary)
        XCTAssertEqual(repaired.heartRateDaySamples, live.heartRateDaySamples)
        XCTAssertEqual(repaired.recordedReadiness, live.recordedReadiness)
        XCTAssertEqual(repaired.recordedReadinessContext, "frozen")
        XCTAssertEqual(repaired.stress, live.stress)
    }

    @MainActor
    func testPartialConcurrentPublicationRejectsOnlyItsChangedLeaf() {
        var live = HealthTrendSnapshot.empty
        live.steps = series(900)
        live.restingHeartRate = series(60)
        var fetched = live
        fetched.steps = series(100)
        fetched.restingHeartRate = .empty
        let result = HealthKitFetchEngine.HealthTrendFetchResult(trends: fetched, hadQueryFailure: false,
            successfulLeaves: [.steps, .restingHeartRate])
        let next = HealthKitWorkoutStore.applyingFullWindowTrendSeries(from: result, to: live,
            capturedRevisions: [.steps: 1], currentRevisions: [.steps: 2])
        XCTAssertEqual(next.steps, live.steps)
        XCTAssertTrue(next.restingHeartRate.isEmpty, "Successful empty is authoritative")
    }

    @MainActor
    func testSleepVitalPartialIsNotCompleteCoverageAndRollingRetentionDoesNotPruneObservations() {
        var fetched = HealthTrendSnapshot.empty
        fetched.steps = .init(points: series(100, daysAgo: 500).points + series(200).points)
        fetched.sleepHistory = .init(days: [.init(date: now, summary: .init(duration: 3600))])
        fetched.sleep = fetched.sleepHistory.durationSeries
        fetched.recordedReadiness = [.init(date: now.addingTimeInterval(-500 * 86400), score: 42)]
        let result = HealthKitFetchEngine.finalizedTrendFetchResult(trends: fetched, hadQueryFailure: false,
            successfulLeaves: [.steps, .sleep], sleepVitalsHadFailure: true,
            retentionStart: now.addingTimeInterval(-364 * 86400))
        XCTAssertTrue(result.hadQueryFailure)
        XCTAssertFalse(result.successfulLeaves.contains(.sleep))
        XCTAssertEqual(result.trends.steps.points.count, 1)
        XCTAssertEqual(result.trends.recordedReadiness, fetched.recordedReadiness)
        var live = fetched
        live.sleepHistory = .init(days: [.init(date: now, summary: .init(duration: 28800))])
        let next = HealthKitWorkoutStore.applyingFullWindowTrendSeries(from: result, to: live,
            capturedRevisions: [:], currentRevisions: [:])
        XCTAssertEqual(next.sleepHistory, live.sleepHistory)
        XCTAssertEqual(next.steps.points.count, 1)
    }

    @MainActor
    func testConcurrentIntradayCommitCannotBeOverwrittenByFullTrendCompute() async {
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart, .steps]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [], engineHealthStore: FakeHealthStore())
        store.contextRefreshOverride = { _ in }
        var original = HealthTrendSnapshot.empty
        original.stepsDaySamples = series(100)
        _ = await store.updateHealthDashboardSnapshot(summary: .empty, trends: original, activityRingHistory: .empty,
            recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false)
        let revision = store.dashboardDataRevision
        let newer = series(900)
        store.beforeDashboardComputeCommit = { [weak store] in
            guard let store else { return }
            store.beforeDashboardComputeCommit = nil
            var trends = store.healthTrends
            trends.stepsDaySamples = newer
            _ = await store.updateHealthDashboardSnapshot(summary: store.healthSummary, trends: trends, activityRingHistory: .empty,
                recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false)
        }
        let accepted = await store.updateHealthDashboardSnapshot(summary: .empty, trends: original, activityRingHistory: .empty,
            recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false,
            expectedDataRevision: revision)
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.healthTrends.stepsDaySamples, newer)
    }
}
