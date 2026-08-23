//
//  BodyOnboardingView.swift
//  Body
//

import SwiftUI

/// Seven-page welcome flow. `.firstRun` runs once on a fresh install (gated by
/// `BodyOnboardingGate` in MainTabView) and owns the first Health load
/// plus the initial sleep-goal setup; `.revisit` is the replayable copy
/// reachable from Settings › About › Onboarding, which shows a Close button
/// and skips the Health load the first run already ran. The first run also
/// opens with `BodyIntroAnimationView`, the word field that streams across the
/// welcome page (tap to skip, Reduce Motion drops it).
struct BodyOnboardingView: View {
    enum Mode {
        case firstRun
        case revisit
    }

    /// The intro owns the screen while `.playing`, keeps streaming its last
    /// words while the pages fade up in `.revealing`, and unmounts at
    /// `.finished`.
    enum IntroState {
        case playing
        case revealing
        case finished
    }

    let mode: Mode

    /// Previews and render tests only: freezes the intro and the page reveal at
    /// one instant. `skipsIntro` is kept for the same reason.
    private let introPreviewTime: TimeInterval?
    private let skipsIntro: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @AppStorage(BodyAppearancePreference.onboardingCompletedVersionKey) private var onboardingCompletedVersion = ""
    @AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey) private var sleepDurationGoalMinutes = BodySleepDurationGoal.defaultMinutes
    @AppStorage(BodyAppearancePreference.showWorkoutEffortSuggestionsKey) private var showWorkoutEffortSuggestions = true
    @AppStorage(BodyAppearancePreference.autoApplyWorkoutEffortKey) private var autoApplyWorkoutEffort = false
    @State private var showsWorkoutEffortWriteDenied = false
    /// Retains the opt-in auto-apply pass so switching it off cancels the
    /// in-flight batch (same contract as the Settings sheet).
    @State private var autoApplyTask: Task<Void, Never>?
    @State private var step = 0
    /// Set before every step change so the page slide matches the direction:
    /// Continue brings the next page in from the right, Back from the left.
    @State private var isMovingBack = false
    @State private var isLoadingHealth = false
    @State private var hasAttemptedHealthLoad = false
    /// The Workouts page preview mirrors the tab's own two charts; the sample
    /// switch control flips between them exactly like the real one.
    @State private var showsWorkoutBreakdown = false
    @State private var introState: IntroState

    private static let pageCount = 7
    private static let lastStep = pageCount - 1
    /// The welcome page also owns the Health permission prompt and first load.
    private static let healthStep = 0

    /// Previews and render tests only: `initialStep` opens a specific page, the
    /// two flags open it in a state the user would otherwise reach by tapping
    /// (the Health load in flight, the Workouts preview switched over),
    /// `skipsIntro` opens straight on the pages, and `introPreviewTime` freezes
    /// the intro and the reveal at that many seconds in.
    init(
        mode: Mode,
        initialStep: Int = 0,
        previewsHealthLoad: Bool = false,
        previewsWorkoutBreakdown: Bool = false,
        skipsIntro: Bool = false,
        introPreviewTime: TimeInterval? = nil
    ) {
        self.mode = mode
        self.skipsIntro = skipsIntro
        self.introPreviewTime = introPreviewTime
        _step = State(initialValue: min(max(initialStep, 0), Self.lastStep))
        _isLoadingHealth = State(initialValue: previewsHealthLoad)
        _hasAttemptedHealthLoad = State(initialValue: previewsHealthLoad)
        _showsWorkoutBreakdown = State(initialValue: previewsWorkoutBreakdown)
        _introState = State(initialValue: skipsIntro ? .finished : .playing)
    }

    /// The pages are hidden while the field owns the screen. A frozen preview
    /// reads the reveal off the timeline instead of the live state.
    private var pagesOpacity: Double {
        if let introPreviewTime, !skipsIntro {
            return BodyIntroTimeline.revealProgress(at: introPreviewTime)
        }
        return introState == .playing && !reduceMotion ? 0 : 1
    }

    var body: some View {
        ZStack {
            BodyAppBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                // Navigation is button-driven (no paging TabView) so the
                // welcome page's Continue can start the Health load before it
                // advances; each page's own ScrollView still scrolls vertically.
                ZStack {
                    currentPage
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityElement(children: .contain)
                .accessibilityValue(Text(pageProgressText))
            }
            // The buttons and dots float over the scrolling page (no backdrop of
            // their own); `page` pads its content so nothing hides under them.
            .overlay(alignment: .bottom) {
                VStack(spacing: 14) {
                    bottomBar
                    pageDots
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            // The same capsule the app floats over the tabs during a refresh,
            // in the same top-center spot: the first load stays visible on
            // whichever page the user has moved on to.
            .overlay(alignment: .top) {
                if isLoadingHealth {
                    BodySyncStatusBadgeLabel(icon: .spinner, text: "Loading data...")
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.28), value: isLoadingHealth)
            // Gating sits outside the floating overlays so the Continue button
            // and the loading badge are hidden and untappable too, not just the
            // page behind them.
            .opacity(pagesOpacity)
            .scaleEffect(0.96 + 0.04 * pagesOpacity)
            .allowsHitTesting(introState != .playing)
            .accessibilityHidden(introState == .playing)
            .animation(.easeOut(duration: BodyIntroTimeline.revealDuration), value: introState)
            .readableContentColumn()

            // The word field streams across the background and hands the
            // screen to the welcome page under its tail.
            if introState != .finished && !reduceMotion {
                BodyIntroAnimationView(
                    previewTime: introPreviewTime,
                    onReveal: { introState = .revealing },
                    onFinished: { introState = .finished }
                )
                .ignoresSafeArea()
                // Once the pages are fading up they take the taps; the field
                // only keeps drawing its last words out.
                .allowsHitTesting(introState == .playing)
            }
        }
        .interactiveDismissDisabled(mode == .firstRun)
        .onChange(of: sleepDurationGoalMinutes) { republishCompanionSnapshotsIfFirstRun() }
        .onAppear {
            // `introState` can't read the environment in `init`, and toggling
            // Reduce Motion later must never start the intro.
            if reduceMotion && introState == .playing {
                introState = .finished
            }
        }
    }

    @ViewBuilder
    private var currentPage: some View {
        switch step {
        case Self.healthStep:
            welcomePage
        case 1:
            readinessPage
        case 2:
            sleepPage
        case 3:
            trainingLoadPage
        case 4:
            effortPage
        case 5:
            workoutsPage
        default:
            donePage
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()

            switch mode {
            case .firstRun:
                if showsSkipButton {
                    Button {
                        finish()
                    } label: {
                        Text("onboarding.skip")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    }
                }
            case .revisit:
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .accessibilityLabel(Text("onboarding.close"))
                }
            }
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// Skip is offered on the pages the user can safely leave; the welcome page
    /// owns the permission prompt and the last page already ends the flow.
    private var showsSkipButton: Bool {
        (1..<Self.lastStep).contains(step)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    /// Back takes 30% of the row and Continue the rest; on the first page
    /// Continue spans the full width.
    private var bottomBar: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            HStack(spacing: spacing) {
                if step >= 1 {
                    Button {
                        move(to: step - 1)
                    } label: {
                        Text("onboarding.back")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BodyGlassChip(color: .white, cornerRadius: 16, fillOpacity: 0.7))
                    }
                    .frame(width: (proxy.size.width - spacing) * 0.3)
                }

                primaryButton
            }
        }
        .frame(height: 50)
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            Text(primaryButtonTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                // Same flat glass chip as the workout type bars: translucent
                // fill, thin white rim, no gradient or material.
                .background(BodyGlassChip(color: .blue, cornerRadius: 16, fillOpacity: 0.7))
        }
    }

    /// `LocalizedStringKey` (not `String(localized:)`) so the label follows the
    /// environment locale like every other `Text` on the page.
    /// The Health load reports itself on the page, never on the button, so
    /// Continue stays available while it runs.
    private var primaryButtonTitle: LocalizedStringKey {
        step == Self.lastStep ? "onboarding.getStarted" : "onboarding.continue"
    }

    private var pageProgressText: String {
        String(localized: "onboarding.pageProgress \(step + 1) \(Self.pageCount)")
    }

    // MARK: - Pages

    private var welcomePage: some View {
        page(centersVertically: true) {
            Image(BodyAppIconOption.option(named: UIApplication.shared.alternateIconName).previewAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)

            pageHeader(
                iconName: nil,
                title: "onboarding.welcome.title",
                subtitle: nil
            )

            // Only the first run loads Health data; by the time the replay
            // copy can be opened, permissions and the first refresh are done.
            if mode == .firstRun {
                VStack(spacing: 10) {
                    Text("onboarding.welcome.load")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    // Once the load is underway the permission sentence is
                    // stale, so it crossfades into the nudge to keep going.
                    if hasAttemptedHealthLoad {
                        Text("onboarding.health.continue")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    } else {
                        Text("onboarding.health.body")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: hasAttemptedHealthLoad)
            }

            // Shown on the replay too: the privacy promise is the reason the
            // flow asks for Health access in the first place.
            OnboardingFeatureRow(
                iconName: "lock.fill",
                tintColor: .green,
                title: "onboarding.welcome.privacy",
                subtitle: "onboarding.welcome.privacy.subtitle"
            )
            .padding(.top, 4)

            if mode == .firstRun {

                if hasAttemptedHealthLoad && !isLoadingHealth {
                    // The green check means data actually landed. A load that
                    // completed but brought back nothing (denied permissions,
                    // an empty Health store) clears
                    // `needsInitialHealthDataLoad` yet must still show the
                    // neutral row plus any notice.
                    if !workoutStore.hasHealthDataToShow {
                        healthOutcomeRow(
                            iconName: "info.circle.fill",
                            tintColor: .secondary,
                            message: Text("onboarding.health.finished")
                        )

                        if let notice = workoutStore.healthDataNotice {
                            Text(notice)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        healthOutcomeRow(
                            iconName: "checkmark.circle.fill",
                            tintColor: .green,
                            message: Text("onboarding.health.loaded")
                        )
                    }
                }
            }
        }
    }

    private var readinessPage: some View {
        page {
            pageHeader(
                iconName: nil,
                title: "onboarding.readiness.title",
                subtitle: "onboarding.readiness.subtitle"
            )

            // The Home star hero (colored wave backdrop + score label) over a
            // fabricated summary, cropped to a card.
            ZStack(alignment: .top) {
                BodyReadinessHeroBackdrop(readiness: Self.sampleReadiness)
                BodyReadinessHeroLabel(readiness: Self.sampleReadiness, morningScore: nil)
                    .padding(.horizontal, 20)
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            // The backdrop melts into the flat grouped background, which is a
            // touch lighter than the page gradient, so a hard clip leaves a pale
            // rim around the lower corners. Fading the card out over its last
            // third lets it dissolve into the page instead.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.62),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                OnboardingFeatureRow(
                    iconName: "bolt.heart.fill",
                    tintColor: .pink,
                    title: "onboarding.readiness.signals",
                    subtitle: "onboarding.readiness.signals.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "waveform.path.ecg",
                    tintColor: .teal,
                    title: "onboarding.readiness.patterns",
                    subtitle: "onboarding.readiness.patterns.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "clock.arrow.circlepath",
                    tintColor: .indigo,
                    title: "onboarding.readiness.live",
                    subtitle: "onboarding.readiness.live.subtitle"
                )
            }
        }
    }

    private var trainingLoadPage: some View {
        page {
            pageHeader(
                iconName: nil,
                title: "onboarding.trainingLoad.title",
                subtitle: "onboarding.trainingLoad.subtitle"
            )

            // Exactly the width of one Home grid card (two columns, 16pt
            // gutters, 14pt between), centered on the page.
            BodyHealthMetricCard(metric: Self.sampleTrainingLoadMetric)
                .containerRelativeFrame(.horizontal) { length, _ in (length - 46) / 2 }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                OnboardingFeatureRow(
                    iconName: "arrow.left.arrow.right",
                    tintColor: .orange,
                    title: "onboarding.trainingLoad.ratio",
                    subtitle: "onboarding.trainingLoad.ratio.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "checkmark.circle.fill",
                    tintColor: .green,
                    title: "onboarding.trainingLoad.range",
                    subtitle: "onboarding.trainingLoad.range.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "chart.line.uptrend.xyaxis",
                    tintColor: .red,
                    title: "onboarding.trainingLoad.direction",
                    subtitle: "onboarding.trainingLoad.direction.subtitle"
                )
            }
        }
    }

    private var effortPage: some View {
        page {
            pageHeader(
                iconName: nil,
                title: "onboarding.effort.title",
                subtitle: "onboarding.effort.subtitle"
            )

            sampleEffortCard
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                OnboardingFeatureRow(
                    iconName: "slider.horizontal.3",
                    tintColor: .red,
                    title: "onboarding.effort.rate",
                    subtitle: "onboarding.effort.rate.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "speedometer",
                    tintColor: .purple,
                    title: "onboarding.effort.suggest",
                    subtitle: "onboarding.effort.suggest.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "hand.raised.fill",
                    tintColor: .blue,
                    title: "onboarding.effort.yours",
                    subtitle: "onboarding.effort.yours.subtitle"
                )
            }

            effortSettingsCard
        }
    }

    /// The same two switches as Settings › Workouts › Effort Suggestions,
    /// bound to the same keys; Auto-Apply asks for Health write access at
    /// the moment it's turned on, exactly like the Settings sheet.
    private var effortSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("onboarding.effort.settings")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                BodyEffortSuggestionToggleRow(isEnabled: $showWorkoutEffortSuggestions)

                Divider()
                    .padding(.leading, 76)

                BodyAutoApplyEffortToggleRow(isEnabled: $autoApplyWorkoutEffort)
                    .disabled(!showWorkoutEffortSuggestions)
                    .opacity(showWorkoutEffortSuggestions ? 1 : 0.4)
            }
            // The rows are the Settings components verbatim; a smaller type
            // size keeps them in proportion with the onboarding copy.
            .dynamicTypeSize(.xSmall)
            .bodyCardBackground(cornerRadius: 26, translucent: true)

            Text("onboarding.effort.settingsHint")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .onChange(of: autoApplyWorkoutEffort) {
            guard autoApplyWorkoutEffort else {
                autoApplyTask?.cancel()
                autoApplyTask = nil
                return
            }
            autoApplyTask?.cancel()
            autoApplyTask = Task {
                if await workoutStore.requestWorkoutEffortWriteAuthorization() {
                    await workoutStore.autoApplyPredictedEffortNow()
                } else {
                    autoApplyWorkoutEffort = false
                    showsWorkoutEffortWriteDenied = true
                }
            }
        }
        .alert("Auto-Apply Needs Permission", isPresented: $showsWorkoutEffortWriteDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Auto-Apply needs permission to update Workouts in Apple Health. Allow it in Settings › Health › Data Access & Devices › Body, then switch Auto-Apply back on.")
        }
        .onDisappear {
            autoApplyTask?.cancel()
            autoApplyTask = nil
        }
    }

    /// The workout detail's effort card over a fabricated 7/10 rating: the real
    /// `BodyWorkoutEffortChart` meter and `WorkoutEffortPresentation` wording on
    /// the same card surface, minus the editing controls it can't reach here.
    private var sampleEffortCard: some View {
        let presentation = WorkoutEffortPresentation(score: 7)
        let effortColor = presentation?.intensity.tintColor ?? Color.secondary

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Effort")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                if let presentation {
                    HStack(spacing: 12) {
                        Text(presentation.valueText)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(effortColor)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(effortColor.opacity(0.2)))

                        Text(presentation.descriptor)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(effortColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            BodyWorkoutEffortChart(
                score: presentation?.normalizedScore,
                tintColor: effortColor
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .bodyCardBackground(cornerRadius: 30, translucent: true)
    }

    /// Mirrors `WorkoutCalendarCountMarker.markers(for:)` — star 1, moon 3,
    /// sun 8, flame 13+ — so the legend and the calendar can't drift apart
    /// without a test noticing.
    private var workoutsPage: some View {
        page {
            pageHeader(
                iconName: nil,
                title: "onboarding.calendar.title",
                subtitle: "onboarding.calendar.subtitle"
            )

            // The Workouts tab's own card over a sample month: the calendar
            // that hits every marker tier, and the activity breakdown behind
            // the same switch control the tab uses.
            workoutsPreviewCard
                // Illustration, like every other page's preview: the rows below
                // carry the same information in words.
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                OnboardingFeatureRow(
                    iconName: "chart.bar.yaxis",
                    tintColor: .mint,
                    title: "onboarding.calendar.switch",
                    subtitle: "onboarding.calendar.switch.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "star.fill",
                    tintColor: .yellow,
                    title: "onboarding.calendar.star",
                    subtitle: "onboarding.calendar.star.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "moon.fill",
                    tintColor: .indigo,
                    title: "onboarding.calendar.moon",
                    subtitle: "onboarding.calendar.moon.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "sun.max.fill",
                    tintColor: .orange,
                    title: "onboarding.calendar.sun",
                    subtitle: "onboarding.calendar.sun.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "flame.fill",
                    tintColor: .red,
                    title: "onboarding.calendar.flame",
                    subtitle: "onboarding.calendar.flame.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "square.and.arrow.up.fill",
                    tintColor: .blue,
                    title: "onboarding.calendar.share",
                    subtitle: "onboarding.calendar.share.subtitle"
                )
            }
        }
    }

    /// Live sample of the Workouts tab's chart card: the switch control in the
    /// calendar's last cell (and on the breakdown's last bar) flips between the
    /// two views here just as it does in the tab.
    private var workoutsPreviewCard: some View {
        VStack(spacing: 0) {
            if showsWorkoutBreakdown {
                WorkoutTypeBreakdownView(
                    snapshot: Self.sampleCalendarSnapshot,
                    style: .app,
                    onSwitchChart: toggleWorkoutsPreview
                )
                .padding(18)
            } else {
                WorkoutCalendarView(
                    snapshot: Self.sampleCalendarSnapshot,
                    style: .widgetLarge,
                    fillsAvailableHeight: false,
                    onSwitchChart: toggleWorkoutsPreview
                )
                .padding(14)
            }
        }
        .bodyCardBackground(translucent: true)
    }

    private var sleepPage: some View {
        page {
            pageHeader(
                iconName: nil,
                title: "onboarding.sleep.title",
                subtitle: "onboarding.sleep.subtitle"
            )

            // The real Summary sleep card at its in-app (one grid column) width.
            BodyHealthMetricCard(metric: Self.sampleSleepMetric)
                .containerRelativeFrame(.horizontal) { length, _ in (length - 46) / 2 }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                OnboardingFeatureRow(
                    iconName: "chart.bar.fill",
                    tintColor: Color(red: 0.20, green: 0.72, blue: 1.00),
                    title: "onboarding.sleep.stages",
                    subtitle: "onboarding.sleep.stages.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "clock.fill",
                    tintColor: .indigo,
                    title: "onboarding.sleep.consistency",
                    subtitle: "onboarding.sleep.consistency.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "person.crop.circle",
                    tintColor: .teal,
                    title: "onboarding.sleep.baseline",
                    subtitle: "onboarding.sleep.baseline.subtitle"
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("onboarding.sleep.goal")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    Stepper(
                        value: sleepDurationGoal,
                        in: BodySleepDurationGoal.minimumMinutes...BodySleepDurationGoal.maximumMinutes,
                        step: BodySleepDurationGoal.stepMinutes
                    ) {
                        HStack(spacing: 14) {
                            BodySettingsIconTile(
                                iconName: "bed.double.fill",
                                color: Color(red: 0.20, green: 0.72, blue: 1.00)
                            )

                            Text("Amount")
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer(minLength: 12)

                            Text(BodySleepDurationGoal.displayText(for: sleepDurationGoal.wrappedValue))
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.leading, 14)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                    }
                    .padding(.trailing, 18)
                }
                .dynamicTypeSize(.xSmall)
                .bodyCardBackground(cornerRadius: 26, translucent: true)

                Text("onboarding.sleep.goalHint")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var donePage: some View {
        page {
            pageHeader(
                iconName: "checkmark.seal.fill",
                title: "onboarding.done.title",
                subtitle: nil
            )

            VStack(spacing: 14) {
                OnboardingFeatureRow(
                    iconName: "arrow.clockwise.circle.fill",
                    tintColor: .white,
                    title: "onboarding.done.tip1",
                    subtitle: "onboarding.done.tip1.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "hand.draw.fill",
                    tintColor: .white,
                    title: "onboarding.done.tip2",
                    subtitle: "onboarding.done.tip2.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "arrow.left.arrow.right.circle.fill",
                    tintColor: .white,
                    title: "onboarding.done.sources",
                    subtitle: "onboarding.done.sources.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "slider.horizontal.3",
                    tintColor: .white,
                    title: "onboarding.done.explore",
                    subtitle: "onboarding.done.explore.subtitle"
                )

                OnboardingFeatureRow(
                    iconName: "sparkles",
                    tintColor: .white,
                    title: "onboarding.done.tip3",
                    subtitle: "onboarding.done.tip3.subtitle"
                )
            }
        }
    }

    // MARK: - Page building blocks

    /// Every page scrolls on its own so the top bar, dots, and buttons stay put
    /// at large Dynamic Type sizes.
    /// `centersVertically` floats short content (the welcome page) in the
    /// middle of the page instead of pinning it to the top; the page still
    /// scrolls if it ever outgrows the screen.
    private func page<Content: View>(
        centersVertically: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let content = content()
        return GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                // Room for the floating buttons + dots at the bottom.
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity, minHeight: centersVertically ? proxy.size.height : 0)
            }
        }
    }

    @ViewBuilder
    private func pageHeader(iconName: String?, title: LocalizedStringKey, subtitle: LocalizedStringKey?) -> some View {
        VStack(spacing: 12) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.primary)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func healthOutcomeRow(iconName: String, tintColor: Color, message: Text) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tintColor)
                .accessibilityHidden(true)

            message
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The Summary readiness card's model over a fabricated score and week of
    /// trend points, built the same way `BodyHomeView.readinessMetric` builds the
    /// live one.
    private static let sampleReadiness = ReadinessSummary(
        score: 88,
        status: .high,
        confidence: .high,
        // A sleep component keeps the hero on its normal band explanation
        // instead of the "sleep data isn't in yet" fallback.
        components: [ReadinessComponent(kind: .sleep, score: 80, weight: 1, message: "")],
        drivers: []
    )

    private static let sampleSleepMetric = BodyHealthMetricCard.Model(
        kind: .sleep,
        title: "Sleep",
        value: BodyValueFormat.sleepDurationText(for: 7 * 3_600 + 42 * 60),
        unit: "",
        symbolName: "bed.double.fill",
        symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
        chartPreview: sampleSeries(values: [6.9, 7.4, 6.6, 7.8, 7.1, 8.0, 7.7].map { $0 * 3_600 })
    )

    private static let sampleTrainingLoadMetric = BodyHealthMetricCard.Model(
        kind: .trainingLoad,
        title: "Training Load",
        value: BodyValueFormat.numberText(1.12, decimals: 2),
        unit: "",
        symbolName: "figure.strengthtraining.traditional",
        symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
        chartPreviewStyle: .line,
        chartPreview: sampleSeries(values: [0.86, 0.94, 0.91, 1.04, 0.99, 1.18, 1.12])
    )

    /// One point per day ending today, oldest first — the shape the card's
    /// preview groups by day.
    private static func sampleSeries(values: [Double]) -> HealthTrendSeries {
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        let points = values.enumerated().compactMap { offset, value -> HealthTrendDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: offset - (values.count - 1), to: today) else {
                return nil
            }
            return HealthTrendDataPoint(date: date, value: value)
        }
        return HealthTrendSeries(points: points)
    }

    /// A fixed 31 day month whose 1st falls on a Wednesday (October 2025),
    /// nearly every day active like a busy real month: walks dominate,
    /// strength, cycling, climbing, hiking, and ball sports mix in, counts are
    /// mostly 1 to 4, and a few days reach 8 (sun) or 13 (flame).
    private static let sampleCalendarSnapshot: WorkoutMonthSnapshot = {
        let calendar = Calendar.bodyGregorian
        let month = 10
        let year = 2025
        // day: (type shown on the cell, workouts that day). Missing days stay empty.
        let plan: [Int: (BodyWorkoutType, Int)] = [
            1: (.walking, 1), 2: (.strengthTraining, 2), 3: (.strengthTraining, 1), 4: (.walking, 1),
            5: (.walking, 2), 6: (.climbing, 3), 7: (.walking, 6), 9: (.strengthTraining, 4),
            10: (.strengthTraining, 2), 11: (.walking, 1), 12: (.cycling, 3), 13: (.walking, 1),
            14: (.walking, 2), 15: (.cycling, 4), 16: (.climbing, 8), 17: (.walking, 4),
            18: (.cycling, 1), 19: (.walking, 3), 20: (.walking, 1), 21: (.strengthTraining, 2),
            22: (.strengthTraining, 13), 23: (.walking, 6), 24: (.hiking, 2), 25: (.walking, 2),
            27: (.tennis, 2), 28: (.soccer, 1), 30: (.strengthTraining, 8), 31: (.running, 1)
        ]
        var workouts: [WorkoutSummary] = []
        for (day, entry) in plan {
            for index in 0..<entry.1 {
                guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 6 + index, minute: 0)) else {
                    continue
                }
                workouts.append(WorkoutSummary(type: entry.0, startDate: start, duration: 1_800))
            }
        }
        return WorkoutMonthSnapshot.make(month: month, year: year, workouts: workouts, calendar: calendar)
    }()

    // MARK: - Bindings

    private var sleepDurationGoal: Binding<Int> {
        Binding {
            BodySleepDurationGoal.storedMinutes(from: sleepDurationGoalMinutes)
        } set: { minutes in
            sleepDurationGoalMinutes = BodySleepDurationGoal.storedMinutes(from: minutes)
        }
    }

    // MARK: - Actions

    private func toggleWorkoutsPreview() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showsWorkoutBreakdown.toggle()
        }
    }

    private func primaryAction() {
        if mode == .firstRun && step == Self.healthStep && !hasAttemptedHealthLoad {
            loadHealth()
            return
        }

        if step == Self.lastStep {
            finish()
            return
        }

        move(to: step + 1)
    }

    /// The outgoing page keeps the transition it was last rendered with, so the
    /// direction has to land in a render of its own before the step changes;
    /// flipping both in one update would slide the old page out the wrong way.
    private func move(to newStep: Int) {
        isMovingBack = newStep < step
        DispatchQueue.main.async {
            withAnimation {
                step = newStep
            }
        }
    }

    /// The page slides the way the user is travelling; both ends fade so the
    /// outgoing and incoming pages don't overlap harshly mid-slide.
    private var pageTransition: AnyTransition {
        let incoming: Edge = isMovingBack ? .leading : .trailing
        let outgoing: Edge = isMovingBack ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: incoming).combined(with: .opacity),
            removal: .move(edge: outgoing).combined(with: .opacity)
        )
    }

    /// Mirrors `BodyFirstLaunchLoadOverlay.loadData()`: the authorization sheet
    /// plus the full first refresh. Nothing waits on it. The flow keeps moving
    /// under the loading badge, and the welcome page reports the outcome
    /// whenever the user is looking at it once the refresh settles.
    private func loadHealth() {
        guard !isLoadingHealth else {
            return
        }

        isLoadingHealth = true
        hasAttemptedHealthLoad = true
        Task {
            await workoutStore.requestAuthorizationAndRefresh()
            await workoutStore.awaitRefreshCompletion()
            isLoadingHealth = false
        }
    }

    private func finish() {
        onboardingCompletedVersion = BodyOnboardingGate.currentAppVersion()
        dismiss()
    }

    /// The replayable copy must not spam the widget/watch snapshots when the
    /// user is only re-reading the flow.
    private func republishCompanionSnapshotsIfFirstRun() {
        guard mode == .firstRun else {
            return
        }

        workoutStore.republishCompanionSnapshots()
    }
}

private struct OnboardingFeatureRow: View {
    let iconName: String
    let tintColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BodySettingsIconTile(iconName: iconName, color: tintColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    BodyOnboardingView(mode: .firstRun)
        .environmentObject(HealthKitWorkoutStore())
}
