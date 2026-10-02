//
//  WatchIntradayChartStoreTests.swift
//  BodyWatchTests
//
//  Locks the read rules of the "Last 8 hours" charts
//  (`WatchIntradayChartStore.refreshIfStale`): a kind is read at most once per
//  `refreshInterval`, counted from the last read that FINISHED; a nil read
//  keeps the chart but still starts the wait, an empty one removes it; a read
//  that was cancelled, or that was in flight when `clear()` ran, lands nothing
//  and records nothing; and only the Heart Rate and HRV kinds ever read.
//
//  The clock and the HealthKit read are both injected. A held read parks
//  inside the loader until the test releases it, and signals its arrival
//  through a continuation, so nothing here sleeps or polls.
//

import XCTest
@testable import BodyWatch

@MainActor
final class WatchIntradayChartStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let heartRate = WatchMetricKindKey.heartRate
    private let hrv = WatchMetricKindKey.heartRateVariability
    private var interval: TimeInterval { WatchIntradayChartStore.refreshInterval }

    private final class Clock {
        var now: Date
        init(now: Date) { self.now = now }
    }

    private struct Call: Equatable {
        let kind: String
        let window: WatchIntradayWindow
    }

    /// The scripted read. Records every call and answers from `results` in
    /// order; a read past the end of the script fails the test, so a scripted
    /// nil ("keep the chart") is never confused with a missing answer. While
    /// `holdsReads` is set, each read parks until `release()`.
    @MainActor
    private final class Loader {
        private(set) var calls: [Call] = []
        var results: [[WatchIntradayBucket]?] = []
        var holdsReads = false
        /// Runs inside each read, after any park: a read that takes time.
        var duringRead: (() -> Void)?
        private var parkedRead: CheckedContinuation<Void, Never>?
        private var arrivalWaiter: CheckedContinuation<Void, Never>?

        func load(_ kind: String, _ window: WatchIntradayWindow) async -> [WatchIntradayBucket]? {
            calls.append(Call(kind: kind, window: window))
            if holdsReads {
                await withCheckedContinuation { continuation in
                    parkedRead = continuation
                    arrivalWaiter?.resume()
                    arrivalWaiter = nil
                }
            }
            duringRead?()
            guard !results.isEmpty else {
                XCTFail("unscripted read of \(kind)")
                return nil
            }
            return results.removeFirst()
        }

        /// Returns once a held read has parked.
        func waitForParkedRead() async {
            guard parkedRead == nil else { return }
            await withCheckedContinuation { arrivalWaiter = $0 }
        }

        func release() {
            parkedRead?.resume()
            parkedRead = nil
        }
    }

    private func makeStore() -> (WatchIntradayChartStore, Clock, Loader) {
        let clock = Clock(now: t0)
        let loader = Loader()
        let store = WatchIntradayChartStore(now: { clock.now }) { kind, window in
            await loader.load(kind, window)
        }
        return (store, clock, loader)
    }

    /// The store doesn't place or validate slots, so one slot is enough to
    /// tell two reads apart.
    private func buckets(_ average: Double) -> [WatchIntradayBucket] {
        [WatchIntradayBucket(start: t0, minimum: average - 5, maximum: average + 5, average: average)]
    }

    // MARK: - Reading and the interval

    func testFirstRefreshReadsTheWindowEndingNowAndPublishesTheChart() async {
        let (store, _, loader) = makeStore()
        loader.results = [buckets(62)]

        let wait = await store.refreshIfStale(kind: heartRate)

        let window = WatchIntradayWindow.endingAt(t0)
        XCTAssertEqual(loader.calls, [Call(kind: heartRate, window: window)])
        XCTAssertEqual(store.charts[heartRate], WatchIntradayChart(window: window, buckets: buckets(62)))
        XCTAssertEqual(wait, interval)
    }

    func testARefreshInsideTheIntervalWaitsAndOneAfterItReads() async {
        let (store, clock, loader) = makeStore()
        loader.results = [buckets(62), buckets(70)]
        await store.refreshIfStale(kind: heartRate)

        clock.now = t0.addingTimeInterval(120)
        let wait = await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(wait, 180, "the time left, not the whole interval")
        XCTAssertEqual(loader.calls.count, 1)

        clock.now = t0.addingTimeInterval(interval)
        let next = await store.refreshIfStale(kind: heartRate)
        let window = WatchIntradayWindow.endingAt(clock.now)
        XCTAssertEqual(loader.calls.last, Call(kind: heartRate, window: window))
        XCTAssertEqual(loader.calls.count, 2)
        XCTAssertEqual(store.charts[heartRate], WatchIntradayChart(window: window, buckets: buckets(70)))
        XCTAssertEqual(next, interval)
    }

    /// Counted from the finish: a slow read must not eat into the wait.
    func testTheIntervalCountsFromWhenTheReadFinished() async {
        let (store, clock, loader) = makeStore()
        loader.results = [buckets(62), buckets(70)]
        let finishedAt = t0.addingTimeInterval(30)
        loader.duringRead = { clock.now = finishedAt }
        await store.refreshIfStale(kind: heartRate)
        loader.duringRead = nil

        clock.now = t0.addingTimeInterval(interval)
        let wait = await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(wait, 30)
        XCTAssertEqual(loader.calls.count, 1)

        clock.now = t0.addingTimeInterval(30 + interval)
        await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(loader.calls.count, 2)
    }

    /// The clock moved back: the attempt is in the future, and parking the
    /// read until the clock caught up would freeze the chart.
    func testAFutureDatedAttemptCountsAsStale() async {
        let (store, clock, loader) = makeStore()
        loader.results = [buckets(62), buckets(70)]
        await store.refreshIfStale(kind: heartRate)

        clock.now = t0.addingTimeInterval(-60)
        let wait = await store.refreshIfStale(kind: heartRate)

        XCTAssertEqual(loader.calls.count, 2)
        XCTAssertEqual(store.charts[heartRate]?.buckets, buckets(70))
        XCTAssertEqual(wait, interval)
    }

    /// A failed read (a locked watch) keeps what's on screen, and is still
    /// throttled, so it can't retry in a tight loop.
    func testANilReadKeepsTheChartAndStillStartsTheWait() async {
        let (store, clock, loader) = makeStore()
        loader.results = [buckets(62), nil]
        await store.refreshIfStale(kind: heartRate)
        let original = WatchIntradayChart(window: WatchIntradayWindow.endingAt(t0), buckets: buckets(62))

        clock.now = t0.addingTimeInterval(interval)
        let wait = await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(loader.calls.count, 2)
        XCTAssertEqual(store.charts[heartRate], original, "the chart and its original window stay")
        XCTAssertEqual(wait, interval)

        clock.now = t0.addingTimeInterval(interval + 120)
        let throttled = await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(throttled, 180)
        XCTAssertEqual(loader.calls.count, 2)
    }

    func testAnEmptyReadRemovesTheChart() async {
        let (store, clock, loader) = makeStore()
        loader.results = [buckets(62), []]
        await store.refreshIfStale(kind: heartRate)
        XCTAssertNotNil(store.charts[heartRate])

        clock.now = t0.addingTimeInterval(interval)
        let wait = await store.refreshIfStale(kind: heartRate)

        XCTAssertNil(store.charts[heartRate])
        XCTAssertEqual(wait, interval)
    }

    // MARK: - Reads that must not land

    /// The page was swiped away mid read: nothing lands, and no attempt is
    /// recorded, so swiping back reads right away.
    func testACancelledReadLandsNothingAndRecordsNoAttempt() async {
        let (store, _, loader) = makeStore()
        loader.holdsReads = true
        loader.results = [buckets(62)]
        let task = Task { await store.refreshIfStale(kind: heartRate) }
        await loader.waitForParkedRead()

        task.cancel()
        loader.release()
        let wait = await task.value

        XCTAssertEqual(wait, 0)
        XCTAssertNil(store.charts[heartRate])

        loader.holdsReads = false
        loader.results = [buckets(70)]
        await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(loader.calls.count, 2, "the cancelled read recorded no attempt")
        XCTAssertEqual(store.charts[heartRate]?.buckets, buckets(70))
    }

    func testClearDropsChartsAndAttemptsAndBumpsTheGeneration() async {
        let (store, clock, loader) = makeStore()
        loader.results = [buckets(62), buckets(70)]
        await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(store.generation, 0)

        store.clear()
        XCTAssertTrue(store.charts.isEmpty)
        XCTAssertEqual(store.generation, 1)

        clock.now = t0.addingTimeInterval(60)
        await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(loader.calls.count, 2, "the clear forgot the attempt")
    }

    /// A read that started under the old selection must not land on top of
    /// the clear, nor leave an attempt behind. The clock doesn't move after
    /// the discarded read, so a recorded attempt would throttle the next one.
    func testClearDiscardsTheReadInFlight() async {
        let (store, _, loader) = makeStore()
        loader.holdsReads = true
        loader.results = [buckets(62)]
        let task = Task { await store.refreshIfStale(kind: heartRate) }
        await loader.waitForParkedRead()

        store.clear()
        XCTAssertEqual(store.generation, 1)
        loader.release()
        let wait = await task.value

        XCTAssertEqual(wait, 0)
        XCTAssertTrue(store.charts.isEmpty, "the read from before the clear did not land")

        loader.holdsReads = false
        loader.results = [buckets(70)]
        await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(loader.calls.count, 2, "the discarded read recorded no attempt")
        XCTAssertEqual(store.charts[heartRate]?.buckets, buckets(70))
    }

    /// The manual refresh button: what's on screen stays, the next visit reads.
    func testInvalidateKeepsChartsButTheNextRefreshReads() async {
        let (store, clock, loader) = makeStore()
        loader.results = [buckets(62), buckets(70)]
        await store.refreshIfStale(kind: heartRate)
        let chart = store.charts[heartRate]

        store.invalidate()
        XCTAssertEqual(store.charts[heartRate], chart)
        XCTAssertEqual(store.generation, 0, "only a clear bumps the generation")

        clock.now = t0.addingTimeInterval(60)
        await store.refreshIfStale(kind: heartRate)
        XCTAssertEqual(loader.calls.count, 2)
    }

    // MARK: - Kinds

    func testKindsWithoutAChartNeverRead() async {
        let (store, _, loader) = makeStore()

        let wait = await store.refreshIfStale(kind: WatchMetricKindKey.sleep)

        XCTAssertTrue(loader.calls.isEmpty)
        XCTAssertTrue(store.charts.isEmpty)
        XCTAssertEqual(wait, interval)
    }

    func testEachKindKeepsItsOwnInterval() async {
        let (store, clock, loader) = makeStore()
        loader.results = [buckets(62), buckets(45)]
        await store.refreshIfStale(kind: heartRate)

        clock.now = t0.addingTimeInterval(60)
        let hrvWait = await store.refreshIfStale(kind: hrv)
        let heartRateWait = await store.refreshIfStale(kind: heartRate)

        XCTAssertEqual(loader.calls.map(\.kind), [heartRate, hrv])
        XCTAssertEqual(hrvWait, interval)
        XCTAssertEqual(heartRateWait, 240)
        XCTAssertEqual(store.charts[hrv]?.buckets, buckets(45))
        XCTAssertEqual(store.charts[heartRate]?.buckets, buckets(62))
    }
}
