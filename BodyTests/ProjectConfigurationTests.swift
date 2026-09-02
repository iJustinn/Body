//
//  ProjectConfigurationTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

final class ProjectConfigurationTests: XCTestCase {
    override func setUpWithError() throws {
        try BodyTestSupport.requireProjectRoot()
    }

    func testSettingsAboutTabsMatchCoinAboutSet() {
        XCTAssertEqual(
            BodySettingsAboutTab.allCases.map(\.title),
            [
                "How to Use",
                "Privacy",
                "Onboarding",
                "More",
                "Version"
            ]
        )
        XCTAssertEqual(
            BodySettingsAboutTab.allCases.filter(\.opensSheet).map(\.title),
            [
                "More"
            ]
        )
    }

    func testSettingsDataTabsExposePermissions() {
        XCTAssertEqual(BodySettingsDataTab.allCases.map(\.title), ["Source", "Permissions", "Data Refresh", "Cache"])
        XCTAssertEqual(BodySettingsDataTab.source.sheet, .source)
        XCTAssertEqual(BodySettingsDataTab.permissions.sheet, .permissions)
        XCTAssertEqual(BodySettingsDataTab.syncStatus.sheet, .syncStatus)
        XCTAssertEqual(BodySettingsDataTab.cache.sheet, .cache)
    }

    func testHomeBackgroundDefaultUsesBalancedBlueProfile() {
        XCTAssertEqual(BodyHomeBackground.rawValue(from: BodyHomeBackground.defaultColors), "30B5FF,0A85FF,0057D9")
        XCTAssertEqual(BodyHomeBackground.defaultSeparators[0], 0.33, accuracy: 0.0001)
        XCTAssertEqual(BodyHomeBackground.defaultSeparators[1], 0.67, accuracy: 0.0001)
        XCTAssertEqual(BodyHomeBackgroundProfile.appDefault.segmentSummary, "33% / 34% / 33%")
    }

    func testHomeBackgroundProfileStoreKeepsFixedDefaultAndCapsCustomProfiles() {
        let profiles = (0..<6).map { index in
            BodyHomeBackgroundProfile(
                id: "custom-\(index)",
                colorsRawValue: "30B5FF,0A85FF,0057D9",
                separatorsRawValue: "0.3300,0.6700"
            )
        }

        let rawValue = BodyHomeBackgroundProfileStore.rawValue(from: profiles)
        let customProfiles = BodyHomeBackgroundProfileStore.customProfiles(from: rawValue)
        let allProfiles = BodyHomeBackgroundProfileStore.allProfiles(from: rawValue)

        XCTAssertEqual(customProfiles.count, 4)
        XCTAssertEqual(allProfiles.count, 5)
        XCTAssertEqual(allProfiles.first?.id, BodyHomeBackgroundProfile.appDefaultID)
        XCTAssertFalse(customProfiles.contains { $0.id == BodyHomeBackgroundProfile.appDefaultID })
    }

    func testHomeBackgroundCustomProfileNamesArePersistedAndEditable() throws {
        let profile = BodyHomeBackgroundProfile.custom(
            name: "  Evening Blue  ",
            colors: BodyHomeBackground.defaultColors,
            separators: BodyHomeBackground.defaultSeparators
        )
        let rawValue = BodyHomeBackgroundProfileStore.rawValue(from: [profile])
        let decodedProfile = try XCTUnwrap(BodyHomeBackgroundProfileStore.customProfiles(from: rawValue).first)

        XCTAssertEqual(decodedProfile.displayName(defaultName: "Saved 1"), "Evening Blue")
        XCTAssertEqual(decodedProfile.renamed("  Ocean  ").displayName(defaultName: "Saved 1"), "Ocean")
        XCTAssertEqual(decodedProfile.renamed("   ").displayName(defaultName: "Saved 1"), "Saved 1")
    }

    func testHealthMetricChartXDomainComputesExpectedPadding() {
        let hour: TimeInterval = 60 * 60
        let day: TimeInterval = 24 * hour
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let endDate = startDate.addingTimeInterval(3 * day)
        let dates = [endDate, startDate]

        let standardMonthDomain = bodyHealthDetailChartXDomain(for: dates, selectedRange: .recentMonth)
        XCTAssertEqual(standardMonthDomain.lowerBound.timeIntervalSince(startDate), -2 * hour, accuracy: 0.001)
        XCTAssertEqual(standardMonthDomain.upperBound.timeIntervalSince(endDate), 7 * day * 0.55, accuracy: 0.001)

        let immersiveWeekDomain = bodyHealthDetailChartXDomain(for: dates, selectedRange: .recentWeek, immersive: true)
        XCTAssertEqual(immersiveWeekDomain.lowerBound.timeIntervalSince(startDate), -2 * hour, accuracy: 0.001)
        XCTAssertEqual(immersiveWeekDomain.upperBound.timeIntervalSince(endDate), 26 * hour, accuracy: 0.001)

        let immersivePairedWeekDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentWeek,
            immersive: true,
            immersivePairedBars: true
        )
        XCTAssertEqual(immersivePairedWeekDomain.lowerBound.timeIntervalSince(startDate), -12 * hour, accuracy: 0.001)
        XCTAssertEqual(immersivePairedWeekDomain.upperBound.timeIntervalSince(endDate), 12 * hour, accuracy: 0.001)

        // Immersive month charts keep a half-bucket (12h) leading nudge with a 28h trailing
        // padding.
        let immersiveMonthDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentMonth,
            immersive: true
        )
        XCTAssertEqual(immersiveMonthDomain.lowerBound.timeIntervalSince(startDate), -12 * hour, accuracy: 0.001)
        XCTAssertEqual(immersiveMonthDomain.upperBound.timeIntervalSince(endDate), 28 * hour, accuracy: 0.001)

        // Single-source six-month charts pin the first mark to the left wall (no leading
        // padding) with a 1.5-bucket trailing padding (9 days).
        let immersiveSixMonthDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentSixMonths,
            immersive: true
        )
        XCTAssertEqual(immersiveSixMonthDomain.lowerBound.timeIntervalSince(startDate), 0, accuracy: 0.001)
        XCTAssertEqual(immersiveSixMonthDomain.upperBound.timeIntervalSince(endDate), 9 * day, accuracy: 0.001)

        // Single-source year charts do the same: no leading padding, trailing 18 days.
        let immersiveYearDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentYear,
            immersive: true
        )
        XCTAssertEqual(immersiveYearDomain.lowerBound.timeIntervalSince(startDate), 0, accuracy: 0.001)
        XCTAssertEqual(immersiveYearDomain.upperBound.timeIntervalSince(endDate), 18 * day, accuracy: 0.001)

        // The two-source paired-bar comparison chart keeps symmetric padding.
        let pairedBarSixMonthDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentSixMonths,
            immersive: true,
            immersivePairedBars: true,
            pairedBarComparison: true
        )
        XCTAssertEqual(pairedBarSixMonthDomain.lowerBound.timeIntervalSince(startDate), -3 * day, accuracy: 0.001)
        XCTAssertEqual(pairedBarSixMonthDomain.upperBound.timeIntervalSince(endDate), 3 * day, accuracy: 0.001)

        // Line/range comparison charts (paired bars but not the bar variant) still bias left.
        let rangeComparisonSixMonthDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentSixMonths,
            immersive: true,
            immersivePairedBars: true
        )
        XCTAssertEqual(rangeComparisonSixMonthDomain.lowerBound.timeIntervalSince(startDate), 0, accuracy: 0.001)
        XCTAssertEqual(rangeComparisonSixMonthDomain.upperBound.timeIntervalSince(endDate), 9 * day, accuracy: 0.001)

        let emptyDateDomain = bodyHealthDetailChartXDomain(
            for: [],
            selectedRange: .recentWeek,
            immersive: true,
            immersivePairedBars: true
        )
        XCTAssertEqual(emptyDateDomain.upperBound.timeIntervalSince(emptyDateDomain.lowerBound), day, accuracy: 0.001)
    }

    func testAppWidgetAndWatchShareAppGroupEntitlement() throws {
        let appEntitlements = try BodyTestSupport.propertyList(at: "Body/Body.entitlements")
        let widgetEntitlements = try BodyTestSupport.propertyList(at: "BodyWidgetExtension.entitlements")
        let watchEntitlements = try BodyTestSupport.propertyList(at: "BodyWatch/BodyWatch.entitlements")
        let watchWidgetEntitlements = try BodyTestSupport.propertyList(at: "BodyWatchWidgetExtension/BodyWatchWidgetExtension.entitlements")

        XCTAssertEqual(
            appEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
        XCTAssertEqual(
            widgetEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
        XCTAssertEqual(
            watchEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
        XCTAssertEqual(
            watchWidgetEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
    }

    func testAppDeclaresHealthKitEntitlement() throws {
        let appEntitlements = try BodyTestSupport.propertyList(at: "Body/Body.entitlements")
        let watchEntitlements = try BodyTestSupport.propertyList(at: "BodyWatch/BodyWatch.entitlements")

        XCTAssertEqual(appEntitlements["com.apple.developer.healthkit"] as? Bool, true)
        // The watch app runs its own HR/HRV HealthKit queries on the live path.
        XCTAssertEqual(watchEntitlements["com.apple.developer.healthkit"] as? Bool, true)
    }

    func testPrivacyManifestsDeclareUserDefaultsAndNoTracking() throws {
        // Per-target expected categories: app + iOS widget + watch app declare both
        // UserDefaults and FileTimestamp access; the watch widget (no UserDefaults use)
        // declares FileTimestamp only.
        let expectedCategoriesByPath: [String: Set<String>] = [
            "Body/PrivacyInfo.xcprivacy": ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp"],
            "BodyWidgetExtension/PrivacyInfo.xcprivacy": ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp"],
            "BodyWatch/PrivacyInfo.xcprivacy": ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp"],
            "BodyWatchWidgetExtension/PrivacyInfo.xcprivacy": ["NSPrivacyAccessedAPICategoryFileTimestamp"],
        ]

        for (path, expectedCategories) in expectedCategoriesByPath {
            let manifest = try BodyTestSupport.propertyList(at: path)
            XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false, path)
            XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty, true, path)

            let accessedAPITypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]], path)
            let declaredCategories = Set(accessedAPITypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
            XCTAssertEqual(declaredCategories, expectedCategories, path)

            if expectedCategories.contains("NSPrivacyAccessedAPICategoryUserDefaults") {
                let userDefaultsDeclaration = accessedAPITypes.first {
                    $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
                }
                XCTAssertEqual(
                    userDefaultsDeclaration?["NSPrivacyAccessedAPITypeReasons"] as? [String],
                    ["CA92.1"],
                    path
                )
            }

            if expectedCategories.contains("NSPrivacyAccessedAPICategoryFileTimestamp") {
                let fileTimestampDeclaration = accessedAPITypes.first {
                    $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryFileTimestamp"
                }
                XCTAssertEqual(
                    fileTimestampDeclaration?["NSPrivacyAccessedAPITypeReasons"] as? [String],
                    ["C617.1"],
                    path
                )
            }
        }
    }

    func testProjectBuildSettingsMatchInitialReleasePlan() throws {
        let project = try BodyTestSupport.sourceText(at: "body.xcodeproj/project.pbxproj")

        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body.BodyWidgetExtension;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.BodyTests;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body.watchkitapp;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body.watchkitapp.WatchWidget;"))
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"BodyBlack BodyGray BodyPink BodyPurple BodyWhite\";"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSHealthShareUsageDescription"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSHealthUpdateUsageDescription"))
        // Every target that declares HealthKit read access (and carries the HealthKit
        // entitlement) must also declare NSHealthUpdateUsageDescription, or App Store
        // validation rejects the bundle. The watch app shipped Share without Update once.
        XCTAssertEqual(
            project.occurrenceCount(of: "INFOPLIST_KEY_NSHealthShareUsageDescription"),
            project.occurrenceCount(of: "INFOPLIST_KEY_NSHealthUpdateUsageDescription")
        )
        // The share card's Save button writes to the photo library; without this string
        // the add-only authorization prompt crashes the app. App target only (Debug +
        // Release) — the widget and watch never save.
        XCTAssertEqual(project.occurrenceCount(of: "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription"), 2)
        // The copy now covers video saves too, since the Save button can also write an
        // exported MP4 from the Your Video background.
        XCTAssertEqual(project.occurrenceCount(of: "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = \"Body saves the workout images and videos you create to your photo library.\";"), 2)
        XCTAssertTrue(project.contains("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;"))
        XCTAssertTrue(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 18.0;"))
        XCTAssertTrue(project.contains("TARGETED_DEVICE_FAMILY = \"1,2\";"))
        XCTAssertTrue(project.contains("SUPPORTS_MACCATALYST = NO;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";"))
        XCTAssertTrue(project.contains("MARKETING_VERSION = 1.1.0;"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 2;"))
        // All six targets (app, widget, tests, watch app, watch complications, watch tests)
        // × Debug/Release must move together on a version bump — `contains`
        // alone would pass with a stale target left behind.
        XCTAssertEqual(project.occurrenceCount(of: "MARKETING_VERSION = 1.1.0;"), 12)
        XCTAssertEqual(project.occurrenceCount(of: "CURRENT_PROJECT_VERSION = 2;"), 12)
        // Strict concurrency stays on project-wide (targeted for now; complete and
        // Swift 6 are separate migrations) so actor and Sendable annotations are checked.
        XCTAssertEqual(project.occurrenceCount(of: "SWIFT_STRICT_CONCURRENCY = targeted;"), 2)
        XCTAssertTrue(project.contains("VALIDATE_PRODUCT = YES;"))
    }

    func testWatchMetricKindKeysMatchIOSWidgetStyling() throws {
        let pairs: [(kind: String, widgetMetric: HealthWidgetMetric)] = [
            (WatchMetricKindKey.trainingLoad, .trainingLoad),
            (WatchMetricKindKey.readiness, .readiness),
            (WatchMetricKindKey.sleep, .sleep),
            (WatchMetricKindKey.heartRate, .heartRate),
            (WatchMetricKindKey.heartRateVariability, .heartRateVariability),
            (WatchMetricKindKey.restingHeartRate, .restingHeartRate),
            (WatchMetricKindKey.wristTemperature, .wristTemperature)
        ]

        XCTAssertEqual(pairs.map(\.kind), WatchMetricKindKey.displayOrder)

        for (kind, widgetMetric) in pairs {
            XCTAssertEqual(kind, widgetMetric.rawValue)
            XCTAssertEqual(WatchMetricKindKey.symbolName(forKind: kind), widgetMetric.symbolName, kind)

            let tint = WatchMetricKindKey.tint(forKind: kind)
            let components = UIColor(widgetMetric.tintColor).cgColor.components ?? []
            XCTAssertGreaterThanOrEqual(components.count, 3, kind)
            XCTAssertEqual(Double(components[0]), tint.red, accuracy: 0.001, kind)
            XCTAssertEqual(Double(components[1]), tint.green, accuracy: 0.001, kind)
            XCTAssertEqual(Double(components[2]), tint.blue, accuracy: 0.001, kind)
        }

        // Exercise Minutes rides the watch snapshot for the rectangular
        // complication only: it has no dashboard card, no detail page and no
        // ring, so it must stay out of `displayOrder` (which drives
        // `orderedMetrics` everywhere in the watch app UI). Its key still has
        // to match the iOS widget metric's raw value, because the phone-side
        // trend lookup keys off it.
        XCTAssertFalse(WatchMetricKindKey.displayOrder.contains(WatchMetricKindKey.exerciseMinutes))
        XCTAssertEqual(WatchMetricKindKey.exerciseMinutes, HealthWidgetMetric.exerciseMinutes.rawValue)

        // Weekly Workout Time is the kind that complication actually reads now
        // (summed workout durations); `exerciseMinutes` above survives only as
        // the fallback for a cached snapshot from an older phone build. It has
        // no `HealthWidgetMetric` counterpart at all, so it can never join the
        // `pairs` table above, and it must stay out of `displayOrder` for the
        // same reason: no dashboard card, no detail page, no ring.
        XCTAssertFalse(WatchMetricKindKey.displayOrder.contains(WatchMetricKindKey.workoutMinutes))
    }

    func testHealthKitUsageDescriptionListsRequestedHealthCategories() throws {
        let project = try BodyTestSupport.sourceText(at: "body.xcodeproj/project.pbxproj")
        let usageDescription = "Body reads workouts, workout routes, Activity Rings, sleep, heart rate, HRV, beat-to-beat heart rhythm data, blood oxygen, respiratory rate, body measurements, energy, exercise minutes, skin temperature, daylight, steps, cardio fitness, power, cadence, running form, swim strokes, distance, date of birth, and biological sex from Apple Health to power your dashboard, charts, and widgets."

        XCTAssertEqual(project.occurrenceCount(of: usageDescription), 2)
        XCTAssertFalse(project.contains("Body reads workout, sleep, heart, and body measurement data"))
    }

    func testTestPlanCoversCurrentBranchAndBodyProSurface() throws {
        let testPlan = try BodyTestSupport.sourceText(at: "TestPlan.md")

        XCTAssertTrue(testPlan.contains("branch `body-v1.1.0`"))
        XCTAssertFalse(testPlan.contains("branch `body-v1.0.2`"))
        XCTAssertFalse(testPlan.contains("branch `body-1.0.1`"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.12`"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.11`"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.10`"))
        XCTAssertTrue(testPlan.contains("app version 1.1.0 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 1.1.0 build 1)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.2 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 4)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 25)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 23)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 22)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 21)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 20)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 19)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 18)"))
        XCTAssertTrue(testPlan.contains("Settings › About › Onboarding"))
        // The first-run intro's automated and manual coverage.
        XCTAssertTrue(testPlan.contains("BodyIntroAnimationTests"))
        XCTAssertTrue(testPlan.contains("intro plays"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 17)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 16)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 15)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 14)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 17)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 16)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 15)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 1)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 1)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 21)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 19)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 18)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 17)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 16)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 15)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 1)"))
        XCTAssertTrue(testPlan.contains("sync status badge"))
        XCTAssertTrue(testPlan.contains("Energy by Activity"))
        XCTAssertTrue(testPlan.contains("Low Heart Rate"))
        XCTAssertTrue(testPlan.contains("High Heart Rate"))
        XCTAssertTrue(testPlan.contains("Low Blood Oxygen"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.9`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 1)"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.8`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 1)"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.9.7`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 1)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.6 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.6 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.6 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.6 build 1)"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.9.6`"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.9.5`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 1)"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.9.3`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 8"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 7"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 6"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 5"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 3"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 2"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 1"))
        XCTAssertFalse(testPlan.contains("app version 0.9.2 build 1"))
        XCTAssertFalse(testPlan.contains("app version 0.9.1 build 3"))
        XCTAssertFalse(testPlan.contains("app version 0.9.1 build 2"))
        XCTAssertFalse(testPlan.contains("app version 0.9.1 build 1"))
        XCTAssertFalse(testPlan.contains("app version 0.7.0 build 1"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.6.0`"))
        XCTAssertFalse(testPlan.contains("app version 0.6.0 build 2"))
        XCTAssertFalse(testPlan.contains("branch `codex/body-v0.3.0`"))
        XCTAssertFalse(testPlan.contains("branch `codex/body-v0.3.4`"))
        XCTAssertTrue(testPlan.contains("Body/Views/BodyProView.swift"))
        XCTAssertTrue(testPlan.contains("Body Pro entry navigation"))
        XCTAssertTrue(testPlan.contains("Body Pro icon flip"))
        XCTAssertFalse(testPlan.contains("version-card unlock"))
        XCTAssertFalse(testPlan.contains("creator-surprise icon sheet"))
    }

    func testAppIconAssetsIncludePrimaryAndAlternateOptions() throws {
        // Every shipping app icon is an Icon Composer (.icon) bundle at its target
        // root — primary AppIcon plus five color alternates, and the watch + widget.
        let iconBundles = [
            "Body/AppIcon.icon/icon.json",
            "Body/BodyBlack.icon/icon.json",
            "Body/BodyGray.icon/icon.json",
            "Body/BodyPink.icon/icon.json",
            "Body/BodyPurple.icon/icon.json",
            "Body/BodyWhite.icon/icon.json",
            "BodyWatch/AppIcon.icon/icon.json",
            "BodyWidgetExtension/AppIcon.icon/icon.json"
        ]

        for path in iconBundles {
            let data = try Data(contentsOf: BodyTestSupport.projectRoot.appendingPathComponent(path))
            XCTAssertGreaterThan(data.count, 0, path)
        }

        // In-app icon-picker thumbnails, one per standard color.
        let previewAssets = [
            "Body/Assets.xcassets/BodyIcon01.imageset/BodyIcon01.png",
            "Body/Assets.xcassets/BodyIconBlack.imageset/BodyIconBlack.png",
            "Body/Assets.xcassets/BodyIconGray.imageset/BodyIconGray.png",
            "Body/Assets.xcassets/BodyIconPink.imageset/BodyIconPink.png",
            "Body/Assets.xcassets/BodyIconPurple.imageset/BodyIconPurple.png",
            "Body/Assets.xcassets/BodyIconWhite.imageset/BodyIconWhite.png"
        ]

        for path in previewAssets {
            let data = try Data(contentsOf: BodyTestSupport.projectRoot.appendingPathComponent(path))
            XCTAssertGreaterThan(data.count, 0, path)
        }

        // The legacy .appiconset artwork and the removed "Present" creator-surprise
        // alternates (icons + preview thumbnails) must no longer exist.
        let removedPaths = [
            "Body/Assets.xcassets/AppIcon.appiconset",
            "Body/Assets.xcassets/BodyBlack.appiconset",
            "Body/Assets.xcassets/BodyClassicAlt.appiconset",
            "Body/Assets.xcassets/BodyBlackAlt.appiconset",
            "Body/Assets.xcassets/BodyGrayAlt.appiconset",
            "Body/Assets.xcassets/BodyPinkAlt.appiconset",
            "Body/Assets.xcassets/BodyPurpleAlt.appiconset",
            "Body/Assets.xcassets/BodyWhiteAlt.appiconset",
            "Body/Assets.xcassets/BodyIconClassicAlt.imageset",
            "Body/Assets.xcassets/BodyIconBlackAlt.imageset",
            "Body/Assets.xcassets/BodyIconWhiteAlt.imageset",
            "BodyWidgetExtension/Assets.xcassets/AppIcon.appiconset"
        ]

        for path in removedPaths {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: BodyTestSupport.projectRoot.appendingPathComponent(path).path),
                path
            )
        }
    }

    func testProjectDeclaresSimplifiedChineseLocalization() throws {
        let project = try BodyTestSupport.sourceText(at: "body.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains(#""zh-Hans","#))
        XCTAssertTrue(project.contains("developmentRegion = en;"))
    }

    func testChineseLocalizationCatalogsAreComplete() throws {
        let catalogPaths = [
            "Body/Localizable.xcstrings",
            "Body/InfoPlist.xcstrings",
            "BodyMetricsKit/BodyMetricsKit.xcstrings",
            "BodyShared/BodyShared.xcstrings",
            "BodyWatchShared/BodyWatchShared.xcstrings",
            "BodyWatchSnapshotKit/BodyWatchSnapshotKit.xcstrings",
            "BodyWatch/Localizable.xcstrings",
            "BodyWatch/InfoPlist.xcstrings",
            "BodyWidgetExtension/Localizable.xcstrings",
            "BodyWatchWidgetExtension/Localizable.xcstrings"
        ]

        for path in catalogPaths {
            let data = try Data(contentsOf: BodyTestSupport.projectRoot.appendingPathComponent(path))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], path)
            XCTAssertEqual(root["sourceLanguage"] as? String, "en", path)
            let strings = try XCTUnwrap(root["strings"] as? [String: Any], path)
            XCTAssertFalse(strings.isEmpty, "\(path) has no entries")

            for (key, rawEntry) in strings {
                // Xcode's string-catalog build phase intermittently re-injects an
                // empty-key placeholder ("" with no localizations) into the app
                // catalog on recompile. It is never user-facing, so skip it rather
                // than fail the Chinese-coverage check on every unrelated UI change.
                if key.isEmpty { continue }

                let entry = try XCTUnwrap(rawEntry as? [String: Any], "\(path) \(key)")
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "\(path) \(key)")
                for language in ["en", "zh-Hans"] {
                    let localization = try XCTUnwrap(
                        localizations[language] as? [String: Any],
                        "\(path) \(key) missing \(language)"
                    )
                    let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any], "\(path) \(key) \(language)")
                    XCTAssertEqual(unit["state"] as? String, "translated", "\(path) \(key) \(language)")
                    let value = try XCTUnwrap(unit["value"] as? String, "\(path) \(key) \(language)")
                    XCTAssertFalse(value.isEmpty, "\(path) \(key) \(language)")
                }
            }
        }
    }

}
