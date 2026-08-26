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

    /// 1000 → 🍔550 leaves 450 → 🍜450 leaves 0. Exact greedy sequence.
    func testKnownKilocaloriesProducesExpectedSequence() {
        let result = EnergyEquivalent.decompose(kilocalories: 1000)
        XCTAssertEqual(result?.map { $0.emoji }, ["🍔", "🍜"])
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

    /// Excluding the burger forces the 1000 kcal case onto smaller foods.
    func testExcludingFoodsChangesResult() {
        let withBurger = EnergyEquivalent.decompose(kilocalories: 1000)
        let withoutBurger = EnergyEquivalent.decompose(kilocalories: 1000, excluding: ["🍔"])
        XCTAssertEqual(withBurger?.map { $0.emoji }, ["🍔", "🍜"])
        XCTAssertNotEqual(withoutBurger?.map { $0.emoji }, withBurger?.map { $0.emoji })
        XCTAssertFalse(withoutBurger?.contains { $0.emoji == "🍔" } ?? true)
    }

    func testAllFoodsHiddenReturnsNil() {
        let allEmojis = Set(EnergyEquivalent.foods.map { $0.emoji })
        XCTAssertNil(EnergyEquivalent.decompose(kilocalories: 1000, excluding: allEmojis))
    }

    func testFoodsAreStrictlyDescendingByKilocalories() {
        let kcals = EnergyEquivalent.foods.map { $0.kilocalories }
        for (a, b) in zip(kcals, kcals.dropFirst()) {
            XCTAssertGreaterThan(a, b)
        }
    }
}
