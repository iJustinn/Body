//
//  SourceComparison.swift
//  Body
//

import Foundation

enum BodyHealthSourceRole: String, Hashable, CaseIterable {
    case primary
    case secondary
}

struct BodyHealthSourceTrend: Equatable, Identifiable {
    var role: BodyHealthSourceRole
    var sourceName: String
    var series: HealthTrendSeries

    var id: String {
        "\(role.rawValue)-\(sourceName)"
    }

    /// The daily mean over the whole range, the way the single source readout
    /// averages. Averaging the chart's comparison buckets instead would drop
    /// the oldest partial bucket, leaving the first days of 6 Months and Year
    /// out.
    func averageValue(
        in range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> Double? {
        series.limited(to: range, calendar: calendar, date: date).averageValue
    }
}

struct BodyHealthSourceComparisonTrend: Equatable {
    var primary: BodyHealthSourceTrend
    var secondary: BodyHealthSourceTrend

    var isEmpty: Bool {
        primary.series.isEmpty && secondary.series.isEmpty
    }

    func mapValues(_ transform: (Double) -> Double) -> BodyHealthSourceComparisonTrend {
        BodyHealthSourceComparisonTrend(
            primary: BodyHealthSourceTrend(
                role: primary.role,
                sourceName: primary.sourceName,
                series: primary.series.mapValues(transform)
            ),
            secondary: BodyHealthSourceTrend(
                role: secondary.role,
                sourceName: secondary.sourceName,
                series: secondary.series.mapValues(transform)
            )
        )
    }
}

struct BodyHealthSourceRangeTrend: Equatable, Identifiable {
    var role: BodyHealthSourceRole
    var sourceName: String
    var series: HealthTrendRangeSeries

    var id: String {
        "\(role.rawValue)-\(sourceName)"
    }

    /// The mean of each day's average over the whole range, like
    /// `BodyHealthSourceTrend.averageValue(in:)`.
    func averageValue(
        in range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> Double? {
        series.limited(to: range, calendar: calendar, date: date).averageValue
    }
}

struct BodyHealthSourceRangeComparisonTrend: Equatable {
    var primary: BodyHealthSourceRangeTrend
    var secondary: BodyHealthSourceRangeTrend

    var isEmpty: Bool {
        primary.series.isEmpty && secondary.series.isEmpty
    }
}
