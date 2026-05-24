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

    func averageValue(
        in range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> Double? {
        let values = series
            .sourceComparisonChartCalendarPoints(to: range, calendar: calendar, date: date)
            .compactMap(\.value)
            .filter(\.isFinite)
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
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

    func averageValue(
        in range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> Double? {
        let values = series
            .sourceComparisonChartCalendarPoints(to: range, calendar: calendar, date: date)
            .compactMap(\.averageValue)
            .filter(\.isFinite)
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }
}

struct BodyHealthSourceRangeComparisonTrend: Equatable {
    var primary: BodyHealthSourceRangeTrend
    var secondary: BodyHealthSourceRangeTrend

    var isEmpty: Bool {
        primary.series.isEmpty && secondary.series.isEmpty
    }
}
