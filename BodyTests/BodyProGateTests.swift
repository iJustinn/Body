//
//  BodyProGateTests.swift
//  BodyTests
//
//  The Day Ring Home Hero gate added in 1.1.3 build 3: a free user's stored Day
//  Ring pick falls back to the Readiness Ring everywhere until Pro unlocks.
//

import XCTest
@testable import Body

final class BodyProGateTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func anchor() throws -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 25
        components.hour = 10
        components.timeZone = TimeZone.current
        return try XCTUnwrap(calendar.date(from: components))
    }

    // MARK: - Home Hero

    func testDayRingIsTheOnlyProGatedHero() {
        XCTAssertTrue(BodyStarMetric.dayRing.isProGated)
        XCTAssertFalse(BodyStarMetric.readiness.isProGated)
    }

    func testStoredDayRingFallsBackToReadinessUntilProUnlocks() {
        XCTAssertEqual(BodyStarMetric.proGated(.dayRing, isProUnlocked: false), .readiness)
        XCTAssertEqual(BodyStarMetric.proGated(.dayRing, isProUnlocked: true), .dayRing)
    }

    func testReadinessAndNoneStayFree() {
        XCTAssertEqual(BodyStarMetric.proGated(.readiness, isProUnlocked: false), .readiness)
        XCTAssertNil(BodyStarMetric.proGated(nil, isProUnlocked: false))
        XCTAssertNil(BodyStarMetric.proGated(nil, isProUnlocked: true))
    }

    /// The hero a free user sees is the Readiness Ring, so its data must be fetched
    /// even when the Readiness card is off and the stored pick is the Day Ring.
    func testFetchSelectionFetchesReadinessForTheHeroAFreeUserSees() throws {
        let suiteName = "BodyProGateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var cards = BodySummaryCardSelection.defaultValue
        cards.selectedCards.remove(.readiness)
        defaults.set(cards.rawValue, forKey: BodyAppearancePreference.summaryCardSelectionKey)
        defaults.set(BodyHomeTrendCardSelection(selectedCards: []).rawValue, forKey: BodyAppearancePreference.homeTrendCardSelectionKey)
        defaults.set(BodyStarMetric.dayRing.rawValue, forKey: BodyAppearancePreference.starredMetricKey)

        XCTAssertTrue(BodyDashboardFetchSelection.load(defaults: defaults, isProUnlocked: false).includesFullPayload(.readiness))
        XCTAssertFalse(BodyDashboardFetchSelection.load(defaults: defaults, isProUnlocked: true).includesFullPayload(.readiness))
    }
}
