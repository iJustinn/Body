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

        BodyHealthPermissionSelection.migrateIfNeeded(defaults: defaults)
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

        BodyHealthPermissionSelection.migrateIfNeeded(defaults: defaults)
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

        BodyHealthPermissionSelection.migrateIfNeeded(defaults: defaults)
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
        BodyHealthPermissionSelection.migrateIfNeeded(defaults: defaults)
        let migrated = BodyHealthPermissionSelection.load(defaults: defaults)
        XCTAssertTrue(migrated.includes(.cardioFitness))

        migrated.setting(.cardioFitness, isEnabled: false).save(defaults: defaults)

        BodyHealthPermissionSelection.migrateIfNeeded(defaults: defaults)
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
        // The fetch selection unions both surfaces, and the trend list defaults to
        // every card — so the trend card would supply the metric on its own. Silence
        // it to keep this about summary-card visibility.
        defaults.set("none", forKey: BodyAppearancePreference.homeTrendCardSelectionKey)
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
        // As above: the trend surface would otherwise pull the metric in by itself.
        defaults.set("none", forKey: BodyAppearancePreference.homeTrendCardSelectionKey)

        let fetch = BodyDashboardFetchSelection.load(defaults: defaults)

        XCTAssertFalse(fetch.includes(.cardioFitness))
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.summaryCardCardioFitnessMigratedKey),
            "still one-time"
        )
    }

    // MARK: - Trend card visibility migration

    /// Asserts on the trend selection itself rather than on `BodyDashboardFetchSelection`:
    /// that type unions both selections, so the summary-card migration would mask a
    /// trend-card one that never ran.
    func testCustomizedTrendListGainsTheCardioFitnessTrendCard() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "heartRate,sleep,steps",
            forKey: BodyAppearancePreference.homeTrendCardSelectionKey
        )

        let migrated = BodyHomeTrendCardSelection.load(defaults: defaults)

        XCTAssertTrue(migrated.includes(BodyHomeTrendCardKind.cardioFitness))
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.homeTrendCardCardioFitnessMigratedKey)
        )
        XCTAssertTrue(
            defaults.string(forKey: BodyAppearancePreference.homeTrendCardSelectionKey)?
                .contains("cardioFitness") == true,
            "the views read this key through @AppStorage, so the migration has to write it back"
        )
    }

    func testCardioFitnessTrendCardOptOutIsNotReEnabled() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "heartRate,sleep",
            forKey: BodyAppearancePreference.homeTrendCardSelectionKey
        )
        _ = BodyHomeTrendCardSelection.load(defaults: defaults)

        defaults.set(
            "heartRate,sleep",
            forKey: BodyAppearancePreference.homeTrendCardSelectionKey
        )
        let reloaded = BodyHomeTrendCardSelection.load(defaults: defaults)

        XCTAssertFalse(reloaded.includes(BodyHomeTrendCardKind.cardioFitness))
    }

    func testEmptyTrendListIsNotGivenALoneCardioFitnessTrendCard() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("none", forKey: BodyAppearancePreference.homeTrendCardSelectionKey)

        let migrated = BodyHomeTrendCardSelection.load(defaults: defaults)

        XCTAssertEqual(migrated.enabledCount, 0)
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.homeTrendCardCardioFitnessMigratedKey),
            "still one-time"
        )
    }

    /// The two selections are stored under separate keys, so a user who customized
    /// only one of them must still be migrated for the other.
    func testTrendAndSummaryMigrationsRunIndependently() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("sleep,heartRate", forKey: BodyAppearancePreference.summaryCardSelectionKey)
        defaults.set(true, forKey: BodyAppearancePreference.summaryCardCardioFitnessMigratedKey)
        defaults.set("heartRate,sleep", forKey: BodyAppearancePreference.homeTrendCardSelectionKey)

        _ = BodyDashboardFetchSelection.load(defaults: defaults)

        XCTAssertFalse(
            BodySummaryCardSelection.load(defaults: defaults).includes(.cardioFitness),
            "the summary migration already ran and must not run again"
        )
        XCTAssertTrue(
            BodyHomeTrendCardSelection.load(defaults: defaults).includes(BodyHomeTrendCardKind.cardioFitness)
        )
    }
}
