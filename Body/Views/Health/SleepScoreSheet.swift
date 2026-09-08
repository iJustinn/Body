//
//  SleepScoreSheet.swift
//  Body
//

import SwiftUI

struct SleepScoreDetailsSelection: Identifiable {
    let date: Date
    let score: SleepScoreSummary

    var id: String {
        "\(date.timeIntervalSinceReferenceDate)-\(score.total)"
    }
}

struct SleepScoreDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selection: SleepScoreDetailsSelection
    let accentColor: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detailed Scoring")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(selection.score.categories) { category in
                                BodySleepScoreCategoryRow(
                                    category: category,
                                    color: bodySleepScoreColor(for: category.kind, accentColor: accentColor)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Sleep Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bodySheetBackground(Color(.systemBackground))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .frame(width: 58, height: 58)
                .background(accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(selection.score.total)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)

                    Text("/100")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(selection.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(selection.score.comment)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct BodySleepScoreCategoryRow: View {
    let category: SleepScoreCategory
    let color: Color

    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue

    private var selectedTemperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.TemperatureUnitPreference.storedValue(from: selectedTemperatureUnitRawValue)
    }

    private var valueText: String? {
        guard let temperatureCelsius = category.temperatureCelsius else {
            return category.valueDescription
        }

        let display = BodyValueFormat.temperatureDisplay(
            celsius: temperatureCelsius,
            temperatureUnitPreference: selectedTemperatureUnitPreference
        )
        return "\(display.value)\(display.unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(category.kind.displayName)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    if let valueText {
                        Text(valueText)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 12)

                Text("\(category.points)/\(category.maximumPoints)")
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))

                    Capsule()
                        .fill(color.gradient)
                        .frame(width: proxy.size.width * category.progress)
                }
            }
            .frame(height: 9)
        }
    }
}

private func bodySleepScoreColor(for kind: SleepScoreCategory.Kind, accentColor: Color) -> Color {
    switch kind {
    case .duration:
        return accentColor
    case .continuity:
        return Color(red: 0.14, green: 0.72, blue: 0.42)
    case .consistency:
        return Color(red: 0.10, green: 0.58, blue: 1.00)
    case .rem:
        return Color(red: 0.42, green: 0.80, blue: 1.00)
    case .deep:
        return Color(red: 0.25, green: 0.25, blue: 0.82)
    case .pressure:
        return Color(red: 0.58, green: 0.42, blue: 0.95)
    case .vitals:
        return Color(red: 1.00, green: 0.25, blue: 0.45)
    case .temperature:
        return Color(red: 1.00, green: 0.57, blue: 0.24)
    }
}

