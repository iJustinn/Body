//
//  WatchIntradayChartStore.swift
//  BodyWatch
//
//  The data behind the "Last 8 hours" charts on the Heart Rate and HRV detail
//  pages: the watch reads them from its own Apple Health data, in 30 minute
//  slots, with no phone involved. Held in memory only. The pager asks for a
//  kind only while that kind's page is the visible one (see
//  `WatchMetricDetailPager`), and a kind is read at most once every
//  `refreshInterval`, counted from the last read that finished, so paging
//  back and forth costs no extra HealthKit queries.
//
//  The read itself is injected (`Load`): production wires it to
//  `WatchMetricsModel.readIntradayBuckets`, which owns the permission gate
//  and the source resolution; tests script it.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import Foundation

/// One 30 minute slot of readings, in the metric's display unit (bpm for
/// Heart Rate, ms for HRV). Slots without a reading are never built.
struct WatchIntradayBucket: Equatable, Sendable {
    let start: Date
    let minimum: Double
    let maximum: Double
    let average: Double

    /// Where the slot is plotted: its middle, so a slot's mark sits between
    /// its own edges rather than on the next slot's start.
    var midpoint: Date {
        start.addingTimeInterval(WatchIntradayWindow.slotLength / 2)
    }
}

/// The rolling window one read covers. Slots are aligned to the local half
/// hour, so the window opens 8 hours before the CURRENT slot's start: the
/// oldest slot is always whole and only the current one is partial.
struct WatchIntradayWindow: Equatable, Sendable {
    static let slotLength: TimeInterval = 30 * 60
    static let length: TimeInterval = 8 * 60 * 60

    /// The oldest slot's start, also the HealthKit query's anchor.
    let start: Date
    /// When the read ran: the query covers `start...end`.
    let end: Date
    /// The current slot's end, the chart's right edge, so the current slot's
    /// midpoint is never drawn past the plot.
    let plotEnd: Date

    /// The window ending at `now`. The current slot starts at the local hour's
    /// start plus whole 30 minute steps, not at a whole multiple of 30 minutes
    /// since the reference date: a +5:45 zone would otherwise put the slot
    /// edges at :15 and :45, and an hour shortened by a DST change would drift
    /// them. `length` is how far back it opens: the Heart Rate and HRV charts'
    /// 8 hours by default, the Stress chart's 12.
    static func endingAt(_ now: Date, length: TimeInterval = Self.length, calendar: Calendar = .current) -> WatchIntradayWindow {
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let offset = max(0, now.timeIntervalSince(hourStart))
        let slotStart = hourStart.addingTimeInterval((offset / slotLength).rounded(.down) * slotLength)
        return WatchIntradayWindow(
            start: slotStart.addingTimeInterval(-length),
            end: now,
            plotEnd: slotStart.addingTimeInterval(slotLength)
        )
    }
}

/// One finished read: the window it covered and the slots that had readings
/// (never empty; an empty read removes the chart instead).
struct WatchIntradayChart: Equatable, Sendable {
    let window: WatchIntradayWindow
    let buckets: [WatchIntradayBucket]
}

@MainActor
final class WatchIntradayChartStore: ObservableObject {
    /// Reads one kind's slots over `window`. `nil` means "keep what's on
    /// screen": the read failed (a locked or off wrist watch), or the phone's
    /// source selection couldn't be resolved this time. An empty array is a
    /// real absence: no readings in the window, the kind isn't charted, or the
    /// gate refused the read (Heart turned off on the phone, or nothing
    /// synced yet), and it removes the chart.
    typealias Load = @MainActor (_ kind: String, _ window: WatchIntradayWindow) async -> [WatchIntradayBucket]?

    /// The minimum time between two finished reads of the same kind.
    static let refreshInterval: TimeInterval = 5 * 60
    /// The kinds whose pages carry a "Last 8 hours" chart.
    static let chartKinds: Set<String> = [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability]

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
    /// readings, the way the watch takes them.
    static func preview(kind: String, now: Date = Date(), calendar: Calendar = .current) -> WatchIntradayChart {
        let window = WatchIntradayWindow.endingAt(now, calendar: calendar)
        let slotCount = Int((window.plotEnd.timeIntervalSince(window.start) / WatchIntradayWindow.slotLength).rounded())
        func slotStart(_ index: Int) -> Date {
            window.start.addingTimeInterval(Double(index) * WatchIntradayWindow.slotLength)
        }

        guard kind == WatchMetricKindKey.heartRate else {
            let readings: [(slot: Int, value: Double)] = [(1, 48), (4, 41), (8, 56), (12, 44), (15, 38)]
            let buckets = readings
                .filter { $0.slot < slotCount }
                .map { WatchIntradayBucket(start: slotStart($0.slot), minimum: $0.value, maximum: $0.value, average: $0.value) }
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
