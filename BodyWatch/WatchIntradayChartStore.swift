//
//  WatchIntradayChartStore.swift
//  BodyWatch
//
//  The data behind the "Last 8 hours" charts on the Heart Rate, HRV, Steps
//  and Active Energy detail pages: the watch reads them from its own Apple
//  Health data, in 30 minute slots, with no phone involved. The Blood Oxygen
//  page's chart isn't read here: it draws the snapshot's
//  (`WatchMetricDetailView.snapshotChartKinds`). Held in memory only. The pager asks for a
//  kind only while that kind's page is the visible one (see
//  `WatchMetricDetailPager`), and a kind is read at most once every
//  `refreshInterval`, counted from the last read that finished, so paging
//  back and forth costs no extra HealthKit queries.
//
//  The read itself is injected (`Load`): production wires it to
//  `WatchMetricsModel.readIntradayBuckets`, which owns the per kind permission
//  gate and the source resolution; tests script it. The slot types it holds
//  (`WatchIntradayBucket`, `WatchIntradayWindow`, `WatchIntradayChart`) live
//  in BodyWatchShared/Models/WatchIntradayChart.swift, shared with the chart
//  complications.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import Foundation

@MainActor
final class WatchIntradayChartStore: ObservableObject {
    /// Reads one kind's slots over `window`. `nil` means "keep what's on
    /// screen": the read failed (a locked or off wrist watch), or the phone's
    /// source selection couldn't be resolved this time. An empty array is a
    /// real absence: no readings in the window, the kind isn't charted, or the
    /// gate refused the read (the kind's permission, Heart, Steps or Energy,
    /// turned off on the phone, or nothing synced yet), and it removes the
    /// chart.
    typealias Load = @MainActor (_ kind: String, _ window: WatchIntradayWindow) async -> [WatchIntradayBucket]?

    /// The minimum time between two finished reads of the same kind.
    static let refreshInterval: TimeInterval = 5 * 60
    /// The kinds whose pages carry a "Last 8 hours" chart the watch reads
    /// live. Blood Oxygen's page draws the snapshot's chart instead
    /// (`WatchMetricDetailView.snapshotChartKinds`), so it isn't one.
    static let chartKinds: Set<String> = [
        WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability,
        WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy
    ]

    /// The latest chart per kind; a kind without one shows no chart and its
    /// page doesn't scroll.
    @Published private(set) var charts: [String: WatchIntradayChart] = [:]
    /// Bumped by `clear()`. The pager keys its read loop on it so the visible
    /// page reads again right away, and a read that started before the bump
    /// is dropped instead of landing on top of the clear.
    @Published private(set) var generation: UInt64 = 0

    /// When each kind's last read FINISHED. Only an uncancelled read under the
    /// current generation is recorded: recording at the start would make a
    /// quick swipe away and back wait 5 minutes for a read that never landed,
    /// and recording only successes would retry a failing read (a locked
    /// watch) in a tight loop.
    private var lastAttempts: [String: Date] = [:]
    private let now: () -> Date
    private let load: Load

    init(now: @escaping () -> Date = { Date() }, load: @escaping Load) {
        self.now = now
        self.load = load
    }

    /// Reads `kind` unless it was read less than `refreshInterval` ago, and
    /// returns the seconds until it is due again. There is deliberately no
    /// "already reading" latch: a cancelled read (the page was swiped away)
    /// can only clear such a latch once it is back on the main actor, so a
    /// quick swipe back would find it still set and skip the read. Two
    /// overlapping reads of the same kind are harmless instead; each lands
    /// only if its task is still current.
    @discardableResult
    func refreshIfStale(kind: String) async -> TimeInterval {
        guard Self.chartKinds.contains(kind) else { return Self.refreshInterval }

        let startedAt = now()
        // A future dated attempt (the clock moved back) counts as stale rather
        // than parking the read until the clock catches up.
        if let last = lastAttempts[kind], last <= startedAt {
            let elapsed = startedAt.timeIntervalSince(last)
            if elapsed < Self.refreshInterval {
                return Self.refreshInterval - elapsed
            }
        }

        let readGeneration = generation
        let window = WatchIntradayWindow.endingAt(startedAt)
        let buckets = await load(kind, window)
        guard !Task.isCancelled, readGeneration == generation else { return 0 }

        lastAttempts[kind] = now()
        guard let buckets else { return Self.refreshInterval }
        let chart = buckets.isEmpty ? nil : WatchIntradayChart(window: window, buckets: buckets)
        if charts[kind] != chart {
            charts[kind] = chart
        }
        return Self.refreshInterval
    }

    /// The manual refresh button: the charts stay on screen, but the next
    /// visit to each page reads fresh instead of waiting out the interval.
    func invalidate() {
        lastAttempts.removeAll()
    }

    /// The data the charts may show changed (the phone's Heart permission or
    /// source selection): drop every chart and every in flight read, so
    /// nothing read under the old selection stays on screen.
    func clear() {
        if !charts.isEmpty {
            charts.removeAll()
        }
        lastAttempts.removeAll()
        generation &+= 1
    }
}

extension WatchIntradayChart {
    /// A deterministic chart ending at `now` for previews and the watch page
    /// screenshots. Heart Rate: a resting stretch, a workout spike, and an
    /// hour off the wrist that breaks the average line. HRV: a few sparse
    /// readings, the way the watch takes them: a run of consecutive slots the
    /// line joins, lone slots it skips, each with a small spread and one with
    /// a single reading. Blood Oxygen: about one slot an hour, whole percents
    /// between 93 and 100 (one slot reaching 100, so the capped value axis
    /// shows), a single reading, and the latest slot averaging 97. Steps and
    /// Active Energy: a walk, a desk stretch with an idle hour (no slots), and
    /// a late walk.
    static func preview(kind: String, now: Date = Date(), calendar: Calendar = .current) -> WatchIntradayChart {
        let window = WatchIntradayWindow.endingAt(now, calendar: calendar)
        let slotCount = Int((window.plotEnd.timeIntervalSince(window.start) / WatchIntradayWindow.slotLength).rounded())
        func slotStart(_ index: Int) -> Date {
            window.start.addingTimeInterval(Double(index) * WatchIntradayWindow.slotLength)
        }
        func totals(_ sums: [Double?]) -> WatchIntradayChart {
            let buckets = sums.prefix(slotCount).enumerated().compactMap { index, sum -> WatchIntradayBucket? in
                guard let sum else { return nil }
                return WatchIntradayBucket(start: slotStart(index), minimum: sum, maximum: sum, average: sum)
            }
            return WatchIntradayChart(window: window, buckets: buckets)
        }

        switch kind {
        case WatchMetricKindKey.steps:
            return totals([420, 980, 1_640, 310, 120, nil, nil, 260, 2_210, 1_480, 390, 150, 90, 640, 1_120, 710, 480])
        case WatchMetricKindKey.activeEnergy:
            return totals([28, 54, 96, 24, 12, nil, nil, 20, 138, 92, 30, 14, 9, 42, 70, 46, 31])
        case WatchMetricKindKey.oxygenSaturation:
            let readings: [(slot: Int, minimum: Double, maximum: Double, average: Double)] = [
                (0, 95, 97, 96), (2, 94, 96, 95), (4, 97, 97, 97), (5, 96, 100, 98), (7, 94, 98, 96),
                (9, 93, 95, 94), (10, 95, 98, 97), (12, 97, 99, 98), (14, 96, 99, 98), (15, 96, 98, 97)
            ]
            let buckets = readings
                .filter { $0.slot < slotCount }
                .map { WatchIntradayBucket(start: slotStart($0.slot), minimum: $0.minimum, maximum: $0.maximum, average: $0.average) }
            return WatchIntradayChart(window: window, buckets: buckets)
        default:
            break
        }

        guard kind == WatchMetricKindKey.heartRate else {
            let readings: [(slot: Int, value: Double, spread: Double)] = [(1, 48, 9), (2, 52, 7), (3, 45, 5), (8, 56, 14), (12, 44, 0), (14, 41, 6), (15, 38, 7)]
            let buckets = readings
                .filter { $0.slot < slotCount }
                .map { WatchIntradayBucket(start: slotStart($0.slot), minimum: $0.value - $0.spread, maximum: $0.value + $0.spread, average: $0.value) }
            return WatchIntradayChart(window: window, buckets: buckets)
        }

        let workout = 6...8
        let offWrist = 10...11
        let buckets = (0..<slotCount).compactMap { index -> WatchIntradayBucket? in
            guard !offWrist.contains(index) else { return nil }
            let wobble = sin(Double(index) * 0.9) * 4
            if workout.contains(index) {
                let peak = 128 + Double(index - workout.lowerBound) * 12 + wobble
                return WatchIntradayBucket(start: slotStart(index), minimum: peak - 24, maximum: peak + 12, average: peak)
            }
            let resting = 64 + wobble
            return WatchIntradayBucket(start: slotStart(index), minimum: resting - 6, maximum: resting + 9, average: resting)
        }
        return WatchIntradayChart(window: window, buckets: buckets)
    }
}
