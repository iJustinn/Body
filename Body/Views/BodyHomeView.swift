//
//  BodyHomeView.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHomeView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @AppStorage(BodyAppearancePreference.selectedAccentKey) private var selectedAccentRawValue = BodyAppAccent.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedUnitPreferenceKey) private var selectedUnitPreferenceRawValue = BodyValueFormat.UnitPreference.defaultValue.rawValue

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        if let healthDataNotice = workoutStore.healthDataNotice {
                            BodyHealthNoticeBanner(message: healthDataNotice)
                        }

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(metricCards) { metric in
                                NavigationLink(value: metric.kind) {
                                    BodyHealthMetricCard(metric: metric)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await workoutStore.requestAuthorizationAndRefresh()
                }
            }
            .navigationDestination(for: HealthMetricKind.self) { kind in
                BodyHealthMetricDetailView(model: detailModel(for: kind))
            }
        }
    }

    private var metricCards: [BodyHealthMetricCard.Model] {
        let summary = workoutStore.healthSummary

        return [
            BodyHealthMetricCard.Model(
                kind: .sleep,
                title: "Sleep",
                value: formattedSleepDuration(summary.sleep.duration),
                unit: "",
                symbolName: "bed.double.fill",
                symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00)
            ),
            metric(
                kind: .restingHeartRate,
                title: "Resting Heart Rate",
                summary: summary.restingHeartRate,
                unit: "bpm",
                decimals: 0,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45)
            ),
            massMetric(
                kind: .bodyMass,
                title: "Weight",
                summary: summary.bodyMass,
                symbolName: "scalemass.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00)
            ),
            metric(
                kind: .bodyFatPercentage,
                title: "Body Fat",
                summary: summary.bodyFatPercentage,
                unit: "%",
                decimals: 1,
                symbolName: "percent",
                symbolColor: Color(red: 1.00, green: 0.68, blue: 0.08)
            ),
            metric(
                kind: .heartRateVariability,
                title: "HRV",
                summary: summary.heartRateVariability,
                unit: "ms",
                decimals: 1,
                symbolName: "waveform.path.ecg",
                symbolColor: Color(red: 0.46, green: 0.90, blue: 0.18)
            ),
            metric(
                kind: .oxygenSaturation,
                title: "Blood Oxygen",
                summary: summary.oxygenSaturation,
                unit: "%",
                decimals: 0,
                symbolName: "drop.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.18)
            ),
            metric(
                kind: .vo2Max,
                title: "VO2 Max",
                summary: summary.vo2Max,
                unit: "mL/kg/min",
                decimals: 1,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85)
            ),
            metric(
                kind: .bodyMassIndex,
                title: "BMI",
                summary: summary.bodyMassIndex,
                unit: "",
                decimals: 1,
                symbolName: "person.fill",
                symbolColor: selectedAccent.color
            ),
            metric(
                kind: .activeEnergy,
                title: "Active Energy",
                summary: summary.activeEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12)
            ),
            metric(
                kind: .restingEnergy,
                title: "Resting Energy",
                summary: summary.restingEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42)
            )
        ]
    }

    private var selectedAccent: BodyAppAccent {
        BodyAppAccent.storedValue(from: selectedAccentRawValue)
    }

    private var selectedUnitPreference: BodyValueFormat.UnitPreference {
        BodyValueFormat.UnitPreference.storedValue(from: selectedUnitPreferenceRawValue)
    }

    private func metric(
        kind: HealthMetricKind,
        title: String,
        summary: HealthMetricSummary,
        unit: String,
        decimals: Int,
        symbolName: String,
        symbolColor: Color
    ) -> BodyHealthMetricCard.Model {
        BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: summary.value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor
        )
    }

    private func massMetric(
        kind: HealthMetricKind,
        title: String,
        summary: HealthMetricSummary,
        symbolName: String,
        symbolColor: Color
    ) -> BodyHealthMetricCard.Model {
        let display = summary.value.map {
            BodyValueFormat.massDisplay(kilograms: $0, unitPreference: selectedUnitPreference)
        }
        return BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: display?.value ?? "--",
            unit: display?.unit ?? "",
            symbolName: symbolName,
            symbolColor: symbolColor
        )
    }

    private func formattedSleepDuration(_ duration: TimeInterval?) -> String {
        duration.map { BodyValueFormat.sleepDurationText(for: $0) } ?? "--"
    }

    private func detailModel(for kind: HealthMetricKind) -> BodyHealthMetricDetailModel {
        let summary = workoutStore.healthSummary
        let trends = workoutStore.healthTrends

        switch kind {
        case .sleep:
            return BodyHealthMetricDetailModel(
                title: "Sleep",
                value: formattedSleepDuration(summary.sleep.duration),
                unit: "",
                symbolName: "bed.double.fill",
                symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
                series: trends.sleep,
                sleepStageSnapshot: summary.sleep.stageSnapshot,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + "h" }
            )
        case .restingHeartRate:
            return metricDetail(
                kind: kind,
                title: "Resting Heart Rate",
                summary: summary.restingHeartRate,
                unit: "bpm",
                decimals: 0,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45)
            )
        case .bodyMass:
            let display = summary.bodyMass.value.map {
                BodyValueFormat.massDisplay(kilograms: $0, unitPreference: selectedUnitPreference)
            }
            let massUnit = BodyValueFormat.massValue(
                kilograms: 0,
                unitPreference: selectedUnitPreference
            ).unit
            return BodyHealthMetricDetailModel(
                title: "Weight",
                value: display?.value ?? "--",
                unit: display?.unit ?? massUnit,
                symbolName: "scalemass.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00),
                series: trends.bodyMass.mapValues {
                    BodyValueFormat.massValue(kilograms: $0, unitPreference: selectedUnitPreference).value
                },
                sleepStageSnapshot: nil,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " " + massUnit }
            )
        case .bodyFatPercentage:
            return metricDetail(
                kind: kind,
                title: "Body Fat",
                summary: summary.bodyFatPercentage,
                unit: "%",
                decimals: 1,
                symbolName: "percent",
                symbolColor: Color(red: 1.00, green: 0.68, blue: 0.08)
            )
        case .heartRateVariability:
            return metricDetail(
                kind: kind,
                title: "HRV",
                summary: summary.heartRateVariability,
                unit: "ms",
                decimals: 1,
                symbolName: "waveform.path.ecg",
                symbolColor: Color(red: 0.46, green: 0.90, blue: 0.18)
            )
        case .oxygenSaturation:
            return metricDetail(
                kind: kind,
                title: "Blood Oxygen",
                summary: summary.oxygenSaturation,
                unit: "%",
                decimals: 0,
                symbolName: "drop.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.18)
            )
        case .vo2Max:
            return metricDetail(
                kind: kind,
                title: "VO2 Max",
                summary: summary.vo2Max,
                unit: "mL/kg/min",
                decimals: 1,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85)
            )
        case .bodyMassIndex:
            return metricDetail(
                kind: kind,
                title: "BMI",
                summary: summary.bodyMassIndex,
                unit: "",
                decimals: 1,
                symbolName: "person.fill",
                symbolColor: selectedAccent.color
            )
        case .activeEnergy:
            return metricDetail(
                kind: kind,
                title: "Active Energy",
                summary: summary.activeEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .bar
            )
        case .restingEnergy:
            return metricDetail(
                kind: kind,
                title: "Resting Energy",
                summary: summary.restingEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42),
                chartStyle: .bar
            )
        }
    }

    private func metricDetail(
        kind: HealthMetricKind,
        title: String,
        summary: HealthMetricSummary,
        unit: String,
        decimals: Int,
        symbolName: String,
        symbolColor: Color,
        chartStyle: BodyHealthMetricChartStyle = .line
    ) -> BodyHealthMetricDetailModel {
        let suffix = unit.isEmpty ? "" : " " + unit
        return BodyHealthMetricDetailModel(
            title: title,
            value: summary.value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor,
            series: workoutStore.healthTrends.series(for: kind),
            sleepStageSnapshot: nil,
            chartStyle: chartStyle,
            valueFormatter: { BodyValueFormat.numberText($0, decimals: decimals) + suffix }
        )
    }
}

private enum BodyHealthMetricChartStyle {
    case line
    case bar
}

private struct BodyHealthMetricDetailModel {
    let title: String
    let value: String
    let unit: String
    let symbolName: String
    let symbolColor: Color
    let series: HealthTrendSeries
    let sleepStageSnapshot: SleepStageSnapshot?
    let chartStyle: BodyHealthMetricChartStyle
    let valueFormatter: (Double) -> String
}

private struct BodyHealthMetricDetailView: View {
    let model: BodyHealthMetricDetailModel
    @State private var selectedTrendRange = BodyHealthTrendRange.defaultValue

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                BodyHealthTrendRangeSelector(selectedRange: $selectedTrendRange)
                trendCard
                if let sleepStageSnapshot = model.sleepStageSnapshot {
                    sleepStageCard(sleepStageSnapshot)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            Image(systemName: model.symbolName)
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.symbolColor)
                .frame(width: 58, height: 58)
                .background(model.symbolColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.title)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Current")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 10)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if !model.unit.isEmpty {
                    Text(model.unit)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 94)
        .bodyCardBackground()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selectedTrendRange.chartTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            if visibleSeries.isEmpty {
                Text("No recent data")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart(visibleSeries.points) { point in
                    switch model.chartStyle {
                    case .line:
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value(model.title, point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(model.symbolColor)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value(model.title, point.value)
                        )
                        .foregroundStyle(model.symbolColor)
                        .symbolSize(28)
                    case .bar:
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value(model.title, point.value)
                        )
                        .foregroundStyle(model.symbolColor.gradient)
                        .cornerRadius(4)
                    }
                }
                .chartXScale(domain: chartXDomain)
                .chartYScale(domain: chartYDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: selectedTrendRange.axisStrideDayCount)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.18))
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.28))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(selectedTrendRange.axisLabel(for: date))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.18))
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.28))
                        AxisValueLabel {
                            if let yValue = value.as(Double.self) {
                                Text(model.valueFormatter(yValue))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .frame(height: 260)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func sleepStageCard(_ snapshot: SleepStageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's Sleep Stages")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if let date = snapshot.date {
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }

            if snapshot.isEmpty {
                Text("No sleep stages today")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                BodySleepStageChart(snapshot: snapshot)
                    .frame(height: 260)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private var visibleSeries: HealthTrendSeries {
        model.series.limited(to: selectedTrendRange)
    }

    private var chartXDomain: ClosedRange<Date> {
        let dates = visibleSeries.points.map(\.date)
        let leadingPadding: TimeInterval = 6 * 60 * 60
        let trailingPadding: TimeInterval = 18 * 60 * 60

        guard let startDate = dates.min(), let endDate = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-leadingPadding)...now.addingTimeInterval(trailingPadding)
        }

        return startDate.addingTimeInterval(-leadingPadding)...endDate.addingTimeInterval(trailingPadding)
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = visibleSeries.points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        if model.chartStyle == .bar {
            let padding = max(maximum * 0.12, 1)
            return 0...(maximum + padding)
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.12, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }
}

private struct BodyHealthTrendRangeSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedRange: BodyHealthTrendRange

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BodyHealthTrendRange.allCases) { range in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(selectedRange == range ? .accentColor : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .bodyTrendRangeTabBackground(
                            isSelected: selectedRange == range,
                            colorScheme: colorScheme
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BodySleepStageChart: View {
    let snapshot: SleepStageSnapshot

    var body: some View {
        Chart {
            ForEach(stageTransitions) { transition in
                RectangleMark(
                    xStart: .value("Transition Start", transition.startDate),
                    xEnd: .value("Transition End", transition.endDate),
                    yStart: .value("Transition Stage Start", transition.lowerStagePosition),
                    yEnd: .value("Transition Stage End", transition.upperStagePosition)
                )
                .foregroundStyle(color(for: transition.tintStage).opacity(0.20))
                .cornerRadius(7)
            }

            ForEach(snapshot.segments) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.startDate),
                    xEnd: .value("End", segment.endDate),
                    yStart: .value("Stage Start", segment.stage.chartPosition - 0.32),
                    yEnd: .value("Stage End", segment.stage.chartPosition + 0.32)
                )
                .foregroundStyle(color(for: segment.stage).gradient)
                .cornerRadius(6)
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: 0.5...4.5)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: SleepStage.allCases.map(\.chartPosition)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let position = value.as(Double.self),
                       let stage = SleepStage.stage(at: position) {
                        Text(stage.displayName)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }

    private var stageTransitions: [SleepStageTransition] {
        let sortedSegments = snapshot.segments.sorted { $0.startDate < $1.startDate }
        let maximumConnectedGap: TimeInterval = 8 * 60
        let halfConnectorWidth: TimeInterval = 2 * 60
        let connectorStageInset = 0.28

        return zip(sortedSegments, sortedSegments.dropFirst()).compactMap { previous, next in
            guard previous.stage != next.stage else {
                return nil
            }

            let gap = next.startDate.timeIntervalSince(previous.endDate)
            guard abs(gap) <= maximumConnectedGap else {
                return nil
            }

            let boundaryStart = min(previous.endDate, next.startDate).addingTimeInterval(-halfConnectorWidth)
            let boundaryEnd = max(previous.endDate, next.startDate).addingTimeInterval(halfConnectorWidth)
            let tintStage = next.stage == .awake ? previous.stage : next.stage

            return SleepStageTransition(
                id: "\(previous.id)-\(next.id)",
                startDate: boundaryStart,
                endDate: boundaryEnd,
                lowerStagePosition: min(previous.stage.chartPosition, next.stage.chartPosition) + connectorStageInset,
                upperStagePosition: max(previous.stage.chartPosition, next.stage.chartPosition) - connectorStageInset,
                tintStage: tintStage
            )
        }
    }

    private var chartXDomain: ClosedRange<Date> {
        let startDate = snapshot.segments.map(\.startDate).min() ?? Date()
        let endDate = snapshot.segments.map(\.endDate).max() ?? Date()
        let padding: TimeInterval = 15 * 60
        return startDate.addingTimeInterval(-padding)...endDate.addingTimeInterval(padding)
    }

    private var xAxisValues: [Date] {
        axisValues(strideHours: 2, minimumCount: 4)
    }

    private func axisValues(strideHours: Int, minimumCount: Int) -> [Date] {
        let calendar = Calendar.current
        let lowerBound = chartXDomain.lowerBound
        let upperBound = chartXDomain.upperBound
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: lowerBound)
        components.minute = 0
        components.second = 0
        components.nanosecond = 0

        var current = calendar.date(from: components) ?? lowerBound
        if current < lowerBound {
            current = calendar.date(byAdding: .hour, value: 1, to: current) ?? lowerBound
        }

        var values: [Date] = []
        while current <= upperBound {
            values.append(current)
            let next = calendar.date(byAdding: .hour, value: strideHours, to: current)
                ?? current.addingTimeInterval(TimeInterval(strideHours) * 60 * 60)
            guard next > current else {
                break
            }
            current = next
        }

        if values.count < minimumCount && strideHours > 1 {
            return axisValues(strideHours: 1, minimumCount: minimumCount)
        }

        return values
    }

    private func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake:
            return Color(red: 1.00, green: 0.31, blue: 0.22)
        case .rem:
            return Color(red: 0.42, green: 0.80, blue: 1.00)
        case .core:
            return Color(red: 0.24, green: 0.56, blue: 1.00)
        case .deep:
            return Color(red: 0.25, green: 0.25, blue: 0.82)
        }
    }
}

private struct SleepStageTransition: Identifiable {
    let id: String
    let startDate: Date
    let endDate: Date
    let lowerStagePosition: Double
    let upperStagePosition: Double
    let tintStage: SleepStage
}

private struct BodyHealthNoticeBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(cornerRadius: 22)
    }
}

private struct BodyHealthMetricCard: View {
    struct Model: Identifiable {
        let kind: HealthMetricKind
        let title: String
        let value: String
        let unit: String
        let symbolName: String
        let symbolColor: Color

        var id: String {
            kind.id
        }
    }

    let metric: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(metric.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                Image(systemName: metric.symbolName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(metric.symbolColor)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(metric.symbolColor.opacity(0.16))
                    )
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                    .layoutPriority(1)

                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .bodyCardBackground(cornerRadius: 28)
    }
}

struct BodyCardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .light ? Color(.systemBackground) : Color(.secondarySystemBackground))
                    .shadow(
                        color: Color.black.opacity(colorScheme == .light ? 0.07 : 0),
                        radius: 14,
                        x: 0,
                        y: 6
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .light ? 0.04 : 0), lineWidth: 1)
            )
    }
}

extension View {
    func bodyCardBackground(cornerRadius: CGFloat = 30) -> some View {
        modifier(BodyCardBackgroundModifier(cornerRadius: cornerRadius))
    }

    func bodyTrendRangeTabBackground(isSelected: Bool, colorScheme: ColorScheme) -> some View {
        background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(colorScheme == .light ? 0.12 : 0.22)
                        : (colorScheme == .light ? Color(.systemBackground) : Color(.secondarySystemBackground))
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .light ? 0.045 : 0),
                    radius: 8,
                    x: 0,
                    y: 3
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(colorScheme == .light ? 0.05 : 0),
                    lineWidth: 1
                )
        )
    }
}
