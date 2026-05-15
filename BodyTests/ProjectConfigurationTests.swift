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
        XCTAssertEqual(source.occurrenceCount(of: "overflowResolution: bodyChartSelectionOverflowResolution"), 8)
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
            5
        )
        XCTAssertFalse(source.contains("bodyHealthDetailChartTrailingDatePadding: TimeInterval = 36 * 60 * 60"))
        XCTAssertFalse(source.contains("let leadingPadding: TimeInterval = 6 * 60 * 60"))
        XCTAssertFalse(source.contains("let trailingPadding: TimeInterval = 18 * 60 * 60"))
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
        let chartBlock = source[chartStart...].prefix(4_500)

        XCTAssertTrue(chartBlock.contains("BodyLineChartPreviewPointSymbol("))
        XCTAssertTrue(chartBlock.contains("isCurrent: isLatestBucket(bucket)"))
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
        let contextBlock = String(source[contextStart...].prefix(1_800))

        XCTAssertTrue(detailBlock.contains("sleepHistory: trends.sleepHistory"))
        XCTAssertTrue(contextBlock.contains("model.kind == .heartRate || model.kind == .heartRateVariability"))
        XCTAssertTrue(contextBlock.contains("sleepSummary(for: selectedMetricDay)?.stageSnapshot.dateInterval"))
        XCTAssertTrue(contextBlock.contains("workouts(on: dayInterval)"))
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
        let chartBlock = String(source[chartStart...].prefix(12_000))

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
        XCTAssertTrue(chartBlock.contains(#"y: .value("Average \(title)", averageValue)"#))
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
        let cardBlock = String(source[cardStart...].prefix(1_100))
        let trendCardStart = try XCTUnwrap(source.range(of: "homeTrendCard(\n                kind: .wristTemperature")?.lowerBound)
        let trendCardBlock = String(source[trendCardStart...].prefix(1_100))
        let detailStart = try XCTUnwrap(source.range(of: "case .wristTemperature:")?.lowerBound)
        let detailBlock = String(source[detailStart...].prefix(2_300))
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
        XCTAssertTrue(chartBlock.contains("guard let highlightedRangeResolver, let selectedTrendPoint else {"))
        XCTAssertTrue(chartBlock.contains("return highlightedRangeResolver(selectedTrendPoint.value) ?? highlightedRange"))
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
        let trendCardBlock = String(source[trendCardStart...].prefix(5_500))
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
        let arcBlock = String(source[arcStart...].prefix(2_800))

        XCTAssertTrue(graphicBlock.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(graphicBlock.contains("private func sweepAnimation(ringIndex: Int) -> Animation?"))
        XCTAssertEqual(graphicBlock.occurrenceCount(of: ".animation(sweepAnimation(ringIndex:"), 3)
        XCTAssertTrue(graphicBlock.contains(".smooth(duration: 0.75, extraBounce: 0)"))
        XCTAssertTrue(graphicBlock.contains(".delay(Double(ringIndex) * 0.05)"))
        XCTAssertTrue(source.contains("private struct BodyActivityRingHeadPosition: GeometryEffect"))
        XCTAssertTrue(source.contains("var animatableData: Double"))
        XCTAssertTrue(arcBlock.contains(".modifier(BodyActivityRingHeadPosition(progress: animatedHeadProgress, radius: radius))"))
    }

    func testAggregatedHealthChartsWireRangeLabelsAndBarWidths() throws {
        let source = try text(at: "Body/Views/BodyHomeView.swift")

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
        XCTAssertEqual(source.occurrenceCount(of: "width: .fixed(chartBarWidth)"), 3)
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
        let legendItemBlock = source[legendItemStart...].prefix(700)
        let averageTextStart = try XCTUnwrap(legendItemBlock.range(of: "Text(\"Avg \\(valueText)\")")?.lowerBound)
        let averageTextBlock = legendItemBlock[averageTextStart...].prefix(180)
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
        XCTAssertTrue(project.contains("MARKETING_VERSION = 0.3.9;"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 2;"))
        XCTAssertTrue(project.contains("VALIDATE_PRODUCT = YES;"))
    }

    func testVersionDocumentationAndSettingsFallbackMatchBuildTwo() throws {
        let readme = try text(at: "README.md")
        let versionHistory = try text(at: "VersionHistory.md")
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(readme.contains("Current app version: **0.3.9 (build 2)**"))
        XCTAssertTrue(versionHistory.contains("## 0.3.9 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Added Heart Rate, Wrist Temperature, and Training Load dashboard cards with dedicated detail charts."))
        XCTAssertTrue(versionHistory.contains("Moved the dashboard cache out of UserDefaults into file-backed storage to avoid oversized preferences writes."))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.3.9 build 2."))
        XCTAssertFalse(readme.contains("Current app version: **0.3.5"))
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

        XCTAssertTrue(testPlan.contains("branch `body-v0.3.5`"))
        XCTAssertFalse(testPlan.contains("branch `codex/body-v0.3.0`"))
        XCTAssertFalse(testPlan.contains("branch `codex/body-v0.3.4`"))
        XCTAssertTrue(testPlan.contains("Body/Views/BodyProView.swift"))
        XCTAssertTrue(testPlan.contains("Body Pro entry navigation"))
        XCTAssertTrue(testPlan.contains("Body Pro icon flip"))
        XCTAssertTrue(testPlan.contains("version-card unlock"))
        XCTAssertTrue(testPlan.contains("creator-surprise icon sheet"))
    }

    func testWorkoutsMonthLoadUsesPendingBannerInsteadOfEmptyPlaceholder() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")

        XCTAssertTrue(workoutsSource.contains("@State private var pendingMonthSelection: BodyMonthYear?"))
        XCTAssertTrue(workoutsSource.contains("if let pendingMonthSelection {"))
        XCTAssertTrue(workoutsSource.contains("BodyWorkoutMonthLoadingBanner(monthYear: pendingMonthSelection)"))
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
        XCTAssertFalse(homeSource.contains("private var sleepDatePickerDates"))
        XCTAssertFalse(homeSource.contains("private var metricDatePickerDates"))
        XCTAssertFalse(homeSource.contains("private func sleepDateTile"))
        XCTAssertFalse(homeSource.contains("private func metricDateTile"))
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
