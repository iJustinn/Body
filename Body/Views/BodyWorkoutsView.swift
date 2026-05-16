//
//  BodyWorkoutsView.swift
//  Body
//

import SwiftUI

struct BodyWorkoutsView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMonth = Calendar.bodyGregorian.component(.month, from: Date())
    @State private var selectedYear = Calendar.bodyGregorian.component(.year, from: Date())
    @State private var pendingMonthSelection: BodyMonthYear?
    @State private var searchText = ""
    @State private var showingSortSheet = false
    @State private var showingFilterSheet = false
    @State private var selectedSortOption: BodyWorkoutListSortOption = .dateDescending
    @State private var selectedWorkoutTypes = Set(BodyWorkoutType.allCases)
    @State private var selectedWorkoutForDetails: WorkoutSummary?
    @State private var selectedWorkoutListSelection: BodyWorkoutListSelection?
    @State private var isListLoaded = false

    private var monthSwitchTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
    }

    private var monthIdentity: String {
        "\(selectedYear)-\(selectedMonth)"
    }

    var body: some View {
        let visibleWorkouts = filteredWorkouts

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
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if let pendingMonthSelection {
                        BodyWorkoutMonthLoadingBanner(monthYear: pendingMonthSelection)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    searchAndControlsRow
                        .padding(.horizontal)
                        .padding(.top, 8)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            workoutCalendarCard
                                .id("calendar-\(monthIdentity)")
                                .transition(monthSwitchTransition)

                            Group {
                                if visibleWorkouts.isEmpty {
                                    emptyStateView
                                        .transition(.opacity)
                                        .animation(.easeInOut, value: visibleWorkouts.isEmpty)
                                } else {
                                    LazyVStack(spacing: 12) {
                                        ForEach(visibleWorkouts) { workout in
                                            Button {
                                                selectedWorkoutForDetails = workout
                                            } label: {
                                                BodyWorkoutExpenseStyleRow(
                                                    workout: workout,
                                                    titleFontSize: 23,
                                                    metadataFontSize: 15,
                                                    amountFontSize: 26
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityHint("Shows workout details")
                                        }
                                    }
                                }
                            }
                            .id("list-\(monthIdentity)")
                            .transition(monthSwitchTransition)

                            workoutTypeSummaryCard(workouts: allWorkouts)
                                .id("summary-\(monthIdentity)")
                                .transition(monthSwitchTransition)
                        }
                        .padding(.horizontal)
                        .padding(.top, 32)
                        .padding(.bottom, 110)
                    }
                    .refreshable {
                        await workoutStore.requestAuthorizationAndRefresh()
                    }
                    .opacity(isListLoaded ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: isListLoaded)
                    .animation(.easeInOut(duration: 0.2), value: selectedSortOption)
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [
                                Color(.systemGroupedBackground),
                                Color(.systemGroupedBackground).opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 24)
                        .allowsHitTesting(false)
                    }
                }
            }
            .sheet(isPresented: $showingSortSheet) {
                BodyWorkoutSortView(selectedSortOption: $selectedSortOption)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingFilterSheet) {
                BodyWorkoutFilterView(
                    selectedWorkoutTypes: $selectedWorkoutTypes,
                    workoutTypes: availableWorkoutTypes
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedWorkoutForDetails) { workout in
                BodyWorkoutDetailSheet(workout: workout)
            }
            .sheet(item: $selectedWorkoutListSelection) { selection in
                BodyWorkoutListSheet(selection: selection)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                await workoutStore.loadRecentWorkoutMonthsIfNeeded()
                animateListInIfNeeded()
            }
            .onAppear {
                animateListInIfNeeded()
            }
        }
    }

    private var selectedSnapshot: WorkoutMonthSnapshot {
        workoutStore.snapshot(month: selectedMonth, year: selectedYear)
    }

    private var allWorkouts: [WorkoutSummary] {
        selectedSnapshot.days.flatMap(\.workouts)
    }

    private var availableWorkoutTypes: [BodyWorkoutType] {
        let types = Set(allWorkouts.map(\.type))
        return BodyWorkoutType.allCases
            .filter { types.contains($0) }
            .sorted {
                if $0.displayPriority == $1.displayPriority {
                    return $0.displayName < $1.displayName
                }

                return $0.displayPriority > $1.displayPriority
            }
    }

    private var filteredWorkouts: [WorkoutSummary] {
        let normalizedSearchText = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let searchedWorkouts = allWorkouts.filter { workout in
            selectedWorkoutTypes.contains(workout.type)
                && (
                    normalizedSearchText.isEmpty
                        || workout.type.displayName.lowercased().contains(normalizedSearchText)
                        || workout.sourceName.lowercased().contains(normalizedSearchText)
                        || dateSearchText(for: workout.startDate).contains(normalizedSearchText)
                )
        }

        return sorted(workouts: searchedWorkouts)
    }

    private var hasActiveFilters: Bool {
        BodyWorkoutFilterLogic.hasActiveFilters(selectedTypes: selectedWorkoutTypes)
    }

    private var localizedMonthTitle: String {
        guard let date = Calendar.bodyGregorian.date(
            from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)
        ) else {
            return "\(selectedMonth)"
        }

        let formatter = DateFormatter()
        formatter.calendar = .bodyGregorian
        formatter.locale = .current
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    private var searchAndControlsRow: some View {
        HStack(spacing: 10) {
            Button {
                showingSortSheet = true
            } label: {
                searchControlCard(iconName: "arrow.up.arrow.down", size: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sort workouts")

            Button {
                showingFilterSheet = true
            } label: {
                searchControlCard(iconName: "line.3.horizontal.decrease.circle", size: 19)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter workouts")

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Search workouts", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 46)
            .bodyWorkoutsToolbarCardBackground(colorScheme: colorScheme)
        }
        .frame(height: 46)
    }

    private var workoutCalendarCard: some View {
        WorkoutCalendarView(
            snapshot: selectedSnapshot,
            style: .widgetLarge,
            fillsAvailableHeight: false,
            onSelectDay: { day in
                selectedWorkoutListSelection = .day(day)
            }
        )
        .padding(14)
        .bodyCardBackground()
    }

    private func searchControlCard(iconName: String, size: CGFloat) -> some View {
        Image(systemName: iconName)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(.accentColor)
            .frame(width: 46, height: 46)
            .bodyWorkoutsToolbarCardBackground(colorScheme: colorScheme)
    }

    private func workoutTypeSummaryCard(workouts: [WorkoutSummary]) -> some View {
        VStack(spacing: 18) {
            monthlySummaryHeader(workouts: workouts)

            Divider()
                .overlay(Color.secondary.opacity(0.18))

            WorkoutTypeBreakdownView(
                snapshot: selectedSnapshot,
                style: .app,
                onSelectType: { type in
                    selectedWorkoutListSelection = .type(
                        type,
                        workouts: workoutsForType(type)
                    )
                }
            )
        }
        .padding(18)
        .bodyCardBackground()
    }

    private func monthlySummaryHeader(workouts: [WorkoutSummary]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total for \(localizedMonthTitle)")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)

                Text(BodyValueFormat.durationText(for: totalDuration(for: workouts)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Workouts")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)

                Text("\(workouts.count)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .fontWeight(.bold)
            }
        }
    }

    private func workoutsForType(_ type: BodyWorkoutType) -> [WorkoutSummary] {
        allWorkouts
            .filter { $0.type == type }
            .sorted { $0.startDate > $1.startDate }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.6))
                .padding()

            Text("No Workouts Found")
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)

            if !searchText.isEmpty {
                Text("Try adjusting your search or filters")
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else if hasActiveFilters {
                Text("Try selecting more workout types in the filter")
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    selectedWorkoutTypes = Set(BodyWorkoutType.allCases)
                } label: {
                    Text("Reset Filters")
                        .foregroundColor(.accentColor)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor, lineWidth: 1)
                        )
                }
                .padding(.top, 8)
            } else {
                Text("No workouts for \(localizedMonthTitle) \(selectedYear)")
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let didLoad = await withTaskGroup(of: Bool?.self) { group in
                group.addTask {
                    await workoutStore.loadMonthIfNeeded(month: monthYear.month, year: monthYear.year)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                    return nil
                }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }
            await MainActor.run {
                guard pendingMonthSelection == monthYear else {
                    return
                }

                if didLoad == true {
                    applyMonthSelection(monthYear)
                }

                pendingMonthSelection = nil
            }
        }

        return false
    }

    private func applyMonthSelection(_ monthYear: BodyMonthYear) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            selectedMonth = monthYear.month
            selectedYear = monthYear.year
        }
    }

    private func sorted(workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        switch selectedSortOption {
        case .dateDescending:
            return workouts.sorted { $0.startDate > $1.startDate }
        case .dateAscending:
            return workouts.sorted { $0.startDate < $1.startDate }
        case .durationDescending:
            return workouts.sorted {
                if $0.duration == $1.duration {
                    return $0.startDate > $1.startDate
                }

                return $0.duration > $1.duration
            }
        case .energyDescending:
            return workouts.sorted {
                if ($0.activeEnergyKilocalories ?? 0) == ($1.activeEnergyKilocalories ?? 0) {
                    return $0.startDate > $1.startDate
                }

                return ($0.activeEnergyKilocalories ?? 0) > ($1.activeEnergyKilocalories ?? 0)
            }
        case .workoutType:
            return workouts.sorted {
                if $0.type.displayName == $1.type.displayName {
                    return $0.startDate > $1.startDate
                }

                return $0.type.displayName < $1.type.displayName
            }
        }
    }

    private func totalDuration(for workouts: [WorkoutSummary]) -> TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }

    private func dateSearchText(for date: Date) -> String {
        date.formatted(.dateTime.month(.wide).day().year().hour().minute()).lowercased()
    }

    private func animateListInIfNeeded() {
        guard !isListLoaded else {
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                withAnimation {
                    isListLoaded = true
                }
            }
        }
    }
}

private struct BodyWorkoutMonthLoadingBanner: View {
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

enum BodyWorkoutFilterLogic {
    static func toggled(_ workoutType: BodyWorkoutType, in selectedTypes: Set<BodyWorkoutType>) -> Set<BodyWorkoutType> {
        var updatedTypes = selectedTypes
        if updatedTypes.contains(workoutType) {
            updatedTypes.remove(workoutType)
        } else {
            updatedTypes.insert(workoutType)
        }
        return updatedTypes
    }

    static func hasActiveFilters(selectedTypes: Set<BodyWorkoutType>) -> Bool {
        selectedTypes != Set(BodyWorkoutType.allCases)
    }
}

private enum BodyWorkoutListSortOption: String, CaseIterable, Identifiable {
    case dateDescending
    case dateAscending
    case durationDescending
    case energyDescending
    case workoutType

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dateDescending:
            return "Newest"
        case .dateAscending:
            return "Oldest"
        case .durationDescending:
            return "Duration"
        case .energyDescending:
            return "Energy"
        case .workoutType:
            return "Workout Type"
        }
    }
}

struct BodyWorkoutRowPresentation {
    let detailIconName: String
    let detailText: String
    let trailingEnergyText: String?

    init(
        workout: WorkoutSummary,
        locale: Locale = .current,
        unitPreference: BodyValueFormat.UnitPreference = .system,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference? = nil,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference = .kilocalories
    ) {
        let energyText = workout.activeEnergyKilocalories.map {
            BodyValueFormat.energyText(
                kilocalories: $0,
                locale: locale,
                energyUnitPreference: energyUnitPreference
            )
        }

        if let distanceMeters = workout.distanceMeters, distanceMeters > 0 {
            detailIconName = "map.fill"
            if let distanceUnitPreference {
                detailText = BodyValueFormat.distanceText(
                    meters: distanceMeters,
                    locale: locale,
                    distanceUnitPreference: distanceUnitPreference
                )
            } else {
                detailText = BodyValueFormat.distanceText(
                    meters: distanceMeters,
                    locale: locale,
                    unitPreference: unitPreference
                )
            }
            trailingEnergyText = energyText
        } else if let energyText {
            detailIconName = "flame.fill"
            detailText = energyText
            trailingEnergyText = nil
        } else {
            detailIconName = "heart.text.square.fill"
            detailText = workout.sourceName
            trailingEnergyText = nil
        }
    }
}

private struct BodyWorkoutExpenseStyleRow: View {
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue = BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    let workout: WorkoutSummary
    let titleFontSize: CGFloat
    let metadataFontSize: CGFloat
    let amountFontSize: CGFloat

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: workout.type.symbolName)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(workout.type.color)
                .frame(width: 58, height: 58)
                .background(workout.type.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(workout.type.displayName)
                    .font(.system(size: titleFontSize, weight: .bold))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(formattedCompactDateTime)
                    .font(.system(size: metadataFontSize, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 6) {
                    Image(systemName: presentation.detailIconName)
                        .font(.system(size: metadataFontSize, weight: .semibold))
                        .foregroundColor(workout.type.color)

                    Text(presentation.detailText)
                        .font(.system(size: metadataFontSize, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .layoutPriority(0)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 7) {
                Text(BodyValueFormat.durationText(for: workout.duration))
                    .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let trailingEnergyText = presentation.trailingEnergyText {
                    Text(trailingEnergyText)
                        .font(.system(size: metadataFontSize, weight: .semibold))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .layoutPriority(3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 104)
        .bodyCardBackground()
    }

    private var formattedCompactDateTime: String {
        "\(formattedCompactDate), \(formattedTime)"
    }

    private var formattedCompactDate: String {
        let day = Calendar.bodyGregorian.component(.day, from: workout.startDate)
        let month = workout.startDate.formatted(.dateTime.month(.wide))
        return "\(month) \(day)"
    }

    private var formattedTime: String {
        workout.startDate.formatted(.dateTime.hour().minute())
    }

    private var presentation: BodyWorkoutRowPresentation {
        BodyWorkoutRowPresentation(
            workout: workout,
            distanceUnitPreference: selectedDistanceUnitPreference,
            energyUnitPreference: selectedEnergyUnitPreference
        )
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

private struct BodyWorkoutDetailSheet: View {
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue = BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    let workout: WorkoutSummary

    private let sheetHeight: CGFloat = 730
    private let metricColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                compactWorkoutContent
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var compactWorkoutContent: some View {
        VStack(spacing: 18) {
            topEntryPanel
            workoutDetailsCard
            effortCard
            heartRateSection
            sourceFooter
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 22)
    }

    private var topEntryPanel: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: workout.type.symbolName)
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(workout.type.color)
                    .frame(width: 68, height: 68)
                    .background(workout.type.color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text("\(presentation.dateTitle) - \(presentation.timeRangeText)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 12) {
                Text("Duration")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                Text(presentation.durationClockText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }
            .frame(width: 152, alignment: .trailing)
        }
    }

    private var workoutDetailsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Workout Details")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 18) {
                ForEach(presentation.detailMetrics, id: \.title) { metric in
                    BodyWorkoutDetailMetricTile(
                        title: metric.title,
                        value: metric.value,
                        valueColor: metricValueColor(for: metric.title)
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .bodyCardBackground(cornerRadius: 30)
    }

    private var effortCard: some View {
        let effortPresentation = presentation.effortPresentation
        let effortColor = effortPresentation?.intensity.tintColor ?? Color.secondary

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Effort")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("+/-")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }

                if let effortPresentation {
                    HStack(spacing: 12) {
                        Text(effortPresentation.valueText)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(effortColor)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(effortColor.opacity(0.2)))

                        Text(effortPresentation.descriptor)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(effortColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    Text("No Saved Effort")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            BodyWorkoutEffortBars(
                segmentFills: effortPresentation?.segmentFills ?? [0, 0, 0, 0, 0],
                tintColor: effortColor
            )
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .bodyCardBackground(cornerRadius: 30)
    }

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            BodyWorkoutHeartRateChartCard(samples: presentation.heartRateSamples)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(workout.type.color)

            Text(presentation.sourceText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func metricValueColor(for title: String) -> Color {
        if title.hasPrefix("Active ") || title.hasPrefix("Total ") {
            return .pink
        }

        switch title {
        case "Avg Heart Rate":
            return .red
        case "Distance":
            return workout.type.color
        default:
            return .primary
        }
    }

    private var presentation: WorkoutDetailPresentation {
        WorkoutDetailPresentation(
            workout: workout,
            distanceUnitPreference: selectedDistanceUnitPreference,
            energyUnitPreference: selectedEnergyUnitPreference
        )
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

private struct BodyWorkoutDetailMetricTile: View {
    let title: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.46)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
    }
}

private struct BodyWorkoutEffortBars: View {
    let segmentFills: [Double]
    let tintColor: Color

    private let barHeights: [CGFloat] = [14, 22, 30, 38, 46]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(barHeights.indices, id: \.self) { index in
                let barHeight = barHeights[index]
                let fill = segmentFill(at: index)

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 11, height: barHeight)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tintColor)
                        .frame(width: 11, height: max(barHeight * fill, fill > 0 ? 4 : 0))
                }
                .frame(width: 11, height: barHeight, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .frame(width: 88, height: 54, alignment: .trailing)
    }

    private func segmentFill(at index: Int) -> CGFloat {
        guard segmentFills.indices.contains(index) else {
            return 0
        }

        return CGFloat(min(max(segmentFills[index], 0), 1))
    }
}

private extension WorkoutEffortIntensity {
    var tintColor: Color {
        switch self {
        case .easy:
            return Color(red: 0.10, green: 0.78, blue: 0.67)
        case .moderate:
            return Color(red: 1.0, green: 0.62, blue: 0.18)
        case .hard:
            return Color(red: 0.72, green: 0.36, blue: 1.0)
        case .allOut:
            return Color(red: 1.0, green: 0.23, blue: 0.39)
        }
    }
}

private struct BodyWorkoutHeartRateChartCard: View {
    let samples: [WorkoutHeartRateSample]

    var body: some View {
        Group {
            if samples.isEmpty {
                ZStack {
                    Color.clear

                    Text("No Heart Rate Data")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(height: 210)
            } else {
                BodyWorkoutHeartRateChart(samples: samples)
                    .frame(height: 210)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .bodyCardBackground(cornerRadius: 30)
    }
}

private struct BodyWorkoutHeartRateChart: View {
    let samples: [WorkoutHeartRateSample]

    private static let timeMarkLabelHorizontalInset: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let metrics = BodyWorkoutHeartRateChartMetrics(samples: samples)
            let plotRect = CGRect(
                x: 0,
                y: 6,
                width: max(1, geometry.size.width - 38),
                height: max(1, geometry.size.height - 34)
            )

            ZStack {
                Canvas { context, _ in
                    drawGrid(in: plotRect, context: &context)
                    drawSamples(metrics: metrics, in: plotRect, context: &context)
                }

                Text("\(metrics.maximumLabel)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .position(x: plotRect.maxX + 22, y: plotRect.minY)

                Text("\(metrics.minimumLabel)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .position(x: plotRect.maxX + 22, y: plotRect.maxY)

                ForEach(metrics.timeMarks) { mark in
                    Text(mark.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .position(
                            x: timeMarkLabelX(for: mark, in: plotRect),
                            y: plotRect.maxY + 18
                        )
                }
            }
        }
    }

    private func drawGrid(in plotRect: CGRect, context: inout GraphicsContext) {
        var horizontalGrid = Path()
        horizontalGrid.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
        horizontalGrid.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.minY))
        horizontalGrid.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        horizontalGrid.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.stroke(
            horizontalGrid,
            with: .color(Color.secondary.opacity(0.28)),
            lineWidth: 1
        )

        var verticalGrid = Path()
        for fraction in BodyWorkoutHeartRateChartMetrics.timeMarkFractions {
            let x = plotRect.minX + plotRect.width * CGFloat(fraction)
            verticalGrid.move(to: CGPoint(x: x, y: plotRect.minY))
            verticalGrid.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        }
        context.stroke(
            verticalGrid,
            with: .color(Color.secondary.opacity(0.26)),
            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
        )
    }

    private func drawSamples(
        metrics: BodyWorkoutHeartRateChartMetrics,
        in plotRect: CGRect,
        context: inout GraphicsContext
    ) {
        let tickHeight = min(max(plotRect.height * 0.12, 18), 44)
        let lineWidth = min(max(plotRect.width / 320, 2), 3)

        for sample in metrics.samples {
            let x = plotRect.minX + plotRect.width * metrics.xFraction(for: sample)
            let y = plotRect.minY + plotRect.height * metrics.yFraction(for: sample)
            let startY = max(plotRect.minY + 4, y - tickHeight / 2)
            let endY = min(plotRect.maxY - 4, y + tickHeight / 2)

            var path = Path()
            path.move(to: CGPoint(x: x, y: startY))
            path.addLine(to: CGPoint(x: x, y: endY))
            context.stroke(
                path,
                with: .color(.red),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }

    private func timeMarkLabelX(for mark: BodyWorkoutHeartRateTimeMark, in plotRect: CGRect) -> CGFloat {
        let rawX = plotRect.minX + plotRect.width * CGFloat(mark.fraction)
        let lowerBound = plotRect.minX + Self.timeMarkLabelHorizontalInset
        let upperBound = max(lowerBound, plotRect.maxX - Self.timeMarkLabelHorizontalInset)

        return min(max(rawX, lowerBound), upperBound)
    }
}

private struct BodyWorkoutHeartRateChartMetrics {
    let samples: [WorkoutHeartRateSample]
    let minimumValue: Double
    let maximumValue: Double
    let startDate: Date
    let endDate: Date

    static let timeMarkFractions = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]

    var minimumLabel: Int {
        Int(minimumValue.rounded())
    }

    var maximumLabel: Int {
        Int(maximumValue.rounded())
    }

    var timeMarks: [BodyWorkoutHeartRateTimeMark] {
        Self.timeMarkFractions.map { fraction in
            let date = startDate.addingTimeInterval(duration * fraction)
            return BodyWorkoutHeartRateTimeMark(
                fraction: fraction,
                label: date.formatted(.dateTime.hour().minute())
            )
        }
    }

    private var duration: TimeInterval {
        max(endDate.timeIntervalSince(startDate), 1)
    }

    init(samples: [WorkoutHeartRateSample]) {
        let sortedSamples = samples.sorted { $0.date < $1.date }
        self.samples = sortedSamples
        self.startDate = sortedSamples.first?.date ?? Date()
        self.endDate = sortedSamples.last?.date ?? self.startDate.addingTimeInterval(60)

        let values = sortedSamples.map(\.beatsPerMinute).filter(\.isFinite)
        let lowestValue = max(0, values.min() ?? 70)
        let highestValue = max(lowestValue + 1, values.max() ?? 165)
        let lowerBound = max(0, (floor((lowestValue - 5) / 5) * 5))
        let upperBound = ceil((highestValue + 5) / 5) * 5

        self.minimumValue = lowerBound
        self.maximumValue = max(upperBound, lowerBound + 10)
    }

    func xFraction(for sample: WorkoutHeartRateSample) -> Double {
        min(max(sample.date.timeIntervalSince(startDate) / duration, 0), 1)
    }

    func yFraction(for sample: WorkoutHeartRateSample) -> Double {
        let range = max(maximumValue - minimumValue, 1)
        return 1 - min(max((sample.beatsPerMinute - minimumValue) / range, 0), 1)
    }
}

private struct BodyWorkoutHeartRateTimeMark: Identifiable {
    let fraction: Double
    let label: String

    var id: Double {
        fraction
    }
}

private struct BodyWorkoutSortView: View {
    @Binding var selectedSortOption: BodyWorkoutListSortOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(BodyWorkoutListSortOption.allCases) { option in
                        HStack {
                            Text(option.displayName)
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.medium)

                            Spacer()

                            if selectedSortOption == option {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSortOption = option
                            dismiss()
                        }
                    }
                } header: {
                    Text("Sort by")
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BodyWorkoutFilterView: View {
    @Binding var selectedWorkoutTypes: Set<BodyWorkoutType>
    let workoutTypes: [BodyWorkoutType]
    @Environment(\.dismiss) private var dismiss
    @State private var tempSelectedWorkoutTypes: Set<BodyWorkoutType>

    init(selectedWorkoutTypes: Binding<Set<BodyWorkoutType>>, workoutTypes: [BodyWorkoutType]) {
        self._selectedWorkoutTypes = selectedWorkoutTypes
        self.workoutTypes = workoutTypes
        self._tempSelectedWorkoutTypes = State(initialValue: selectedWorkoutTypes.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section {
                        if workoutTypes.isEmpty {
                            Text("No workout types for this month")
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(workoutTypes) { workoutType in
                                HStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(workoutType.color.opacity(0.16))
                                            .frame(width: 32, height: 32)

                                        Image(systemName: workoutType.symbolName)
                                            .foregroundColor(workoutType.color)
                                            .font(.system(size: 17, weight: .semibold))
                                    }

                                    Text(workoutType.displayName)
                                        .font(.system(.title3, design: .rounded))
                                        .fontWeight(.medium)

                                    Spacer()

                                    if tempSelectedWorkoutTypes.contains(workoutType) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleWorkoutType(workoutType)
                                }
                            }
                        }
                    } header: {
                        Text("Workout Types")
                    } footer: {
                        Text("Select which workout types to display")
                    }

                    if !workoutTypes.isEmpty {
                        Section {
                            HStack(spacing: 12) {
                                Button {
                                    tempSelectedWorkoutTypes.formUnion(workoutTypes)
                                } label: {
                                    Text("Select All")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                                .tint(Color(.systemGray))

                                Button {
                                    tempSelectedWorkoutTypes.subtract(workoutTypes)
                                } label: {
                                    Text("Deselect All")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                                .tint(Color(.systemGray))
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        selectedWorkoutTypes = tempSelectedWorkoutTypes
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleWorkoutType(_ workoutType: BodyWorkoutType) {
        tempSelectedWorkoutTypes = BodyWorkoutFilterLogic.toggled(workoutType, in: tempSelectedWorkoutTypes)
    }
}

private extension View {
    func bodyWorkoutsToolbarCardBackground(colorScheme: ColorScheme) -> some View {
        background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .light ? Color(.systemBackground) : Color(.secondarySystemBackground))
                .shadow(
                    color: Color.black.opacity(colorScheme == .light ? 0.025 : 0),
                    radius: 4,
                    x: 0,
                    y: 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .light ? 0.05 : 0), lineWidth: 1)
        )
    }
}

#Preview {
    BodyWorkoutsView()
        .environmentObject(HealthKitWorkoutStore())
}
