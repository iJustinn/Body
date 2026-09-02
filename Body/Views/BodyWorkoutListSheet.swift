//
//  BodyWorkoutListSheet.swift
//  Body
//

import SwiftUI

enum BodyWorkoutListSelection: Identifiable {
    /// The day's workouts, sorted ascending by start date once at construction
    /// (`BodyWorkoutListSelection.day(_:)` below) rather than on every read of
    /// `workouts`.
    case day(WorkoutDaySummary, workouts: [WorkoutSummary])
    case type(BodyWorkoutType, workouts: [WorkoutSummary])

    /// Builds a `.day` selection with its workouts pre-sorted, so `workouts`
    /// below is a plain stored read.
    static func day(_ day: WorkoutDaySummary) -> BodyWorkoutListSelection {
        .day(day, workouts: day.workouts.sorted { $0.startDate < $1.startDate })
    }

    var id: String {
        switch self {
        case .day(let day, _):
            return "day-\(day.dateKey)"
        case .type(let type, _):
            return "type-\(type.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .day(let day, _):
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

    func accentColor(palette: BodyWorkoutColorPalette) -> Color {
        switch self {
        case .day(let day, _):
            return day.primaryWorkoutType.map { palette.color(for: $0) } ?? Color.accentColor
        case .type(let type, _):
            return palette.color(for: type)
        }
    }

    var workouts: [WorkoutSummary] {
        switch self {
        case .day(_, let workouts):
            return workouts
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
            return String(localized: "Day \(day.day)")
        }

        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

struct BodyWorkoutListSheet: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.workoutColorPalette) private var workoutColorPalette
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @State private var selectedWorkout: WorkoutSummary?
    @Namespace private var workoutZoom
    let selection: BodyWorkoutListSelection

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    summaryCard

                    Text("Workouts")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.top, 4)

                    if selection.workouts.isEmpty {
                        emptyState
                    } else {
                        ForEach(selection.workouts) { workout in
                            Button {
                                selectedWorkout = workout
                            } label: {
                                BodyWorkoutRecordRow(
                                    workout: workout,
                                    customName: workoutStore.workoutCustomNames[workout.id],
                                    recordStanding: workoutStore.rowRecordStanding(for: workout)
                                )
                                    .matchedTransitionSource(id: workout.id, in: workoutZoom) {
                                        $0.clipShape(.rect(cornerRadius: 30, style: .continuous))
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows workout details")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .bodySheetBackground()
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selectedWorkout) { workout in
                BodyWorkoutDetailSheet(workout: workout)
                    .environmentObject(workoutStore)
                    .navigationTransition(.zoom(sourceID: workout.id, in: workoutZoom))
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 16) {
            Image(systemName: selection.iconName)
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selection.accentColor(palette: workoutColorPalette))
                .frame(width: 58, height: 58)
                .background(selection.accentColor(palette: workoutColorPalette).opacity(0.14))
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

            Text(BodyValueFormat.energyText(
                kilocalories: selection.totalEnergyKilocalories,
                energyUnitPreference: selectedEnergyUnitPreference
            ))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 94)
        .bodyCardBackground(translucent: true)
    }

    private var emptyState: some View {
        Text("No workouts for this selection.")
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 28)
            .bodyCardBackground(translucent: true)
    }

    private var selectedEnergyUnitPreference: BodyValueFormat.EnergyUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.EnergyUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.EnergyUnitPreference.storedValue(from: selectedEnergyUnitRawValue)
    }
}

private struct BodyWorkoutRecordRow: View {
    @Environment(\.workoutColorPalette) private var workoutColorPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue = BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    let workout: WorkoutSummary
    var customName: String? = nil
    /// The workout's strongest record standing, or nil when it holds none. Computed
    /// at the call site — the row is a pure struct with no store access.
    var recordStanding: WorkoutRecordStanding? = nil

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: workout.type.symbolName)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(workoutColorPalette.color(for: workout.type))
                .frame(width: 54, height: 54)
                .background(workoutColorPalette.color(for: workout.type).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(customName ?? workout.type.displayName)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let recordStanding {
                        BodyWorkoutPRGlyph(standing: recordStanding)
                        // The baseline scan usually finishes after this sheet is up,
                        // so the trophy fades into a settled row.
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeIn(duration: 0.3), value: recordStanding)

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
                    Text(BodyValueFormat.energyText(
                        kilocalories: energy,
                        energyUnitPreference: selectedEnergyUnitPreference
                    ))
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
        .bodyCardBackground(translucent: true)
    }

    private var workoutDetailText: String {
        var details = [timeText(for: workout.startDate)]

        if let distanceMeters = workout.distanceMeters, distanceMeters > 0 {
            details.append(
                BodyValueFormat.distanceText(
                    meters: distanceMeters,
                    distanceUnitPreference: selectedDistanceUnitPreference
                )
            )
        }

        details.append(workout.sourceName)
        return details.joined(separator: " · ")
    }

    private var selectedDistanceUnitPreference: BodyValueFormat.DistanceUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.DistanceUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.DistanceUnitPreference.storedValue(from: selectedDistanceUnitRawValue)
    }

    private var selectedEnergyUnitPreference: BodyValueFormat.EnergyUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.EnergyUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.EnergyUnitPreference.storedValue(from: selectedEnergyUnitRawValue)
    }
}

private func timeText(for date: Date) -> String {
    date.formatted(.dateTime.hour().minute())
}
