//
//  BodyHomeView.swift
//  Body
//

import SwiftUI

struct BodyHomeView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @AppStorage(BodyAppearancePreference.selectedAccentKey) private var selectedAccentRawValue = BodyAppAccent.defaultValue.rawValue

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
                                BodyHealthMetricCard(metric: metric)
                            }
                        }

                        syncButton
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
            }
        }
    }

    private var syncButton: some View {
        Button {
            Task { await workoutStore.requestAuthorizationAndRefresh() }
        } label: {
            Text(workoutStore.isRefreshing ? "Syncing Health Data..." : "Sync Health Data")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 62)
                .contentShape(Rectangle())
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(selectedAccent.color)
                .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 6)
        )
        .opacity(workoutStore.isRefreshing ? 0.55 : 1)
        .buttonStyle(.plain)
        .disabled(workoutStore.isRefreshing)
    }

    private var metricCards: [BodyHealthMetricCard.Model] {
        let summary = workoutStore.healthSummary

        return [
            BodyHealthMetricCard.Model(
                title: "Sleep",
                value: formattedSleepDuration(summary.sleep.duration),
                unit: "",
                symbolName: "bed.double.fill",
                symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00)
            ),
            metric(
                title: "Resting Heart Rate",
                summary: summary.restingHeartRate,
                unit: "bpm",
                decimals: 0,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45)
            ),
            massMetric(
                title: "Weight",
                summary: summary.bodyMass,
                symbolName: "scalemass.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00)
            ),
            metric(
                title: "Body Fat",
                summary: summary.bodyFatPercentage,
                unit: "%",
                decimals: 1,
                symbolName: "percent",
                symbolColor: Color(red: 1.00, green: 0.68, blue: 0.08)
            ),
            metric(
                title: "HRV",
                summary: summary.heartRateVariability,
                unit: "ms",
                decimals: 1,
                symbolName: "waveform.path.ecg",
                symbolColor: Color(red: 0.46, green: 0.90, blue: 0.18)
            ),
            metric(
                title: "Blood Oxygen",
                summary: summary.oxygenSaturation,
                unit: "%",
                decimals: 0,
                symbolName: "drop.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.18)
            ),
            metric(
                title: "VO2 Max",
                summary: summary.vo2Max,
                unit: "mL/kg/min",
                decimals: 1,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85)
            ),
            metric(
                title: "BMI",
                summary: summary.bodyMassIndex,
                unit: "",
                decimals: 1,
                symbolName: "person.fill",
                symbolColor: selectedAccent.color
            )
        ]
    }

    private var selectedAccent: BodyAppAccent {
        BodyAppAccent.storedValue(from: selectedAccentRawValue)
    }

    private func metric(
        title: String,
        summary: HealthMetricSummary,
        unit: String,
        decimals: Int,
        symbolName: String,
        symbolColor: Color
    ) -> BodyHealthMetricCard.Model {
        BodyHealthMetricCard.Model(
            title: title,
            value: summary.value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor
        )
    }

    private func massMetric(
        title: String,
        summary: HealthMetricSummary,
        symbolName: String,
        symbolColor: Color
    ) -> BodyHealthMetricCard.Model {
        let display = summary.value.map { BodyValueFormat.massDisplay(kilograms: $0) }
        return BodyHealthMetricCard.Model(
            title: title,
            value: display?.value ?? "--",
            unit: display?.unit ?? "",
            symbolName: symbolName,
            symbolColor: symbolColor
        )
    }

    private func formattedSleepDuration(_ duration: TimeInterval?) -> String {
        duration.map { BodyValueFormat.durationText(for: $0) } ?? "--"
    }
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
        let title: String
        let value: String
        let unit: String
        let symbolName: String
        let symbolColor: Color

        var id: String {
            title
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
}
