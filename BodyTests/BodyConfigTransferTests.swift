import XCTest
@testable import Body

final class BodyConfigTransferTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    private func file(_ settings: [String: BodyConfigTransfer.Value]) -> BodyConfigTransfer.File {
        BodyConfigTransfer.File(
            format: BodyConfigTransfer.format, schemaVersion: BodyConfigTransfer.schemaVersion,
            exportedAt: Date(timeIntervalSince1970: 1_780_000_000), appVersion: "1.1.6", build: "4",
            settings: settings
        )
    }

    private func json(_ text: String) -> Data {
        Data(text.utf8)
    }

    func testRoundTripCopiesEveryAllowlistedValue() throws {
        let source = try makeDefaults()
        let sourceGroup = try makeDefaults()
        for entry in BodyConfigTransfer.entries {
            let store = entry.inAppGroup ? sourceGroup : source
            switch entry.type {
            case .bool: store.set(true, forKey: entry.key)
            case .int: store.set(450, forKey: entry.key)
            case .double: store.set(1.2, forKey: entry.key)
            case .string: store.set("value.\(entry.key)", forKey: entry.key)
            }
        }

        let data = try BodyConfigTransfer.export(defaults: source, groupDefaults: sourceGroup)
        let decoded = try BodyConfigTransfer.decode(data)
        XCTAssertEqual(decoded.settings.count, BodyConfigTransfer.entries.count)

        let target = try makeDefaults()
        let targetGroup = try makeDefaults()
        BodyConfigTransfer.write(decoded, defaults: target, groupDefaults: targetGroup)
        for entry in BodyConfigTransfer.entries {
            let expected = (entry.inAppGroup ? sourceGroup : source).object(forKey: entry.key) as? NSObject
            let actual = (entry.inAppGroup ? targetGroup : target).object(forKey: entry.key) as? NSObject
            XCTAssertEqual(actual, expected, entry.key)
        }
        // Workout colors live only in the App Group suite the widgets read.
        XCTAssertNil(target.object(forKey: BodyAppearancePreference.workoutColorOverridesKey))
    }

    func testExportLeavesOutUnsetAndExcludedKeys() throws {
        let source = try makeDefaults()
        let sourceGroup = try makeDefaults()
        source.set("Ziheng", forKey: BodyAppearancePreference.profileNameKey)
        source.set("heart,steps", forKey: BodyAppearancePreference.healthPermissionSelectionKey)
        source.set("1.1.6", forKey: BodyAppearancePreference.onboardingCompletedVersionKey)
        source.set(true, forKey: BodyAppearancePreference.summaryCardStressMigratedKey)
        sourceGroup.set(true, forKey: "bodyProUnlocked")
        source.set(420, forKey: BodyAppearancePreference.sleepDurationGoalMinutesKey)

        let decoded = try BodyConfigTransfer.decode(
            BodyConfigTransfer.export(defaults: source, groupDefaults: sourceGroup)
        )

        XCTAssertEqual(decoded.settings, [BodyAppearancePreference.sleepDurationGoalMinutesKey: .int(420)])
        XCTAssertEqual(decoded.format, "body.config")
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testImportResetsMissingKeysAndIgnoresUnknownOnes() throws {
        let target = try makeDefaults()
        let targetGroup = try makeDefaults()
        target.set(false, forKey: BodyAppearancePreference.showSleepScoreKey)
        targetGroup.set("running:335BB0", forKey: BodyAppearancePreference.workoutColorOverridesKey)

        BodyConfigTransfer.write(
            file([BodyAppearancePreference.selectedThemeKey: .string("dark"), "unknownKey": .bool(true)]),
            defaults: target, groupDefaults: targetGroup
        )

        XCTAssertNil(target.object(forKey: BodyAppearancePreference.showSleepScoreKey))
        XCTAssertNil(targetGroup.object(forKey: BodyAppearancePreference.workoutColorOverridesKey))
        XCTAssertNil(target.object(forKey: "unknownKey"))
        XCTAssertEqual(target.string(forKey: BodyAppearancePreference.selectedThemeKey), "dark")
    }

    func testDecodeRejectsForeignNewerAndMistypedFiles() {
        let date = "2026-10-15T12:00:00Z"
        XCTAssertThrowsError(try BodyConfigTransfer.decode(json("not json"))) {
            XCTAssertEqual($0 as? BodyConfigTransfer.ImportError, .notAConfig)
        }
        XCTAssertThrowsError(try BodyConfigTransfer.decode(json(
            #"{"format":"other","schemaVersion":1,"exportedAt":"\#(date)","settings":{}}"#
        ))) {
            XCTAssertEqual($0 as? BodyConfigTransfer.ImportError, .notAConfig)
        }
        XCTAssertThrowsError(try BodyConfigTransfer.decode(json(
            #"{"format":"body.config","schemaVersion":2,"exportedAt":"\#(date)","settings":{}}"#
        ))) {
            XCTAssertEqual($0 as? BodyConfigTransfer.ImportError, .newerSchema)
        }
        XCTAssertThrowsError(try BodyConfigTransfer.decode(json(
            #"{"format":"body.config","schemaVersion":1,"exportedAt":"\#(date)","settings":{"sleepDurationGoalMinutes":"eight"}}"#
        ))) {
            XCTAssertEqual($0 as? BodyConfigTransfer.ImportError, .mismatchedValue("sleepDurationGoalMinutes"))
        }
        XCTAssertThrowsError(try BodyConfigTransfer.decode(json(
            #"{"format":"body.config","schemaVersion":1,"exportedAt":"\#(date)","settings":{"sleepDurationGoalMinutes":7.5}}"#
        )))
        XCTAssertThrowsError(try BodyConfigTransfer.decode(json(
            #"{"format":"body.config","schemaVersion":1,"exportedAt":"\#(date)","settings":{"showSleepScore":1}}"#
        )))
        // JSON writes a whole double without its fraction, so 1 still reads as 1.0.
        XCTAssertNoThrow(try BodyConfigTransfer.decode(json(
            #"{"format":"body.config","schemaVersion":1,"exportedAt":"\#(date)","settings":{"workoutEquivalentEmojiScale":1}}"#
        )))
    }

    func testImportMarksCardMigrationsDoneSoTheLayoutStaysExact() throws {
        let target = try makeDefaults()
        let cards = BodySummaryCardSelection(selectedCards: [.heartRate, .steps])

        BodyConfigTransfer.write(
            file([BodyAppearancePreference.summaryCardSelectionKey: .string(cards.rawValue)]),
            defaults: target, groupDefaults: try makeDefaults()
        )

        for key in BodyConfigTransfer.cardMigrationKeys {
            XCTAssertTrue(target.bool(forKey: key), key)
        }
        XCTAssertEqual(BodySummaryCardSelection.load(defaults: target).selectedCards, [.heartRate, .steps])
    }

    func testWriteReportsOnlyChangedKeys() throws {
        let target = try makeDefaults()
        target.set(480, forKey: BodyAppearancePreference.sleepDurationGoalMinutesKey)
        target.set("dark", forKey: BodyAppearancePreference.selectedThemeKey)
        target.set(true, forKey: BodyNotificationPreferences.stressKey)

        let changed = BodyConfigTransfer.write(
            file([
                BodyAppearancePreference.sleepDurationGoalMinutesKey: .int(420),
                BodyAppearancePreference.selectedThemeKey: .string("dark"),
                BodyNotificationPreferences.stressKey: .bool(false)
            ]),
            defaults: target, groupDefaults: try makeDefaults()
        )

        XCTAssertEqual(changed, [
            BodyAppearancePreference.sleepDurationGoalMinutesKey,
            BodyNotificationPreferences.stressKey
        ])
    }

    @MainActor
    func testStoreAdoptsImportedSourcesWithOneUserInitiatedRefresh() async throws {
        let defaults = try makeDefaults()
        let group = BodyCustomHealthSourceGroup.custom(name: "Rings", memberIdentityKeys: ["bundle=a|name=a", "bundle=b|name=b"])
        let selection = BodyHealthDataSourceSelection.defaultValue.settingDefault(option: group.option)
        selection.save(defaults: defaults)
        defaults.set(BodyCustomHealthSourceGroupStore.rawValue(from: [group]), forKey: BodyAppearancePreference.customHealthSourceGroupsKey)
        defaults.set(true, forKey: BodyAppearancePreference.combinesHealthDataSourcesByNameKey)

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: [.heart, .steps]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore()
        )
        let refreshed = expectation(description: "one corrective refresh")
        refreshed.assertForOverFulfill = true
        store.contextRefreshOverride = { intent in
            XCTAssertEqual(intent, .userInitiated)
            refreshed.fulfill()
        }

        await store.reloadHealthSourceConfiguration(defaults: defaults)
        await fulfillment(of: [refreshed], timeout: 3)
        store.contextRefreshOverride = nil

        XCTAssertEqual(store.customHealthSourceGroups, [group])
        XCTAssertEqual(store.healthDataSourceSelection, selection)
        XCTAssertTrue(store.combinesHealthDataSourcesByName)
    }
}
