//
//  BodyCompanionPublisherTests.swift
//  BodyTests
//
//  The watch publish's epoch gate (H7), the republish debounce, and the widget
//  save's independence from the watch send. The build runs off-actor, so a Clear
//  Cache can land between the main-actor capture and the hop back; the send
//  must lose that race rather than ship pre-clear metrics onto wiped state.
//

import XCTest
@testable import Body

@MainActor
final class BodyCompanionPublisherTests: XCTestCase {
    private static func makeSharedInput() -> BodyCompanionPublishInput.Shared {
        BodyCompanionPublishInput.Shared(
            trends: .empty,
            summary: .empty,
            temperatureUnitPreference: .celsius,
            energyUnitPreference: .kilocalories,
            idealSleepDuration: 8 * 60 * 60,
            showSleepScore: true
        )
    }

    private func makeInput(
        epoch: Int,
        homeHeroRaw: String = BodyStarMetric.readiness.rawValue,
        shared: BodyCompanionPublishInput.Shared? = nil,
        now: Date = Date(),
        lastRefreshDate: Date? = nil,
        permissionSelection: BodyHealthPermissionSelection = .defaultValue,
        metricPullDates: [String: Date] = [:],
        workoutColorPalette: BodyWorkoutColorPalette = .builtIn,
        metricWarningsOnHero: Bool = true,
        dismissedMetricWarningsRaw: String = "",
        metricWarningFoldDates: [String: Date] = [:],
        metricWarningThresholdsRaw: String = "",
        warningMaxHeartRate: Double?? = nil,
        metricWarningNotificationsEnabled: Bool = false,
        metricWarningNotificationLedgerRaw: String = ""
    ) -> BodyCompanionPublishInput {
        BodyCompanionPublishInput(
            shared: shared ?? Self.makeSharedInput(),
            epoch: epoch,
            lastRefreshDate: lastRefreshDate,
            permissionSelection: permissionSelection,
            permissionRawValue: "",
            now: now,
            workoutCalendar: .bodyGregorian,
            monthSnapshots: [:],
            captureSequence: 1,
            // `nil` keeps the seed (and its time-zone map and zlib pass) out of
            // this test: the gate under test sits after the build either way.
            dataThrough: nil,
            readinessComputeDate: nil,
            trainingLoadComputeDate: nil,
            workoutMinutesDataAsOf: .distantPast,
            metricPullDates: metricPullDates,
            trainingLoadStartDay: nil,
            trainingLoadDailyLoads: nil,
            trainingLoadDataThrough: nil,
            trainingLoadEffortHints: nil,
            expectedSourceIDsByKind: [:],
            followsSystemUnits: true,
            selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue,
            showsSubMinuteAwakeStages: false,
            showsLeadingTrailingAwakeStages: false,
            readinessHeroShowsLevel: true,
            showsSleepDebt: false,
            homeHeroRaw: homeHeroRaw,
            dayRingShowsCaption: false,
            metricWarningSelectionRaw: BodyMetricWarningSelection.defaultRawValue,
            metricWarningsOnHero: metricWarningsOnHero,
            dismissedMetricWarningsRaw: dismissedMetricWarningsRaw,
            metricWarningFoldDates: metricWarningFoldDates,
            metricWarningThresholdsRaw: metricWarningThresholdsRaw,
            warningMaxHeartRate: warningMaxHeartRate,
            metricWarningNotificationsEnabled: metricWarningNotificationsEnabled,
            metricWarningNotificationLedgerRaw: metricWarningNotificationLedgerRaw,
            workoutColorPalette: workoutColorPalette,
            healthDataSourceSelectionRaw: "",
            customHealthSourceGroupsRaw: nil,
            combinesByName: false
        )
    }

    func testCurrentEpochSendsTheBuiltSnapshot() async {
        let sent = expectation(description: "sent")
        let publisher = BodyCompanionPublisher(send: { _, _, _, _, _ in sent.fulfill() })

        publisher.publishWatchSnapshot(makeInput(epoch: 3), isEpochCurrent: { $0 == 3 })

        await fulfillment(of: [sent], timeout: 5)
    }

    func testHomeHeroChoiceRidesTheWatchSnapshot() async {
        // The watch draws the hero picked in the phone's Settings, and only the Day
        // Ring pays for the workout list.
        for (raw, carriesWorkouts) in [(BodyStarMetric.dayRing.rawValue, true), (BodyStarMetric.readiness.rawValue, false)] {
            let sent = expectation(description: "sent \(raw)")
            let publisher = BodyCompanionPublisher(send: { snapshot, _, _, _, _ in
                XCTAssertEqual(snapshot.homeHero, raw)
                XCTAssertEqual(snapshot.dayRingShowsCaption, false)
                XCTAssertEqual(snapshot.dayRingWorkouts != nil, carriesWorkouts)
                sent.fulfill()
            })

            publisher.publishWatchSnapshot(makeInput(epoch: 3, homeHeroRaw: raw), isEpochCurrent: { $0 == 3 })

            await fulfillment(of: [sent], timeout: 5)
        }
    }

    /// The Stress page's "Last 8 hours" is built from the captured LIVE
    /// trends (only they carry the intraday day samples), stamped with the
    /// Stress card's own watermark, and only while Heart is on. The workout
    /// colors ride along in their raw form, empty without Body Pro.
    func testStressTimelineAndWorkoutColorsRideTheWatchSnapshot() async throws {
        let calendar = Calendar.bodyGregorian
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let today = calendar.startOfDay(for: now)
        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = (1...20).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map {
                StressDaySummary(date: $0, averageScore: 30, scoredWindowCount: 40, quietHRMedian: 60)
            }
        }
        .sorted { $0.date < $1.date }
        // 02:00 to 10:00, two readings in every window.
        trends.heartRateDaySamples = HealthTrendSeries(points: (8..<40).flatMap { index -> [HealthTrendDataPoint] in
            let windowStart = today.addingTimeInterval(Double(index) * 900)
            return [
                HealthTrendDataPoint(date: windowStart.addingTimeInterval(60), value: 72),
                HealthTrendDataPoint(date: windowStart.addingTimeInterval(420), value: 72)
            ]
        })
        let shared = BodyCompanionPublishInput.Shared(
            trends: trends,
            summary: .empty,
            temperatureUnitPreference: .celsius,
            energyUnitPreference: .kilocalories,
            idealSleepDuration: 8 * 60 * 60,
            showSleepScore: true
        )
        let refreshed = now.addingTimeInterval(-900)
        let pulled = now.addingTimeInterval(-300)
        let expected = WatchStressTimelineBuilder.make(
            dashboard: HealthDashboardSnapshot(summary: .empty, trends: trends),
            workouts: [],
            now: now,
            calendar: calendar,
            computedAt: pulled
        )
        XCTAssertNotNil(expected)

        let cases: [(name: String, permission: BodyHealthPermissionSelection, palette: BodyWorkoutColorPalette, timeline: WatchStressTimeline?, overrides: String)] = [
            ("built-in colors", .defaultValue, .builtIn, expected, ""),
            ("Body Pro colors", .defaultValue, BodyWorkoutColorPalette(rawOverrides: "running:12AB34", isProUnlocked: true), expected, "running:12AB34"),
            ("lapsed Body Pro", .defaultValue, BodyWorkoutColorPalette(rawOverrides: "running:12AB34", isProUnlocked: false), expected, ""),
            ("Heart off", BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false), .builtIn, nil, "")
        ]
        for testCase in cases {
            let sent = expectation(description: testCase.name)
            let publisher = BodyCompanionPublisher(send: { snapshot, _, _, _, _ in
                XCTAssertEqual(snapshot.stressTimeline, testCase.timeline, testCase.name)
                XCTAssertEqual(snapshot.workoutColorOverrides, testCase.overrides, testCase.name)
                if testCase.timeline != nil {
                    XCTAssertEqual(
                        snapshot.metric(forKind: WatchMetricKindKey.stress)?.computedAt,
                        snapshot.stressTimeline?.computedAt,
                        "\(testCase.name): the card and its timeline share one watermark"
                    )
                }
                sent.fulfill()
            })

            publisher.publishWatchSnapshot(
                makeInput(
                    epoch: 3,
                    shared: shared,
                    now: now,
                    lastRefreshDate: refreshed,
                    permissionSelection: testCase.permission,
                    metricPullDates: [WatchMetricKindKey.stress: pulled],
                    workoutColorPalette: testCase.palette
                ),
                isEpochCurrent: { $0 == 3 }
            )

            await fulfillment(of: [sent], timeout: 5)
        }
    }

    func testStaleEpochNeverSends() async {
        let sent = expectation(description: "sent")
        sent.isInverted = true
        let publisher = BodyCompanionPublisher(send: { _, _, _, _, _ in sent.fulfill() })

        // A Clear Cache bumped the epoch while the build was on the persist
        // queue, so the captured epoch no longer matches.
        publisher.publishWatchSnapshot(makeInput(epoch: 3), isEpochCurrent: { $0 == 4 })

        await fulfillment(of: [sent], timeout: 2)
    }

    func testScheduleRepublishRunsOnlyTheLastRebuildOfABurst() async {
        // A held stepper fires one `onChange` per tick; each rebuild encodes both
        // snapshots and reloads the widget timelines, so all but the last has to
        // be cancelled inside the debounce window.
        let publisher = BodyCompanionPublisher(send: { _, _, _, _, _ in })
        let first = expectation(description: "first")
        first.isInverted = true
        let second = expectation(description: "second")

        publisher.scheduleRepublish { first.fulfill() }
        publisher.scheduleRepublish { second.fulfill() }

        await fulfillment(of: [first, second], timeout: 2)
    }

    func testWidgetSaveNeverReachesTheWatchSend() async {
        // `saveHealthWidgetSnapshot` is called on its own from several refresh
        // paths; it writes the App Group file and nothing else. A send from it
        // would ship an unsequenced snapshot the watch would merge out of order.
        let sent = expectation(description: "sent")
        sent.isInverted = true
        let publisher = BodyCompanionPublisher(send: { _, _, _, _, _ in sent.fulfill() })

        publisher.saveWidgetSnapshot(
            BodyCompanionPublishInput.Widget(
                shared: Self.makeSharedInput(),
                weightUnitPreference: .kilograms,
                primarySourceNames: [:]
            )
        )

        await fulfillment(of: [sent], timeout: 2)
    }

    // MARK: - Watch metric warnings

    /// 2026-06-20 10:00, the publish time every warning test below runs at.
    nonisolated private static let warningNow = Calendar.bodyGregorian.date(
        from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)
    )!

    /// Both watch cards that can carry a warning: Heart Rate and Skin Temp.
    nonisolated private static let warningCardKinds: Set<String> = [
        WatchMetricKindKey.heartRate,
        WatchMetricKindKey.wristTemperature
    ]

    /// An episode of `kind` starting at `hour`:`minute` on `dayOffset` days
    /// from `warningNow`'s day.
    nonisolated private static func warningEvent(
        _ kind: MetricWarningKind,
        hour: Int,
        minute: Int = 0,
        dayOffset: Int = 0,
        threshold: Double? = nil
    ) -> MetricWarningEvent {
        let calendar = Calendar.bodyGregorian
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: warningNow))!
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return MetricWarningEvent(
            kind: kind,
            startDate: start,
            endDate: start.addingTimeInterval(15 * 60),
            extremeValue: 0,
            sampleCount: 3,
            threshold: threshold
        )
    }

    /// Every kind detected today, listed out of kind order so the test sees the
    /// publisher put them back in it.
    nonisolated private static func summaryWithEveryWarningToday() -> HealthSummarySnapshot {
        var summary = HealthSummarySnapshot.empty
        summary.metricWarnings = [
            warningEvent(.highWristTemperature, hour: 6, threshold: 37.2),
            warningEvent(.highRespiratoryRate, hour: 5),
            warningEvent(.highHeartRate, hour: 8, minute: 5, threshold: 120),
            warningEvent(.lowBloodOxygen, hour: 4),
            warningEvent(.lowHeartRate, hour: 3, minute: 10, threshold: 40)
        ]
        return summary
    }

    nonisolated private static func watchWarnings(
        summary: HealthSummarySnapshot = BodyCompanionPublisherTests.summaryWithEveryWarningToday(),
        selectionRaw: String = BodyMetricWarningSelection.defaultRawValue,
        dismissedRaw: String = "",
        foldDates: [String: Date] = [:],
        cardKinds: Set<String> = BodyCompanionPublisherTests.warningCardKinds
    ) -> [WatchMetricWarning]? {
        BodyCompanionPublisher.watchMetricWarnings(
            summary: summary,
            selectionRaw: selectionRaw,
            dismissedRaw: dismissedRaw,
            foldDates: foldDates,
            cardKinds: cardKinds,
            now: warningNow
        )
    }

    /// Today's Low and High Heart Rate and High Skin Temperature ship in kind
    /// order with the phone's fold key, their own threshold and start; Blood
    /// Oxygen and Respiratory Rate have no watch card, so they never do.
    func testWatchWarningsShipTodaysCardedKindsInKindOrder() throws {
        let warnings = try XCTUnwrap(Self.watchWarnings())

        XCTAssertEqual(warnings.map(\.kind), ["lowHeartRate", "highHeartRate", "highWristTemperature"])
        XCTAssertEqual(
            warnings.map(\.foldKey),
            ["lowHeartRate@2026-06-20", "highHeartRate@2026-06-20", "highWristTemperature@2026-06-20"]
        )
        XCTAssertEqual(warnings.map(\.threshold), [40, 120, 37.2])
        XCTAssertEqual(
            warnings.map(\.startDate),
            [
                Self.warningEvent(.lowHeartRate, hour: 3, minute: 10).startDate,
                Self.warningEvent(.highHeartRate, hour: 8, minute: 5).startDate,
                Self.warningEvent(.highWristTemperature, hour: 6).startDate
            ]
        )
        XCTAssertEqual(warnings.map(\.isFolded), [false, false, false])
        XCTAssertEqual(warnings.map(\.foldChangedAt), [nil, nil, nil])
        // The key is the phone's one fold key builder, verbatim.
        let summary = Self.summaryWithEveryWarningToday()
        XCTAssertEqual(
            warnings.first?.foldKey,
            BodyDismissedMetricWarnings.entryKey(for: try XCTUnwrap(summary.warning(.lowHeartRate)))
        )
    }

    /// The watch drops a warning after midnight anyway, so a summary still
    /// holding yesterday's episode doesn't ship it.
    func testWatchWarningsLeaveOutEpisodesFromAnotherDay() throws {
        var summary = HealthSummarySnapshot.empty
        summary.metricWarnings = [
            Self.warningEvent(.lowHeartRate, hour: 23, dayOffset: -1),
            Self.warningEvent(.highHeartRate, hour: 9),
            Self.warningEvent(.highWristTemperature, hour: 6, dayOffset: -1)
        ]

        let warnings = try XCTUnwrap(Self.watchWarnings(summary: summary))

        XCTAssertEqual(warnings.map(\.kind), ["highHeartRate"])
    }

    /// Only the kinds turned on in the Warnings selection ship; with every kind
    /// off nothing does.
    func testWatchWarningsFollowTheWarningsSelection() throws {
        let selection = BodyMetricWarningSelection(enabledKinds: [.highHeartRate, .lowBloodOxygen])
        let warnings = try XCTUnwrap(Self.watchWarnings(selectionRaw: selection.rawValue))

        XCTAssertEqual(warnings.map(\.kind), ["highHeartRate"])
        XCTAssertNil(Self.watchWarnings(selectionRaw: BodyMetricWarningSelection(enabledKinds: []).rawValue))
    }

    /// A warning ships only with its card: a card the builder left out (its
    /// permission off, say) takes its warnings with it.
    func testWatchWarningsShipOnlyForCardsInTheSnapshot() throws {
        let heartOnly = try XCTUnwrap(Self.watchWarnings(cardKinds: [WatchMetricKindKey.heartRate]))
        XCTAssertEqual(heartOnly.map(\.kind), ["lowHeartRate", "highHeartRate"])

        let skinOnly = try XCTUnwrap(Self.watchWarnings(cardKinds: [WatchMetricKindKey.wristTemperature, WatchMetricKindKey.stress]))
        XCTAssertEqual(skinOnly.map(\.kind), ["highWristTemperature"])

        XCTAssertNil(Self.watchWarnings(cardKinds: [WatchMetricKindKey.stress, WatchMetricKindKey.sleep]))
    }

    /// The phone's fold state and its stamps ride with each warning; other
    /// days' and Body Radar's entries change nothing.
    func testWatchWarningsCarryTheFoldStateAndItsStamp() throws {
        let stamp = Self.warningNow.addingTimeInterval(-600)
        let unfoldStamp = Self.warningNow.addingTimeInterval(-60)
        let warnings = try XCTUnwrap(Self.watchWarnings(
            dismissedRaw: "bodyRadar@2026-06-20,highHeartRate@2026-06-20,lowHeartRate@2026-06-19",
            foldDates: [
                "highHeartRate@2026-06-20": stamp,
                // An unfold is stamped too, and its entry is absent from the set.
                "highWristTemperature@2026-06-20": unfoldStamp,
                "lowHeartRate@2026-06-19": stamp
            ]
        ))

        XCTAssertEqual(warnings.map(\.isFolded), [false, true, false])
        XCTAssertEqual(warnings.map(\.foldChangedAt), [nil, stamp, unfoldStamp])
    }

    func testWatchWarningsAreNilWhenNothingQualifies() {
        XCTAssertNil(Self.watchWarnings(summary: .empty))

        var summary = HealthSummarySnapshot.empty
        summary.metricWarnings = [
            Self.warningEvent(.lowBloodOxygen, hour: 4),
            Self.warningEvent(.highRespiratoryRate, hour: 5),
            Self.warningEvent(.lowHeartRate, hour: 3, dayOffset: -1)
        ]
        XCTAssertNil(Self.watchWarnings(summary: summary))
    }

    /// The publish puts the warnings and the Show on Home Hero switch on the
    /// snapshot it sends, filtered by the cards the builder made: with Heart
    /// off there's no Heart Rate card, so only Skin Temp's warning ships.
    func testWarningsAndTheHeroSwitchRideTheWatchSnapshot() async throws {
        let shared = BodyCompanionPublishInput.Shared(
            trends: .empty,
            summary: Self.summaryWithEveryWarningToday(),
            temperatureUnitPreference: .celsius,
            energyUnitPreference: .kilocalories,
            idealSleepDuration: 8 * 60 * 60,
            showSleepScore: true
        )
        let stamp = Self.warningNow.addingTimeInterval(-120)
        let cases: [(name: String, permission: BodyHealthPermissionSelection, onHero: Bool, kinds: [String])] = [
            ("every permission", .defaultValue, false, ["lowHeartRate", "highHeartRate", "highWristTemperature"]),
            ("Heart off", BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false), true, ["highWristTemperature"])
        ]
        for testCase in cases {
            let sent = expectation(description: testCase.name)
            let publisher = BodyCompanionPublisher(send: { snapshot, _, _, _, _ in
                XCTAssertEqual(snapshot.heroShowsWarnings, testCase.onHero, testCase.name)
                XCTAssertEqual(snapshot.metricWarnings?.map(\.kind), testCase.kinds, testCase.name)
                let skinTemp = snapshot.metricWarnings?.last
                XCTAssertEqual(skinTemp?.isFolded, true, testCase.name)
                XCTAssertEqual(skinTemp?.foldChangedAt, stamp, testCase.name)
                sent.fulfill()
            })

            publisher.publishWatchSnapshot(
                makeInput(
                    epoch: 3,
                    shared: shared,
                    now: Self.warningNow,
                    permissionSelection: testCase.permission,
                    metricWarningsOnHero: testCase.onHero,
                    dismissedMetricWarningsRaw: "highWristTemperature@2026-06-20",
                    metricWarningFoldDates: ["highWristTemperature@2026-06-20": stamp]
                ),
                isEpochCurrent: { $0 == 3 }
            )

            await fulfillment(of: [sent], timeout: 5)
        }
    }

    // MARK: - Watch warning settings

    nonisolated private static func warningSettings(
        selectionRaw: String = BodyMetricWarningSelection.defaultRawValue,
        thresholdsRaw: String = "",
        maxHeartRate: Double?? = 190,
        notificationsEnabled: Bool = true,
        ledgerRaw: String = ""
    ) -> WatchWarningSettings {
        BodyCompanionPublisher.watchWarningSettings(
            selectionRaw: selectionRaw,
            thresholdsRaw: thresholdsRaw,
            maxHeartRate: maxHeartRate,
            notificationsEnabled: notificationsEnabled,
            ledgerRaw: ledgerRaw
        )
    }

    /// A resolved max heart rate gives High Heart Rate its zone 3 default (70 %
    /// of 190 is 133 bpm); resolved without a birth date it is the 120 bpm
    /// fallback.
    func testWatchWarningSettingsResolveTheHighHeartRateDefault() {
        XCTAssertEqual(
            Self.warningSettings(maxHeartRate: 190).thresholds,
            ["lowHeartRate": 40, "highHeartRate": 133, "highWristTemperature": 38]
        )
        XCTAssertEqual(Self.warningSettings(maxHeartRate: .some(nil)).thresholds["highHeartRate"], 120)
    }

    /// Before anything resolved the birth date, High Heart Rate's default is
    /// unknown, so its limit is left out rather than sent as 120 bpm. A user
    /// override needs no birth date and always ships.
    func testWatchWarningSettingsLeaveOutAnUnresolvedHighHeartRateDefault() {
        XCTAssertNil(Self.warningSettings(maxHeartRate: .none).thresholds["highHeartRate"])

        let override = BodyMetricWarningThresholds(overrides: [.highHeartRate: 150]).rawValue
        XCTAssertEqual(Self.warningSettings(thresholdsRaw: override, maxHeartRate: .none).thresholds["highHeartRate"], 150)
        XCTAssertEqual(Self.warningSettings(thresholdsRaw: override, maxHeartRate: 190).thresholds["highHeartRate"], 150)
    }

    /// Low Heart Rate and High Skin Temperature never wait for the birth date:
    /// their defaults (40 bpm, 38 °C) or the user's overrides ship whatever
    /// the max heart rate's state. A kind without a watch card never ships.
    func testWatchWarningSettingsAlwaysCarryLowHeartRateAndSkinTemperature() {
        for maxHeartRate: Double?? in [.none, .some(nil), 190] {
            let thresholds = Self.warningSettings(maxHeartRate: maxHeartRate).thresholds
            XCTAssertEqual(thresholds["lowHeartRate"], 40)
            XCTAssertEqual(thresholds["highWristTemperature"], 38)
        }

        let overrides = BodyMetricWarningThresholds(
            overrides: [.lowHeartRate: 45, .highWristTemperature: 37.5, .lowBloodOxygen: 92]
        ).rawValue
        XCTAssertEqual(
            Self.warningSettings(thresholdsRaw: overrides, maxHeartRate: .none).thresholds,
            ["lowHeartRate": 45, "highWristTemperature": 37.5]
        )
    }

    /// The enabled kinds ship in kind order however the selection spells
    /// them, and only those with a watch card. The limits don't follow the
    /// selection.
    func testWatchWarningSettingsListTheEnabledCardKindsInKindOrder() {
        let reordered = Self.warningSettings(selectionRaw: "highWristTemperature,lowBloodOxygen,lowHeartRate")
        XCTAssertEqual(reordered.enabledKinds, ["lowHeartRate", "highWristTemperature"])
        XCTAssertEqual(reordered.thresholds.count, 3)

        XCTAssertEqual(Self.warningSettings().enabledKinds, ["lowHeartRate", "highHeartRate", "highWristTemperature"])
        XCTAssertEqual(Self.warningSettings(selectionRaw: "none").enabledKinds, [])
    }

    /// The notification switch rides along as is, and the notification ledger
    /// for the card kinds only, keyed by raw value.
    func testWatchWarningSettingsCarryTheNotificationSwitchAndLedger() {
        XCTAssertTrue(Self.warningSettings(notificationsEnabled: true).notifies)
        XCTAssertFalse(Self.warningSettings(notificationsEnabled: false).notifies)

        let ledgerRaw = #"{"highHeartRate":"2026-06-20","lowBloodOxygen":"2026-06-20","lowHeartRate":"2026-06-19"}"#
        XCTAssertEqual(
            Self.warningSettings(ledgerRaw: ledgerRaw).notifiedDays,
            ["highHeartRate": "2026-06-20", "lowHeartRate": "2026-06-19"]
        )
        XCTAssertEqual(Self.warningSettings(ledgerRaw: "").notifiedDays, [:])
    }

    /// The publish puts the warning settings on the snapshot it sends, the
    /// same whichever cards the builder made: the watch checks its own
    /// warnings under its own permissions.
    func testWarningSettingsRideTheWatchSnapshot() async {
        let expected = WatchWarningSettings(
            thresholds: ["lowHeartRate": 45, "highHeartRate": 133, "highWristTemperature": 38],
            enabledKinds: ["lowHeartRate", "highHeartRate", "highWristTemperature"],
            notifies: true,
            notifiedDays: ["highHeartRate": "2026-06-20"]
        )
        let cases: [(name: String, permission: BodyHealthPermissionSelection)] = [
            ("every permission", .defaultValue),
            ("Heart off", BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false))
        ]
        for testCase in cases {
            let sent = expectation(description: testCase.name)
            let publisher = BodyCompanionPublisher(send: { snapshot, _, _, _, _ in
                XCTAssertEqual(snapshot.warningSettings, expected, testCase.name)
                sent.fulfill()
            })

            publisher.publishWatchSnapshot(
                makeInput(
                    epoch: 3,
                    now: Self.warningNow,
                    permissionSelection: testCase.permission,
                    metricWarningThresholdsRaw: BodyMetricWarningThresholds(overrides: [.lowHeartRate: 45]).rawValue,
                    warningMaxHeartRate: 190,
                    metricWarningNotificationsEnabled: true,
                    metricWarningNotificationLedgerRaw: #"{"highHeartRate":"2026-06-20"}"#
                ),
                isEpochCurrent: { $0 == 3 }
            )

            await fulfillment(of: [sent], timeout: 5)
        }
    }
}
