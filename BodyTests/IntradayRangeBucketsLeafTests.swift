//
//  IntradayRangeBucketsLeafTests.swift
//  BodyTests
//
//  `BodyHealthQuantityFetch.intradayRangeBuckets`, driven against
//  `FakeHealthStore`: the 30 minute "Last 8 hours" slots the watch's Heart
//  Rate and HRV detail pages read on demand (`WatchHealthStore.intradayBuckets`)
//  and the watch compute reads for their chart complications
//  (`WatchDeltaFetcher`, `WatchMetricsSnapshot.heartCharts`), so what these
//  pin holds for both:
//  * the collection it runs (average + min + max, 30 minute intervals
//    anchored at the window's own start, the caller's predicate untouched),
//    which no scripted answer can show;
//  * the slot rule, the same as `dailyQuantityRangeSeries`' day rule: a slot
//    is a bucket only when its minimum, maximum and average are all present
//    and finite, dated at the slot's start;
//  * the tri-state contract (`HealthKitLeafFailureSemanticsTests`): an empty
//    window is a success, a failure (a locked watch's `failure(nil)`
//    included) reports once, and a cancellation fails without reporting;
//  * the descriptor rows the compute takes its type and unit from, which
//    must stay the page's own (SDNN in ms, beats per minute, no transform),
//    so a complication and its page can't read different numbers.
//

import XCTest
import HealthKit
@testable import Body

final class IntradayRangeBucketsLeafTests: XCTestCase {
    private struct ScriptedError: Error {}

    private let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
    private let slot = WatchIntradayWindow.slotLength
    /// The window's oldest slot start, 00:30 UTC: on a half hour, not a whole
    /// one, so the anchor assertions can tell "the window's start" from "its
    /// hour".
    private let start = Date(timeIntervalSince1970: 1_788_134_400 + 1_800)

    // MARK: - The collection

    func testRunsAnAverageMinMaxCollectionInHalfHourSlotsAnchoredAtTheWindowStart() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        store.scriptDailyQuantityRanges(for: type, values: [])
        // The page's own predicate: open ended, so a series that started
        // before the window still contributes its in-window beats.
        let predicate = try XCTUnwrap(BodyHealthSourceResolver.combinedPredicate(startDate: start, endDate: nil))

        _ = await BodyHealthQuantityFetch.intradayRangeBuckets(
            store: store,
            quantityType: type,
            predicate: predicate,
            unit: beatsPerMinute,
            start: start,
            end: start.addingTimeInterval(16 * slot + 600)
        )

        // Wrong options would make HealthKit return no min or max, which no
        // script can show.
        let request = try XCTUnwrap(store.dailyQuantityRangeRequests.last)
        XCTAssertEqual(request.quantityType, type)
        XCTAssertEqual(request.options, [.discreteAverage, .discreteMin, .discreteMax])
        XCTAssertEqual(request.anchorDate, start, "the window's start is already on the slot grid")
        XCTAssertEqual(request.intervalComponents, DateComponents(minute: 30))
        XCTAssertEqual(request.predicate, predicate, "the caller's predicate runs untouched")
    }

    // MARK: - The slot rule

    /// The page's rule, now shared: a slot without all three statistics, or
    /// with one that isn't finite, is no bucket at all, and a kept one is
    /// dated at its own start with its values in the caller's unit.
    func testKeepsOnlyCompleteFiniteSlotsDatedAtTheirStart() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let unit = beatsPerMinute
        func bpm(_ value: Double?) -> HKQuantity? {
            value.map { HKQuantity(unit: unit, doubleValue: $0) }
        }
        func range(_ index: Double, min: Double?, max: Double?, average: Double?) -> BodyDatedQuantityRange {
            BodyDatedQuantityRange(
                date: start.addingTimeInterval(index * slot),
                minimum: bpm(min),
                maximum: bpm(max),
                average: bpm(average)
            )
        }
        let store = FakeHealthStore()
        store.scriptDailyQuantityRanges(for: type, values: [
            range(0, min: 55, max: 75, average: 64),
            range(1, min: nil, max: 75, average: 64),
            range(2, min: 55, max: nil, average: 64),
            range(3, min: 55, max: 75, average: nil),
            range(4, min: -Double.infinity, max: 75, average: 64),
            range(5, min: 55, max: Double.infinity, average: 64),
            range(6, min: 55, max: 75, average: Double.nan),
            range(16, min: 56, max: 70, average: 62)
        ])

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.intradayRangeBuckets(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: unit,
            start: start,
            end: start.addingTimeInterval(16 * slot + 600),
            onFailure: { recorder.record($0) }
        )

        guard case .success(let buckets) = outcome else {
            return XCTFail("a scripted collection must succeed")
        }
        XCTAssertEqual(buckets, [
            WatchIntradayBucket(start: start, minimum: 55, maximum: 75, average: 64),
            WatchIntradayBucket(start: start.addingTimeInterval(16 * slot), minimum: 56, maximum: 70, average: 62)
        ])
        XCTAssertEqual(recorder.count, 0)
    }

    /// The values come back in the unit asked for, whatever unit HealthKit
    /// holds them in: SDNN stored in seconds reads in milliseconds.
    func testReadsEachSlotInTheCallersUnit() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        let seconds = HKUnit.second()
        let store = FakeHealthStore()
        store.scriptDailyQuantityRanges(for: type, values: [
            BodyDatedQuantityRange(
                date: start,
                minimum: HKQuantity(unit: seconds, doubleValue: 0.043),
                maximum: HKQuantity(unit: seconds, doubleValue: 0.053),
                average: HKQuantity(unit: seconds, doubleValue: 0.048)
            )
        ])

        let outcome = await BodyHealthQuantityFetch.intradayRangeBuckets(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: .secondUnit(with: .milli),
            start: start,
            end: start.addingTimeInterval(slot)
        )

        guard case .success(let buckets) = outcome, let bucket = buckets.first else {
            return XCTFail("a scripted collection must succeed")
        }
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(bucket.minimum, 43, accuracy: 1e-9)
        XCTAssertEqual(bucket.maximum, 53, accuracy: 1e-9)
        XCTAssertEqual(bucket.average, 48, accuracy: 1e-9)
    }

    // MARK: - Failure semantics

    func testAnEmptyWindowIsASuccess() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        let store = FakeHealthStore()
        store.scriptDailyQuantityRanges(for: type, values: [])

        let recorder = FailureRecorder()
        let outcome = await BodyHealthQuantityFetch.intradayRangeBuckets(
            store: store,
            quantityType: type,
            predicate: nil,
            unit: .secondUnit(with: .milli),
            start: start,
            end: start.addingTimeInterval(16 * slot),
            onFailure: { recorder.record($0) }
        )

        guard case .success(let buckets) = outcome else {
            return XCTFail("an empty window is a genuine absence, not a failure")
        }
        XCTAssertTrue(buckets.isEmpty)
        XCTAssertEqual(recorder.count, 0)
    }

    func testAFailureFailsAndReportsOnce() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))

        let lockedStore = FakeHealthStore()
        lockedStore.scriptStatisticsCollection(for: type, .failure(nil))
        let lockedRecorder = FailureRecorder()
        let locked = await BodyHealthQuantityFetch.intradayRangeBuckets(
            store: lockedStore,
            quantityType: type,
            predicate: nil,
            unit: beatsPerMinute,
            start: start,
            end: start.addingTimeInterval(16 * slot),
            onFailure: { lockedRecorder.record($0) }
        )
        XCTAssertFalse(locked.isSuccess)
        XCTAssertEqual(lockedRecorder.count, 1, "a locked watch must still report a failure")
        XCTAssertNil(lockedRecorder.errors.first ?? nil, "`failure(nil)` must not invent an error")

        let failingStore = FakeHealthStore()
        failingStore.scriptStatisticsCollection(for: type, .failure(ScriptedError()))
        let failingRecorder = FailureRecorder()
        let failed = await BodyHealthQuantityFetch.intradayRangeBuckets(
            store: failingStore,
            quantityType: type,
            predicate: nil,
            unit: beatsPerMinute,
            start: start,
            end: start.addingTimeInterval(16 * slot),
            onFailure: { failingRecorder.record($0) }
        )
        XCTAssertFalse(failed.isSuccess)
        XCTAssertEqual(failingRecorder.count, 1)
        XCTAssertTrue((failingRecorder.errors.first ?? nil) is ScriptedError)
    }

    func testCancellationFailsWithoutReporting() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let store = FakeHealthStore()
        let recorder = FailureRecorder()
        let unit = beatsPerMinute
        let start = self.start
        let end = start.addingTimeInterval(16 * slot)

        let outcome = await cancelling {
            await BodyHealthQuantityFetch.intradayRangeBuckets(
                store: store,
                quantityType: type,
                predicate: nil,
                unit: unit,
                start: start,
                end: end,
                onFailure: { recorder.record($0) }
            )
        }

        XCTAssertFalse(try XCTUnwrap(outcome).isSuccess)
        XCTAssertEqual(recorder.count, 0, "cancellation is not a query failure")
    }

    // MARK: - The compute reads the page's type and unit

    /// The page spells its rows as literals (`WatchHealthStore.intradayQuery`);
    /// the compute reads the descriptor table. Pinning the table to the same
    /// literals, and to no transform (the leaf takes none), keeps the
    /// complication and the page on one type and one unit.
    func testTheDescriptorRowsMatchThePagesTypeAndUnit() throws {
        let heartRate = try XCTUnwrap(HealthMetricQueryDescriptor.descriptor(for: .heartRate))
        XCTAssertEqual(heartRate.quantityType, .heartRate)
        XCTAssertEqual(heartRate.unit, HKUnit.count().unitDivided(by: .minute()))
        XCTAssertEqual(heartRate.sourceKind, .heartRate)
        XCTAssertEqual(heartRate.valueTransform(73), 73)

        let hrv = try XCTUnwrap(HealthMetricQueryDescriptor.descriptor(for: .heartRateVariability))
        XCTAssertEqual(hrv.quantityType, .heartRateVariabilitySDNN, "SDNN, the type the HRV page reads")
        XCTAssertEqual(hrv.unit, .secondUnit(with: .milli))
        XCTAssertEqual(hrv.sourceKind, .heartRateVariability)
        XCTAssertEqual(hrv.valueTransform(48), 48)
    }

    // MARK: - Helpers

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

/// Lock-guarded recorder for the leaf's `onFailure` hook.
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
