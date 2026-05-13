//
//  ProjectConfigurationTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class ProjectConfigurationTests: XCTestCase {
    func testSettingsAboutTabsMatchCoinAboutSet() {
        XCTAssertEqual(
            BodySettingsAboutTab.allCases.map(\.title),
            [
                "How to Use",
                "Feedback",
                "Privacy",
                "Disclaimer",
                "Copyright",
                "Version"
            ]
        )
        XCTAssertEqual(
            BodySettingsAboutTab.allCases.filter(\.opensSheet).map(\.title),
            [
                "How to Use",
                "Feedback",
                "Privacy",
                "Disclaimer",
                "Copyright"
            ]
        )
    }

    func testSettingsDataTabsExposePermissions() {
        XCTAssertEqual(BodySettingsDataTab.allCases.map(\.title), ["Permissions"])
        XCTAssertEqual(BodySettingsDataTab.permissions.sheet, .permissions)
    }

    func testHealthPermissionTogglesUseGreenOnAndRedOffSwitchColors() throws {
        let source = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(source.contains("private struct BodyPermissionSwitchToggleStyle: ToggleStyle"))
        XCTAssertTrue(source.contains("BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red)"))
        XCTAssertTrue(source.contains("configuration.isOn ? onColor : offColor"))
        XCTAssertTrue(source.contains("configuration.isOn.toggle()"))
        XCTAssertFalse(source.contains(".tint(permission.tintColor)"))
    }

    func testHealthMetricChartSelectionAnnotationsFitWithinChartEdges() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertTrue(source.contains("private let bodyChartSelectionOverflowResolution"))
        XCTAssertTrue(source.contains("AnnotationOverflowResolution("))
        XCTAssertTrue(source.contains("x: .fit(to: .chart)"))
        XCTAssertTrue(source.contains("y: .disabled"))
        XCTAssertEqual(source.occurrenceCount(of: "overflowResolution: bodyChartSelectionOverflowResolution"), 5)
        XCTAssertFalse(source.contains(".annotation(position: .top, spacing: 8) {"))
    }

    func testHealthMetricChartDateDomainsFavorRightSidePadding() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertTrue(source.contains("bodyHealthDetailChartLeadingDatePadding: TimeInterval = 2 * 60 * 60"))
        XCTAssertTrue(source.contains("bodyHealthDetailChartTrailingDatePadding: TimeInterval = 36 * 60 * 60"))
        XCTAssertTrue(source.contains("private func bodyHealthDetailChartXDomain(for dates: [Date]) -> ClosedRange<Date>"))
        XCTAssertEqual(source.occurrenceCount(of: "return bodyHealthDetailChartXDomain(for:"), 3)
        XCTAssertFalse(source.contains("let leadingPadding: TimeInterval = 6 * 60 * 60"))
        XCTAssertFalse(source.contains("let trailingPadding: TimeInterval = 18 * 60 * 60"))
    }

    func testLineHealthChartsDoNotRenderEmptyDatePlaceholderMarks() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertFalse(source.contains("BodyLineChartPlaceholderSymbol"))
        XCTAssertFalse(source.contains("placeholderSymbolSize"))
        XCTAssertTrue(source.contains("placeholderBarYValue"))
    }

    func testAggregatedHealthChartsWireRangeLabelsAndBarWidths() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertTrue(source.contains("private func bodyChartSelectionDateText(for point: HealthTrendCalendarPoint) -> String?"))
        XCTAssertEqual(source.occurrenceCount(of: "dateText: bodyChartSelectionDateText(for: selectedTrendPoint)"), 1)
        XCTAssertEqual(source.occurrenceCount(of: "dateText: bodyChartSelectionDateText(for: selectedPoint)"), 1)
        XCTAssertTrue(source.contains("dateText: selectedTrendDateText"))
        XCTAssertEqual(source.occurrenceCount(of: "width: .fixed(selectedTrendRange.chartBarWidth)"), 2)
    }

    func testBasicsWeightBodyFatMonthChartHidesPointMarksOnlyInDualChart() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertTrue(source.contains("private var showsWeightBodyFatPointMarks: Bool"))
        XCTAssertTrue(source.contains("selectedRange.showsPointMarks && selectedRange != .recentMonth"))
        XCTAssertEqual(source.occurrenceCount(of: "if showsWeightBodyFatPointMarks"), 2)
        XCTAssertTrue(source.contains("if selectedRange.showsPointMarks"))
        XCTAssertTrue(source.contains("if selectedTrendRange.showsPointMarks"))
    }

    func testBasicsTrendLegendShowsAverageValuesBehindMetricLabels() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertTrue(source.contains("weightAverageText: basicsWeightAverageText"))
        XCTAssertTrue(source.contains("bodyFatAverageText: basicsBodyFatAverageText"))
        XCTAssertTrue(source.contains("legendItem(title: \"Body Fat\", valueText: bodyFatAverageText, color: bodyFatColor)"))
        XCTAssertTrue(source.contains("legendItem(title: \"Weight\", valueText: weightAverageText, color: weightColor)"))
        XCTAssertTrue(source.contains("if let valueText"))
    }

    func testWorkoutHeartRateXAxisLabelsStayInsidePlotEdges() throws {
        let source = try text(at: "Body/Views/BodyWorkoutsView.swift")

        XCTAssertTrue(source.contains("private static let timeMarkLabelHorizontalInset: CGFloat = 24"))
        XCTAssertTrue(source.contains("static let timeMarkFractions = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]"))
        XCTAssertTrue(source.contains("Self.timeMarkFractions.map"))
        XCTAssertTrue(source.contains("BodyWorkoutHeartRateChartMetrics.timeMarkFractions"))
        XCTAssertTrue(source.contains("timeMarkLabelX(for: mark, in: plotRect)"))
        XCTAssertTrue(source.contains("min(max(rawX, lowerBound), upperBound)"))
        XCTAssertFalse(source.contains("x: plotRect.minX + plotRect.width * mark.fraction"))
    }

    func testSummaryTabUsesHealthDashboardIcon() throws {
        let source = try text(at: "Body/Views/MainTabView.swift")

        XCTAssertTrue(source.contains(#"Label("Summary", systemImage: "heart.text.square.fill")"#))
        XCTAssertFalse(source.contains(#"Label("Summary", systemImage: "house.fill")"#))
    }

    func testAppAndWidgetShareAppGroupEntitlement() throws {
        let appEntitlements = try propertyList(at: "Body/Body.entitlements")
        let widgetEntitlements = try propertyList(at: "BodyWidgetExtension.entitlements")

        XCTAssertEqual(
            appEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
        XCTAssertEqual(
            widgetEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
    }

    func testAppDeclaresHealthKitEntitlement() throws {
        let appEntitlements = try propertyList(at: "Body/Body.entitlements")

        XCTAssertEqual(appEntitlements["com.apple.developer.healthkit"] as? Bool, true)
    }

    func testPrivacyManifestsDeclareUserDefaultsAndNoTracking() throws {
        for path in ["Body/PrivacyInfo.xcprivacy", "BodyWidgetExtension/PrivacyInfo.xcprivacy"] {
            let manifest = try propertyList(at: path)
            XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false, path)
            XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty, true, path)

            let accessedAPITypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]], path)
            let userDefaultsDeclaration = accessedAPITypes.first {
                $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
            }
            XCTAssertEqual(
                userDefaultsDeclaration?["NSPrivacyAccessedAPITypeReasons"] as? [String],
                ["CA92.1"],
                path
            )
        }
    }

    func testProjectBuildSettingsMatchInitialReleasePlan() throws {
        let project = try text(at: "body.xcodeproj/project.pbxproj")

        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body.BodyWidgetExtension;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.BodyTests;"))
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"BodyBlack BodyBlackAlt BodyClassicAlt BodyGray BodyGrayAlt BodyPink BodyPinkAlt BodyPurple BodyPurpleAlt BodyWhite BodyWhiteAlt\";"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSHealthShareUsageDescription"))
        XCTAssertTrue(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 18.0;"))
        XCTAssertTrue(project.contains("TARGETED_DEVICE_FAMILY = 1;"))
        XCTAssertTrue(project.contains("SUPPORTS_MACCATALYST = NO;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;"))
        XCTAssertTrue(project.contains("MARKETING_VERSION = 0.3.3;"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 1;"))
        XCTAssertTrue(project.contains("VALIDATE_PRODUCT = YES;"))
    }

    func testAppIconAssetsIncludePrimaryAndAlternateOptions() throws {
        let iconPaths = [
            "Body/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
            "Body/Assets.xcassets/BodyClassicAlt.appiconset/BodyClassicAlt.png",
            "Body/Assets.xcassets/BodyBlack.appiconset/BodyBlack.png",
            "Body/Assets.xcassets/BodyBlackAlt.appiconset/BodyBlackAlt.png",
            "Body/Assets.xcassets/BodyGray.appiconset/BodyGray.png",
            "Body/Assets.xcassets/BodyGrayAlt.appiconset/BodyGrayAlt.png",
            "Body/Assets.xcassets/BodyPink.appiconset/BodyPink.png",
            "Body/Assets.xcassets/BodyPinkAlt.appiconset/BodyPinkAlt.png",
            "Body/Assets.xcassets/BodyPurple.appiconset/BodyPurple.png",
            "Body/Assets.xcassets/BodyPurpleAlt.appiconset/BodyPurpleAlt.png",
            "Body/Assets.xcassets/BodyWhite.appiconset/BodyWhite.png",
            "Body/Assets.xcassets/BodyWhiteAlt.appiconset/BodyWhiteAlt.png",
            "Body/Assets.xcassets/BodyIcon01.imageset/BodyIcon01.png",
            "Body/Assets.xcassets/BodyIconBlack.imageset/BodyIconBlack.png",
            "Body/Assets.xcassets/BodyIconBlackAlt.imageset/BodyIconBlackAlt.png",
            "Body/Assets.xcassets/BodyIconClassicAlt.imageset/BodyIconClassicAlt.png",
            "Body/Assets.xcassets/BodyIconGray.imageset/BodyIconGray.png",
            "Body/Assets.xcassets/BodyIconGrayAlt.imageset/BodyIconGrayAlt.png",
            "Body/Assets.xcassets/BodyIconPink.imageset/BodyIconPink.png",
            "Body/Assets.xcassets/BodyIconPinkAlt.imageset/BodyIconPinkAlt.png",
            "Body/Assets.xcassets/BodyIconPurple.imageset/BodyIconPurple.png",
            "Body/Assets.xcassets/BodyIconPurpleAlt.imageset/BodyIconPurpleAlt.png",
            "Body/Assets.xcassets/BodyIconWhite.imageset/BodyIconWhite.png",
            "Body/Assets.xcassets/BodyIconWhiteAlt.imageset/BodyIconWhiteAlt.png",
            "BodyWidgetExtension/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        ]

        for path in iconPaths {
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
            XCTAssertGreaterThan(data.count, 0, path)
        }
    }

    func testSettingsVersionTapUnlocksCreatorSurpriseIcons() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(settingsSource.contains("@State private var versionTapCount = 0"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.creatorSurpriseIconsUnlockedKey)"))
        XCTAssertTrue(settingsSource.contains("handleVersionCardTap()"))
        XCTAssertTrue(settingsSource.contains("versionTapCount >= 5"))
        XCTAssertTrue(settingsSource.contains("showingCreatorSurprise = true"))
        XCTAssertTrue(settingsSource.contains("BodyCreatorSurpriseOverlay"))
        XCTAssertTrue(settingsSource.contains("BodyCreatorRibbon"))
        XCTAssertTrue(settingsSource.contains("availableOptions(includeCreatorSurprises:"))

        let requiredLabels = [
            #"displayName: "Classic""#,
            #"descriptor: "Original""#,
            #"displayName: "Rose""#,
            #"descriptor: "Pink""#,
            #"displayName: "Violet""#,
            #"descriptor: "Purple""#,
            #"displayName: "Midnight""#,
            #"descriptor: "Black""#,
            #"displayName: "Neutral""#,
            #"descriptor: "Gray""#,
            #"displayName: "Light""#,
            #"descriptor: "White""#,
            #"descriptor: "Present""#
        ]

        for label in requiredLabels {
            XCTAssertTrue(settingsSource.contains(label), label)
        }

        XCTAssertEqual(settingsSource.occurrenceCount(of: #"descriptor: "Present""#), 6)
    }

    func testBodyProPageUsesCoinStyleSettingsEntryAndIconAssets() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let bodyProSource = try text(at: "Body/Views/BodyProView.swift")

        XCTAssertTrue(settingsSource.contains("bodyProEntryCard"))
        XCTAssertTrue(settingsSource.contains("NavigationLink {"))
        XCTAssertTrue(settingsSource.contains("BodyProView()"))
        XCTAssertTrue(settingsSource.contains("BodySettingsTypography.sectionTitleFontSize"))
        XCTAssertTrue(bodyProSource.contains("BodyProFlippableIcon"))
        XCTAssertTrue(bodyProSource.contains("BodyProIconGlow()"))
        XCTAssertTrue(bodyProSource.contains("private struct BodyProIconGlow"))
        XCTAssertTrue(bodyProSource.contains("RadialGradient("))
        XCTAssertTrue(bodyProSource.contains("BodyProPalette.gold.opacity(0.28)"))
        XCTAssertTrue(bodyProSource.contains("BodyProPalette.gold.opacity(0.10)"))
        XCTAssertTrue(bodyProSource.contains("BodyProPalette.gold.opacity(0.08)"))
        XCTAssertFalse(bodyProSource.contains("BodyProPalette.gold.opacity(0.42)"))
        XCTAssertTrue(bodyProSource.contains("BodyAppearancePreference.bodyProIconAssetName(showsBack:"))
        XCTAssertTrue(bodyProSource.contains(#"Text("Unlock All Pro Features")"#))
        XCTAssertFalse(bodyProSource.contains(#"Text("Unlock Body Pro")"#))
        XCTAssertTrue(bodyProSource.contains("private struct BodyProFeatureCheckmark"))
        XCTAssertEqual(bodyProSource.occurrenceCount(of: "BodyProFeatureCheckmark()"), 2)
        XCTAssertFalse(bodyProSource.contains("HStack(alignment: .top, spacing: 14)"))
        XCTAssertFalse(bodyProSource.contains(".padding(.top, 2)"))
        XCTAssertFalse(bodyProSource.contains(".padding(.top, 8)"))
        XCTAssertEqual(bodyProSource.occurrenceCount(of: "BodyProFeature("), 2)
        XCTAssertTrue(bodyProSource.contains("Six-Month and Year Charts"))
        XCTAssertTrue(bodyProSource.contains("Body Widgets"))
        XCTAssertTrue(bodyProSource.contains("Future Pro Updates"))
        XCTAssertTrue(bodyProSource.contains("$5.99"))
        XCTAssertFalse(bodyProSource.contains("$0.89"))
        XCTAssertFalse(bodyProSource.contains("$2.59"))
        XCTAssertFalse(bodyProSource.contains("$8.99"))
        XCTAssertFalse(bodyProSource.contains("$15.99"))

        let proIconPaths = [
            "Body/Assets.xcassets/BodyProIcon.imageset/BodyProIcon.png",
            "Body/Assets.xcassets/BodyProIconBack.imageset/BodyProIconBack.png"
        ]

        for path in proIconPaths {
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
            XCTAssertGreaterThan(data.count, 0, path)
        }
    }

    func testWidgetFamiliesArePinnedPerWidget() throws {
        let widgetSource = try text(at: "BodyWidgetExtension/WorkoutCalendarWidget.swift")
        let breakdownSource = try text(at: "BodyShared/Components/WorkoutTypeBreakdownView.swift")

        XCTAssertEqual(widgetSource.occurrenceCount(of: ".supportedFamilies([.systemLarge])"), 1)
        XCTAssertEqual(widgetSource.occurrenceCount(of: ".supportedFamilies([.systemMedium, .systemLarge])"), 1)
        XCTAssertTrue(widgetSource.contains("style: .widgetLarge"))
        XCTAssertTrue(widgetSource.contains(".padding(14)"))
        XCTAssertTrue(widgetSource.contains("family == .systemMedium ? .widgetMedium : .widgetLarge"))
        XCTAssertTrue(breakdownSource.contains("case .app:"))
        XCTAssertTrue(breakdownSource.contains("return snapshot.workoutTypeBreakdown.count"))
        XCTAssertTrue(breakdownSource.contains("case .widgetMedium:"))
        XCTAssertTrue(breakdownSource.contains("return 2"))
        XCTAssertTrue(breakdownSource.contains("case .widgetLarge:"))
        XCTAssertTrue(breakdownSource.contains("return 5"))
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func propertyList(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent(relativePath))
        var format = PropertyListSerialization.PropertyListFormat.xml
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )
        return try XCTUnwrap(propertyList as? [String: Any])
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
