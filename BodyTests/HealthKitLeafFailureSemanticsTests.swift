//
//  HealthKitLeafFailureSemanticsTests.swift
//  BodyTests
//
//  The shared HealthKit query leaves, driven against `FakeHealthStore`.
//
//  What these pin is the tri-state contract the whole cache-preservation story
//  rests on: a query FAILURE (including HealthKit's "neither samples nor an
//  error" on a locked device, i.e. `failure(nil)`) must stay distinguishable
//  from a genuine EMPTY result, and a CANCELLED read must fail WITHOUT
//  reporting a failure — cancellation is the caller losing a race, not
//  HealthKit misbehaving, and logging it as a failure is what used to make a
//  dismissed sheet look like a broken store.
//

import XCTest
import HealthKit
@testable import Body

final class HealthKitLeafFailureSemanticsTests: XCTestCase {
    private struct ScriptedError: Error {}

    /// How long a cancelled leaf read gets to come back. Cancellation is
    /// cooperative but immediate here; a second is pure slack.
    private static let cancellationTimeout: TimeInterval = 1

    // MARK: - latestQuantitySample

    func testLatestQuantitySampleReportsScriptedError() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        let error = ScriptedError()
        store.scriptSamples(for: type, .failure(error))

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.latestQuantitySample(
            store: store,
            quantityType: type,
            predicate: nil,
            onFailure: { recorder.record($0) }
        )

        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue((recorder.errors.first ?? nil) is ScriptedError)
    }

    func testLatestQuantitySampleReportsNilErrorFailure() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        store.scriptSamples(for: type, .failure(nil))

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.latestQuantitySample(
            store: store,
            quantityType: type,
            predicate: nil,
            onFailure: { recorder.record($0) }
        )

        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(recorder.count, 1, "a locked device must still report a failure")
        XCTAssertNil(recorder.errors.first ?? nil, "`failure(nil)` must not invent an error")
    }

    func testLatestQuantitySampleTreatsNoSamplesAsSuccess() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        store.scriptSamples(for: type, .samples([]))

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.latestQuantitySample(
            store: store,
            quantityType: type,
            predicate: nil,
            onFailure: { recorder.record($0) }
        )

        guard case .success(let sample) = outcome else {
            return XCTFail("an empty window is a genuine absence, not a failure")
        }
        XCTAssertNil(sample)
        XCTAssertEqual(recorder.count, 0)
    }

    func testLatestQuantitySampleFailsSilentlyOnCancellation() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        let recorder = FailureRecorder()

        let outcome = await cancelling {
            await BodyHealthQuantityFetch.latestQuantitySample(
                store: store,
                quantityType: type,
                predicate: nil,
                onFailure: { recorder.record($0) }
            )
        }

        XCTAssertFalse(try XCTUnwrap(outcome).isSuccess)
        XCTAssertEqual(recorder.count, 0, "cancellation is not a query failure")
    }

    // MARK: - mostRecentQuantity

    func testMostRecentQuantityReportsScriptedError() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        store.scriptStatistics(for: type, .failure(ScriptedError()))

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.mostRecentQuantity(
            store: store,
            quantityType: type,
            predicate: nil,
            onFailure: { recorder.record($0) }
        )

        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(recorder.count, 1)
    }

    func testMostRecentQuantityFailsSilentlyOnCancellation() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        let recorder = FailureRecorder()

        let outcome = await cancelling {
            await BodyHealthQuantityFetch.mostRecentQuantity(
                store: store,
                quantityType: type,
                predicate: nil,
                onFailure: { recorder.record($0) }
            )
        }

        XCTAssertFalse(try XCTUnwrap(outcome).isSuccess)
        XCTAssertEqual(recorder.count, 0)
    }

    // MARK: - dailyQuantitySeries / dailyQuantitySummary

    func testDailyQuantitySeriesReportsNilErrorFailure() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .restingHeartRate))
        let store = FakeHealthStore()
        store.scriptStatisticsCollection(for: type, .failure(nil))

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.dailyQuantitySeries(
            store: store,
            quantityType: type,
            predicate: nil,
            aggregation: .average,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: Date(timeIntervalSince1970: 1_788_134_400),
            end: Date(timeIntervalSince1970: 1_788_220_800),
            calendar: .bodyGregorian,
            onFailure: { recorder.record($0) }
        )

        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertNil(recorder.errors.first ?? nil)
    }

    func testDailyQuantitySummaryPropagatesFailureWithoutDoubleReporting() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .restingHeartRate))
        let store = FakeHealthStore()
        store.scriptStatisticsCollection(for: type, .failure(ScriptedError()))

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.dailyQuantitySummary(
            store: store,
            quantityType: type,
            predicate: nil,
            aggregation: .average,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: Date(timeIntervalSince1970: 1_788_134_400),
            end: Date(timeIntervalSince1970: 1_788_220_800),
            calendar: .bodyGregorian,
            onFailure: { recorder.record($0) }
        )

        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(recorder.count, 1, "the summary must not re-report its series' failure")
    }

    // MARK: - dailyQuantityRangeSeries

    /// The phone's range point rule (`fetchDailyQuantityAverageAndRangeSeries`):
    /// a day is a point only when its average, minimum and maximum are all
    /// present and finite after `valueTransform`, dated to the day's start.
    func testDailyQuantityRangeSeriesKeepsOnlyCompleteFiniteDaysAtTheirStartOfDay() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let unit = HKUnit.count().unitDivided(by: .minute())
        let calendar = Calendar.bodyGregorian
        func noon(_ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12)))
        }
        func bpm(_ value: Double?) -> HKQuantity? {
            value.map { HKQuantity(unit: unit, doubleValue: $0) }
        }
        func range(_ day: Int, min: Double?, max: Double?, average: Double?) throws -> BodyDatedQuantityRange {
            BodyDatedQuantityRange(date: try noon(day), minimum: bpm(min), maximum: bpm(max), average: bpm(average))
        }
        let store = FakeHealthStore()
        store.scriptDailyQuantityRanges(for: type, values: [
            try range(1, min: 50, max: 90, average: 70),
            try range(2, min: nil, max: 90, average: 70),
            try range(3, min: 50, max: nil, average: 70),
            try range(4, min: 50, max: 90, average: nil),
            // 13 transforms to infinity below: dropped for a non-finite low,
            // high, or average alike.
            try range(5, min: 13, max: 90, average: 70),
            try range(6, min: 50, max: 13, average: 70),
            try range(7, min: 50, max: 90, average: 13),
            try range(8, min: 55, max: 95, average: 75)
        ])
        let start = try noon(1)
        let end = try noon(8)

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.dailyQuantityRangeSeries(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: unit,
            start: start,
            end: end,
            calendar: calendar,
            valueTransform: { $0 == 13 ? .infinity : $0 * 2 },
            onFailure: { recorder.record($0) }
        )

        guard case .success(let series) = outcome else {
            return XCTFail("a scripted collection must succeed")
        }
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        XCTAssertEqual(series, HealthTrendRangeSeries(points: [
            HealthTrendRangeDataPoint(date: firstDay, lowValue: 100, highValue: 180, averageValue: 140),
            HealthTrendRangeDataPoint(date: lastDay, lowValue: 110, highValue: 190, averageValue: 150)
        ]))
        XCTAssertEqual(recorder.count, 0)

        // The collection the phone runs: average + min + max, one-day
        // intervals anchored at the window's first midnight. Wrong options
        // would make HealthKit return no min or max, which no script can show.
        let request = try XCTUnwrap(store.dailyQuantityRangeRequests.last)
        XCTAssertEqual(request.options, [.discreteAverage, .discreteMin, .discreteMax])
        XCTAssertEqual(request.anchorDate, calendar.startOfDay(for: start))
        XCTAssertEqual(request.intervalComponents, DateComponents(day: 1))
    }

    func testDailyQuantityRangeSeriesTreatsNoDaysAsSuccess() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        let store = FakeHealthStore()
        store.scriptDailyQuantityRanges(for: type, values: [])

        let outcome = await BodyHealthQuantityFetch.dailyQuantityRangeSeries(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: .secondUnit(with: .milli),
            start: Date(timeIntervalSince1970: 1_788_134_400),
            end: Date(timeIntervalSince1970: 1_788_220_800),
            calendar: .bodyGregorian
        )

        guard case .success(let series) = outcome else {
            return XCTFail("an empty window is a genuine absence, not a failure")
        }
        XCTAssertTrue(series.isEmpty)
    }

    func testDailyQuantityRangeSeriesReportsNilErrorFailure() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        store.scriptStatisticsCollection(for: type, .failure(nil))

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.dailyQuantityRangeSeries(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: Date(timeIntervalSince1970: 1_788_134_400),
            end: Date(timeIntervalSince1970: 1_788_220_800),
            calendar: .bodyGregorian,
            onFailure: { recorder.record($0) }
        )

        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(recorder.count, 1, "a locked device must still report a failure")
        XCTAssertNil(recorder.errors.first ?? nil)
    }

    func testDailyQuantityRangeSeriesFailsSilentlyOnCancellation() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        let recorder = FailureRecorder()

        let outcome = await cancelling {
            await BodyHealthQuantityFetch.dailyQuantityRangeSeries(
                store: store,
                quantityType: type,
                predicate: nil,
                unit: HKUnit.count().unitDivided(by: .minute()),
                start: Date(timeIntervalSince1970: 1_788_134_400),
                end: Date(timeIntervalSince1970: 1_788_220_800),
                calendar: .bodyGregorian,
                onFailure: { recorder.record($0) }
            )
        }

        XCTAssertFalse(try XCTUnwrap(outcome).isSuccess)
        XCTAssertEqual(recorder.count, 0, "cancellation is not a query failure")
    }

    // MARK: - sleepSamples

    func testSleepSamplesReportsScriptedErrorAndEmptyIsSuccess() async throws {
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let failingStore = FakeHealthStore()
        failingStore.scriptSamples(for: sleepType, .failure(ScriptedError()))
        let failureRecorder = FailureRecorder()
        let failed = await BodySleepFetch.sleepSamples(
            store: failingStore,
            predicate: nil,
            sort: sort,
            onFailure: { failureRecorder.record($0) }
        )
        XCTAssertFalse(failed.isSuccess)
        XCTAssertEqual(failureRecorder.count, 1)

        let emptyStore = FakeHealthStore()
        emptyStore.scriptSamples(for: sleepType, .samples([]))
        let emptyRecorder = FailureRecorder()
        let empty = await BodySleepFetch.sleepSamples(
            store: emptyStore,
            predicate: nil,
            sort: sort,
            onFailure: { emptyRecorder.record($0) }
        )
        guard case .success(let samples) = empty else {
            return XCTFail("a night with no samples is a genuine absence")
        }
        XCTAssertTrue(samples.isEmpty)
        XCTAssertEqual(emptyRecorder.count, 0)
    }

    func testSleepSamplesFailsSilentlyOnCancellation() async throws {
        let store = FakeHealthStore()
        let recorder = FailureRecorder()
        let outcome = await cancelling {
            await BodySleepFetch.sleepSamples(
                store: store,
                predicate: nil,
                sort: NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false),
                onFailure: { recorder.record($0) }
            )
        }

        XCTAssertFalse(try XCTUnwrap(outcome).isSuccess)
        XCTAssertEqual(recorder.count, 0)
    }

    // MARK: - vitalWindowSamples

    func testVitalWindowSamplesReportsNilErrorFailure() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        store.scriptSamples(for: type, .failure(nil))

        let night = DateInterval(
            start: Date(timeIntervalSince1970: 1_788_134_400),
            end: Date(timeIntervalSince1970: 1_788_163_200)
        )
        let recorder = FailureRecorder()
        let outcome = await BodySleepFetch.vitalWindowSamples(
            store: store,
            quantityType: type,
            intervals: [night],
            sourcePredicate: nil,
            unit: HKUnit.count().unitDivided(by: .minute()),
            onFailure: { recorder.record($0) }
        )

        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertNil(recorder.errors.first ?? nil)
    }

    // MARK: - workouts

    func testWorkoutsReportsFailureAndTreatsEmptyAsSuccess() async {
        let failingStore = FakeHealthStore()
        failingStore.scriptSamples(for: HKObjectType.workoutType(), .failure(ScriptedError()))
        let failureRecorder = FailureRecorder()
        let failed = await BodyWorkoutFetch.workouts(
            store: failingStore,
            start: Date(timeIntervalSince1970: 1_788_134_400),
            end: Date(timeIntervalSince1970: 1_788_220_800),
            onFailure: { failureRecorder.record($0) }
        )
        XCTAssertFalse(failed.isSuccess)
        XCTAssertEqual(failureRecorder.count, 1)

        let emptyStore = FakeHealthStore()
        emptyStore.scriptSamples(for: HKObjectType.workoutType(), .samples([]))
        let emptyRecorder = FailureRecorder()
        let empty = await BodyWorkoutFetch.workouts(
            store: emptyStore,
            start: Date(timeIntervalSince1970: 1_788_134_400),
            end: Date(timeIntervalSince1970: 1_788_220_800),
            onFailure: { emptyRecorder.record($0) }
        )
        guard case .success(let workouts) = empty else {
            return XCTFail("a window with no workouts is a genuine absence")
        }
        XCTAssertTrue(workouts.isEmpty)
        XCTAssertEqual(emptyRecorder.count, 0)
    }

    func testWorkoutsFailsOnCancellation() async throws {
        let store = FakeHealthStore()
        let recorder = FailureRecorder()

        let outcome = await cancelling {
            await BodyWorkoutFetch.workouts(
                store: store,
                start: Date(timeIntervalSince1970: 1_788_134_400),
                end: Date(timeIntervalSince1970: 1_788_220_800),
                onFailure: { recorder.record($0) }
            )
        }

        XCTAssertFalse(try XCTUnwrap(outcome).isSuccess)
        XCTAssertEqual(recorder.count, 0)
    }

    // MARK: - savedEffortOutcome

    func testSavedEffortOutcomeSeparatesFailureFromNoSavedEffort() async throws {
        let effortType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .workoutEffortScore))
        let workout = Self.makeWorkout()

        let failingStore = FakeHealthStore()
        failingStore.scriptSamples(for: effortType, .failure(nil))
        guard case .failed = await BodyWorkoutEffortFetcher.savedEffortOutcome(
            for: workout,
            store: failingStore
        ) else {
            return XCTFail("a failed effort query must stay retryable")
        }

        let emptyStore = FakeHealthStore()
        emptyStore.scriptSamples(for: effortType, .samples([]))
        guard case .noSavedEffort = await BodyWorkoutEffortFetcher.savedEffortOutcome(
            for: workout,
            store: emptyStore
        ) else {
            return XCTFail("an empty effort query is a confirmed absence, not a failure")
        }
    }

    func testSavedEffortOutcomeFailsOnCancellation() async throws {
        let store = FakeHealthStore()
        let workout = Self.makeWorkout()

        let outcome = await cancelling {
            await BodyWorkoutEffortFetcher.savedEffortOutcome(for: workout, store: store)
        }

        guard case .failed = try XCTUnwrap(outcome) else {
            return XCTFail("a cancelled effort query must not be cached as score-less")
        }
    }

    // MARK: - discoverSources

    func testDiscoverSourcesReportsFailureWithQueryContext() async throws {
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let store = FakeHealthStore()
        store.scriptSources(for: sleepType, .failure(ScriptedError()))

        let recorder = ContextFailureRecorder()
        let sources = await BodyHealthSourceResolver.discoverSources(
            for: sleepType,
            store: store,
            onFailure: { recorder.record($0, $1) }
        )

        XCTAssertNil(sources)
        XCTAssertEqual(recorder.contexts, ["sources:\(sleepType.identifier)"])
    }

    func testDiscoverSourcesTreatsEmptySourcesAsSuccess() async throws {
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let store = FakeHealthStore()
        store.scriptSources(for: sleepType, .sources([]))

        let recorder = ContextFailureRecorder()
        let sources = await BodyHealthSourceResolver.discoverSources(
            for: sleepType,
            store: store,
            onFailure: { recorder.record($0, $1) }
        )

        XCTAssertEqual(sources?.count, 0)
        XCTAssertTrue(recorder.contexts.isEmpty)
    }

    func testDiscoverSourcesFailsSilentlyOnCancellation() async throws {
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let store = FakeHealthStore()
        let recorder = ContextFailureRecorder()

        let sources = await cancelling {
            await BodyHealthSourceResolver.discoverSources(
                for: sleepType,
                store: store,
                onFailure: { recorder.record($0, $1) }
            )
        }

        XCTAssertNil(try XCTUnwrap(sources))
        XCTAssertTrue(recorder.contexts.isEmpty, "cancellation is not a query failure")
    }

    // MARK: - Helpers

    /// Runs `work` in a task, cancels it, and returns its value — proving the
    /// leaf comes back rather than pinning the caller on a query that will
    /// never resume. `nil` means the leaf never returned in time.
    private func cancelling<Value: Sendable>(
        _ work: @escaping @Sendable () async -> Value
    ) async -> Value? {
        let task = Task { await work() }
        // Let the leaf reach its suspension point before cancelling, so this
        // exercises cancel-while-armed rather than cancel-before-install.
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let timeout = Task<Value?, Never> {
            try? await Task.sleep(for: .seconds(Self.cancellationTimeout))
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

    private static func makeWorkout() -> HKWorkout {
        makeTestWorkout(
            activityType: .running,
            start: Date(timeIntervalSince1970: 1_788_134_400),
            end: Date(timeIntervalSince1970: 1_788_138_000),
            metadata: nil
        )
    }
}

/// Lock-guarded recorder for the leaves' `onFailure` hook.
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

/// Lock-guarded recorder for source discovery's `(context, error)` hook.
private final class ContextFailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func record(_ context: String, _ error: Error?) {
        lock.lock(); recorded.append(context); lock.unlock()
    }

    var contexts: [String] {
        lock.lock(); defer { lock.unlock() }; return recorded
    }
}
