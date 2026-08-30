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
        Food(emoji: "🧋", kilocalories: 340, name: LocalizedStringResource("equivalent.food.bubbleTea", defaultValue: "Bubble Tea")),
        Food(emoji: "🍟", kilocalories: 320, name: LocalizedStringResource("equivalent.food.fries", defaultValue: "Fries")),
        Food(emoji: "🌭", kilocalories: 300, name: LocalizedStringResource("equivalent.food.hotDog", defaultValue: "Hot Dog")),
        Food(emoji: "🍕", kilocalories: 285, name: LocalizedStringResource("equivalent.food.pizza", defaultValue: "Pizza Slice")),
        Food(emoji: "🥐", kilocalories: 260, name: LocalizedStringResource("equivalent.food.croissant", defaultValue: "Croissant")),
        Food(emoji: "🍩", kilocalories: 250, name: LocalizedStringResource("equivalent.food.donut", defaultValue: "Donut")),
        Food(emoji: "🥑", kilocalories: 240, name: LocalizedStringResource("equivalent.food.avocado", defaultValue: "Avocado")),
        Food(emoji: "🌮", kilocalories: 220, name: LocalizedStringResource("equivalent.food.taco", defaultValue: "Taco")),
        Food(emoji: "🍚", kilocalories: 200, name: LocalizedStringResource("equivalent.food.rice", defaultValue: "Rice Bowl")),
        Food(emoji: "☕", kilocalories: 190, name: LocalizedStringResource("equivalent.food.latte", defaultValue: "Latte")),
        Food(emoji: "🍙", kilocalories: 180, name: LocalizedStringResource("equivalent.food.riceBall", defaultValue: "Rice Ball")),
        Food(emoji: "🥤", kilocalories: 160, name: LocalizedStringResource("equivalent.food.soda", defaultValue: "Soda")),
        Food(emoji: "🍺", kilocalories: 150, name: LocalizedStringResource("equivalent.food.beer", defaultValue: "Beer")),
        Food(emoji: "🍦", kilocalories: 140, name: LocalizedStringResource("equivalent.food.iceCream", defaultValue: "Ice Cream")),
        Food(emoji: "🥭", kilocalories: 130, name: LocalizedStringResource("equivalent.food.mango", defaultValue: "Mango")),
        Food(emoji: "🍷", kilocalories: 125, name: LocalizedStringResource("equivalent.food.wine", defaultValue: "Glass of Wine")),
        Food(emoji: "🍌", kilocalories: 100, name: LocalizedStringResource("equivalent.food.banana", defaultValue: "Banana")),
        Food(emoji: "🍎", kilocalories: 95, name: LocalizedStringResource("equivalent.food.apple", defaultValue: "Apple")),
        Food(emoji: "🍇", kilocalories: 90, name: LocalizedStringResource("equivalent.food.grapes", defaultValue: "Grapes")),
        Food(emoji: "🍉", kilocalories: 85, name: LocalizedStringResource("equivalent.food.watermelon", defaultValue: "Watermelon Slice")),
        Food(emoji: "🍞", kilocalories: 80, name: LocalizedStringResource("equivalent.food.bread", defaultValue: "Bread Slice")),
        Food(emoji: "🍪", kilocalories: 70, name: LocalizedStringResource("equivalent.food.cookie", defaultValue: "Cookie")),
        Food(emoji: "🍊", kilocalories: 65, name: LocalizedStringResource("equivalent.food.orange", defaultValue: "Orange")),
        Food(emoji: "🥟", kilocalories: 60, name: LocalizedStringResource("equivalent.food.dumpling", defaultValue: "Dumpling")),
        Food(emoji: "🍫", kilocalories: 50, name: LocalizedStringResource("equivalent.food.chocolate", defaultValue: "Chocolate Square")),
    ]

    static let maximumCount = 12

    /// Zero-kcal filler so one- or two-emoji breakdowns still feel like a
    /// physics toy. Lives outside `foods`: it represents nothing, so it can't
    /// be picked, hidden, or counted toward the total.
    static let iceCube = Food(emoji: "🧊", kilocalories: 0, name: LocalizedStringResource("equivalent.food.iceCube", defaultValue: "Ice Cube"))

    /// Greedily decomposes `kilocalories` over the non-hidden foods. Each step
    /// draws from a small band of similar-kcal candidates instead of always
    /// taking the single largest fit, so the mix varies between workouts —
    /// the draw is seeded by the kcal total, keeping the same input mapping to
    /// the same output (the persisted-breakdown contract relies on that).
    /// Truncates at `maximumCount`; any remainder below the smallest available
    /// food is dropped rather than rounded up. Returns nil when there is
    /// nothing meaningful to show: a nil/zero/negative total, every food
    /// hidden, or a total below the smallest available food's kcal.
    ///
    /// `preferringMoreItems` trades single large foods for a fuller card: the
    /// band then centers on the piece size that fills the cap, so 500 kcal
    /// reads as a handful of small snacks instead of one noodle bowl.
    static func decompose(
        kilocalories: Double?,
        excluding hidden: Set<String> = [],
        preferringMoreItems: Bool = false
    ) -> [Food]? {
        guard let kilocalories, kilocalories > 0 else { return nil }

        let available = foods.filter { !hidden.contains($0.emoji) }
        guard let smallest = available.last, kilocalories >= smallest.kilocalories else {
            return nil
        }

        var generator = SeededGenerator(seed: kilocalories.bitPattern)
        let idealPiece = kilocalories / Double(maximumCount)

        var remainder = kilocalories
        var result: [Food] = []
        while result.count < maximumCount {
            let fitting = available.filter { $0.kilocalories <= remainder }
            guard let largest = fitting.first, let smallestFit = fitting.last else { break }

            let band: [Food]
            if preferringMoreItems {
                // Foods around the piece size that would fill the card; when the
                // remainder is too small for that band, the smallest fit keeps
                // the pieces plentiful.
                let centered = fitting.filter { $0.kilocalories >= idealPiece * 0.5 && $0.kilocalories <= idealPiece * 2 }
                band = centered.isEmpty ? [smallestFit] : centered
            } else {
                // Foods within reach of the best fit, so the count stays low but
                // the pick isn't always the same glyph.
                band = fitting.filter { $0.kilocalories >= largest.kilocalories * 0.7 }
            }

            guard let next = band.randomElement(using: &generator) else { break }
            result.append(next)
            remainder -= next.kilocalories
        }

        // Sparse breakdowns get a few zero-kcal ice cubes so the card still has
        // something to knock around; the draw shares the seeded generator, so
        // the pad count is as stable as the mix itself.
        if !result.isEmpty, result.count <= 2 {
            let padCount = 2 + Int(generator.next() % 3)
            result.append(contentsOf: Array(repeating: iceCube, count: padCount))
        }

        return result
    }
}

/// SplitMix64 — a tiny deterministic generator so `decompose`'s draws are a
/// pure function of the seed (the system generator would reshuffle every call).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
