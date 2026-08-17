//
//  CardioFitnessLevelTests.swift
//  BodyTests
//
//  Covers the cardio fitness level bands: the FRIEND-derived cutoff table stays
//  internally ordered, a reading lands in the band its value belongs to, and
//  every profile the norms don't cover (too young, too old, no sex) classifies
//  as unclassified rather than being clamped into an edge decade.
//

import XCTest
@testable import Body

final class CardioFitnessLevelTests: XCTestCase {

    // MARK: - Table integrity

    func testEveryAgeAndSexGroupHasStrictlyIncreasingCutoffs() {
        for sex in [CardioFitnessSex.female, .male] {
            let decades = CardioFitnessLevel.cutoffsBySexAndDecade[sex] ?? [:]
            XCTAssertEqual(
                Set(decades.keys),
                [20, 30, 40, 50, 60, 70],
                "\(sex) must cover every decade the classifiable age range spans"
            )

            for (decade, cutoffs) in decades {
                XCTAssertLessThan(cutoffs.p20, cutoffs.p50, "\(sex) \(decade)s p20 < p50")
                XCTAssertLessThan(cutoffs.p50, cutoffs.p75, "\(sex) \(decade)s p50 < p75")
                XCTAssertGreaterThan(cutoffs.p20, 0, "\(sex) \(decade)s cutoffs are positive")
            }
        }
    }

    /// VO₂ max declines with age, so each decade's cutoffs should sit below the
    /// previous one's. A transcription slip that swapped two rows would show up
    /// here and nowhere else.
    func testCutoffsDeclineWithAgeWithinEachSex() {
        for sex in [CardioFitnessSex.female, .male] {
            let decades = CardioFitnessLevel.cutoffsBySexAndDecade[sex] ?? [:]
            for decade in [20, 30, 40, 50, 60] {
                guard let younger = decades[decade], let older = decades[decade + 10] else {
                    XCTFail("missing \(sex) decade around \(decade)")
                    continue
                }
                XCTAssertLessThan(older.p20, younger.p20, "\(sex) \(decade + 10)s p20 below \(decade)s")
                XCTAssertLessThan(older.p50, younger.p50, "\(sex) \(decade + 10)s p50 below \(decade)s")
                XCTAssertLessThan(older.p75, younger.p75, "\(sex) \(decade + 10)s p75 below \(decade)s")
            }
        }
    }

    // MARK: - Classification

    private let male40s = CardioFitnessProfile(ageYears: 45, sex: .male)

    func testValueLandsInTheBandItsCutoffsDefine() throws {
        let cutoffs = try XCTUnwrap(CardioFitnessLevel.cutoffs(for: male40s))

        XCTAssertEqual(CardioFitnessLevel.level(for: cutoffs.p20 - 0.1, profile: male40s), .low)
        XCTAssertEqual(CardioFitnessLevel.level(for: cutoffs.p20, profile: male40s), .belowAverage)
        XCTAssertEqual(CardioFitnessLevel.level(for: cutoffs.p50 - 0.1, profile: male40s), .belowAverage)
        XCTAssertEqual(CardioFitnessLevel.level(for: cutoffs.p50, profile: male40s), .aboveAverage)
        XCTAssertEqual(CardioFitnessLevel.level(for: cutoffs.p75 - 0.1, profile: male40s), .aboveAverage)
        XCTAssertEqual(CardioFitnessLevel.level(for: cutoffs.p75, profile: male40s), .high)
    }

    func testDecadeIsSelectedByTheProfilesAge() {
        // 29 still reads as the 20s row; 30 crosses into the 30s row.
        let twenties = CardioFitnessProfile(ageYears: 29, sex: .male)
        let thirties = CardioFitnessProfile(ageYears: 30, sex: .male)

        XCTAssertEqual(
            CardioFitnessLevel.cutoffs(for: twenties),
            CardioFitnessLevel.cutoffsBySexAndDecade[.male]?[20]
        )
        XCTAssertEqual(
            CardioFitnessLevel.cutoffs(for: thirties),
            CardioFitnessLevel.cutoffsBySexAndDecade[.male]?[30]
        )
    }

    func testWomenAndMenClassifyTheSameReadingDifferently() {
        // The norms are sex-specific; a reading just under the male median for
        // 45 sits in the top quartile for a woman of the same age.
        let value = 36.0
        let woman = CardioFitnessProfile(ageYears: 45, sex: .female)

        XCTAssertEqual(CardioFitnessLevel.level(for: value, profile: male40s), .belowAverage)
        XCTAssertEqual(CardioFitnessLevel.level(for: value, profile: woman), .high)
    }

    /// The bands must agree with the words the UI puts on them: "Above Average"
    /// tells the user they are above the midpoint for their age and sex, so the
    /// boundary has to be the published median. Cutting it lower would label an
    /// ordinary below-median reading as above average.
    func testAboveAverageBeginsAtThePublishedMedian() throws {
        // FRIEND treadmill medians (Kaminsky 2015, Table 3), verbatim.
        let medians: [CardioFitnessSex: [Int: Double]] = [
            .male: [20: 48.0, 30: 42.4, 40: 37.8, 50: 32.6, 60: 28.2, 70: 24.4],
            .female: [20: 37.6, 30: 30.2, 40: 26.7, 50: 23.4, 60: 20.0, 70: 18.3]
        ]

        for (sex, byDecade) in medians {
            for (decade, median) in byDecade {
                let profile = CardioFitnessProfile(ageYears: decade + 5, sex: sex)
                let cutoffs = try XCTUnwrap(CardioFitnessLevel.cutoffs(for: profile))

                XCTAssertEqual(cutoffs.p50, median, accuracy: .ulpOfOne, "\(sex) \(decade)s median")

                // Just under the median is never "Above Average".
                XCTAssertEqual(
                    CardioFitnessLevel.level(for: median - 0.1, profile: profile),
                    .belowAverage,
                    "\(sex) \(decade)s: below-median must not read as above average"
                )
                XCTAssertEqual(
                    CardioFitnessLevel.level(for: median, profile: profile),
                    .aboveAverage,
                    "\(sex) \(decade)s: the median itself starts Above Average"
                )
            }
        }
    }

    // MARK: - Unclassified states

    func testAgesOutsideTheClassifiableRangeAreUnclassified() {
        let tooYoung = CardioFitnessProfile(ageYears: 19, sex: .male)
        let tooOld = CardioFitnessProfile(ageYears: 80, sex: .male)

        XCTAssertNil(CardioFitnessLevel.cutoffs(for: tooYoung))
        XCTAssertNil(CardioFitnessLevel.cutoffs(for: tooOld))
        XCTAssertNil(CardioFitnessLevel.level(for: 45, profile: tooYoung))
        XCTAssertNil(CardioFitnessLevel.level(for: 45, profile: tooOld))
    }

    func testBoundaryAgesStayClassifiable() {
        XCTAssertNotNil(CardioFitnessLevel.cutoffs(for: CardioFitnessProfile(ageYears: 20, sex: .male)))
        XCTAssertNotNil(CardioFitnessLevel.cutoffs(for: CardioFitnessProfile(ageYears: 79, sex: .female)))
    }

    func testMissingValueOrProfileIsUnclassified() {
        XCTAssertNil(CardioFitnessLevel.level(for: nil, profile: male40s))
        XCTAssertNil(CardioFitnessLevel.level(for: 45, profile: nil))
        XCTAssertNil(CardioFitnessLevel.level(for: .nan, profile: male40s))
        XCTAssertNil(CardioFitnessLevel.level(for: .infinity, profile: male40s))
    }

    // MARK: - Bounds and range text

    func testOuterBandsAreOpenEnded() throws {
        let low = try XCTUnwrap(CardioFitnessLevel.bounds(for: .low, profile: male40s))
        let high = try XCTUnwrap(CardioFitnessLevel.bounds(for: .high, profile: male40s))

        XCTAssertNil(low.lower, "Low runs down to the plot floor")
        XCTAssertNotNil(low.upper)
        XCTAssertNotNil(high.lower)
        XCTAssertNil(high.upper, "High runs up to the plot ceiling")
    }

    func testAdjacentBandsShareABoundary() throws {
        let below = try XCTUnwrap(CardioFitnessLevel.bounds(for: .belowAverage, profile: male40s))
        let above = try XCTUnwrap(CardioFitnessLevel.bounds(for: .aboveAverage, profile: male40s))

        XCTAssertEqual(below.upper, above.lower)
    }

    func testBoundsAreUnavailableForAnUnclassifiableProfile() {
        let tooOld = CardioFitnessProfile(ageYears: 95, sex: .female)

        XCTAssertNil(CardioFitnessLevel.bounds(for: .low, profile: tooOld))
        XCTAssertNil(CardioFitnessLevel.rangeText(for: .low, profile: tooOld))
    }

    func testRangeTextWritesOpenEndedBandsWithAComparator() throws {
        let locale = Locale(identifier: "en_US")
        let low = try XCTUnwrap(CardioFitnessLevel.rangeText(for: .low, profile: male40s, locale: locale))
        let high = try XCTUnwrap(CardioFitnessLevel.rangeText(for: .high, profile: male40s, locale: locale))
        let middle = try XCTUnwrap(
            CardioFitnessLevel.rangeText(for: .belowAverage, profile: male40s, locale: locale)
        )

        XCTAssertTrue(low.hasPrefix("<"), "got \(low)")
        XCTAssertTrue(high.hasPrefix("≥"), "got \(high)")
        XCTAssertTrue(middle.contains("-"), "got \(middle)")
    }

    // MARK: - Display order

    func testDisplayOrderRunsHighestBandFirstAndCoversEveryLevel() {
        XCTAssertEqual(
            CardioFitnessLevel.displayOrder,
            [.high, .aboveAverage, .belowAverage, .low]
        )
    }

    // MARK: - Breakdown

    func testBreakdownCountsEachDayIntoItsLevel() throws {
        let calendar = Calendar.bodyGregorian
        let today = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))
        )
        let cutoffs = try XCTUnwrap(CardioFitnessLevel.cutoffs(for: male40s))

        // Three readings on consecutive days: one clearly Low, two clearly High.
        let values: [Double] = [cutoffs.p20 - 5, cutoffs.p75 + 5, cutoffs.p75 + 6]
        let points = values.enumerated().compactMap { offset, value -> HealthTrendDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -(2 - offset), to: today) else {
                return nil
            }
            return HealthTrendDataPoint(date: calendar.startOfDay(for: date), value: value)
        }

        let entries = CardioFitnessLevelBreakdown.entries(
            for: HealthTrendSeries(points: points),
            range: .recentWeek,
            profile: male40s,
            calendar: calendar,
            date: today
        )

        XCTAssertEqual(entries.map(\.level), CardioFitnessLevel.displayOrder)
        XCTAssertEqual(entries.first { $0.level == .low }?.dayCount, 1)
        XCTAssertEqual(entries.first { $0.level == .high }?.dayCount, 2)
        XCTAssertEqual(entries.first { $0.level == .aboveAverage }?.dayCount, 0)
        XCTAssertEqual(entries.first { $0.level == .high }?.totalDayCount, 3)
        XCTAssertEqual(entries.first { $0.level == .high }?.fractionOfTotal ?? 0, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testBreakdownIsEmptyWithoutAClassifiableProfile() {
        let entries = CardioFitnessLevelBreakdown.entries(
            for: HealthTrendSeries(points: [HealthTrendDataPoint(date: Date(), value: 45)]),
            range: .recentWeek,
            profile: nil
        )

        XCTAssertEqual(entries.map(\.level), CardioFitnessLevel.displayOrder)
        XCTAssertTrue(entries.allSatisfy { $0.dayCount == 0 })
        XCTAssertTrue(entries.allSatisfy { $0.totalDayCount == 0 })
    }
}
