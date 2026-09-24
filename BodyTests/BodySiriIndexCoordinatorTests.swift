//
//  BodySiriIndexCoordinatorTests.swift
//  BodyTests
//
//  Covers the actor that owns Body's Spotlight copy: what it indexes, when it
//  skips the write, how it retries after a failure, and how overlapping
//  requests coalesce.
//

import XCTest
@testable import Body

// MARK: - Doubles

/// Lets a test hold an in-flight index call open until it says otherwise.
private actor IndexGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }
}

private actor FakeSiriIndexClient: BodySiriIndexClient {

    enum Call: Equatable {
        case deleteAll
        case index([String])
    }

    private(set) var calls: [Call] = []
    private(set) var indexStartCount = 0
    private var failuresRemaining = 0
    private var gate: IndexGate?

    func failNextIndexCalls(_ count: Int) {
        failuresRemaining = count
    }

    func hold(with gate: IndexGate) {
        self.gate = gate
    }

    var indexedPayloads: [[String]] {
        calls.compactMap { call in
            if case let .index(ids) = call { return ids }
            return nil
        }
    }

    func deleteAll() async throws {
        calls.append(.deleteAll)
    }

    func index(_ entities: [BodyHealthMetricEntity]) async throws {
        indexStartCount += 1
        if let gate {
            await gate.wait()
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw CocoaError(.fileWriteUnknown)
        }
        calls.append(.index(entities.map(\.id)))
    }
}

/// A bundle loader whose value the test can change between requests.
private final class BundleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var bundle: BodySiriSnapshotBundle

    init(_ bundle: BodySiriSnapshotBundle) {
        self.bundle = bundle
    }

    var value: BodySiriSnapshotBundle {
        get { lock.withLock { bundle } }
        set { lock.withLock { bundle = newValue } }
    }

    var loader: @Sendable () -> BodySiriSnapshotBundle {
        { [self] in value }
    }
}

// MARK: - Tests

final class BodySiriIndexCoordinatorTests: XCTestCase {

    private let calendar = Calendar.bodyGregorian

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    private func trend(
        _ metric: HealthWidgetMetric,
        _ displayValues: [HealthWidgetDisplayValue]
    ) -> HealthWidgetMetricTrend {
        HealthWidgetMetricTrend(
            metric: metric,
            primarySourceName: nil,
            week: .empty,
            month: .empty,
            displayValues: displayValues
        )
    }

    private func bundle(hrv: String, restingHeartRate: String = "--") -> BodySiriSnapshotBundle {
        BodySiriSnapshotBundle(
            widget: HealthWidgetSnapshot(
                generatedDate: date(2026, 9, 17, 8, 30),
                metricTrends: [
                    trend(.heartRateVariability, [HealthWidgetDisplayValue(value: hrv, unit: "ms")]),
                    trend(.restingHeartRate, [HealthWidgetDisplayValue(value: restingHeartRate, unit: "bpm")])
                ],
                sleep: HealthWidgetSleepStages(night: nil, sourceName: nil, segments: [])
            ),
            now: date(2026, 9, 17, 9, 0)
        )
    }

    // MARK: - Indexing

    func testFirstRequestIndexesOnlyMetricsWithValues() async {
        let client = FakeSiriIndexClient()
        let box = BundleBox(bundle(hrv: "45"))
        let coordinator = BodySiriIndexCoordinator(client: client, bundleLoader: box.loader)

        await coordinator.requestReindex()

        let calls = await client.calls
        XCTAssertEqual(calls, [.deleteAll, .index([BodySiriMetric.heartRateVariability.rawValue])])
    }

    func testAnUnchangedPayloadSkipsTheWrite() async {
        let client = FakeSiriIndexClient()
        let box = BundleBox(bundle(hrv: "45"))
        let coordinator = BodySiriIndexCoordinator(client: client, bundleLoader: box.loader)

        await coordinator.requestReindex()
        let afterFirst = await client.calls.count
        await coordinator.requestReindex()

        let afterSecond = await client.calls.count
        XCTAssertEqual(afterFirst, 2)
        XCTAssertEqual(afterSecond, afterFirst)
    }

    func testAChangedPayloadDeletesThenIndexes() async {
        let client = FakeSiriIndexClient()
        let box = BundleBox(bundle(hrv: "45"))
        let coordinator = BodySiriIndexCoordinator(client: client, bundleLoader: box.loader)

        await coordinator.requestReindex()
        box.value = bundle(hrv: "52", restingHeartRate: "48")
        await coordinator.requestReindex()

        let calls = await client.calls
        XCTAssertEqual(
            calls,
            [
                .deleteAll,
                .index([BodySiriMetric.heartRateVariability.rawValue]),
                .deleteAll,
                .index([
                    BodySiriMetric.heartRateVariability.rawValue,
                    BodySiriMetric.restingHeartRate.rawValue
                ])
            ]
        )
    }

    // MARK: - Failure

    func testAFailedIndexIsRetriedOnTheNextRequest() async {
        let client = FakeSiriIndexClient()
        await client.failNextIndexCalls(1)
        let box = BundleBox(bundle(hrv: "45"))
        let coordinator = BodySiriIndexCoordinator(client: client, bundleLoader: box.loader)

        await coordinator.requestReindex()
        let afterFailure = await client.indexedPayloads
        XCTAssertTrue(afterFailure.isEmpty)

        // Same payload as the failed attempt: the retry must not be skipped.
        await coordinator.requestReindex()

        let afterRetry = await client.indexedPayloads
        XCTAssertEqual(afterRetry, [[BodySiriMetric.heartRateVariability.rawValue]])
    }

    // MARK: - Clearing

    func testClearDeletesAndLetsTheNextRequestIndexAgain() async {
        let client = FakeSiriIndexClient()
        let box = BundleBox(bundle(hrv: "45"))
        let coordinator = BodySiriIndexCoordinator(client: client, bundleLoader: box.loader)

        await coordinator.requestReindex()
        await coordinator.clear()
        await coordinator.requestReindex()

        let calls = await client.calls
        XCTAssertEqual(
            calls,
            [
                .deleteAll,
                .index([BodySiriMetric.heartRateVariability.rawValue]),
                .deleteAll,
                .deleteAll,
                .index([BodySiriMetric.heartRateVariability.rawValue])
            ]
        )
    }

    func testClearWaitsForAnInFlightWriteSoTheDeleteLandsAfterIt() async {
        let client = FakeSiriIndexClient()
        let gate = IndexGate()
        await client.hold(with: gate)
        let box = BundleBox(bundle(hrv: "45"))
        let coordinator = BodySiriIndexCoordinator(client: client, bundleLoader: box.loader)

        let run = Task { await coordinator.requestReindex() }
        for _ in 0..<500 {
            let started = await client.indexStartCount
            if started > 0 { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        let clear = Task { await coordinator.clear() }
        // The clear must still be parked while the write is held open.
        try? await Task.sleep(nanoseconds: 20_000_000)
        let callsWhileHeld = await client.calls
        XCTAssertEqual(callsWhileHeld, [.deleteAll])

        await gate.open()
        await run.value
        await clear.value

        let calls = await client.calls
        XCTAssertEqual(
            calls,
            [
                .deleteAll,
                .index([BodySiriMetric.heartRateVariability.rawValue]),
                .deleteAll
            ]
        )
    }

    // MARK: - Coalescing

    func testOverlappingRequestsCoalesceToOneExtraRun() async {
        let client = FakeSiriIndexClient()
        let gate = IndexGate()
        await client.hold(with: gate)
        let box = BundleBox(bundle(hrv: "45"))
        let coordinator = BodySiriIndexCoordinator(client: client, bundleLoader: box.loader)

        let first = Task { await coordinator.requestReindex() }

        // Wait until the first run is parked inside the client.
        for _ in 0..<500 {
            let started = await client.indexStartCount
            if started > 0 { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let startedRuns = await client.indexStartCount
        XCTAssertEqual(startedRuns, 1)

        // Every value differs, so a skipped write cannot mask a missing run.
        box.value = bundle(hrv: "46")
        await coordinator.requestReindex()
        box.value = bundle(hrv: "47")
        await coordinator.requestReindex()

        await gate.open()
        await first.value

        let totalStarts = await client.indexStartCount
        let totalPayloads = await client.indexedPayloads
        XCTAssertEqual(totalStarts, 2)
        XCTAssertEqual(totalPayloads.count, 2)
    }
}
