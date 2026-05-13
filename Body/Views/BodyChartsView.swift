//
//  BodyChartsView.swift
//  Body
//

import SwiftUI

struct BodyChartsView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @State private var selectedMonth = Calendar.bodyGregorian.component(.month, from: Date())
    @State private var selectedYear = Calendar.bodyGregorian.component(.year, from: Date())
    @State private var pendingMonthSelection: BodyMonthYear?
    @State private var selectedWorkouts: BodyWorkoutListSelection?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    BodyMonthYearPicker(
                        selectedMonth: $selectedMonth,
                        selectedYear: $selectedYear,
                        onMonthYearRequested: requestMonthYearSelection
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    if let pendingMonthSelection {
                        BodyChartsLoadingBanner(monthYear: pendingMonthSelection)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    ZStack(alignment: .top) {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 22) {
                                WorkoutCalendarView(
                                    snapshot: selectedSnapshot,
                                    style: .widgetLarge,
                                    fillsAvailableHeight: false,
                                    onSelectDay: { day in
                                        selectedWorkouts = .day(day)
                                    }
                                )
                                .padding(14)
                                .bodyCardBackground()

                                WorkoutTypeBreakdownView(
                                    snapshot: selectedSnapshot,
                                    style: .app,
                                    onSelectType: { type in
                                        selectedWorkouts = .type(
                                            type,
                                            workouts: workouts(for: type)
                                        )
                                    }
                                )
                                .padding(14)
                                .bodyCardBackground()
                            }
                            .padding(.horizontal)
                            .padding(.top, 30)
                            .padding(.bottom, 110)
                        }

                        BodyChartsScrollTransitionShade()
                    }
                }
            }
            .sheet(item: $selectedWorkouts) { selection in
                BodyWorkoutListSheet(selection: selection)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                await workoutStore.loadRecentWorkoutMonthsIfNeeded()
            }
        }
    }

    private var selectedSnapshot: WorkoutMonthSnapshot {
        workoutStore.snapshot(month: selectedMonth, year: selectedYear)
    }

    private func workouts(for type: BodyWorkoutType) -> [WorkoutSummary] {
        selectedSnapshot.days
            .flatMap(\.workouts)
            .filter { $0.type == type }
            .sorted { $0.startDate > $1.startDate }
    }

    private func requestMonthYearSelection(_ monthYear: BodyMonthYear) -> Bool {
        guard selectedMonth != monthYear.month || selectedYear != monthYear.year else {
            return true
        }

        if workoutStore.hasLoadedSnapshot(month: monthYear.month, year: monthYear.year) {
            applyMonthSelection(monthYear)
            return true
        }

        pendingMonthSelection = monthYear
        Task {
            let didLoad = await workoutStore.loadMonthIfNeeded(month: monthYear.month, year: monthYear.year)
            await MainActor.run {
                if didLoad {
                    applyMonthSelection(monthYear)
                }

                if pendingMonthSelection == monthYear {
                    pendingMonthSelection = nil
                }
            }
        }

        return false
    }

    private func applyMonthSelection(_ monthYear: BodyMonthYear) {
        selectedMonth = monthYear.month
        selectedYear = monthYear.year
    }
}

private struct BodyChartsScrollTransitionShade: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color(.systemGroupedBackground).opacity(0.92),
                Color(.systemGroupedBackground).opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 30)
        .allowsHitTesting(false)
    }
}

private struct BodyChartsLoadingBanner: View {
    let monthYear: BodyMonthYear

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Loading \(monthYear.displayName)")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

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

#Preview {
    BodyChartsView()
        .environmentObject(HealthKitWorkoutStore())
}
