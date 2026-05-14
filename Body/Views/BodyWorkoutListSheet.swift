//
//  BodyWorkoutListSheet.swift
//  Body
//

import SwiftUI

enum BodyWorkoutListSelection: Identifiable {
    case day(WorkoutDaySummary)
    case type(BodyWorkoutType, workouts: [WorkoutSummary])

    var id: String {
        switch self {
        case .day(let day):
            return "day-\(day.dateKey)"
        case .type(let type, _):
            return "type-\(type.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .day(let day):
            return dayTitle(for: day)
        case .type(let type, _):
            return type.displayName
        }
    }

    var subtitle: String {
        BodyValueFormat.workoutCountText(workouts.count)
    }

    var iconName: String {
        switch self {
        case .day:
            return "calendar"
        case .type(let type, _):
            return type.symbolName
        }
    }

    var accentColor: Color {
        switch self {
        case .day(let day):
            return day.primaryWorkoutType?.color ?? Color.accentColor
        case .type(let type, _):
            return type.color
        }
    }

    var workouts: [WorkoutSummary] {
        switch self {
        case .day(let day):
            return day.workouts.sorted { $0.startDate < $1.startDate }
        case .type(_, let workouts):
            return workouts
        }
    }

    var totalDuration: TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }

    var totalEnergyKilocalories: Double {
        workouts.reduce(0) { $0 + ($1.activeEnergyKilocalories ?? 0) }
    }

    private func dayTitle(for day: WorkoutDaySummary) -> String {
        let parts = day.dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.bodyGregorian.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
              ) else {
            return "Day \(day.day)"
        }

        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

struct BodyWorkoutListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selection: BodyWorkoutListSelection

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard

                    Text("Workouts")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.top, 4)

                    if selection.workouts.isEmpty {
                        emptyState
                    } else {
                        ForEach(selection.workouts) { workout in
                            BodyWorkoutRecordRow(workout: workout)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 16) {
            Image(systemName: selection.iconName)
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selection.accentColor)
                .frame(width: 58, height: 58)
                .background(selection.accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(selection.title)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("\(selection.subtitle) · \(BodyValueFormat.durationText(for: selection.totalDuration))")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 12)

            Text(BodyValueFormat.energyText(kilocalories: selection.totalEnergyKilocalories))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 94)
        .bodyCardBackground()
    }

    private var emptyState: some View {
        Text("No workouts for this selection.")
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 28)
            .bodyCardBackground()
    }
}

private struct BodyWorkoutRecordRow: View {
    @AppStorage(BodyAppearancePreference.selectedUnitPreferenceKey) private var selectedUnitPreferenceRawValue = BodyValueFormat.UnitPreference.defaultValue.rawValue
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: workout.type.symbolName)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(workout.type.color)
                .frame(width: 54, height: 54)
                .background(workout.type.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(workout.type.displayName)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(workoutDetailText)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 5) {
                Text(BodyValueFormat.durationText(for: workout.duration))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let energy = workout.activeEnergyKilocalories {
                    Text(BodyValueFormat.energyText(kilocalories: energy))
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 88)
        .bodyCardBackground()
    }

    private var workoutDetailText: String {
        var details = [timeText(for: workout.startDate)]

        if let distanceMeters = workout.distanceMeters, distanceMeters > 0 {
            details.append(
                BodyValueFormat.distanceText(
                    meters: distanceMeters,
                    unitPreference: selectedUnitPreference
                )
            )
        }

        details.append(workout.sourceName)
        return details.joined(separator: " · ")
    }

    private var selectedUnitPreference: BodyValueFormat.UnitPreference {
        BodyValueFormat.UnitPreference.storedValue(from: selectedUnitPreferenceRawValue)
    }
}

private func timeText(for date: Date) -> String {
    date.formatted(.dateTime.hour().minute())
}
