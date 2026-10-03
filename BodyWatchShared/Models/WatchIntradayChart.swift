//
//  WatchIntradayChart.swift
//  BodyWatchShared
//
//  The 30 minute slots behind the watch's "Last 8 hours" charts, and the
//  geometry every drawing of them shares. The Heart Rate, HRV, Steps and
//  Active Energy detail pages read their slots on demand
//  (`WatchIntradayChartStore`, held in memory); the Heart Rate and HRV chart
//  complications draw the copy the watch compute keeps in the snapshot
//  (`WatchMetricsSnapshot.heartCharts`), which is why these types are
//  Codable.
//
//  Shared by the iOS `Body` target (the snapshot it encodes names these
//  types), the `BodyWatch` target and the watch widget extension, so it stays
//  Foundation only.
//

import Foundation

/// One 30 minute slot of readings, in the metric's display unit (bpm for
/// Heart Rate, ms for HRV, steps, kcal or kJ for the energies). Slots without
/// a reading are never built. For the daily total kinds (Steps, Active Energy)
/// a slot has one number, its sum, carried in all three fields; the chart's
/// `.totals` style reads `average`.
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
/// removal, so a persisted snapshot never carries one either.
struct WatchIntradayChart: Codable, Equatable, Sendable {
    let window: WatchIntradayWindow
    let buckets: [WatchIntradayBucket]
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

    /// The value range of a Heart Rate or HRV plot: spans every slot's range
    /// so no capsule clips, padded and clamped like the iPhone Day View's
    /// `computeYDomain` (Body/Views/Health/Charts/MetricCharts.swift), which
    /// is iOS-only.
    static func rangeDomain(for buckets: [WatchIntradayBucket]) -> ClosedRange<Double> {
        let values = buckets.flatMap { [$0.minimum, $0.maximum] }.filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.02, 1)
            let lower = max(0, minimum - padding)
            return lower...max(maximum + padding, lower + 1)
        }

        let padding = max((maximum - minimum) * 0.16, 1)
        let lower = max(0, minimum - padding)
        return lower...max(maximum + padding, lower + 1)
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
