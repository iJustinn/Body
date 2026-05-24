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
        XCTAssertEqual(BodySettingsDataTab.allCases.map(\.title), ["Source", "Permissions", "Data Refresh", "Cache"])
        XCTAssertEqual(BodySettingsDataTab.source.sheet, .source)
        XCTAssertEqual(BodySettingsDataTab.permissions.sheet, .permissions)
        XCTAssertEqual(BodySettingsDataTab.syncStatus.sheet, .syncStatus)
        XCTAssertEqual(BodySettingsDataTab.cache.sheet, .cache)
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
        XCTAssertEqual(source.occurrenceCount(of: "overflowResolution: bodyChartSelectionOverflowResolution"), 10)
        XCTAssertFalse(source.contains(".annotation(position: .top, spacing: 8) {"))
    }

    func testHealthMetricChartDateDomainsFavorRightSidePadding() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertTrue(source.contains("bodyHealthDetailChartLeadingDatePadding: TimeInterval = 2 * 60 * 60"))
        XCTAssertTrue(source.contains("bodyHealthDetailChartMinimumTrailingDatePadding: TimeInterval = 36 * 60 * 60"))
        XCTAssertTrue(source.contains("private func bodyHealthDetailChartTrailingDatePadding(for selectedRange: BodyHealthTrendRange) -> TimeInterval"))
        XCTAssertTrue(source.contains("let rangeScaledPadding = Double(selectedRange.axisStrideDayCount) * 24 * 60 * 60 * 0.55"))
        XCTAssertTrue(source.contains("return max(bodyHealthDetailChartMinimumTrailingDatePadding, rangeScaledPadding)"))
        XCTAssertTrue(source.contains("private func bodyHealthDetailChartXDomain(for dates: [Date], selectedRange: BodyHealthTrendRange) -> ClosedRange<Date>"))
        XCTAssertEqual(
            source.occurrenceCount(of: "self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)"),
            7
        )
        XCTAssertFalse(source.contains("bodyHealthDetailChartTrailingDatePadding: TimeInterval = 36 * 60 * 60"))
        XCTAssertFalse(source.contains("let leadingPadding: TimeInterval = 6 * 60 * 60"))
        XCTAssertFalse(source.contains("let trailingPadding: TimeInterval = 18 * 60 * 60"))
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
        let source = try text(at: "Body/Views/BodyHomeView.swift")
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

    func testLineHealthChartsDoNotRenderEmptyDatePlaceholderMarks() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertFalse(source.contains("BodyLineChartPlaceholderSymbol"))
        XCTAssertFalse(source.contains("placeholderSymbolSize"))
        XCTAssertTrue(source.contains("placeholderBarYValue"))
    }

    func testLineHealthChartsUseStraightInterpolation() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertFalse(source.contains(".interpolationMethod(.catmullRom)"))
        XCTAssertEqual(
            source.occurrenceCount(of: ".interpolationMethod("),
            source.occurrenceCount(of: ".interpolationMethod(.linear)")
        )
    }

    func testMetricDayLineChartUsesPreviewDotSymbols() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let chartStart = try XCTUnwrap(source.range(of: "private struct BodyHealthMetricDayChart")?.lowerBound)
        let chartBlock = source[chartStart...].prefix(7_000)

        XCTAssertTrue(chartBlock.contains("BodyLineChartPreviewPointSymbol("))
        XCTAssertTrue(chartBlock.contains("isCurrent: isLatestEntry(entry)"))
        XCTAssertTrue(chartBlock.contains("pointDiameter: Self.pointDiameter"))
        XCTAssertTrue(chartBlock.contains("currentPointDiameter: Self.currentPointDiameter"))
        XCTAssertFalse(chartBlock.contains(".symbolSize(24)"))
    }

    func testHeartRateVariabilityDayChartUsesSleepAndWorkoutContextOverlay() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let detailStart = try XCTUnwrap(
            source.range(of: "case .heartRateVariability:\n            return metricDetail(")?.lowerBound
        )
        let detailBlock = String(source[detailStart...].prefix(900))
        let contextStart = try XCTUnwrap(source.range(of: "private var selectedMetricDayContextIntervals")?.lowerBound)
        let contextBlock = String(source[contextStart...].prefix(2_400))
        let chartStart = try XCTUnwrap(source.range(of: "private struct BodyHealthMetricDayChart")?.lowerBound)
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
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let previewBlock = String(source[
            try XCTUnwrap(source.range(of: "private struct BodyHealthMetricCardTrendPreview")?.lowerBound)...
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
        XCTAssertTrue(previewBlock.contains("BodyHomeMetricCardPreview.rangeCalendarPoints(from: rangeSeries)"))
        XCTAssertTrue(previewBlock.contains("RoundedRectangle(cornerRadius: 2, style: .continuous)"))
        XCTAssertTrue(previewBlock.contains("Capsule(style: .continuous)"))
    }

    func testHeartRateRangeChartUsesStandardBarSelectionRule() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let chartStart = try XCTUnwrap(source.range(of: "private struct BodyHeartRateRangeTrendChart")?.lowerBound)
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
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private func wristTemperatureMetric")?.lowerBound)
        let cardBlock = String(source[cardStart...].prefix(1_500))
        let trendCardStart = try XCTUnwrap(source.range(of: "homeTrendCard(\n                kind: .wristTemperature")?.lowerBound)
        let trendCardBlock = String(source[trendCardStart...].prefix(1_100))
        let detailStart = try XCTUnwrap(source.range(of: "case .wristTemperature:")?.lowerBound)
        let detailBlock = String(source[detailStart...].prefix(3_000))
        let dayViewStart = try XCTUnwrap(source.range(of: "private var supportsMetricDayView")?.lowerBound)
        let dayViewBlock = String(source[dayViewStart...].prefix(700))

        XCTAssertTrue(cardBlock.contains(#"title: "Wrist Temp""#))
        XCTAssertEqual(source.components(separatedBy: #"title: "Wrist Temp""#).count - 1, 1)
        XCTAssertTrue(cardBlock.contains("chartPreviewStyle: .line"))
        XCTAssertTrue(trendCardBlock.contains(#"title: "Wrist Temperature""#))
        XCTAssertTrue(detailBlock.contains(#"title: "Wrist Temperature""#))
        XCTAssertTrue(detailBlock.contains("series: trends.wristTemperature.mapValues"))
        XCTAssertTrue(detailBlock.contains("daySeries: .empty"))
        XCTAssertTrue(detailBlock.contains("chartStyle: .line"))
        XCTAssertTrue(dayViewBlock.contains(".wristTemperature"))
    }

    func testTrainingLoadCardUsesLineChartWithCurrentIntervalWithoutUnitsOrDayView() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let cardStart = try XCTUnwrap(source.range(of: "metric(\n                kind: .trainingLoad")?.lowerBound)
        let cardBlock = String(source[cardStart...].prefix(1_100))
        let trendCardStart = try XCTUnwrap(source.range(of: "homeTrendCard(\n                kind: .trainingLoad")?.lowerBound)
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
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let chartStart = try XCTUnwrap(source.range(of: "private struct BodyHealthMetricTrendChart")?.lowerBound)
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
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let trendCardStart = try XCTUnwrap(source.range(of: "private var trendCard")?.lowerBound)
        let trendCardBlock = String(source[trendCardStart...].prefix(8_000))
        let breakdownStart = try XCTUnwrap(source.range(of: "private struct BodyTrainingLoadIntervalBreakdownChart")?.lowerBound)
        let breakdownBlock = String(source[breakdownStart...].prefix(4_500))

        XCTAssertTrue(trendCardBlock.contains("if model.kind == .trainingLoad {"))
        XCTAssertTrue(trendCardBlock.contains("BodyTrainingLoadIntervalBreakdownChart("))
        XCTAssertTrue(trendCardBlock.contains("series: model.series"))
        XCTAssertTrue(trendCardBlock.contains("selectedRange: selectedTrendRange"))
        XCTAssertTrue(breakdownBlock.contains("TrainingLoadIntervalBreakdown.entries("))
        XCTAssertTrue(breakdownBlock.contains("GeometryReader { geometry in"))
        XCTAssertTrue(breakdownBlock.contains("RoundedRectangle(cornerRadius: barCornerRadius"))
        XCTAssertTrue(breakdownBlock.contains("dayCountText(for: entry.dayCount)"))
        XCTAssertTrue(breakdownBlock.contains("entry.interval.title"))
        XCTAssertTrue(breakdownBlock.contains("entry.interval.symbolName"))
    }

    func testSummaryMetricValuesUseClockStyleNumericTransitions() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

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
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let detailViewStart = try XCTUnwrap(source.range(of: "private struct BodyHealthMetricDetailView")?.lowerBound)
        let detailViewBlock = String(source[detailViewStart...].prefix(15_000))
        let pickerStart = try XCTUnwrap(source.range(of: "private struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        let pickerBlock = String(source[pickerStart...].prefix(8_000))

        XCTAssertTrue(detailViewBlock.contains("model.kind.supportsHealthDataSourceSelection"))
        XCTAssertTrue(detailViewBlock.contains("workoutStore.selectedHealthDataSourceOption(for: model.kind)"))
        XCTAssertTrue(detailViewBlock.contains("BodyHealthDataSourcePickerSheet("))
        XCTAssertTrue(pickerBlock.contains("workoutStore.healthDataSourceOptions(for: kind)"))
        XCTAssertTrue(pickerBlock.contains("workoutStore.updateHealthDataSource(for: kind, option: option)"))
    }

    func testHealthDataSourcePickerRowsShowSourceNamesOnly() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let pickerStart = try XCTUnwrap(source.range(of: "private struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        let pickerBlock = String(source[pickerStart...].prefix(8_000))

        XCTAssertTrue(pickerBlock.contains("Text(option.name)"))
        XCTAssertFalse(pickerBlock.contains("Only this source"))
        XCTAssertFalse(pickerBlock.contains("All available Apple Health sources"))
        XCTAssertFalse(pickerBlock.contains("Hide secondary comparison"))
        XCTAssertFalse(pickerBlock.contains("optionDetailText"))
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
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let trendCardStart = try XCTUnwrap(homeSource.range(of: "private var trendCard: some View")?.lowerBound)
        let trendCardBlock = String(homeSource[trendCardStart...].prefix(10_000))
        let comparisonChartStart = try XCTUnwrap(homeSource.range(of: "private struct BodyHealthSourceComparisonBarChart")?.lowerBound)
        let comparisonChartBlock = String(homeSource[comparisonChartStart...].prefix(8_000))
        let rangeComparisonChartStart = try XCTUnwrap(homeSource.range(of: "private struct BodyHealthSourceComparisonRangeChart")?.lowerBound)
        let rangeComparisonChartBlock = String(homeSource[rangeComparisonChartStart...].prefix(8_000))
        let rangeBandChartStart = try XCTUnwrap(homeSource.range(of: "private struct BodyHeartRateRangeTrendChart")?.lowerBound)
        let rangeBandChartBlock = String(homeSource[rangeBandChartStart...].prefix(14_000))

        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceLegend("))
        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceComparisonBarChart("))
        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceComparisonRangeChart("))
        XCTAssertTrue(trendCardBlock.contains("model.kind.usesSourceComparisonRangeBandLineChart"))
        XCTAssertTrue(trendCardBlock.contains("secondaryRangeSeries: sourceRangeComparisonTrend.secondary.series"))
        XCTAssertTrue(trendCardBlock.contains("sourceComparisonTrend"))
        XCTAssertTrue(trendCardBlock.contains("sourceRangeComparisonTrend"))
        XCTAssertTrue(homeSource.contains("Color(red: 0.58, green: 0.36, blue: 0.98)"))
        XCTAssertTrue(appearanceSource.contains("var usesSourceComparisonRangeBandLineChart: Bool"))
        XCTAssertTrue(comparisonChartBlock.contains("chartDate: point.date.addingTimeInterval"))
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
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let trendCardStart = try XCTUnwrap(homeSource.range(of: "private var trendCard: some View")?.lowerBound)
        let trendCardBlock = String(homeSource[trendCardStart...].prefix(9_000))
        let lineComparisonChartStart = try XCTUnwrap(homeSource.range(of: "private struct BodyHealthSourceComparisonLineChart")?.lowerBound)
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

    func testSourceSelectableDayChartsUsePrimarySecondaryComparisonLines() throws {
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
        let engineSource = try healthKitFetchEngineText()
        let snapshotSource = try text(at: "Body/Models/HealthSummarySnapshot.swift")
        let dayChartCardStart = try XCTUnwrap(homeSource.range(of: "private var metricDayChartCard: some View")?.lowerBound)
        let dayChartCardBlock = String(homeSource[dayChartCardStart...].prefix(3_500))
        let dayChartStart = try XCTUnwrap(homeSource.range(of: "private struct BodyHealthMetricDayChart")?.lowerBound)
        let dayChartBlock = String(homeSource[dayChartStart...].prefix(10_000))

        XCTAssertTrue(dayChartCardBlock.contains("BodyHealthSourceLegend("))
        XCTAssertTrue(dayChartCardBlock.contains("selectedMetricSecondaryDaySeries"))
        XCTAssertTrue(dayChartCardBlock.contains("secondarySeries: selectedMetricSecondaryDaySeries"))
        XCTAssertTrue(dayChartBlock.contains("secondaryHourlyBuckets"))
        XCTAssertTrue(dayChartBlock.contains("series: .value(\"Source\", entry.sourceRole.rawValue)"))
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
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let trendCardStart = try XCTUnwrap(source.range(of: "private var trendCard: some View")?.lowerBound)
        let trendChartStart = try XCTUnwrap(
            source.range(of: "if let visibleBasicsTrend", range: trendCardStart..<source.endIndex)?.lowerBound
        )
        let trendHeaderBlock = String(source[trendCardStart..<trendChartStart])
        let dayChartCardStart = try XCTUnwrap(source.range(of: "private var metricDayChartCard: some View")?.lowerBound)
        let dayChartStart = try XCTUnwrap(
            source.range(of: "if selectedMetricDaySeries.isEmpty", range: dayChartCardStart..<source.endIndex)?.lowerBound
        )
        let dayHeaderBlock = String(source[dayChartCardStart..<dayChartStart])

        XCTAssertTrue(trendHeaderBlock.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(dayHeaderBlock.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
    }

    func testSourceLegendContentIsTrailingAligned() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let legendStart = try XCTUnwrap(source.range(of: "private struct BodyHealthSourceLegend: View")?.lowerBound)
        let comparisonChartStart = try XCTUnwrap(
            source.range(of: "private struct BodyHealthSourceComparisonLineChart", range: legendStart..<source.endIndex)?.lowerBound
        )
        let legendBlock = String(source[legendStart..<comparisonChartStart])

        XCTAssertTrue(legendBlock.contains("VStack(alignment: .trailing, spacing: 7)"))
        XCTAssertTrue(legendBlock.contains(".frame(maxWidth: 180, alignment: .trailing)"))
        XCTAssertFalse(legendBlock.contains("VStack(alignment: .leading, spacing: 7)"))
        XCTAssertFalse(legendBlock.contains(".frame(maxWidth: 180, alignment: .leading)"))
    }

    func testBasicsLegendMatchesTrailingSourceLegendStyle() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let legendStart = try XCTUnwrap(source.range(of: "private struct BodyBasicsTrendLegend: View")?.lowerBound)
        let selectionValueStart = try XCTUnwrap(
            source.range(of: "private struct BodyChartSelectionValue", range: legendStart..<source.endIndex)?.lowerBound
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
        let source = try text(at: "Body/Views/BodyHomeView.swift")
        let chartStart = try XCTUnwrap(source.range(of: "private struct BodyBasicsTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(12_000))

        XCTAssertTrue(chartBlock.contains("private let normalizedYDomain = 0.0...1.1"))
        XCTAssertTrue(chartBlock.contains(".chartYScale(domain: normalizedYDomain)"))
        XCTAssertFalse(chartBlock.contains(".chartYScale(domain: 0...1)"))
    }

    func testHealthKitFetchesBarAndRangeSecondarySourceComparisons() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let engineSource = try healthKitFetchEngineText()
        let snapshotSource = try text(at: "Body/Models/HealthSummarySnapshot.swift")

        XCTAssertTrue(storeSource.contains("@Published private(set) var secondaryHealthDataSourceSelection"))
        XCTAssertTrue(storeSource.contains("func selectedSecondaryHealthDataSourceOption(for kind: HealthMetricKind)"))
        XCTAssertTrue(storeSource.contains("func updateSecondaryHealthDataSource(for kind: HealthMetricKind"))
        XCTAssertTrue(engineSource.contains("private func fetchSecondaryTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendSeries"))
        XCTAssertTrue(engineSource.contains("private func fetchSecondaryRangeTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendRangeSeries"))
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

    func testMetricDetailScreensPullToRefreshOnlyCurrentMetric() throws {
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let detailViewStart = try XCTUnwrap(homeSource.range(of: "private struct BodyHealthMetricDetailView")?.lowerBound)
        let detailViewBlock = String(homeSource[detailViewStart...].prefix(3_500))
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
        XCTAssertTrue(methodBlock.contains("await refresh(month: month, year: year, calendar: calendar, updatesHealthSummary: false)"))
        XCTAssertFalse(methodBlock.contains("fetchHealthSummary(calendar: calendar)"))
        XCTAssertFalse(methodBlock.contains("fetchHealthTrends(calendar: calendar)"))
        XCTAssertFalse(methodBlock.contains("fetchActivityRingHistory(calendar: calendar)"))
    }

    func testAggregatedHealthChartsWireRangeLabelsAndBarWidths() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertFalse(source.contains("basicsLegendTrailingAxisGutter"))
        XCTAssertTrue(source.contains("private func bodyChartSelectionDateText(for point: HealthTrendCalendarPoint) -> String?"))
        XCTAssertTrue(source.contains("private func bodyChartSelectionDateText(for point: HealthTrendRangeCalendarPoint) -> String?"))
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
        let source = try text(at: "Body/Views/BodyHomeView.swift")

        XCTAssertFalse(source.contains("private var showsWeightBodyFatPointMarks: Bool"))
        XCTAssertFalse(source.contains("selectedRange.showsPointMarks && selectedRange != .recentMonth"))
        XCTAssertFalse(source.contains("if showsWeightBodyFatPointMarks"))
        XCTAssertEqual(source.occurrenceCount(of: "if selectedRange.showsPointMarks"), 6)

        let chartStart = try XCTUnwrap(source.range(of: "private struct BodyBasicsTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(7_000))
        XCTAssertEqual(chartBlock.occurrenceCount(of: "if selectedRange.showsPointMarks"), 2)
    }

    func testBasicsTrendLegendShowsAverageValuesBehindMetricLabels() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

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
        XCTAssertTrue(project.contains("MARKETING_VERSION = 0.5.6;"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 4;"))
        XCTAssertTrue(project.contains("VALIDATE_PRODUCT = YES;"))
    }

    func testVersionDocumentationAndSettingsFallbackMatchCurrentRelease() throws {
        let readme = try text(at: "README.md")
        let versionHistory = try text(at: "VersionHistory.md")
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(readme.contains("Current app version: **0.5.6 (build 4)**"))
        XCTAssertTrue(versionHistory.contains("## 0.5.6 (build 4)"))
        XCTAssertTrue(versionHistory.contains("## 0.5.6 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Redesigned the workout detail heart rate chart"))
        XCTAssertTrue(versionHistory.contains("Added step-count day-line support"))
        XCTAssertTrue(versionHistory.contains("Readiness scoring now honors the configured sleep goal"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.5.6 build 4."))
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
        XCTAssertGreaterThanOrEqual(settingsSource.occurrenceCount(of: #"?? "Unknown""#), 4)
    }

    func testHealthKitUsageDescriptionListsRequestedHealthCategories() throws {
        let project = try text(at: "body.xcodeproj/project.pbxproj")
        let usageDescription = "Body reads workouts, Activity Rings, sleep, heart rate, HRV, blood oxygen, respiratory rate, body measurements, energy, exercise minutes, wrist temperature, daylight, and steps from Apple Health to power your dashboard, charts, and widgets."

        XCTAssertEqual(project.occurrenceCount(of: usageDescription), 2)
        XCTAssertFalse(project.contains("Body reads workout, sleep, heart, and body measurement data"))
    }

    func testTestPlanCoversCurrentBranchAndBodyProSurface() throws {
        let testPlan = try text(at: "TestPlan.md")

        XCTAssertTrue(testPlan.contains("branch `body-v0.5.6`"))
        XCTAssertTrue(testPlan.contains("app version 0.5.6 build 4"))
        XCTAssertFalse(testPlan.contains("branch `codex/body-v0.3.0`"))
        XCTAssertFalse(testPlan.contains("branch `codex/body-v0.3.4`"))
        XCTAssertTrue(testPlan.contains("Body/Views/BodyProView.swift"))
        XCTAssertTrue(testPlan.contains("Body Pro entry navigation"))
        XCTAssertTrue(testPlan.contains("Body Pro icon flip"))
        XCTAssertTrue(testPlan.contains("version-card unlock"))
        XCTAssertTrue(testPlan.contains("creator-surprise icon sheet"))
    }

    func testWorkoutsMonthLoadUsesPullToRefreshOverlay() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")

        XCTAssertTrue(workoutsSource.contains("@State private var pendingMonthSelection: BodyMonthYear?"))
        XCTAssertTrue(workoutsSource.contains(".bodyPullToRefreshLoadingOverlay(isPresented: isPullRefreshing || pendingMonthSelection != nil)"))
        XCTAssertFalse(workoutsSource.contains("BodyWorkoutMonthLoadingBanner"))
        XCTAssertTrue(workoutsSource.contains("pendingMonthSelection = monthYear"))
        XCTAssertTrue(workoutsSource.contains("await workoutStore.loadMonthIfNeeded(month: monthYear.month, year: monthYear.year)"))
        XCTAssertTrue(workoutsSource.contains("guard pendingMonthSelection == monthYear else"))
        XCTAssertTrue(workoutsSource.contains("if didLoad == true {"))
        XCTAssertTrue(workoutsSource.contains("applyMonthSelection(monthYear)"))
        XCTAssertTrue(workoutsSource.contains("return false"))
    }

    func testDeadChartsViewAndHealthCardAccessoryBranchAreRemoved() throws {
        let oldChartsViewURL = projectRoot.appendingPathComponent("Body/Views/BodyChartsView.swift")
        let chartsSource = try text(at: "Body/Views/BodyWorkoutListSheet.swift")
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")

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
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")

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
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
        let widgetSource = try text(at: "BodyWidgetExtension/WorkoutCalendarWidget.swift")

        XCTAssertFalse(homeSource.contains("let calendar = Calendar.current"))
        XCTAssertFalse(widgetSource.contains("Calendar.current.date(byAdding: .minute"))
        XCTAssertTrue(homeSource.contains("let calendar = Calendar.bodyGregorian"))
        XCTAssertTrue(widgetSource.contains("Calendar.bodyGregorian.date(byAdding: .minute"))
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

    func testSettingsMetricsSectionGroupsUnitsSummaryCardsAndTrendControls() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
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
        let sleepGoalRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Sleep Goal""#))
        let unitsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Units""#))
        let summaryCardsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Summary Cards""#))
        let chartsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Charts Range""#))
        let trendCardsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Trend Cards""#))

        XCTAssertLessThan(appearanceSectionRange.lowerBound, metricsSectionRange.lowerBound)
        XCTAssertLessThan(metricsSectionRange.lowerBound, dataSectionRange.lowerBound)
        XCTAssertTrue(metricsBlock.contains(#"BodySettingsCardSection("Metrics")"#))
        XCTAssertLessThan(sleepGoalRange.lowerBound, unitsRange.lowerBound)
        XCTAssertLessThan(unitsRange.lowerBound, chartsRange.lowerBound)
        XCTAssertLessThan(chartsRange.lowerBound, summaryCardsRange.lowerBound)
        XCTAssertLessThan(summaryCardsRange.lowerBound, trendCardsRange.lowerBound)
        XCTAssertFalse(appearanceBlock.contains(#"title: "Summary Cards""#))
        XCTAssertFalse(appearanceBlock.contains(#"title: "Charts Range""#))
        XCTAssertFalse(appearanceBlock.contains(#"title: "Trend Cards""#))
        XCTAssertFalse(settingsSource.contains("private var unitSection: some View"))
        XCTAssertFalse(settingsSource.contains(#"title: "Measurement""#))
        XCTAssertTrue(settingsSource.contains(#".navigationTitle("Charts Range")"#))
        XCTAssertTrue(settingsSource.contains(#"BodySettingsAboutSheetScaffold(title: "Trend Cards")"#))
        XCTAssertFalse(settingsSource.contains(#".navigationTitle("Default Trend Range")"#))
        XCTAssertFalse(settingsSource.contains(#"BodySettingsAboutSheetScaffold(title: "Home Trend Cards")"#))
        XCTAssertLessThan(iconRange.lowerBound, appearanceBlock.endIndex)
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.summaryCardSelectionKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.defaultTrendRangeKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey)"))
        XCTAssertTrue(settingsSource.contains("case .sleepDurationGoal:"))
        XCTAssertTrue(settingsSource.contains("case .summaryCards:"))
        XCTAssertTrue(settingsSource.contains("case .defaultTrendRange:"))
        XCTAssertTrue(settingsSource.contains("case .homeTrendCards:"))
        XCTAssertTrue(settingsSource.contains("BodySleepDurationGoalSettingsSheet("))
        XCTAssertTrue(settingsSource.contains("BodySummaryCardsSettingsSheet("))
        XCTAssertTrue(settingsSource.contains("BodyDefaultTrendRangePickerSheet("))
        XCTAssertTrue(settingsSource.contains("BodyHomeTrendCardsSettingsSheet("))
        XCTAssertTrue(settingsSource.contains("ForEach(BodyHomeCardKind.defaultOrder)"))
        XCTAssertTrue(settingsSource.contains("ForEach(BodyHomeTrendCardKind.defaultOrder)"))
        XCTAssertTrue(settingsSource.contains("BodySummaryCardToggleRow("))
        XCTAssertTrue(settingsSource.contains("BodyHomeTrendCardToggleRow("))
        XCTAssertTrue(appearanceSource.contains("var isBeta: Bool"))
        XCTAssertTrue(appearanceSource.contains("case .readiness:"))
        XCTAssertTrue(settingsSource.contains("if card.isBeta"))
        XCTAssertTrue(settingsSource.contains(#"Text("Beta")"#))
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.defaultTrendRangeKey)"))
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey)"))
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey)"))
        XCTAssertTrue(homeSource.contains("initialTrendRange: defaultTrendRange"))
        XCTAssertTrue(homeSource.contains("idealSleepDuration: sleepDurationGoal"))
        XCTAssertTrue(homeSource.contains(".filter { homeTrendCardSelection.includes($0.presentation.kind) }"))
    }

    func testSettingsUnitsPageHasSystemToggleAndIndependentUnitControls() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let formatterSource = try text(at: "BodyShared/Models/WorkoutSummary.swift")

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

    func testHowToUseGuideCoversCurrentSettingsAndDataFeatures() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let howToUseStart = try XCTUnwrap(settingsSource.range(of: "private struct BodyHowToUseSettingsSheet")?.lowerBound)
        let howToUseBlock = String(settingsSource[howToUseStart...].prefix(5_500))

        XCTAssertTrue(howToUseBlock.contains(#"title: "Connect Apple Health""#))
        XCTAssertTrue(howToUseBlock.contains("Open Data > Source to set default primary and secondary Apple Health sources or combine duplicate source names."))
        XCTAssertTrue(howToUseBlock.contains("Open Data > Permissions to choose which Apple Health categories Body uses inside the app."))
        XCTAssertTrue(howToUseBlock.contains("Open Data > Data Refresh to see the last refresh time or run Refresh Now."))
        XCTAssertTrue(howToUseBlock.contains(#"title: "Customize Metrics""#))
        XCTAssertTrue(howToUseBlock.contains("Use Metrics > Units to follow the system or choose weight, distance, energy, and temperature units manually."))
        XCTAssertTrue(howToUseBlock.contains("Use Metrics > Summary Cards, Charts Range, and Trend Cards to decide what appears on Summary and which default range charts open with."))
        XCTAssertTrue(howToUseBlock.contains(#"title: "Manage Cache""#))
        XCTAssertTrue(howToUseBlock.contains("Use Data > Source for app-wide primary and secondary defaults, or tap the source picker on a metric detail to override that metric."))
        XCTAssertTrue(howToUseBlock.contains("Use Data > Cache to review cached dashboard, workout, and Activity Ring data."))
        XCTAssertTrue(howToUseBlock.contains("Clear Cache removes local snapshots; Rebuild Cache refreshes Apple Health and rebuilds the local files."))
        XCTAssertFalse(howToUseBlock.contains("Use Settings to change appearance, app accent, icon, and measurement units."))
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
            "Body/Services/HealthKitFetchEngine+SourceOptions.swift"
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
