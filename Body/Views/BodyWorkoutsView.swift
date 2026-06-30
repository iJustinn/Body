//
//  BodyWorkoutsView.swift
//  Body
//

import SwiftUI

struct BodyWorkoutsView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMonth = Calendar.bodyGregorian.component(.month, from: Date())
    @State private var selectedYear = Calendar.bodyGregorian.component(.year, from: Date())
    @State private var pendingMonthSelection: BodyMonthYear?
    @State private var searchText = ""
    @State private var showingFilterSheet = false
    @State private var selectedSortOption: BodyWorkoutListSortOption = .dateDescending
    @State private var selectedWorkoutTypes = Set(BodyWorkoutType.allCases)
    @State private var selectedWorkoutForDetails: WorkoutSummary?
    @State private var selectedWorkoutListSelection: BodyWorkoutListSelection?
    @State private var isListLoaded = false
    @State private var isPullRefreshing = false
    @Namespace private var workoutZoom

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
                BodyAppBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    BodyMonthYearPicker(
                        selectedMonth: $selectedMonth,
                        selectedYear: $selectedYear,
                        onMonthYearRequested: requestMonthYearSelection
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)

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
                                                .matchedTransitionSource(id: workout.id, in: workoutZoom) {
                                                    $0.clipShape(.rect(cornerRadius: 30, style: .continuous))
                                                }
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
                        let started = Date()
                        isPullRefreshing = true
                        await workoutStore.refreshWorkoutMonth(month: selectedMonth, year: selectedYear)
                        await workoutStore.awaitRefreshCompletion(minimumDurationFrom: started)
                        isPullRefreshing = false
                    }
                    .opacity(isListLoaded ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: isListLoaded)
                    .animation(.easeInOut(duration: 0.2), value: selectedSortOption)
                    .mask(
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 24)
                            Rectangle().fill(Color.black)
                        }
                    )
                }
                .readableContentColumn()
                // Let the list scroll under the floating tab bar so the Liquid Glass bar
                // refracts content instead of the background's plain lower region.
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .bodyPullToRefreshLoadingOverlay(isPresented: isPullRefreshing || pendingMonthSelection != nil)
            .sheet(isPresented: $showingFilterSheet) {
                BodyWorkoutFilterView(
                    selectedWorkoutTypes: $selectedWorkoutTypes,
                    workoutTypes: availableWorkoutTypes
                )
                .presentationDetents([.medium, .large])
            }
            .navigationDestination(item: $selectedWorkoutForDetails) { workout in
                BodyWorkoutDetailSheet(workout: workout)
                    .environmentObject(workoutStore)
                    .navigationTransition(.zoom(sourceID: workout.id, in: workoutZoom))
            }
            .sheet(item: $selectedWorkoutListSelection) { selection in
                BodyWorkoutListSheet(selection: selection)
                    .environmentObject(workoutStore)
                    .presentationDetents([.fraction(0.6), .large])
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

        return BodyDateFormatterCache.formatter(dateFormat: "MMMM").string(from: date)
    }

    private var searchAndControlsRow: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort by", selection: $selectedSortOption) {
                    ForEach(BodyWorkoutListSortOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                searchControlCard(iconName: "arrow.up.arrow.down", size: 18)
            }
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
            .bodyWorkoutsToolbarCardBackground()
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
        .bodyCardBackground(translucent: true)
    }

    private func searchControlCard(iconName: String, size: CGFloat) -> some View {
        Image(systemName: iconName)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(.accentColor)
            .frame(width: 46, height: 46)
            .bodyWorkoutsToolbarCardBackground()
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
        .bodyCardBackground(translucent: true)
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
        .bodyCardBackground(translucent: true)
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

struct BodyWorkoutDetailSheet: View {
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue = BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @State private var isEditingEffort = false
    @State private var editingScore = 5
    @State private var isSavingEffort = false
    @State private var effortError: String?
    @State private var route: WorkoutRoute?
    @State private var scrollOffset: CGFloat = 0
    /// Age-estimated max HR (220 − age) from Apple Health, loaded once to anchor the
    /// heart-rate zones; nil until loaded (or when no birth date), falling back to the
    /// workout's own peak HR.
    @State private var resolvedMaxHeartRate: Double?
    let workout: WorkoutSummary

    init(workout: WorkoutSummary) {
        self.workout = workout
    }

    private let metricColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    /// Height of the fixed route-map background that the content scrolls over.
    private let mapHeight: CGFloat = 510

    /// How far the floating content overlaps up onto the map's faded lower edge,
    /// so the header sits a little higher over the map rather than below it.
    private let contentTopOverlap: CGFloat = 150

    var body: some View {
        ZStack(alignment: .top) {
            if let route {
                // The map is the page background: pure black with the route map
                // pinned to the top, blending into the black. Content floats over
                // it with no backing of its own (like the home and detail pages).
                Color.black.ignoresSafeArea()

                BodyWorkoutRouteMapHero(route: route, tint: workout.type.color)
                    .frame(height: mapHeight)
                    .overlay {
                        // Dim the map as the content floats up over it.
                        Color.black
                            .opacity(mapDimOpacity)
                            .allowsHitTesting(false)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            } else {
                sheetBackdrop
            }

            ScrollView(.vertical, showsIndicators: false) {
                compactWorkoutContent
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                scrollOffset = offset
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            route = await workoutStore.loadWorkoutRoute(for: workout)
        }
    }

    /// The fixed route map sits behind the scroll content; as the content slides
    /// up over it the map dims toward black so the sheet reads as one surface
    /// lifting off the map instead of a banner scrolling away.
    private var mapDimOpacity: Double {
        guard route != nil else {
            return 0
        }
        let progress = min(max(scrollOffset / mapHeight, 0), 1)
        return progress * 0.95
    }

    @ViewBuilder
    private var sheetBackdrop: some View {
        // Pre-iOS-26 has no Liquid Glass, so the detail uses an opaque base
        // behind the workout-tinted background.
        if #unavailable(iOS 26.0) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }

        // When there is no route map, use the same workout-tint-to-black
        // backdrop as the metric detail page.
        LinearGradient(
            colors: [workout.type.color.opacity(0.45), Color.black],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.5)
        )
        .ignoresSafeArea()
    }

    private var compactWorkoutContent: some View {
        VStack(spacing: 0) {
            if route != nil {
                // Transparent gap that reveals the map background above; the
                // content below floats over it with no backing of its own.
                Color.clear.frame(height: mapHeight - contentTopOverlap)
            }

            VStack(spacing: 18) {
                topEntryPanel
                workoutDetailsCard
                effortCard
                heartRateSection
                sourceFooter
            }
            .padding(.horizontal, 20)
            .padding(.top, route == nil ? 18 : 24)
            .padding(.bottom, 22)
            .readableContentColumn()
        }
    }

    private var topEntryPanel: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: workout.type.symbolName)
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(workout.type.color)
                    .frame(width: 68, height: 68)
                    .background(workout.type.color.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    if let locality = route?.locality {
                        HStack(spacing: 5) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(workout.type.color)
                            Text(locality)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }

                    Text("\(presentation.dateTitle) - \(presentation.timeRangeText)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                // Distance-tracking workouts lead the hero with distance above duration.
                // Both hero props are set together, so unwrap as a pair.
                if let value = presentation.heroDistanceValue, let unit = presentation.heroDistanceUnit {
                    VStack(alignment: .trailing, spacing: -2) {
                        // Concatenated so the serif number and its small unit share a baseline and
                        // scale together under one minimumScaleFactor within the fixed-width column.
                        (
                            Text(value)
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.primary)
                            + Text(" \(unit)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.secondary)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)

                        Text("Distance")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .trailing, spacing: -2) {
                    Text(presentation.durationClockText)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)

                    Text("Duration")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 152, alignment: .trailing)
        }
    }

    private var workoutDetailsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Details")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 18) {
                ForEach(presentation.detailMetrics, id: \.kind) { metric in
                    BodyWorkoutDetailMetricTile(
                        title: metric.title,
                        value: metric.value
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .bodyCardBackground(cornerRadius: 30, translucent: true)
    }

    /// The effort to display — a rating the user just saved this session (kept on
    /// the store) wins over the snapshot's baked-in value so an edit shows at once.
    private var effortLevel: Double? {
        workoutStore.workoutEffortOverrides[workout.id] ?? workout.effortLevel
    }

    /// While editing, the in-progress value drives the header so the meter and
    /// number update live; otherwise the saved value (override-aware) is shown.
    private var displayedEffortLevel: Double? {
        isEditingEffort ? Double(editingScore) : effortLevel
    }

    /// Tapping the card expands it in place to reveal the editing controls — no
    /// separate sheet. Cancel/Save sit on the left, the −/+ steppers on the right.
    private var effortCard: some View {
        let presentation = displayedEffortLevel.flatMap { WorkoutEffortPresentation(score: $0) }
        let effortColor = presentation?.intensity.tintColor ?? Color.secondary

        return VStack(alignment: .leading, spacing: 18) {
            effortHeader(presentation: presentation, color: effortColor)

            if isEditingEffort {
                effortEditingControls(color: effortColor)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .bodyCardBackground(cornerRadius: 30, translucent: true)
        .alert("Couldn't Save", isPresented: effortErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(effortError ?? "")
        }
    }

    private func effortHeader(presentation: WorkoutEffortPresentation?, color: Color) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Effort")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("+/-")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }

                if let presentation {
                    HStack(spacing: 12) {
                        Text(presentation.valueText)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(color)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(color.opacity(0.2)))

                        Text(presentation.descriptor)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(color)
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

            BodyWorkoutEffortChart(
                score: presentation?.normalizedScore,
                tintColor: color,
                showsLevelDots: isEditingEffort
            )
            .accessibilityHidden(true)
            .animation(.snappy(duration: 0.3), value: displayedEffortLevel)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditingEffort {
                cancelEditingEffort()
            } else {
                beginEditingEffort()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isEditingEffort ? "Stop editing" : "Edit effort")
    }

    private func effortEditingControls(color: Color) -> some View {
        HStack(spacing: 10) {
            Button {
                cancelEditingEffort()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .frame(minWidth: 84)
                    .bodyTrendRangeTabBackgroundOnGradient(isSelected: false)
            }
            .buttonStyle(.plain)
            .disabled(isSavingEffort)

            Button {
                saveEditingEffort()
            } label: {
                Group {
                    if isSavingEffort {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Text("Save")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 42)
                .frame(minWidth: 80)
                .bodyTrendRangeTabBackgroundOnGradient(isSelected: true)
            }
            .buttonStyle(.plain)
            .disabled(isSavingEffort)

            Spacer(minLength: 10)

            effortStepButton(systemName: "minus", color: color, isEnabled: editingScore > 1 && !isSavingEffort) {
                withAnimation(.snappy(duration: 0.28)) { editingScore = max(editingScore - 1, 1) }
            }
            effortStepButton(systemName: "plus", color: color, isEnabled: editingScore < 10 && !isSavingEffort) {
                withAnimation(.snappy(duration: 0.28)) { editingScore = min(editingScore + 1, 10) }
            }
        }
    }

    private func effortStepButton(systemName: String, color: Color, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(isEnabled ? color : Color.secondary.opacity(0.4))
                .frame(width: 50, height: 42)
                .bodyTrendRangeTabBackgroundOnGradient(isSelected: false)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemName == "plus" ? "Increase effort" : "Decrease effort")
    }

    private var effortErrorBinding: Binding<Bool> {
        Binding(
            get: { effortError != nil },
            set: { if !$0 { effortError = nil } }
        )
    }

    private func beginEditingEffort() {
        editingScore = effortLevel.map { min(max(Int($0.rounded()), 1), 10) } ?? 5
        withAnimation(.snappy(duration: 0.3)) { isEditingEffort = true }
    }

    private func cancelEditingEffort() {
        withAnimation(.snappy(duration: 0.3)) { isEditingEffort = false }
    }

    private func saveEditingEffort() {
        isSavingEffort = true
        let value = Double(editingScore)
        Task {
            do {
                try await workoutStore.saveWorkoutEffort(workoutID: workout.id, score: value)
                isSavingEffort = false
                withAnimation(.snappy(duration: 0.3)) { isEditingEffort = false }
            } catch {
                isSavingEffort = false
                effortError = "Body couldn't save the effort rating to Apple Health. Make sure Body is allowed to update Workouts in Settings › Health › Data Access & Devices."
            }
        }
    }

    private var heartRateSection: some View {
        BodyWorkoutHeartRateChartCard(
            samples: presentation.heartRateSamples,
            maxHeartRate: resolvedMaxHeartRate ?? workout.maximumHeartRateBeatsPerMinute
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        // Re-key on the permission selection so toggling Date of Birth re-resolves the
        // anchor: when it goes out of scope `userMaxHeartRate()` returns nil and the chart
        // falls back to the session-peak HR (no `== nil` guard — `.task(id:)` dedupes).
        .task(id: workoutStore.permissionSelection.rawValue) {
            resolvedMaxHeartRate = await workoutStore.userMaxHeartRate()
        }
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

    /// Splits a formatted value ("172 BPM") into number and trailing unit so the
    /// unit can read smaller and gray like the hero distance. Values that don't
    /// start with a digit (e.g. "No Data", "—") stay whole.
    private var valueParts: (number: String, unit: String) {
        guard let first = value.first, first.isNumber,
              let spaceIndex = value.firstIndex(of: " ") else {
            return (value, "")
        }
        return (String(value[..<spaceIndex]), String(value[value.index(after: spaceIndex)...]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueParts.number)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !valueParts.unit.isEmpty {
                    Text(valueParts.unit)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
    }
}

private struct EffortWedge: Shape {
    /// Top-edge heights at the left and right edges, as a fraction (0...1) of the
    /// frame height; the sloped top joins adjacent wedges into one rising triangle.
    var leftHeight: CGFloat
    var rightHeight: CGFloat
    var cornerRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let topLeft = CGPoint(x: 0, y: height * (1 - leftHeight))
        let topRight = CGPoint(x: width, y: height * (1 - rightHeight))
        let bottomRight = CGPoint(x: width, y: height)
        let bottomLeft = CGPoint(x: 0, y: height)
        let radius = min(cornerRadius, width / 2, height * min(leftHeight, rightHeight) / 2)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: (topLeft.y + bottomLeft.y) / 2))
        path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: radius)
        path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: radius)
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: radius)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// The effort meter: four wedge segments whose shared sloped top reads as one triangle.
/// Segment widths track each band's level count (Easy/Moderate = 3, Hard/All Out = 2),
/// and the tint fills left-to-right to the exact 1–10 score, so a partly-filled segment
/// shows the precise level. While editing it overlays the level dots (current one lit).
private struct BodyWorkoutEffortChart: View {
    /// Exact effort 1...10 (nil = no saved effort → an empty triangle).
    let score: Double?
    let tintColor: Color
    /// While editing, overlays the 1–10 level dots with the current level lit.
    var showsLevelDots: Bool = false

    private let bandLevelCounts: [Int] = [3, 3, 2, 2]
    private let maxHeight: CGFloat = 66
    private let unitWidth: CGFloat = 11
    private let gap: CGFloat = 4

    private var totalLevels: Int { bandLevelCounts.reduce(0, +) }
    private var currentLevel: Int { min(max(Int((score ?? 0).rounded()), 1), 10) }

    var body: some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(bandLevelCounts.indices, id: \.self) { band in
                segment(band: band)
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
    }

    private func segment(band: Int) -> some View {
        let lo = bandStart(band)
        let hi = lo + bandLevelCounts[band]
        let width = CGFloat(bandLevelCounts[band]) * unitWidth
        let wedge = EffortWedge(
            leftHeight: heightFraction(at: lo),
            rightHeight: heightFraction(at: hi)
        )

        return ZStack(alignment: .bottomLeading) {
            wedge.fill(Color.secondary.opacity(0.18))

            wedge.fill(tintColor)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: width * fillFraction(from: lo, to: hi))
                }

            if showsLevelDots {
                levelDots(band: band)
            }
        }
        .frame(width: width, height: maxHeight, alignment: .bottom)
    }

    private func levelDots(band: Int) -> some View {
        let lo = bandStart(band)
        return HStack(spacing: 5) {
            ForEach(0..<bandLevelCounts[band], id: \.self) { offset in
                let level = lo + offset + 1
                Circle()
                    .fill(level == currentLevel ? Color.white : Color.white.opacity(0.5))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    /// Units (0-based) before `band`: 0, 3, 6, 8.
    private func bandStart(_ band: Int) -> Int {
        bandLevelCounts.prefix(band).reduce(0, +)
    }

    /// Top height (fraction of `maxHeight`) at a unit position 0...totalLevels — a
    /// straight line from a low left edge to full height, i.e. the triangle's slope.
    private func heightFraction(at unit: Int) -> CGFloat {
        let base: CGFloat = 0.1
        return base + (1 - base) * CGFloat(unit) / CGFloat(totalLevels)
    }

    /// Filled fraction (0...1) of a segment spanning [lo, hi) units for `score`.
    private func fillFraction(from lo: Int, to hi: Int) -> CGFloat {
        guard let score else { return 0 }
        let filled = min(max(score - Double(lo), 0), Double(hi - lo))
        return CGFloat(filled / Double(hi - lo))
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

/// The heart-rate zone breakdown under the HR chart: one row per zone (5 → 0) with a
/// proportional colored bar, percentage, time-in-zone, and bpm range.
private struct BodyWorkoutHeartRateZoneChart: View {
    let zones: [WorkoutHeartRateZone]

    private let pctWidth: CGFloat = 46
    private let bpmWidth: CGFloat = 84
    private let barHeight: CGFloat = 16

    var body: some View {
        VStack(spacing: 11) {
            headerRow
            ForEach(zones) { zone in
                row(for: zone)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Zone")
                .fixedSize()
            Spacer(minLength: 8)
            Text("Pct.")
                .frame(width: pctWidth, alignment: .trailing)
            Text("bpm")
                .frame(width: bpmWidth, alignment: .trailing)
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .foregroundColor(.secondary)
    }

    private func row(for zone: WorkoutHeartRateZone) -> some View {
        HStack(spacing: 10) {
            Text("\(zone.zone)")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .frame(width: 24, alignment: .leading)

            bar(for: zone)

            Text("\(Int((zone.fraction * 100).rounded()))%")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: pctWidth, alignment: .trailing)

            Text(zone.bpmRangeText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(.secondary)
                .frame(width: bpmWidth, alignment: .trailing)
        }
    }

    private func bar(for zone: WorkoutHeartRateZone) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                Capsule(style: .continuous)
                    .fill(color(for: zone.zone))
                    // Floor the width at the bar height so a tiny share reads as a
                    // circle (a Capsule with equal width/height) rather than a stub.
                    .frame(width: max(geometry.size.width * zone.fraction, zone.fraction > 0 ? barHeight : 0))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
    }

    private func color(for zone: Int) -> Color {
        switch zone {
        case 0:
            return Color(red: 0.36, green: 0.86, blue: 0.69)
        case 1:
            return Color(red: 0.30, green: 0.55, blue: 0.98)
        case 2:
            return Color(red: 1.0, green: 0.83, blue: 0.30)
        case 3:
            return Color(red: 1.0, green: 0.62, blue: 0.18)
        case 4:
            return Color(red: 1.0, green: 0.45, blue: 0.20)
        default:
            return Color(red: 1.0, green: 0.27, blue: 0.31)
        }
    }
}

private struct BodyWorkoutHeartRateChartCard: View {
    let samples: [WorkoutHeartRateSample]
    /// Anchors the zone bands (% of this value); nil hides the zone breakdown.
    var maxHeartRate: Double?

    var body: some View {
        let cachedMetrics: BodyWorkoutHeartRateChartMetrics? = samples.isEmpty
            ? nil
            : BodyWorkoutHeartRateChartMetrics(samples: samples)
        let zones = maxHeartRate.flatMap {
            WorkoutHeartRateZones.zones(samples: samples, maxHeartRate: $0)
        }

        return VStack(alignment: .leading, spacing: 14) {
            header(metrics: cachedMetrics)
            chartView(metrics: cachedMetrics)
            if let zones {
                BodyWorkoutHeartRateZoneChart(zones: zones)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .bodyCardBackground(cornerRadius: 30, translucent: true)
    }

    private func header(metrics: BodyWorkoutHeartRateChartMetrics?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Heart Rate")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Spacer(minLength: 0)

            if let metrics {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(metrics.dataMinimumLabel)-\(metrics.dataMaximumLabel)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("BPM")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(BodyWorkoutHeartRateChart.referenceLineColor)
            }
        }
    }

    @ViewBuilder
    private func chartView(metrics: BodyWorkoutHeartRateChartMetrics?) -> some View {
        if let metrics {
            BodyWorkoutHeartRateChart(metrics: metrics)
                .frame(height: 210)
        } else {
            ZStack {
                Color.clear

                Text("No Heart Rate Data")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(height: 210)
        }
    }
}

private struct BodyWorkoutHeartRateChart: View {
    let metrics: BodyWorkoutHeartRateChartMetrics

    private static let timeMarkLabelHorizontalInset: CGFloat = 24
    private static let yAxisLabelInset: CGFloat = 44
    private static let xAxisLabelOffset: CGFloat = 18

    static let referenceLineColor = Color(red: 0.20, green: 0.62, blue: 1.0)

    var body: some View {
        GeometryReader { geometry in
            let plotRect = CGRect(
                x: 0,
                y: 6,
                width: max(1, geometry.size.width - Self.yAxisLabelInset),
                height: max(1, geometry.size.height - 34)
            )

            ZStack {
                Canvas { context, _ in
                    drawGrid(in: plotRect, context: &context)
                    drawReferenceLine(in: plotRect, context: &context)
                    drawScatterDots(in: plotRect, context: &context)
                    drawSmoothedLine(in: plotRect, context: &context)
                }

                yAxisLabels(in: plotRect)

                ForEach(metrics.timeMarks) { mark in
                    Text(mark.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .position(
                            x: timeMarkLabelX(for: mark, in: plotRect),
                            y: plotRect.maxY + Self.xAxisLabelOffset
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

        var tickGrid = Path()
        for tickValue in metrics.primaryTickValues {
            let y = plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: Double(tickValue)))
            tickGrid.move(to: CGPoint(x: plotRect.minX, y: y))
            tickGrid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        context.stroke(
            tickGrid,
            with: .color(Color.secondary.opacity(0.18)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
        )
    }

    private func drawReferenceLine(in plotRect: CGRect, context: inout GraphicsContext) {
        let y = plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: metrics.averageValue))
        var line = Path()
        line.move(to: CGPoint(x: plotRect.minX, y: y))
        line.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        context.stroke(
            line,
            with: .color(Self.referenceLineColor.opacity(0.85)),
            lineWidth: 1
        )
    }

    private func drawScatterDots(in plotRect: CGRect, context: inout GraphicsContext) {
        let dotRadius: CGFloat = 1.8
        for sample in metrics.samples {
            let x = plotRect.minX + plotRect.width * CGFloat(metrics.xFraction(for: sample))
            let yFraction = metrics.yFraction(for: sample)
            let y = plotRect.minY + plotRect.height * CGFloat(yFraction)
            let color = BodyWorkoutHeartRateChartMetrics.color(forFraction: 1 - yFraction)
            let circleRect = CGRect(
                x: x - dotRadius,
                y: y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(
                Path(ellipseIn: circleRect),
                with: .color(color.opacity(0.38))
            )
        }
    }

    private func drawSmoothedLine(in plotRect: CGRect, context: inout GraphicsContext) {
        let series = metrics.smoothedSeries
        guard series.count >= 2 else {
            return
        }

        let points = series.map { point in
            CGPoint(
                x: plotRect.minX + plotRect.width * CGFloat(metrics.xFraction(forDate: point.date)),
                y: plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: point.value))
            )
        }
        let path = Self.smoothedPath(through: points)

        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: BodyWorkoutHeartRateChartMetrics.gradientStops),
            startPoint: CGPoint(x: plotRect.midX, y: plotRect.maxY),
            endPoint: CGPoint(x: plotRect.midX, y: plotRect.minY)
        )

        context.stroke(
            path,
            with: shading,
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    private static func smoothedPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else {
            return path
        }
        path.move(to: first)

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i < points.count - 2 ? points[i + 2] : points[i + 1]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }

    @ViewBuilder
    private func yAxisLabels(in plotRect: CGRect) -> some View {
        ForEach(metrics.primaryTickValues, id: \.self) { tickValue in
            Text("\(tickValue)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .position(
                    x: plotRect.maxX + 22,
                    y: plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: Double(tickValue)))
                )
        }

        Text("\(metrics.averageLabel)")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(Self.referenceLineColor)
            .position(
                x: plotRect.maxX + 22,
                y: plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: metrics.averageValue))
            )
    }

    private func timeMarkLabelX(for mark: BodyWorkoutHeartRateTimeMark, in plotRect: CGRect) -> CGFloat {
        let rawX = plotRect.minX + plotRect.width * CGFloat(mark.fraction)
        let lowerBound = plotRect.minX + Self.timeMarkLabelHorizontalInset
        let upperBound = max(lowerBound, plotRect.maxX - Self.timeMarkLabelHorizontalInset)

        return min(max(rawX, lowerBound), upperBound)
    }
}

private struct BodyWorkoutHeartRateChartMetrics {
    struct SmoothedPoint {
        let date: Date
        let value: Double
    }

    let samples: [WorkoutHeartRateSample]
    let minimumValue: Double
    let maximumValue: Double
    let dataMinimumValue: Double
    let dataMaximumValue: Double
    let averageValue: Double
    let startDate: Date
    let endDate: Date

    static let timeMarkFractions = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]

    var dataMinimumLabel: Int {
        Int(dataMinimumValue.rounded())
    }

    var dataMaximumLabel: Int {
        Int(dataMaximumValue.rounded())
    }

    var averageLabel: Int {
        Int(averageValue.rounded())
    }

    var primaryTickValues: [Int] {
        let avg = Int(averageValue.rounded())
        let dataMax = dataMaximumValue
        let topTick = max(Int((dataMax / 10).rounded(.toNearestOrEven)) * 10, avg + 10)
        let mid = (Double(avg) + Double(topTick)) / 2
        let midTick = Int((mid / 10).rounded(.toNearestOrEven)) * 10

        var ticks: [Int] = []
        if topTick - avg >= 12 {
            ticks.append(topTick)
        }
        if midTick - avg >= 10, topTick - midTick >= 10 {
            ticks.append(midTick)
        }
        return ticks.sorted().reversed()
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

        self.dataMinimumValue = lowestValue
        self.dataMaximumValue = highestValue
        self.minimumValue = lowerBound
        self.maximumValue = max(upperBound, lowerBound + 10)
        self.averageValue = values.isEmpty
            ? (lowerBound + upperBound) / 2
            : values.reduce(0, +) / Double(values.count)
    }

    func xFraction(for sample: WorkoutHeartRateSample) -> Double {
        xFraction(forDate: sample.date)
    }

    func xFraction(forDate date: Date) -> Double {
        min(max(date.timeIntervalSince(startDate) / duration, 0), 1)
    }

    func yFraction(for sample: WorkoutHeartRateSample) -> Double {
        yFraction(forValue: sample.beatsPerMinute)
    }

    func yFraction(forValue value: Double) -> Double {
        let range = max(maximumValue - minimumValue, 1)
        return 1 - min(max((value - minimumValue) / range, 0), 1)
    }

    var smoothedSeries: [SmoothedPoint] {
        guard !samples.isEmpty else {
            return []
        }

        let bucketTarget = 60
        if samples.count <= bucketTarget {
            return samples.map { SmoothedPoint(date: $0.date, value: $0.beatsPerMinute) }
        }

        let bucketDuration = duration / Double(bucketTarget)
        guard bucketDuration > 0 else {
            return samples.map { SmoothedPoint(date: $0.date, value: $0.beatsPerMinute) }
        }

        var sums = [Double](repeating: 0, count: bucketTarget)
        var counts = [Int](repeating: 0, count: bucketTarget)

        for sample in samples {
            let offset = sample.date.timeIntervalSince(startDate)
            let idx = min(bucketTarget - 1, max(0, Int(offset / bucketDuration)))
            sums[idx] += sample.beatsPerMinute
            counts[idx] += 1
        }

        var points: [SmoothedPoint] = []
        points.reserveCapacity(bucketTarget)
        for i in 0..<bucketTarget where counts[i] > 0 {
            let midTime = bucketDuration * (Double(i) + 0.5)
            points.append(SmoothedPoint(
                date: startDate.addingTimeInterval(midTime),
                value: sums[i] / Double(counts[i])
            ))
        }
        return points
    }

    private struct ColorStop {
        let location: Double
        let red: Double
        let green: Double
        let blue: Double
    }

    private static let colorStops: [ColorStop] = [
        ColorStop(location: 0.0,  red: 0.20, green: 0.92, blue: 0.82),
        ColorStop(location: 0.30, red: 0.25, green: 0.62, blue: 1.0),
        ColorStop(location: 0.55, red: 0.98, green: 0.86, blue: 0.30),
        ColorStop(location: 0.78, red: 1.0,  green: 0.55, blue: 0.20),
        ColorStop(location: 1.0,  red: 1.0,  green: 0.30, blue: 0.30)
    ]

    static let gradientStops: [Gradient.Stop] = colorStops.map { stop in
        Gradient.Stop(
            color: Color(red: stop.red, green: stop.green, blue: stop.blue),
            location: stop.location
        )
    }

    static func color(forFraction fraction: Double) -> Color {
        let f = max(0, min(1, fraction))
        guard let last = colorStops.last else {
            return Color(red: 1.0, green: 0.30, blue: 0.30)
        }
        for i in 1..<colorStops.count {
            if f <= colorStops[i].location {
                let prev = colorStops[i - 1]
                let curr = colorStops[i]
                let span = curr.location - prev.location
                let t = span > 0 ? (f - prev.location) / span : 0
                return Color(
                    red: prev.red + (curr.red - prev.red) * t,
                    green: prev.green + (curr.green - prev.green) * t,
                    blue: prev.blue + (curr.blue - prev.blue) * t
                )
            }
        }
        return Color(red: last.red, green: last.green, blue: last.blue)
    }
}

private struct BodyWorkoutHeartRateTimeMark: Identifiable {
    let fraction: Double
    let label: String

    var id: Double {
        fraction
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
                                .listRowBackground(Color.clear)
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
                .scrollContentBackground(.hidden)
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
    func bodyWorkoutsToolbarCardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

#Preview {
    BodyWorkoutsView()
        .environmentObject(HealthKitWorkoutStore())
}
