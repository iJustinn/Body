//
//  WatchMetricWarningsTests.swift
//  BodyWatchTests
//
//  What the watch draws for today's metric warnings (`WatchMetricWarnings`):
//  each warning lands on the card of its metric in the phone's kind order,
//  folded warnings leave the glyph and the hero badges, a badge points only at
//  a card the dashboard shows and only while the phone's Show on Home Hero
//  switch is on, and the card sentence is the phone's copy, time format and
//  temperature text. Heart Rate, Blood Oxygen and Skin Temp carry warnings;
//  High Respiratory Rate, with no watch card, never shows.
//
//  The warnings shown are the phone's together with the watch's own checks
//  under the phone's settings, one per kind with the earlier start winning,
//  and none of High Heart Rate starting inside a workout or its 30 minute
//  grace; the fold resend list keeps every fold key once, workouts or not.
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

    /// Mixed input order, plus a kind the watch has no card for (High
    /// Respiratory Rate) and a kind a newer phone might send.
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

        let oxygen = WatchMetricWarnings.rows(forCardKind: WatchMetricKindKey.oxygenSaturation, in: warnings, isFolded: unfolded)
        XCTAssertEqual(oxygen.map(\.kind), [.lowBloodOxygen])
        XCTAssertEqual(MetricWarningKind.lowBloodOxygen.metric.rawValue, WatchMetricKindKey.oxygenSaturation)

        // A warned metric without a watch card, and cards without warnings.
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

    func testBloodOxygenCardGetsItsGlyphAndBadge() {
        XCTAssertEqual(
            WatchMetricWarnings.glyphLabel(forCardKind: WatchMetricKindKey.oxygenSaturation, in: warnings, isFolded: unfolded),
            "Low Blood Oxygen"
        )
        XCTAssertNil(WatchMetricWarnings.glyphLabel(forCardKind: WatchMetricKindKey.oxygenSaturation, in: warnings) { _ in true })

        let badges = WatchMetricWarnings.heroBadges(
            cardKinds: [WatchMetricKindKey.heartRate, WatchMetricKindKey.oxygenSaturation, WatchMetricKindKey.wristTemperature],
            warnings: warnings,
            showsOnHero: true,
            isFolded: unfolded
        )
        XCTAssertEqual(
            badges.map(\.cardKind),
            [WatchMetricKindKey.heartRate, WatchMetricKindKey.oxygenSaturation, WatchMetricKindKey.wristTemperature]
        )
        XCTAssertEqual(badges[1].titles, ["Low Blood Oxygen"])
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
        XCTAssertEqual(WatchMetricWarnings.title(for: .lowBloodOxygen), "Low Blood Oxygen")
        XCTAssertEqual(WatchMetricWarnings.title(for: .highWristTemperature), "High Skin Temperature")
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
    }

    /// The phone's Blood Oxygen copy, the threshold a whole percent; the
    /// temperature unit plays no part. High Respiratory Rate has none.
    func testBloodOxygenSentenceIsThePhonesCopy() {
        let time = start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))

        for usesFahrenheit in [false, true] {
            XCTAssertEqual(
                WatchMetricWarnings.sentence(for: warning(.lowBloodOxygen, threshold: 90), kind: .lowBloodOxygen, usesFahrenheit: usesFahrenheit),
                "Your blood oxygen fell below 90% starting at \(time)."
            )
        }
        XCTAssertNil(WatchMetricWarnings.sentence(for: warning(.highRespiratoryRate), kind: .highRespiratoryRate, usesFahrenheit: false))
    }

    // MARK: - Shown: the phone's warnings and the watch's own

    private let calendar = Calendar.bodyGregorian

    /// `hour`:`minute`:`second` on a fixed day, in the test machine's own time
    /// zone; fold keys are built by `MetricWarningDayKey` to match.
    private func today(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: Date(timeIntervalSinceReferenceDate: 812_800_000))!
    }

    private var now: Date { today(14) }

    private var workout: WatchWorkoutSpan { WatchWorkoutSpan(start: today(10), end: today(11)) }

    private func pushed(
        _ kind: MetricWarningKind,
        at startDate: Date,
        isFolded: Bool = false,
        foldChangedAt: Date? = nil
    ) -> WatchMetricWarning {
        WatchMetricWarning(
            kind: kind.rawValue,
            startDate: startDate,
            threshold: kind.defaultThreshold,
            foldKey: MetricWarningDayKey.foldKey(kind: kind, startDate: startDate, calendar: calendar),
            isFolded: isFolded,
            foldChangedAt: foldChangedAt
        )
    }

    private func check(_ kind: MetricWarningKind, at startDate: Date, threshold: Double? = nil) -> WatchWarningCheck {
        WatchWarningCheck(
            kind: kind.rawValue,
            checkedAt: now,
            threshold: threshold ?? kind.defaultThreshold,
            episode: WatchWarningCheck.Episode(
                startDate: startDate,
                endDate: startDate.addingTimeInterval(10 * 60),
                extremeValue: kind.isAbove ? kind.defaultThreshold + 10 : kind.defaultThreshold - 4
            )
        )
    }

    /// The phone's settings: every watch card kind on, at its default limit
    /// unless `thresholds` names another.
    private func phoneSettings(
        enabled: [MetricWarningKind] = [.lowHeartRate, .highHeartRate, .lowBloodOxygen, .highWristTemperature],
        thresholds: [MetricWarningKind: Double] = [:]
    ) -> WatchWarningSettings {
        let kinds: [MetricWarningKind] = [.lowHeartRate, .highHeartRate, .lowBloodOxygen, .highWristTemperature]
        return WatchWarningSettings(
            thresholds: Dictionary(uniqueKeysWithValues: kinds.map { ($0.rawValue, thresholds[$0] ?? $0.defaultThreshold) }),
            enabledKinds: enabled.map(\.rawValue),
            notifies: true,
            notifiedDays: [:]
        )
    }

    private func shown(
        pushed: [WatchMetricWarning] = [],
        checks: [WatchWarningCheck]? = nil,
        spans: [WatchWorkoutSpan]? = nil,
        settings: WatchWarningSettings?
    ) -> [WatchMetricWarning] {
        WatchMetricWarnings.shown(
            pushed: pushed,
            checks: checks,
            workoutSpans: spans,
            settings: settings,
            now: now,
            calendar: calendar
        )
    }

    func testWithoutChecksThePushedWarningsShow() {
        let warnings = [pushed(.lowHeartRate, at: today(3)), pushed(.highWristTemperature, at: today(4))]

        XCTAssertEqual(shown(pushed: warnings, settings: phoneSettings()), warnings)
        XCTAssertEqual(shown(pushed: warnings, checks: [], spans: [], settings: phoneSettings()), warnings)
    }

    /// An older phone sends no settings: only its own warnings show, still
    /// without a High Heart Rate one a workout covers.
    func testWithoutSettingsOnlyThePushedWarningsShow() {
        let low = pushed(.lowHeartRate, at: today(3))
        let high = pushed(.highHeartRate, at: today(10, 5))
        let checks = [check(.lowHeartRate, at: today(1)), check(.highWristTemperature, at: today(2))]

        XCTAssertEqual(shown(pushed: [low, high], checks: checks, settings: nil), [low, high])
        XCTAssertEqual(shown(pushed: [low, high], checks: checks, spans: [workout], settings: nil), [low])
    }

    func testAWarningOnlyTheWatchFoundShows() {
        let start = today(9, 30)

        let warnings = shown(
            checks: [check(.highHeartRate, at: start, threshold: 125)],
            settings: phoneSettings(thresholds: [.highHeartRate: 125])
        )

        XCTAssertEqual(warnings, [WatchMetricWarning(
            kind: "highHeartRate",
            startDate: start,
            threshold: 125,
            foldKey: MetricWarningDayKey.foldKey(kind: .highHeartRate, startDate: start, calendar: calendar),
            isFolded: false,
            foldChangedAt: nil
        )])
    }

    /// Per kind the earlier start wins, and a tie keeps the phone's warning
    /// with its own fold state.
    func testThePhonesEarlierWarningWins() {
        let phone = pushed(.lowHeartRate, at: today(2), isFolded: true, foldChangedAt: today(6))

        XCTAssertEqual(shown(pushed: [phone], checks: [check(.lowHeartRate, at: today(3))], settings: phoneSettings()), [phone])
        XCTAssertEqual(shown(pushed: [phone], checks: [check(.lowHeartRate, at: today(2))], settings: phoneSettings()), [phone])
    }

    /// The watch's earlier start wins and takes the fold state the phone
    /// published for the day's fold key.
    func testTheWatchsEarlierWarningWinsWithThePhonesFoldState() {
        let stamp = today(6)
        let phone = pushed(.lowHeartRate, at: today(3), isFolded: true, foldChangedAt: stamp)

        let warnings = shown(pushed: [phone], checks: [check(.lowHeartRate, at: today(1, 15))], settings: phoneSettings())

        XCTAssertEqual(warnings.map(\.startDate), [today(1, 15)])
        XCTAssertEqual(warnings.first?.foldKey, phone.foldKey)
        XCTAssertEqual(warnings.first?.isFolded, true)
        XCTAssertEqual(warnings.first?.foldChangedAt, stamp)
    }

    /// Each kind is decided on its own, so the union holds one per kind.
    func testTheUnionHoldsOneWarningPerKind() {
        let phoneLow = pushed(.lowHeartRate, at: today(2))

        let warnings = shown(
            pushed: [phoneLow],
            checks: [check(.lowHeartRate, at: today(4)), check(.highWristTemperature, at: today(5))],
            settings: phoneSettings()
        )

        XCTAssertEqual(warnings.map(\.kind), ["lowHeartRate", "highWristTemperature"])
        XCTAssertEqual(warnings.first, phoneLow)
    }

    /// A limit changed on the phone since the check, or one the phone hasn't
    /// resolved yet, sets the check aside until the next compute.
    func testACheckUnderAnotherLimitIsSetAside() {
        let checks = [check(.highHeartRate, at: today(9), threshold: 120)]
        var unresolved = phoneSettings()
        unresolved.thresholds[MetricWarningKind.highHeartRate.rawValue] = nil

        XCTAssertTrue(shown(checks: checks, settings: phoneSettings(thresholds: [.highHeartRate: 130])).isEmpty)
        XCTAssertTrue(shown(checks: checks, settings: unresolved).isEmpty)
    }

    func testAKindTurnedOffInWarningsIsSetAside() {
        let settings = phoneSettings(enabled: [.highHeartRate, .highWristTemperature])

        XCTAssertTrue(shown(checks: [check(.lowHeartRate, at: today(3))], settings: settings).isEmpty)
    }

    /// Yesterday's episode, or a check that found nothing, shows nothing.
    func testOnlyAnEpisodeStartingTodayShows() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today(23, 50))!
        var nothing = check(.lowHeartRate, at: today(3))
        nothing.episode = nil

        XCTAssertTrue(shown(checks: [check(.lowHeartRate, at: yesterday)], settings: phoneSettings()).isEmpty)
        XCTAssertTrue(shown(checks: [nothing], settings: phoneSettings()).isEmpty)
    }

    /// Respiratory Rate has no watch card, so its check never shows, even
    /// turned on at a matching limit.
    func testAKindWithoutAWatchCardIsSetAside() {
        var settings = phoneSettings()
        settings.enabledKinds.append(MetricWarningKind.highRespiratoryRate.rawValue)
        settings.thresholds[MetricWarningKind.highRespiratoryRate.rawValue] = MetricWarningKind.highRespiratoryRate.defaultThreshold

        XCTAssertTrue(shown(checks: [check(.highRespiratoryRate, at: today(4))], settings: settings).isEmpty)
    }

    /// Blood Oxygen has a watch card, so the watch's own Low Blood Oxygen
    /// check shows under the phone's limit, and not once the phone turns the
    /// kind off or moves the limit.
    func testTheWatchsBloodOxygenCheckShows() {
        let start = today(4, 20)
        let oxygen = check(.lowBloodOxygen, at: start)

        XCTAssertEqual(shown(checks: [oxygen], settings: phoneSettings()), [WatchMetricWarning(
            kind: "lowBloodOxygen",
            startDate: start,
            threshold: 90,
            foldKey: MetricWarningDayKey.foldKey(kind: .lowBloodOxygen, startDate: start, calendar: calendar),
            isFolded: false,
            foldChangedAt: nil
        )])
        XCTAssertTrue(shown(checks: [oxygen], settings: phoneSettings(enabled: [.lowHeartRate, .highHeartRate])).isEmpty)
        XCTAssertTrue(shown(checks: [oxygen], settings: phoneSettings(thresholds: [.lowBloodOxygen: 88])).isEmpty)
    }

    /// A High Heart Rate warning starting inside a workout or the 30 minutes
    /// after it is left out, whichever device found it; both ends count.
    func testAWorkoutHidesHighHeartRateThroughItsRecoveryGrace() {
        let settings = phoneSettings()

        for start in [today(10), today(10, 40), today(11), today(11, 30)] {
            XCTAssertTrue(shown(pushed: [pushed(.highHeartRate, at: start)], spans: [workout], settings: settings).isEmpty, "phone, \(start)")
            XCTAssertTrue(shown(checks: [check(.highHeartRate, at: start)], spans: [workout], settings: settings).isEmpty, "watch, \(start)")
        }
        for start in [today(9, 59, 59), today(11, 30, 1)] {
            XCTAssertEqual(shown(pushed: [pushed(.highHeartRate, at: start)], spans: [workout], settings: settings).map(\.startDate), [start])
            XCTAssertEqual(shown(checks: [check(.highHeartRate, at: start)], spans: [workout], settings: settings).map(\.startDate), [start])
        }
    }

    /// Only High Heart Rate leaves workouts out.
    func testAWorkoutKeepsLowHeartRate() {
        let phone = pushed(.lowHeartRate, at: today(10, 30))

        XCTAssertEqual(shown(pushed: [phone], spans: [workout], settings: phoneSettings()), [phone])
        XCTAssertEqual(
            shown(checks: [check(.lowHeartRate, at: today(10, 15))], spans: [workout], settings: phoneSettings()).map(\.startDate),
            [today(10, 15)]
        )
    }

    /// The phone's warning started during the workout and the watch found a
    /// later episode after it: that one shows, with the fold state the phone
    /// published for the day.
    func testALaterWatchEpisodeStandsInForAPhoneWarningAWorkoutHides() {
        let stamp = today(12)
        let phone = pushed(.highHeartRate, at: today(10, 20), isFolded: true, foldChangedAt: stamp)

        let warnings = shown(pushed: [phone], checks: [check(.highHeartRate, at: today(13))], spans: [workout], settings: phoneSettings())

        XCTAssertEqual(warnings.map(\.startDate), [today(13)])
        XCTAssertEqual(warnings.first?.foldKey, phone.foldKey)
        XCTAssertEqual(warnings.first?.isFolded, true)
        XCTAssertEqual(warnings.first?.foldChangedAt, stamp)
    }

    // MARK: - Fold resend list

    /// Every fold key once, the phone's warning first, with the checks under
    /// the phone's settings but no workout left out: the phone's High Heart
    /// Rate inside the workout stays, though `shown` hides it.
    func testTheFoldResendListHoldsEveryFoldKeyOnce() {
        let phoneHigh = pushed(.highHeartRate, at: today(10, 20), isFolded: true, foldChangedAt: today(12))
        let checks = [
            check(.highHeartRate, at: today(9)),
            check(.lowHeartRate, at: today(3)),
            check(.highWristTemperature, at: today(4), threshold: 37)
        ]

        let list = WatchMetricWarnings.foldResendList(
            pushed: [phoneHigh],
            checks: checks,
            settings: phoneSettings(),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(list.first, phoneHigh)
        XCTAssertEqual(list.map(\.foldKey), [
            phoneHigh.foldKey,
            MetricWarningDayKey.foldKey(kind: .lowHeartRate, startDate: today(3), calendar: calendar)
        ])
        XCTAssertFalse(shown(pushed: [phoneHigh], spans: [workout], settings: phoneSettings()).contains(phoneHigh))
    }

    func testWithoutSettingsTheFoldResendListIsThePushedWarnings() {
        let warnings = [pushed(.highHeartRate, at: today(10, 20)), pushed(.lowHeartRate, at: today(3))]

        XCTAssertEqual(
            WatchMetricWarnings.foldResendList(pushed: warnings, checks: [check(.highWristTemperature, at: today(4))], settings: nil, now: now, calendar: calendar),
            warnings
        )
    }
}
