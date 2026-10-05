//
//  EnergyEquivalentTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class EnergyEquivalentTests: XCTestCase {
    func testNilZeroOrNegativeKilocaloriesReturnsNil() {
        XCTAssertNil(EnergyEquivalent.decompose(kilocalories: nil))
        XCTAssertNil(EnergyEquivalent.decompose(kilocalories: 0))
        XCTAssertNil(EnergyEquivalent.decompose(kilocalories: -100))
    }

    /// The smallest food (🍬, 20 kcal) is the floor — anything below it has
    /// nothing meaningful to show.
    func testBelowSmallestFoodReturnsNil() {
        XCTAssertNil(EnergyEquivalent.decompose(kilocalories: 15))
    }

    /// The banded draw may vary the mix, but the shown foods must still cover
    /// most of the total: the leftover is always below the smallest food, and
    /// the fewest-items mode keeps the count small.
    func testKnownKilocaloriesIsWellCovered() {
        let result = EnergyEquivalent.decompose(kilocalories: 1000)
        let covered = result?.reduce(0) { $0 + $1.kilocalories } ?? 0
        let smallest = EnergyEquivalent.foods.last?.kilocalories ?? 0
        let realFoods = result?.filter { $0.kilocalories > 0 } ?? []
        XCTAssertGreaterThan(covered, 1000 - smallest)
        XCTAssertLessThanOrEqual(covered, 1000)
        XCTAssertLessThanOrEqual(realFoods.count, 5)
    }

    /// One- or two-food breakdowns get padded with zero-kcal ice cubes so the
    /// physics card isn't nearly empty; the pad never changes the covered kcal.
    func testSparseBreakdownsArePaddedWithIceCubes() {
        let result = EnergyEquivalent.decompose(kilocalories: 100)
        let iceCubes = result?.filter { $0.emoji == "🧊" } ?? []
        let realFoods = result?.filter { $0.kilocalories > 0 } ?? []
        XCTAssertLessThanOrEqual(realFoods.count, 2)
        XCTAssertTrue((2...4).contains(iceCubes.count))
        XCTAssertTrue(iceCubes.allSatisfy { $0.kilocalories == 0 })
    }

    func testHugeKilocaloriesCapsAtMaximumCount() {
        let result = EnergyEquivalent.decompose(kilocalories: 10_000)
        XCTAssertEqual(result?.count, EnergyEquivalent.maximumCount)
        XCTAssertEqual(EnergyEquivalent.maximumCount, 12)
    }

    func testDecomposeIsDeterministic() {
        let first = EnergyEquivalent.decompose(kilocalories: 1_234)
        let second = EnergyEquivalent.decompose(kilocalories: 1_234)
        XCTAssertEqual(first?.map { $0.emoji }, second?.map { $0.emoji })
    }

    /// Hidden foods never appear, whatever the banded draw picks.
    func testExcludingFoodsRemovesThemFromResults() {
        let withoutBurger = EnergyEquivalent.decompose(kilocalories: 1000, excluding: ["🍔"])
        XCTAssertFalse(withoutBurger?.contains { $0.emoji == "🍔" } ?? true)
        XCTAssertFalse(withoutBurger?.isEmpty ?? true)
    }

    func testAllFoodsHiddenReturnsNil() {
        let allEmojis = Set(EnergyEquivalent.foods.map { $0.emoji })
        XCTAssertNil(EnergyEquivalent.decompose(kilocalories: 1000, excluding: allEmojis))
    }

    /// 500 kcal in more-items mode fills the card with small snacks — more
    /// pieces than the fewest-items pass, drawn from more than one food so the
    /// row isn't a single repeated glyph.
    func testPreferringMoreItemsUsesMoreAndVariedFoods() {
        let fewest = EnergyEquivalent.decompose(kilocalories: 500)?.filter { $0.kilocalories > 0 }
        let more = EnergyEquivalent.decompose(kilocalories: 500, preferringMoreItems: true)?.filter { $0.kilocalories > 0 }
        XCTAssertGreaterThan(more?.count ?? 0, fewest?.count ?? 0)
        XCTAssertGreaterThan(Set(more?.map { $0.emoji } ?? []).count, 1)
    }

    /// Totals too big for even the largest food to cover within the cap fall
    /// back to the plain greedy pass (which already saturates the card).
    func testPreferringMoreItemsHugeTotalMatchesGreedyCapBehavior() {
        let more = EnergyEquivalent.decompose(kilocalories: 10_000, preferringMoreItems: true)
        XCTAssertEqual(more?.count, EnergyEquivalent.maximumCount)
    }

    func testPreferringMoreItemsIsDeterministicAndRespectsExclusions() {
        let first = EnergyEquivalent.decompose(kilocalories: 900, excluding: ["🍫"], preferringMoreItems: true)
        let second = EnergyEquivalent.decompose(kilocalories: 900, excluding: ["🍫"], preferringMoreItems: true)
        XCTAssertEqual(first?.map { $0.emoji }, second?.map { $0.emoji })
        XCTAssertFalse(first?.contains { $0.emoji == "🍫" } ?? true)
        XCTAssertGreaterThan(first?.count ?? 0, 1)
    }

    func testFoodsAreStrictlyDescendingByKilocalories() {
        let kcals = EnergyEquivalent.foods.map { $0.kilocalories }
        for (a, b) in zip(kcals, kcals.dropFirst()) {
            XCTAssertGreaterThan(a, b)
        }
    }

    /// ~300 kcal in more-items mode used to be six 🍫, the only food in its
    /// band; the small foods now fill that band with a mix of different ones.
    func testMoreItemsAt300KilocaloriesMixesSmallFoods() throws {
        let result = try XCTUnwrap(EnergyEquivalent.decompose(kilocalories: 300, preferringMoreItems: true))
        let counts = Dictionary(result.map { ($0.emoji, 1) }, uniquingKeysWith: +)
        XCTAssertGreaterThanOrEqual(counts.count, 8)
        XCTAssertLessThanOrEqual(counts.values.max() ?? 0, 2)
        XCTAssertLessThanOrEqual(counts["🍫"] ?? 0, 1)
    }

    /// Unused foods come first, so across everyday totals the fewest-items
    /// mode never repeats a food and the more-items mode shows one at most twice.
    func testFoodsRarelyRepeatAcrossTypicalTotals() {
        for kilocalories in stride(from: 100.0, through: 2500, by: 3.7) {
            let fewest = EnergyEquivalent.decompose(kilocalories: kilocalories)?.filter { $0.kilocalories > 0 } ?? []
            let more = EnergyEquivalent.decompose(kilocalories: kilocalories, preferringMoreItems: true)?.filter { $0.kilocalories > 0 } ?? []
            let fewestMax = Dictionary(fewest.map { ($0.emoji, 1) }, uniquingKeysWith: +).values.max() ?? 0
            let moreMax = Dictionary(more.map { ($0.emoji, 1) }, uniquingKeysWith: +).values.max() ?? 0
            XCTAssertLessThanOrEqual(fewestMax, 1, "fewest-items repeat at \(kilocalories) kcal")
            XCTAssertLessThanOrEqual(moreMax, 2, "more-items repeat at \(kilocalories) kcal")
        }
    }

    /// Reaching outside the band for variety is guarded near the cap, so a
    /// long workout still covers nearly all of its energy in 12 foods.
    func testLongWorkoutsKeepTheirCoverage() {
        for kilocalories in stride(from: 2500.0, through: 5500, by: 3.3) {
            let covered = EnergyEquivalent.decompose(kilocalories: kilocalories)?.reduce(0) { $0 + $1.kilocalories } ?? 0
            XCTAssertGreaterThanOrEqual(covered, kilocalories * 0.9, "coverage at \(kilocalories) kcal")
        }
    }

    /// A cached breakdown is reused only for the same food table and inputs;
    /// one drawn from an older table re-rolls once.
    func testCachedBreakdownIsReusedOnlyForTheSameTableAndInputs() {
        let cached = PersistedEnergyEquivalent(
            tuningVersion: EnergyEquivalent.tuningVersion,
            kilocalories: 300,
            hiddenFoods: ["🍔"],
            prefersMoreItems: nil,
            emojis: ["🍫"]
        )
        XCTAssertTrue(cached.isReusable(kilocalories: 300, hiddenFoods: ["🍔"], prefersMoreItems: false))
        XCTAssertFalse(cached.isReusable(kilocalories: 301, hiddenFoods: ["🍔"], prefersMoreItems: false))
        XCTAssertFalse(cached.isReusable(kilocalories: nil, hiddenFoods: ["🍔"], prefersMoreItems: false))
        XCTAssertFalse(cached.isReusable(kilocalories: 300, hiddenFoods: [], prefersMoreItems: false))
        XCTAssertFalse(cached.isReusable(kilocalories: 300, hiddenFoods: ["🍔"], prefersMoreItems: true))

        let olderTable = PersistedEnergyEquivalent(
            tuningVersion: 1,
            kilocalories: 300,
            hiddenFoods: ["🍔"],
            prefersMoreItems: false,
            emojis: ["🍫"]
        )
        XCTAssertNotEqual(EnergyEquivalent.tuningVersion, 1)
        XCTAssertFalse(olderTable.isReusable(kilocalories: 300, hiddenFoods: ["🍔"], prefersMoreItems: false))
    }
}
