//
//  BodyHealthStatFormat.swift
//  Body
//
//  The windows and wording of the average and range readouts on the metric
//  detail pages, every label in letters on every screen. The hero's top row
//  reads the range the chart shows ("W Avg", "M Range", "6M Avg", "Y Range");
//  the Day View header reads its selected day ("D Avg", "D Range"), except
//  for the hourly totals of Steps and Active Energy, whose day reads as a
//  total over an hourly average ("D Total", "H Avg").
//

import Foundation

enum BodyHealthStatFormat {
    /// One readout's label, in letters on every screen, so the two row
    /// legends (two sources, or Basics' two series) never grow a third line.
    enum Stat {
        /// The average, or the lowest to highest, over one of the chart's
        /// ranges, today included.
        case average(over: BodyHealthTrendRange)
        case range(over: BodyHealthTrendRange)
        case dailyAverage
        case dailyRange
        case dailyTotal
        case hourlyAverage

        var label: String {
            switch self {
            case .average(over: .recentWeek):
                return String(localized: "detail.weeklyAvgShortPrefix", defaultValue: "W Avg")
            case .average(over: .recentMonth):
                return String(localized: "detail.monthlyAvgShortPrefix", defaultValue: "M Avg")
            case .average(over: .recentSixMonths):
                return String(localized: "detail.sixMonthAvgShortPrefix", defaultValue: "6M Avg")
            case .average(over: .recentYear):
                return String(localized: "detail.yearlyAvgShortPrefix", defaultValue: "Y Avg")
            case .range(over: .recentWeek):
                return String(localized: "detail.weeklyRangeShortPrefix", defaultValue: "W Range")
            case .range(over: .recentMonth):
                return String(localized: "detail.monthlyRangeShortPrefix", defaultValue: "M Range")
            case .range(over: .recentSixMonths):
                return String(localized: "detail.sixMonthRangeShortPrefix", defaultValue: "6M Range")
            case .range(over: .recentYear):
                return String(localized: "detail.yearlyRangeShortPrefix", defaultValue: "Y Range")
            case .dailyAverage:
                return String(localized: "detail.dailyAvgShortPrefix", defaultValue: "D Avg")
            case .dailyRange:
                return String(localized: "detail.dailyRangeShortPrefix", defaultValue: "D Range")
            case .dailyTotal:
                return String(localized: "detail.dailyTotalShortPrefix", defaultValue: "D Total")
            case .hourlyAverage:
                return String(localized: "detail.hourlyAvgShortPrefix", defaultValue: "H Avg")
            }
        }
    }

    /// Whether a kind's daily value is a running total (Steps, the two
    /// energies, Exercise Minutes, Daylight), the descriptor's own query shape.
    static func isDailyTotal(_ kind: HealthMetricKind) -> Bool {
        HealthMetricQueryDescriptor.descriptor(for: kind)?.trend == .dailyCumulative
    }

    /// The lowest and highest finite value, nil without one.
    static func valueRange(_ values: [Double]) -> ClosedRange<Double>? {
        let finite = values.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else {
            return nil
        }

        return low...high
    }

    /// "lo-hi unit": both ends in the kind's own formatter, so the decimals
    /// match the average beside it, with the unit the formatter appends
    /// ("%", " bpm", " °C") printed once, after the high end. A low end that
    /// isn't a plain number with a unit (a sleep duration) keeps its full
    /// text. A range whose two ends print the same reads as that one value.
    static func rangeText(_ range: ClosedRange<Double>, formatter: (Double) -> String) -> String {
        let lowText = formatter(range.lowerBound)
        let highText = formatter(range.upperBound)
        guard lowText != highText else {
            return highText
        }

        return "\(numberPart(of: lowText, sharingUnitWith: highText))-\(highText)"
    }

    /// `text` without the unit suffix it shares with `other`, when what is
    /// left is a plain number; `text` itself otherwise. The number ends at
    /// its last decimal digit, so a unit's own sub or superscript ("VO₂ max",
    /// "m²") stays with the unit.
    private static func numberPart(of text: String, sharingUnitWith other: String) -> String {
        guard let lastDigit = text.lastIndex(where: isDecimalDigit) else {
            return text
        }

        let suffix = text[text.index(after: lastDigit)...]
        let number = text[...lastDigit]
        guard !suffix.isEmpty,
              other.hasSuffix(suffix),
              !number.contains(where: \.isLetter) else {
            return text
        }

        return String(number)
    }

    /// A decimal digit in any script ("4", "٤"), unlike `isNumber`, which
    /// counts "₂" and "²" too.
    private static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.generalCategory == .decimalNumber
    }
}
