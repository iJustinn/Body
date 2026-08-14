//
//  CardioFitnessLevel.swift
//  Body
//

import Foundation

/// Biological sex as far as the cardio fitness norms are concerned. HealthKit's
/// `HKBiologicalSex` also carries `.notSet` and `.other`; both map to `nil` here,
/// which leaves the reading unclassified rather than guessing a norm table.
enum CardioFitnessSex: String, Codable, Equatable {
    case female
    case male
}

/// Age + sex, the two inputs the cardio fitness norms are indexed by. Persisted
/// alongside the summary so the home card can classify on cold launch, before a
/// fetch lands.
struct CardioFitnessProfile: Codable, Equatable {
    var ageYears: Int
    var sex: CardioFitnessSex
}

/// Where a VO₂ max reading sits against people of the same age and sex.
///
/// Apple's Health app shows the same four levels but does not publish its cutoff
/// table — its whitepaper states only the methodology (quintiles by sex and age
/// decade, from the FRIEND registry). These bands are built from published FRIEND
/// normative percentiles instead, so they land close to but not exactly on the
/// Health app's. The About copy attributes them to FRIEND for that reason.
enum CardioFitnessLevel: Hashable {
    case low
    case belowAverage
    case aboveAverage
    case high

    /// Highest level first, matching how the detail card and the home preview
    /// stack their rows.
    static let displayOrder: [CardioFitnessLevel] = [
        .high,
        .aboveAverage,
        .belowAverage,
        .low
    ]

    /// Keyed rather than plain literals: bare "Low"/"High" already belong to the
    /// readiness statuses, whose translations read as quality judgements ("良好")
    /// rather than as the ends of an average-relative scale. Sharing those keys
    /// would break this ramp in every non-English locale.
    var title: String {
        switch self {
        case .low:
            return String(localized: "cardioFitness.level.low", defaultValue: "Low", table: "BodyMetricsKit")
        case .belowAverage:
            return String(localized: "cardioFitness.level.belowAverage", defaultValue: "Below Average", table: "BodyMetricsKit")
        case .aboveAverage:
            return String(localized: "cardioFitness.level.aboveAverage", defaultValue: "Above Average", table: "BodyMetricsKit")
        case .high:
            return String(localized: "cardioFitness.level.high", defaultValue: "High", table: "BodyMetricsKit")
        }
    }

    var explanation: String {
        switch self {
        case .low:
            return String(localized: "Your VO₂ max is below most people of your age and sex. Regular cardiovascular exercise is the most reliable way to raise it.", table: "BodyMetricsKit")
        case .belowAverage:
            return String(localized: "Your VO₂ max sits under the midpoint for your age and sex. Adding intensity or frequency to your cardio usually moves this up.", table: "BodyMetricsKit")
        case .aboveAverage:
            return String(localized: "Your VO₂ max is above the midpoint for your age and sex. Keeping your current cardio routine should hold it there.", table: "BodyMetricsKit")
        case .high:
            return String(localized: "Your VO₂ max is well above most people of your age and sex. That is a strong marker of cardiorespiratory fitness.", table: "BodyMetricsKit")
        }
    }
}

// MARK: - Norms

extension CardioFitnessLevel {
    /// The percentile cutoffs one age×sex group's bands are cut at, in mL/kg/min.
    /// `low` ends at `p20`, `belowAverage` spans `p20..<p50`, `aboveAverage`
    /// spans `p50..<p75`, and `high` runs above `p75`.
    ///
    /// The median is the boundary that matters most: "Above Average" has to mean
    /// at or above the midpoint for your age and sex, which is what the level's
    /// own copy tells the user. Cutting it anywhere below `p50` would label an
    /// ordinary below-median reading as above average.
    struct Cutoffs: Equatable {
        let p20: Double
        let p50: Double
        let p75: Double
    }

    /// Classification is defined for ages 20 through 79 only: the FRIEND tables
    /// stop at 79 and Apple's own classification starts at 20, while HealthKit
    /// will happily report an age of 85. Outside that span every caller treats
    /// the reading as unclassified rather than clamping it into an edge decade.
    static let classifiableAgeRange: ClosedRange<Int> = 20...79

    /// FRIEND normative VO₂ max cutoffs, keyed by sex then by age decade.
    ///
    /// Source: Kaminsky LA, Arena R, Myers J. "Reference Standards for
    /// Cardiorespiratory Fitness Measured With Cardiopulmonary Exercise
    /// Testing: Data From the Fitness Registry and the Importance of Exercise
    /// National Database." Mayo Clin Proc. 2015;90(11):1515-1523, Table 3 —
    /// the *measured* treadmill rows from FRIEND. (The same table's Cooper
    /// Clinic rows are *predicted* from Balke test time and are a different
    /// dataset; they are deliberately not used here. Figures circulating as
    /// "FRIEND" with a 20-29 median of 49.5/40.6 are from the 2021 update, a
    /// different cohort vintage — also not used, so the table stays internally
    /// consistent.)
    ///
    /// That table publishes the 5th, 10th, 25th, 50th, 75th, 90th and 95th
    /// percentiles. `p50` and `p75` below are taken from it verbatim; only `p20`
    /// is derived, linearly interpolated between the published 10th and 25th and
    /// rounded to one decimal, so it still sits inside a published interval.
    ///
    /// Why these three boundaries:
    /// - `p20` for Low is the one cutoff Apple documents. Its whitepaper states
    ///   the low-cardio-fitness notification fires at the lowest quintile for
    ///   sex and age by decade from FRIEND, for ages 20-59.
    /// - `p50` for Above Average, because the level's copy tells the user they
    ///   are above the midpoint — so the boundary has to BE the midpoint.
    /// - `p75` for High: the top quartile, published rather than interpolated.
    ///
    /// Apple documents the four level names but not the cutoffs behind three of
    /// them, so these bands land near the Health app's without matching them.
    ///
    /// Note the 70-79 rows rest on the thinnest samples in the registry
    /// (n=137 men, n=98 women), so those bands are the least stable.
    static let cutoffsBySexAndDecade: [CardioFitnessSex: [Int: Cutoffs]] = [
        .male: [
            20: Cutoffs(p20: 37.4, p50: 48.0, p75: 55.2),
            30: Cutoffs(p20: 34.0, p50: 42.4, p75: 49.2),
            40: Cutoffs(p20: 30.2, p50: 37.8, p75: 45.0),
            50: Cutoffs(p20: 25.7, p50: 32.6, p75: 39.7),
            60: Cutoffs(p20: 22.4, p50: 28.2, p75: 34.5),
            70: Cutoffs(p20: 19.3, p50: 24.4, p75: 30.4)
        ],
        .female: [
            20: Cutoffs(p20: 28.3, p50: 37.6, p75: 44.7),
            30: Cutoffs(p20: 23.8, p50: 30.2, p75: 36.1),
            40: Cutoffs(p20: 21.0, p50: 26.7, p75: 32.4),
            50: Cutoffs(p20: 19.0, p50: 23.4, p75: 27.6),
            60: Cutoffs(p20: 16.3, p50: 20.0, p75: 23.8),
            70: Cutoffs(p20: 14.9, p50: 18.3, p75: 20.8)
        ]
    ]

    /// The cutoffs covering a profile, or `nil` when the age is outside
    /// `classifiableAgeRange` or the table has no row for it.
    static func cutoffs(for profile: CardioFitnessProfile) -> Cutoffs? {
        guard classifiableAgeRange.contains(profile.ageYears) else {
            return nil
        }
        // Decades are keyed by their first year: 20, 30, … 70.
        return cutoffsBySexAndDecade[profile.sex]?[(profile.ageYears / 10) * 10]
    }

    /// The level a reading falls in, or `nil` when the value is missing/not
    /// finite or the profile can't be classified.
    static func level(for value: Double?, profile: CardioFitnessProfile?) -> CardioFitnessLevel? {
        guard let value, value.isFinite,
              let profile,
              let cutoffs = cutoffs(for: profile) else {
            return nil
        }

        if value < cutoffs.p20 {
            return .low
        } else if value < cutoffs.p50 {
            return .belowAverage
        } else if value < cutoffs.p75 {
            return .aboveAverage
        } else {
            return .high
        }
    }

    /// This level's VO₂ max span for a profile. `nil` bounds are open-ended and
    /// the chart band clamps them to the plot domain, matching how Training Load
    /// writes "< 0.80" and "> 1.50".
    static func bounds(
        for level: CardioFitnessLevel,
        profile: CardioFitnessProfile
    ) -> (lower: Double?, upper: Double?)? {
        guard let cutoffs = cutoffs(for: profile) else {
            return nil
        }

        switch level {
        case .low:
            return (nil, cutoffs.p20)
        case .belowAverage:
            return (cutoffs.p20, cutoffs.p50)
        case .aboveAverage:
            return (cutoffs.p50, cutoffs.p75)
        case .high:
            return (cutoffs.p75, nil)
        }
    }

    /// The span written the way the level card lists it.
    static func rangeText(
        for level: CardioFitnessLevel,
        profile: CardioFitnessProfile,
        locale: Locale = .current
    ) -> String? {
        guard let bounds = bounds(for: level, profile: profile) else {
            return nil
        }

        func number(_ value: Double) -> String {
            BodyValueFormat.numberText(value, decimals: 1, locale: locale)
        }

        switch (bounds.lower, bounds.upper) {
        case let (nil, upper?):
            return "< " + number(upper)
        case let (lower?, nil):
            return "≥ " + number(lower)
        case let (lower?, upper?):
            return number(lower) + "-" + number(upper)
        case (nil, nil):
            return nil
        }
    }
}

// MARK: - Breakdown

struct CardioFitnessLevelBreakdownEntry: Equatable, Identifiable {
    let level: CardioFitnessLevel
    let dayCount: Int
    let totalDayCount: Int

    var id: CardioFitnessLevel {
        level
    }

    var fractionOfTotal: Double {
        guard totalDayCount > 0 else { return 0 }
        return Double(dayCount) / Double(totalDayCount)
    }
}

enum CardioFitnessLevelBreakdown {
    static func entries(
        for series: HealthTrendSeries,
        range: BodyHealthTrendRange,
        profile: CardioFitnessProfile?,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [CardioFitnessLevelBreakdownEntry] {
        let levels = series.calendarPoints(to: range, calendar: calendar, date: date)
            .compactMap { point in
                CardioFitnessLevel.level(for: point.value, profile: profile)
            }
        let countsByLevel = Dictionary(grouping: levels) { $0 }
            .mapValues(\.count)
        let totalDayCount = countsByLevel.values.reduce(0, +)

        return CardioFitnessLevel.displayOrder.map { level in
            CardioFitnessLevelBreakdownEntry(
                level: level,
                dayCount: countsByLevel[level, default: 0],
                totalDayCount: totalDayCount
            )
        }
    }
}
