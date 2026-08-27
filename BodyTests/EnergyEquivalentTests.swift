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

    /// The smallest food (🍫, 50 kcal) is the floor — anything below it has
    /// nothing meaningful to show.
    func testBelowSmallestFoodReturnsNil() {
        XCTAssertNil(EnergyEquivalent.decompose(kilocalories: 30))
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
}
