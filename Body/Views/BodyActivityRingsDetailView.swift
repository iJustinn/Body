//
//  BodyActivityRingsDetailView.swift
//  Body
//

import SwiftUI
import UIKit

private enum BodyActivityRingPalette {
    static let move = Color(red: 1.00, green: 0.12, blue: 0.36)
    static let exercise = Color(red: 0.48, green: 1.00, blue: 0.00)
    static let stand = Color(red: 0.16, green: 0.92, blue: 0.96)
}

extension Color {
    /// Parses a 6-digit RRGGBB hex string into a Color (nil when malformed).
    init?(bodyHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// RRGGBB hex string for persistence.
    var bodyHexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// The customizable color mix + per-color widths behind the Home hero background.
/// The app-wide custom background: the user's saved color mix when the Background setting
/// is on, otherwise the plain grouped background. Used as-is on Workouts and Settings, which
/// always show it. Home composes the mix directly instead (so it can suppress it while a star
/// metric supplies the hero backdrop).
struct BodyAppBackground: View {
    @AppStorage(BodyAppearancePreference.homeBackgroundEnabledKey) private var enabled = true
    @AppStorage(BodyAppearancePreference.homeBackgroundColorsKey) private var colorsRawValue = ""
    @AppStorage(BodyAppearancePreference.homeBackgroundSeparatorsKey) private var separatorsRawValue = ""
    @Environment(BodyProStore.self) private var proStore: BodyProStore?

    var body: some View {
        if enabled {
            let isPro = proStore?.isPro ?? false
            BodyActivityRingsCard.heroBackground(
                colors: BodyHomeBackground.proGatedColors(from: colorsRawValue, isProUnlocked: isPro),
                separators: BodyHomeBackground.proGatedSeparators(from: separatorsRawValue, isProUnlocked: isPro)
            )
        } else {
            Color(.systemGroupedBackground)
        }
    }
}

/// Defaults to three neighboring blue tones split into uneven thirds; users can
/// override the colors and the dividers between them.
enum BodyHomeBackground {
    static var defaultColors: [Color] {
        [
            Color(red: 0.19, green: 0.71, blue: 1.00),
            Color(red: 0.04, green: 0.52, blue: 1.00),
            Color(red: 0.00, green: 0.34, blue: 0.85)
        ]
    }

    /// Internal divider positions for the default 3-color mix (two gates → three bands).
    static var defaultSeparators: [Double] { [0.33, 0.67] }

    static func colors(from rawValue: String) -> [Color] {
        let parsed = rawValue
            .split(separator: ",")
            .compactMap { Color(bodyHex: String($0)) }
        return parsed.isEmpty ? defaultColors : Array(parsed.prefix(3))
    }

    static func rawValue(from colors: [Color]) -> String {
        colors.prefix(3).map(\.bodyHexString).joined(separator: ",")
    }

    static func separators(from rawValue: String) -> [Double] {
        let parsed = rawValue
            .split(separator: ",")
            .compactMap { Double($0) }
            .filter { $0 > 0 && $0 < 1 }
            .sorted()
        return parsed.isEmpty ? defaultSeparators : parsed
    }

    /// Custom background colors are a Body Pro feature; non-Pro users always render the
    /// app-default mix regardless of any stored customization.
    static func proGatedColors(from rawValue: String, isProUnlocked: Bool) -> [Color] {
        isProUnlocked ? colors(from: rawValue) : defaultColors
    }

    static func proGatedSeparators(from rawValue: String, isProUnlocked: Bool) -> [Double] {
        isProUnlocked ? separators(from: rawValue) : defaultSeparators
    }

    static func rawValue(fromSeparators separators: [Double]) -> String {
        separators.map { String(format: "%.4f", $0) }.joined(separator: ",")
    }

    /// Sorted internal boundaries for `count` colors (count − 1 values in (0,1)),
    /// falling back to the default split when the stored data doesn't match.
    static func normalizedSeparators(_ separators: [Double], count: Int) -> [Double] {
        guard count > 1 else { return [] }
        let needed = count - 1
        let cleaned = separators.filter { $0 > 0 && $0 < 1 }.sorted()
        guard cleaned.count == needed else {
            return Array(defaultSeparators.prefix(needed))
        }
        return cleaned
    }
}

struct BodyHomeBackgroundProfile: Codable, Equatable, Identifiable {
    static let appDefaultID = "app-default"

    let id: String
    let colorsRawValue: String
    let separatorsRawValue: String
    var name: String? = nil

    static var appDefault: BodyHomeBackgroundProfile {
        BodyHomeBackgroundProfile(
            id: appDefaultID,
            colorsRawValue: BodyHomeBackground.rawValue(from: BodyHomeBackground.defaultColors),
            separatorsRawValue: BodyHomeBackground.rawValue(fromSeparators: BodyHomeBackground.defaultSeparators)
        )
    }

    static func custom(name: String, colors: [Color], separators: [Double]) -> BodyHomeBackgroundProfile {
        BodyHomeBackgroundProfile(
            id: UUID().uuidString,
            colorsRawValue: BodyHomeBackground.rawValue(from: colors),
            separatorsRawValue: BodyHomeBackground.rawValue(
                fromSeparators: BodyHomeBackground.normalizedSeparators(separators, count: 3)
            ),
            name: Self.sanitizedName(name)
        )
    }

    var colors: [Color] {
        BodyHomeBackground.colors(from: colorsRawValue)
    }

    var separators: [Double] {
        BodyHomeBackground.normalizedSeparators(BodyHomeBackground.separators(from: separatorsRawValue), count: 3)
    }

    var fingerprint: String {
        Self.fingerprint(colorsRawValue: colorsRawValue, separatorsRawValue: separatorsRawValue)
    }

    var segmentSummary: String {
        let bounds = [0.0] + separators + [1.0]
        return zip(bounds, bounds.dropFirst())
            .map { Int((($1 - $0) * 100).rounded()) }
            .map { "\($0)%" }
            .joined(separator: " / ")
    }

    func displayName(defaultName: String) -> String {
        Self.sanitizedName(name ?? "") ?? defaultName
    }

    func renamed(_ name: String) -> BodyHomeBackgroundProfile {
        BodyHomeBackgroundProfile(
            id: id,
            colorsRawValue: colorsRawValue,
            separatorsRawValue: separatorsRawValue,
            name: Self.sanitizedName(name)
        )
    }

    static func sanitizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fingerprint(colors: [Color], separators: [Double]) -> String {
        fingerprint(
            colorsRawValue: BodyHomeBackground.rawValue(from: colors),
            separatorsRawValue: BodyHomeBackground.rawValue(
                fromSeparators: BodyHomeBackground.normalizedSeparators(separators, count: 3)
            )
        )
    }

    static func fingerprint(colorsRawValue: String, separatorsRawValue: String) -> String {
        let colorsRawValue = BodyHomeBackground.rawValue(from: BodyHomeBackground.colors(from: colorsRawValue))
        let separatorsRawValue = BodyHomeBackground.rawValue(
            fromSeparators: BodyHomeBackground.normalizedSeparators(
                BodyHomeBackground.separators(from: separatorsRawValue),
                count: 3
            )
        )
        return "\(colorsRawValue)|\(separatorsRawValue)"
    }
}

enum BodyHomeBackgroundProfileStore {
    static let maximumProfileCount = 5
    static var maximumCustomProfileCount: Int { maximumProfileCount - 1 }

    static func allProfiles(from rawValue: String) -> [BodyHomeBackgroundProfile] {
        [BodyHomeBackgroundProfile.appDefault] + customProfiles(from: rawValue)
    }

    static func customProfiles(from rawValue: String) -> [BodyHomeBackgroundProfile] {
        guard
            let data = rawValue.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([BodyHomeBackgroundProfile].self, from: data)
        else {
            return []
        }

        return Array(
            decoded
                .filter { $0.id != BodyHomeBackgroundProfile.appDefaultID }
                .prefix(maximumCustomProfileCount)
        )
    }

    static func rawValue(from profiles: [BodyHomeBackgroundProfile]) -> String {
        let profiles = Array(
            profiles
                .filter { $0.id != BodyHomeBackgroundProfile.appDefaultID }
                .prefix(maximumCustomProfileCount)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(profiles),
            let rawValue = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return rawValue
    }
}

enum BodyActivityRingGraphicGeometry {
    static let ringLineWidth: CGFloat = 12.5
    static let fenceLineWidth: CGFloat = 2.5
    static let edgeFenceGap: CGFloat = fenceLineWidth / 2
    static let moveDiameter: CGFloat = 102
    static let exerciseDiameter: CGFloat = 72
    static let standDiameter: CGFloat = 42
    static let moveExerciseFenceDiameter: CGFloat = 87
    static let exerciseStandFenceDiameter: CGFloat = 57
    static let outerFenceDiameter: CGFloat = ringOuterEdge(diameter: moveDiameter) + edgeFenceGap + fenceLineWidth
    static let innerFenceDiameter: CGFloat = ringInnerEdge(diameter: standDiameter) - edgeFenceGap - fenceLineWidth

    static func ringOuterEdge(diameter: CGFloat) -> CGFloat {
        diameter + ringLineWidth
    }

    static func ringInnerEdge(diameter: CGFloat) -> CGFloat {
        diameter - ringLineWidth
    }

    static func fenceOuterEdge(diameter: CGFloat) -> CGFloat {
        diameter + fenceLineWidth
    }

    static func fenceInnerEdge(diameter: CGFloat) -> CGFloat {
        diameter - fenceLineWidth
    }
}

enum BodyActivityRingAnimationProgress {
    static func normalized(_ progress: Double) -> Double {
        guard progress.isFinite else {
            return 0
        }

        return max(progress, 0)
    }
}

enum BodyActivityRingCompletionStarGeometry {
    static let referenceRingSize: CGFloat = 34
    static let referenceFontSize: CGFloat = 9
    static let referenceOffset = CGSize(width: 3, height: -4)
    static let referenceShadowRadius: CGFloat = 1
    static let referenceShadowYOffset: CGFloat = 0.5
    static let foregroundZIndex: Double = 1

    static func scale(for ringSize: CGFloat) -> CGFloat {
        max(ringSize, 0) / referenceRingSize
    }

    static func fontSize(for ringSize: CGFloat) -> CGFloat {
        referenceFontSize * scale(for: ringSize)
    }

    static func offset(for ringSize: CGFloat) -> CGSize {
        let scale = scale(for: ringSize)
        return CGSize(
            width: referenceOffset.width * scale,
            height: referenceOffset.height * scale
        )
    }

    static func shadowRadius(for ringSize: CGFloat) -> CGFloat {
        referenceShadowRadius * scale(for: ringSize)
    }

    static func shadowYOffset(for ringSize: CGFloat) -> CGFloat {
        referenceShadowYOffset * scale(for: ringSize)
    }
}

private struct BodyActivityRingCompletionStar: View {
    let ringSize: CGFloat

    var body: some View {
        let geometry = BodyActivityRingCompletionStarGeometry.self
        let starOffset = geometry.offset(for: ringSize)

        Image(systemName: "star.fill")
            .font(.system(size: geometry.fontSize(for: ringSize), weight: .heavy, design: .rounded))
            .foregroundColor(Color(red: 1.00, green: 0.78, blue: 0.12))
            .shadow(
                color: .black.opacity(0.22),
                radius: geometry.shadowRadius(for: ringSize),
                y: geometry.shadowYOffset(for: ringSize)
            )
            .offset(x: starOffset.width, y: starOffset.height)
            .accessibilityHidden(true)
    }
}

struct BodyActivityRingsDetailView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarMonths: [ActivityRingCalendarMonth] = []
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var isAwayFromToday = false
    @State private var isNearTop = false
    @State private var isUnderfilled = true
    @State private var isLoadingOlderMonths = false
    @State private var hasUserInteracted = false
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var hasPendingCalendarRefresh = false
    /// Hard cap on loads that aren't tied to a fresh touch. Every load
    /// consumes one; a new touch refills (`onScrollPhaseChange`). This keeps
    /// any layout/geometry feedback loop from paging in months unboundedly —
    /// without it, scroll-anchor vs. LazyVStack estimation churn once chained
    /// through years of history in one shot.
    @State private var remainingAutomaticLoads = 4

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let calendar = Calendar.bodyGregorian
    /// Distance from the content top that counts as "near the top" for
    /// paging in older months.
    private let olderMonthLoadThreshold: CGFloat = 300
    /// Distance scrolled up from today (the content bottom) past which the
    /// "Today" toolbar button fades in.
    private let awayFromTodayThreshold: CGFloat = 240

    private struct ScrollLoadSignals: Equatable {
        var isNearTop: Bool
        var isUnderfilled: Bool
        var isAwayFromToday: Bool
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 46) {
                ForEach(displayedCalendarMonths) { month in
                    monthSection(month)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .readableContentColumn()
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        // Keeps the month the user is looking at in place when older months
        // are inserted above it. UX-only: pagination stays bounded by the
        // load budget even if this repositioning misses.
        .scrollPosition($scrollPosition, anchor: .top)
        .onScrollGeometryChange(for: ScrollLoadSignals.self) { geometry in
            ScrollLoadSignals(
                isNearTop: geometry.contentOffset.y + geometry.contentInsets.top < olderMonthLoadThreshold,
                isUnderfilled: geometry.contentSize.height - geometry.containerSize.height < olderMonthLoadThreshold,
                isAwayFromToday: geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y > awayFromTodayThreshold
            )
        } action: { _, signals in
            if isNearTop != signals.isNearTop {
                isNearTop = signals.isNearTop
            }
            if isUnderfilled != signals.isUnderfilled {
                isUnderfilled = signals.isUnderfilled
            }
            if isAwayFromToday != signals.isAwayFromToday {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAwayFromToday = signals.isAwayFromToday
                }
            }
        }
        .onScrollPhaseChange { _, newPhase in
            scrollPhase = newPhase
            if hasPendingCalendarRefresh, newPhase != .decelerating, newPhase != .animating {
                refreshCalendarMonths()
            }

            guard newPhase == .tracking || newPhase == .interacting else {
                return
            }

            hasUserInteracted = true
            remainingAutomaticLoads = max(remainingAutomaticLoads, 3)
            loadOlderMonthsIfNeeded()
        }
        .overlay(alignment: .top) {
            // Outside the scroll content so showing/hiding it can't change
            // the content size or perturb anchoring.
            if isLoadingOlderMonths && workoutStore.hasMoreActivityRingHistory {
                ProgressView()
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(.top, 8)
                    .accessibilityLabel("Loading earlier months")
            }
        }
        .task {
            refreshCalendarMonths()
            loadOlderMonthsIfNeeded()
        }
        .onChange(of: isNearTop) { _, nearTop in
            if nearTop {
                loadOlderMonthsIfNeeded()
            }
        }
        .onChange(of: workoutStore.loadingActivityRingMonthKeys.isEmpty) { _, isIdle in
            // Re-kick when a load that was in flight (possibly started by an
            // earlier instance of this view) finishes — `.onAppear`-style
            // triggers missing this transition was the old stall-at-top bug.
            if isIdle {
                loadOlderMonthsIfNeeded()
            }
        }
        .onChange(of: workoutStore.activityRingHistory) { _, _ in
            refreshCalendarMonths()
        }
        .onChange(of: workoutStore.healthSummary.activityRings) { _, _ in
            guard workoutStore.activityRingHistory.days.isEmpty,
                  workoutStore.activityRingHistory.loadedMonthKeys.isEmpty else {
                return
            }
            refreshCalendarMonths()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            // The cached months bake in "today" (future-day dimming), so they
            // must be rebuilt when the day rolls over while the screen is up.
            refreshCalendarMonths()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshCalendarMonths()
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Activity Rings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isAwayFromToday {
                ToolbarItem(placement: .topBarTrailing) {
                    todayToolbarButton
                }
            }
        }
    }

    private var todayToolbarButton: some View {
        Button {
            withAnimation(.smooth) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        } label: {
            Text("Today")
        }
        .accessibilityLabel("Scroll to today")
    }

    /// Falls back to a synchronous computation for the first frame so the
    /// initial bottom anchor lays out against real content; the cache takes
    /// over once `.task` runs.
    private var displayedCalendarMonths: [ActivityRingCalendarMonth] {
        calendarMonths.isEmpty ? displayHistory.calendarMonths(calendar: calendar) : calendarMonths
    }

    private func refreshCalendarMonths() {
        // Mutating the list mid-flick forces a re-anchor against estimated
        // row heights — the visible "jump" on fast scrolls. Fetch results
        // wait out the deceleration and apply once the scroll settles.
        guard scrollPhase != .decelerating, scrollPhase != .animating else {
            hasPendingCalendarRefresh = true
            return
        }

        hasPendingCalendarRefresh = false
        calendarMonths = displayHistory.calendarMonths(calendar: calendar)
    }

    /// Single pagination funnel. A load runs only near the top of the
    /// content, and only when the user has touched the scroll view (normal
    /// paging) or the content cannot fill the screen yet (initial fill).
    /// Progress chaining re-enters through the same guards, so every path
    /// is bounded by `remainingAutomaticLoads`.
    private func loadOlderMonthsIfNeeded() {
        guard isNearTop,
              !isLoadingOlderMonths,
              hasUserInteracted || isUnderfilled,
              remainingAutomaticLoads > 0,
              workoutStore.hasMoreActivityRingHistory,
              workoutStore.loadingActivityRingMonthKeys.isEmpty
        else {
            return
        }

        remainingAutomaticLoads -= 1
        isLoadingOlderMonths = true
        Task {
            let historyBeforeLoad = workoutStore.activityRingHistory
            await workoutStore.loadPreviousActivityRingMonthIfNeeded()
            isLoadingOlderMonths = false
            // Chain only when the load made progress; errors and end-of-data
            // wait for a fresh scroll instead of retrying in a tight loop.
            if workoutStore.activityRingHistory != historyBeforeLoad {
                loadOlderMonthsIfNeeded()
            }
        }
    }

    private var displayHistory: ActivityRingHistorySnapshot {
        let history = workoutStore.activityRingHistory
        guard history.days.isEmpty, history.loadedMonthKeys.isEmpty else {
            return history
        }

        let currentSummary = workoutStore.healthSummary.activityRings
        guard !currentSummary.isEmpty else {
            return .empty
        }

        return ActivityRingHistorySnapshot(days: [
            ActivityRingDaySummary(date: Date(), summary: currentSummary)
        ])
    }

    private func monthSection(_ month: ActivityRingCalendarMonth) -> some View {
        VStack(spacing: 13) {
            VStack(spacing: 4) {
                Text(monthTitle(for: month))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))

                    Text("x \(month.completedRingCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.secondary)
                .accessibilityLabel("\(month.completedRingCount) completed days")
            }
            .frame(maxWidth: .infinity)

            weekdayHeader

            LazyVGrid(columns: columns, spacing: 13) {
                ForEach(0..<leadingBlankCount(for: month), id: \.self) { _ in
                    Color.clear
                        .frame(height: 48)
                        .accessibilityHidden(true)
                }

                ForEach(month.days) { day in
                    BodyActivityRingCalendarDayCell(day: day)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        let symbols = weekdaySymbols

        return HStack(spacing: 0) {
            ForEach(symbols.indices, id: \.self) { index in
                Text(symbols[index])
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var weekdaySymbols: [String] {
        calendar.bodyRotatedVeryShortWeekdaySymbols()
    }

    private func leadingBlankCount(for month: ActivityRingCalendarMonth) -> Int {
        guard let firstDate = month.days.first?.date else {
            return 0
        }

        return calendar.leadingBlankDayCount(for: firstDate)
    }

    private func monthTitle(for month: ActivityRingCalendarMonth) -> String {
        guard let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else {
            return ""
        }

        return "\(date.formatted(.dateTime.month(.abbreviated))), \(date.formatted(.dateTime.year()))"
    }
}

private struct BodyActivityRingCalendarDayCell: View {
    let day: ActivityRingCalendarDay

    var body: some View {
        VStack(spacing: 5) {
            Text(dayNumberText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(day.isFuture ? Color.secondary.opacity(0.45) : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            ZStack(alignment: .topTrailing) {
                BodyScaledActivityRingGraphic(summary: day.summary, size: 34)
                    .opacity(ringOpacity)

                if showsCompletionStar {
                    BodyActivityRingCompletionStar(ringSize: 34)
                        .zIndex(BodyActivityRingCompletionStarGeometry.foregroundZIndex)
                }
            }
            .frame(width: 38, height: 34)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayNumberText: String {
        "\(Calendar.bodyGregorian.component(.day, from: day.date))"
    }

    private var ringOpacity: Double {
        if day.isFuture {
            return 0.18
        }

        return 1
    }

    private var showsCompletionStar: Bool {
        day.hasData && !day.isFuture && day.summary.isCompleted
    }

    private var accessibilityLabel: String {
        let dateText = day.date.formatted(.dateTime.month(.wide).day())
        guard day.hasData else {
            return String(localized: "\(dateText), no activity ring data")
        }

        let completionText = day.summary.isCompleted ? String(localized: ", completed") : ""
        return String(localized: "\(dateText)\(completionText), Move \(metricText(day.summary.move)), Exercise \(metricText(day.summary.exercise)), Stand \(metricText(day.summary.stand))")
    }

    private func metricText(_ metric: ActivityRingMetric) -> String {
        guard let value = metric.value, let goal = metric.goal else {
            return String(localized: "no data")
        }

        return String(localized: "\(Int(value.rounded())) of \(Int(goal.rounded()))")
    }
}

private struct BodyScaledActivityRingGraphic: View {
    let summary: ActivityRingSummary
    let size: CGFloat

    var body: some View {
        BodyActivityRingGraphic(
            summary: summary,
            moveColor: BodyActivityRingPalette.move,
            exerciseColor: BodyActivityRingPalette.exercise,
            standColor: BodyActivityRingPalette.stand
        )
        .frame(width: 108, height: 108)
        .scaleEffect(size / 108)
        .frame(width: size, height: size)
    }
}

struct BodyActivityRingsCard: View {
    let summary: ActivityRingSummary
    /// `true` renders the card chrome-free for the home-page star hero (the rings +
    /// numbers sit directly on the tinted gradient backdrop).
    var isHero: Bool = false

    private let ringSize: CGFloat = 108
    private var heroRingScale: CGFloat { isHero ? 1.4 : 1.0 }
    private let moveColor = BodyActivityRingPalette.move
    private let exerciseColor = BodyActivityRingPalette.exercise
    private let standColor = BodyActivityRingPalette.stand

    var body: some View {
        let card = HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                if !isHero {
                    Text("Activity Rings")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                ZStack(alignment: .topTrailing) {
                    BodyActivityRingGraphic(
                        summary: summary,
                        moveColor: moveColor,
                        exerciseColor: exerciseColor,
                        standColor: standColor
                    )
                    .frame(width: ringSize, height: ringSize)

                    if summary.isCompleted {
                        BodyActivityRingCompletionStar(ringSize: ringSize)
                            .transition(.opacity)
                            .zIndex(BodyActivityRingCompletionStarGeometry.foregroundZIndex)
                    }
                }
                .frame(width: ringSize, height: ringSize)
                .scaleEffect(heroRingScale)
                .frame(width: ringSize * heroRingScale, height: ringSize * heroRingScale)
                .padding(.leading, 12)
                .animation(.easeInOut(duration: 0.35), value: summary.isCompleted)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                BodyActivityRingMetricRow(
                    title: "Move",
                    metric: summary.move,
                    unit: "KCAL",
                    color: moveColor
                )
                BodyActivityRingMetricRow(
                    title: "Exercise",
                    metric: summary.exercise,
                    unit: "MIN",
                    color: exerciseColor
                )
                BodyActivityRingMetricRow(
                    title: "Stand",
                    metric: summary.stand,
                    unit: "HRS",
                    color: standColor
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(isHero ? 6 : 18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)

        if isHero {
            // No background shape — instead each colored ring/number gets a black layer
            // directly beneath it (stacked shadows that hug the glyph/arc shapes), so the
            // content reads on any backdrop without a visible card.
            card
                .environment(\.colorScheme, .dark)
                .shadow(color: .black, radius: 3)
                .shadow(color: .black, radius: 3)
        } else {
            card.bodyCardBackground(cornerRadius: 28, translucent: true, translucentFillOpacity: 0.09)
        }
    }

    /// Full-bleed home backdrop: the chosen mix colors blended left to right, each
    /// centered in a band whose width is set by `separators` (the draggable dividers),
    /// over the page background, with a top-to-bottom fade so the colors ease into the
    /// plain background lower down. Falls back to the three ring colors / default split.
    static func heroBackground(colors: [Color], separators: [Double] = BodyHomeBackground.defaultSeparators) -> some View {
        let mix = colors.isEmpty ? BodyHomeBackground.defaultColors : Array(colors.prefix(3))
        let bounds = [0.0] + BodyHomeBackground.normalizedSeparators(separators, count: mix.count) + [1.0]

        // Each color sits at the center of its band and blends smoothly into its
        // neighbors; the dividers set the band widths (how much area each color takes).
        let stops = mix.enumerated().map { index, color in
            Gradient.Stop(color: color.opacity(0.3), location: (bounds[index] + bounds[index + 1]) / 2)
        }

        return ZStack {
            Color(.systemGroupedBackground)

            LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: Color(.systemGroupedBackground), location: 0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct BodyActivityRingMetricRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let metric: ActivityRingMetric
    let unit: String
    let color: Color

    private var localizedTitle: String {
        String(localized: String.LocalizationValue(title))
    }

    private var localizedUnit: String {
        String(localized: String.LocalizationValue(unit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(localizedTitle)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                BodyAnimatedMetricValueText(
                    value: valueText,
                    fontSize: 24,
                    color: metricTextColor,
                    minimumScaleFactor: 0.65
                )

                Text(localizedUnit)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(metricTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "\(localizedTitle) \(valueText) \(localizedUnit)"))
        }
    }

    private var valueText: String {
        guard let value = metric.value, let goal = metric.goal else {
            return "--/--"
        }

        return "\(roundedText(value))/\(roundedText(goal))"
    }

    private func roundedText(_ value: Double) -> String {
        BodyValueFormat.numberText(value.rounded(), decimals: 0)
    }

    private var metricTextColor: Color {
        colorScheme == .light ? Color.black : color
    }
}

private struct BodyActivityRingGraphic: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let summary: ActivityRingSummary
    let moveColor: Color
    let exerciseColor: Color
    let standColor: Color

    var body: some View {
        let geometry = BodyActivityRingGraphicGeometry.self
        let fenceColor = Color.black

        ZStack {
            BodyActivityRingFence(diameter: geometry.moveExerciseFenceDiameter, color: fenceColor)
            BodyActivityRingFence(diameter: geometry.exerciseStandFenceDiameter, color: fenceColor)

            BodyActivityRingArc(
                progress: summary.move.completionProgress,
                showsFullStartMarker: summary.move.showsFullStartMarker,
                color: moveColor,
                lineWidth: geometry.ringLineWidth,
                animation: sweepAnimation(ringIndex: 0)
            )
                .frame(width: geometry.moveDiameter, height: geometry.moveDiameter)
            BodyActivityRingArc(
                progress: summary.exercise.completionProgress,
                showsFullStartMarker: summary.exercise.showsFullStartMarker,
                color: exerciseColor,
                lineWidth: geometry.ringLineWidth,
                animation: sweepAnimation(ringIndex: 1)
            )
                .frame(width: geometry.exerciseDiameter, height: geometry.exerciseDiameter)
            BodyActivityRingArc(
                progress: summary.stand.completionProgress,
                showsFullStartMarker: summary.stand.showsFullStartMarker,
                color: standColor,
                lineWidth: geometry.ringLineWidth,
                animation: sweepAnimation(ringIndex: 2)
            )
                .frame(width: geometry.standDiameter, height: geometry.standDiameter)

            BodyActivityRingFence(diameter: geometry.outerFenceDiameter, color: fenceColor)
            BodyActivityRingFence(diameter: geometry.innerFenceDiameter, color: fenceColor)
        }
    }

    private func sweepAnimation(ringIndex: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .smooth(duration: 0.75, extraBounce: 0)
            .delay(Double(ringIndex) * 0.05)
    }
}

private struct BodyActivityRingFence: View {
    let diameter: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .stroke(color, lineWidth: BodyActivityRingGraphicGeometry.fenceLineWidth)
            .frame(width: diameter, height: diameter)
    }
}

private struct BodyActivityRingArc: View {
    @State private var displayedProgress: Double?

    let progress: Double
    let showsFullStartMarker: Bool
    let color: Color
    let lineWidth: CGFloat
    let animation: Animation?

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radius = diameter / 2

            ZStack {
                Circle()
                    .stroke(
                        color.opacity(0.18),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                BodyActivityRingTrimShape(progress: animatedHeadProgress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                if showsFullStartMarker {
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth, height: lineWidth)
                        .modifier(BodyActivityRingHeadPosition(progress: animatedHeadProgress, radius: radius))
                }

                BodyActivityRingHead(color: color)
                    .frame(width: lineWidth, height: lineWidth)
                    .rotationEffect(.degrees(animatedHeadProgress * 360))
                    .modifier(BodyActivityRingHeadPosition(progress: animatedHeadProgress, radius: radius))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            setAnimatedProgress(normalizedProgress, animation: nil)
        }
        .onChange(of: normalizedProgress) { _, nextProgress in
            setAnimatedProgress(nextProgress, animation: animation)
        }
    }

    private var normalizedProgress: Double {
        BodyActivityRingAnimationProgress.normalized(progress)
    }

    private var animatedHeadProgress: Double {
        displayedProgress ?? normalizedProgress
    }

    private func setAnimatedProgress(_ nextProgress: Double, animation: Animation?) {
        if let animation {
            withAnimation(animation) {
                displayedProgress = nextProgress
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedProgress = nextProgress
            }
        }
    }
}

private struct BodyActivityRingTrimShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        var circle = Path()
        circle.addEllipse(in: rect)
        return circle.trimmedPath(from: 0, to: CGFloat(clamped))
    }
}

private struct BodyActivityRingHeadPosition: GeometryEffect {
    var progress: Double
    let radius: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let headOffsetX = CGFloat(sin(progress * 2 * .pi)) * radius
        let headOffsetY = -CGFloat(cos(progress * 2 * .pi)) * radius

        return ProjectionTransform(CGAffineTransform(translationX: headOffsetX, y: headOffsetY))
    }
}

private struct BodyActivityRingHead: View {
    let color: Color

    var body: some View {
        ZStack {
            BodyActivityRingHeadFill()
                .fill(color)

            BodyActivityRingHeadEdge()
                .stroke(
                    Color.black.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
        }
    }
}

private struct BodyActivityRingHeadFill: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct BodyActivityRingHeadEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        return path
    }
}
