import HealthKit
import XCTest
@testable import Body

final class HealthDashboardCalendarContextTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        return result
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func scope(_ calendar: Calendar, _ now: Date) -> HealthDashboardCacheScope {
        let sources = Dictionary(uniqueKeysWithValues: HealthDashboardCacheScope.leafKinds.map {
            ($0.rawValue, HealthDashboardCacheScope.Source(request: $0.rawValue, members: ["A"]))
        })
        return .init(primary: sources, secondary: sources,
                     aggregation: HealthDashboardCacheScope.key([String(describing: calendar.identifier), calendar.timeZone.identifier, "aggregation-v3"]),
                     sleepGoal: 28_800, summaryDayStart: calendar.startOfDay(for: now))
    }

    private func snapshot(_ day: Date) -> HealthDashboardSnapshot {
        var result = HealthDashboardSnapshot.empty
        result.summary.steps = .init(value: 1234)
        result.summary.heartRate = .init(value: 60)
        result.summary.bodyMass = .init(value: 70)
        result.summary.activityRings = .init(move: .init(value: 500, goal: 500), exercise: .empty, stand: .empty)
        result.trends.steps = .init(points: [.init(date: day, value: 1234)])
        result.trends.stepsDaySamples = result.trends.steps
        result.trends.heartRateDaySamples = .init(points: [.init(date: day, value: 60)])
        result.trends.recordedReadiness = [.init(date: day, score: 42)]
        result.trends.recordedReadinessContext = "original frozen context"
        result.trends.recordedBodyRadarContext = "original radar context"
        return result
    }

    func testTravelInvalidatesAggregatesButPreservesRawInstantsAndFrozenAttribution() throws {
        let now = date("2026-09-04T05:00:00Z")
        for (from, to) in [("America/New_York", "America/Los_Angeles"),
                           ("America/Los_Angeles", "America/New_York"),
                           ("Pacific/Kiritimati", "Pacific/Pago_Pago"),
                           ("Pacific/Pago_Pago", "Pacific/Kiritimati")] {
            let old = scope(calendar(from), now), next = scope(calendar(to), now)
            let original = snapshot(calendar(from).startOfDay(for: now))
            let repaired = next.scoping(original, from: old)
            XCTAssertTrue(repaired.trends.steps.isEmpty)
            XCTAssertTrue(repaired.trends.stepsDaySamples.isEmpty)
            XCTAssertEqual(repaired.trends.heartRateDaySamples, original.trends.heartRateDaySamples)
            XCTAssertEqual(repaired.trends.recordedReadiness, original.trends.recordedReadiness)
            XCTAssertEqual(repaired.trends.recordedReadinessContext, original.trends.recordedReadinessContext)
            XCTAssertEqual(repaired.trends.recordedBodyRadarContext, original.trends.recordedBodyRadarContext)
            XCTAssertNil(repaired.summary.readiness.score)
            XCTAssertNil(repaired.summary.bodyRadar)
            XCTAssertEqual(HealthDashboardCacheScope(signature: next.signature), next)
        }
    }

    func testMidnightExpiresTodayNotHistoryAndUsesCalendarDaysAcrossDST() {
        let cal = calendar("America/New_York")
        for (start, hours) in [("2026-03-08T05:00:00Z", 23), ("2026-11-01T04:00:00Z", 25)] {
            let beginning = date(start)
            let end = cal.date(byAdding: .day, value: 1, to: beginning)!
            XCTAssertEqual(end.timeIntervalSince(beginning), Double(hours) * 3600)
            let old = scope(cal, beginning), before = scope(cal, end.addingTimeInterval(-1))
            XCTAssertEqual(old, before, "An offset change within the day is not midnight")
            let original = snapshot(beginning)
            let next = scope(cal, end).scoping(original, from: before)
            XCTAssertNil(next.summary.steps.value)
            XCTAssertTrue(next.summary.activityRings.isEmpty)
            XCTAssertEqual(next.summary.heartRate, original.summary.heartRate)
            XCTAssertEqual(next.summary.bodyMass, original.summary.bodyMass)
            XCTAssertEqual(next.trends, original.trends)
        }
    }

    @MainActor
    func testMidnightInsideFreshnessTTLQueuesCorrectionBeforeResumeGate() async throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let cal = calendar("America/New_York")
        var now = date("2026-09-04T03:59:50Z")
        let store = makeStore(snapshot(now), context: { (cal, now) })
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dirty.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let domains: Set<HealthMetricKind> = [.steps, .heartRate]
        let ledger = BodyHealthDirtyWorkStore(file: file, domains: domains, context: store.currentObserverLedgerContext())
        _ = await ledger.flush()
        for kind in domains {
            let value = await ledger.receipt(for: kind)
            let acknowledged = await ledger.acknowledge(try XCTUnwrap(value), current: true, history: true)
            XCTAssertTrue(acknowledged)
        }
        store.markRefreshSucceeded(date: now, refreshedVitals: true, publishesWatch: false)
        store.stageCompletedDashboardFreshness(date: now)
        XCTAssertNotNil(store.currentDashboardPersistenceMetadata().freshness)
        let corrected = expectation(description: "midnight correction")
        store.contextRefreshOverride = { _ in corrected.fulfill() }
        now = now.addingTimeInterval(20)
        await store.syncWhenAppBecomesActive(date: now)
        XCTAssertNil(store.healthSummary.steps.value)
        XCTAssertEqual(store.healthTrends.steps.points.count, 1)
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertNil(store.currentDashboardPersistenceMetadata().freshness)
        // Reproduce coordinator synchronization using the real injected store
        // scope, without attaching observers or querying personal Health data.
        _ = await ledger.synchronize(domains: domains, context: store.currentObserverLedgerContext())
        let pending = await ledger.snapshot()
        XCTAssertTrue(pending.entries.values.allSatisfy { !$0.currentPending && !$0.historyPending },
                      "Midnight must not create observer history work")
        await fulfillment(of: [corrected], timeout: 3)
        store.contextRefreshOverride = { _ in }
    }

    func testLedgerRolloverAcrossDSTPreservesCleanHistoryOnSynchronizeAndReload() async throws {
        let cal = calendar("America/New_York")
        for (start, hours) in [("2026-03-08T05:00:00Z", 23), ("2026-11-01T04:00:00Z", 25)] {
            let dayA = date(start)
            let dayB = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: dayA))
            XCTAssertEqual(dayB.timeIntervalSince(dayA), Double(hours) * 3600)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dirty.json")
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            let ledger = BodyHealthDirtyWorkStore(file: file, domains: [.steps], context: .init(scope: scope(cal, dayA)))
            _ = await ledger.flush()
            let value = await ledger.receipt(for: .steps)
            let acknowledged = await ledger.acknowledge(try XCTUnwrap(value), current: true, history: true)
            XCTAssertTrue(acknowledged)
            let clean = await ledger.snapshot()
            _ = await ledger.synchronize(domains: [.steps], context: .init(scope: scope(cal, dayB.addingTimeInterval(-1))))
            let beforeMidnight = await ledger.snapshot()
            XCTAssertEqual(beforeMidnight, clean, "DST offset changes alone do not replace the context")
            let saved = try Data(contentsOf: file)
            _ = await ledger.synchronize(domains: [.steps], context: .init(scope: scope(cal, dayB)))
            let warm = await ledger.snapshot()
            XCTAssertEqual(warm, clean)
            try saved.write(to: file, options: .atomic)
            let cold = BodyHealthDirtyWorkStore(file: file, domains: [.steps], context: .init(scope: scope(cal, dayB)))
            let coldState = await cold.snapshot()
            XCTAssertEqual(coldState, clean)
        }
    }

    @MainActor
    func testColdHydrationAfterMidnightExpiresTodayAndRetainsHistory() {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let cal = calendar("America/New_York")
        let dayA = date("2026-09-04T03:59:50Z"), dayB = dayA.addingTimeInterval(20)
        let original = snapshot(dayA)
        let prior = makeStore(original, context: { (cal, dayA) })
        let loaded = makeStore(original, context: { (cal, dayB) }, signature: prior.currentDashboardCacheScope().signature)
        loaded.contextRefreshOverride = { _ in }
        XCTAssertNil(loaded.healthSummary.steps.value)
        XCTAssertTrue(loaded.healthSummary.activityRings.isEmpty)
        XCTAssertEqual(loaded.healthSummary.heartRate.value, original.summary.heartRate.value)
        XCTAssertEqual(loaded.healthTrends.steps, original.trends.steps)
        XCTAssertNil(loaded.lastSuccessfulRefreshDate)
        XCTAssertNil(loaded.currentDashboardPersistenceMetadata().freshness)
    }

    @MainActor
    func testZoneChangeBeforeComputeAdmissionRejectsOldBuckets() async {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let now = date("2026-09-04T05:00:00Z")
        var cal = calendar("America/New_York")
        let original = snapshot(now)
        let store = makeStore(original, context: { (cal, now) })
        store.contextRefreshOverride = { _ in }
        store.beforeDashboardComputeCommit = { cal = self.calendar("America/Los_Angeles") }
        let accepted = await store.updateHealthDashboardSnapshot(
            summary: original.summary, trends: original.trends, activityRingHistory: .empty,
            recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false
        )
        XCTAssertFalse(accepted)
        XCTAssertTrue(store.healthTrends.steps.isEmpty)
        XCTAssertEqual(store.healthTrends.heartRateDaySamples, original.trends.heartRateDaySamples)
        XCTAssertEqual(store.healthTrends.recordedReadiness, original.trends.recordedReadiness)
        XCTAssertNil(store.makeSharedPublishInput().summary.steps.value)
    }

    func testLegacyDayKeyExpiresOnlyTodayOnReload() throws {
        let cal = calendar("America/New_York"), now = date("2026-09-04T05:00:00Z")
        var legacy = scope(cal, now)
        legacy.summaryDayStart = nil
        let decoded = try XCTUnwrap(HealthDashboardCacheScope(signature: legacy.signature))
        let original = snapshot(now)
        let next = scope(cal, now).scoping(original, from: decoded)
        XCTAssertNil(next.summary.steps.value)
        XCTAssertEqual(next.trends, original.trends)
        XCTAssertEqual(next.summary.heartRate, original.summary.heartRate)
    }

    func testFailedFullWindowCannotResurrectOldZoneSeries() async throws {
        let now = date("2026-09-04T05:00:00Z")
        let oldCalendar = calendar("America/New_York"), newCalendar = calendar("America/Los_Angeles")
        let original = snapshot(now.addingTimeInterval(-60 * 86_400))
        let scoped = scope(newCalendar, now).scoping(original, from: scope(oldCalendar, now))
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        fake.scriptSources(for: type, .sources([]))
        fake.scriptStatisticsCollection(for: type, .failure(nil))
        let engine = HealthKitFetchEngine(permission: .init(enabledPermissions: [.steps]),
                                         healthDataSourceSelection: .defaultValue,
                                         secondaryHealthDataSourceSelection: .defaultValue,
                                         combinesHealthDataSourcesByName: false, healthStore: fake)
        let selection = BodyDashboardFetchSelection(summaryCards: .init(selectedCards: [.steps]),
                                                   trendCards: .init(selectedCards: []))
        let result = await engine.fetchHealthTrends(calendar: newCalendar, cachedTrends: scoped.trends,
                                                  selection: selection, trendWindowDays: nil)
        XCTAssertTrue(result.hadQueryFailure)
        XCTAssertTrue(fake.leafRequests.contains(.statisticsCollection(type.identifier)))
        XCTAssertTrue(result.trends.steps.isEmpty)
        XCTAssertEqual(result.trends.recordedReadiness, original.trends.recordedReadiness)
    }

    @MainActor
    private func makeStore(_ snapshot: HealthDashboardSnapshot,
                           context: @escaping () -> (calendar: Calendar, date: Date),
                           signature: String? = nil) -> HealthKitWorkoutStore {
        let permission = BodyHealthPermissionSelection(enabledPermissions: [.heart, .steps, .basics, .activityRings])
        var snapshot = snapshot
        // These tests change only calendar context. A mismatched readiness
        // signature would independently schedule an init-time overlay repair
        // and race the frozen-record preservation assertion.
        snapshot.trends.recordedReadinessContext = HealthKitWorkoutStore.readinessRecordContextSignature(
            permissionSelection: permission, healthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false,
            idealSleepDuration: HealthKitWorkoutStore.storedIdealSleepDuration(),
            showsSubMinuteAwakeStages: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
            showsLeadingTrailingAwakeStages: BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages()
        )
        return HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: snapshot,
                              initialSummaryContextSignature: signature,
                              initialPermissionSelection: permission,
                              initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
                              initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
                              engineHealthStore: FakeHealthStore(), calendarContext: context)
    }
}
