//
//  BodyReadinessHeroWarningBadgeTests.swift
//  BodyTests
//

import SwiftUI
import XCTest
@testable import Body

/// The readiness hero mirrors the Home cards' warning glyphs. The badges are derived
/// from the finished card models, so these cover the derivation rather than the
/// detection: order, gating, and that a badge never invents a glyph, tint or name its
/// card isn't already showing.
final class BodyReadinessHeroWarningBadgeTests: XCTestCase {
    private func model(
        kind: HealthMetricKind,
        title: String,
        warningSymbolName: String?,
        warningColor: Color = .yellow,
        warningAccessibilityLabel: String? = nil
    ) -> BodyHealthMetricCard.Model {
        BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: "--",
            unit: "",
            symbolName: "heart.fill",
            symbolColor: .red,
            warningSymbolName: warningSymbolName,
            warningColor: warningColor,
            warningAccessibilityLabel: warningAccessibilityLabel
        )
    }

    private var warnedHeartRate: BodyHealthMetricCard.Model {
        model(kind: .heartRate, title: "Heart Rate", warningSymbolName: "exclamationmark.triangle.fill")
    }

    private var warnedOxygen: BodyHealthMetricCard.Model {
        model(kind: .oxygenSaturation, title: "Blood Oxygen", warningSymbolName: "exclamationmark.triangle.fill")
    }

    private var warnedBodyRadar: BodyHealthMetricCard.Model {
        model(
            kind: .bodyRadar,
            title: "Body Radar",
            warningSymbolName: "exclamationmark.triangle.fill",
            warningColor: .red,
            warningAccessibilityLabel: "Major signs"
        )
    }

    func testBadgesFollowTheVisibleCardOrderRatherThanTheWarningKindOrder() {
        let badges = BodyReadinessHeroWarningBadge.badges(
            visibleCards: [.oxygenSaturation, .sleep, .heartRate],
            lookup: [
                .heartRate: warnedHeartRate,
                .oxygenSaturation: warnedOxygen,
                .sleep: model(kind: .sleep, title: "Sleep", warningSymbolName: nil)
            ]
        )

        XCTAssertEqual(badges.map(\.card), [.oxygenSaturation, .heartRate])
    }

    func testACardMissingFromTheVisibleListContributesNoBadge() {
        let badges = BodyReadinessHeroWarningBadge.badges(
            visibleCards: [.heartRate],
            lookup: [.heartRate: warnedHeartRate, .oxygenSaturation: warnedOxygen]
        )

        XCTAssertEqual(badges.map(\.card), [.heartRate])
    }

    func testACardWithoutAWarningGlyphContributesNoBadge() {
        let badges = BodyReadinessHeroWarningBadge.badges(
            visibleCards: [.heartRate, .oxygenSaturation],
            lookup: [
                .heartRate: model(kind: .heartRate, title: "Heart Rate", warningSymbolName: nil),
                .oxygenSaturation: warnedOxygen
            ]
        )

        XCTAssertEqual(badges.map(\.card), [.oxygenSaturation])
    }

    func testACardWithNoModelAtAllContributesNoBadge() {
        let badges = BodyReadinessHeroWarningBadge.badges(
            visibleCards: [.heartRate, .activityRings],
            lookup: [.heartRate: warnedHeartRate]
        )

        XCTAssertEqual(badges.map(\.card), [.heartRate])
    }

    func testBadgeCarriesItsCardsOwnGlyphAndTint() {
        let badges = BodyReadinessHeroWarningBadge.badges(
            visibleCards: [.heartRate, .bodyRadar],
            lookup: [.heartRate: warnedHeartRate, .bodyRadar: warnedBodyRadar]
        )

        XCTAssertEqual(badges.map(\.symbolName), ["exclamationmark.triangle.fill", "exclamationmark.triangle.fill"])
        XCTAssertEqual(badges.first?.color, .yellow)
        // Body Radar tints its badge by region, so it must not inherit the heart
        // cards' yellow.
        XCTAssertEqual(badges.last?.color, .red)
    }

    func testBodyRadarSpeaksItsVerdictWhileTheHeartCardsFallBackToTheirTitle() {
        let badges = BodyReadinessHeroWarningBadge.badges(
            visibleCards: [.heartRate, .oxygenSaturation, .bodyRadar],
            lookup: [
                .heartRate: warnedHeartRate,
                .oxygenSaturation: warnedOxygen,
                .bodyRadar: warnedBodyRadar
            ]
        )

        XCTAssertEqual(
            badges.map(\.accessibilityLabel),
            [
                String(localized: "Heart Rate"),
                String(localized: "Blood Oxygen"),
                "Major signs"
            ]
        )
        // Never the card badge's hardcoded fallback wording.
        XCTAssertFalse(badges.map(\.accessibilityLabel).contains(String(localized: "Low Heart Rate")))
    }

    func testEveryCardThatCanCarryAGlyphStillYieldsAtMostThreeBadges() {
        let lookup: [HealthMetricKind: BodyHealthMetricCard.Model] = [
            .heartRate: warnedHeartRate,
            .oxygenSaturation: warnedOxygen,
            .bodyRadar: warnedBodyRadar
        ]
        let badges = BodyReadinessHeroWarningBadge.badges(
            visibleCards: BodyHomeCardKind.allCases,
            lookup: lookup
        )

        XCTAssertEqual(badges.count, 3)
        XCTAssertEqual(Set(badges.map(\.id)).count, 3)
    }

    /// A hero badge scrolls by `BodyHomeCardKind.id`, and Home's one ScrollView also
    /// hosts the trends section. `BodyHomeCardKind` and `HealthMetricKind` share raw
    /// values, so without the trend cards' prefix both publish "heartRate" and
    /// `scrollTo` picks whichever it likes.
    func testGridAndTrendCardScrollIDsCannotCollide() {
        let gridIDs = Set(BodyHomeCardKind.allCases.map(\.id))
        let trendIDs = Set(HealthMetricKind.allCases.map { BodyHomeTrendCard.Model.scrollIDPrefix + $0.id })

        XCTAssertTrue(gridIDs.isDisjoint(with: trendIDs))
        // The prefix is what does it: the raw ids really do overlap.
        XCTAssertFalse(gridIDs.isDisjoint(with: Set(HealthMetricKind.allCases.map(\.id))))
    }

    func testNoVisibleCardsMeansNoBadges() {
        XCTAssertTrue(
            BodyReadinessHeroWarningBadge.badges(
                visibleCards: [],
                lookup: [.heartRate: warnedHeartRate]
            ).isEmpty
        )
    }
}
