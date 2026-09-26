//
//  BodyMetricWarningCard.swift
//  Body
//

import Charts
import SwiftUI

/// The close button at a warning card's top right. Shared by the threshold
/// warning cards and the Body Radar card.
struct BodyWarningCardCloseButton: View {
    /// Grows the tap area to the 44 pt minimum without moving the glyph or the
    /// header's height: the slop is padded in and cancelled out again.
    private static let tapSlop: CGFloat = 11

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                // A plain gray, not the hierarchical style, which would take the
                // card header's warning tint.
                .foregroundStyle(Color.secondary)
                .padding(Self.tapSlop)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-Self.tapSlop)
        .accessibilityLabel(Text("Close"))
    }
}

/// Mirrors Apple's threshold notifications (Low/High Heart Rate, Low Blood
/// Oxygen, plus Body's High Respiratory Rate and High Skin Temperature) on the
/// metric detail page: the sentence names the episode's first
/// past-threshold reading, and the chart shows the readings around it against
/// the threshold rule.
struct BodyMetricWarningCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let event: MetricWarningEvent
    let samples: [HealthTrendDataPoint]
    let window: DateInterval
    let tint: Color
    /// Optional report-out of the scrub callout, so the detail page can float it on the
    /// topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    var floatingCallout: BodyChartFloatingCalloutState? = nil
    /// Closes the card once the user has read it. Nil hides the close button.
    var onDismiss: (() -> Void)? = nil

    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue

    @State private var selectedDate: Date?

    private var temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.TemperatureUnitPreference.storedValue(from: selectedTemperatureUnitRawValue)
    }

    /// Wrist temperature is stored in °C; a Fahrenheit user sees the chart, the
    /// rule and the callout converted. Every other kind draws its values as is.
    private func displayValue(_ value: Double) -> Double {
        guard event.kind == .highWristTemperature else {
            return value
        }

        return BodyValueFormat.temperatureValue(
            celsius: value,
            temperatureUnitPreference: temperatureUnitPreference
        ).value
    }

    /// The limit this episode was detected against — the user's custom threshold
    /// when they set one, so the sentence and the rule match what fired.
    private var threshold: Double {
        displayValue(event.threshold)
    }

    /// The readings in display units (see `displayValue`).
    private var displaySamples: [HealthTrendDataPoint] {
        guard event.kind == .highWristTemperature else {
            return samples
        }

        return samples.map { HealthTrendDataPoint(date: $0.date, value: displayValue($0.value)) }
    }

    /// The episode in display units, for the dot thinning's threshold test.
    private var displayEvent: MetricWarningEvent {
        guard event.kind == .highWristTemperature else {
            return event
        }

        var converted = event
        converted.threshold = threshold
        converted.extremeValue = displayValue(event.extremeValue)
        return converted
    }

    /// Matches the detail page's Day View chart transition.
    private var chartTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                title
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Spacer(minLength: 0)

                if let onDismiss {
                    BodyWarningCardCloseButton(action: onDismiss)
                }
            }
            .foregroundStyle(.yellow)

            Text(sentence)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if event.kind.excludesWorkouts {
                Text("If you were working out, this warning will disappear once the workout is logged.")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !samples.isEmpty {
                chart
                    // Scoped like the Day View chart: only sample changes animate,
                    // so the marks glide instead of snapping when the day (or the
                    // threshold) moves, and the outer transaction keeps inherited
                    // scroll/date-picker animations out.
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0), value: samples)
                    .transition(chartTransition)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
        .onAppear { BodyConfirmationHaptics.playWarningAppeared(event) }
    }

    @ViewBuilder
    private var title: some View {
        switch event.kind {
        case .lowHeartRate:
            Text("Low Heart Rate")
        case .highHeartRate:
            Text("High Heart Rate")
        case .lowBloodOxygen:
            Text("Low Blood Oxygen")
        case .highRespiratoryRate:
            Text("High Respiratory Rate")
        case .highWristTemperature:
            Text("High Skin Temperature")
        }
    }

    private var sentence: String {
        let time = timeText(for: event.startDate)
        switch event.kind {
        case .lowHeartRate:
            return String(localized: "Your heart rate fell below \(Int(threshold)) BPM starting at \(time).")
        case .highHeartRate:
            return String(localized: "Your heart rate rose above \(Int(threshold)) BPM starting at \(time).")
        case .lowBloodOxygen:
            return String(localized: "Your blood oxygen fell below \(Int(threshold))% starting at \(time).")
        case .highRespiratoryRate:
            return String(localized: "Your respiratory rate rose above \(Int(threshold)) br/min starting at \(time).")
        case .highWristTemperature:
            let temperature = BodyMetricWarningTemperatureText.text(
                celsius: event.threshold,
                temperatureUnitPreference: temperatureUnitPreference
            )
            return String(localized: "Your skin temperature rose above \(temperature) starting at \(time).")
        }
    }

    private var valueLabel: LocalizedStringKey {
        switch event.kind {
        case .lowHeartRate, .highHeartRate:
            return "Heart Rate"
        case .lowBloodOxygen:
            return "Blood Oxygen"
        case .highRespiratoryRate:
            return "Respiratory Rate"
        case .highWristTemperature:
            return "Skin Temperature"
        }
    }

    /// Axis and callout precision: whole numbers except for temperature, whose
    /// readings differ by tenths of a degree.
    private var valueDecimals: Int {
        event.kind == .highWristTemperature ? 1 : 0
    }

    private func isPastThreshold(_ value: Double) -> Bool {
        event.kind.isAbove ? value > threshold : value < threshold
    }

    private var chart: some View {
        // Sources can stamp two readings at the same instant, so the marks are
        // keyed by position rather than by date.
        let samples = displaySamples
        let indexedSamples = Array(samples.enumerated())
        // The line runs through every reading; the dots are thinned so their
        // rings stay legible on a dense per-second series.
        let indexedPointMarks = Array(
            MetricThresholdWarning.chartPointMarks(for: samples, in: window, of: displayEvent).enumerated()
        )

        return Chart {
            ForEach(indexedSamples, id: \.offset) { _, sample in
                LineMark(
                    x: .value("Time", sample.date),
                    y: .value(valueLabel, sample.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            ForEach(indexedPointMarks, id: \.offset) { _, sample in
                PointMark(
                    x: .value("Time", sample.date),
                    y: .value(valueLabel, sample.value)
                )
                .symbol {
                    // The same ring the Day View and range trend charts draw, so
                    // a warning's readings read as that same series. Filled — the
                    // form those charts reserve for their latest reading — marks
                    // the past-threshold readings this card is about.
                    BodyLineChartPreviewPointSymbol(
                        tintColor: isPastThreshold(sample.value) ? .yellow : tint,
                        isCurrent: isPastThreshold(sample.value),
                        pointDiameter: BodyHealthMetricDayChart.pointDiameter,
                        currentPointDiameter: BodyHealthMetricDayChart.currentPointDiameter
                    )
                }
            }

            // Unlabelled: the sentence above the chart already names the
            // threshold, so a value riding the rule only repeated it.
            RuleMark(y: .value("Threshold", threshold))
                .foregroundStyle(.yellow)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))

            if let selectedSample {
                RuleMark(x: .value("Selected Time", selectedSample.date))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        // Stands down while the floating callout renders, or the
                        // callout draws twice.
                        if floatingCallout == nil {
                            selectionAnnotation(for: selectedSample)
                        }
                    }

                // The same filled dot the Day View and range trend charts drop
                // on the scrubbed reading, so the callout's value is anchored
                // to a point on the line.
                PointMark(
                    x: .value("Selected Time", selectedSample.date),
                    y: .value(valueLabel, selectedSample.value)
                )
                .foregroundStyle(isPastThreshold(selectedSample.value) ? .yellow : tint)
                .symbolSize(82)
            }
        }
        .chartXScale(domain: window.start...window.end)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    // A mark on the trailing domain edge would have its label
                    // truncated by the plot bounds, so it goes unlabelled.
                    if let date = value.as(Date.self), isInteriorAxisDate(date) {
                        Text(timeText(for: date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let metricValue = value.as(Double.self) {
                        Text(metricValue.formatted(.number.precision(.fractionLength(valueDecimals))))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        // Sized so the whole card matches a home trend comparison card, which
        // it sits directly above on a metric detail page: that card's chart is
        // 128, but it also carries a divider and an averages row this one has
        // no equivalent of, so the chart absorbs the 77pt difference.
        .frame(height: 205)
        .bodyChartHoldToScrub($selectedDate)
        .bodyChartScrubHaptics(selection: selectedSample?.date)
        .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedSample?.date, centersOnDayInterval: false) {
            guard let selectedSample else {
                return AnyView(EmptyView())
            }
            return AnyView(selectionAnnotation(for: selectedSample))
        }
    }

    /// The reading under the finger, matched by time the way the trend charts do.
    private var selectedSample: HealthTrendDataPoint? {
        guard let selectedDate else {
            return nil
        }

        return displaySamples.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private func selectionAnnotation(for sample: HealthTrendDataPoint) -> BodyChartSelectionAnnotation {
        BodyChartSelectionAnnotation(
            eyebrow: nil,
            values: [
                BodyChartSelectionValue(
                    title: nil,
                    value: formattedValue(sample.value),
                    color: isPastThreshold(sample.value) ? .yellow : tint
                )
            ],
            date: sample.date,
            dateText: timeText(for: sample.date)
        )
    }

    /// Same units the sentence above the chart names the threshold in.
    private func formattedValue(_ value: Double) -> String {
        let number = BodyValueFormat.numberText(value, decimals: valueDecimals)
        switch event.kind {
        case .lowHeartRate, .highHeartRate:
            return number + " BPM"
        case .lowBloodOxygen:
            return number + "%"
        case .highRespiratoryRate:
            return number + " " + String(localized: "br/min")
        case .highWristTemperature:
            return number + "°" + temperatureUnitPreference.unitLabel
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = displaySamples.map(\.value).filter(\.isFinite)
        // Temperature moves by tenths, so five degrees of headroom would flatten
        // the line; a degree each side keeps the crossing visible.
        let padding: Double = event.kind == .highWristTemperature ? 1 : 5
        let lower = (min(values.min() ?? threshold, threshold)).rounded(.down) - padding
        let upper = max(values.max() ?? threshold, threshold) + padding
        return lower...max(upper, lower + 1)
    }

    private func isInteriorAxisDate(_ date: Date) -> Bool {
        date < window.end.addingTimeInterval(-window.duration * 0.08)
    }

    private func timeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
