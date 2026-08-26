//
//  EnergyEquivalent.swift
//  Body
//
//  Converts a workout's active-energy kilocalories into a handful of food
//  emoji, greedily decomposing the total over a fixed kcal table so the
//  "Equivalent" card can show something tangible instead of a bare number.
//  Pure and deterministic — no HealthKit or persistence dependency lives here.
//

import Foundation

enum EnergyEquivalent {
    /// Forensic metadata only, carried on the persisted payload — bumping this
    /// never invalidates a cached breakdown (see `HealthKitWorkoutStore`).
    static let tuningVersion = 1

    struct Food: Identifiable {
        let emoji: String
        let kilocalories: Double
        let name: LocalizedStringResource

        var id: String { emoji }
    }

    /// Fixed kcal table, descending. Values are approximate real-world
    /// portions, not a HealthKit or nutrition-database read.
    static let foods: [Food] = [
        Food(emoji: "🍔", kilocalories: 550, name: LocalizedStringResource("equivalent.food.burger", defaultValue: "Burger")),
        Food(emoji: "🍜", kilocalories: 450, name: LocalizedStringResource("equivalent.food.noodles", defaultValue: "Noodles")),
        Food(emoji: "🍣", kilocalories: 350, name: LocalizedStringResource("equivalent.food.sushi", defaultValue: "Sushi Roll")),
        Food(emoji: "🍟", kilocalories: 320, name: LocalizedStringResource("equivalent.food.fries", defaultValue: "Fries")),
        Food(emoji: "🍕", kilocalories: 285, name: LocalizedStringResource("equivalent.food.pizza", defaultValue: "Pizza Slice")),
        Food(emoji: "🥑", kilocalories: 240, name: LocalizedStringResource("equivalent.food.avocado", defaultValue: "Avocado")),
        Food(emoji: "🍚", kilocalories: 200, name: LocalizedStringResource("equivalent.food.rice", defaultValue: "Rice Bowl")),
        Food(emoji: "🍺", kilocalories: 150, name: LocalizedStringResource("equivalent.food.beer", defaultValue: "Beer")),
        Food(emoji: "🍦", kilocalories: 140, name: LocalizedStringResource("equivalent.food.iceCream", defaultValue: "Ice Cream")),
        Food(emoji: "🍞", kilocalories: 80, name: LocalizedStringResource("equivalent.food.bread", defaultValue: "Bread Slice")),
        Food(emoji: "🥟", kilocalories: 60, name: LocalizedStringResource("equivalent.food.dumpling", defaultValue: "Dumpling")),
        Food(emoji: "🍫", kilocalories: 50, name: LocalizedStringResource("equivalent.food.chocolate", defaultValue: "Chocolate Square")),
    ]

    static let maximumCount = 12

    /// Greedily decomposes `kilocalories` over the non-hidden foods, always
    /// taking the largest food at-or-below the remainder. Truncates at
    /// `maximumCount`; any remainder below the smallest available food is
    /// dropped rather than rounded up. Returns nil when there is nothing
    /// meaningful to show: a nil/zero/negative total, every food hidden, or a
    /// total below the smallest available food's kcal.
    static func decompose(kilocalories: Double?, excluding hidden: Set<String> = []) -> [Food]? {
        guard let kilocalories, kilocalories > 0 else { return nil }

        let available = foods.filter { !hidden.contains($0.emoji) }
        guard let smallest = available.last, kilocalories >= smallest.kilocalories else {
            return nil
        }

        var remainder = kilocalories
        var result: [Food] = []
        while result.count < maximumCount {
            guard let next = available.first(where: { $0.kilocalories <= remainder }) else {
                break
            }
            result.append(next)
            remainder -= next.kilocalories
        }

        return result
    }
}
