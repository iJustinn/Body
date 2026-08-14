//
//  CardioFitnessMigrationTests.swift
//  BodyTests
//
//  Covers the two one-time migrations that hand an existing user the new Cardio
//  Fitness metric: the permission toggle (only for users who already had VO₂ max
//  readable, i.e. Workouts + Workout Metrics both on) and the home-card
//  visibility entry (customized layouts otherwise never gain a new card, and an
//  unselected card is never fetched). Both carry their own key so they run
//  independently of the older expanded-permissions migration, which has already
//  set its flag for every existing install.
//

import XCTest
@testable import Body

final class CardioFitnessMigrationTests: XCTestCase {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    // MARK: - Permission migration

    func testCardioFitnessPermissionIsAddedWhenWorkoutMetricsWereReadable() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Both parents on — this user could already read VO₂ max per workout.
        defaults.set(
            "workouts,workoutMetrics,heart",
            forKey: BodyAppearancePreference.healthPermissionSelectionKey
        )

        let migrated = BodyHealthPermissionSelection.load(defaults: defaults)

        XCTAssertTrue(migrated.includes(.cardioFitness))
        XCTAssertTrue(defaults.bool(forKey: BodyAppearancePreference.healthCardioFitnessMigratedKey))
    }

    /// The older expanded migration runs first and can insert `.workoutMetrics`
    /// for a pre-expansion selection, so a legacy Workouts-only user — who did
    /// have VO₂ max readable — must still be migrated.
    func testLegacyWorkoutsOnlySelectionStillGainsCardioFitness() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("workouts,sleep", forKey: BodyAppearancePreference.healthPermissionSelectionKey)

        let migrated = BodyHealthPermissionSelection.load(defaults: defaults)

        XCTAssertTrue(migrated.includes(.workoutMetrics), "the expanded migration runs first")
        XCTAssertTrue(migrated.includes(.cardioFitness))
    }

    func testCardioFitnessPermissionIsNotAddedWhenWorkoutsWereOff() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Heart on but Workouts off: VO₂ max was never readable for this user,
        // so the migration must not silently widen their granted data.
        defaults.set("heart,sleep", forKey: BodyAppearancePreference.healthPermissionSelectionKey)

        let migrated = BodyHealthPermissionSelection.load(defaults: defaults)

        XCTAssertFalse(migrated.includes(.cardioFitness))
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.healthCardioFitnessMigratedKey),
            "the flag is still recorded so this stays strictly one-time"
        )
    }

    func testCardioFitnessPermissionOptOutIsNotReEnabled() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "workouts,workoutMetrics",
            forKey: BodyAppearancePreference.healthPermissionSelectionKey
        )
        let migrated = BodyHealthPermissionSelection.load(defaults: defaults)
        XCTAssertTrue(migrated.includes(.cardioFitness))

        migrated.setting(.cardioFitness, isEnabled: false).save(defaults: defaults)

        let reloaded = BodyHealthPermissionSelection.load(defaults: defaults)
        XCTAssertFalse(reloaded.includes(.cardioFitness), "a deliberate opt-out must stick")
    }

    // MARK: - Home card visibility migration

    func testCustomizedLayoutGainsTheCardioFitnessCard() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // A customized layout saved before the card existed.
        defaults.set(
            "sleep,heartRate,steps",
            forKey: BodyAppearancePreference.summaryCardSelectionKey
        )

        let fetch = BodyDashboardFetchSelection.load(defaults: defaults)

        XCTAssertTrue(
            fetch.includes(.cardioFitness),
            "an unselected card is never fetched, so visibility must be migrated"
        )
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.summaryCardCardioFitnessMigratedKey)
        )
    }

    func testCardioFitnessCardVisibilityOptOutIsNotReEnabled() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "sleep,heartRate",
            forKey: BodyAppearancePreference.summaryCardSelectionKey
        )
        _ = BodyDashboardFetchSelection.load(defaults: defaults)

        // The user hides it again; a second load must respect that.
        defaults.set(
            "sleep,heartRate",
            forKey: BodyAppearancePreference.summaryCardSelectionKey
        )
        let reloaded = BodyDashboardFetchSelection.load(defaults: defaults)

        XCTAssertFalse(reloaded.includes(.cardioFitness))
    }

    /// "Hide every card" is representable and reachable; turning it into a
    /// layout showing one lone Cardio Fitness card would be a worse outcome than
    /// leaving it out.
    func testEmptyLayoutIsNotGivenALoneCardioFitnessCard() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("none", forKey: BodyAppearancePreference.summaryCardSelectionKey)

        let fetch = BodyDashboardFetchSelection.load(defaults: defaults)

        XCTAssertFalse(fetch.includes(.cardioFitness))
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.summaryCardCardioFitnessMigratedKey),
            "still one-time"
        )
    }
}
