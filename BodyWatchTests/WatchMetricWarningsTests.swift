//
//  WatchMetricWarningsTests.swift
//  BodyWatchTests
//
//  What the watch draws for the phone's metric warnings (`WatchMetricWarnings`):
//  each warning lands on the card of its metric in the phone's kind order,
//  folded warnings leave the glyph and the hero badges, a badge points only at
//  a card the dashboard shows and only while the phone's Show on Home Hero
//  switch is on, and the card sentence is the phone's copy, time format and
//  temperature text.
//

import XCTest
@testable import BodyWatch

final class WatchMetricWarningsTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 812_783_520)

    private func warning(_ kind: String, threshold: Double = 120) -> WatchMetricWarning {
        WatchMetricWarning(
            kind: kind,
            startDate: start,
            threshold: threshold,
            foldKey: "\(kind)@2026-10-04",
            isFolded: false
        )
    }

    private func warning(_ kind: MetricWarningKind, threshold: Double? = nil) -> WatchMetricWarning {
        warning(kind.rawValue, threshold: threshold ?? kind.defaultThreshold)
    }

    private let unfolded: (WatchMetricWarning) -> Bool = { _ in false }

    /// Mixed input order, plus kinds the watch has no card for and a kind a
    /// newer phone might send.
    private var warnings: [WatchMetricWarning] {
        [
            warning(.highHeartRate),
            warning(.highWristTemperature),
            warning(.lowBloodOxygen),
            warning(.lowHeartRate),
            warning(.highRespiratoryRate),
            warning("lowBodyTemperature")
        ]
    }

    // MARK: - Rows

    func testRowsFollowTheKindOrderOnTheirOwnCard() {
        let heart = WatchMetricWarnings.rows(forCardKind: WatchMetricKindKey.heartRate, in: warnings, isFolded: unfolded)
        XCTAssertEqual(heart.map(\.kind), [.lowHeartRate, .highHeartRate])
        XCTAssertEqual(heart.map(\.id), ["lowHeartRate@2026-10-04", "highHeartRate@2026-10-04"])

        let skin = WatchMetricWarnings.rows(forCardKind: WatchMetricKindKey.wristTemperature, in: warnings, isFolded: unfolded)
        XCTAssertEqual(skin.map(\.kind), [.highWristTemperature])

        // Warned metrics without a watch card, and cards without warnings.
        XCTAssertTrue(WatchMetricWarnings.rows(forCardKind: MetricWarningKind.lowBloodOxygen.metric.rawValue, in: warnings, isFolded: unfolded).isEmpty)
        XCTAssertTrue(WatchMetricWarnings.rows(forCardKind: MetricWarningKind.highRespiratoryRate.metric.rawValue, in: warnings, isFolded: unfolded).isEmpty)
        XCTAssertTrue(WatchMetricWarnings.rows(forCardKind: WatchMetricKindKey.sleep, in: warnings, isFolded: unfolded).isEmpty)
    }

    func testRowsCarryTheFoldState() {
        let rows = WatchMetricWarnings.rows(forCardKind: WatchMetricKindKey.heartRate, in: warnings) { $0.kind == "lowHeartRate" }

        XCTAssertEqual(rows.map(\.isFolded), [true, false])
    }

    // MARK: - Card glyph

    func testGlyphLabelListsTheUnfoldedTitles() {
        let both = WatchMetricWarnings.glyphLabel(forCardKind: WatchMetricKindKey.heartRate, in: warnings, isFolded: unfolded)
        XCTAssertEqual(both, ListFormatter.localizedString(byJoining: [
            WatchMetricWarnings.title(for: .lowHeartRate)!,
            WatchMetricWarnings.title(for: .highHeartRate)!
        ]))

        let highOnly = WatchMetricWarnings.glyphLabel(forCardKind: WatchMetricKindKey.heartRate, in: warnings) { $0.kind == "lowHeartRate" }
        XCTAssertEqual(highOnly, WatchMetricWarnings.title(for: .highHeartRate))
    }

    func testGlyphLabelIsNilWhenEveryWarningIsFolded() {
        XCTAssertNil(WatchMetricWarnings.glyphLabel(forCardKind: WatchMetricKindKey.heartRate, in: warnings) { _ in true })
        XCTAssertNil(WatchMetricWarnings.glyphLabel(forCardKind: WatchMetricKindKey.heartRate, in: [], isFolded: unfolded))
    }

    // MARK: - Hero badges

    func testHeroBadgesFollowTheCardOrder() {
        let badges = WatchMetricWarnings.heroBadges(
            cardKinds: [WatchMetricKindKey.sleep, WatchMetricKindKey.wristTemperature, WatchMetricKindKey.heartRate],
            warnings: warnings,
            showsOnHero: true,
            isFolded: unfolded
        )

        XCTAssertEqual(badges.map(\.cardKind), [WatchMetricKindKey.wristTemperature, WatchMetricKindKey.heartRate])
        XCTAssertEqual(badges.first?.titles, [WatchMetricWarnings.title(for: .highWristTemperature)].compactMap { $0 })
        XCTAssertEqual(
            badges.last?.titles,
            [WatchMetricWarnings.title(for: .lowHeartRate), WatchMetricWarnings.title(for: .highHeartRate)].compactMap { $0 }
        )
    }

    /// The hero's VoiceOver value joins every badge's titles into one list, so
    /// the badges hand over plain titles: in the card order, each card's in
    /// kind order, never a list already formatted per card.
    func testHeroBadgeTitlesFlattenToOneOrderedList() {
        let badges = WatchMetricWarnings.heroBadges(
            cardKinds: [WatchMetricKindKey.heartRate, WatchMetricKindKey.wristTemperature],
            warnings: warnings,
            showsOnHero: true,
            isFolded: unfolded
        )

        let titles = badges.flatMap(\.titles)
        XCTAssertEqual(
            titles,
            [
                WatchMetricWarnings.title(for: .lowHeartRate),
                WatchMetricWarnings.title(for: .highHeartRate),
                WatchMetricWarnings.title(for: .highWristTemperature)
            ].compactMap { $0 }
        )
        XCTAssertEqual(titles.count, 3)
    }

    func testHeroBadgesFollowThePhonesSwitch() {
        XCTAssertTrue(WatchMetricWarnings.heroBadges(
            cardKinds: [WatchMetricKindKey.heartRate, WatchMetricKindKey.wristTemperature],
            warnings: warnings,
            showsOnHero: false,
            isFolded: unfolded
        ).isEmpty)
    }

    /// Heart Rate hidden on the watch: its warnings badge nothing, as a phone
    /// badge only points at a card the user can see.
    func testAHiddenCardContributesNoBadge() {
        let badges = WatchMetricWarnings.heroBadges(
            cardKinds: [WatchMetricKindKey.wristTemperature],
            warnings: warnings,
            showsOnHero: true,
            isFolded: unfolded
        )

        XCTAssertEqual(badges.map(\.cardKind), [WatchMetricKindKey.wristTemperature])
    }

    func testFoldedWarningsLeaveTheHero() {
        let badges = WatchMetricWarnings.heroBadges(
            cardKinds: [WatchMetricKindKey.heartRate, WatchMetricKindKey.wristTemperature],
            warnings: warnings,
            showsOnHero: true
        ) { $0.kind == "highWristTemperature" }

        XCTAssertEqual(badges.map(\.cardKind), [WatchMetricKindKey.heartRate])
    }

    // MARK: - Copy

    func testTitlesExistOnlyForTheCardedKinds() {
        XCTAssertEqual(WatchMetricWarnings.title(for: .lowHeartRate), "Low Heart Rate")
        XCTAssertEqual(WatchMetricWarnings.title(for: .highHeartRate), "High Heart Rate")
        XCTAssertEqual(WatchMetricWarnings.title(for: .highWristTemperature), "High Skin Temperature")
        XCTAssertNil(WatchMetricWarnings.title(for: .lowBloodOxygen))
        XCTAssertNil(WatchMetricWarnings.title(for: .highRespiratoryRate))
    }

    func testHeartRateSentencesAreThePhonesCopy() {
        let time = start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        XCTAssertEqual(WatchMetricWarnings.timeText(for: start), time)

        XCTAssertEqual(
            WatchMetricWarnings.sentence(for: warning(.lowHeartRate, threshold: 42), kind: .lowHeartRate, usesFahrenheit: false),
            "Your heart rate fell below 42 BPM starting at \(time)."
        )
        XCTAssertEqual(
            WatchMetricWarnings.sentence(for: warning(.highHeartRate, threshold: 128), kind: .highHeartRate, usesFahrenheit: true),
            "Your heart rate rose above 128 BPM starting at \(time)."
        )
    }

    /// The threshold arrives in °C and reads in the Skin Temp card's unit,
    /// through the phone's one temperature formatter.
    func testSkinTemperatureSentenceUsesTheCardsUnit() throws {
        let time = start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let skin = warning(.highWristTemperature, threshold: 37.5)

        let celsius = BodyMetricWarningTemperatureText.text(celsius: 37.5, temperatureUnitPreference: .celsius)
        let fahrenheit = BodyMetricWarningTemperatureText.text(celsius: 37.5, temperatureUnitPreference: .fahrenheit)
        XCTAssertTrue(celsius.hasSuffix("°C"))
        XCTAssertTrue(fahrenheit.hasSuffix("°F"))

        XCTAssertEqual(
            WatchMetricWarnings.sentence(for: skin, kind: .highWristTemperature, usesFahrenheit: false),
            "Your skin temperature rose above \(celsius) starting at \(time)."
        )
        XCTAssertEqual(
            WatchMetricWarnings.sentence(for: skin, kind: .highWristTemperature, usesFahrenheit: true),
            "Your skin temperature rose above \(fahrenheit) starting at \(time)."
        )
        XCTAssertNil(WatchMetricWarnings.sentence(for: warning(.lowBloodOxygen), kind: .lowBloodOxygen, usesFahrenheit: false))
    }
}
