//
//  BodyHealthStatFormatTests.swift
//  BodyTests
//
//  Covers the metric detail pages' range readouts (`BodyHealthStatFormat`):
//  both ends in the kind's own formatter with its unit printed once, a
//  duration kept whole, one value for a range of one, and which kinds count
//  as running daily totals.
//

import XCTest
@testable import Body

final class BodyHealthStatFormatTests: XCTestCase {
    func testAUnitWithoutASpaceIsPrintedOnce() {
        XCTAssertEqual(
            BodyHealthStatFormat.rangeText(70...88) { BodyValueFormat.numberText($0, decimals: 0) + "%" },
            "70-88%"
        )
    }

    func testAUnitAfterASpaceIsPrintedOnce() {
        XCTAssertEqual(
            BodyHealthStatFormat.rangeText(48...142) { BodyValueFormat.numberText($0, decimals: 0) + " bpm" },
            "48-142 bpm"
        )
        XCTAssertEqual(
            BodyHealthStatFormat.rangeText(36.2...36.8) { BodyValueFormat.numberText($0, decimals: 1) + " °C" },
            "36.2-36.8 °C"
        )
    }

    /// Cardio Fitness read "38.5 VO₂ max-39.4 VO₂ max": the unit's "₂" was
    /// taken for the number's last digit.
    func testAUnitWithASubOrSuperscriptDigitIsPrintedOnce() {
        XCTAssertEqual(
            BodyHealthStatFormat.rangeText(38.5...39.4) { BodyValueFormat.numberText($0, decimals: 1) + " VO₂ max" },
            "38.5-39.4 VO₂ max"
        )
        XCTAssertEqual(
            BodyHealthStatFormat.rangeText(21.4...23.9) { BodyValueFormat.numberText($0, decimals: 1) + " kg/m²" },
            "21.4-23.9 kg/m²"
        )
    }

    /// The formatter's decimals and grouping carry over, so the range reads
    /// like the average beside it.
    func testTheFormattersDecimalsAndGroupingCarryOver() {
        XCTAssertEqual(
            BodyHealthStatFormat.rangeText(32.4...88.1) { BodyValueFormat.numberText($0, decimals: 1) + " ms" },
            "32.4-88.1 ms"
        )
        let grouped = BodyHealthStatFormat.rangeText(3_210...12_450) { BodyValueFormat.numberText($0, decimals: 0) }
        XCTAssertEqual(
            grouped,
            "\(BodyValueFormat.numberText(3_210, decimals: 0))-\(BodyValueFormat.numberText(12_450, decimals: 0))"
        )
    }

    func testAUnitlessValueHasNothingToStrip() {
        XCTAssertEqual(
            BodyHealthStatFormat.rangeText(5...78) { BodyValueFormat.numberText($0, decimals: 0) },
            "5-78"
        )
    }

    /// A sleep duration's trailing "m" is part of the value, not a unit.
    func testADurationKeepsBothEndsWhole() {
        let duration: (Double) -> String = { BodyValueFormat.sleepDurationText(for: $0 * 60 * 60) }
        XCTAssertEqual(
            BodyHealthStatFormat.rangeText(6.25...8.5, formatter: duration),
            "\(duration(6.25))-\(duration(8.5))"
        )
    }

    func testARangeOfOneValueReadsAsThatValue() {
        let bpm: (Double) -> String = { BodyValueFormat.numberText($0, decimals: 0) + " bpm" }
        XCTAssertEqual(BodyHealthStatFormat.rangeText(72...72, formatter: bpm), "72 bpm")
        // Ends that round to the same text read as one value too.
        XCTAssertEqual(BodyHealthStatFormat.rangeText(71.6...72.4, formatter: bpm), "72 bpm")
    }

    func testValueRangeSkipsNonFiniteValues() {
        XCTAssertEqual(BodyHealthStatFormat.valueRange([4, .nan, 9, 1, .infinity]), 1...9)
        XCTAssertNil(BodyHealthStatFormat.valueRange([.nan]))
        XCTAssertNil(BodyHealthStatFormat.valueRange([]))
    }

    func testTheDailyTotalKindsAreTheDescriptorsCumulativeOnes() {
        for kind in [HealthMetricKind.steps, .activeEnergy, .restingEnergy, .exerciseMinutes, .timeInDaylight] {
            XCTAssertTrue(BodyHealthStatFormat.isDailyTotal(kind), "\(kind)")
        }
        for kind in [HealthMetricKind.heartRate, .heartRateVariability, .restingHeartRate, .oxygenSaturation, .respiratoryRate, .wristTemperature, .bodyMass, .cardioFitness, .readiness, .stress, .sleep, .trainingLoad] {
            XCTAssertFalse(BodyHealthStatFormat.isDailyTotal(kind), "\(kind)")
        }
    }

    /// A small phone (an SE or mini, 375 pt or narrower, the Home cards'
    /// compact width) reads every label short; an unmeasured width reads
    /// them in full.
    func testSmallScreensReadTheShortLabels() {
        XCTAssertEqual(BodyHealthStatFormat.compactScreenMaximumWidth, 375)
        XCTAssertTrue(BodyHealthStatFormat.usesShortLabels(forScreenWidth: 320))
        XCTAssertTrue(BodyHealthStatFormat.usesShortLabels(forScreenWidth: 375))
        XCTAssertFalse(BodyHealthStatFormat.usesShortLabels(forScreenWidth: 376))
        XCTAssertFalse(BodyHealthStatFormat.usesShortLabels(forScreenWidth: 402))
        XCTAssertFalse(BodyHealthStatFormat.usesShortLabels(forScreenWidth: 0))
    }

    func testTheHeroWindowIsTheLastSevenDays() {
        XCTAssertEqual(BodyHealthStatFormat.heroWindow, .recentWeek)
        XCTAssertEqual(BodyHealthStatFormat.heroWindow.dayCount, 7)
    }
}

/// Covers how the hero's value row shares its width
/// (`BodyHeroValueRowLayout.shares`): natural widths while they fit, then
/// shrinking together in proportion, never below an item's minimum scale.
final class BodyHeroValueRowLayoutTests: XCTestCase {
    private let scales: [CGFloat] = [0.6, 0.75]
    private let gap = BodyHeroValueRowLayout().minimumGap

    func testTheItemsStayAtLeastSixPointsApart() {
        XCTAssertEqual(gap, 6)
        XCTAssertEqual(BodyHeroValueRowLayout().minimumScales, scales)
    }

    /// The labels' complaint: they kept their natural width only when the
    /// row split evenly happened to give it to them.
    func testItemsThatFitKeepTheirNaturalWidth() {
        XCTAssertEqual(
            BodyHeroValueRowLayout.shares(of: [90, 200], minimumScales: scales, in: 370, minimumGap: gap),
            [90, 200]
        )
        XCTAssertEqual(
            BodyHeroValueRowLayout.shares(of: [164, 200], minimumScales: scales, in: 370, minimumGap: gap),
            [164, 200]
        )
    }

    func testAFullRowShrinksBothInProportion() {
        let shares = BodyHeroValueRowLayout.shares(of: [200, 200], minimumScales: scales, in: 360 + gap, minimumGap: gap)
        XCTAssertEqual(shares[0], 180, accuracy: 0.001)
        XCTAssertEqual(shares[1], 180, accuracy: 0.001)
    }

    /// The labels would go below the three quarters they can shrink to, so
    /// they hold there and the big number gives the rest.
    func testAnItemBelowItsMinimumHoldsThereAndTheOtherGivesWay() {
        let shares = BodyHeroValueRowLayout.shares(of: [200, 240], minimumScales: scales, in: 300 + gap, minimumGap: gap)
        XCTAssertEqual(shares[1], 180, accuracy: 0.001)
        XCTAssertEqual(shares[0], 120, accuracy: 0.001)
    }

    func testARowTooNarrowForEveryMinimumGivesEachItsMinimum() {
        let shares = BodyHeroValueRowLayout.shares(of: [200, 240], minimumScales: scales, in: 100, minimumGap: gap)
        XCTAssertEqual(shares[0], 120, accuracy: 0.001)
        XCTAssertEqual(shares[1], 180, accuracy: 0.001)
    }

    /// A row with only the big number (no labels) keeps it whole.
    func testASingleItemThatFitsKeepsItsWidth() {
        XCTAssertEqual(BodyHeroValueRowLayout.shares(of: [90], minimumScales: scales, in: 370, minimumGap: gap), [90])
    }
}
