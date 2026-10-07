//
//  StressLeafFetchTests.swift
//  BodyTests
//
//  The shared HealthKit leaves behind Stress's intraday inputs, driven against
//  `FakeHealthStore`: the raw sample series (heart rate, SDNN, Recovery HRV),
//  the intraday cumulative series (the Day View's hourly bars and Stress's 15
//  minute movement mask), and the RMSSD fetch with its beat-to-beat scan. The
//  phone's engine and the watch's delta fetcher both call these, so what they
//  pin holds on both devices. The engine's own Stress movement reads are
//  pinned too: the 15 minute request, and the Steps refresh that keeps the
//  mask current only while Stress can score.
//
//  `HKHeartbeatSeriesSample` has no public initializer, so the beat streams
//  themselves can't be scripted; the scan is pinned up to its series query
//  (cap, order, failure, timeout and admission) instead.
//

import XCTest
import HealthKit
@testable import Body

final class StressLeafFetchTests: XCTestCase {
    private struct ScriptedError: Error {}

    private let start = Date(timeIntervalSince1970: 1_788_134_400)
    private let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    // MARK: - quantitySampleSeries

    func testQuantitySampleSeriesDatesEachSampleAtItsEndInAscendingOrder() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        store.scriptSamples(for: type, .samples([
            sample(type, 60, endingAt: start.addingTimeInterval(60)),
            sample(type, 40, endingAt: start.addingTimeInterval(120)),
            sample(type, 72, endingAt: start.addingTimeInterval(180))
        ]))

        let outcome = await BodyHealthQuantityFetch.quantitySampleSeries(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: beatsPerMinute,
            valueTransform: { $0 == 40 ? .nan : $0 * 2 }
        )

        guard case .success(let series) = outcome else {
            return XCTFail("a scripted window is a success")
        }
        XCTAssertEqual(series.points, [
            HealthTrendDataPoint(date: start.addingTimeInterval(60), value: 120),
            HealthTrendDataPoint(date: start.addingTimeInterval(180), value: 144)
        ], "transformed, dated at each sample's end, non-finite dropped")

        let request = try XCTUnwrap(store.sampleRequests.last)
        XCTAssertEqual(request.limit, HKObjectQueryNoLimit)
        XCTAssertEqual(request.sortDescriptors.map(\.key), [HKSampleSortIdentifierEndDate])
        XCTAssertEqual(request.sortDescriptors.map(\.ascending), [true])
    }

    func testQuantitySampleSeriesSeparatesFailureFromEmpty() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN))

        let failingStore = FakeHealthStore()
        failingStore.scriptSamples(for: type, .failure(nil))
        let failureRecorder = FailureRecorder()
        let failed = await BodyHealthQuantityFetch.quantitySampleSeries(
            store: failingStore,
            quantityType: type,
            predicate: nil,
            unit: .secondUnit(with: .milli),
            onFailure: { failureRecorder.record($0) }
        )
        XCTAssertFalse(failed.isSuccess)
        XCTAssertEqual(failureRecorder.count, 1, "a locked device must still report a failure")

        let emptyStore = FakeHealthStore()
        emptyStore.scriptSamples(for: type, .samples([]))
        let emptyRecorder = FailureRecorder()
        let empty = await BodyHealthQuantityFetch.quantitySampleSeries(
            store: emptyStore,
            quantityType: type,
            predicate: nil,
            unit: .secondUnit(with: .milli),
            onFailure: { emptyRecorder.record($0) }
        )
        guard case .success(let series) = empty else {
            return XCTFail("an empty window is a genuine absence, not a failure")
        }
        XCTAssertTrue(series.isEmpty)
        XCTAssertEqual(emptyRecorder.count, 0)
    }

    func testQuantitySampleSeriesFailsSilentlyOnCancellation() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        let recorder = FailureRecorder()
        let unit = beatsPerMinute

        let outcome = await cancelling {
            await BodyHealthQuantityFetch.quantitySampleSeries(
                store: store,
                quantityType: type,
                predicate: nil,
                unit: unit,
                onFailure: { recorder.record($0) }
            )
        }

        XCTAssertFalse(try XCTUnwrap(outcome).isSuccess)
        XCTAssertEqual(recorder.count, 0, "cancellation is not a query failure")
    }

    // MARK: - intradayCumulativeSeries

    func testHourlyCumulativeSeriesDropsIdleAndNonFiniteHours() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        let store = FakeHealthStore()
        let hour: TimeInterval = 3600
        store.scriptCumulativeQuantities(for: type, values: [
            BodyDatedQuantity(date: start, quantity: HKQuantity(unit: .count(), doubleValue: 120)),
            BodyDatedQuantity(date: start.addingTimeInterval(hour), quantity: HKQuantity(unit: .count(), doubleValue: 0)),
            BodyDatedQuantity(date: start.addingTimeInterval(2 * hour), quantity: HKQuantity(unit: .count(), doubleValue: 340)),
            BodyDatedQuantity(date: start.addingTimeInterval(3 * hour), quantity: HKQuantity(unit: .count(), doubleValue: 999))
        ])
        // Mid-hour on purpose: the collection must anchor on the hour itself.
        let windowStart = start.addingTimeInterval(23 * 60)

        let outcome = await BodyHealthQuantityFetch.intradayCumulativeSeries(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: .count(),
            bucket: .hour,
            start: windowStart,
            end: start.addingTimeInterval(4 * hour),
            calendar: .bodyGregorian,
            valueTransform: { $0 == 999 ? .infinity : $0 }
        )

        guard case .success(let series) = outcome else {
            return XCTFail("a scripted window is a success")
        }
        XCTAssertEqual(series.points, [
            HealthTrendDataPoint(date: start, value: 120),
            HealthTrendDataPoint(date: start.addingTimeInterval(2 * hour), value: 340)
        ], "an idle hour and a non-finite one are omitted, not zero bars")

        let request = try XCTUnwrap(store.cumulativeQuantityRequests.last)
        XCTAssertEqual(request.options, .cumulativeSum)
        XCTAssertEqual(request.intervalComponents.hour, 1)
        XCTAssertEqual(request.anchorDate, Calendar.bodyGregorian.dateInterval(of: .hour, for: windowStart)?.start)
    }

    func testHourlyCumulativeSeriesReportsFailureAndFailsSilentlyOnCancellation() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned))
        let windowStart = start
        let windowEnd = start.addingTimeInterval(86_400)

        let failingStore = FakeHealthStore()
        failingStore.scriptStatisticsCollection(for: type, .failure(ScriptedError()))
        let failureRecorder = FailureRecorder()
        let failed = await BodyHealthQuantityFetch.intradayCumulativeSeries(
            store: failingStore,
            quantityType: type,
            predicate: nil,
            unit: .kilocalorie(),
            bucket: .hour,
            start: windowStart,
            end: windowEnd,
            calendar: .bodyGregorian,
            onFailure: { failureRecorder.record($0) }
        )
        XCTAssertFalse(failed.isSuccess)
        XCTAssertEqual(failureRecorder.count, 1)
        XCTAssertTrue((failureRecorder.errors.first ?? nil) is ScriptedError)

        let pendingStore = FakeHealthStore()
        let cancelRecorder = FailureRecorder()
        let cancelled = await cancelling {
            await BodyHealthQuantityFetch.intradayCumulativeSeries(
                store: pendingStore,
                quantityType: type,
                predicate: nil,
                unit: .kilocalorie(),
                bucket: .hour,
                start: windowStart,
                end: windowEnd,
                calendar: .bodyGregorian,
                onFailure: { cancelRecorder.record($0) }
            )
        }
        XCTAssertFalse(try XCTUnwrap(cancelled).isSuccess)
        XCTAssertEqual(cancelRecorder.count, 0, "cancellation is not a query failure")
    }

    /// Stress's bucket: 15 minutes from the day's midnight, whatever time the
    /// window opens, so every bucket is exactly one Stress window.
    func testQuarterHourBucketsAnchorAtMidnightSoEachIsOneStressWindow() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        let store = FakeHealthStore()
        let calendar = Calendar.bodyGregorian
        // Mid-morning and off the grid on purpose: the collection must anchor on
        // the day's midnight, not on the window's start or its hour.
        let windowStart = start.addingTimeInterval(10 * 3_600 + 23 * 60)
        let midnight = calendar.startOfDay(for: windowStart)
        let quarter: TimeInterval = 900
        store.scriptCumulativeQuantities(for: type, values: [
            BodyDatedQuantity(date: midnight.addingTimeInterval(41 * quarter), quantity: HKQuantity(unit: .count(), doubleValue: 120)),
            BodyDatedQuantity(date: midnight.addingTimeInterval(42 * quarter), quantity: HKQuantity(unit: .count(), doubleValue: 0)),
            BodyDatedQuantity(date: midnight.addingTimeInterval(43 * quarter), quantity: HKQuantity(unit: .count(), doubleValue: 340)),
            BodyDatedQuantity(date: midnight.addingTimeInterval(44 * quarter), quantity: HKQuantity(unit: .count(), doubleValue: 999))
        ])

        let outcome = await BodyHealthQuantityFetch.intradayCumulativeSeries(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: .count(),
            bucket: .quarterHour,
            start: windowStart,
            end: windowStart.addingTimeInterval(2 * 3_600),
            calendar: calendar,
            valueTransform: { $0 == 999 ? .nan : $0 }
        )

        guard case .success(let series) = outcome else {
            return XCTFail("a scripted window is a success")
        }
        XCTAssertEqual(series.points, [
            HealthTrendDataPoint(date: midnight.addingTimeInterval(41 * quarter), value: 120),
            HealthTrendDataPoint(date: midnight.addingTimeInterval(43 * quarter), value: 340)
        ], "an idle bucket and a non-finite one are omitted, dated at each bucket's start")

        let request = try XCTUnwrap(store.cumulativeQuantityRequests.last)
        XCTAssertEqual(request.options, .cumulativeSum)
        XCTAssertEqual(request.intervalComponents.minute, 15)
        XCTAssertNil(request.intervalComponents.hour)
        XCTAssertEqual(request.anchorDate, midnight)
    }

    // MARK: - The engine's Stress movement reads

    /// The engine reads Stress's movement through the steps row, in 15 minute
    /// buckets from the midnight it is handed, not the Day View's hours.
    func testStressMovementFetchAsksForQuarterHoursFromMidnight() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        let fake = FakeHealthStore()
        let calendar = Calendar.bodyGregorian
        let midnight = calendar.startOfDay(for: engineNow)
        fake.scriptCumulativeQuantities(for: type, values: [
            BodyDatedQuantity(date: midnight.addingTimeInterval(40 * 900), quantity: HKQuantity(unit: .count(), doubleValue: 420)),
            BodyDatedQuantity(date: midnight.addingTimeInterval(41 * 900), quantity: HKQuantity(unit: .count(), doubleValue: 0))
        ])
        let engine = engine(fake, permissions: [.steps, .heart])

        let fetched = await engine.fetchStressMovementSamples(
            for: .steps,
            calendar: calendar,
            startDate: midnight,
            endDate: midnight.addingTimeInterval(12 * 3_600)
        )

        let series = try XCTUnwrap(fetched, "a scripted read is a success")
        XCTAssertEqual(series.points, [HealthTrendDataPoint(date: midnight.addingTimeInterval(40 * 900), value: 420)])
        let request = try XCTUnwrap(fake.cumulativeQuantityRequests.last)
        XCTAssertEqual(request.quantityType, type)
        XCTAssertEqual(request.options, .cumulativeSum)
        XCTAssertEqual(request.intervalComponents.minute, 15)
        XCTAssertNil(request.intervalComponents.hour)
        XCTAssertEqual(request.anchorDate, midnight)
    }

    /// A Steps refresh keeps Stress's mask current whenever Stress can score
    /// (Heart on), so the background recompute after new steps never scores a
    /// walk; without Heart it carries the cached mask and claims no authority.
    func testStepsRefreshKeepsTheStressMovementMaskCurrentOnlyWithHeart() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: engineNow)
        let bucket = today.addingTimeInterval(36 * 900)
        func scriptedStore() -> FakeHealthStore {
            let fake = FakeHealthStore()
            fake.scriptCumulativeQuantities(for: type, values: [
                BodyDatedQuantity(date: bucket, quantity: HKQuantity(unit: .count(), doubleValue: 640))
            ])
            // Every other leaf of the Steps refresh fails at once, so nothing
            // parks on an unscripted read.
            fake.scriptSources(for: type, .sources([]))
            fake.scriptSamples(for: type, .failure(nil))
            fake.scriptStatisticsCollection(for: type, .failure(nil))
            fake.scriptStatistics(for: type, .failure(nil))
            return fake
        }
        var existing = HealthDashboardSnapshot.empty
        existing.trends.stressStepsDaySamples = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: today.addingTimeInterval(-3 * 86_400), value: 500)
        ])

        let withHeart = scriptedStore()
        let heartEngine = engine(withHeart, permissions: [.steps, .heart])
        await heartEngine.setHealthTrendAnchorDate(engineNow)
        let refreshed = await heartEngine.fetchHealthDashboardSnapshot(for: .steps, calendar: calendar, existing: existing)
        // The cached point sits inside the 48 hour overlap re-read from its
        // day's midnight, so the fresh read replaces it.
        XCTAssertEqual(refreshed.snapshot.trends.stressStepsDaySamples.points, [HealthTrendDataPoint(date: bucket, value: 640)])
        XCTAssertTrue(refreshed.authoritativeDaySampleSeries.contains(.stressStepsDaySamples))
        XCTAssertTrue(withHeart.cumulativeQuantityRequests.contains { $0.intervalComponents.minute == 15 })

        let withoutHeart = scriptedStore()
        let plainEngine = engine(withoutHeart, permissions: [.steps])
        await plainEngine.setHealthTrendAnchorDate(engineNow)
        let carried = await plainEngine.fetchHealthDashboardSnapshot(for: .steps, calendar: calendar, existing: existing)
        XCTAssertEqual(carried.snapshot.trends.stressStepsDaySamples, existing.trends.stressStepsDaySamples)
        XCTAssertFalse(carried.authoritativeDaySampleSeries.contains(.stressStepsDaySamples))
        XCTAssertFalse(withoutHeart.cumulativeQuantityRequests.contains { $0.intervalComponents.minute == 15 })
    }

    // MARK: - BodyHeartbeatRMSSDFetch

    func testLimitsKeepThePhoneScanAndCapTheWatch() {
        let phone = BodyHeartbeatRMSSDFetch.Limits.phone
        XCTAssertEqual(phone.seriesLimit, 120)
        XCTAssertEqual(phone.concurrency, 4)
        XCTAssertEqual(phone.seriesTimeout, .seconds(5))
        XCTAssertEqual(phone.overallTimeout, .seconds(20))

        let watch = BodyHeartbeatRMSSDFetch.Limits.watch
        XCTAssertEqual(watch.seriesLimit, 24)
        XCTAssertEqual(watch.concurrency, 2)
        XCTAssertEqual(watch.seriesTimeout, .seconds(3))
        XCTAssertEqual(watch.overallTimeout, .seconds(6))
    }

    func testRMSSDPrefersRecoveryHRVAndNeverScans() async throws {
        let recoveryType = try recoveryHRVType()
        let store = FakeHealthStore()
        let milliseconds = HKUnit.secondUnit(with: .milli)
        store.scriptSamples(for: recoveryType, .samples([
            HKQuantitySample(
                type: recoveryType,
                quantity: HKQuantity(unit: milliseconds, doubleValue: 41),
                start: start,
                end: start.addingTimeInterval(60)
            )
        ]))

        let outcome = await BodyHeartbeatRMSSDFetch.rmssdSamples(store: store, predicate: nil, limits: .watch)

        guard case .success(let series) = outcome else {
            return XCTFail("Recovery HRV samples are a success")
        }
        XCTAssertEqual(series.points, [HealthTrendDataPoint(date: start.addingTimeInterval(60), value: 41)])
        XCTAssertFalse(store.leafRequests.contains(.samples(HKSeriesType.heartbeat().identifier)),
                       "Recovery HRV hardware never scans")
    }

    func testRMSSDFallsThroughToTheCappedScanWhenRecoveryHRVIsEmpty() async throws {
        let recoveryType = try recoveryHRVType()
        let store = FakeHealthStore()
        store.scriptSamples(for: recoveryType, .samples([]))
        store.scriptSamples(for: HKSeriesType.heartbeat(), .samples([]))

        let outcome = await BodyHeartbeatRMSSDFetch.rmssdSamples(store: store, predicate: nil, limits: .watch)

        guard case .success(let series) = outcome else {
            return XCTFail("a watch that records no beat-to-beat data is a genuine absence")
        }
        XCTAssertTrue(series.isEmpty)
        let scan = try XCTUnwrap(store.sampleRequests.last { $0.sampleType == HKSeriesType.heartbeat() })
        XCTAssertEqual(scan.limit, 24, "the watch scans at most 24 series")
        XCTAssertEqual(scan.sortDescriptors.map(\.key), [HKSampleSortIdentifierEndDate])
        XCTAssertEqual(scan.sortDescriptors.map(\.ascending), [false], "a cap hit starves the oldest series")
    }

    func testRMSSDFallsThroughToTheScanWhenRecoveryHRVFails() async throws {
        let recoveryType = try recoveryHRVType()
        let store = FakeHealthStore()
        store.scriptSamples(for: recoveryType, .failure(nil))
        store.scriptSamples(for: HKSeriesType.heartbeat(), .samples([]))
        let recorder = ContextRecorder()

        let outcome = await BodyHeartbeatRMSSDFetch.rmssdSamples(
            store: store,
            predicate: nil,
            limits: .watch,
            onFailure: { context, _ in recorder.record(context) }
        )

        XCTAssertTrue(outcome.isSuccess, "a failed Recovery read falls through to the scan")
        XCTAssertTrue(store.leafRequests.contains(.samples(HKSeriesType.heartbeat().identifier)))
        XCTAssertEqual(recorder.contexts, [recoveryType.identifier])
    }

    func testScanFailureIsAFailureWithTheSeriesContext() async {
        let store = FakeHealthStore()
        store.scriptSamples(for: HKSeriesType.heartbeat(), .failure(nil))
        let recorder = ContextRecorder()

        let outcome = await BodyHeartbeatRMSSDFetch.scan(
            store: store,
            predicate: nil,
            limits: .phone,
            onFailure: { context, _ in recorder.record(context) }
        )

        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(recorder.contexts, [HKSeriesType.heartbeat().identifier])
        XCTAssertEqual(store.sampleRequests.last?.limit, 120)
    }

    func testScanPastItsOverallTimeoutIsAFailure() async {
        let store = FakeHealthStore()
        // Unscripted: the series query never answers.
        let limits = BodyHeartbeatRMSSDFetch.Limits(
            seriesLimit: 24,
            concurrency: 2,
            seriesTimeout: .milliseconds(100),
            overallTimeout: .milliseconds(200)
        )
        let recorder = ContextRecorder()
        let clock = ContinuousClock()
        let began = clock.now

        let outcome = await BodyHeartbeatRMSSDFetch.scan(
            store: store,
            predicate: nil,
            limits: limits,
            onFailure: { context, _ in recorder.record(context) }
        )

        XCTAssertFalse(outcome.isSuccess, "a timed out scan must never pass for a complete one")
        XCTAssertLessThan(clock.now - began, .seconds(5))
        XCTAssertTrue(recorder.contexts.isEmpty, "the deadline is not a query failure")
    }

    func testScanRunsItsSeriesQueryUnderAdmission() async {
        let admitted = FakeHealthStore()
        admitted.scriptSamples(for: HKSeriesType.heartbeat(), .samples([]))
        let ledger = AdmissionLedger()
        let outcome = await BodyHeartbeatRMSSDFetch.scan(
            store: admitted,
            predicate: nil,
            limits: .phone,
            admission: {
                ledger.enter()
                return { ledger.exit() }
            }
        )
        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(ledger.counts.entered, 1)
        XCTAssertEqual(ledger.counts.exited, 1, "the permit is handed back once the query ends")

        let refused = FakeHealthStore()
        refused.scriptSamples(for: HKSeriesType.heartbeat(), .samples([]))
        let denied = await BodyHeartbeatRMSSDFetch.scan(
            store: refused,
            predicate: nil,
            limits: .phone,
            admission: { nil }
        )
        XCTAssertFalse(denied.isSuccess, "a query that may not run fails the scan")
        XCTAssertTrue(refused.leafRequests.isEmpty)
    }

    // MARK: - Helpers

    /// The engine tests' clock, as in `IntradayRepairTests`.
    private let engineNow = Date(timeIntervalSince1970: 1_788_500_000)

    private func engine(_ fake: FakeHealthStore, permissions: Set<BodyHealthPermission>) -> HealthKitFetchEngine {
        HealthKitFetchEngine(permission: .init(enabledPermissions: permissions),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: fake)
    }

    private func sample(_ type: HKQuantityType, _ value: Double, endingAt end: Date) -> HKQuantitySample {
        HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: beatsPerMinute, doubleValue: value),
            start: end.addingTimeInterval(-30),
            end: end
        )
    }

    private func recoveryHRVType() throws -> HKQuantityType {
        guard let identifier = BodyHeartbeatRMSSDFetch.recoveryHRVIdentifier,
              let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw XCTSkip("Recovery HRV needs iOS 27")
        }
        return type
    }

    /// Runs `work` in a task, cancels it once it is suspended on the fake's
    /// never-answering read, and returns its value; `nil` means the leaf never
    /// came back.
    private func cancelling<Value: Sendable>(
        _ work: @escaping @Sendable () async -> Value
    ) async -> Value? {
        let task = Task { await work() }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let timeout = Task<Value?, Never> {
            try? await Task.sleep(for: .seconds(1))
            return nil
        }
        return await withTaskGroup(of: Value?.self) { group in
            group.addTask { await task.value }
            group.addTask { await timeout.value }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Lock-guarded recorder for a leaf's `onFailure` hook.
private final class FailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Error?] = []

    func record(_ error: Error?) {
        lock.lock(); recorded.append(error); lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }; return recorded.count
    }

    var errors: [Error?] {
        lock.lock(); defer { lock.unlock() }; return recorded
    }
}

/// Lock-guarded recorder for the RMSSD fetch's `(context, error)` hook.
private final class ContextRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func record(_ context: String) {
        lock.lock(); recorded.append(context); lock.unlock()
    }

    var contexts: [String] {
        lock.lock(); defer { lock.unlock() }; return recorded
    }
}

/// Counts a scripted admission's grants and releases.
private final class AdmissionLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = 0
    private var exited = 0

    func enter() {
        lock.lock(); entered += 1; lock.unlock()
    }

    func exit() {
        lock.lock(); exited += 1; lock.unlock()
    }

    var counts: (entered: Int, exited: Int) {
        lock.lock(); defer { lock.unlock() }; return (entered, exited)
    }
}
