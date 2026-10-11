//
//  WatchIntradayChart.swift
//  BodyWatchShared
//
//  The 30 minute slots behind the watch's "Last 8 hours" charts, and the
//  geometry every drawing of them shares. The Heart Rate, HRV, Steps and
//  Active Energy detail pages read their slots on demand
//  (`WatchIntradayChartStore`, held in memory); the Heart Rate, HRV and Blood
//  Oxygen chart complications draw the copy the snapshot carries
//  (`WatchMetricsSnapshot.heartCharts`), which is why these types are
//  Codable. The watch compute builds those three; for Blood Oxygen the iPhone
//  sends its own slots too and the two are combined (`combined(with:)`), and
//  the Blood Oxygen page draws that same snapshot copy (`windowed(endingAt:)`)
//  rather than a read of its own.
//
//  Shared by the iOS `Body` target (the snapshot it encodes names these
//  types), the `BodyWatch` target and the watch widget extension, so it stays
//  Foundation only.
//

import Foundation

/// One 30 minute slot of readings, in the metric's display unit (bpm for
/// Heart Rate, ms for HRV, percent for Blood Oxygen, steps, kcal or kJ for
/// the energies). Slots without a reading are never built. For the daily
/// total kinds (Steps, Active Energy) a slot has one number, its sum,
/// carried in all three fields; the chart's `.totals` style reads `average`.
struct WatchIntradayBucket: Codable, Equatable, Sendable {
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
struct WatchIntradayWindow: Codable, Equatable, Sendable {
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

/// One finished read: the window it covered and the slots that had readings.
/// The page store never keeps an empty one (an empty read removes the chart
/// instead). In a snapshot the watch computed, an empty chart is the
/// compute's "read succeeded, found nothing", which the merge turns into a
/// removal (for Blood Oxygen, into the held slots re-windowed, see
/// `combined(with:)`), so a persisted snapshot never carries one either.
struct WatchIntradayChart: Codable, Equatable, Sendable {
    let window: WatchIntradayWindow
    let buckets: [WatchIntradayBucket]

    /// This chart moved onto the window ending at `now`: the slots that start
    /// inside it, on that window, so a chart read or pushed earlier draws the
    /// same last 8 hours as a fresh read would. Nil when no slot is left. The
    /// Blood Oxygen page draws the snapshot's chart through this, where the
    /// pages fed by `WatchIntradayChartStore` draw a read of their own.
    func windowed(endingAt now: Date, calendar: Calendar = .current) -> WatchIntradayChart? {
        let current = WatchIntradayWindow.endingAt(now, calendar: calendar)
        let kept = buckets.filter { $0.start >= current.start && $0.start < current.plotEnd }
        return kept.isEmpty ? nil : WatchIntradayChart(window: current, buckets: kept)
    }

    /// Two reads of one kind's slots put together, for the charts both devices
    /// build (`WatchMetricKindKey.combinedChartKinds`): the later window (by
    /// `end`, `other` winning a tie), every slot of either chart that starts
    /// inside it, and where both have a slot (slots share one half hour grid,
    /// keyed by `start`), the later chart's. Sorted by start, so an encoded
    /// snapshot stays byte for byte deterministic. Nil when no slot is left;
    /// `self` unchanged without `other`. Unlike a plain replace, a chart built
    /// from older readings, such as an iPhone push from samples it read a
    /// while ago, can't wipe slots only the other read holds; it can still win
    /// a shared slot until the next read, since "later" is the window's end.
    func combined(with other: WatchIntradayChart?) -> WatchIntradayChart? {
        guard let other else { return self }
        let (older, newer) = other.window.end >= window.end ? (self, other) : (other, self)
        var slots: [Date: WatchIntradayBucket] = [:]
        for bucket in older.buckets { slots[bucket.start] = bucket }
        for bucket in newer.buckets { slots[bucket.start] = bucket }
        let kept = slots.values
            .filter { $0.start >= newer.window.start }
            .sorted { $0.start < $1.start }
        return kept.isEmpty ? nil : WatchIntradayChart(window: newer.window, buckets: kept)
    }

    /// `combined(with:)` where the displayed chart may be missing too: the
    /// merges' entry point. Without a `current` chart an `incoming` one with
    /// slots is taken as is, and an empty one leaves nothing.
    static func combining(_ current: WatchIntradayChart?, with incoming: WatchIntradayChart?) -> WatchIntradayChart? {
        guard let current else {
            return incoming.flatMap { $0.buckets.isEmpty ? nil : $0 }
        }
        return current.combined(with: incoming)
    }
}

/// The geometry the detail pages' charts (`WatchIntradayChartView`,
/// `WatchStressChartView`) and the chart complications
/// (`WatchRecentHoursChartView`) share, so a complication never windows,
/// ticks or breaks its line differently from the page it opens.
enum WatchIntradayChartGeometry {
    /// Slot starts this far apart break the average line: an hour or more of
    /// empty slots between two readings (the watch was off the wrist). A
    /// single empty slot is bridged.
    private static let lineBreakGap: TimeInterval = WatchIntradayWindow.slotLength + 60 * 60

    /// Where `date` falls across `domain`, clamped to 0...1.
    static func fraction(for date: Date, in domain: ClosedRange<Date>) -> Double {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(domain.lowerBound) / span))
    }

    /// The slots oldest first, split wherever an hour or more of empty slots
    /// separates two readings (the watch was off the wrist), so the average
    /// line breaks there instead of bridging the gap. A run may hold a single
    /// slot.
    static func lineRuns(_ buckets: [WatchIntradayBucket]) -> [[WatchIntradayBucket]] {
        var runs: [[WatchIntradayBucket]] = []
        for bucket in buckets.sorted(by: { $0.start < $1.start }) {
            if let previous = runs.last?.last, bucket.start.timeIntervalSince(previous.start) < lineBreakGap {
                runs[runs.count - 1].append(bucket)
            } else {
                runs.append([bucket])
            }
        }
        return runs
    }

    /// The value range of a Heart Rate, HRV or Blood Oxygen plot: spans every
    /// slot's range so no capsule clips, padded and clamped like the iPhone
    /// Day View's `computeYDomain` (Body/Views/Health/Charts/MetricCharts.swift),
    /// which is iOS-only. With a `ceiling` no reading passes (Blood Oxygen's
    /// 100%, `WatchMetricKindKey.valueCeiling`), the padding stops
    /// `ceilingHeadroom` above it: no round value past the ceiling gets a
    /// label, so a lone 100% reading never reads 101 or 102, and a dot at the
    /// ceiling keeps room inside the plot.
    static func rangeDomain(for buckets: [WatchIntradayBucket], ceiling: Double? = nil) -> ClosedRange<Double> {
        let values = buckets.flatMap { [$0.minimum, $0.maximum] }.filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        let domain: ClosedRange<Double>
        if minimum == maximum {
            let padding = max(abs(minimum) * 0.02, 1)
            let lower = max(0, minimum - padding)
            domain = lower...max(maximum + padding, lower + 1)
        } else {
            let padding = max((maximum - minimum) * 0.16, 1)
            let lower = max(0, minimum - padding)
            domain = lower...max(maximum + padding, lower + 1)
        }

        guard let ceiling, maximum <= ceiling, domain.upperBound > ceiling + ceilingHeadroom else {
            return domain
        }
        return domain.lowerBound...(ceiling + ceilingHeadroom)
    }

    /// How far a capped value range reaches past its ceiling: half a unit,
    /// short of the next whole value.
    static let ceilingHeadroom = 0.5

    /// The round values a Heart Rate, HRV or Blood Oxygen chart complication
    /// labels on its axis: the multiples inside `domain` of the smallest step of 1, 2, 2.5
    /// or 5 times a power of ten (never under 1, and 2.5 only from 25 up, so
    /// every label is a whole number) that leaves at most three, so 55...149
    /// reads 75, 100 and 125. A range so flat that this leaves a single value
    /// allows four, so 41...49 reads 42, 44, 46 and 48, and one that still
    /// leaves a single value (56...64 reads 60) keeps it.
    static func valueTicks(in domain: ClosedRange<Double>) -> [Double] {
        let three = valueTicks(in: domain, maximumCount: 3)
        guard three.count < 2 else { return three }
        let four = valueTicks(in: domain, maximumCount: 4)
        return four.count > three.count ? four : three
    }

    private static func valueTicks(in domain: ClosedRange<Double>, maximumCount: Int) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, span.isFinite else { return [] }
        var magnitude = max(1, pow(10, floor(log10(span / Double(maximumCount)))))
        while true {
            for multiplier in [1.0, 2, 2.5, 5] where multiplier != 2.5 || magnitude >= 10 {
                let step = multiplier * magnitude
                let first = (domain.lowerBound / step).rounded(.up)
                let last = (domain.upperBound / step).rounded(.down)
                if last - first + 1 <= Double(maximumCount) {
                    guard first <= last else { return [] }
                    return stride(from: first, through: last, by: 1).map { $0 * step }
                }
            }
            magnitude *= 10
        }
    }

    /// The even local hours more than 30 minutes inside both edges, so no
    /// hour label clips at the plot's ends.
    static func hourTicks(in domain: ClosedRange<Date>, calendar: Calendar = .current) -> [Date] {
        let margin: TimeInterval = 30 * 60
        var ticks: [Date] = []
        calendar.enumerateDates(
            startingAfter: domain.lowerBound,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) { date, _, stop in
            guard let date, domain.upperBound.timeIntervalSince(date) > margin else {
                stop = true
                return
            }
            if date.timeIntervalSince(domain.lowerBound) > margin,
               calendar.component(.hour, from: date).isMultiple(of: 2) {
                ticks.append(date)
            }
        }
        return ticks
    }
}
