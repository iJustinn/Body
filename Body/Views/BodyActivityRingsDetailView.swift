//
//  BodyActivityRingsDetailView.swift
//  Body
//

import SwiftUI

private enum BodyActivityRingPalette {
    static let move = Color(red: 1.00, green: 0.12, blue: 0.36)
    static let exercise = Color(red: 0.48, green: 1.00, blue: 0.00)
    static let stand = Color(red: 0.16, green: 0.92, blue: 0.96)
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
    @State private var topVisibleMonthID: String?
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

    private struct ScrollLoadSignals: Equatable {
        var isNearTop: Bool
        var isUnderfilled: Bool
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
        .scrollPosition(id: $topVisibleMonthID, anchor: .top)
        .onScrollGeometryChange(for: ScrollLoadSignals.self) { geometry in
            ScrollLoadSignals(
                isNearTop: geometry.contentOffset.y + geometry.contentInsets.top < olderMonthLoadThreshold,
                isUnderfilled: geometry.contentSize.height - geometry.containerSize.height < olderMonthLoadThreshold
            )
        } action: { _, signals in
            if isNearTop != signals.isNearTop {
                isNearTop = signals.isNearTop
            }
            if isUnderfilled != signals.isUnderfilled {
                isUnderfilled = signals.isUnderfilled
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

        return date.formatted(.dateTime.month(.abbreviated))
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
            return "\(dateText), no activity ring data"
        }

        let completionText = day.summary.isCompleted ? ", completed" : ""
        return "\(dateText)\(completionText), Move \(metricText(day.summary.move)), Exercise \(metricText(day.summary.exercise)), Stand \(metricText(day.summary.stand))"
    }

    private func metricText(_ metric: ActivityRingMetric) -> String {
        guard let value = metric.value, let goal = metric.goal else {
            return "no data"
        }

        return "\(Int(value.rounded())) of \(Int(goal.rounded()))"
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

    private let ringSize: CGFloat = 108
    private let moveColor = BodyActivityRingPalette.move
    private let exerciseColor = BodyActivityRingPalette.exercise
    private let standColor = BodyActivityRingPalette.stand

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity Rings")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

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
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
        .bodyCardBackground(cornerRadius: 28)
    }
}

private struct BodyActivityRingMetricRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let metric: ActivityRingMetric
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
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

                Text(unit)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(metricTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) \(valueText) \(unit)")
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
