//
//  BodyHealthStatFormat.swift
//  Body
//
//  The windows and wording of the average and range readouts on the metric
//  detail pages. The hero's top row reads the last 7 days ("Weekly"), whatever
//  range the chart shows; the Day View header reads its selected day
//  ("Daily"), except for the hourly totals of Steps and Active Energy, whose
//  day reads as a total over an hourly average. Each label has a short form
//  ("W Avg", "D Range", "H Avg") for the two row legends and small screens.
//

import Foundation

enum BodyHealthStatFormat {
    /// The hero readouts' window: the last 7 calendar days, today included.
    static let heroWindow: BodyHealthTrendRange = .recentWeek

    /// At or below this screen width (an iPhone SE or mini, the Home cards'
    /// compact width) every label reads its short form, to save space.
    static let compactScreenMaximumWidth: CGFloat = BodyHomeMetricCardPreview.compactScreenMaximumWidth

    /// One readout's label, in full ("Weekly Avg") or short ("W Avg"): the
    /// short form inside the two row legends (two sources, or Basics' two
    /// series), so they never grow a third line, and everywhere on a small
    /// screen.
    enum Stat {
        case weeklyAverage
        case weeklyRange
        case dailyAverage
        case dailyRange
        case dailyTotal
        case hourlyAverage

        func label(short: Bool) -> String {
            switch (self, short) {
            case (.weeklyAverage, false):
                return String(localized: "detail.weeklyAvgPrefix", defaultValue: "Weekly Avg")
            case (.weeklyAverage, true):
                return String(localized: "detail.weeklyAvgShortPrefix", defaultValue: "W Avg")
            case (.weeklyRange, false):
                return String(localized: "detail.weeklyRangePrefix", defaultValue: "Weekly Range")
            case (.weeklyRange, true):
                return String(localized: "detail.weeklyRangeShortPrefix", defaultValue: "W Range")
            case (.dailyAverage, false):
                return String(localized: "detail.dailyAvgPrefix", defaultValue: "Daily Avg")
            case (.dailyAverage, true):
                return String(localized: "detail.dailyAvgShortPrefix", defaultValue: "D Avg")
            case (.dailyRange, false):
                return String(localized: "detail.dailyRangePrefix", defaultValue: "Daily Range")
            case (.dailyRange, true):
                return String(localized: "detail.dailyRangeShortPrefix", defaultValue: "D Range")
            case (.dailyTotal, false):
                return String(localized: "detail.dailyTotalPrefix", defaultValue: "Daily Total")
            case (.dailyTotal, true):
                return String(localized: "detail.dailyTotalShortPrefix", defaultValue: "D Total")
            case (.hourlyAverage, false):
                return String(localized: "detail.hourlyAvgPrefix", defaultValue: "Hourly Avg")
            case (.hourlyAverage, true):
                return String(localized: "detail.hourlyAvgShortPrefix", defaultValue: "H Avg")
            }
        }
    }

    /// Whether a screen this wide reads the short labels; an unmeasured (0)
    /// width reads the full ones.
    static func usesShortLabels(forScreenWidth width: CGFloat) -> Bool {
        width > 0 && width <= compactScreenMaximumWidth
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
    /// left is a plain number; `text` itself otherwise.
    private static func numberPart(of text: String, sharingUnitWith other: String) -> String {
        guard let lastDigit = text.lastIndex(where: \.isNumber) else {
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
}
