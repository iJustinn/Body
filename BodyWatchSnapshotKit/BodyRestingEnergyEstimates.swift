//
//  BodyRestingEnergyEstimates.swift
//  BodyWatchSnapshotKit
//
//  The pure half of resting energy's scale-estimate rule, shared by Body and
//  BodyWatch. A scale writes its whole-day resting energy estimate at every
//  weigh-in (sometimes the same one twice), so summing them doubles the day.
//  Both the iOS `HealthKitFetchEngine` (its daily resting energy series and
//  today's summary) and the watch's week of daily totals
//  (`BodyHealthQuantityFetch.dailyCumulativeSeries`) therefore keep the large
//  samples out of HealthKit's sum and add each day back through `fold` below,
//  so the two devices can't count the same weigh-ins differently.
//

import Foundation

enum BodyRestingEnergyEstimates {
    /// Only whole-day estimates are this large, so the sample query that reads
    /// them stays tiny next to the watch's thousands of small samples.
    static let minimumKilocalories = 500.0

    struct Sample: Hashable {
        let start: Date
        let end: Date
        let source: String
        let value: Double
    }

    struct Day: Equatable {
        /// What the day's large samples add to the sum of its small ones.
        var total = 0.0
        /// The estimates behind an averaged day, by time, for the chart
        /// callout. Empty when no source repeated an estimate.
        var records: [HealthTrendDataPoint] = []
    }

    /// A large sample logged over under an hour is a whole-day estimate, not
    /// energy burned in that time: per source and day, exact duplicates
    /// collapse and the rest count once, at their average. A large sample
    /// logged over longer is ordinary energy and counts in full.
    static func fold(
        samples: [Sample],
        calendar: Calendar
    ) -> [Date: Day] {
        struct Key: Hashable {
            let day: Date
            let source: String
        }
        var days: [Date: Day] = [:]
        var estimates: [Sample] = []
        for sample in samples {
            if sample.end.timeIntervalSince(sample.start) < 3600 {
                estimates.append(sample)
            } else {
                days[calendar.startOfDay(for: sample.start), default: .init()].total += sample.value
            }
        }
        let groups = Dictionary(grouping: Set(estimates)) { Key(day: calendar.startOfDay(for: $0.start), source: $0.source) }
        for (key, group) in groups {
            days[key.day, default: .init()].total += group.reduce(0) { $0 + $1.value } / Double(group.count)
            if group.count > 1 {
                days[key.day, default: .init()].records += group.map { HealthTrendDataPoint(date: $0.start, value: $0.value) }
            }
        }
        return days.mapValues { day in
            Day(total: day.total, records: day.records.sorted { ($0.date, $0.value) < ($1.date, $1.value) })
        }
    }
}
