//
//  BodyWorkoutsView.swift
//  Body
//

import SwiftUI
import UIKit

struct BodyWorkoutsView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedMonth = Calendar.bodyGregorian.component(.month, from: Date())
    @State private var selectedYear = Calendar.bodyGregorian.component(.year, from: Date())
    @State private var observedCurrentMonthYear = BodyMonthYear.current()
    @State private var pendingMonthSelection: PendingMonthSelection?
    @State private var monthLoadTasks: [String: Task<Bool, Never>] = [:]
    @State private var searchText = ""
    @State private var showingFilterSheet = false
    @State private var showingMonthPicker = false
    @State private var selectedSortOption: BodyWorkoutListSortOption = .dateDescending
    @State private var selectedWorkoutTypes = Set(BodyWorkoutType.allCases)
    @State private var selectedWorkoutForDetails: WorkoutSummary?
    @State private var selectedWorkoutListSelection: BodyWorkoutListSelection?
    @State private var isListLoaded = false
    @State private var searchCorpusCache = BodyWorkoutSearchCorpusCache()
    @AppStorage(BodyAppearancePreference.workoutsChartShowsTypeBreakdownKey) private var workoutsChartShowsTypeBreakdown = false
    @Namespace private var workoutZoom

    private var monthSwitchTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
    }

    private var monthIdentity: String {
        "\(selectedYear)-\(selectedMonth)"
    }

    /// A card entering or leaving the list fades; the cards around it glide to
    /// their new places.
    private var workoutRowTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.28))
    }

    private var workoutRowChangeAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.32, extraBounce: 0)
    }

    /// The two charts cross-fade into each other. Applied to both branches, so
    /// the outgoing card fades out while the incoming one fades in rather than
    /// one replacing the other.
    private var chartSwitchTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.2))
    }

    /// Carried by `withAnimation` at the toggle rather than `.animation(value:)`
    /// on the slot: the cards are different heights, and the workout list that
    /// has to move is the slot's *sibling*, outside any animation scope a
    /// modifier on the slot itself could establish.
    private var chartSwitchAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private func switchChart() {
        withAnimation(chartSwitchAnimation) {
            workoutsChartShowsTypeBreakdown.toggle()
        }
    }

    var body: some View {
        let baseSnapshot = selectedSnapshot
        let allWorkouts = baseSnapshot.days.flatMap(\.workouts)
        let matchingWorkouts = self.matchingWorkouts(from: allWorkouts, in: baseSnapshot)
        let visibleWorkouts = sorted(workouts: matchingWorkouts)
        let displaySnapshot = self.displaySnapshot(from: baseSnapshot, matching: matchingWorkouts)
        // Membership, not the snapshot: a refresh republishes the month with a
        // fresh `generatedAt` every time (see `HealthKitWorkoutStore.refresh`),
        // so keying on the snapshot would twitch the list on every sync. Set
        // rather than array, so a pure re-sort leaves this key untouched and the
        // `selectedSortOption` animation below stays in charge of re-order moves.
        let visibleWorkoutIDs = Set(visibleWorkouts.map(\.id))

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
                            // One slot, one chart. The month `.id` still gives
                            // the block a fresh identity per month, so a month
                            // switch cross-fades the whole card exactly as it
                            // did when these were two separate cards.
                            Group {
                                if workoutsChartShowsTypeBreakdown {
                                    workoutTypeSummaryCard(snapshot: displaySnapshot, workouts: matchingWorkouts)
                                        .transition(chartSwitchTransition)
                                } else {
                                    workoutCalendarCard(snapshot: displaySnapshot)
                                        .transition(chartSwitchTransition)
                                }
                            }
                            .id("chart-\(monthIdentity)")
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
                                                    titleFontSize: 20,
                                                    metadataFontSize: 13,
                                                    amountFontSize: 25,
                                                    customName: workoutStore.workoutCustomNames[workout.id]
                                                )
                                                .matchedTransitionSource(id: workout.id, in: workoutZoom) {
                                                    $0.clipShape(.rect(cornerRadius: 30, style: .continuous))
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityHint("Shows workout details")
                                            // Outside the button label, so the
                                            // zoom source inside it keeps its
                                            // geometry while a fade is in flight.
                                            .transition(workoutRowTransition)
                                        }
                                    }
                                }
                            }
                            // On the Group, not the LazyVStack: the stack only
                            // exists in the non-empty branch, so a modifier there
                            // would be built fresh — with no previous value to
                            // compare — exactly when it matters most, an empty
                            // month receiving its first workout. Inside the `.id`
                            // below, so a month switch rebuilds this silently and
                            // leaves the cross-fade to `monthSwitchTransition`.
                            .animation(workoutRowChangeAnimation, value: visibleWorkoutIDs)
                            .id("list-\(monthIdentity)")
                            .transition(monthSwitchTransition)
                        }
                        .padding(.horizontal)
                        .padding(.top, 32)
                        .padding(.bottom, 110)
                    }
                    .bodyPullToRefresh(isRefreshing: workoutStore.isRefreshing) {
                        Task { await workoutStore.refreshWorkoutMonth(month: selectedMonth, year: selectedYear) }
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
            .overlay(alignment: .top) {
                if pendingMonthSelection != nil {
                    BodySyncStatusBadgeLabel(icon: .spinner, text: "Loading data...")
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: pendingMonthSelection == nil)
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
                advanceToNewMonthIfNeeded()
                animateListInIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                advanceToNewMonthIfNeeded()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    advanceToNewMonthIfNeeded()
                }
            }
        }
    }

    /// Follows the calendar into a new month while the app stays alive: if the
    /// user was viewing the (old) current month, the selection moves to the new
    /// month — shown immediately as an empty snapshot; the regular foreground
    /// sync fetches and persists its real data.
    private func advanceToNewMonthIfNeeded(now: Date = Date()) {
        guard let advance = BodyWorkoutMonthRollover.advance(
            now: now,
            observedCurrent: observedCurrentMonthYear,
            selection: BodyMonthYear(month: selectedMonth, year: selectedYear)
        ) else {
            return
        }

        observedCurrentMonthYear = advance.newCurrent
        if advance.shouldMoveSelection {
            applyMonthSelection(advance.newCurrent)
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

    private var normalizedSearchText: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func matchingWorkouts(from allWorkouts: [WorkoutSummary], in baseSnapshot: WorkoutMonthSnapshot) -> [WorkoutSummary] {
        let normalizedSearchText = self.normalizedSearchText

        guard !normalizedSearchText.isEmpty else {
            return allWorkouts.filter { workout in
                selectedWorkoutTypes.contains(workout.type)
            }
        }

        // The corpus cache must always see the unfiltered snapshot and full
        // workout list — its key includes `generatedAt`, so a filtered array
        // under the same key would persist a partial corpus.
        let corpus = searchCorpusCache.entries(
            for: baseSnapshot,
            workouts: allWorkouts,
            dateSearchText: dateSearchText(for:)
        )

        return allWorkouts.filter { workout in
            guard selectedWorkoutTypes.contains(workout.type) else {
                return false
            }

            // The custom name is matched outside the corpus: renames don't change the
            // snapshot identity the cache is keyed on, so baking it in would serve a
            // stale name. The type name stays a searchable alias either way.
            guard let corpusEntry = corpus[workout.id] else {
                return workout.type.displayName.lowercased().contains(normalizedSearchText)
                    || workout.sourceName.lowercased().contains(normalizedSearchText)
                    || dateSearchText(for: workout.startDate).contains(normalizedSearchText)
                    || (workoutStore.workoutCustomNames[workout.id]?.lowercased().contains(normalizedSearchText) ?? false)
            }

            return corpusEntry.typeText.contains(normalizedSearchText)
                || corpusEntry.sourceText.contains(normalizedSearchText)
                || corpusEntry.dateText.contains(normalizedSearchText)
                || (workoutStore.workoutCustomNames[workout.id]?.lowercased().contains(normalizedSearchText) ?? false)
        }
    }

    private func displaySnapshot(from baseSnapshot: WorkoutMonthSnapshot, matching: [WorkoutSummary]) -> WorkoutMonthSnapshot {
        guard hasActiveFilters || !normalizedSearchText.isEmpty else {
            return baseSnapshot
        }

        return BodyWorkoutFilterLogic.displaySnapshot(
            from: baseSnapshot,
            matchingIDs: Set(matching.map(\.id))
        )
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

        return BodyDateFormatterCache.formatter(template: "MMMM").string(from: date)
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
                searchControlCard(iconName: "line.3.horizontal.decrease", size: 19)
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

            Button {
                showingMonthPicker = true
            } label: {
                searchControlCard(iconName: "calendar", size: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Jump to month")
            .popover(isPresented: $showingMonthPicker) {
                BodyWorkoutMonthPicker(
                    selectedMonth: selectedMonth,
                    selectedYear: selectedYear,
                    onSelect: { monthYear in
                        _ = requestMonthYearSelection(monthYear)
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        }
        .frame(height: 46)
    }

    private func workoutCalendarCard(snapshot: WorkoutMonthSnapshot) -> some View {
        WorkoutCalendarView(
            snapshot: snapshot,
            style: .widgetLarge,
            fillsAvailableHeight: false,
            onSelectDay: { day in
                selectedWorkoutListSelection = .day(day)
            },
            onSwitchChart: switchChart
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

    private func workoutTypeSummaryCard(snapshot: WorkoutMonthSnapshot, workouts: [WorkoutSummary]) -> some View {
        VStack(spacing: 18) {
            monthlySummaryHeader(workouts: workouts)

            Divider()
                .overlay(Color.secondary.opacity(0.18))

            WorkoutTypeBreakdownView(
                snapshot: snapshot,
                style: .app,
                onSelectType: { type in
                    selectedWorkoutListSelection = .type(
                        type,
                        workouts: workoutsForType(type, in: workouts)
                    )
                },
                onSwitchChart: switchChart
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

    private func workoutsForType(_ type: BodyWorkoutType, in workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        workouts
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
                // The year interpolates as a String: an Int picks up the locale's
                // digit grouping and renders "August 2,026".
                Text("No workouts for \(localizedMonthTitle) \(String(selectedYear))")
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

        // First-wins latch: a fresh token identifies this request so a stale
        // completion (e.g. a load that finishes after the 15s timeout already
        // cleared the overlay, or after a different month was tapped) can't
        // navigate. Whichever of the load task or the 15s sleeper resolves the
        // token first wins; the other no-ops.
        let token = UUID()
        pendingMonthSelection = PendingMonthSelection(request: token, monthYear: monthYear)

        // Reuse a single in-flight load per month so repeated taps of a hung
        // month await the same task instead of stacking new calls onto the
        // store's non-cancellation-aware continuations.
        let loadTask = monthLoadTask(for: monthYear)
        Task {
            let didLoad = await loadTask.value
            finishPendingMonthSelection(token: token, didLoad: didLoad)
        }
        Task {
            try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            finishPendingMonthSelection(token: token, didLoad: nil)
        }

        return false
    }

    /// Returns the in-flight load task for `monthYear`, creating (and retaining)
    /// one if none exists so concurrent/repeat requests share a single load.
    private func monthLoadTask(for monthYear: BodyMonthYear) -> Task<Bool, Never> {
        let key = monthYear.id
        if let existing = monthLoadTasks[key] {
            return existing
        }

        let task = Task { @MainActor in
            let didLoad = await workoutStore.loadMonthIfNeeded(month: monthYear.month, year: monthYear.year)
            monthLoadTasks.removeValue(forKey: key)
            return didLoad
        }
        monthLoadTasks[key] = task
        return task
    }

    /// Resolves the pending month request identified by `token`. Applies the
    /// selection only when the token still matches and the load succeeded; a
    /// timeout (`didLoad == nil`) or failed load just clears the overlay.
    /// Always clears pending state on a token match so a late load completion
    /// never auto-navigates — the next tap hits `hasLoadedSnapshot` instantly.
    @MainActor
    private func finishPendingMonthSelection(token: UUID, didLoad: Bool?) {
        guard let pending = pendingMonthSelection, pending.request == token else {
            return
        }

        if didLoad == true {
            applyMonthSelection(pending.monthYear)
        }

        pendingMonthSelection = nil
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

/// Identifies an in-flight month-selection request. The `request` token lets a
/// completion apply only to the exact request that started it, so a stale load
/// (finishing after a timeout or a different month tap) cannot navigate.
private struct PendingMonthSelection: Equatable {
    let request: UUID
    let monthYear: BodyMonthYear
}

/// Caches the lowercased search fields (`type`, `source`, formatted `date`) for
/// each workout in the currently selected month, avoiding recomputation on
/// every keystroke. Invalidated whenever the snapshot identity, locale, or
/// time zone changes, since `dateSearchText` is locale/time-zone derived.
private final class BodyWorkoutSearchCorpusCache {
    private struct Key: Equatable {
        let month: Int
        let year: Int
        let generatedAt: Date
        let localeIdentifier: String
        let timeZoneIdentifier: String
    }

    private var key: Key?
    private var storedEntries: [WorkoutSummary.ID: (typeText: String, sourceText: String, dateText: String)] = [:]

    func entries(
        for snapshot: WorkoutMonthSnapshot,
        workouts: [WorkoutSummary],
        dateSearchText: (Date) -> String
    ) -> [WorkoutSummary.ID: (typeText: String, sourceText: String, dateText: String)] {
        let currentKey = Key(
            month: snapshot.month,
            year: snapshot.year,
            generatedAt: snapshot.generatedAt,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier
        )

        guard key == currentKey else {
            key = currentKey
            storedEntries = Dictionary(
                workouts.map { workout in
                    (
                        workout.id,
                        (
                            typeText: workout.type.displayName.lowercased(),
                            sourceText: workout.sourceName.lowercased(),
                            dateText: dateSearchText(workout.startDate)
                        )
                    )
                },
                uniquingKeysWith: { _, latest in latest }
            )
            return storedEntries
        }

        return storedEntries
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

    /// Rebuilds a snapshot with each day's workouts narrowed to `matchingIDs`,
    /// keeping the original day buckets and `generatedAt` so no workout can
    /// move days (the persisted snapshot doesn't record the calendar/time zone
    /// that formed it, so re-bucketing from `startDate` is not safe).
    static func displaySnapshot(from snapshot: WorkoutMonthSnapshot, matchingIDs: Set<WorkoutSummary.ID>) -> WorkoutMonthSnapshot {
        WorkoutMonthSnapshot(
            month: snapshot.month,
            year: snapshot.year,
            generatedAt: snapshot.generatedAt,
            days: snapshot.days.map { day in
                WorkoutDaySummary(
                    dateKey: day.dateKey,
                    day: day.day,
                    workouts: day.workouts.filter { matchingIDs.contains($0.id) }
                )
            }
        )
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
            return String(localized: "Newest")
        case .dateAscending:
            return String(localized: "Oldest")
        case .durationDescending:
            return String(localized: "Duration")
        case .energyDescending:
            return String(localized: "Energy")
        case .workoutType:
            return String(localized: "Workout Type")
        }
    }
}

struct BodyWorkoutRowPresentation {
    let detailIconName: String
    let detailText: String
    let trailingDetailText: String?

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
            let distanceText: String
            if let distanceUnitPreference {
                distanceText = BodyValueFormat.distanceText(
                    meters: distanceMeters,
                    locale: locale,
                    distanceUnitPreference: distanceUnitPreference
                )
            } else {
                distanceText = BodyValueFormat.distanceText(
                    meters: distanceMeters,
                    locale: locale,
                    unitPreference: unitPreference
                )
            }
            if let energyText {
                detailIconName = "flame.fill"
                detailText = energyText
                trailingDetailText = distanceText
            } else {
                detailIconName = "map.fill"
                detailText = distanceText
                trailingDetailText = nil
            }
        } else if let energyText {
            detailIconName = "flame.fill"
            detailText = energyText
            trailingDetailText = nil
        } else {
            detailIconName = "heart.text.square.fill"
            detailText = workout.sourceName
            trailingDetailText = nil
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
    var customName: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: workout.type.symbolName)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(workout.type.color)
                .frame(width: 56, height: 56)
                .background(workout.type.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(customName ?? workout.type.displayName)
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

            VStack(alignment: .trailing, spacing: 5) {
                Text(BodyValueFormat.durationText(for: workout.duration))
                    .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let trailingDetailText = presentation.trailingDetailText {
                    Text(trailingDetailText)
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
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 78)
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

/// Holds the workout detail sheet's live scroll offset. Kept as a standalone
/// `@Observable` so writing it on each scroll frame only invalidates the map-dim
/// overlay that reads `offset` instead of all of `BodyWorkoutDetailSheet`, whose body
/// rebuilds the comparison/splits/HR derivations on every evaluation.
/// (Mirrors `BodyHomeScrollState`.)
@Observable
private final class BodyWorkoutDetailScrollState {
    var offset: CGFloat = 0
}

/// Holds the 3D route hero's rotation, for the same reason as the scroll state above:
/// a drag writes on every frame, and only the hero reading it should redraw. `yaw` is
/// the settled angle in radians, `drag` the in-flight swipe folded into it when the
/// finger lifts. Internal so the hero can take it; not `private` for that reason alone.
@Observable
final class BodyWorkoutRouteYawState {
    var yaw: Double = 0
    var drag: Double = 0
    /// True from the first qualifying swipe frame until just after the finger lifts.
    /// The tap gap's Button fires on that same touch-up, so it reads this to tell a
    /// rotation's release from a tap — otherwise every swipe would also open the
    /// full-screen map. Read only inside the button's action (not its body), so
    /// flipping it never re-renders the sheet.
    var isSwiping = false
}

/// Dims the fixed route-map hero as the sheet content floats up over it. Reads
/// `scrollState.offset` itself so only this overlay re-renders per scroll frame, not
/// all of `BodyWorkoutDetailSheet`.
private struct BodyWorkoutMapDimOverlay: View {
    let scrollState: BodyWorkoutDetailScrollState
    let mapHeight: CGFloat

    private var opacity: Double {
        let progress = min(max(scrollState.offset / mapHeight, 0), 1)
        return progress * 0.95
    }

    var body: some View {
        Color.black
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

struct BodyWorkoutDetailSheet: View {
    /// Pops the push from the Workouts list and closes the full-screen cover from the
    /// list sheet alike — the nav bar is hidden, so the custom Back button below drives
    /// this instead of the system back chevron.
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue = BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.showWorkoutEffortSuggestionsKey) private var showWorkoutEffortSuggestions = true
    @AppStorage(BodyAppearancePreference.workoutRouteStyleKey) private var workoutRouteStyleRawValue = BodyWorkoutRouteStyle.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.drawsWorkoutRouteOnLoadKey) private var drawsRouteOnLoad = true
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    /// Where every detail chart's hold-to-scrub callout is published; the overlay
    /// below draws it above the page's Back/Share chrome.
    @State private var chartCallout = BodyChartFloatingCalloutState()
    @State private var isEditingEffort = false
    @State private var editingScore = 5
    @State private var isSavingEffort = false
    @State private var effortError: String?
    @State private var isRenamingWorkout = false
    @State private var renameDraft = ""
    /// The current effort prediction, shown persistently as "Body's prediction: N" on
    /// every workout — rated or not, editing or not. Cached in @State so it isn't
    /// rebuilt on each scroll frame; refreshed when the workout, max HR, comparison
    /// history, or the setting changes.
    @State private var prediction: WorkoutEffortEstimator.Estimate?
    /// Gate so the prediction publishes once, after both the comparison history and max
    /// HR settle — no provisional (uncalibrated) value flashes before the inputs load.
    @State private var predictionInputsSettled = false
    /// True once the 30-day history load has been awaited, whatever it found. The
    /// comparison window's `isComplete` can never turn true when the months simply
    /// cannot load (Workouts permission off, Apple Health unavailable, a failed fetch),
    /// so without this the Details legend would sit on "Calculating…" forever. Kept
    /// separate from `predictionInputsSettled`, which also waits on max HR.
    @State private var comparisonMonthsSettled = false
    /// True while the editor holds a value pre-filled from the prediction that the user
    /// hasn't adjusted — the one signal `saveEditingEffort` uses to exclude an
    /// accepted-unchanged suggestion from calibration (no feedback loop).
    @State private var editorPrefilledFromSuggestion = false
    /// True while the editor was opened (unrated) before the prediction settled, so its
    /// default 5 is a stand-in: when the settled prediction lands, `refreshPrediction`
    /// re-fills the editor — unless the user touched it first (any −/+ tap clears this).
    @State private var editorAwaitingPrediction = false
    @State private var route: WorkoutRoute?
    /// True once `loadWorkoutRoute` has returned — route or nil — so the Share
    /// button never appears mid-load.
    @State private var routeLoadSettled = false
    /// What the cheap `HKWorkoutRoute` probe knows before the fixes land. `.present`
    /// reserves the hero band up front, so the content never drops ~324 pt part-way
    /// through the load.
    @State private var routePresence: BodyWorkoutRoutePresence = .unknown
    /// Pinned on the first `.task` pass: a route already in the store's session cache is
    /// on screen from the first frame, so that visit must not replay the draw — the
    /// animation is for a wait, and there wasn't one.
    @State private var routeWasCachedOnOpen: Bool?
    @State private var splitData: WorkoutSplitData = .empty
    @State private var metricSeries: WorkoutMetricSeriesData = .empty
    @State private var heartRateRecoveryBPM: Double?
    /// Live scroll offset, held in an `@Observable` so writing it on every scroll frame
    /// only invalidates the map-dim overlay that reads it — not the whole sheet, whose
    /// body rebuilds the comparison/splits/HR-chart derivations on each evaluation.
    /// (Mirrors `BodyHomeScrollState`.)
    @State private var scrollState = BodyWorkoutDetailScrollState()
    /// Rotation of the 3D route hero. Session-only: the sheet — and with it this
    /// state — is rebuilt on each presentation, so the route always opens at rest.
    @State private var routeYawState = BodyWorkoutRouteYawState()
    @State private var showsFullScreenRouteMap = false
    @State private var showsShareSheet = false
    /// Resting screen y of the metrics column's top — the distance text when the
    /// workout has one, the duration otherwise. Measured in the content coordinate
    /// space (which doesn't move with scroll) plus the viewport's top inset, so it
    /// settles on layout instead of per scroll frame. Nil until measured.
    @State private var heroContentTop: CGFloat?
    /// The sheet's own top safe-area inset — where the ScrollView viewport begins,
    /// while the hero starts at the sheet's top edge.
    @State private var topSafeAreaInset: CGFloat = 0
    @Namespace private var routeMapZoom
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

    /// Coordinate space of the scrolling content: frames measured in it don't move
    /// with the scroll, so the hero measurement fires on layout changes only.
    private static let contentSpace = "workoutDetailContent"

    /// Invisible tap slop around the Share capsule. The map's full-screen tap
    /// target sits directly behind it, so a near-miss — or a hit on a corner of
    /// the capsule's bounding box, which the capsule shape doesn't cover — opened
    /// the map instead of the share sheet.
    private static let shareButtonTapSlop: CGFloat = 12
    /// Invisible vertical tap slop around the hero title's rename button, so its
    /// ~24 pt text line still meets the 44 pt minimum target without shifting layout.
    private static let titleTapSlop: CGFloat = 10

    private var routeStyle: BodyWorkoutRouteStyle {
        BodyWorkoutRouteStyle(rawValue: workoutRouteStyleRawValue) ?? .defaultValue
    }

    /// The route to draw: the loaded one, or the store's session cache on a reopen so an
    /// already-resolved route is on screen from the first body pass rather than after the
    /// `.task` round trip.
    private var displayedRoute: WorkoutRoute? {
        route ?? workoutStore.cachedWorkoutRoute(for: workout)
    }

    /// What the page currently believes about the route, folding the settled load in over
    /// the probe: a resolved route is present whatever the probe said, and once the load
    /// has settled with nothing, the band collapses.
    private var effectiveRoutePresence: BodyWorkoutRoutePresence {
        if displayedRoute != nil { return .present }
        if routeLoadSettled { return .absent }
        return routePresence
    }

    /// Height of the gap the content leaves for the hero. Animated as a height rather
    /// than switched by inserting the gap: SwiftUI lays a newly inserted fixed-height
    /// view out at full size on its first frame, so an insertion would snap the content
    /// down — exactly the jump this reserves the band to avoid.
    private var reservedGapHeight: CGFloat {
        effectiveRoutePresence.reservesHero ? mapHeight - contentTopOverlap : 0
    }

    /// The routeless layout has no hero gap above the content, so it reserves room for
    /// the Share capsule (44 pt + its 12 pt bottom slop) that overlays the top-trailing
    /// corner. Interpolated alongside the gap so the two move as one.
    private var contentTopPadding: CGFloat {
        effectiveRoutePresence.reservesHero ? 24 : 60
    }

    /// Whether this visit should draw the route in. A route already cached when the page
    /// opened was never waited for, so it just appears; Reduce Motion and the Draw Route
    /// setting opt out entirely.
    ///
    /// The Map style never draws: its route is baked into the map snapshot rather than
    /// stroked by the hero, so Route Style offers the switch only for the map-free
    /// styles. The stored preference is left alone — picking Plain or 3D again restores
    /// whatever it was set to.
    private var drawsRouteReveal: Bool {
        guard routeStyle.supportsRouteDraw, drawsRouteOnLoad, !reduceMotion else { return false }
        return !(routeWasCachedOnOpen ?? (workoutStore.cachedWorkoutRoute(for: workout) != nil))
    }

    /// Whether the reserved band shimmers while the fixes load. It stands in wherever no
    /// draw is coming to fill the wait — the switch turned off, or the Map style, which
    /// can't draw at all. (Reduce Motion is not one of these: the draw is still the plan,
    /// it just lands finished, and the shimmer would be motion where none was wanted.)
    private var showsRouteLoadingShimmer: Bool {
        !(routeStyle.supportsRouteDraw && drawsRouteOnLoad)
    }

    private var routeReservationAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0)
    }

    /// Carries the hero's arrival. Needed because the placeholder and the real hero are
    /// different views: without it the shimmer would snap to the route.
    private var routeRevealAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.35)
    }

    /// Both heroes center the route's vertical extent midway between the top safe
    /// area (below the status bar / Dynamic Island — anchoring at the physical screen
    /// top read too high on island phones) and the top of the metrics column. Until
    /// that column is measured, fall back to where the fixed layout puts it — the tap
    /// gap plus the content's top padding, below the safe area — so the first frame
    /// is already close and the map's re-snapshot isn't visible.
    private var routeTargetCenterY: CGFloat {
        let contentTop = heroContentTop ?? (topSafeAreaInset + mapHeight - contentTopOverlap + 24)
        return (topSafeAreaInset + contentTop) / 2
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let route = displayedRoute {
                switch routeStyle {
                case .map:
                    // The map is the page background: pure black with the route map
                    // pinned to the top, blending into the black. Content floats over
                    // it with no backing of its own (like the home and detail pages).
                    Color.black.ignoresSafeArea()

                    BodyWorkoutRouteMapHero(route: route, tint: workout.type.color, targetCenterY: routeTargetCenterY, topInset: topSafeAreaInset)
                        .frame(height: mapHeight)
                        .matchedTransitionSource(id: "routeMap", in: routeMapZoom)
                        .overlay {
                            // Dim the map as the content floats up over it. Reads
                            // `scrollState.offset` itself so only this layer re-renders per
                            // scroll frame, not all of the sheet.
                            BodyWorkoutMapDimOverlay(scrollState: scrollState, mapHeight: mapHeight)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                case .plain:
                    // No tiles to blend into, so the page keeps the routeless
                    // workout-tint backdrop and the route strokes over it.
                    sheetBackdrop

                    BodyWorkoutRoutePlainHero(route: route, tint: workout.type.color, targetCenterY: routeTargetCenterY, topInset: topSafeAreaInset, drawsReveal: drawsRouteReveal)
                        .frame(height: mapHeight)
                        .matchedTransitionSource(id: "routeMap", in: routeMapZoom)
                        .overlay {
                            BodyWorkoutMapDimOverlay(scrollState: scrollState, mapHeight: mapHeight)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                case .threeD:
                    // Same page as Plain — the ribbon strokes over the workout-tint
                    // backdrop, and falls back to the plain trace on its own when the
                    // route carries no altitude.
                    sheetBackdrop

                    BodyWorkoutRoute3DHero(route: route, tint: workout.type.color, targetCenterY: routeTargetCenterY, topInset: topSafeAreaInset, yawState: routeYawState, drawsReveal: drawsRouteReveal)
                        .frame(height: mapHeight)
                        .matchedTransitionSource(id: "routeMap", in: routeMapZoom)
                        .overlay {
                            BodyWorkoutMapDimOverlay(scrollState: scrollState, mapHeight: mapHeight)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            } else if effectiveRoutePresence.reservesHero {
                // The probe confirmed a route but the fixes haven't landed. Hold the
                // band open on the style's own backdrop so the page doesn't have to
                // change background a second time when the hero arrives, and — when the
                // draw is switched off — shimmer rather than sit empty.
                if routeStyle == .map {
                    Color.black.ignoresSafeArea()
                } else {
                    sheetBackdrop
                }

                if showsRouteLoadingShimmer {
                    BodyWorkoutRouteHeroShimmer(
                        tint: workout.type.color,
                        targetCenterY: routeTargetCenterY,
                        topInset: topSafeAreaInset
                    )
                    .frame(height: mapHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
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
                scrollState.offset = offset
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onGeometryChange(for: CGFloat.self) { proxy in
            // The ScrollView keeps the sheet's safe area while the hero ignores it, so
            // this inset converts content-space positions into hero-space ones.
            proxy.safeAreaInsets.top
        } action: { inset in
            topSafeAreaInset = inset
        }
        .overlay(alignment: .topLeading) {
            // The nav bar is hidden, so this stands in for the system back button —
            // same safe-area trick as the Share capsule opposite it. Always visible
            // (no route/settle gating) since both entry paths (push from the list,
            // full-screen cover from the list sheet) need a way back.
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .modifier(BodyWorkoutBackButtonBackground())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .accessibilityLabel("Back")
        }
        .overlay(alignment: .topTrailing) {
            // The ZStack keeps its safe-area insets, so the button clears the
            // status bar / Dynamic Island even though the map extends under them
            // (same trick as the full-screen map's close button). The animation
            // is scoped to this subtree so the button fades in once the route fetch
            // settles, for routed and routeless workouts alike, without animating the
            // sheet's own layout swap.
            ZStack {
                if routeLoadSettled {
                    Button {
                        showsShareSheet = true
                    } label: {
                        Text("Share")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .modifier(BodyWorkoutShareButtonBackground())
                            // Grows the hit area without moving the capsule: the
                            // trailing page padding below absorbs the sideways slop.
                            // Nothing on top — the capsule already sits at the top of
                            // the safe area, and expanding past it wouldn't hit-test.
                            .padding(
                                EdgeInsets(
                                    top: 0,
                                    leading: Self.shareButtonTapSlop,
                                    bottom: Self.shareButtonTapSlop,
                                    trailing: Self.shareButtonTapSlop
                                )
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20 - Self.shareButtonTapSlop)
                    .accessibilityLabel("Share Workout")
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: routeLoadSettled)
        }
        .overlay {
            // Last overlay on the stack, so a chart's scrub callout draws over the
            // Back and Share controls instead of under them.
            BodyChartFloatingCalloutLayer(state: chartCallout)
        }
        .onDisappear {
            chartCallout.callout = nil
        }
        .fullScreenCover(isPresented: $showsShareSheet) {
            BodyWorkoutShareSheet(workout: workout, route: displayedRoute, presentation: presentation)
        }
        .alert("Rename Workout", isPresented: $isRenamingWorkout) {
            TextField(workout.type.displayName, text: $renameDraft)

            Button("Save") {
                workoutStore.setCustomName(renameDraft, workoutID: workout.id)
            }

            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showsFullScreenRouteMap) {
            if let route = displayedRoute {
                BodyWorkoutRouteMapFullScreen(route: route, tint: workout.type.color)
                    .navigationTransition(.zoom(sourceID: "routeMap", in: routeMapZoom))
            }
        }
        .task {
            routeLoadSettled = false
            routePresence = .unknown
            if routeWasCachedOnOpen == nil {
                routeWasCachedOnOpen = workoutStore.cachedWorkoutRoute(for: workout) != nil
            }

            // The probe reserves the hero band early; it must never gate the fetch. It
            // runs in its own child task because `fetchWorkout` wraps a raw HKSampleQuery
            // with neither cancellation nor a timeout — awaiting it here would put a
            // genuine stall surface ahead of the route, the splits, and Share.
            let probeTask = Task { @MainActor in
                let presence = await workoutStore.workoutRoutePresence(for: workout)
                guard !Task.isCancelled, route == nil else { return }
                withAnimation(routeReservationAnimation) { routePresence = presence }
            }
            defer { probeTask.cancel() }

            // Fixes first, with `locality` still nil: the reverse geocode is a network
            // round trip and the route's draw-in shouldn't queue behind it.
            async let loadedCoordinates = workoutStore.loadWorkoutRouteCoordinates(for: workout)
            // Load the route and distance samples concurrently so the splits
            // section isn't blocked behind the route fetch + reverse geocoding.
            async let loadedSplitData = workoutStore.loadWorkoutSplitData(for: workout)

            let coordinatesRoute = await loadedCoordinates
            guard !Task.isCancelled else { return }
            withAnimation(routeRevealAnimation) { route = coordinatesRoute }

            // Served from the cache the stage above just filled, so this is only the
            // reverse geocode folding the city label in.
            async let loadedRoute = workoutStore.loadWorkoutRoute(for: workout)
            let resolvedRoute = await loadedRoute
            // The loader returns nil on cancel, so a cancelled reload must not flip a
            // routed page to routeless.
            guard !Task.isCancelled else { return }
            route = resolvedRoute
            withAnimation(routeReservationAnimation) {
                routePresence = resolvedRoute == nil ? .absent : .present
            }
            // Settle — and so reveal Share — before awaiting the splits. Share is gated
            // on this flag alone, so awaiting the distance read first would let a slow
            // splits query hide Share long after the route finished.
            routeLoadSettled = true
            splitData = await loadedSplitData
        }
        .task(id: "\(workout.id.uuidString)-\(workoutStore.permissionSelection.rawValue)") {
            predictionInputsSettled = false
            comparisonMonthsSettled = false
            prediction = nil
            editorPrefilledFromSuggestion = false
            editorAwaitingPrediction = false
            // Clear the metric series and heart-rate recovery up front so a Workout
            // Metrics (or Heart) opt-out hides the cards and the tile immediately, then
            // re-read them below under the new selection.
            metricSeries = .empty
            heartRateRecoveryBPM = nil
            // Resolve both estimator inputs before publishing anything: max HR and the
            // 30-day comparison history. Publishing once, after both settle, means the
            // label never shows a provisional (uncalibrated) number that then flips.
            // Re-keying on the permission selection re-resolves the anchor when Date of
            // Birth toggles: out of scope, `userMaxHeartRate()` returns nil and the HR
            // chart falls back to the session-peak HR.
            async let maxHeartRate = workoutStore.userMaxHeartRate()
            await workoutStore.ensureComparisonMonthsLoaded(for: workout)
            // Before the max-HR await, so the Details legend resolves as soon as the
            // history lands instead of waiting on an unrelated query.
            comparisonMonthsSettled = true
            resolvedMaxHeartRate = await maxHeartRate
            predictionInputsSettled = true
            refreshPrediction()
            async let loadedMetricSeries = workoutStore.loadWorkoutMetricSeriesData(for: workout)
            async let loadedHeartRateRecovery = workoutStore.loadWorkoutHeartRateRecovery(for: workout)
            let resolvedMetricSeries = await loadedMetricSeries
            let resolvedHeartRateRecovery = await loadedHeartRateRecovery
            guard !Task.isCancelled else { return }
            metricSeries = resolvedMetricSeries
            heartRateRecoveryBPM = resolvedHeartRateRecovery
        }
        .onChange(of: showWorkoutEffortSuggestions) { refreshPrediction() }
        .onChange(of: effectiveRoutePresence.reservesHero) { _, reservesHero in
            // The gap above the content is open only while the hero band is reserved, so
            // a reserved measurement doesn't apply once it collapses. The arrival
            // direction needs no reset — `updateHeroContentTop` never stores routeless
            // measurements, and clearing here could race the geometry callback that
            // just measured the reserved layout and lose its value for good.
            if !reservesHero {
                heroContentTop = nil
            }
        }
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

    /// Transparent gap that reveals the map background above; the content below floats
    /// over it with no backing of its own. The map itself is behind the ScrollView and
    /// can't be hit-tested, so the gap doubles as its tap target — and, in 3D, as the
    /// surface the rotation swipe lands on. Map and Plain get exactly the button they
    /// had before rotation existed.
    @ViewBuilder
    private var routeTapGap: some View {
        // While the band is merely reserved there is no route to open or rotate, so the
        // gap is inert space until the fixes land. The height is always driven by
        // `reservedGapHeight`, which animates between 0 and the hero's band rather than
        // the gap being inserted — SwiftUI lays an inserted fixed-height view out at full
        // size immediately, which is the snap this whole feature removes.
        if displayedRoute == nil {
            Color.clear
                .frame(height: reservedGapHeight)
                .accessibilityHidden(true)
        } else {
            interactiveRouteTapGap
        }
    }

    @ViewBuilder
    private var interactiveRouteTapGap: some View {
        let gap = Button {
            // The release that ends a rotation swipe lands here too; only a real
            // tap opens the map.
            guard !routeYawState.isSwiping else { return }
            showsFullScreenRouteMap = true
        } label: {
            Color.clear
                .frame(height: reservedGapHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route map")

        if routeStyle == .threeD {
            gap
                .accessibilityHint("Shows a full screen interactive map. Swipe left or right to rotate the 3D route.")
                // VoiceOver can't perform the swipe itself, so the same rotation is
                // offered as two 30° steps.
                // Same handedness as the swipe: "right" moves the near edge right.
                .accessibilityAction(named: Text("Rotate Left")) { turnRoute(by: .pi / 6) }
                .accessibilityAction(named: Text("Rotate Right")) { turnRoute(by: -.pi / 6) }
                .simultaneousGesture(routeYawGesture)
        } else {
            gap
                .accessibilityHint("Shows a full screen interactive map")
        }
    }

    /// Radians of rotation per point of horizontal swipe (~0.6°/pt): half a screen
    /// width turns the route about a quarter turn. Negative because the finger drags
    /// the ribbon's NEAR edge: with the camera looking north from the south, moving
    /// that edge rightwards is a counter-clockwise turn seen from above, and the
    /// projection's positive yaw is clockwise.
    private static let routeYawRadiansPerPoint = -Double.pi / 300

    /// Horizontal swipe on the 3D hero's tap gap, turning the route about its own
    /// centre. Recognized simultaneously so it never blocks the sheet's scrolling or
    /// the gap's own tap, and it writes only to the yaw state so a drag frame redraws
    /// the hero alone.
    private var routeYawGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                // Recomputed rather than latched, so a swipe that turns vertical
                // mid-drag hands the rotation back instead of leaving it stuck.
                let isSwipe = Self.isRouteYawSwipe(value)
                routeYawState.drag = isSwipe
                    ? Double(value.translation.width) * Self.routeYawRadiansPerPoint
                    : 0
                // Latched, not recomputed: once a drag has rotated the route, its
                // release must not read as a tap even if it ended near-vertical.
                if isSwipe {
                    routeYawState.isSwiping = true
                }
            }
            .onEnded { value in
                if Self.isRouteYawSwipe(value) {
                    turnRoute(by: Double(value.translation.width) * Self.routeYawRadiansPerPoint)
                }
                routeYawState.drag = 0
                // The Button's action fires on this same touch-up, in an order SwiftUI
                // doesn't promise — clear the latch on the next run-loop turn so the
                // action sees it either way.
                let yawState = routeYawState
                DispatchQueue.main.async {
                    yawState.isSwiping = false
                }
            }
    }

    /// A drag turns the route when it starts clear of the system's edge-back strip
    /// (which must stay a back swipe, cf. `BodyHomeView.isEdgeBackSwipe`) and runs more
    /// sideways than up and down — a scroll must never spin the route.
    private static func isRouteYawSwipe(_ value: DragGesture.Value) -> Bool {
        value.startLocation.x > 20 && abs(value.translation.width) > abs(value.translation.height)
    }

    private func turnRoute(by delta: Double) {
        routeYawState.yaw = Self.normalizedYaw(routeYawState.yaw + delta)
    }

    /// Folds a settled angle into (−π, π], so turning the same way over and over can't
    /// grow the stored yaw without bound.
    private static func normalizedYaw(_ yaw: Double) -> Double {
        var normalized = yaw.truncatingRemainder(dividingBy: 2 * .pi)
        if normalized > .pi {
            normalized -= 2 * .pi
        }
        if normalized <= -.pi {
            normalized += 2 * .pi
        }
        return normalized
    }

    private var compactWorkoutContent: some View {
        // Build the presentation once per body pass and thread it to the sections that
        // read it. It calls `comparisonContext(for:)` and constructs a full
        // `WorkoutDetailPresentation`, so evaluating it once per section (four of them)
        // wasted that work on every store publish.
        let presentation = presentation
        // Both halves of the merged Pace card, read once: the card is shown when
        // either exists, so an inline check would recompute the splits.
        let paceOrSpeed = paceOrSpeedPresentation
        let splits = splitsPresentation
        return VStack(spacing: 0) {
            // Always present, sized by `reservedGapHeight` — see `routeTapGap`.
            routeTapGap

            VStack(spacing: 18) {
                topEntryPanel(presentation: presentation)
                workoutDetailsCard(presentation: presentation)
                effortCard
                heartRateSection(presentation: presentation)
                if paceOrSpeed != nil || splits != nil {
                    BodyWorkoutPaceCard(
                        presentation: paceOrSpeed,
                        splits: splits,
                        floatingCallout: chartCallout
                    )
                }
                if let elevationPresentation {
                    BodyWorkoutElevationLineCard(
                        presentation: elevationPresentation,
                        floatingCallout: chartCallout
                    )
                }
                if let cadencePresentation {
                    BodyWorkoutBucketedSeriesCard(
                        presentation: cadencePresentation,
                        floatingCallout: chartCallout
                    )
                }
                if let strideLengthPresentation {
                    BodyWorkoutBucketedSeriesCard(
                        presentation: strideLengthPresentation,
                        floatingCallout: chartCallout
                    )
                }
                if let groundContactPresentation {
                    BodyWorkoutBucketedSeriesCard(
                        presentation: groundContactPresentation,
                        floatingCallout: chartCallout
                    )
                }
                if let verticalOscillationPresentation {
                    BodyWorkoutBucketedSeriesCard(
                        presentation: verticalOscillationPresentation,
                        floatingCallout: chartCallout
                    )
                }
                sourceFooter(presentation: presentation)
            }
            .padding(.horizontal, 20)
            // The routeless layout has no map gap above the content, so it reserves
            // room for the Share capsule (44 pt + its 12 pt bottom slop) that overlays
            // the top-trailing corner.
            .padding(.top, contentTopPadding)
            .padding(.bottom, 22)
            .readableContentColumn()
        }
        .coordinateSpace(.named(Self.contentSpace))
    }

    /// Stores the metrics column's resting screen y, the anchor the route centers
    /// against. Ignored while the hero band isn't reserved: the routeless layout has no
    /// gap above the content, so its measurement would place the route far too high.
    ///
    /// Keyed on the reservation rather than on the loaded route so the anchor settles
    /// while the band is still empty — the draw then runs in its final framing instead of
    /// re-centering part-way through.
    private func updateHeroContentTop(contentMinY: CGFloat) {
        guard effectiveRoutePresence.reservesHero else {
            return
        }

        let screenY = topSafeAreaInset + contentMinY
        if heroContentTop != screenY {
            heroContentTop = screenY
        }
    }

    private func topEntryPanel(presentation: WorkoutDetailPresentation) -> some View {
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
                    Button {
                        renameDraft = workoutStore.workoutCustomNames[workout.id] ?? ""
                        isRenamingWorkout = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(presentation.title)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)

                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        // Grows the tap area to a 44 pt minimum without moving the
                        // title: the vertical slop is padded in here and cancelled
                        // out below, like the Share capsule's slop. It stays as wide
                        // as the title only — the map/route surface behind this
                        // column must remain hittable.
                        .padding(.vertical, Self.titleTapSlop)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -Self.titleTapSlop)
                    .accessibilityLabel(presentation.title)
                    .accessibilityHint("Rename Workout")

                    heroContextRow

                    Text(presentation.heroDateLineText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.primary)
                            + Text(" \(unit)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.secondary)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)

                        Text("Distance")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .trailing, spacing: -2) {
                    Text(presentation.durationClockText)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)

                    Text("Duration")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 152, alignment: .trailing)
            .onGeometryChange(for: CGFloat.self) { proxy in
                // This column's top is the distance text's top when the workout has a
                // distance, the duration's otherwise — the line the route centers above.
                proxy.frame(in: .named(Self.contentSpace)).minY
            } action: { minY in
                updateHeroContentTop(contentMinY: minY)
            }
        }
    }

    /// Locality above weather, each on its own line. Either line is dropped when its
    /// value is missing.
    ///
    /// The locality half is held open for the whole routed layout, invisible until the
    /// reverse geocode lands. The row sits in the hero's leading column while the metrics
    /// column opposite is what `heroContentTop` measures, so letting it appear late would
    /// nudge that anchor, re-frame every hero, and re-fire the map snapshotter part-way
    /// through the route's draw.
    @ViewBuilder
    private var heroContextRow: some View {
        let locality = displayedRoute?.locality
        let localityText = locality ?? (effectiveRoutePresence.reservesHero ? " " : nil)
        let temperatureText = workout.weatherTemperatureCelsius.flatMap {
            BodyValueFormat.temperatureHeroText(
                celsius: $0,
                temperatureUnitPreference: selectedTemperatureUnitPreference
            )
        }
        // Whole percent with no space before the sign, matching the temperature's
        // tight hero formatting rather than the Details tile's "64 %".
        let humidityText = workout.weatherHumidityPercent.flatMap { humidity -> String? in
            guard humidity.isFinite else {
                return nil
            }

            return "\(BodyValueFormat.numberText(humidity.rounded(), decimals: 0))%"
        }
        let weatherText = [temperatureText, humidityText]
            .compactMap { $0 }
            .joined(separator: ", ")

        if localityText != nil || !weatherText.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let localityText {
                    heroContextPair(systemImage: "location.fill", text: localityText)
                        .opacity(locality != nil ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.28),
                            value: displayedRoute?.locality
                        )
                }

                if !weatherText.isEmpty {
                    // The recorded sky condition when the source wrote one; the
                    // thermometer otherwise, so an indoor or condition-less workout
                    // still reads as a temperature.
                    heroContextPair(
                        systemImage: workout.weatherCondition?.symbolName ?? "thermometer.medium",
                        text: weatherText
                    )
                }
            }
            // Both rows shrink themselves to fit (`minimumScaleFactor`), which lets the
            // hero's HStack propose them less width than they'd like and hand the slack
            // to the metrics column — the rows then render below their real point size
            // while the date line beside them stays full size. The priority makes them
            // claim their ideal width first, so the scale factor only engages for a
            // locality long enough to genuinely need it.
            .layoutPriority(1)
        }
    }

    private func heroContextPair(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(workout.type.color)
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func workoutDetailsCard(presentation: WorkoutDetailPresentation) -> some View {
        // Heart-rate recovery loads separately when the summary carries none, so it
        // joins the grid as a trailing tile once it lands — skipped when the summary
        // already emitted the tile, so the two paths never both show it.
        var metrics = presentation.detailMetrics
        if let heartRateRecoveryBPM, !metrics.contains(where: { $0.kind == .heartRateRecovery }) {
            metrics.append(WorkoutDetailPresentation.heartRateRecoveryMetric(bpm: heartRateRecoveryBPM))
        }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Details")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                if let availability = presentation.comparisonAvailability {
                    BodyWorkoutComparisonLegend(availability: availability)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 20) {
                ForEach(metrics, id: \.kind) { metric in
                    BodyWorkoutDetailMetricTile(
                        title: metric.title,
                        value: metric.value,
                        comparison: metric.comparison
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

    /// The prediction line stays up while the estimator's inputs load — as
    /// "Calculating…", the same stand-in the Details legend shows — so the settled
    /// number crossfades into place instead of the line appearing from nothing. It's
    /// dropped only once the inputs have settled without an estimate (a workout with
    /// no usable signal), or when suggestions are off.
    private var showsEffortPredictionLine: Bool {
        showWorkoutEffortSuggestions && (prediction != nil || !predictionInputsSettled)
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

                if showsEffortPredictionLine {
                    BodyWorkoutEffortPredictionLine(score: prediction?.score)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Scoped to the line's own appearance: a workout whose inputs settle
            // without an estimate fades the placeholder out instead of cutting it.
            // Keyed on that alone, so editing the effort beside it is untouched.
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0),
                value: showsEffortPredictionLine
            )

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
                editorPrefilledFromSuggestion = false
                editorAwaitingPrediction = false
                withAnimation(.snappy(duration: 0.28)) { editingScore = max(editingScore - 1, 1) }
            }
            effortStepButton(systemName: "plus", color: color, isEnabled: editingScore < 10 && !isSavingEffort) {
                editorPrefilledFromSuggestion = false
                editorAwaitingPrediction = false
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
        // Pre-fill from the already-settled prediction — estimating here again could
        // publish a provisional number on a fast tap before the inputs load.
        let estimate = showWorkoutEffortSuggestions ? prediction : nil
        if let effortLevel {
            // A logged workout opens at its saved value — the pre-fill is only for
            // workouts the user hasn't rated yet.
            editingScore = min(max(Int(effortLevel.rounded()), 1), 10)
            editorPrefilledFromSuggestion = false
            editorAwaitingPrediction = false
        } else if let estimate {
            // Pre-fill the editor from the prediction for an unrated workout. The value
            // is snapshotted into editingScore, so a later load can't move it mid-edit.
            editingScore = estimate.score
            editorPrefilledFromSuggestion = true
            editorAwaitingPrediction = false
        } else {
            editingScore = 5
            editorPrefilledFromSuggestion = false
            // Tapped before the prediction settled: the 5 is a stand-in, so let the
            // settled prediction re-fill the untouched editor when it lands.
            editorAwaitingPrediction = showWorkoutEffortSuggestions && !predictionInputsSettled
        }
        withAnimation(.snappy(duration: 0.3)) { isEditingEffort = true }
    }

    private func cancelEditingEffort() {
        editorPrefilledFromSuggestion = false
        editorAwaitingPrediction = false
        withAnimation(.snappy(duration: 0.3)) { isEditingEffort = false }
    }

    private func saveEditingEffort() {
        isSavingEffort = true
        // Saving commits the shown value; a prediction landing mid-save must not move it.
        editorAwaitingPrediction = false
        let value = Double(editingScore)
        // Saved straight from an unadjusted pre-fill → the rating is the prediction's
        // own output, so mark it for exclusion from future calibration; any other save
        // clears the mark (the rating is the user's judgment again).
        let acceptedSuggestionUnchanged = editorPrefilledFromSuggestion
        Task {
            do {
                try await workoutStore.saveWorkoutEffort(workoutID: workout.id, score: value)
                workoutStore.setEffortSuggestionAccepted(acceptedSuggestionUnchanged, workoutID: workout.id)
                isSavingEffort = false
                editorPrefilledFromSuggestion = false
                // The prediction label stays shown after saving — it's decoupled from
                // the edit session, so the user can compare it against their own rating.
                withAnimation(.snappy(duration: 0.3)) { isEditingEffort = false }
            } catch {
                isSavingEffort = false
                effortError = String(localized: "Body couldn't save the effort rating to Apple Health. Make sure Body is allowed to update Workouts in Settings › Health › Data Access & Devices.")
            }
        }
    }

    /// Recomputes the persistent prediction from currently-loaded inputs. Cheap and
    /// synchronous; called from the coordinated load task and the setting toggle, never
    /// per render, so scrolling doesn't repeatedly rebuild the 30-day comparison window.
    /// Publishes only after both inputs settle (`predictionInputsSettled`), and then
    /// best-effort even if the history load couldn't complete every month — it ran once,
    /// so there's no provisional flash.
    private func refreshPrediction() {
        guard predictionInputsSettled else { return }
        prediction = showWorkoutEffortSuggestions
            ? WorkoutEffortEstimator.estimate(for: effortEstimateInput())
            : nil
        // An editor opened on the placeholder 5 before the inputs settled (and untouched
        // since) moves to the real pre-fill now, so a fast tap can't freeze a stand-in
        // value beside a different settled prediction.
        if editorAwaitingPrediction {
            editorAwaitingPrediction = false
            if isEditingEffort, !isSavingEffort, let prediction {
                withAnimation(.snappy(duration: 0.28)) { editingScore = prediction.score }
                editorPrefilledFromSuggestion = true
            }
        }
    }

    /// Everything the effort estimator needs, read synchronously from already-published
    /// store state — no fetches, safe to call from the tap handler on the main actor.
    /// Delegates to the store so the detail view and the auto-apply pass build the
    /// estimator input identically.
    private func effortEstimateInput() -> WorkoutEffortEstimator.Input {
        workoutStore.effortEstimateInput(for: workout, maxHeartRate: resolvedMaxHeartRate)
    }

    private func heartRateSection(presentation: WorkoutDetailPresentation) -> some View {
        BodyWorkoutHeartRateChartCard(
            samples: presentation.heartRateSamples,
            maxHeartRate: resolvedMaxHeartRate ?? workout.maximumHeartRateBeatsPerMinute,
            floatingCallout: chartCallout
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceFooter(presentation: WorkoutDetailPresentation) -> some View {
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
        let comparison = workoutStore.comparisonContext(for: workout)
        return WorkoutDetailPresentation(
            workout: workout,
            distanceUnitPreference: selectedDistanceUnitPreference,
            energyUnitPreference: selectedEnergyUnitPreference,
            comparisonWorkouts: comparison.priorWorkouts,
            comparisonDataComplete: comparison.isComplete,
            comparisonLoadSettled: comparisonMonthsSettled,
            customName: workoutStore.workoutCustomNames[workout.id]
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

    private var selectedTemperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.TemperatureUnitPreference.storedValue(from: selectedTemperatureUnitRawValue)
    }

    /// Per-km/mi split rows for the current unit preference; nil when the
    /// workout has no usable distance samples or isn't a pace/speed activity.
    /// Recomputes on unit toggle without refetching (boundaries are unit-derived).
    private var splitsPresentation: WorkoutSplitsPresentation? {
        let unitMeters = selectedDistanceUnitPreference == .miles ? 1_609.344 : 1_000.0
        let splits = WorkoutSplitCalculator.splits(
            samples: splitData.distanceSamples,
            unitMeters: unitMeters,
            workoutStart: workout.startDate,
            workoutEnd: workout.startDate.addingTimeInterval(max(0, workout.duration)),
            segments: splitData.segments
        )
        return WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: workout.type.paceStyle,
            distanceUnitPreference: selectedDistanceUnitPreference,
            heartRateSamples: workout.heartRateSamples ?? [],
            stepSamples: splitData.stepSamples
        )
    }

    /// The route's elevation profile for the current unit preference; nil when the
    /// workout has no route, too few altitude samples, or a flat course — which
    /// hides the card.
    private var elevationPresentation: WorkoutElevationLinePresentation? {
        WorkoutElevationLinePresentation(
            profile: displayedRoute?.elevationProfile ?? [],
            workoutDuration: workout.effectiveEndDate.timeIntervalSince(workout.startDate),
            ascentMeters: workout.elevationAscendedMeters,
            distanceUnitPreference: selectedDistanceUnitPreference
        )
    }

    /// Per-bucket pace (walk/run/hike) or speed (cycling) bars; nil when the workout
    /// has too little distance data or isn't a pace/speed activity.
    private var paceOrSpeedPresentation: WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.paceOrSpeed(
            data: metricSeries,
            type: workout.type,
            distanceUnitPreference: selectedDistanceUnitPreference
        )
    }

    /// Per-bucket step cadence (walk/run/hike) or cycling cadence bars; nil when the
    /// workout has too little data.
    private var cadencePresentation: WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.cadence(
            data: metricSeries,
            type: workout.type,
            distanceUnitPreference: selectedDistanceUnitPreference
        )
    }

    /// Per-bucket stride length bars for the current unit preference; nil when the
    /// workout has too little stride data (or isn't a stepping activity), which
    /// hides the card.
    private var strideLengthPresentation: WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.strideLength(
            data: metricSeries,
            type: workout.type,
            distanceUnitPreference: selectedDistanceUnitPreference
        )
    }

    /// Per-bucket ground contact time bars; nil unless the watch recorded the
    /// running-form metric.
    private var groundContactPresentation: WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.groundContactTime(
            data: metricSeries,
            type: workout.type,
            distanceUnitPreference: selectedDistanceUnitPreference
        )
    }

    /// Per-bucket vertical oscillation bars; nil unless the watch recorded the
    /// running-form metric.
    private var verticalOscillationPresentation: WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.verticalOscillation(
            data: metricSeries,
            type: workout.type,
            distanceUnitPreference: selectedDistanceUnitPreference
        )
    }
}

/// iOS 26 Liquid Glass capsule for the detail share button; pre-26 mirrors the
/// full-screen map close button's material treatment.
private struct BodyWorkoutShareButtonBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// iOS 26 Liquid Glass circle for the detail back button — the circular twin of
/// `BodyWorkoutShareButtonBackground`; pre-26 mirrors the same material treatment.
private struct BodyWorkoutBackButtonBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// The line beside the "Details" heading naming what the badges under it are showing.
/// One `Text` whose string changes rather than three swapped views, so the wording
/// crossfades into place while the badge digits roll over beneath it.
private struct BodyWorkoutComparisonLegend: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let availability: WorkoutMetricComparisonAvailability

    private var text: String {
        switch availability {
        case .ready:
            return String(localized: "vs 30-day avg")
        case .calculating:
            return String(localized: "Calculating…")
        case .insufficientHistory:
            return String(localized: "Not enough history yet")
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary)
            .lineLimit(1)
            // The two placeholder states are markedly longer than "vs 30-day avg", so
            // they shrink rather than wrap — a wrap would change the header's height
            // mid-crossfade.
            .minimumScaleFactor(0.8)
            .contentTransition(reduceMotion ? .identity : .opacity)
            // Same curve as `bodyLegendNumberFlip`, so the wording and the numbers
            // settle together.
            .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: text)
    }
}

/// The persistent "Body's prediction: N" line under the effort value. One `Text` whose
/// string changes rather than a placeholder view swapped for a value view, so the
/// stand-in crossfades into the settled number the way the Details legend's does.
private struct BodyWorkoutEffortPredictionLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Nil while the estimator's inputs (30-day history, max HR) are still loading.
    let score: Int?

    private var text: String {
        guard let score else { return String(localized: "Body's prediction: Calculating…") }
        return String(localized: "Body's prediction: \(score)")
    }

    private var accessibilityText: String {
        guard let score else { return String(localized: "Body's prediction: Calculating…") }
        return String(localized: "Body's prediction: \(score) out of 10")
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(reduceMotion ? .identity : .opacity)
            // Same curve as `BodyWorkoutComparisonLegend`, so a page whose Details
            // legend and prediction settle together settles as one motion.
            .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: text)
            .accessibilityLabel(accessibilityText)
    }
}

private struct BodyWorkoutDetailMetricTile: View {
    let title: String
    let value: String
    let comparison: WorkoutMetricComparison?

    /// Combined VoiceOver label so the caption's ↑/↓ glyph is spoken meaningfully
    /// ("12 percent lower than 30-day average") instead of read as a bare symbol.
    private var metricAccessibilityLabel: String {
        var parts = [title, value]
        if let comparison {
            parts.append(comparison.accessibilityLabel)
        }
        return parts.joined(separator: ", ")
    }

    /// Splits a formatted value ("172 BPM") into number and trailing unit so the
    /// unit can read smaller and gray like the hero distance. Values that don't
    /// start with a digit (e.g. "No Data", "—") stay whole; a leading minus sign
    /// counts as a number so a sub-zero temperature ("-10 °C") still splits.
    private var valueParts: (number: String, unit: String) {
        let digits = value.drop { $0 == "-" || $0 == "\u{2212}" }
        guard let first = digits.first, first.isNumber,
              let spaceIndex = value.firstIndex(of: " ") else {
            return (value, "")
        }
        return (String(value[..<spaceIndex]), String(value[value.index(after: spaceIndex)...]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(valueParts.number)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if !valueParts.unit.isEmpty || comparison != nil {
                    VStack(alignment: .leading, spacing: -2) {
                        if let comparison {
                            Text(comparison.badgeText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                // The "0%" stand-in holds this slot until the history
                                // lands, so the real percentage rolls in from it.
                                .bodyLegendNumberFlip(value: comparison.badgeText)
                        }
                        if !valueParts.unit.isEmpty {
                            Text(valueParts.unit)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metricAccessibilityLabel)
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

    /// Tapping the breakdown swaps the share column between percentage and time.
    @State private var showsDuration = false

    private let pctWidth: CGFloat = 60
    private let durationWidth: CGFloat = 84
    private let bpmWidth: CGFloat = 84
    private let barHeight: CGFloat = 12

    private var valueWidth: CGFloat { showsDuration ? durationWidth : pctWidth }

    var body: some View {
        VStack(spacing: 11) {
            headerRow
            ForEach(zones) { zone in
                row(for: zone)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                showsDuration.toggle()
            }
        }
    }

    private var headerRow: some View {
        let valueHeader: LocalizedStringKey = showsDuration ? "Time" : "Pct."
        return HStack(spacing: 10) {
            Text("Zone")
                .fixedSize()
            Spacer(minLength: 8)
            Text(valueHeader)
                .frame(width: valueWidth, alignment: .trailing)
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
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundColor(.primary)
                .frame(width: 24, alignment: .leading)

            bar(for: zone)

            Text(showsDuration
                ? BodyValueFormat.stopwatchDurationText(for: zone.duration)
                : "\(Int((zone.fraction * 100).rounded()))%")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: valueWidth, alignment: .trailing)

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

/// Pace/Speed and its per-km/mi splits in one card, the way the Heart Rate card
/// carries the zone breakdown under its chart. Either half can be absent: a workout
/// can have splits but too few buckets for the plot, or the reverse.
private struct BodyWorkoutPaceCard: View {
    let presentation: WorkoutBucketedSeriesPresentation?
    let splits: WorkoutSplitsPresentation?
    var floatingCallout: BodyChartFloatingCalloutState?

    /// The splits' own header names the column "Pace"/"Speed", so it titles the card
    /// when the plot is missing.
    private var title: String {
        presentation?.title ?? splits?.valueHeaderText ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            if let presentation {
                HStack(alignment: .top, spacing: 12) {
                    bodyWorkoutSeriesStatBlock(
                        value: presentation.averageText,
                        unit: presentation.unitText,
                        caption: presentation.averageCaption
                    )
                    bodyWorkoutSeriesStatBlock(
                        value: presentation.extremeText,
                        unit: presentation.unitText,
                        caption: presentation.extremeCaption
                    )
                }

                BodyWorkoutBucketedSeriesPlot(
                    presentation: presentation,
                    calloutEyebrow: presentation.title.uppercased(),
                    floatingCallout: floatingCallout
                )
                .frame(height: 210)
            }

            if let splits {
                BodyWorkoutSplitsSection(presentation: splits)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .bodyCardBackground(cornerRadius: 30, translucent: true)
        // A container rather than one flattened element: the summary still names the
        // card, while the plot inside stays reachable as its own adjustable element.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation?.accessibilitySummary ?? title)
    }
}

private struct BodyWorkoutSplitsSection: View {
    let presentation: WorkoutSplitsPresentation

    /// Tapping the splits swaps the pace bars for a step-cadence column.
    @State private var showsCadenceColumn = false

    /// Fastest-split highlight, matching the BPM readout on the Heart Rate card.
    private static let fastestColor = BodyWorkoutChartPalette.referenceLineColor

    /// Slowest-split highlight, matching Zone 5 on the heart-rate zone breakdown.
    private static let slowestColor = Color(red: 1.0, green: 0.27, blue: 0.31)

    // Column geometry mirrors the heart-rate zone breakdown so the two cards align.
    private let indexWidth: CGFloat = 24
    private let valueWidth: CGFloat = 72
    private let hrWidth: CGFloat = 84
    private let cadenceWidth: CGFloat = 76
    private let barHeight: CGFloat = 12

    var body: some View {
        VStack(spacing: 11) {
            headerRow
            ForEach(presentation.rows) { row in
                splitRow(row)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                showsCadenceColumn.toggle()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text(presentation.unitHeaderText)
                .fixedSize()
            Spacer(minLength: 8)
            Text(presentation.valueHeaderText)
                .frame(width: valueWidth, alignment: .trailing)
            Text(presentation.heartRateHeaderText)
                .frame(width: hrWidth, alignment: .trailing)
            if showsCadenceColumn {
                Text(presentation.cadenceHeaderText)
                    .minimumScaleFactor(0.7)
                    .frame(width: cadenceWidth, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .foregroundColor(.secondary)
    }

    private func splitRow(_ row: WorkoutSplitsPresentation.Row) -> some View {
        let color = row.isFastest
            ? Self.fastestColor
            : (row.isSlowest ? Self.slowestColor : Color.primary)
        return HStack(spacing: 10) {
            Text(row.indexText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(color)
                .frame(width: indexWidth, alignment: .leading)

            bar(for: row)

            Text(row.valueText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(color)
                .frame(width: valueWidth, alignment: .trailing)

            Text(verbatim: row.heartRateText ?? "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundColor(row.heartRateText == nil ? .secondary : color)
                .frame(width: hrWidth, alignment: .trailing)

            if showsCadenceColumn {
                Text(verbatim: row.cadenceText ?? "—")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundColor(row.cadenceText == nil ? .secondary : color)
                    .frame(width: cadenceWidth, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private func bar(for row: WorkoutSplitsPresentation.Row) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                Capsule(style: .continuous)
                    .fill(row.isFastest
                        ? Self.fastestColor
                        : (row.isSlowest ? Self.slowestColor : Color.secondary))
                    // Floor the width at the bar height so the shortest (fastest) split
                    // reads as a circle rather than a stub.
                    .frame(width: max(geometry.size.width * row.barFraction, barHeight))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
    }
}

/// Resolves a detail chart's y-axis label, stepping the font down when the text would
/// overflow the 44 pt gutter it is centred in — `1,400 ft`, `7:30` and zh-Hans digits
/// all run wider than the plain numbers the 14 pt size is sized for.
private func bodyWorkoutChartAxisLabel(
    _ label: String,
    in context: GraphicsContext
) -> GraphicsContext.ResolvedText {
    func resolve(_ size: CGFloat) -> GraphicsContext.ResolvedText {
        context.resolve(
            Text(label)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        )
    }
    func fits(_ resolved: GraphicsContext.ResolvedText) -> Bool {
        resolved.measure(in: CGSize(width: 200, height: 40)).width <= 40
    }

    let base = resolve(14)
    if fits(base) {
        return base
    }
    let medium = resolve(12)
    if fits(medium) {
        return medium
    }
    return resolve(11)
}

/// A Catmull-Rom-ish curve through `points` — the smoothing both profile lines (heart
/// rate and elevation) draw, so neither reads as a polyline of straight segments.
private func bodyWorkoutSmoothedPath(through points: [CGPoint]) -> Path {
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

/// The colour language every workout detail chart shares: one low-to-high ramp
/// (teal → blue → yellow → orange → red) plus the blue the Splits card highlights
/// its fastest split with.
private enum BodyWorkoutChartPalette {
    static let referenceLineColor = Color(red: 0.20, green: 0.62, blue: 1.0)

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

/// The plot every bucketed workout detail chart draws — pace/speed, cadence, stride
/// length, ground contact time and vertical oscillation all hand it
/// a `WorkoutBucketedSeriesPresentation` and get the same grid, ramp bars and
/// `HH:mm:ss` marks. Holding on it scrubs: the touched bucket gets a rule line and a
/// callout published to the sheet's floating layer.
private struct BodyWorkoutBucketedSeriesPlot: View {
    let presentation: WorkoutBucketedSeriesPresentation
    /// The callout's small-caps header — the card's own title, uppercased.
    let calloutEyebrow: String
    /// Where a scrub publishes its callout; the sheet's overlay draws it above the
    /// page chrome. Nil in contexts with no such layer (previews, renders).
    var floatingCallout: BodyChartFloatingCalloutState?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The scrubbed bar's centre x in plot coordinates, or nil when nothing is held.
    @State private var scrubX: CGFloat?
    /// Which bar that x snapped to.
    @State private var scrubbedBarID: Int?
    /// VoiceOver's own cursor through the bars, stepped by the adjustable action.
    @State private var accessibilityBarIndex = 0

    private static let yAxisLabelInset: CGFloat = 44
    private static let xAxisLabelOffset: CGFloat = 18
    private static let timeMarkLabelHorizontalInset: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let plotRect = Self.plotRect(in: geometry.size)

            Canvas { context, _ in
                drawGrid(in: plotRect, context: &context)
                drawBars(in: plotRect, context: &context)
                drawTimeMarks(in: plotRect, context: &context)
                drawSelection(in: plotRect, context: &context)
            }
            .contentShape(Rectangle())
            .gesture(
                BodyChartScrubGesture(isEnabled: !presentation.bars.isEmpty) { location in
                    scrub(to: location, plotRect: plotRect, plotFrame: geometry.frame(in: .global))
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            guard !presentation.bars.isEmpty else { return }
            switch direction {
            case .increment:
                accessibilityBarIndex = min(accessibilityBarIndex + 1, presentation.bars.count - 1)
            case .decrement:
                accessibilityBarIndex = max(accessibilityBarIndex - 1, 0)
            @unknown default:
                break
            }
        }
        .onDisappear {
            clearScrub()
        }
    }

    private static func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: 0,
            y: 6,
            width: max(1, size.width - Self.yAxisLabelInset),
            height: max(1, size.height - 34)
        )
    }

    // MARK: - Drawing

    private func drawGrid(in plotRect: CGRect, context: inout GraphicsContext) {
        var grid = Path()
        for fraction in presentation.yAxisFractions {
            let y = self.y(for: fraction, in: plotRect)
            grid.move(to: CGPoint(x: plotRect.minX, y: y))
            grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        context.stroke(
            grid,
            with: .color(Color.secondary.opacity(0.26)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )

        for (index, label) in presentation.yAxisLabels.enumerated() where index < presentation.yAxisFractions.count {
            context.draw(
                bodyWorkoutChartAxisLabel(label, in: context),
                at: CGPoint(x: plotRect.maxX + 22, y: y(for: presentation.yAxisFractions[index], in: plotRect))
            )
        }
    }

    private func drawBars(in plotRect: CGRect, context: inout GraphicsContext) {
        for bar in presentation.bars {
            let leading = plotRect.minX + plotRect.width * CGFloat(bar.xStart) + 1
            let trailing = plotRect.minX + plotRect.width * CGFloat(bar.xEnd) - 1
            let width = max(2, trailing - leading)
            let lowY = y(for: bar.lowFraction, in: plotRect)
            // The bucket's own place in the axis range picks its colour off the shared
            // heart-rate ramp, so a card's highs and lows read the same way everywhere.
            let color = BodyWorkoutChartPalette.color(forFraction: bar.valueFraction)

            context.fill(
                Path(
                    roundedRect: CGRect(x: leading, y: lowY, width: width, height: plotRect.maxY - lowY),
                    cornerRadius: min(2, width / 2)
                ),
                with: .color(color.opacity(0.10))
            )

            // Ranges thinner than the capsule's minimum height are centred on the
            // bucket's average so a flat (computed) bar still reads as a mark.
            let highY = y(for: bar.highFraction, in: plotRect)
            var capsule = CGRect(x: leading, y: highY, width: width, height: lowY - highY)
            if capsule.height < 6 {
                let center = y(for: bar.valueFraction, in: plotRect)
                capsule = CGRect(x: leading, y: center - 3, width: width, height: 6)
            }
            context.fill(
                Path(roundedRect: capsule, cornerRadius: width / 2),
                with: .color(color)
            )
        }
    }

    private func drawTimeMarks(in plotRect: CGRect, context: inout GraphicsContext) {
        let lowerBound = plotRect.minX + Self.timeMarkLabelHorizontalInset
        let upperBound = max(lowerBound, plotRect.maxX - Self.timeMarkLabelHorizontalInset)
        for mark in presentation.timeMarks {
            let rawX = plotRect.minX + plotRect.width * CGFloat(mark.fraction)
            context.draw(
                context.resolve(
                    Text(mark.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                ),
                at: CGPoint(x: min(max(rawX, lowerBound), upperBound), y: plotRect.maxY + Self.xAxisLabelOffset)
            )
        }
    }

    /// The held bucket's rule line — drawn last so it sits over the bars. The values
    /// themselves ride in the floating callout, so the line is the only mark.
    private func drawSelection(in plotRect: CGRect, context: inout GraphicsContext) {
        guard let scrubX, scrubbedBar != nil else { return }

        var rule = Path()
        rule.move(to: CGPoint(x: scrubX, y: plotRect.minY))
        rule.addLine(to: CGPoint(x: scrubX, y: plotRect.maxY))
        context.stroke(rule, with: .color(Color.secondary.opacity(0.48)), lineWidth: 1.4)
    }

    private func y(for fraction: Double, in plotRect: CGRect) -> CGFloat {
        plotRect.maxY - plotRect.height * CGFloat(fraction)
    }

    // MARK: - Scrubbing

    /// The bar the current `scrubX` snapped to. Looked up by id rather than stored
    /// whole, so a re-published presentation can't leave a stale bar on screen.
    private var scrubbedBar: WorkoutBucketedSeriesPresentation.Bar? {
        guard let scrubbedBarID else { return nil }
        return presentation.bars.first { $0.id == scrubbedBarID }
    }

    private func centerX(of bar: WorkoutBucketedSeriesPresentation.Bar, width: CGFloat) -> CGFloat {
        width * CGFloat((bar.xStart + bar.xEnd) / 2)
    }

    private func scrub(to location: CGPoint?, plotRect: CGRect, plotFrame: CGRect) {
        guard let location, let bar = bar(atX: location.x, in: plotRect) else {
            clearScrub()
            return
        }

        let centreX = plotRect.minX + centerX(of: bar, width: plotRect.width)
        let callout = BodyChartFloatingCallout(
            anchor: CGPoint(x: plotFrame.minX + centreX, y: plotFrame.minY + plotRect.minY),
            content: AnyView(calloutContent(for: bar)),
            // The topmost cards sit under the Back/Share controls, so a callout that
            // can't fit above the plot flips below it instead of clamping over them.
            placement: .aboveOrBelow(anchorBottom: plotFrame.minY + plotRect.maxY)
        )

        if scrubX == nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                scrubX = centreX
                scrubbedBarID = bar.id
                floatingCallout?.callout = callout
            }
        } else {
            scrubX = centreX
            scrubbedBarID = bar.id
            floatingCallout?.callout = callout
        }
    }

    private func clearScrub() {
        guard scrubX != nil || floatingCallout?.callout != nil else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            scrubX = nil
            scrubbedBarID = nil
            floatingCallout?.callout = nil
        }
    }

    /// The bucket under the finger, or the nearest one when the touch lands in a gap
    /// (bars are inset by a point on each side) or outside the plot entirely.
    private func bar(atX x: CGFloat, in plotRect: CGRect) -> WorkoutBucketedSeriesPresentation.Bar? {
        guard plotRect.width > 0, !presentation.bars.isEmpty else { return nil }
        let fraction = Double((x - plotRect.minX) / plotRect.width)
        if let hit = presentation.bars.first(where: { fraction >= $0.xStart && fraction <= $0.xEnd }) {
            return hit
        }
        return presentation.bars.min {
            abs(($0.xStart + $0.xEnd) / 2 - fraction) < abs(($1.xStart + $1.xEnd) / 2 - fraction)
        }
    }

    private func calloutContent(for bar: WorkoutBucketedSeriesPresentation.Bar) -> some View {
        let color = BodyWorkoutChartPalette.color(forFraction: bar.valueFraction)
        let values: [BodyChartSelectionValue]
        if bar.lowText == bar.highText {
            values = [
                BodyChartSelectionValue(
                    title: nil,
                    value: "\(bar.valueText) \(presentation.unitText)",
                    color: color
                )
            ]
        } else {
            values = [
                BodyChartSelectionValue(
                    title: String(localized: "detail.avgPrefix", defaultValue: "Avg"),
                    value: "\(bar.valueText) \(presentation.unitText)",
                    color: color
                ),
                BodyChartSelectionValue(
                    title: String(localized: "chart.legendRange", defaultValue: "Range"),
                    value: "\(bar.lowText)–\(bar.highText)",
                    color: color.opacity(0.55)
                )
            ]
        }

        return BodyChartSelectionAnnotation(
            eyebrow: calloutEyebrow,
            values: values,
            date: Date(),
            dateText: presentation.elapsedText(for: bar)
        )
        // Touch-only peek: the plot's own adjustable value reads the same numbers.
        .accessibilityHidden(true)
    }

    // MARK: - Accessibility

    private var accessibilityValueText: String {
        guard presentation.bars.indices.contains(accessibilityBarIndex) else { return "" }
        let bar = presentation.bars[accessibilityBarIndex]
        let base = "\(presentation.elapsedText(for: bar)), \(bar.valueText) \(presentation.unitText)"
        guard bar.lowText != bar.highText else { return base }
        return "\(base), \(bar.lowText)–\(bar.highText)"
    }
}

/// One card for every bucketed workout series — pace/speed, cadence, stride length,
/// ground contact time, vertical oscillation. The presentation carries the
/// strings, axis and bars, so all of them share `BodyWorkoutBucketedSeriesPlot`.
private struct BodyWorkoutBucketedSeriesCard: View {
    let presentation: WorkoutBucketedSeriesPresentation
    var floatingCallout: BodyChartFloatingCalloutState?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(presentation.title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            HStack(alignment: .top, spacing: 12) {
                bodyWorkoutSeriesStatBlock(
                    value: presentation.averageText,
                    unit: presentation.unitText,
                    caption: presentation.averageCaption
                )
                bodyWorkoutSeriesStatBlock(
                    value: presentation.extremeText,
                    unit: presentation.unitText,
                    caption: presentation.extremeCaption
                )
            }

            BodyWorkoutBucketedSeriesPlot(
                presentation: presentation,
                calloutEyebrow: presentation.title.uppercased(),
                floatingCallout: floatingCallout
            )
            .frame(height: 210)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .bodyCardBackground(cornerRadius: 30, translucent: true)
        // A container rather than one flattened element: the summary still names the
        // card, while the plot inside stays reachable as its own adjustable element.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
    }
}

/// The Avg/extreme readout every bucketed series card puts above its plot — shared so
/// the merged Pace card and the plain bar cards keep identical headers.
private func bodyWorkoutSeriesStatBlock(value: String, unit: String, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(unit)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        Text(caption)
            .font(.system(size: 15))
            .foregroundColor(.secondary)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .frame(maxWidth: .infinity, alignment: .leading)
}

private struct BodyWorkoutHeartRateChartCard: View {
    let samples: [WorkoutHeartRateSample]
    /// Anchors the zone bands (% of this value); nil hides the zone breakdown.
    var maxHeartRate: Double?
    var floatingCallout: BodyChartFloatingCalloutState?

    /// Sorts and derives the chart's axis bounds from `samples` only when the sample
    /// set actually changes — not on every body pass (e.g. when `maxHeartRate` resolves
    /// after the chart first renders). The derivation sorts the full HR series, so this
    /// keeps a long workout's chart from re-sorting on unrelated re-renders.
    @State private var metricsCache = HeartRateMetricsCache()

    var body: some View {
        let metrics = metricsCache.metrics(for: samples)
        let zones = maxHeartRate.flatMap {
            WorkoutHeartRateZones.zones(samples: samples, maxHeartRate: $0)
        }

        return VStack(alignment: .leading, spacing: 14) {
            header(metrics: metrics)
            chartView(metrics: metrics)
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
                    Text("bpm")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func chartView(metrics: BodyWorkoutHeartRateChartMetrics?) -> some View {
        if let metrics {
            BodyWorkoutHeartRateChart(metrics: metrics, floatingCallout: floatingCallout)
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

/// Memoizes the HR chart's derived metrics so the O(n log n) sample sort runs once per
/// distinct sample set rather than on every card body pass. Held via `@State` in the
/// card, so it persists across the view struct's recreations. Samples are downsampled
/// (≤96 points), so the equality check is cheap.
private final class HeartRateMetricsCache {
    private var cachedSamples: [WorkoutHeartRateSample]?
    private var cachedMetrics: BodyWorkoutHeartRateChartMetrics?

    func metrics(for samples: [WorkoutHeartRateSample]) -> BodyWorkoutHeartRateChartMetrics? {
        if let cachedSamples, cachedSamples == samples {
            return cachedMetrics
        }
        let metrics = samples.isEmpty ? nil : BodyWorkoutHeartRateChartMetrics(samples: samples)
        cachedSamples = samples
        cachedMetrics = metrics
        return metrics
    }
}

/// The heart-rate profile: every sample as a faint scatter dot under a smoothed line
/// coloured by the shared low-to-high ramp, bracketed by the session's average (solid)
/// and its max/min (dashed) reference lines. Holding on it scrubs: the nearest smoothed
/// point gets a rule line and a callout published to the sheet's floating layer.
private struct BodyWorkoutHeartRateChart: View {
    let metrics: BodyWorkoutHeartRateChartMetrics
    /// Where a scrub publishes its callout; the sheet's overlay draws it above the
    /// page chrome. Nil in contexts with no such layer (previews, renders).
    var floatingCallout: BodyChartFloatingCalloutState?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The scrubbed point's x in plot coordinates, or nil when nothing is held.
    @State private var scrubX: CGFloat?
    /// Which smoothed point that x snapped to.
    @State private var scrubbedPointIndex: Int?
    /// VoiceOver's own cursor through the smoothed points.
    @State private var accessibilityPointIndex = 0

    private static let timeMarkLabelHorizontalInset: CGFloat = 24
    private static let yAxisLabelInset: CGFloat = 44
    private static let xAxisLabelOffset: CGFloat = 18

    var body: some View {
        // Bucketing the samples is O(n); doing it once per body pass keeps the drawing
        // and the scrub lookup reading the same points.
        let series = metrics.smoothedSeries

        return GeometryReader { geometry in
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
                    drawSmoothedLine(series, in: plotRect, context: &context)
                    drawSelection(series, in: plotRect, context: &context)
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
            .contentShape(Rectangle())
            .gesture(
                BodyChartScrubGesture(isEnabled: !series.isEmpty) { location in
                    scrub(
                        to: location,
                        series: series,
                        plotRect: plotRect,
                        plotFrame: geometry.frame(in: .global)
                    )
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart Rate"))
        .accessibilityValue(accessibilityValueText(series: series))
        .accessibilityAdjustableAction { direction in
            guard !series.isEmpty else { return }
            switch direction {
            case .increment:
                accessibilityPointIndex = min(accessibilityPointIndex + 1, series.count - 1)
            case .decrement:
                accessibilityPointIndex = max(accessibilityPointIndex - 1, 0)
            @unknown default:
                break
            }
        }
        .onDisappear {
            clearScrub()
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
            with: .color(BodyWorkoutChartPalette.referenceLineColor.opacity(0.85)),
            lineWidth: 1
        )

        // Dashed session max and min lines bracketing the solid average line.
        var extremesLines = Path()
        for value in metrics.extremaReferenceValues {
            let extremeY = plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: value))
            extremesLines.move(to: CGPoint(x: plotRect.minX, y: extremeY))
            extremesLines.addLine(to: CGPoint(x: plotRect.maxX, y: extremeY))
        }
        context.stroke(
            extremesLines,
            with: .color(BodyWorkoutChartPalette.referenceLineColor.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
    }

    private func drawScatterDots(in plotRect: CGRect, context: inout GraphicsContext) {
        let dotRadius: CGFloat = 1.8
        for sample in metrics.samples {
            let x = plotRect.minX + plotRect.width * CGFloat(metrics.xFraction(for: sample))
            let yFraction = metrics.yFraction(for: sample)
            let y = plotRect.minY + plotRect.height * CGFloat(yFraction)
            let color = BodyWorkoutChartPalette.color(forFraction: 1 - yFraction)
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

    private func drawSmoothedLine(
        _ series: [BodyWorkoutHeartRateChartMetrics.SmoothedPoint],
        in plotRect: CGRect,
        context: inout GraphicsContext
    ) {
        guard series.count >= 2 else {
            return
        }

        let points = series.map { point(for: $0, in: plotRect) }
        let path = bodyWorkoutSmoothedPath(through: points)

        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: BodyWorkoutChartPalette.gradientStops),
            startPoint: CGPoint(x: plotRect.midX, y: plotRect.maxY),
            endPoint: CGPoint(x: plotRect.midX, y: plotRect.minY)
        )

        context.stroke(
            path,
            with: shading,
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    /// The held point's rule line — drawn last so it sits over the line. The value
    /// itself rides in the floating callout, so the rule is the only mark.
    private func drawSelection(
        _ series: [BodyWorkoutHeartRateChartMetrics.SmoothedPoint],
        in plotRect: CGRect,
        context: inout GraphicsContext
    ) {
        guard let scrubX, let index = scrubbedPointIndex, series.indices.contains(index) else { return }

        var rule = Path()
        rule.move(to: CGPoint(x: scrubX, y: plotRect.minY))
        rule.addLine(to: CGPoint(x: scrubX, y: plotRect.maxY))
        context.stroke(rule, with: .color(Color.secondary.opacity(0.48)), lineWidth: 1.4)
    }

    private func point(
        for smoothed: BodyWorkoutHeartRateChartMetrics.SmoothedPoint,
        in plotRect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: plotRect.minX + plotRect.width * CGFloat(metrics.xFraction(forDate: smoothed.date)),
            y: plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: smoothed.value))
        )
    }

    private func color(for smoothed: BodyWorkoutHeartRateChartMetrics.SmoothedPoint) -> Color {
        BodyWorkoutChartPalette.color(forFraction: 1 - metrics.yFraction(forValue: smoothed.value))
    }

    @ViewBuilder
    private func yAxisLabels(in plotRect: CGRect) -> some View {
        Text("\(metrics.averageLabel)")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(BodyWorkoutChartPalette.referenceLineColor)
            .position(
                x: plotRect.maxX + 22,
                y: plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: metrics.averageValue))
            )

        // Values for the dashed session max/min lines, mirroring the average label
        // but dimmed to match their line weight.
        ForEach(metrics.extremaReferenceValues, id: \.self) { value in
            Text("\(Int(value.rounded()))")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(BodyWorkoutChartPalette.referenceLineColor.opacity(0.55))
                .position(
                    x: plotRect.maxX + 22,
                    y: plotRect.minY + plotRect.height * CGFloat(metrics.yFraction(forValue: value))
                )
        }
    }

    private func timeMarkLabelX(for mark: BodyWorkoutHeartRateTimeMark, in plotRect: CGRect) -> CGFloat {
        let rawX = plotRect.minX + plotRect.width * CGFloat(mark.fraction)
        let lowerBound = plotRect.minX + Self.timeMarkLabelHorizontalInset
        let upperBound = max(lowerBound, plotRect.maxX - Self.timeMarkLabelHorizontalInset)

        return min(max(rawX, lowerBound), upperBound)
    }

    // MARK: - Scrubbing

    private func scrub(
        to location: CGPoint?,
        series: [BodyWorkoutHeartRateChartMetrics.SmoothedPoint],
        plotRect: CGRect,
        plotFrame: CGRect
    ) {
        guard let location, let index = nearestPointIndex(toX: location.x, series: series, in: plotRect) else {
            clearScrub()
            return
        }

        let pointX = point(for: series[index], in: plotRect).x
        let callout = BodyChartFloatingCallout(
            anchor: CGPoint(x: plotFrame.minX + pointX, y: plotFrame.minY + plotRect.minY),
            content: AnyView(calloutContent(for: series[index])),
            // The topmost cards sit under the Back/Share controls, so a callout that
            // can't fit above the plot flips below it instead of clamping over them.
            placement: .aboveOrBelow(anchorBottom: plotFrame.minY + plotRect.maxY)
        )

        if scrubX == nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                scrubX = pointX
                scrubbedPointIndex = index
                floatingCallout?.callout = callout
            }
        } else {
            scrubX = pointX
            scrubbedPointIndex = index
            floatingCallout?.callout = callout
        }
    }

    private func clearScrub() {
        guard scrubX != nil || floatingCallout?.callout != nil else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            scrubX = nil
            scrubbedPointIndex = nil
            floatingCallout?.callout = nil
        }
    }

    private func nearestPointIndex(
        toX x: CGFloat,
        series: [BodyWorkoutHeartRateChartMetrics.SmoothedPoint],
        in plotRect: CGRect
    ) -> Int? {
        guard plotRect.width > 0, !series.isEmpty else { return nil }
        let fraction = Double((x - plotRect.minX) / plotRect.width)
        return series.indices.min {
            abs(metrics.xFraction(forDate: series[$0].date) - fraction)
                < abs(metrics.xFraction(forDate: series[$1].date) - fraction)
        }
    }

    private func calloutContent(for smoothed: BodyWorkoutHeartRateChartMetrics.SmoothedPoint) -> some View {
        BodyChartSelectionAnnotation(
            eyebrow: String(localized: "Heart Rate").uppercased(),
            values: [
                BodyChartSelectionValue(
                    title: nil,
                    value: "\(Int(smoothed.value.rounded())) bpm",
                    color: color(for: smoothed)
                )
            ],
            date: smoothed.date,
            // The plot's own axis reads clock time, so the callout does too.
            dateText: smoothed.date.formatted(.dateTime.hour().minute())
        )
        // Touch-only peek: the plot's own adjustable value reads the same numbers.
        .accessibilityHidden(true)
    }

    // MARK: - Accessibility

    private func accessibilityValueText(
        series: [BodyWorkoutHeartRateChartMetrics.SmoothedPoint]
    ) -> String {
        guard series.indices.contains(accessibilityPointIndex) else { return "" }
        let point = series[accessibilityPointIndex]
        return "\(point.date.formatted(.dateTime.hour().minute())), \(Int(point.value.rounded())) bpm"
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

    /// Distinct session max/min values for the dashed reference lines and their
    /// labels. Flat HR makes max == min (and both can equal the average), which
    /// would collide SwiftUI `\.self` IDs and stack labels on top of the average —
    /// so deduplicate by displayed value and drop any that rounds to the average.
    var extremaReferenceValues: [Double] {
        var seenLabels: Set<Int> = [averageLabel]
        var result: [Double] = []
        for value in [dataMaximumValue, dataMinimumValue] where seenLabels.insert(Int(value.rounded())).inserted {
            result.append(value)
        }
        return result
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
        let actualHighest = max(lowestValue, values.max() ?? 165)
        // Pad only the scaling bound so a flat series still yields a nonzero range;
        // the max label and reference line show the real peak, not the pad (otherwise
        // an all-140 bpm workout would report a 141 bpm maximum).
        let highestValue = max(lowestValue + 1, actualHighest)
        let lowerBound = max(0, (floor((lowestValue - 5) / 5) * 5))
        let upperBound = ceil((highestValue + 5) / 5) * 5

        self.dataMinimumValue = lowestValue
        self.dataMaximumValue = actualHighest
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
}

private struct BodyWorkoutHeartRateTimeMark: Identifiable {
    let fraction: Double
    let label: String

    var id: Double {
        fraction
    }
}

/// The Elevation card: the route's smoothed altitude profile drawn in the heart-rate
/// chart's line style, but with no average/extreme reference lines — the terrain has
/// no meaningful "average", so the right-hand gutter carries the axis' own ticks.
private struct BodyWorkoutElevationLineCard: View {
    let presentation: WorkoutElevationLinePresentation
    var floatingCallout: BodyChartFloatingCalloutState?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(presentation.title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            HStack(alignment: .top, spacing: 12) {
                statBlock(value: presentation.ascentText, caption: presentation.ascentCaption)
                statBlock(value: presentation.maxElevationText, caption: presentation.maxCaption)
            }

            BodyWorkoutElevationLinePlot(
                presentation: presentation,
                floatingCallout: floatingCallout
            )
            .frame(height: 210)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .bodyCardBackground(cornerRadius: 30, translucent: true)
        // A container rather than one flattened element: the summary still names the
        // card, while the plot inside stays reachable as its own adjustable element.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
    }

    private func statBlock(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(presentation.unitText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Text(caption)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The elevation profile plot — the heart-rate chart's frame, dashed gridlines and
/// ramped smoothed line, minus its scatter dots and reference lines. Holding on it
/// scrubs the nearest sample.
private struct BodyWorkoutElevationLinePlot: View {
    let presentation: WorkoutElevationLinePresentation
    var floatingCallout: BodyChartFloatingCalloutState?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrubX: CGFloat?
    @State private var scrubbedPointID: Int?
    @State private var accessibilityPointIndex = 0

    /// Matches `BodyWorkoutHeartRateChart` so every detail chart's plot lines up.
    private static let yAxisLabelInset: CGFloat = 44
    private static let xAxisLabelOffset: CGFloat = 18
    private static let timeMarkLabelHorizontalInset: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let plotRect = CGRect(
                x: 0,
                y: 6,
                width: max(1, geometry.size.width - Self.yAxisLabelInset),
                height: max(1, geometry.size.height - 34)
            )

            Canvas { context, _ in
                drawGrid(in: plotRect, context: &context)
                drawProfile(in: plotRect, context: &context)
                drawTimeMarks(in: plotRect, context: &context)
                drawSelection(in: plotRect, context: &context)
            }
            .contentShape(Rectangle())
            .gesture(
                BodyChartScrubGesture(isEnabled: !presentation.points.isEmpty) { location in
                    scrub(to: location, plotRect: plotRect, plotFrame: geometry.frame(in: .global))
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            guard !presentation.points.isEmpty else { return }
            switch direction {
            case .increment:
                accessibilityPointIndex = min(accessibilityPointIndex + 1, presentation.points.count - 1)
            case .decrement:
                accessibilityPointIndex = max(accessibilityPointIndex - 1, 0)
            @unknown default:
                break
            }
        }
        .onDisappear {
            clearScrub()
        }
    }

    // MARK: - Drawing

    private func drawGrid(in plotRect: CGRect, context: inout GraphicsContext) {
        var frameLines = Path()
        frameLines.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
        frameLines.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.minY))
        frameLines.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        frameLines.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.stroke(frameLines, with: .color(Color.secondary.opacity(0.28)), lineWidth: 1)

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
        for fraction in presentation.yAxisFractions {
            let y = self.y(for: fraction, in: plotRect)
            tickGrid.move(to: CGPoint(x: plotRect.minX, y: y))
            tickGrid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        context.stroke(
            tickGrid,
            with: .color(Color.secondary.opacity(0.18)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
        )

        for (index, label) in presentation.yAxisLabels.enumerated()
        where index < presentation.yAxisFractions.count {
            context.draw(
                bodyWorkoutChartAxisLabel(label, in: context),
                at: CGPoint(x: plotRect.maxX + 22, y: y(for: presentation.yAxisFractions[index], in: plotRect))
            )
        }
    }

    private func drawProfile(in plotRect: CGRect, context: inout GraphicsContext) {
        guard presentation.points.count >= 2 else { return }

        let points = presentation.points.map { position(of: $0, in: plotRect) }
        context.stroke(
            bodyWorkoutSmoothedPath(through: points),
            with: .linearGradient(
                Gradient(stops: BodyWorkoutChartPalette.gradientStops),
                startPoint: CGPoint(x: plotRect.midX, y: plotRect.maxY),
                endPoint: CGPoint(x: plotRect.midX, y: plotRect.minY)
            ),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawTimeMarks(in plotRect: CGRect, context: inout GraphicsContext) {
        let lowerBound = plotRect.minX + Self.timeMarkLabelHorizontalInset
        let upperBound = max(lowerBound, plotRect.maxX - Self.timeMarkLabelHorizontalInset)
        for mark in presentation.timeMarks {
            let rawX = plotRect.minX + plotRect.width * CGFloat(mark.fraction)
            context.draw(
                context.resolve(
                    Text(mark.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                ),
                at: CGPoint(x: min(max(rawX, lowerBound), upperBound), y: plotRect.maxY + Self.xAxisLabelOffset)
            )
        }
    }

    /// The held point's rule line only — the value itself rides in the floating callout.
    private func drawSelection(in plotRect: CGRect, context: inout GraphicsContext) {
        guard let scrubX, scrubbedPoint != nil else { return }

        var rule = Path()
        rule.move(to: CGPoint(x: scrubX, y: plotRect.minY))
        rule.addLine(to: CGPoint(x: scrubX, y: plotRect.maxY))
        context.stroke(rule, with: .color(Color.secondary.opacity(0.48)), lineWidth: 1.4)
    }

    private func position(
        of point: WorkoutElevationLinePresentation.Point,
        in plotRect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: plotRect.minX + plotRect.width * CGFloat(point.xFraction),
            y: y(for: point.yFraction, in: plotRect)
        )
    }

    private func color(for point: WorkoutElevationLinePresentation.Point) -> Color {
        BodyWorkoutChartPalette.color(forFraction: point.yFraction)
    }

    private func y(for fraction: Double, in plotRect: CGRect) -> CGFloat {
        plotRect.maxY - plotRect.height * CGFloat(fraction)
    }

    // MARK: - Scrubbing

    /// Looked up by id rather than stored whole, so a re-published presentation can't
    /// leave a stale point on screen.
    private var scrubbedPoint: WorkoutElevationLinePresentation.Point? {
        guard let scrubbedPointID else { return nil }
        return presentation.points.first { $0.id == scrubbedPointID }
    }

    private func scrub(to location: CGPoint?, plotRect: CGRect, plotFrame: CGRect) {
        guard let location, let point = nearestPoint(toX: location.x, in: plotRect) else {
            clearScrub()
            return
        }

        let pointX = position(of: point, in: plotRect).x
        let callout = BodyChartFloatingCallout(
            anchor: CGPoint(x: plotFrame.minX + pointX, y: plotFrame.minY + plotRect.minY),
            content: AnyView(calloutContent(for: point)),
            placement: .aboveOrBelow(anchorBottom: plotFrame.minY + plotRect.maxY)
        )

        if scrubX == nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                scrubX = pointX
                scrubbedPointID = point.id
                floatingCallout?.callout = callout
            }
        } else {
            scrubX = pointX
            scrubbedPointID = point.id
            floatingCallout?.callout = callout
        }
    }

    private func clearScrub() {
        guard scrubX != nil || floatingCallout?.callout != nil else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            scrubX = nil
            scrubbedPointID = nil
            floatingCallout?.callout = nil
        }
    }

    private func nearestPoint(
        toX x: CGFloat,
        in plotRect: CGRect
    ) -> WorkoutElevationLinePresentation.Point? {
        guard plotRect.width > 0, !presentation.points.isEmpty else { return nil }
        let fraction = Double((x - plotRect.minX) / plotRect.width)
        return presentation.points.min {
            abs($0.xFraction - fraction) < abs($1.xFraction - fraction)
        }
    }

    private func calloutContent(for point: WorkoutElevationLinePresentation.Point) -> some View {
        BodyChartSelectionAnnotation(
            eyebrow: presentation.title.uppercased(),
            values: [
                BodyChartSelectionValue(
                    title: nil,
                    value: "\(point.valueText) \(presentation.unitText)",
                    color: color(for: point)
                )
            ],
            date: Date(),
            dateText: point.elapsedText
        )
        // Touch-only peek: the plot's own adjustable value reads the same numbers.
        .accessibilityHidden(true)
    }

    // MARK: - Accessibility

    private var accessibilityValueText: String {
        guard presentation.points.indices.contains(accessibilityPointIndex) else { return "" }
        let point = presentation.points[accessibilityPointIndex]
        return "\(point.elapsedText), \(point.valueText) \(presentation.unitText)"
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
            .bodySheetBackground()
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

extension View {
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
