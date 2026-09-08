//
//  BodyWorkoutDetailCacheStoreTests.swift
//  BodyTests
//
//  The per-workout detail caches, lifted out of `HealthKitWorkoutStore`. These
//  pin the LRU eviction and, more importantly, the exact subset each clear
//  variant drops: a scoped permission toggle must not wipe caches it cannot
//  have invalidated, and the wholesale clear must leave nothing behind.
//

import XCTest
@testable import Body

@MainActor
final class BodyWorkoutDetailCacheStoreTests: XCTestCase {
    private func seedAll(_ caches: BodyWorkoutDetailCacheStore, id: UUID) {
        caches.touch(id)
        caches.routeCache[id] = .some(WorkoutRoute(coordinates: [], locality: nil))
        caches.routePresenceCache[id] = true
        caches.distanceSampleCache[id] = .empty
        caches.metricSeriesCache[id] = .empty
        caches.heartRateRecoveryCache[id] = .some(62)
        caches.heartRateSeriesCache[id] = []
        caches.energyEquivalentCache[id] = PersistedEnergyEquivalent(
            tuningVersion: 1,
            kilocalories: 400,
            hiddenFoods: [],
            prefersMoreItems: false,
            emojis: ["🍎"]
        )
        caches.detailHydrations[id] = Task {}
    }

    /// Every cache that currently holds an entry for `id`, by name.
    private func populated(_ caches: BodyWorkoutDetailCacheStore, id: UUID) -> Set<String> {
        var names: Set<String> = []
        if caches.routeCache[id] != nil { names.insert("routeCache") }
        if caches.routePresenceCache[id] != nil { names.insert("routePresenceCache") }
        if caches.distanceSampleCache[id] != nil { names.insert("distanceSampleCache") }
        if caches.metricSeriesCache[id] != nil { names.insert("metricSeriesCache") }
        if caches.heartRateRecoveryCache[id] != nil { names.insert("heartRateRecoveryCache") }
        if caches.heartRateSeriesCache[id] != nil { names.insert("heartRateSeriesCache") }
        if caches.energyEquivalentCache[id] != nil { names.insert("energyEquivalentCache") }
        if caches.detailHydrations[id] != nil { names.insert("detailHydrations") }
        return names
    }

    private static let allCacheNames: Set<String> = [
        "routeCache", "routePresenceCache", "distanceSampleCache", "metricSeriesCache",
        "heartRateRecoveryCache", "heartRateSeriesCache", "energyEquivalentCache",
        "detailHydrations"
    ]

    func testTouchKeepsMostRecentlyUsedOrderWithoutDuplicates() {
        let caches = BodyWorkoutDetailCacheStore()
        let a = UUID(), b = UUID(), c = UUID()
        caches.touch(a)
        caches.touch(b)
        caches.touch(c)
        caches.touch(a)
        XCTAssertEqual(caches.workoutDetailCacheOrder, [b, c, a])
    }

    func testTouchEvictsTheOldestWorkoutsBeyondTheCapAndDropsEveryCache() {
        let caches = BodyWorkoutDetailCacheStore()
        let ids = (0..<(HealthKitWorkoutStore.maximumCachedWorkoutDetails + 1)).map { _ in UUID() }
        for id in ids {
            seedAll(caches, id: id)
        }

        // The oldest-touched workout is the one that leaves, and it leaves every
        // cache at once — a half-evicted workout would serve a route with no
        // splits on the next open.
        XCTAssertEqual(caches.workoutDetailCacheOrder, Array(ids.dropFirst()))
        XCTAssertEqual(populated(caches, id: ids[0]), [])
        XCTAssertEqual(populated(caches, id: ids[1]), Self.allCacheNames)
    }

    func testClearAllDropsEveryCacheAndTheOrder() {
        let caches = BodyWorkoutDetailCacheStore()
        let id = UUID()
        seedAll(caches, id: id)

        caches.clearAll()

        XCTAssertEqual(populated(caches, id: id), [])
        XCTAssertTrue(caches.workoutDetailCacheOrder.isEmpty)
    }

    func testHeartScopedClearDropsOnlyTheHeartCaches() {
        let caches = BodyWorkoutDetailCacheStore()
        let id = UUID()
        seedAll(caches, id: id)

        caches.clearHeartScopedCaches()

        // Route, splits, series and the energy breakdown do not ride the Heart
        // toggle, so a Heart change must not cost the detail sheet its hero.
        XCTAssertEqual(
            populated(caches, id: id),
            ["routeCache", "routePresenceCache", "distanceSampleCache", "metricSeriesCache", "energyEquivalentCache"]
        )
        XCTAssertTrue(caches.workoutDetailCacheOrder.isEmpty)
    }

    func testWorkoutMetricsScopedClearDropsOnlyTheMetricsCaches() {
        let caches = BodyWorkoutDetailCacheStore()
        let id = UUID()
        seedAll(caches, id: id)

        caches.clearWorkoutMetricsScopedCaches()

        XCTAssertEqual(
            populated(caches, id: id),
            ["routeCache", "routePresenceCache", "heartRateRecoveryCache", "heartRateSeriesCache", "energyEquivalentCache"]
        )
        XCTAssertTrue(caches.workoutDetailCacheOrder.isEmpty)
    }
}
