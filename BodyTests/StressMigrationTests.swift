//
//  StressMigrationTests.swift
//  BodyTests
//
//  Covers the one-time home-card visibility migrations that hand an existing
//  user the new Stress metric — the summary-card and trend-card twins of
//  `CardioFitnessMigrationTests`. Stress has no permission migration (it reads
//  no new HealthKit types beyond what Readiness already covers), so only the
//  visibility migrations apply.
//

import XCTest
@testable import Body

final class StressMigrationTests: XCTestCase {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    // MARK: - Home card visibility migration

    func testCustomizedLayoutGainsTheStressCard() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // A customized layout saved before the card existed.
        defaults.set(
            "sleep,heartRate,steps",
            forKey: BodyAppearancePreference.summaryCardSelectionKey
        )

        let fetch = BodyDashboardFetchSelection.load(defaults: defaults)

        XCTAssertTrue(
            fetch.includes(.stress),
            "an unselected card is never fetched, so visibility must be migrated"
        )
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.summaryCardStressMigratedKey)
        )
    }

    func testStressCardVisibilityOptOutIsNotReEnabled() throws {
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

        XCTAssertFalse(reloaded.includes(.stress))
    }

    /// "Hide every card" is representable and reachable; turning it into a
    /// layout showing one lone Stress card would be a worse outcome than
    /// leaving it out.
    func testEmptyLayoutIsNotGivenALoneStressCard() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("none", forKey: BodyAppearancePreference.summaryCardSelectionKey)
        // As above: the trend surface would otherwise pull the metric in by itself.
        defaults.set("none", forKey: BodyAppearancePreference.homeTrendCardSelectionKey)

        let fetch = BodyDashboardFetchSelection.load(defaults: defaults)

        XCTAssertFalse(fetch.includes(.stress))
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.summaryCardStressMigratedKey),
            "still one-time"
        )
    }

    // MARK: - Trend card visibility migration

    /// Asserts on the trend selection itself rather than on `BodyDashboardFetchSelection`:
    /// that type unions both selections, so the summary-card migration would mask a
    /// trend-card one that never ran.
    func testCustomizedTrendListGainsTheStressTrendCard() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "heartRate,sleep,steps",
            forKey: BodyAppearancePreference.homeTrendCardSelectionKey
        )

        let migrated = BodyHomeTrendCardSelection.load(defaults: defaults)

        XCTAssertTrue(migrated.includes(BodyHomeTrendCardKind.stress))
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.homeTrendCardStressMigratedKey)
        )
        XCTAssertTrue(
            defaults.string(forKey: BodyAppearancePreference.homeTrendCardSelectionKey)?
                .contains("stress") == true,
            "the views read this key through @AppStorage, so the migration has to write it back"
        )
    }

    func testStressTrendCardOptOutIsNotReEnabled() throws {
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

        XCTAssertFalse(reloaded.includes(BodyHomeTrendCardKind.stress))
    }

    func testEmptyTrendListIsNotGivenALoneStressTrendCard() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("none", forKey: BodyAppearancePreference.homeTrendCardSelectionKey)

        let migrated = BodyHomeTrendCardSelection.load(defaults: defaults)

        XCTAssertEqual(migrated.enabledCount, 0)
        XCTAssertTrue(
            defaults.bool(forKey: BodyAppearancePreference.homeTrendCardStressMigratedKey),
            "still one-time"
        )
    }

    /// The two selections are stored under separate keys, so a user who customized
    /// only one of them must still be migrated for the other.
    func testTrendAndSummaryStressMigrationsRunIndependently() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("sleep,heartRate", forKey: BodyAppearancePreference.summaryCardSelectionKey)
        defaults.set(true, forKey: BodyAppearancePreference.summaryCardStressMigratedKey)
        defaults.set("heartRate,sleep", forKey: BodyAppearancePreference.homeTrendCardSelectionKey)

        _ = BodyDashboardFetchSelection.load(defaults: defaults)

        XCTAssertFalse(
            BodySummaryCardSelection.load(defaults: defaults).includes(.stress),
            "the summary migration already ran and must not run again"
        )
        XCTAssertTrue(
            BodyHomeTrendCardSelection.load(defaults: defaults).includes(BodyHomeTrendCardKind.stress)
        )
    }

    /// The Stress and Cardio Fitness migrations are keyed independently, so a
    /// user who already ran one must still be migrated for the other.
    func testStressAndCardioFitnessMigrationsRunIndependently() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("sleep,heartRate", forKey: BodyAppearancePreference.summaryCardSelectionKey)
        defaults.set(true, forKey: BodyAppearancePreference.summaryCardCardioFitnessMigratedKey)

        let migrated = BodySummaryCardSelection.load(defaults: defaults)

        XCTAssertFalse(migrated.includes(.cardioFitness), "the cardio fitness migration already ran")
        XCTAssertTrue(migrated.includes(.stress), "the stress migration is independently keyed")
    }
}
