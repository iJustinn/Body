//
//  ProjectConfigurationTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

final class ProjectConfigurationTests: XCTestCase {
    func testSettingsAboutTabsMatchCoinAboutSet() {
        XCTAssertEqual(
            BodySettingsAboutTab.allCases.map(\.title),
            [
                "How to Use",
                "Privacy",
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

    func testSettingsAboutDocumentationTabsOpenExternalLinks() throws {
        let source = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(source.contains(#"@State private var showingHowToUseBrowser = false"#))
        XCTAssertTrue(source.contains(#"private let howToUseURLString = "https://docs.ijustinz.com/body/how-to-use""#))
        XCTAssertTrue(source.contains(#"private let privacyPolicyURLString = "https://docs.ijustinz.com/body/privacy""#))
        XCTAssertTrue(source.contains("showingHowToUseBrowser = true"))
        XCTAssertTrue(source.contains("showingPrivacyBrowser = true"))
        XCTAssertTrue(source.contains("case .externalLink:"))
        XCTAssertTrue(source.contains(#"Image(systemName: "arrow.up.right")"#))
        XCTAssertFalse(source.contains("BodyHowToUseSettingsSheet()"))
        XCTAssertFalse(source.contains("private struct BodyHowToUseSettingsSheet"))
    }

    func testSettingsDataTabsExposePermissions() {
        XCTAssertEqual(BodySettingsDataTab.allCases.map(\.title), ["Source", "Permissions", "Data Refresh", "Cache"])
        XCTAssertEqual(BodySettingsDataTab.source.sheet, .source)
        XCTAssertEqual(BodySettingsDataTab.permissions.sheet, .permissions)
        XCTAssertEqual(BodySettingsDataTab.syncStatus.sheet, .syncStatus)
        XCTAssertEqual(BodySettingsDataTab.cache.sheet, .cache)
    }

    func testSettingsSheetsDoNotShowToolbarCloseButtons() throws {
        let source = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertFalse(source.contains(#"Button("Cancel")"#))
        XCTAssertFalse(source.contains(#"Button("Done")"#))
    }

    func testAutoApplyWorkoutEffortSettingIsWiredAndDefaultsOff() throws {
        let keys = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let settings = try text(at: "Body/Views/BodySettingsView.swift")
        let store = try text(at: "Body/Services/HealthKitWorkoutStore.swift")

        XCTAssertTrue(keys.contains(#"static let autoApplyWorkoutEffortKey = "autoApplyWorkoutEffort""#))
        XCTAssertTrue(settings.contains("@AppStorage(BodyAppearancePreference.autoApplyWorkoutEffortKey) private var autoApplyWorkoutEffort = false"))
        XCTAssertTrue(settings.contains("BodyAutoApplyEffortToggleRow("))
        // The setting must gate the auto-write path in the store, not just the UI.
        XCTAssertTrue(store.contains("func autoApplyPredictedEffortIfNeeded(monthKeys:"))
        XCTAssertTrue(store.contains("BodyAppearancePreference.autoApplyWorkoutEffortKey"))
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

    func testSettingsSourceSheetExposesGlobalDefaultsAndCombineToggle() throws {
        let source = try text(at: "Body/Views/BodySettingsView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let engineSource = try healthKitFetchEngineText()

        XCTAssertTrue(source.contains("case source"))
        XCTAssertTrue(source.contains("BodySourceSettingsSheet(workoutStore: workoutStore)"))
        XCTAssertTrue(source.contains("Combine Sources with Same Name"))
        XCTAssertTrue(source.contains("Primary Data Source"))
        XCTAssertTrue(source.contains("Secondary Data Source"))
        XCTAssertTrue(source.contains("updateCombinesHealthDataSourcesByName"))
        XCTAssertTrue(source.contains("updateDefaultHealthDataSource"))
        XCTAssertTrue(source.contains("updateDefaultSecondaryHealthDataSource"))
        XCTAssertTrue(storeSource.contains("resolvedHealthDataSourceOption"))
        XCTAssertTrue(storeSource.contains("resolvedSecondaryHealthDataSourceOption"))
        XCTAssertTrue(engineSource.contains("selectedSecondaryHealthDataSourceOption(for: kind).isNoComparison"))
    }

    func testReadinessDailySeriesUsesCachedBaselineContext() throws {
        let source = try text(at: "BodyMetricsKit/ReadinessScoreCalculator.swift")
        let dailySeriesStart = try XCTUnwrap(source.range(of: "static func dailySeries(")?.lowerBound)
        let nextDeclaration = try XCTUnwrap(source[dailySeriesStart...].range(of: "private static func autonomicReadings(")?.lowerBound)
        let dailySeriesBlock = String(source[dailySeriesStart..<nextDeclaration])

        XCTAssertTrue(source.contains("ReadinessDailySeriesContext"))
        XCTAssertTrue(dailySeriesBlock.contains("ReadinessDailySeriesContext("))
        XCTAssertFalse(dailySeriesBlock.contains("summary("))
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
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("let bodyChartSelectionOverflowResolution"))
        XCTAssertTrue(source.contains("AnnotationOverflowResolution("))
        XCTAssertTrue(source.contains("x: .fit(to: .chart)"))
        XCTAssertTrue(source.contains("y: .disabled"))
        XCTAssertEqual(source.occurrenceCount(of: "overflowResolution: bodyChartSelectionOverflowResolution"), 10)
        XCTAssertFalse(source.contains(".annotation(position: .top, spacing: 8) {"))
    }

    func testHealthMetricChartDateDomainsFavorRightSidePadding() throws {
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("bodyHealthDetailChartLeadingDatePadding: TimeInterval = 2 * 60 * 60"))
        XCTAssertTrue(source.contains("bodyHealthDetailChartMinimumTrailingDatePadding: TimeInterval = 36 * 60 * 60"))
        XCTAssertTrue(source.contains("func bodyHealthDetailChartTrailingDatePadding(for selectedRange: BodyHealthTrendRange) -> TimeInterval"))
        XCTAssertTrue(source.contains("let rangeScaledPadding = Double(selectedRange.axisStrideDayCount) * 24 * 60 * 60 * 0.55"))
        XCTAssertTrue(source.contains("return max(bodyHealthDetailChartMinimumTrailingDatePadding, rangeScaledPadding)"))
        XCTAssertTrue(source.contains("func bodyHealthDetailChartXDomain(for dates: [Date], selectedRange: BodyHealthTrendRange, immersive: Bool = false, immersivePairedBars: Bool = false, pairedBarComparison: Bool = false) -> ClosedRange<Date>"))
        // Immersive charts (Y axis hidden) pad each edge by ~half a data bucket so the
        // first/last bar or point fits without clipping and no empty day appears. Week
        // single-mark charts bias slightly right (less space left, more right). Month charts
        // keep a half-bucket leading nudge with a full-bucket trailing; six-month/year charts
        // pin the first mark to the left wall (no leading padding) with a 1.5-bucket trailing.
        // Only the two-source paired-bar comparison chart is excluded and stays symmetric.
        // Non-immersive charts keep the small leading padding and favor right-side padding.
        XCTAssertTrue(source.contains("let bucketSeconds = Double(selectedRange.chartAggregationDayCount) * 24 * 60 * 60"))
        XCTAssertTrue(source.contains("if selectedRange == .recentWeek && !immersivePairedBars {"))
        XCTAssertTrue(source.contains("leadingDatePadding = 2 * 60 * 60"))
        XCTAssertTrue(source.contains("trailingDatePadding = 26 * 60 * 60"))
        XCTAssertTrue(source.contains("} else if !pairedBarComparison && selectedRange == .recentMonth {"))
        XCTAssertTrue(source.contains("leadingDatePadding = bucketSeconds * 0.5"))
        XCTAssertTrue(source.contains("trailingDatePadding = 28 * 60 * 60"))
        XCTAssertTrue(source.contains("} else if !pairedBarComparison && (selectedRange == .recentSixMonths || selectedRange == .recentYear) {"))
        XCTAssertTrue(source.contains("leadingDatePadding = 0"))
        XCTAssertTrue(source.contains("trailingDatePadding = bucketSeconds * 1.5"))
        XCTAssertTrue(source.contains("let halfBucketPadding = bucketSeconds * 0.5"))
        XCTAssertTrue(source.contains("leadingDatePadding = bodyHealthDetailChartLeadingDatePadding"))
        XCTAssertTrue(source.contains("trailingDatePadding = bodyHealthDetailChartTrailingDatePadding(for: selectedRange)"))
        XCTAssertEqual(
            source.occurrenceCount(of: "self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive:"),
            7
        )
        XCTAssertEqual(
            source.occurrenceCount(of: "bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive)"),
            4
        )
        XCTAssertEqual(
            source.occurrenceCount(of: "immersive: immersive, immersivePairedBars: true)"),
            1
        )
        XCTAssertEqual(
            source.occurrenceCount(of: "immersive: immersive, immersivePairedBars: true, pairedBarComparison: true)"),
            1
        )
        XCTAssertFalse(source.contains("bodyHealthDetailChartTrailingDatePadding: TimeInterval = 36 * 60 * 60"))
        XCTAssertFalse(source.contains("let leadingPadding: TimeInterval = 6 * 60 * 60"))
        XCTAssertFalse(source.contains("let trailingPadding: TimeInterval = 18 * 60 * 60"))
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

    func testHealthDashboardUpdatesRecalculateReadinessBeforeSaving() throws {
        let source = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let updateStart = try XCTUnwrap(source.range(of: "private func updateHealthDashboardSnapshot(")?.lowerBound)
        let saveStart = try XCTUnwrap(
            source.range(of: "HealthDashboardSnapshotStore.save(", range: updateStart..<source.endIndex)?.lowerBound
        )
        let updateBlock = String(source[updateStart..<saveStart])

        XCTAssertTrue(updateBlock.contains(".recalculatingReadiness("))
    }

    func testReadinessCardAndDetailAreRouted() throws {
        let source = try bodyHomeViewText()
        let cardStart = try XCTUnwrap(source.range(of: "private func readinessMetric(")?.lowerBound)
        let cardEnd = try XCTUnwrap(source.range(of: "private func energyMetric(", range: cardStart..<source.endIndex)?.lowerBound)
        let cardBlock = String(source[cardStart..<cardEnd])
        let whyStart = try XCTUnwrap(source.range(of: "private func readinessWhyCard(")?.lowerBound)
        let whyEnd = try XCTUnwrap(source.range(of: "@ViewBuilder\n    private var dataSourceFooter", range: whyStart..<source.endIndex)?.lowerBound)
        let whyBlock = String(source[whyStart..<whyEnd])

        XCTAssertTrue(source.contains("readinessMetric("))
        XCTAssertTrue(source.contains("case .readiness:"))
        XCTAssertTrue(source.contains("summary.readiness"))
        XCTAssertTrue(source.contains("trends.series(for: .readiness)"))
        XCTAssertTrue(source.contains("BodyReadinessStatusPresentation"))
        XCTAssertTrue(source.contains("BodyReadinessStatusBreakdownChart"))
        XCTAssertTrue(cardBlock.contains("unit: summary.score == nil ? \"\" : \"%\""))
        XCTAssertFalse(cardBlock.contains("BodyMetricDisplayValue(title: \"Status\""))
        XCTAssertTrue(source.contains("valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + \"%\" }"))
        XCTAssertTrue(whyBlock.contains("ReadinessStatus.displayOrder"))
        XCTAssertTrue(whyBlock.contains("About your score"))
        XCTAssertTrue(whyBlock.contains("status.scoreRangeText"))
        XCTAssertTrue(whyBlock.contains("status.explanation"))
        XCTAssertTrue(whyBlock.contains("BodyReadinessStatusPresentation.color(for: status)"))
        XCTAssertTrue(whyBlock.contains("activeStatus"))
        XCTAssertTrue(source.contains("@State private var activeReadinessTrendValue: Double?"))
        XCTAssertTrue(source.contains("private var activeReadinessStatus: ReadinessStatus?"))
        XCTAssertTrue(source.contains("readinessWhyCard(for: readiness, activeStatus: activeReadinessStatus)"))
        XCTAssertTrue(source.contains("activeHighlightedValue: model.kind == .readiness ? $activeReadinessTrendValue : nil"))
        XCTAssertFalse(whyBlock.contains("ForEach(readiness.components)"))
    }

    func testBasicsTrendCardsRouteThroughRegisteredNavigationDestination() throws {
        let source = try bodyHomeViewText()

        // The Basics page's Weight/Body Fat trend cards must push a `HomeMetricRoute`
        // (the type registered via `.navigationDestination(for: HomeMetricRoute.self)`
        // on the Home stack that hosts this page), not a bare `HealthMetricKind` — no
        // `navigationDestination(for: HealthMetricKind.self)` is registered anywhere,
        // which would make the cards inert. The `.basicsTrend` route (distinct from the
        // home trends section's `.trend`) also carries the card→detail zoom-morph source.
        XCTAssertTrue(source.contains("NavigationLink(value: HomeMetricRoute.basicsTrend(kind))"))
        XCTAssertTrue(source.contains(".matchedTransitionSource(id: HomeMetricRoute.basicsTrend(kind), in: zoomNamespace)"))
        XCTAssertFalse(source.contains("NavigationLink(value: kind)"))
        XCTAssertTrue(source.contains(".navigationDestination(for: HomeMetricRoute.self)"))
        XCTAssertFalse(source.contains(".navigationDestination(for: HealthMetricKind.self)"))
    }

    func testMetricDetailHeaderIconMatchesHomeMetricCardTintTreatment() throws {
        let source = try bodyHomeViewText()
        let cardIconStart = try XCTUnwrap(source.range(of: "Image(systemName: metric.symbolName)")?.lowerBound)
        let cardIconEnd = try XCTUnwrap(source.range(of: "private var valueRow", range: cardIconStart..<source.endIndex)?.lowerBound)
        let cardIconBlock = String(source[cardIconStart..<cardIconEnd])

        // The metric detail page no longer shows a header icon card — its current
        // value now reads large in the gradient hero — so only the home metric card
        // icon tint treatment is asserted here.
        XCTAssertTrue(cardIconBlock.contains(".foregroundColor(metric.symbolColor)"))
        XCTAssertTrue(cardIconBlock.contains(".fill(metric.symbolColor.opacity(0.16))"))
    }

    func testMetricDetailPagesUseRequestedCardOrdering() throws {
        let source = try bodyHomeViewText()
        // The header/selector/trend-card now live in the gradient hero; the cards
        // that scroll below it (and their ordering) live in `metricDetailCards`.
        let cardsStart = try XCTUnwrap(source.range(of: "private var metricDetailCards: some View")?.lowerBound)
        let cardsEnd = try XCTUnwrap(
            source.range(of: "private var metricHeroValueRow", range: cardsStart..<source.endIndex)?.lowerBound
        )
        let detailBodyBlock = String(source[cardsStart..<cardsEnd])
        let sleepSelectedCardsStart = try XCTUnwrap(detailBodyBlock.range(of: "selectedSleepCards")?.lowerBound)
        let sleepTrendCardStart = try XCTUnwrap(
            detailBodyBlock.range(of: "detailTrendComparisonCard", range: sleepSelectedCardsStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let sleepAboutStart = try XCTUnwrap(detailBodyBlock.range(of: "aboutSleepScoreCard")?.lowerBound)
        let dayViewStart = try XCTUnwrap(detailBodyBlock.range(of: "if supportsMetricDayView")?.lowerBound)
        let metricDayChartStart = try XCTUnwrap(
            detailBodyBlock.range(of: "metricDayChartCard", range: dayViewStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let metricActivityAveragesStart = try XCTUnwrap(
            detailBodyBlock.range(of: "metricActivityAveragesCard", range: metricDayChartStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let dayViewTrendCardStart = try XCTUnwrap(
            detailBodyBlock.range(of: "detailTrendComparisonCard", range: metricDayChartStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let dayViewElseStart = try XCTUnwrap(
            detailBodyBlock.range(of: "} else {", range: dayViewTrendCardStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let nonDayTrendCardStart = try XCTUnwrap(
            detailBodyBlock.range(of: "detailTrendComparisonCard", range: dayViewElseStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let readinessAboutStart = try XCTUnwrap(detailBodyBlock.range(of: "readinessWhyCard(for: readiness")?.lowerBound)
        let helpTextStart = try XCTUnwrap(detailBodyBlock.range(of: "helpTextCard")?.lowerBound)

        XCTAssertLessThan(sleepSelectedCardsStart, sleepTrendCardStart)
        XCTAssertLessThan(sleepTrendCardStart, sleepAboutStart)
        XCTAssertLessThan(metricDayChartStart, dayViewTrendCardStart)
        XCTAssertLessThan(metricDayChartStart, metricActivityAveragesStart)
        XCTAssertLessThan(metricActivityAveragesStart, dayViewTrendCardStart)
        XCTAssertLessThan(dayViewTrendCardStart, dayViewElseStart)
        XCTAssertLessThan(readinessAboutStart, nonDayTrendCardStart)
        XCTAssertLessThan(dayViewTrendCardStart, helpTextStart)
        XCTAssertEqual(detailBodyBlock.occurrenceCount(of: "detailTrendComparisonCard"), 3)
        XCTAssertTrue(source.contains("BodyHomeTrendCardFactory.card("))
        XCTAssertTrue(source.contains("BodyHomeTrendCard(model: card, showsNavigationIndicator: false)"))
        XCTAssertTrue(source.contains("@StateObject private var trendComputationCache = BodyHomeTrendComputationCache()"))
        XCTAssertTrue(source.contains("model.kind == .heartRate || model.kind == .heartRateVariability"))
        XCTAssertTrue(source.contains(#"model.kind == .heartRate ? "Average Heart Rate" : "Average HRV""#))
        XCTAssertFalse(source.contains("Activity Heart Rate"))
    }

    func testLineHealthChartsDoNotRenderEmptyDatePlaceholderMarks() throws {
        let source = try bodyHomeViewText()

        XCTAssertFalse(source.contains("BodyLineChartPlaceholderSymbol"))
        XCTAssertFalse(source.contains("placeholderSymbolSize"))
        XCTAssertTrue(source.contains("placeholderBarYValue"))
    }

    func testLineHealthChartsUseStraightInterpolation() throws {
        let source = try bodyHomeViewText()

        XCTAssertFalse(source.contains(".interpolationMethod(.catmullRom)"))
        XCTAssertEqual(
            source.occurrenceCount(of: ".interpolationMethod("),
            source.occurrenceCount(of: ".interpolationMethod(.linear)")
        )
    }

    func testMetricDayLineChartUsesPreviewDotSymbols() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricDayChart")?.lowerBound)
        let chartBlock = source[chartStart...].prefix(7_000)

        XCTAssertTrue(chartBlock.contains("BodyLineChartPreviewPointSymbol("))
        XCTAssertTrue(chartBlock.contains("isCurrent: isLatestEntry(entry)"))
        XCTAssertTrue(chartBlock.contains("pointDiameter: Self.pointDiameter"))
        XCTAssertTrue(chartBlock.contains("currentPointDiameter: Self.currentPointDiameter"))
        XCTAssertFalse(chartBlock.contains(".symbolSize(24)"))
    }

    func testHeartRateVariabilityDayChartUsesSleepAndWorkoutContextOverlay() throws {
        let source = try bodyHomeViewText()
        let detailStart = try XCTUnwrap(
            source.range(of: "case .heartRateVariability:\n            return metricDetail(")?.lowerBound
        )
        let detailBlock = String(source[detailStart...].prefix(900))
        let contextStart = try XCTUnwrap(source.range(of: "private var selectedMetricDayContextIntervals")?.lowerBound)
        let contextBlock = String(source[contextStart...].prefix(2_400))
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricDayChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(5_000))

        XCTAssertTrue(detailBlock.contains("sleepHistory: trends.sleepHistory"))
        XCTAssertTrue(contextBlock.contains("model.kind == .heartRate || model.kind == .heartRateVariability"))
        XCTAssertTrue(contextBlock.contains("sleepSummary(for: selectedMetricDay)?.stageSnapshot.dateInterval"))
        XCTAssertTrue(contextBlock.contains(#"symbolName: "bed.double.fill""#))
        XCTAssertFalse(contextBlock.contains(#"symbolName: "moon.fill""#))
        XCTAssertTrue(contextBlock.contains("workouts(on: dayInterval)"))
        XCTAssertTrue(contextBlock.contains("color: workout.type.color"))
        XCTAssertFalse(contextBlock.contains("color: Color(red: 1.00, green: 0.38, blue: 0.12)"))
        XCTAssertTrue(chartBlock.contains(".foregroundStyle(interval.color)"))
        XCTAssertFalse(chartBlock.contains("interval.kind == .sleep ? Color.white : interval.color"))
    }

    func testMetricCardPreviewStylesMatchRequestedChartKinds() throws {
        let source = try bodyHomeViewText()
        let previewBlock = String(source[
            try XCTUnwrap(source.range(of: "struct BodyHealthMetricCardTrendPreview")?.lowerBound)...
        ].prefix(8_000))
        let heartRateCardStart = try XCTUnwrap(
            source.range(of: "kind: .heartRate,\n                title: \"Heart Rate\"")?.lowerBound
        )
        let restingHeartRateCardStart = try XCTUnwrap(source.range(of: "kind: .restingHeartRate,")?.lowerBound)
        let heartRateCardBlock = String(source[heartRateCardStart..<restingHeartRateCardStart])
        let heartRateVariabilityCardStart = try XCTUnwrap(source.range(of: "kind: .heartRateVariability,")?.lowerBound)
        let oxygenCardStart = try XCTUnwrap(source.range(of: "kind: .oxygenSaturation,")?.lowerBound)
        let heartRateVariabilityCardBlock = String(source[heartRateVariabilityCardStart..<oxygenCardStart])

        XCTAssertTrue(heartRateCardBlock.contains("chartPreview: trends.series(for: .heartRate)"))
        XCTAssertFalse(heartRateCardBlock.contains("chartRangePreview: trends.rangeSeries(for: .heartRate)"))
        XCTAssertFalse(heartRateCardBlock.contains("chartPreviewStyle: .range"))
        XCTAssertTrue(heartRateVariabilityCardBlock.contains("chartPreview: trends.series(for: .heartRateVariability)"))
        XCTAssertFalse(heartRateVariabilityCardBlock.contains("chartRangePreview: trends.rangeSeries(for: .heartRateVariability)"))
        XCTAssertFalse(heartRateVariabilityCardBlock.contains("chartPreviewStyle: .range"))
        XCTAssertTrue(source.contains("chartRangePreview: trends.rangeSeries(for: .oxygenSaturation)"))
        XCTAssertTrue(source.contains("chartRangePreview: trends.rangeSeries(for: .respiratoryRate)"))
        XCTAssertTrue(source.contains("chartPreviewStyle: .range"))
        XCTAssertTrue(previewBlock.contains("case .range:"))
        XCTAssertTrue(previewBlock.contains("rangePreview"))
        // The card model precomputes the preview points once (instead of the
        // preview view regrouping the series per render); the preview then
        // consumes the prepared range points.
        XCTAssertTrue(source.contains("BodyHomeMetricCardPreview.rangeCalendarPoints(from: $0, previewDayCount: previewDayCount)"))
        XCTAssertTrue(previewBlock.contains("let rangeCalendarPoints: [HealthTrendRangeCalendarPoint]"))
        XCTAssertTrue(previewBlock.contains("RoundedRectangle(cornerRadius: 2, style: .continuous)"))
        XCTAssertTrue(previewBlock.contains("Capsule(style: .continuous)"))
    }

    func testHeartRateRangeChartUsesStandardBarSelectionRule() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyHeartRateRangeTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(18_000))

        XCTAssertTrue(source.contains("private var usesRangeTrendChart: Bool"))
        XCTAssertTrue(source.contains("model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .oxygenSaturation || model.kind == .respiratoryRate"))
        XCTAssertTrue(source.contains("rangeSeries: workoutStore.healthTrends.rangeSeries(for: kind)"))
        XCTAssertTrue(source.contains("yDomain: metricRangeYDomain"))
        XCTAssertTrue(source.contains("return BodyHealthMetricRangeYDomain.bloodOxygen"))
        XCTAssertTrue(source.contains("return BodyHealthMetricRangeYDomain.respiratoryRate"))
        XCTAssertTrue(source.contains("ceil(minimum / 5) * 5 - 5"))
        XCTAssertTrue(source.contains("ceil(maximum / 5) * 5"))
        XCTAssertFalse(source.contains("floor((minimum - 5) / 5) * 5"))
        XCTAssertTrue(source.contains("showsAverageLineOverlay: model.kind == .heartRate || model.kind == .heartRateVariability"))
        XCTAssertTrue(chartBlock.contains("let showsAverageLineOverlay: Bool"))
        XCTAssertTrue(chartBlock.contains("private var rangeBarColor: Color"))
        XCTAssertTrue(chartBlock.contains("showsAverageLineOverlay ? Color.secondary.opacity(0.24) : symbolColor"))
        XCTAssertTrue(chartBlock.contains("private var averageLineOverlay: some ChartContent"))
        XCTAssertTrue(chartBlock.contains("LineMark("))
        XCTAssertTrue(chartBlock.contains(#"y: .value("Average \(title)", entry.value)"#))
        XCTAssertTrue(chartBlock.contains("BodyLineChartPreviewPointSymbol("))
        XCTAssertTrue(source.contains("} else if usesRangeTrendChart, let visibleMetricRangeSeries {"))
        XCTAssertTrue(chartBlock.contains("if let selectedRangePoint {\n                    RuleMark(x: .value(\"Selected Date\", selectedRangePoint.date, unit: .day))"))
        XCTAssertTrue(chartBlock.contains(".foregroundStyle(Color.secondary.opacity(0.48))"))
        XCTAssertTrue(chartBlock.contains(".lineStyle(StrokeStyle(lineWidth: 1.4))"))
        XCTAssertTrue(chartBlock.contains(".foregroundStyle(rangeBarColor)"))
        XCTAssertFalse(chartBlock.contains(".foregroundStyle(symbolColor.opacity(0.68))"))
        XCTAssertFalse(chartBlock.contains("width: .fixed(chartBarWidth + 5)"))
        XCTAssertFalse(chartBlock.contains(".foregroundStyle(Color.secondary.opacity(0.30))"))
    }

    func testWristTemperatureCardUsesLineChartDetailWithoutDayView() throws {
        let source = try bodyHomeViewText()
        let cardStart = try XCTUnwrap(source.range(of: "private func wristTemperatureMetric")?.lowerBound)
        let cardBlock = String(source[cardStart...].prefix(1_500))
        let factoryStart = try XCTUnwrap(source.range(of: "enum BodyHomeTrendCardFactory")?.lowerBound)
        let trendCardStart = try XCTUnwrap(
            source.range(of: "case .wristTemperature:", range: factoryStart..<source.endIndex)?.lowerBound
        )
        let trendCardBlock = String(source[trendCardStart...].prefix(1_100))
        let detailStart = try XCTUnwrap(source.range(of: "case .wristTemperature:")?.lowerBound)
        let detailBlock = String(source[detailStart...].prefix(3_000))
        let dayViewStart = try XCTUnwrap(source.range(of: "private var supportsMetricDayView")?.lowerBound)
        let dayViewBlock = String(source[dayViewStart...].prefix(700))

        XCTAssertTrue(cardBlock.contains(#"title: "Skin Temp""#))
        XCTAssertEqual(source.components(separatedBy: #"title: "Skin Temp""#).count - 1, 1)
        XCTAssertTrue(cardBlock.contains("chartPreviewStyle: .line"))
        XCTAssertTrue(trendCardBlock.contains(#"title: "Skin Temperature""#))
        XCTAssertTrue(detailBlock.contains(#"title: "Skin Temperature""#))
        XCTAssertTrue(detailBlock.contains("series: trends.wristTemperature.mapValues"))
        XCTAssertTrue(detailBlock.contains("daySeries: .empty"))
        XCTAssertTrue(detailBlock.contains("chartStyle: .line"))
        XCTAssertTrue(dayViewBlock.contains(".wristTemperature"))
    }

    func testTrainingLoadCardUsesLineChartWithCurrentIntervalWithoutUnitsOrDayView() throws {
        let source = try bodyHomeViewText()
        let cardStart = try XCTUnwrap(source.range(of: "metric(\n                kind: .trainingLoad")?.lowerBound)
        let cardBlock = String(source[cardStart...].prefix(1_100))
        let factoryStart = try XCTUnwrap(source.range(of: "enum BodyHomeTrendCardFactory")?.lowerBound)
        let trendCardStart = try XCTUnwrap(
            source.range(of: "case .trainingLoad:", range: factoryStart..<source.endIndex)?.lowerBound
        )
        let trendCardBlock = String(source[trendCardStart...].prefix(1_100))
        let detailStart = try XCTUnwrap(source.range(of: "case .trainingLoad:")?.lowerBound)
        let detailBlock = String(source[detailStart...].prefix(900))
        let dayViewStart = try XCTUnwrap(source.range(of: "private var supportsMetricDayView")?.lowerBound)
        let dayViewBlock = String(source[dayViewStart...].prefix(800))

        XCTAssertTrue(cardBlock.contains(#"title: "Training Load""#))
        XCTAssertTrue(cardBlock.contains(#"unit: """#))
        XCTAssertTrue(cardBlock.contains("decimals: 2"))
        XCTAssertFalse(cardBlock.contains(#"unit: "load""#))
        XCTAssertTrue(cardBlock.contains("chartStyle: .line"))
        XCTAssertTrue(cardBlock.contains("chartPreview: trends.series(for: .trainingLoad)"))
        XCTAssertTrue(trendCardBlock.contains(#"title: "Training Load""#))
        XCTAssertTrue(trendCardBlock.contains("chartStyle: .line"))
        XCTAssertTrue(trendCardBlock.contains("series: trends.series(for: .trainingLoad)"))
        XCTAssertTrue(trendCardBlock.contains("valueFormatter: { BodyValueFormat.numberText($0, decimals: 2) }"))
        XCTAssertFalse(trendCardBlock.contains(#"+ " load""#))
        XCTAssertTrue(detailBlock.contains(#"title: "Training Load""#))
        XCTAssertTrue(detailBlock.contains("summary: summary.trainingLoad"))
        XCTAssertTrue(detailBlock.contains(#"unit: """#))
        XCTAssertTrue(detailBlock.contains("decimals: 2"))
        XCTAssertFalse(detailBlock.contains(#"unit: "load""#))
        XCTAssertTrue(detailBlock.contains("chartStyle: .line"))
        XCTAssertTrue(detailBlock.contains("let trainingLoadInterval = BodyTrainingLoadIntervalPresentation.make(for: summary.trainingLoad.value)"))
        XCTAssertTrue(detailBlock.contains("highlightedRange: trainingLoadInterval"))
        XCTAssertTrue(detailBlock.contains("highlightedRangeResolver: BodyTrainingLoadIntervalPresentation.make(for:)"))
        XCTAssertTrue(dayViewBlock.contains(".trainingLoad"))
    }

    func testTrainingLoadTrendChartDrawsDynamicHorizontalCurrentIntervalBandWithoutInlineLabel() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(12_000))

        XCTAssertTrue(chartBlock.contains("let highlightedRange: BodyHealthMetricTrendHighlightedRange?"))
        XCTAssertTrue(chartBlock.contains("let highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)?"))
        XCTAssertTrue(chartBlock.contains("let displayedHighlightedRange = activeHighlightedRange"))
        XCTAssertTrue(chartBlock.contains("if let highlightedRange = displayedHighlightedRange,"))
        XCTAssertTrue(chartBlock.contains("private var activeHighlightedRange: BodyHealthMetricTrendHighlightedRange?"))
        XCTAssertTrue(chartBlock.contains("guard let highlightedRangeResolver, let activeHighlightSourcePoint else {"))
        XCTAssertTrue(chartBlock.contains("return highlightedRangeResolver(activeHighlightSourcePoint.value) ?? highlightedRange"))
        XCTAssertTrue(chartBlock.contains("private var activeHighlightSourcePoint: HealthTrendCalendarPoint?"))
        XCTAssertTrue(chartBlock.contains("selectedTrendPoint ?? latestVisibleTrendPoint"))
        XCTAssertTrue(chartBlock.contains("private var latestVisibleTrendPoint: HealthTrendCalendarPoint?"))
        XCTAssertTrue(chartBlock.contains("visibleFinitePoints.last"))
        XCTAssertTrue(chartBlock.contains(".chartBackground { chartProxy in"))
        XCTAssertTrue(chartBlock.contains("highlightedRange.lowerPlotBound(in: chartYDomain)"))
        XCTAssertTrue(chartBlock.contains("highlightedRange.upperPlotBound(in: chartYDomain)"))
        XCTAssertTrue(chartBlock.contains(".fill(highlightedRange.color.opacity(0.12))"))
        XCTAssertTrue(chartBlock.contains(".fill(highlightedRange.color.opacity(0.72))"))
        XCTAssertTrue(chartBlock.contains("highlightedRangeValues"))
        XCTAssertFalse(chartBlock.contains("Text(highlightedRange.title)"))
        XCTAssertFalse(chartBlock.contains("Highlighted Range Label"))
    }

    func testTrainingLoadDetailShowsIntervalDayBreakdownBelowLineChart() throws {
        let source = try bodyHomeViewText()
        // The day breakdown renders in `metricBreakdownChart`, placed below the hero
        // value row (which sits below the line chart) — so the big current value reads
        // directly under the line chart and the breakdown bars sit beneath it.
        let breakdownContainerStart = try XCTUnwrap(source.range(of: "private var metricBreakdownChart")?.lowerBound)
        let breakdownContainerBlock = String(source[breakdownContainerStart...].prefix(1_200))
        let breakdownStart = try XCTUnwrap(source.range(of: "struct BodyTrainingLoadIntervalBreakdownChart")?.lowerBound)
        let breakdownBlock = String(source[breakdownStart...].prefix(4_500))

        // Within the hero, the value row precedes the breakdown bars.
        let heroStart = try XCTUnwrap(source.range(of: "private var metricHero: some View")?.lowerBound)
        let heroEnd = try XCTUnwrap(
            source.range(of: "private var metricDetailCards", range: heroStart..<source.endIndex)?.lowerBound
        )
        let heroBlock = String(source[heroStart..<heroEnd])
        let valueRowIndex = try XCTUnwrap(heroBlock.range(of: "metricHeroValueRow")?.lowerBound)
        let breakdownIndex = try XCTUnwrap(heroBlock.range(of: "metricBreakdownChart")?.lowerBound)
        XCTAssertLessThan(valueRowIndex, breakdownIndex)

        XCTAssertTrue(breakdownContainerBlock.contains("if model.kind == .trainingLoad {"))
        XCTAssertTrue(breakdownContainerBlock.contains("BodyTrainingLoadIntervalBreakdownChart("))
        XCTAssertTrue(breakdownContainerBlock.contains("series: model.series"))
        XCTAssertTrue(breakdownContainerBlock.contains("selectedRange: selectedTrendRange"))
        XCTAssertTrue(breakdownBlock.contains("TrainingLoadIntervalBreakdown.entries("))
        XCTAssertTrue(breakdownBlock.contains("GeometryReader { geometry in"))
        XCTAssertTrue(breakdownBlock.contains("RoundedRectangle(cornerRadius: barCornerRadius"))
        XCTAssertTrue(breakdownBlock.contains("dayCountText(for: entry.dayCount)"))
        XCTAssertTrue(breakdownBlock.contains("entry.interval.title"))
        XCTAssertTrue(breakdownBlock.contains("entry.interval.symbolName"))
    }

    func testSummaryMetricValuesUseClockStyleNumericTransitions() throws {
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("struct BodyAnimatedMetricValueText: View"))
        XCTAssertTrue(source.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(source.contains(".contentTransition(reduceMotion ? .identity : .numericText())"))
        XCTAssertTrue(source.contains(".monospacedDigit()"))
        XCTAssertTrue(source.contains(".animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: value)"))
        XCTAssertGreaterThanOrEqual(source.occurrenceCount(of: "BodyAnimatedMetricValueText("), 3)
    }

    func testActivityRingGraphicAnimatesProgressWithCircularSweep() throws {
        let source = try text(at: "Body/Views/BodyActivityRingsDetailView.swift")
        let graphicStart = try XCTUnwrap(source.range(of: "private struct BodyActivityRingGraphic")?.lowerBound)
        let graphicBlock = String(source[graphicStart...].prefix(2_400))
        let arcStart = try XCTUnwrap(source.range(of: "private struct BodyActivityRingArc")?.lowerBound)
        let arcBlock = String(source[arcStart...].prefix(4_200))

        XCTAssertTrue(graphicBlock.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(graphicBlock.contains("private func sweepAnimation(ringIndex: Int) -> Animation?"))
        XCTAssertEqual(graphicBlock.occurrenceCount(of: "animation: sweepAnimation(ringIndex:"), 3)
        XCTAssertTrue(graphicBlock.contains(".smooth(duration: 0.75, extraBounce: 0)"))
        XCTAssertTrue(graphicBlock.contains(".delay(Double(ringIndex) * 0.05)"))
        XCTAssertTrue(source.contains("private struct BodyActivityRingHeadPosition: GeometryEffect"))
        XCTAssertTrue(source.contains("var animatableData: Double"))
        XCTAssertTrue(arcBlock.contains(".modifier(BodyActivityRingHeadPosition(progress: animatedHeadProgress, radius: radius))"))
        XCTAssertTrue(arcBlock.contains("setAnimatedProgress(nextProgress, animation: animation)"))
    }

    func testSupportedMetricDetailScreensExposeSwitchableDataSources() throws {
        let source = try bodyHomeViewText()
        let detailViewStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricDetailView")?.lowerBound)
        let pickerStart = try XCTUnwrap(source.range(of: "struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        // The detail view file is concatenated immediately before the picker sheet, so
        // bound the block by the picker declaration rather than a fixed char window the
        // ever-growing detail view keeps outrunning.
        let detailViewBlock = String(source[detailViewStart..<pickerStart])
        let pickerBlock = String(source[pickerStart...].prefix(8_000))

        XCTAssertTrue(detailViewBlock.contains("model.kind.supportsHealthDataSourceSelection"))
        XCTAssertTrue(detailViewBlock.contains("workoutStore.selectedHealthDataSourceOption(for: model.kind)"))
        XCTAssertTrue(detailViewBlock.contains("BodyHealthDataSourcePickerSheet("))
        XCTAssertTrue(pickerBlock.contains("workoutStore.healthDataSourceOptions(for: kind)"))
        XCTAssertTrue(pickerBlock.contains("workoutStore.updateHealthDataSource(for: kind, option: option)"))
    }

    func testMetricDetailViewGatesProRangesAndDays() throws {
        let source = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")

        // Chart-range gate: non-Pro is clamped to Week, and the selector binds to that
        // effective range so a locked pill can't appear selected; locked taps route to
        // the paywall, not the binding.
        XCTAssertTrue(source.contains("isBodyProUnlocked ? selectedTrendRangeSelection : .recentWeek"))
        XCTAssertTrue(source.contains("get: { selectedTrendRange }"))
        XCTAssertTrue(source.contains("isProUnlocked: isBodyProUnlocked"))
        XCTAssertTrue(source.contains("onLockedRangeTap: { showBodyProPaywall = true }"))

        // Day-picker gate: a 3-day free window, and the effective selected day is clamped
        // so a locked day never renders.
        XCTAssertTrue(source.contains("static let freeDatePickerDayCount = 3"))
        XCTAssertTrue(source.contains("func isDatePickerDateLocked"))
        XCTAssertTrue(source.contains("func clampedDatePickerDay"))
        XCTAssertTrue(source.contains("clampedDatePickerDay(selectedMetricDate)"))
        XCTAssertTrue(source.contains("clampedDatePickerDay(selectedSleepDate)"))

        // Every day-selection surface routes through the shared guard, which opens the
        // paywall for a locked day *before* it can reach selectDate.
        let guardStart = try XCTUnwrap(source.range(of: "private func selectDatePickerDay")?.upperBound)
        let guardBlock = String(source[guardStart...].prefix(400))
        let paywallInGuard = try XCTUnwrap(guardBlock.range(of: "showBodyProPaywall = true"))
        let selectInGuard = try XCTUnwrap(guardBlock.range(of: "selectDate(date, for: picker)"))
        XCTAssertTrue(guardBlock.contains("isDatePickerDateLocked(date)"))
        XCTAssertLessThan(paywallInGuard.lowerBound, selectInGuard.lowerBound)
        // Both the date tiles and the Sleep Consistency chart call the guard, not selectDate.
        XCTAssertTrue(source.contains("selectDatePickerDay(dayStart, for: picker)"))
        XCTAssertTrue(source.contains("selectDatePickerDay(day, for: .sleep)"))
    }

    func testHealthDataSourcePickerRowsShowSourceNamesOnly() throws {
        let source = try bodyHomeViewText()
        let pickerStart = try XCTUnwrap(source.range(of: "struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        let pickerBlock = String(source[pickerStart...].prefix(8_000))

        XCTAssertTrue(pickerBlock.contains("Text(option.name)"))
        XCTAssertFalse(pickerBlock.contains("Only this source"))
        XCTAssertFalse(pickerBlock.contains("All available Apple Health sources"))
        XCTAssertFalse(pickerBlock.contains("Hide secondary comparison"))
        XCTAssertFalse(pickerBlock.contains("optionDetailText"))
    }

    func testHealthDataSourcePickerUsesTypedScopedUpdateState() throws {
        let source = try bodyHomeViewText()
        let pickerStart = try XCTUnwrap(source.range(of: "struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        let pickerBlock = String(source[pickerStart...].prefix(8_000))

        XCTAssertTrue(pickerBlock.contains("private enum SourceRole: Equatable"))
        XCTAssertTrue(pickerBlock.contains("private struct PendingSelection: Equatable"))
        XCTAssertTrue(pickerBlock.contains("@State private var updatingSelection: PendingSelection?"))
        XCTAssertTrue(pickerBlock.contains("role: SourceRole"))
        XCTAssertTrue(pickerBlock.contains("let isSelectionLocked = updatingSelection != nil"))
        XCTAssertTrue(pickerBlock.contains(".disabled(isSelected || isSelectionLocked)"))
        XCTAssertTrue(pickerBlock.contains("case .secondary:"))

        XCTAssertFalse(pickerBlock.contains("role: String"))
        XCTAssertFalse(pickerBlock.contains("updatingSelectionID"))
        XCTAssertFalse(pickerBlock.contains(".disabled(updatingSelectionID != nil || isSelected)"))
        XCTAssertFalse(pickerBlock.contains("let isSectionLocked = updatingSelection?.role == role"))
        XCTAssertFalse(pickerBlock.contains("role == \"secondary\""))
    }

    func testHealthDataSourcePickerStaysOpenAfterChangingSelection() throws {
        let source = try bodyHomeViewText()
        let pickerStart = try XCTUnwrap(source.range(of: "struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        let pickerBlock = String(source[pickerStart...].prefix(8_000))
        let updateStart = try XCTUnwrap(pickerBlock.range(of: "private func updateSelection")?.lowerBound)
        let updateBlock = String(pickerBlock[updateStart...].prefix(1_200))

        XCTAssertTrue(pickerBlock.contains("Button(\"Done\")"))
        XCTAssertTrue(pickerBlock.contains("dismiss()"))
        XCTAssertTrue(updateBlock.contains("updatingSelection = nil"))
        XCTAssertFalse(updateBlock.contains("dismiss()"))
    }

    func testHealthKitFetchesApplySourcePreferencesToRequestedMetrics() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let engineSource = try healthKitFetchEngineText()

        XCTAssertTrue(storeSource.contains("fetchHealthDataSourceOptions(calendar: calendar)"))
        XCTAssertTrue(engineSource.contains("sourcePredicate(for: sourceKind)"))
        XCTAssertTrue(engineSource.contains("combinedPredicate(startDate:"))
        XCTAssertTrue(engineSource.contains("sourceKind: .heartRate"))
        XCTAssertTrue(engineSource.contains("sourceKind: .sleep"))
        XCTAssertTrue(engineSource.contains("sourceKind: .basics"))
        XCTAssertTrue(engineSource.contains("sourceKind: .heartRateVariability"))
        XCTAssertTrue(engineSource.contains("sourceKind: .restingHeartRate"))
        XCTAssertTrue(engineSource.contains("sourceKind: .respiratoryRate"))
        XCTAssertTrue(engineSource.contains("sourceKind: .steps"))
        XCTAssertTrue(engineSource.contains("sourceKind: .oxygenSaturation"))
        XCTAssertTrue(engineSource.contains("sourceKind: .activeEnergy"))
        XCTAssertTrue(engineSource.contains("sourceKind: .restingEnergy"))
        XCTAssertTrue(engineSource.contains("sourceKind: .exerciseMinutes"))
        XCTAssertTrue(engineSource.contains("sourceKind: .wristTemperature"))
        XCTAssertTrue(engineSource.contains("sourceKind: .timeInDaylight"))
        XCTAssertTrue(engineSource.contains("case .oxygenSaturation:"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .bodyMass)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .bodyMassIndex)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .oxygenSaturation)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .appleExerciseTime)"))
        XCTAssertTrue(engineSource.contains("HKSourceQuery("))
        XCTAssertTrue(engineSource.contains("HKQuery.predicateForObjects(from: source)"))
        XCTAssertTrue(engineSource.contains("NSCompoundPredicate(orPredicateWithSubpredicates: sourcePredicates)"))
        XCTAssertFalse(engineSource.contains("HKQuery.predicateForObjects(from: Set(sources))"))
        XCTAssertTrue(engineSource.contains("BodyHealthDataSourceOption.individualSourceIdentityKey"))
        XCTAssertTrue(engineSource.contains("BodyHealthDataSourceOption.individualSourceID"))
        XCTAssertTrue(engineSource.contains("sourcesByID[sourceID, default: []].append(source)"))
        XCTAssertFalse(engineSource.contains("sourcesByID[source.bundleIdentifier] = [source]"))
    }

    func testSourceSelectableBarAndRangeDetailsUsePrimarySecondaryComparisonCharts() throws {
        let homeSource = try bodyHomeViewText()
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let trendCardStart = try XCTUnwrap(homeSource.range(of: "private func metricTrendChart")?.lowerBound)
        let trendCardBlock = String(homeSource[trendCardStart...].prefix(10_000))
        let comparisonChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthSourceComparisonBarChart")?.lowerBound)
        let comparisonChartBlock = String(homeSource[comparisonChartStart...].prefix(8_500))
        let rangeComparisonChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthSourceComparisonRangeChart")?.lowerBound)
        let rangeComparisonChartBlock = String(homeSource[rangeComparisonChartStart...].prefix(8_000))
        let rangeBandChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHeartRateRangeTrendChart")?.lowerBound)
        let rangeBandChartBlock = String(homeSource[rangeBandChartStart...].prefix(14_000))

        // The source legend moved from the trend-card header to the hero value row
        // (`heroValueTrailing`); the comparison charts stay in `metricTrendChart`.
        XCTAssertTrue(homeSource.contains("BodyHealthSourceLegend("))
        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceComparisonBarChart("))
        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceComparisonRangeChart("))
        XCTAssertTrue(trendCardBlock.contains("model.kind.usesSourceComparisonRangeBandLineChart"))
        XCTAssertTrue(trendCardBlock.contains("secondaryRangeSeries: sourceRangeComparisonTrend.secondary.series"))
        XCTAssertTrue(trendCardBlock.contains("sourceComparisonTrend"))
        XCTAssertTrue(trendCardBlock.contains("sourceRangeComparisonTrend"))
        XCTAssertTrue(homeSource.contains("Color(red: 0.58, green: 0.36, blue: 0.98)"))
        XCTAssertTrue(appearanceSource.contains("var usesSourceComparisonRangeBandLineChart: Bool"))
        XCTAssertTrue(comparisonChartBlock.contains("chartDate: point.date.addingTimeInterval"))
        // The Week pair is nudged fully into the day's column (both bars right of the
        // midnight gridline) instead of straddling it.
        XCTAssertTrue(comparisonChartBlock.contains("let pairShift: TimeInterval = selectedRange.sourceComparisonChartAggregationDayCount == 1 ? dateOffset * 2 : 0"))
        XCTAssertTrue(comparisonChartBlock.contains("chartDate: point.date.addingTimeInterval(pairShift - dateOffset)"))
        XCTAssertTrue(rangeComparisonChartBlock.contains("let pairShift: TimeInterval = selectedRange.sourceComparisonChartAggregationDayCount == 1 ? dateOffset * 2 : 0"))
        XCTAssertTrue(comparisonChartBlock.contains("x: .value(\"Date\", entry.chartDate)"))
        XCTAssertFalse(comparisonChartBlock.contains(".position(by: .value(\"Source\", entry.sourceRole.rawValue), axis: .horizontal)"))
        XCTAssertTrue(comparisonChartBlock.contains("sourceComparisonChartBarWidth(forAvailableWidth:"))
        XCTAssertTrue(comparisonChartBlock.contains("sourceComparisonChartCalendarPoints(to: selectedRange)"))
        XCTAssertTrue(comparisonChartBlock.contains("BodyChartSelectionValue("))
        XCTAssertTrue(rangeBandChartBlock.contains("secondaryRangePoints"))
        XCTAssertTrue(rangeBandChartBlock.contains("BarMark("))
        XCTAssertTrue(rangeBandChartBlock.contains("series: .value(\"Source\", entry.sourceRole.rawValue)"))
        XCTAssertTrue(rangeBandChartBlock.contains("BodyChartSelectionValue("))
        XCTAssertTrue(rangeComparisonChartBlock.contains("sourceComparisonRangeChartBarWidth(forAvailableWidth:"))
        XCTAssertTrue(rangeComparisonChartBlock.contains("sourceComparisonChartCalendarPoints(to: selectedRange)"))
        XCTAssertTrue(rangeComparisonChartBlock.contains("x: .value(\"Date\", entry.chartDate)"))
        XCTAssertTrue(storeSource.contains("func sourceComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceComparisonTrend?"))
        XCTAssertTrue(storeSource.contains("func sourceRangeComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceRangeComparisonTrend?"))
    }

    func testSourceSelectableLineDetailsUsePrimarySecondaryComparisonLines() throws {
        let homeSource = try bodyHomeViewText()
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let trendCardStart = try XCTUnwrap(homeSource.range(of: "private func metricTrendChart")?.lowerBound)
        let trendCardBlock = String(homeSource[trendCardStart...].prefix(9_000))
        let lineComparisonChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthSourceComparisonLineChart")?.lowerBound)
        let lineComparisonChartBlock = String(homeSource[lineComparisonChartStart...].prefix(10_000))

        XCTAssertTrue(appearanceSource.contains("var usesSourceComparisonLineChart: Bool"))
        XCTAssertTrue(trendCardBlock.contains("sourceLineComparisonTrend"))
        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceComparisonLineChart("))
        XCTAssertTrue(lineComparisonChartBlock.contains("comparison.primary.series.lineChartCalendarPoints(to: selectedRange)"))
        XCTAssertTrue(lineComparisonChartBlock.contains("comparison.secondary.series.lineChartCalendarPoints(to: selectedRange)"))
        XCTAssertTrue(lineComparisonChartBlock.contains("series: .value(\"Source\", entry.sourceRole.rawValue)"))
        XCTAssertTrue(lineComparisonChartBlock.contains("BodyChartSelectionValue("))
        XCTAssertTrue(storeSource.contains("func sourceLineComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceComparisonTrend?"))
    }

    func testSleepStageComparisonCardsShowTrailingSourceLabel() throws {
        let homeSource = try bodyHomeViewText()
        let selectedSleepCardsStart = try XCTUnwrap(
            homeSource.range(of: "private var selectedSleepCards: some View")?.lowerBound
        )
        let selectedSleepCardsBlock = String(homeSource[selectedSleepCardsStart...].prefix(2_500))
        let sleepStageCardStart = try XCTUnwrap(homeSource.range(of: "private func sleepStageCard")?.lowerBound)
        let sleepStageCardBlock = String(homeSource[sleepStageCardStart...].prefix(2_500))
        let sleepStageCardAndSummaryBlock = String(homeSource[sleepStageCardStart...].prefix(5_500))

        XCTAssertTrue(selectedSleepCardsBlock.contains("sourceName: sourceLineComparisonTrend.primary.sourceName"))
        XCTAssertTrue(selectedSleepCardsBlock.contains("sourceName: sourceLineComparisonTrend.secondary.sourceName"))
        XCTAssertFalse(selectedSleepCardsBlock.contains("title: \"Sleep Stages -"))
        XCTAssertTrue(sleepStageCardBlock.contains("sourceName: String? = nil"))
        XCTAssertTrue(sleepStageCardBlock.contains("HStack(alignment: .firstTextBaseline)"))
        XCTAssertTrue(sleepStageCardBlock.contains("Spacer(minLength: 12)"))
        XCTAssertTrue(sleepStageCardBlock.contains("if let sourceName"))
        XCTAssertTrue(sleepStageCardBlock.contains("Text(sourceName)"))
        XCTAssertTrue(sleepStageCardBlock.contains(".font(.system(.caption, design: .rounded))"))
        XCTAssertTrue(sleepStageCardBlock.contains(".foregroundColor(.secondary)"))

        let sleepChartStart = try XCTUnwrap(homeSource.range(of: "struct BodySleepStageChart")?.lowerBound)
        let sleepChartBlock = String(homeSource[sleepChartStart...].prefix(4_000))
        XCTAssertTrue(sleepChartBlock.contains("Text(stage.axisLabel)"))
        // The summary call now lives inside the tap-to-toggle Button (durations <-> optimal
        // ranges), a little deeper in the card body, so widen the inspected window.
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("sleepStageDurationSummary(snapshot)"))
        // The restorative-sleep breakdown wraps the stage row in a VStack and
        // spaces stages with explicit Spacers (HStack(spacing: 0) + enumerated
        // ForEach) rather than the old fixed-spacing HStack.
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("HStack(spacing: 0)"))
        XCTAssertFalse(sleepStageCardAndSummaryBlock.contains("LazyVGrid"))
        XCTAssertFalse(sleepStageCardAndSummaryBlock.contains("GridItem(.flexible(), spacing: 10)"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("ForEach(Array(SleepStage.allCases.enumerated()), id: \\.element)"))
        XCTAssertFalse(sleepStageCardAndSummaryBlock.contains("Text(stage.displayName)"))
        XCTAssertFalse(sleepStageCardAndSummaryBlock.contains("Circle()"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("Rectangle()"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains(".frame(width: 28, height: 3)"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("BodyValueFormat.durationText(for: snapshot.duration(for: stage))"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("VStack(alignment: .center, spacing: 7)"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains(".frame(maxWidth: .infinity, alignment: .center)"))
    }

    func testSleepDetailHeaderValuesUseNumericTransitions() throws {
        let source = try bodyHomeViewText()
        let sleepStageCardStart = try XCTUnwrap(source.range(of: "private func sleepStageCard")?.lowerBound)
        let sleepStageCardEnd = try XCTUnwrap(
            source.range(of: "private func sleepStageDurationSummary", range: sleepStageCardStart..<source.endIndex)?.lowerBound
        )
        let sleepStageCardBlock = String(source[sleepStageCardStart..<sleepStageCardEnd])
        let sleepConsistencyCardStart = try XCTUnwrap(source.range(of: "private var sleepConsistencyCard")?.lowerBound)
        let sleepConsistencyCardEnd = try XCTUnwrap(
            source.range(of: "private var sleepConsistencyChartModel", range: sleepConsistencyCardStart..<source.endIndex)?.lowerBound
        )
        let sleepConsistencyCardBlock = String(source[sleepConsistencyCardStart..<sleepConsistencyCardEnd])

        XCTAssertTrue(sleepStageCardBlock.contains("BodyAnimatedMetricValueText("))
        XCTAssertTrue(sleepStageCardBlock.contains("value: BodyValueFormat.sleepDurationText(for: snapshot.asleepDuration)"))
        XCTAssertTrue(sleepConsistencyCardBlock.contains("BodyAnimatedMetricValueText("))
        XCTAssertTrue(sleepConsistencyCardBlock.contains(#"value: "\(consistencyPercentage)%""#))
    }

    func testSleepStageBreakdownTogglesToOptimalRangeChart() throws {
        let source = try bodyHomeViewText()
        let appearanceSource = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private func sleepStageCard")?.lowerBound)
        let cardEnd = try XCTUnwrap(
            source.range(of: "private func sleepStageDurationSummary", range: cardStart..<source.endIndex)?.lowerBound
        )
        let cardBlock = String(source[cardStart..<cardEnd])

        // Persisted toggle key + property (defaults to the existing duration summary).
        XCTAssertTrue(appearanceSource.contains(#"static let sleepStageBreakdownShowsOptimalRangesKey = "sleepStageBreakdownShowsOptimalRanges""#))
        XCTAssertTrue(source.contains("@AppStorage(BodyAppearancePreference.sleepStageBreakdownShowsOptimalRangesKey) private var sleepStageShowsOptimalRanges = false"))

        // Tap-to-swap wiring lives inside sleepStageCard (durations <-> optimal ranges).
        XCTAssertTrue(cardBlock.contains("if sleepStageShowsOptimalRanges {"))
        XCTAssertTrue(cardBlock.contains("BodySleepStageOptimalRangeChart(snapshot: snapshot)"))
        XCTAssertTrue(cardBlock.contains("sleepStageDurationSummary(snapshot)"))
        XCTAssertTrue(cardBlock.contains("sleepStageShowsOptimalRanges.toggle()"))
        XCTAssertTrue(cardBlock.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(cardBlock.contains(".buttonStyle(.plain)"))

        // The collapsed Button keeps the per-stage values readable to VoiceOver via a spelled-out label.
        XCTAssertTrue(cardBlock.contains(".accessibilityLabel(sleepStageBreakdownAccessibilityLabel(snapshot))"))
        XCTAssertTrue(source.contains("private func sleepStageBreakdownAccessibilityLabel"))
        XCTAssertFalse(cardBlock.contains(#".accessibilityLabel(sleepStageShowsOptimalRanges ? "Stage optimal ranges""#))

        // New chart + display-only optimal bands (percent of time in bed).
        XCTAssertTrue(source.contains("struct BodySleepStageOptimalRangeChart: View"))
        XCTAssertTrue(source.contains("var optimalPercentageRange: ClosedRange<Double>"))
        XCTAssertTrue(source.contains("return 0.00...0.05"))
        XCTAssertTrue(source.contains("return 0.20...0.25"))
        XCTAssertTrue(source.contains("return 0.45...0.55"))
        XCTAssertTrue(source.contains("return 0.13...0.23"))
        XCTAssertTrue(source.contains(#"Text("Optimal Range")"#))

        // Bars grow/shrink when the selected day changes, gated on reduce-motion.
        let chartStart = try XCTUnwrap(source.range(of: "struct BodySleepStageOptimalRangeChart")?.lowerBound)
        let chartEnd = try XCTUnwrap(
            source.range(of: "struct BodySleepConsistencyChart", range: chartStart..<source.endIndex)?.lowerBound
        )
        let chartBlock = String(source[chartStart..<chartEnd])
        XCTAssertTrue(chartBlock.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(chartBlock.contains(".animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: fraction)"))
    }

    func testSourceSelectableDayChartsUsePrimarySecondaryComparisonLines() throws {
        let homeSource = try bodyHomeViewText()
        let engineSource = try healthKitFetchEngineText()
        let snapshotSource = try healthSummarySnapshotText()
        let dayChartCardStart = try XCTUnwrap(homeSource.range(of: "private var metricDayChartCard: some View")?.lowerBound)
        let dayChartCardBlock = String(homeSource[dayChartCardStart...].prefix(3_500))
        let dayChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthMetricDayChart")?.lowerBound)
        let dayChartBlock = String(homeSource[dayChartStart...].prefix(12_000))

        XCTAssertTrue(dayChartCardBlock.contains("BodyHealthSourceLegend("))
        XCTAssertTrue(dayChartCardBlock.contains("selectedMetricSecondaryDaySeries"))
        XCTAssertTrue(dayChartCardBlock.contains("secondarySeries: selectedMetricSecondaryDaySeries"))
        XCTAssertTrue(dayChartBlock.contains("secondaryHourlyBuckets"))
        XCTAssertTrue(dayChartBlock.contains("series: .value(\"Segment\", entry.seriesKey)"))
        XCTAssertTrue(dayChartBlock.contains("BodyChartSelectionValue("))
        XCTAssertTrue(snapshotSource.contains("func secondaryDaySeries(for kind: HealthMetricKind) -> HealthTrendSeries"))
        XCTAssertTrue(engineSource.contains("func fetchSecondaryDaySamples("))
        XCTAssertTrue(engineSource.contains("for kind: HealthMetricKind,"))
        XCTAssertTrue(engineSource.contains("let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)"))
        XCTAssertTrue(engineSource.contains("sourceOption: secondaryOption"))
        XCTAssertTrue(engineSource.contains("trends.heartRateDaySamplesSecondary = await heartRateDaySamplesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.restingHeartRateDaySamplesSecondary = await restingHeartRateDaySamplesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.heartRateVariabilityDaySamplesSecondary = await heartRateVariabilityDaySamplesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.oxygenSaturationDaySamplesSecondary = await oxygenSaturationDaySamplesSecondary"))
    }

    func testChartLegendHeadersFillAvailableWidth() throws {
        let source = try bodyHomeViewText()
        // The trend chart's "Last 7 Days" header was removed when it folded into the
        // gradient hero; only the metric day-chart card still carries a legend header.
        let dayChartCardStart = try XCTUnwrap(source.range(of: "private var metricDayChartCard: some View")?.lowerBound)
        let dayChartStart = try XCTUnwrap(
            source.range(of: "if selectedMetricDaySeries.isEmpty", range: dayChartCardStart..<source.endIndex)?.lowerBound
        )
        let dayHeaderBlock = String(source[dayChartCardStart..<dayChartStart])

        XCTAssertTrue(dayHeaderBlock.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
    }

    func testSourceLegendContentIsTrailingAligned() throws {
        let source = try bodyHomeViewText()
        let legendStart = try XCTUnwrap(source.range(of: "struct BodyHealthSourceLegend: View")?.lowerBound)
        let comparisonChartStart = try XCTUnwrap(
            source.range(of: "struct BodyHealthSourceComparisonLineChart", range: legendStart..<source.endIndex)?.lowerBound
        )
        let legendBlock = String(source[legendStart..<comparisonChartStart])

        XCTAssertTrue(legendBlock.contains("VStack(alignment: .trailing, spacing: 7)"))
        XCTAssertTrue(legendBlock.contains(".frame(maxWidth: 180, alignment: .trailing)"))
        XCTAssertFalse(legendBlock.contains("VStack(alignment: .leading, spacing: 7)"))
        XCTAssertFalse(legendBlock.contains(".frame(maxWidth: 180, alignment: .leading)"))
    }

    func testTwoLineHeroLegendsUseBottomRowAnchoring() throws {
        let source = try bodyHomeViewText()
        let sourceLegendStart = try XCTUnwrap(source.range(of: "struct BodyHealthSourceLegend: View")?.lowerBound)
        let sourceLegendEnd = try XCTUnwrap(
            source.range(of: "struct BodyHealthSourceComparisonLineChart", range: sourceLegendStart..<source.endIndex)?.lowerBound
        )
        let sourceLegendBlock = String(source[sourceLegendStart..<sourceLegendEnd])
        let basicsLegendStart = try XCTUnwrap(source.range(of: "struct BodyBasicsTrendLegend: View")?.lowerBound)
        let basicsLegendEnd = try XCTUnwrap(
            source.range(of: "struct BodyChartSelectionValue", range: basicsLegendStart..<source.endIndex)?.lowerBound
        )
        let basicsLegendBlock = String(source[basicsLegendStart..<basicsLegendEnd])
        let heroTrailingStart = try XCTUnwrap(source.range(of: "private var heroValueTrailing: some View")?.lowerBound)
        let heroTrailingEnd = try XCTUnwrap(
            source.range(of: "private func metricTrendChart", range: heroTrailingStart..<source.endIndex)?.lowerBound
        )
        let heroTrailingBlock = String(source[heroTrailingStart..<heroTrailingEnd])

        XCTAssertTrue(sourceLegendBlock.contains("ForEach(items)"))
        XCTAssertFalse(sourceLegendBlock.contains("ForEach(orderedItems)"))
        XCTAssertTrue(sourceLegendBlock.contains(".alignmentGuide(.firstTextBaseline) { dimensions in"))
        XCTAssertTrue(sourceLegendBlock.contains("dimensions[.lastTextBaseline]"))
        XCTAssertFalse(sourceLegendBlock.contains("dimensions[.firstTextBaseline]"))
        XCTAssertTrue(basicsLegendBlock.contains(".alignmentGuide(.firstTextBaseline) { dimensions in"))
        XCTAssertTrue(basicsLegendBlock.contains("dimensions[.lastTextBaseline]"))
        XCTAssertTrue(heroTrailingBlock.contains("BodyChartBaselineLegend()"))
        XCTAssertTrue(heroTrailingBlock.contains(".alignmentGuide(.firstTextBaseline) { dimensions in"))
        XCTAssertTrue(heroTrailingBlock.contains("dimensions[.lastTextBaseline]"))
        XCTAssertFalse(source.contains("sourceLabelSortOrder"))
        XCTAssertEqual(
            source.occurrenceCount(of: ".sorted { $0.sourceRole.rawValue < $1.sourceRole.rawValue }"),
            3
        )
    }

    func testBasicsLegendMatchesTrailingSourceLegendStyle() throws {
        let source = try bodyHomeViewText()
        let legendStart = try XCTUnwrap(source.range(of: "struct BodyBasicsTrendLegend: View")?.lowerBound)
        let selectionValueStart = try XCTUnwrap(
            source.range(of: "struct BodyChartSelectionValue", range: legendStart..<source.endIndex)?.lowerBound
        )
        let legendBlock = String(source[legendStart..<selectionValueStart])

        XCTAssertTrue(legendBlock.contains("VStack(alignment: .trailing, spacing: 7)"))
        XCTAssertTrue(legendBlock.contains(".frame(maxWidth: 180, alignment: .trailing)"))
        XCTAssertTrue(legendBlock.contains("HStack(spacing: 7)"))
        XCTAssertTrue(legendBlock.contains(".frame(width: 9, height: 9)"))
        XCTAssertTrue(legendBlock.contains(".font(.system(.subheadline, design: .rounded))"))
        XCTAssertTrue(legendBlock.contains(".minimumScaleFactor(0.68)"))
        XCTAssertFalse(legendBlock.contains("VStack(alignment: .leading, spacing: 5)"))
        XCTAssertFalse(legendBlock.contains(".padding(.trailing"))
        XCTAssertFalse(legendBlock.contains("basicsLegendTrailingAxisGutter"))
    }

    func testBasicsTrendChartKeepsTopAxisBelowLegendBand() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyBasicsTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(12_000))

        XCTAssertTrue(chartBlock.contains("private let normalizedYDomain = 0.0...1.1"))
        XCTAssertTrue(chartBlock.contains(".chartYScale(domain: normalizedYDomain)"))
        XCTAssertFalse(chartBlock.contains(".chartYScale(domain: 0...1)"))
    }

    func testHealthKitFetchesBarAndRangeSecondarySourceComparisons() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let engineSource = try healthKitFetchEngineText()
        let snapshotSource = try healthSummarySnapshotText()

        XCTAssertTrue(storeSource.contains("@Published private(set) var secondaryHealthDataSourceSelection"))
        XCTAssertTrue(storeSource.contains("func selectedSecondaryHealthDataSourceOption(for kind: HealthMetricKind)"))
        XCTAssertTrue(storeSource.contains("func updateSecondaryHealthDataSource(for kind: HealthMetricKind"))
        XCTAssertTrue(engineSource.contains("func fetchSecondaryTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendSeries?"))
        XCTAssertTrue(engineSource.contains("func fetchSecondaryRangeTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendRangeSeries?"))
        XCTAssertTrue(engineSource.contains("let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)"))
        XCTAssertTrue(engineSource.contains("sourceOption: secondaryOption"))
        XCTAssertTrue(engineSource.contains("trends.activeEnergySecondary = await activeEnergySecondaryTrend"))
        XCTAssertTrue(engineSource.contains("trends.restingEnergySecondary = await restingEnergySecondaryTrend"))
        XCTAssertTrue(engineSource.contains("trends.exerciseMinutesSecondary = await exerciseMinutesSecondaryTrend"))
        XCTAssertTrue(engineSource.contains("trends.stepsSecondary = await stepsSecondaryTrend"))
        XCTAssertTrue(engineSource.contains("trends.heartRateRangesSecondary = await heartRateRangesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.heartRateVariabilityRangesSecondary = await heartRateVariabilityRangesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.oxygenSaturationRangesSecondary = await oxygenSaturationRangesSecondary"))
        XCTAssertTrue(snapshotSource.contains("var activeEnergySecondary: HealthTrendSeries"))
        XCTAssertTrue(snapshotSource.contains("var restingEnergySecondary: HealthTrendSeries"))
        XCTAssertTrue(snapshotSource.contains("var exerciseMinutesSecondary: HealthTrendSeries"))
        XCTAssertTrue(snapshotSource.contains("var stepsSecondary: HealthTrendSeries"))
        XCTAssertTrue(snapshotSource.contains("var heartRateRangesSecondary: HealthTrendRangeSeries"))
        XCTAssertTrue(snapshotSource.contains("var heartRateVariabilityRangesSecondary: HealthTrendRangeSeries"))
        XCTAssertTrue(snapshotSource.contains("var oxygenSaturationRangesSecondary: HealthTrendRangeSeries"))
        XCTAssertTrue(snapshotSource.contains("next.restingEnergySecondary = refreshed.restingEnergySecondary"))
    }

    func testWorkoutDetailMetricReuseBranchDoesNotResurrectCachedValues() throws {
        // H12 regression guard: the cached-HR-reuse branch used to pass
        // `resolvedVO2 ?? cached.cardioFitnessVO2Max` / `resolvedCadence ??
        // cached.averageStepCadenceSPM`, so a successful query confirming a
        // detail metric absent could never clear the field on a passive
        // resume. Both fallbacks must stay gone, and all three call sites
        // must route through `resolvedWorkoutDetailMetric`.
        let engineSource = try healthKitFetchEngineText()

        XCTAssertFalse(engineSource.contains("?? cached.cardioFitnessVO2Max"))
        XCTAssertFalse(engineSource.contains("?? cached.averageStepCadenceSPM"))
        XCTAssertTrue(engineSource.contains("nonisolated static func resolvedWorkoutDetailMetric("))
        XCTAssertTrue(engineSource.contains("fetched: resolvedCardioFitness?[workout.uuid]"))
        XCTAssertTrue(engineSource.contains("fetched: resolvedStepCadence[workout.uuid]"))
        XCTAssertTrue(engineSource.contains("fetched: resolvedWorkoutDistance[workout.uuid]"))
    }

    func testSecondarySleepStageHistorySkipsVitalsHydration() throws {
        let sleepSource = try text(at: "Body/Services/HealthKitFetchEngine+Sleep.swift")
        let secondarySource = try text(at: "Body/Services/HealthKitFetchEngine+Secondary.swift")
        let fetchSleepHistoryStart = try XCTUnwrap(
            sleepSource.range(of: "func fetchDailySleepHistory(")?.lowerBound
        )
        let fetchSleepHistoryBlock = String(sleepSource[fetchSleepHistoryStart...].prefix(5_500))
        let fetchSecondarySleepStart = try XCTUnwrap(
            secondarySource.range(of: "func fetchSecondarySleepHistory")?.lowerBound
        )
        let fetchSecondarySleepBlock = String(secondarySource[fetchSecondarySleepStart...].prefix(1_000))

        XCTAssertTrue(fetchSleepHistoryBlock.contains("hydrateVitals: Bool = true"))
        XCTAssertTrue(fetchSleepHistoryBlock.contains("guard hydrateVitals else {"))
        XCTAssertTrue(fetchSleepHistoryBlock.contains("return SleepHistoryFetchResult(history: SleepHistorySnapshot(days: days), vitalsHadFailure: false)"))
        XCTAssertTrue(sleepSource.contains("BodySleepStageDisplayPreference.showsSubMinuteAwakeStages()"))
        XCTAssertTrue(sleepSource.contains("showsSubMinuteAwakeStages: showsSubMinuteAwakeStages"))
        XCTAssertTrue(sleepSource.contains("BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages()"))
        XCTAssertTrue(sleepSource.contains("showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages"))
        XCTAssertTrue(fetchSecondarySleepBlock.contains("hydrateVitals: false"))
    }

    func testMetricDetailScreensPullToRefreshOnlyCurrentMetric() throws {
        let homeSource = try bodyHomeViewText()
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let detailViewStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthMetricDetailView")?.lowerBound)
        // Window covers the struct's stored properties + `init` + `body` opening, where the
        // `.refreshable` lives; widened as the property list grew (e.g. `zoomNamespace`).
        let detailViewBlock = String(homeSource[detailViewStart...].prefix(6_000))
        let refreshStart = try XCTUnwrap(storeSource.range(of: "func refreshHealthMetric(_ kind: HealthMetricKind")?.lowerBound)
        let refreshBlock = String(storeSource[refreshStart...].prefix(8_000))

        XCTAssertTrue(detailViewBlock.contains(".refreshable {"))
        XCTAssertTrue(detailViewBlock.contains("await workoutStore.refreshHealthMetric(model.kind)"))
        XCTAssertTrue(refreshBlock.contains("let metricSnapshot = await engine.fetchHealthDashboardSnapshot("))
        XCTAssertTrue(refreshBlock.contains("for: kind"))
        XCTAssertTrue(refreshBlock.contains("existing: existing"))
        XCTAssertTrue(refreshBlock.contains("replacingMetric(kind, with: metricSnapshot.summary)"))
        XCTAssertTrue(refreshBlock.contains("replacingMetric(kind, with: metricSnapshot.trends)"))
        XCTAssertFalse(refreshBlock.contains("engine.fetchHealthSummary(calendar: calendar)"))
        XCTAssertFalse(refreshBlock.contains("engine.fetchHealthTrends(calendar: calendar"))
    }

    func testWorkoutsPullToRefreshOnlyRefreshesSelectedWorkoutMonth() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let refreshableStart = try XCTUnwrap(workoutsSource.range(of: ".refreshable {")?.lowerBound)
        let refreshableBlock = String(workoutsSource[refreshableStart...].prefix(500))
        let methodStart = try XCTUnwrap(storeSource.range(of: "func refreshWorkoutMonth(month: Int, year: Int")?.lowerBound)
        let methodBlock = String(storeSource[methodStart...].prefix(2_000))

        XCTAssertTrue(refreshableBlock.contains("await workoutStore.refreshWorkoutMonth(month: selectedMonth, year: selectedYear)"))
        XCTAssertFalse(refreshableBlock.contains("requestAuthorizationAndRefresh()"))
        XCTAssertTrue(methodBlock.contains("updatesHealthSummary: false"))
        XCTAssertFalse(methodBlock.contains("fetchHealthSummary(calendar: calendar)"))
        XCTAssertFalse(methodBlock.contains("fetchHealthTrends(calendar: calendar)"))
        XCTAssertFalse(methodBlock.contains("fetchActivityRingHistory(calendar: calendar)"))
    }

    func testAggregatedHealthChartsWireRangeLabelsAndBarWidths() throws {
        let source = try bodyHomeViewText()

        XCTAssertFalse(source.contains("basicsLegendTrailingAxisGutter"))
        XCTAssertTrue(source.contains("func bodyChartSelectionDateText(for point: HealthTrendCalendarPoint) -> String?"))
        XCTAssertTrue(source.contains("func bodyChartSelectionDateText(for point: HealthTrendRangeCalendarPoint) -> String?"))
        XCTAssertEqual(source.occurrenceCount(of: "dateText: bodyChartSelectionDateText(for: selectedTrendPoint)"), 1)
        XCTAssertEqual(source.occurrenceCount(of: "dateText: bodyChartSelectionDateText(for: selectedPoint)"), 1)
        XCTAssertEqual(source.occurrenceCount(of: "dateText: bodyChartSelectionDateText(for: selectedRangePoint)"), 1)
        XCTAssertTrue(source.contains("dateText: selectedTrendDateText"))
        XCTAssertEqual(
            source.occurrenceCount(of: "let chartBarWidth = selectedRange.chartBarWidth(forAvailableWidth: proxy.size.width)"),
            1
        )
        XCTAssertEqual(
            source.occurrenceCount(of: "let chartBarWidth = selectedRange.heartRateRangeChartBarWidth(forAvailableWidth: proxy.size.width)"),
            1
        )
        XCTAssertEqual(source.occurrenceCount(of: "width: .fixed(chartBarWidth)"), 5)
    }

    func testBasicsWeightBodyFatMonthChartKeepsStandardPointMarks() throws {
        let source = try bodyHomeViewText()

        XCTAssertFalse(source.contains("private var showsWeightBodyFatPointMarks: Bool"))
        XCTAssertFalse(source.contains("selectedRange.showsPointMarks && selectedRange != .recentMonth"))
        XCTAssertFalse(source.contains("if showsWeightBodyFatPointMarks"))
        XCTAssertEqual(source.occurrenceCount(of: "if selectedRange.showsPointMarks"), 6)

        let chartStart = try XCTUnwrap(source.range(of: "struct BodyBasicsTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(7_000))
        XCTAssertEqual(chartBlock.occurrenceCount(of: "if selectedRange.showsPointMarks"), 2)
    }

    func testBasicsTrendLegendShowsAverageValuesBehindMetricLabels() throws {
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("weightAverageText: basicsWeightAverageText"))
        XCTAssertTrue(source.contains("bodyFatAverageText: basicsBodyFatAverageText"))
        XCTAssertTrue(source.contains("legendItem(title: \"Body Fat\", valueText: bodyFatAverageText, color: bodyFatColor)"))
        XCTAssertTrue(source.contains("legendItem(title: \"Weight\", valueText: weightAverageText, color: weightColor)"))
        let legendItemStart = try XCTUnwrap(source.range(of: "private func legendItem")?.lowerBound)
        let legendItemBlock = source[legendItemStart...].prefix(1_100)
        let averageTextStart = try XCTUnwrap(legendItemBlock.range(of: "Text(\"Avg \\(valueText)\")")?.lowerBound)
        let averageTextBlock = legendItemBlock[averageTextStart...].prefix(260)
        XCTAssertTrue(averageTextBlock.contains(".foregroundColor(.secondary)"))
        XCTAssertFalse(legendItemBlock.contains("Text(valueText)"))
        XCTAssertFalse(averageTextBlock.contains(".foregroundColor(.primary)"))
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

        XCTAssertTrue(source.contains(#"case .summary: "waveform.path.ecg.text""#))
        XCTAssertTrue(source.contains(#"case .summary: "Summary""#))
        XCTAssertFalse(source.contains(#""house.fill""#))
    }

    func testAppWidgetAndWatchShareAppGroupEntitlement() throws {
        let appEntitlements = try propertyList(at: "Body/Body.entitlements")
        let widgetEntitlements = try propertyList(at: "BodyWidgetExtension.entitlements")
        let watchEntitlements = try propertyList(at: "BodyWatch/BodyWatch.entitlements")
        let watchWidgetEntitlements = try propertyList(at: "BodyWatchWidgetExtension/BodyWatchWidgetExtension.entitlements")

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
        let appEntitlements = try propertyList(at: "Body/Body.entitlements")
        let watchEntitlements = try propertyList(at: "BodyWatch/BodyWatch.entitlements")

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
            let manifest = try propertyList(at: path)
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
        let project = try text(at: "body.xcodeproj/project.pbxproj")

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
        XCTAssertTrue(project.contains("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;"))
        XCTAssertTrue(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 18.0;"))
        XCTAssertTrue(project.contains("TARGETED_DEVICE_FAMILY = \"1,2\";"))
        XCTAssertTrue(project.contains("SUPPORTS_MACCATALYST = NO;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";"))
        XCTAssertTrue(project.contains("MARKETING_VERSION = 0.9.9;"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 3;"))
        // All five targets (app, widget, tests, watch app, watch complications)
        // × Debug/Release must move together on a version bump — `contains`
        // alone would pass with a stale target left behind.
        XCTAssertEqual(project.occurrenceCount(of: "MARKETING_VERSION = 0.9.9;"), 10)
        XCTAssertEqual(project.occurrenceCount(of: "CURRENT_PROJECT_VERSION = 3;"), 10)
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
    }

    func testVersionDocumentationAndSettingsFallbackMatchCurrentRelease() throws {
        let readme = try text(at: "README.md")
        let versionHistory = try text(at: "VersionHistory.md")
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(readme.contains("Current app version: **0.9.9 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.6 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.6 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.6 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.6 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 11)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 10)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 9)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.2 (build 3)**"))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 8."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 1."))
        XCTAssertFalse(versionHistory.contains("## 0.9.6 (build 5)"))
        XCTAssertFalse(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.6 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.6 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.6 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.6 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.6 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.6 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.6 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 11)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 11."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 10)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 10."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 9)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 9."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 8."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 8."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.2 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.2 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.2 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.2 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.2 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.2 build 1."))
        XCTAssertFalse(readme.contains("Current app version: **0.9.2 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.2 (build 1)**"))
        XCTAssertTrue(versionHistory.contains("## 0.9.1 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.1 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.1 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.1 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.1 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.1 build 1."))
        XCTAssertFalse(readme.contains("Current app version: **0.9.1 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.1 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.1 (build 1)**"))
        XCTAssertTrue(versionHistory.contains("## 0.7.0 (build 2)"))
        XCTAssertTrue(versionHistory.contains("## 0.7.0 (build 1)"))
        XCTAssertTrue(versionHistory.contains("## 0.6.0 (build 2)"))
        XCTAssertTrue(versionHistory.contains("## 0.6.0 (build 1)"))
        XCTAssertTrue(versionHistory.contains("## 0.5.6 (build 4)"))
        XCTAssertTrue(versionHistory.contains("## 0.5.6 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Redesigned the workout detail heart rate chart"))
        XCTAssertTrue(versionHistory.contains("Added step-count day-line support"))
        XCTAssertTrue(versionHistory.contains("Readiness scoring now honors the configured sleep goal"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.5.6 build 4."))
        XCTAssertFalse(readme.contains("Current app version: **0.5.6 (build 4)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.7.0 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.7.0 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.6.0 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.6.0 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.6 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.6 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.6 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.2 (build 4)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.2 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.2 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.2 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.1 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.1 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.0 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.0 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.4.1"))
        XCTAssertFalse(readme.contains("Current app version: **0.3.5"))
        XCTAssertFalse(readme.contains("Current app version: **0.3.9 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.3.4 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.3.3 (build 2)**"))
        XCTAssertFalse(settingsSource.contains(#"?? "1""#))
        // Version fallbacks are localized; both literal and String(localized:) forms count.
        XCTAssertGreaterThanOrEqual(
            settingsSource.occurrenceCount(of: #"?? "Unknown""#)
                + settingsSource.occurrenceCount(of: #"?? String(localized: "Unknown")"#),
            4
        )
    }

    func testHealthKitUsageDescriptionListsRequestedHealthCategories() throws {
        let project = try text(at: "body.xcodeproj/project.pbxproj")
        let usageDescription = "Body reads workouts, workout routes, Activity Rings, sleep, heart rate, HRV, blood oxygen, respiratory rate, body measurements, energy, exercise minutes, skin temperature, daylight, steps, cardio fitness, power, cadence, swim strokes, distance, and date of birth from Apple Health to power your dashboard, charts, and widgets."

        XCTAssertEqual(project.occurrenceCount(of: usageDescription), 2)
        XCTAssertFalse(project.contains("Body reads workout, sleep, heart, and body measurement data"))
    }

    func testWorkoutRouteReadTypeIsRequested() throws {
        let readTypes = try text(at: "BodyWatchSnapshotKit/BodyHealthReadTypes.swift")
        XCTAssertTrue(readTypes.contains("HKSeriesType.workoutRoute()"))
    }

    func testWorkoutRouteCacheClearsAfterHealthKitAuthorizationGate() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")

        XCTAssertTrue(storeSource.contains("private func requestHealthKitAuthorization() async throws"))
        XCTAssertTrue(storeSource.contains("try await engine.requestAuthorization()"))
        XCTAssertTrue(storeSource.contains("routeCache.removeAll()"))
        XCTAssertEqual(storeSource.occurrenceCount(of: "try await engine.requestAuthorization()"), 1)
        XCTAssertTrue(storeSource.contains("try await requestHealthKitAuthorization()"))
        XCTAssertTrue(storeSource.contains("if permission == .workouts"))
    }

    func testWorkoutDetailPresentsFullScreenPushDragToDismiss() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        let sheetStart = try XCTUnwrap(workoutsSource.range(of: "struct BodyWorkoutDetailSheet")?.lowerBound)
        let sheetBlock = String(workoutsSource[sheetStart...].prefix(6_000))

        // Workout details open as a full-bleed navigation push (so the tab bar stays
        // visible), the map bleeds under the status bar, and the nav bar is hidden. There
        // is no close button — the zoom transition's drag-to-dismiss returns to the card.
        XCTAssertTrue(workoutsSource.contains(".navigationDestination(item: $selectedWorkoutForDetails) { workout in"))
        XCTAssertTrue(workoutsSource.contains(".navigationTransition(.zoom(sourceID: workout.id, in: workoutZoom))"))
        XCTAssertTrue(workoutsSource.contains("async let loadedRoute = workoutStore.loadWorkoutRoute(for: workout)"))
        XCTAssertTrue(workoutsSource.contains("async let loadedSplitData = workoutStore.loadWorkoutSplitData(for: workout)"))
        XCTAssertTrue(workoutsSource.contains("route = await loadedRoute"))
        XCTAssertTrue(workoutsSource.contains(".ignoresSafeArea(edges: .top)"))
        XCTAssertTrue(workoutsSource.contains(".toolbar(.hidden, for: .navigationBar)"))
        XCTAssertFalse(sheetBlock.contains(#"Image(systemName: "xmark")"#))
        XCTAssertFalse(sheetBlock.contains("private var closeButton"))
        XCTAssertFalse(sheetBlock.contains("@Environment(\\.dismiss) private var dismiss"))
        XCTAssertFalse(sheetBlock.contains("distanceMeters ?? 0"))
        XCTAssertFalse(workoutsSource.contains(".fullScreenCover(item: $selectedWorkoutForDetails)"))
        XCTAssertFalse(workoutsSource.contains("selectedDetent"))
        XCTAssertFalse(sheetBlock.contains(".presentationDetents"))
    }

    func testWorkoutListSheetRowsOpenFullScreenDetail() throws {
        let source = try text(at: "Body/Views/BodyWorkoutListSheet.swift")

        // The calendar-day / workout-type list popups make their rows tappable into
        // the same full-screen workout detail used by the Workouts list.
        XCTAssertTrue(source.contains("@State private var selectedWorkout: WorkoutSummary?"))
        XCTAssertTrue(source.contains("selectedWorkout = workout"))
        XCTAssertTrue(source.contains(".matchedTransitionSource(id: workout.id, in: workoutZoom)"))
        XCTAssertTrue(source.contains(".fullScreenCover(item: $selectedWorkout) { workout in"))
        XCTAssertTrue(source.contains("BodyWorkoutDetailSheet(workout: workout)"))
        XCTAssertTrue(source.contains(".navigationTransition(.zoom(sourceID: workout.id, in: workoutZoom))"))
        // The Done button was removed; the popups dismiss via the sheet grabber.
        XCTAssertFalse(source.contains(#"Button("Done")"#))
        XCTAssertTrue(source.contains(".toolbar(.hidden, for: .navigationBar)"))
    }

    func testWorkoutStepSamplesPropagateReadFailuresInsteadOfSwallowingErrors() throws {
        let splitsSource = try text(at: "Body/Services/HealthKitFetchEngine+Splits.swift")

        // H8: a cancelled/transient step-sample read (dismissed detail sheet, XPC
        // drop) must propagate like the distance/route reads and `fetchWorkout(id:)`
        // already do, instead of collapsing to an empty cadence column that the
        // store then caches as confirmed data for the rest of the session.
        XCTAssertTrue(splitsSource.contains("private func workoutStepSamples(for workout: HKWorkout, type: BodyWorkoutType) async throws -> [WorkoutStepSample]"))
        XCTAssertTrue(splitsSource.contains("private func readWorkoutStepSamples(for workout: HKWorkout, stepType: HKQuantityType) async throws -> [WorkoutStepSample]"))
        XCTAssertTrue(splitsSource.contains("stepSamples: try await workoutStepSamples(for: workout, type: type)"))
        XCTAssertFalse(splitsSource.contains("catch {\n            return []\n        }"))

        // The store's catch must keep returning an UNCACHED `.empty` so a retry on
        // reopen can recover — it must not also write the negative result into
        // `distanceSampleCache`, which would make it permanent for the session.
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let loadStart = try XCTUnwrap(storeSource.range(of: "func loadWorkoutSplitData(for workout: WorkoutSummary) async -> WorkoutSplitData")?.lowerBound)
        let loadBlock = String(storeSource[loadStart...].prefix(900))
        let catchStart = try XCTUnwrap(loadBlock.range(of: "} catch {")?.lowerBound)
        let catchBlock = String(loadBlock[catchStart...].prefix(195))

        XCTAssertTrue(catchBlock.contains("return .empty"))
        XCTAssertFalse(catchBlock.contains("distanceSampleCache["))
    }

    func testTestPlanCoversCurrentBranchAndBodyProSurface() throws {
        let testPlan = try text(at: "TestPlan.md")

        XCTAssertTrue(testPlan.contains("branch `body-0.9.9`"))
        XCTAssertTrue(testPlan.contains("app version 0.9.9 build 3)"))
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

    func testWorkoutsMonthLoadUsesPullToRefreshOverlay() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")

        XCTAssertTrue(workoutsSource.contains("@State private var pendingMonthSelection: PendingMonthSelection?"))
        XCTAssertTrue(workoutsSource.contains(".bodyPullToRefreshLoadingOverlay(isPresented: isPullRefreshing || pendingMonthSelection != nil)"))
        XCTAssertFalse(workoutsSource.contains("BodyWorkoutMonthLoadingBanner"))
        XCTAssertFalse(workoutsSource.contains("withTaskGroup"))
        XCTAssertTrue(workoutsSource.contains("pendingMonthSelection = PendingMonthSelection(request: token, monthYear: monthYear)"))
        XCTAssertTrue(workoutsSource.contains("await workoutStore.loadMonthIfNeeded(month: monthYear.month, year: monthYear.year)"))
        XCTAssertTrue(workoutsSource.contains("private func monthLoadTask(for monthYear: BodyMonthYear) -> Task<Bool, Never>"))
        XCTAssertTrue(workoutsSource.contains("func finishPendingMonthSelection(token: UUID, didLoad: Bool?)"))
        XCTAssertTrue(workoutsSource.contains("guard let pending = pendingMonthSelection, pending.request == token else"))
        XCTAssertTrue(workoutsSource.contains("try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)"))
        XCTAssertTrue(workoutsSource.contains("if didLoad == true {"))
        XCTAssertTrue(workoutsSource.contains("applyMonthSelection(pending.monthYear)"))
        XCTAssertTrue(workoutsSource.contains("return false"))
    }

    func testDeadChartsViewAndHealthCardAccessoryBranchAreRemoved() throws {
        let oldChartsViewURL = projectRoot.appendingPathComponent("Body/Views/BodyChartsView.swift")
        let chartsSource = try text(at: "Body/Views/BodyWorkoutListSheet.swift")
        let homeSource = try bodyHomeViewText()

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldChartsViewURL.path))
        XCTAssertFalse(chartsSource.contains("struct BodyChartsView"))
        XCTAssertFalse(chartsSource.contains("BodyChartsScrollTransitionShade"))
        XCTAssertFalse(chartsSource.contains("BodyChartsLoadingBanner"))
        XCTAssertFalse(homeSource.contains("AccessoryMetric"))
        XCTAssertFalse(homeSource.contains("accessoryMetrics"))
        XCTAssertFalse(homeSource.contains("accessoryContent"))
        XCTAssertFalse(homeSource.contains("accessoryMetricStrip"))
    }

    func testSleepAndMetricDayPickersShareDateTileHelper() throws {
        let homeSource = try bodyHomeViewText()

        XCTAssertTrue(homeSource.contains("private var recentDatePickerDates: [Date]"))
        XCTAssertTrue(homeSource.contains("private func datePicker("))
        XCTAssertTrue(homeSource.contains("private func dateTile("))
        XCTAssertTrue(homeSource.contains("BodyDateSliderTileLabel.primaryText(for: dayStart, today: today, calendar: calendar)"))
        XCTAssertFalse(homeSource.contains("private var sleepDatePickerDates"))
        XCTAssertFalse(homeSource.contains("private var metricDatePickerDates"))
        XCTAssertFalse(homeSource.contains("private func sleepDateTile"))
        XCTAssertFalse(homeSource.contains("private func metricDateTile"))
        XCTAssertFalse(homeSource.contains("Text(dayStart.formatted(.dateTime.weekday(.abbreviated)))"))
    }

    func testProjectDateMathUsesBodyGregorianForSleepAxisAndWidgetTimeline() throws {
        let homeSource = try bodyHomeViewText()
        let widgetSource = try text(at: "BodyWidgetExtension/WorkoutCalendarWidget.swift")

        XCTAssertFalse(homeSource.contains("let calendar = Calendar.current"))
        XCTAssertFalse(widgetSource.contains("Calendar.current.date(byAdding: .minute"))
        XCTAssertTrue(homeSource.contains("let calendar = Calendar.bodyGregorian"))
        XCTAssertTrue(widgetSource.contains("Calendar.bodyGregorian.date(byAdding: .minute"))
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
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
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
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
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
                FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent(path).path),
                path
            )
        }
    }

    func testSettingsExposesStandardAppIconOptionsWithoutCreatorSurprise() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let appearanceSource = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")

        // The "Present" creator-surprise icons and their version-tap unlock were removed.
        XCTAssertFalse(settingsSource.contains("versionTapCount"))
        XCTAssertFalse(settingsSource.contains("creatorSurpriseIconsUnlocked"))
        XCTAssertFalse(settingsSource.contains("showingCreatorSurprise"))
        XCTAssertFalse(settingsSource.contains("BodyCreatorSurpriseOverlay"))
        XCTAssertFalse(settingsSource.contains("BodyCreatorRibbon"))
        XCTAssertFalse(settingsSource.contains("availableOptions(includeCreatorSurprises:"))
        XCTAssertFalse(settingsSource.contains(#"descriptor: "Present""#))
        XCTAssertFalse(appearanceSource.contains("creatorSurpriseIconsUnlockedKey"))

        // The six standard color options remain.
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
            #"descriptor: "White""#
        ]

        for label in requiredLabels {
            XCTAssertTrue(settingsSource.contains(label), label)
        }
    }

    func testSettingsMetricsSectionGroupsUnitsSummaryCardsAndTrendControls() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let homeSource = try bodyHomeViewText()
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let appearanceStart = try XCTUnwrap(settingsSource.range(of: "private var appearanceSection: some View")?.lowerBound)
        let appearanceBlock = String(settingsSource[appearanceStart...].prefix(2_500))
        let metricsStart = try XCTUnwrap(settingsSource.range(of: "private var metricsSection: some View")?.lowerBound)
        let metricsBlock = String(settingsSource[metricsStart...].prefix(4_000))
        let stackStart = try XCTUnwrap(
            settingsSource.range(of: "VStack(alignment: .leading, spacing: 22) {")?.lowerBound
        )
        let settingsStack = String(settingsSource[stackStart...].prefix(400))
        let appearanceSectionRange = try XCTUnwrap(settingsStack.range(of: "appearanceSection"))
        let metricsSectionRange = try XCTUnwrap(settingsStack.range(of: "metricsSection"))
        let dataSectionRange = try XCTUnwrap(settingsStack.range(of: "dataSection"))
        let iconRange = try XCTUnwrap(appearanceBlock.range(of: #"title: "Icon""#))
        let sleepRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Sleep""#))
        let unitsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Units""#))
        let summaryCardsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Summary Cards""#))
        let trendCardsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Trend Cards""#))

        XCTAssertLessThan(appearanceSectionRange.lowerBound, metricsSectionRange.lowerBound)
        XCTAssertLessThan(metricsSectionRange.lowerBound, dataSectionRange.lowerBound)
        XCTAssertTrue(metricsBlock.contains(#"BodySettingsCardSection("Metrics")"#))
        XCTAssertLessThan(sleepRange.lowerBound, unitsRange.lowerBound)
        XCTAssertLessThan(unitsRange.lowerBound, summaryCardsRange.lowerBound)
        XCTAssertLessThan(summaryCardsRange.lowerBound, trendCardsRange.lowerBound)
        XCTAssertFalse(metricsBlock.contains(#"title: "Sleep Goal""#))
        XCTAssertFalse(appearanceBlock.contains(#"title: "Summary Cards""#))
        XCTAssertFalse(appearanceBlock.contains(#"title: "Charts Range""#))
        XCTAssertFalse(appearanceBlock.contains(#"title: "Trend Cards""#))
        XCTAssertFalse(settingsSource.contains("private var unitSection: some View"))
        XCTAssertFalse(settingsSource.contains(#"title: "Measurement""#))
        XCTAssertTrue(settingsSource.contains(#"BodySettingsAboutSheetScaffold(title: "Trend Cards")"#))
        XCTAssertFalse(settingsSource.contains(#".navigationTitle("Default Trend Range")"#))
        XCTAssertFalse(settingsSource.contains(#"BodySettingsAboutSheetScaffold(title: "Home Trend Cards")"#))
        XCTAssertLessThan(iconRange.lowerBound, appearanceBlock.endIndex)
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.summaryCardSelectionKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.showsLeadingTrailingAwakeSleepStagesKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey)"))
        XCTAssertTrue(settingsSource.contains("case .sleepDurationGoal:"))
        XCTAssertTrue(settingsSource.contains("case .summaryCards:"))
        XCTAssertTrue(settingsSource.contains("case .homeTrendCards:"))
        XCTAssertTrue(settingsSource.contains("BodySleepSettingsSheet("))
        XCTAssertTrue(settingsSource.contains(#"BodySettingsAboutSheetScaffold(title: "Sleep")"#))
        XCTAssertTrue(settingsSource.contains(#"BodySettingsCardSection("Sleep Stages")"#))
        XCTAssertTrue(settingsSource.contains(#"Text("Show Awake Under 1 Min")"#))
        XCTAssertTrue(settingsSource.contains("Toggle(\"Show Awake Under 1 Min\""))
        XCTAssertTrue(settingsSource.contains(".onChange(of: showsSubMinuteAwakeSleepStages)"))
        XCTAssertTrue(settingsSource.contains(#"Text("Show Awake at Start & End")"#))
        XCTAssertTrue(settingsSource.contains("Toggle(\"Show Awake at Start & End\""))
        XCTAssertTrue(settingsSource.contains(".onChange(of: showsLeadingTrailingAwakeSleepStages)"))
        XCTAssertTrue(settingsSource.contains("BodySummaryCardsSettingsSheet("))
        XCTAssertTrue(settingsSource.contains("BodyHomeTrendCardsSettingsSheet("))
        XCTAssertTrue(settingsSource.contains("ForEach(BodyHomeCardKind.defaultOrder)"))
        XCTAssertTrue(settingsSource.contains("ForEach(BodyHomeTrendCardKind.defaultOrder)"))
        XCTAssertTrue(settingsSource.contains("BodySummaryCardToggleRow("))
        XCTAssertTrue(settingsSource.contains("BodyHomeTrendCardToggleRow("))
        XCTAssertTrue(appearanceSource.contains("var isBeta: Bool"))
        XCTAssertTrue(appearanceSource.contains("case .readiness:"))
        XCTAssertTrue(settingsSource.contains("if card.isBeta"))
        XCTAssertEqual(settingsSource.occurrenceCount(of: #"Text("v1")"#), 1)
        XCTAssertEqual(settingsSource.occurrenceCount(of: #"Text("v2")"#), 1)
        XCTAssertEqual(settingsSource.occurrenceCount(of: #"Text("Beta v2")"#), 1)
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.defaultTrendRangeKey)"))
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey)"))
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey)"))
        XCTAssertTrue(homeSource.contains("initialTrendRange: defaultTrendRange"))
        XCTAssertTrue(homeSource.contains("idealSleepDuration: sleepDurationGoal"))
        XCTAssertTrue(homeSource.contains("BodyHomeTrendCardFactory.cards("))
        XCTAssertTrue(homeSource.contains("selection: homeTrendCardSelection"))
    }

    func testSettingsThemeRowIsRemovedForDarkThemeGate() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let appearanceStart = try XCTUnwrap(settingsSource.range(of: "private var appearanceSection: some View")?.lowerBound)
        let appearanceBlock = String(settingsSource[appearanceStart...].prefix(2_000))
        let backgroundRange = try XCTUnwrap(appearanceBlock.range(of: #"title: "Background""#))

        let firstRowRange = try XCTUnwrap(appearanceBlock.range(of: #"BodySettingsRowLabel("#))
        XCTAssertLessThan(firstRowRange.lowerBound, backgroundRange.lowerBound)
        XCTAssertFalse(appearanceBlock.contains(#"title: "Theme""#))
        XCTAssertFalse(appearanceBlock.contains("currentTheme"))
        XCTAssertFalse(settingsSource.contains("selectedThemeRawValue"))
        XCTAssertFalse(settingsSource.contains("BodyAppTheme"))
        XCTAssertFalse(appearanceBlock.contains("Theme selection is disabled"))
        XCTAssertFalse(appearanceBlock.contains("activeSheet = .theme"))
        XCTAssertFalse(settingsSource.contains("BodyThemePickerSheet"))
        XCTAssertFalse(settingsSource.contains("case theme"))
        XCTAssertFalse(settingsSource.contains("case .theme"))
    }

    func testSettingsUnitsPageHasSystemToggleAndIndependentUnitControls() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let appearanceSource = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let formatterSource = try text(at: "BodyMetricsKit/WorkoutSummary.swift")

        let unitSheetStart = try XCTUnwrap(settingsSource.range(of: "private struct BodyUnitPreferencePickerSheet")?.lowerBound)
        let unitSheetBlock = String(settingsSource[unitSheetStart...].prefix(8_000))

        XCTAssertTrue(appearanceSource.contains("followsSystemUnitsKey"))
        XCTAssertTrue(appearanceSource.contains("selectedWeightUnitKey"))
        XCTAssertTrue(appearanceSource.contains("selectedDistanceUnitKey"))
        XCTAssertTrue(appearanceSource.contains("selectedEnergyUnitKey"))
        XCTAssertTrue(appearanceSource.contains("selectedTemperatureUnitKey"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.followsSystemUnitsKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.selectedWeightUnitKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.selectedDistanceUnitKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.selectedEnergyUnitKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey)"))
        XCTAssertTrue(unitSheetBlock.contains(#"Toggle("Follow System""#))
        XCTAssertTrue(unitSheetBlock.contains(#"title: "Weight""#))
        XCTAssertTrue(unitSheetBlock.contains(#"title: "Distance""#))
        XCTAssertTrue(unitSheetBlock.contains(#"title: "Energy""#))
        XCTAssertTrue(unitSheetBlock.contains(#"title: "Temperature""#))
        XCTAssertTrue(unitSheetBlock.contains("BodyValueFormat.WeightUnitPreference.allCases"))
        XCTAssertTrue(unitSheetBlock.contains("BodyValueFormat.DistanceUnitPreference.allCases"))
        XCTAssertTrue(unitSheetBlock.contains("BodyValueFormat.EnergyUnitPreference.allCases"))
        XCTAssertTrue(unitSheetBlock.contains("BodyValueFormat.TemperatureUnitPreference.allCases"))
        XCTAssertTrue(unitSheetBlock.contains("isEnabled: !followsSystemUnits"))
        XCTAssertTrue(unitSheetBlock.contains(".disabled(followsSystemUnits)"))
        XCTAssertTrue(formatterSource.contains("enum WeightUnitPreference"))
        XCTAssertTrue(formatterSource.contains("enum DistanceUnitPreference"))
        XCTAssertTrue(formatterSource.contains("enum EnergyUnitPreference"))
        XCTAssertTrue(formatterSource.contains("enum TemperatureUnitPreference"))
    }

    func testSettingsDataSectionExposesSyncStatusAndCacheControls() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let dataStart = try XCTUnwrap(settingsSource.range(of: "private var dataSection: some View")?.lowerBound)
        let dataBlock = String(settingsSource[dataStart...].prefix(3_000))
        XCTAssertTrue(dataBlock.contains("BodySettingsDataTab.allCases"))
        XCTAssertTrue(dataBlock.contains("activeSheet = tab.sheet"))
        XCTAssertTrue(dataBlock.contains("dataValue(for: tab)"))
        XCTAssertTrue(settingsSource.contains("return permissionSummaryText"))
        XCTAssertFalse(settingsSource.contains(#""Grant Access""#))
        XCTAssertTrue(settingsSource.contains(#"return "Data Refresh""#))
        XCTAssertFalse(settingsSource.contains(#"return "Health Data Sync""#))
        XCTAssertTrue(settingsSource.contains(#"return "Cache""#))
        XCTAssertTrue(settingsSource.contains("case .syncStatus:"))
        XCTAssertTrue(settingsSource.contains("case .cache:"))
        XCTAssertTrue(settingsSource.contains("case .permissions:"))
        XCTAssertTrue(settingsSource.contains("BodyHealthPermissionsSettingsSheet(workoutStore: workoutStore)"))
        XCTAssertTrue(settingsSource.contains("BodyCacheSettingsSheet(workoutStore: workoutStore)"))
        XCTAssertTrue(settingsSource.contains("workoutStore.healthSyncStatusSummaryText"))
        XCTAssertTrue(settingsSource.contains("workoutStore.cacheStatus.summaryText"))
    }

    func testDataRefreshStatusSheetShowsLastRefreshWithoutDetailBullet() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let sheetStart = try XCTUnwrap(settingsSource.range(of: "private struct BodyHealthSyncStatusSettingsSheet")?.lowerBound)
        let sheetBlock = String(settingsSource[sheetStart...].prefix(2_500))
        let statusTextStart = try XCTUnwrap(storeSource.range(of: "var healthSyncStatusLastRefreshText")?.lowerBound)
        let statusTextBlock = String(storeSource[statusTextStart...].prefix(500))

        XCTAssertTrue(sheetBlock.contains(#"BodySettingsAboutSheetScaffold(title: "Data Refresh")"#))
        XCTAssertTrue(sheetBlock.contains(#""Last refreshed: \(lastSuccessfulRefreshText)""#))
        XCTAssertFalse(sheetBlock.contains("workoutStore.healthSyncStatusDetailText"))
        XCTAssertFalse(sheetBlock.contains(#""Last successful refresh: \(lastSuccessfulRefreshText)""#))
        XCTAssertTrue(storeSource.contains("healthSyncStatusLastRefreshText"))
        XCTAssertFalse(storeSource.contains(#"return "Updated""#))
        XCTAssertTrue(statusTextBlock.contains("date.formatted(.dateTime.month(.abbreviated).day().hour().minute())"))
        XCTAssertFalse(statusTextBlock.contains("date.formatted(date: .abbreviated, time: .shortened)"))
    }

    func testHowToUseGuideMovedOutOfSettings() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(settingsSource.contains(#"private let howToUseURLString = "https://docs.ijustinz.com/body/how-to-use""#))
        XCTAssertFalse(settingsSource.contains("BodyHowToUseGuideSection"))
        XCTAssertFalse(settingsSource.contains("BodyHowToUseGuideCard"))
        XCTAssertFalse(settingsSource.contains(#"title: "Connect Apple Health""#))
    }

    func testBodyProPageUsesCoinStyleSettingsEntryAndIconAssets() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let bodyProSource = try text(at: "Body/Views/BodyProView.swift")
        let settingsStackStart = try XCTUnwrap(
            settingsSource.range(of: "VStack(alignment: .leading, spacing: 22) {")?.lowerBound
        )
        let settingsStack = String(settingsSource[settingsStackStart...].prefix(350))
        let aboutSectionRange = try XCTUnwrap(settingsStack.range(of: "aboutSection"))
        let bodyProEntryRange = try XCTUnwrap(settingsStack.range(of: "bodyProEntryCard"))

        XCTAssertTrue(settingsSource.contains("bodyProEntryCard"))
        XCTAssertLessThan(aboutSectionRange.lowerBound, bodyProEntryRange.lowerBound)
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
        XCTAssertEqual(bodyProSource.occurrenceCount(of: "BodyProFeature("), 5)
        XCTAssertTrue(bodyProSource.contains("Longer-Range Charts"))
        XCTAssertTrue(bodyProSource.contains("Full Day History"))
        XCTAssertTrue(bodyProSource.contains("Custom Backgrounds"))
        XCTAssertTrue(bodyProSource.contains("Secondary Data Source"))
        XCTAssertFalse(bodyProSource.contains("Six-Month and Year Charts"))
        XCTAssertTrue(bodyProSource.contains("Body Widgets"))
        // StoreKit purchase wiring replaced the placeholder stubs.
        XCTAssertTrue(bodyProSource.contains("BodyProStore"))
        XCTAssertTrue(bodyProSource.contains("proStore?.purchase()"))
        XCTAssertTrue(bodyProSource.contains("proStore?.restore()"))
        XCTAssertTrue(bodyProSource.contains("offerCodeRedemption"))
        // Resolve-gating: a checking state shows until entitlement resolves, the
        // purchase action is disabled while a flow is active, and Restore/Redeem
        // stay available during a pending (Ask-to-Buy/SCA) approval.
        XCTAssertTrue(bodyProSource.contains("hasResolved"))
        XCTAssertTrue(bodyProSource.contains("BodyProCheckingCard"))
        XCTAssertTrue(bodyProSource.contains("isPurchaseFlowActive"))
        XCTAssertTrue(bodyProSource.contains("isRestoreOrRedeemDisabled"))
        XCTAssertFalse(bodyProSource.contains("not available in this build"))
        XCTAssertTrue(bodyProSource.contains("Future Pro Updates"))
        // No guessed storefront price: a loading placeholder shows until the
        // StoreKit product resolves, and an unavailable/retry card on failure.
        XCTAssertFalse(bodyProSource.contains("$9.99"))
        XCTAssertTrue(bodyProSource.contains("Loading price…"))
        XCTAssertTrue(bodyProSource.contains("BodyProUnavailableCard"))
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

    /// Pins the RevenueCat monetization wiring that can't be exercised without a configured
    /// SDK and a running store: the entitlement source of truth, purchase/restore/pending
    /// handling, the absence of the retired native-StoreKit plumbing, and the shared App
    /// Group flag. The persistence and change-notification behavior of that flag is exercised
    /// at runtime in `BodyProEntitlementTests`.
    func testBodyProStoreRevenueCatWiringIsGuarded() throws {
        let storeSource = try text(at: "Body/Services/BodyProStore.swift")
        let configSource = try text(at: "Body/Services/RevenueCatConfiguration.swift")
        let entitlementSource = try text(at: "BodyShared/Services/BodyProEntitlement.swift")
        let widgetSource = try text(at: "BodyWidgetExtension/HealthMetricWidget.swift")

        // Backed by RevenueCat, keyed to the single non-consumable that unlocks Pro. The
        // product id is retained — the store fetches it directly for the display price.
        XCTAssertTrue(storeSource.contains("import RevenueCat"))
        XCTAssertTrue(storeSource.contains(#"static let lifetimeProductID = "com.zihengthedeveloper.body.pro.lifetime""#))
        XCTAssertTrue(storeSource.contains("static let entitlementID"))

        // Entitlement source of truth: RevenueCat CustomerInfo. The stream catches
        // this-device / post-call updates; purchase / restore / customerInfo cover the rest.
        XCTAssertTrue(storeSource.contains("Purchases.shared.customerInfoStream"))
        XCTAssertTrue(storeSource.contains("Purchases.shared.purchase(product:"))
        XCTAssertTrue(storeSource.contains("Purchases.shared.restorePurchases()"))
        XCTAssertTrue(storeSource.contains("entitlements[Self.entitlementID]?.isActive == true"))

        // The explicit launch/foreground refresh must force a network fetch, not read the
        // stale local cache — otherwise refunds / other-device purchases never propagate.
        // `.fetchCurrent` is the non-default policy that guarantees this.
        XCTAssertTrue(storeSource.contains("customerInfo(fetchPolicy: .fetchCurrent)"))

        // Pending (Ask-to-Buy / SCA): a pending purchase never unlocks, and the pending
        // state clears once the entitlement actually unlocks (so Restore/Redeem re-enable).
        XCTAssertTrue(storeSource.contains(".paymentPendingError"))
        XCTAssertTrue(storeSource.contains("if unlocked && purchaseState == .pending"))

        // Migration guards: the native StoreKit plumbing is gone. RevenueCat verifies,
        // encodes revocation into `isActive`, and auto-finishes transactions; re-introducing
        // any of these would double-handle purchases or fight the SDK (observer mode).
        XCTAssertFalse(storeSource.contains("Transaction.updates"))
        XCTAssertFalse(storeSource.contains("Transaction.currentEntitlements"))
        XCTAssertFalse(storeSource.contains("transaction.finish()"))
        XCTAssertFalse(storeSource.contains("AppStore.sync()"))
        XCTAssertFalse(storeSource.contains("purchasesAreCompletedBy: .myApp"))
        XCTAssertFalse(storeSource.contains("recordPurchase"))

        // Configuration: one auditable place for the public key + entitlement id, configured
        // once, using RevenueCat's default (SDK-completed) purchase mode. The key and
        // entitlement id must be the real dashboard values — a reverted placeholder key or a
        // wrong entitlement identifier would silently make every entitlement read inactive.
        XCTAssertTrue(configSource.contains(#"static let publicAPIKey = "appl_"#))
        XCTAssertFalse(configSource.contains("REPLACE_ME"))
        XCTAssertFalse(configSource.contains("test_iZhxBFYdgodhOoQkJoDgLpmweay"))
        XCTAssertTrue(configSource.contains(#"static let proEntitlementID = "Body: Health Dashboard Pro""#))
        XCTAssertTrue(configSource.contains("guard !Purchases.isConfigured"))
        XCTAssertTrue(configSource.contains("Purchases.configure(with:"))

        // Shared App Group flag: synchronous source of truth for the widget process and
        // the non-SwiftUI stores; falls back to locked and posts only on a real change.
        XCTAssertTrue(entitlementSource.contains("UserDefaults(suiteName: WorkoutSnapshotStore.appGroupIdentifier)"))
        XCTAssertTrue(entitlementSource.contains("?? false"))
        XCTAssertTrue(entitlementSource.contains("defaults.bool(forKey: unlockedKey) != unlocked"))
        XCTAssertTrue(entitlementSource.contains("NotificationCenter.default.post(name: didChangeNotification"))

        // Widget gating: the gallery/preview shows the unlocked widget so users see what
        // Pro unlocks; the live timeline respects the cached flag.
        XCTAssertTrue(widgetSource.contains("usePlaceholderWhenEmpty || BodyProEntitlement.isUnlocked"))
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

    func testProjectDeclaresSimplifiedChineseLocalization() throws {
        let project = try text(at: "body.xcodeproj/project.pbxproj")
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
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
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

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Concatenates every Swift file backing `BodyHomeView`. The original
    /// 8,600-line `BodyHomeView.swift` was split into focused peer files
    /// (Body/Views/Health/...) — tests that grep for substrings on this view's
    /// surface should look across all of them, not just the main file.
    private func bodyHomeViewText() throws -> String {
        let files = [
            "Body/Views/BodyHomeView.swift",
            "Body/Views/Health/BodyHealthMetricCard.swift",
            "Body/Views/Health/BodyHealthMetricDetailView.swift",
            "Body/Views/Health/BodyHealthDataSourcePickerSheet.swift",
            "Body/Views/Health/BodyHomeTrendCard.swift",
            "Body/Views/Health/BodyHealthNoticeBanner.swift",
            "Body/Views/Health/SleepScoreSheet.swift",
            "Body/Views/Health/ChartHelpers.swift",
            "Body/Views/Health/Charts/MetricCharts.swift",
            "Body/Views/Health/Charts/BasicsCharts.swift",
            "Body/Views/Health/Charts/HeartRateRangeChart.swift",
            "Body/Views/Health/Charts/SourceComparisonCharts.swift",
            "Body/Views/Health/Charts/SleepCharts.swift",
            "Body/Views/Health/Charts/TrainingLoadCharts.swift",
            "Body/Views/Health/Charts/ReadinessChart.swift"
        ]
        return try files.compactMap { file -> String? in
            try? text(at: file)
        }.joined(separator: "\n")
    }

    /// Concatenates every Swift file backing the health summary / dashboard /
    /// trend / activity-ring / sleep / source-comparison / training-load
    /// models. The original 3,300-line `HealthSummarySnapshot.swift` was split
    /// into focused peer files; tests that grep for snapshot substrings should
    /// look across all of them, not just the main file.
    private func healthSummarySnapshotText() throws -> String {
        let files = [
            "BodyMetricsKit/HealthSummarySnapshot.swift",
            "BodyMetricsKit/ActivityRings.swift",
            "BodyMetricsKit/Sleep.swift",
            "Body/Models/SourceComparison.swift",
            "BodyMetricsKit/TrainingLoadCalculator.swift",
            "BodyMetricsKit/HealthTrend.swift"
        ]
        return try files.map { try text(at: $0) }.joined(separator: "\n")
    }

    /// Concatenates every Swift file backing `HealthKitFetchEngine`. The engine
    /// was split across the main actor file and one or more `+...swift`
    /// extension files; tests that grep for engine substrings should look across
    /// the whole engine, not just the main file.
    private func healthKitFetchEngineText() throws -> String {
        let files = [
            "Body/Services/HealthKitFetchEngine.swift",
            "Body/Services/HealthKitFetchEngine+SampleParsers.swift",
            "Body/Services/HealthKitFetchEngine+Sleep.swift",
            "Body/Services/HealthKitFetchEngine+TrainingLoad.swift",
            "Body/Services/HealthKitFetchEngine+ActivityRings.swift",
            "Body/Services/HealthKitFetchEngine+SourceOptions.swift",
            "Body/Services/HealthKitFetchEngine+Secondary.swift",
            "Body/Services/HealthKitFetchEngine+IntradaySamples.swift"
        ]
        return try files.map { try text(at: $0) }.joined(separator: "\n")
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
