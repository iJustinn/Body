//
//  ProjectConfigurationTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

final class ProjectConfigurationTests: XCTestCase {
    func testSettingsAboutTabsMatchCoinAboutSet() {
        XCTAssertEqual(
            BodySettingsAboutTab.allCases.map(\.title),
            [
                "How to Use",
                "Privacy",
                "Onboarding",
                "More",
                "Version"
            ]
        )
        XCTAssertEqual(
            BodySettingsAboutTab.allCases.filter(\.opensSheet).map(\.title),
            [
                "More"
            ]
        )
    }

    func testOnboardingIsWiredIntoLaunchAndSettings() throws {
        let selections = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        XCTAssertTrue(selections.contains(#"static let onboardingCompletedVersionKey = "onboardingCompletedVersion""#))
        // Version-gated: nothing recorded (fresh install or pre-release upgrade)
        // and anything below 1.0.0 present onboarding; 1.0.0+ does not.
        XCTAssertTrue(BodyOnboardingGate.shouldPresent(completedVersion: nil))
        XCTAssertTrue(BodyOnboardingGate.shouldPresent(completedVersion: ""))
        XCTAssertTrue(BodyOnboardingGate.shouldPresent(completedVersion: "0.9.12"))
        XCTAssertFalse(BodyOnboardingGate.shouldPresent(completedVersion: "1.0.0"))
        XCTAssertFalse(BodyOnboardingGate.shouldPresent(completedVersion: "1.10.0"))
        XCTAssertEqual(BodyOnboardingGate.currentAppVersion(), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)

        let mainTabView = try text(at: "Body/Views/MainTabView.swift")
        XCTAssertTrue(mainTabView.contains("fullScreenCover"))
        XCTAssertTrue(mainTabView.contains("BodyOnboardingView(mode: .firstRun)"))

        let settingsView = try text(at: "Body/Views/BodySettingsView.swift")
        XCTAssertTrue(settingsView.contains("BodyOnboardingView(mode: .revisit)"))

        XCTAssertNil(BodySettingsAboutTab.onboarding.sheet)
        XCTAssertEqual(BodySettingsAboutTab.onboarding.title, "Onboarding")

        let onboardingView = try text(at: "Body/Views/BodyOnboardingView.swift")
        XCTAssertFalse(onboardingView.lowercased().contains("connected"))
        XCTAssertTrue(onboardingView.contains("interactiveDismissDisabled"))
        // Only the first run loads Health data, it reports progress on the page
        // rather than on the button, and nothing waits on it.
        XCTAssertTrue(onboardingView.contains("if mode == .firstRun && step == Self.healthStep && !hasAttemptedHealthLoad {"))
        XCTAssertTrue(onboardingView.contains("BodySyncStatusBadgeLabel(icon: .spinner, text: \"Loading data...\")"))
        XCTAssertFalse(onboardingView.contains(".disabled(isLoadingHealth)"))
        XCTAssertFalse(onboardingView.contains("interactiveDismissDisabled(mode == .firstRun || isLoadingHealth)"))
        // The Workouts page preview carries the tab's own calendar/breakdown switch.
        XCTAssertEqual(onboardingView.occurrenceCount(of: "onSwitchChart: toggleWorkoutsPreview"), 2)
        XCTAssertTrue(onboardingView.contains("WorkoutTypeBreakdownView("))
        // Calendar first, like the tab itself: only the switch control moves
        // the preview to the bars.
        XCTAssertTrue(onboardingView.contains("@State private var showsWorkoutBreakdown = false"))
        XCTAssertEqual(onboardingView.occurrenceCount(of: "showsWorkoutBreakdown.toggle()"), 1)
        // Reduce Motion is read from the environment so a live toggle can
        // retire the intro without waiting on `init`.
        XCTAssertTrue(onboardingView.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        // The intro field owns the screen until it reveals the pages, frozen
        // at `introPreviewTime` for previews and render tests.
        XCTAssertTrue(onboardingView.contains("BodyIntroAnimationView(\n                    previewTime: introPreviewTime"))
        // The gating modifiers keep the hidden pages truly untappable and
        // hidden from accessibility, not just faded out.
        XCTAssertTrue(onboardingView.contains(".allowsHitTesting(introState != .playing)"))
        XCTAssertTrue(onboardingView.contains(".accessibilityHidden(introState == .playing)"))
        // Previews and render tests can open straight on the pages, skipping
        // the intro entirely.
        // The intro plays on the first run and on the Settings replay alike; only
        // the render hooks skip it.
        XCTAssertTrue(onboardingView.contains("_introState = State(initialValue: skipsIntro ? .finished : .playing)"))

        let introView = try text(at: "Body/Views/BodyIntroAnimationView.swift")
        // One clock drives both the drawn field and the reveal/finish
        // callbacks, so a skip is just a jump on that same clock.
        XCTAssertTrue(introView.contains("TimelineView("))
        XCTAssertTrue(introView.contains(".task(id: skipGeneration)"))
        XCTAssertTrue(introView.contains("\"onboarding.intro.skip\""))
        // A real button carries the skip, not a tap gesture: VoiceOver and
        // Switch Control need something they can reach and activate.
        XCTAssertFalse(introView.contains("onTapGesture"))
    }

    func testSettingsAboutDocumentationTabsOpenExternalLinks() throws {
        let source = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(source.contains(#"@State private var showingHowToUseBrowser = false"#))
        XCTAssertTrue(source.contains(#"private let howToUseURLString = "https://docs.ijustinz.com/body/how-to-use""#))
        XCTAssertTrue(source.contains(#"private let privacyPolicyURLString = "https://docs.ijustinz.com/body/privacy""#))
        XCTAssertTrue(source.contains("showingHowToUseBrowser = true"))
        XCTAssertTrue(source.contains("showingPrivacyBrowser = true"))
        XCTAssertTrue(source.contains("case .externalLink:"))
        XCTAssertTrue(source.contains(#"Image(systemName: "arrow.up.right")"#))
        XCTAssertFalse(source.contains("BodyHowToUseSettingsSheet()"))
        XCTAssertFalse(source.contains("private struct BodyHowToUseSettingsSheet"))
    }

    func testSettingsDataTabsExposePermissions() {
        XCTAssertEqual(BodySettingsDataTab.allCases.map(\.title), ["Source", "Permissions", "Data Refresh", "Cache"])
        XCTAssertEqual(BodySettingsDataTab.source.sheet, .source)
        XCTAssertEqual(BodySettingsDataTab.permissions.sheet, .permissions)
        XCTAssertEqual(BodySettingsDataTab.syncStatus.sheet, .syncStatus)
        XCTAssertEqual(BodySettingsDataTab.cache.sheet, .cache)
    }

    func testSettingsSheetsDoNotShowToolbarCloseButtons() throws {
        let source = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertFalse(source.contains(#"Button("Cancel")"#))
        XCTAssertFalse(source.contains(#"Button("Done")"#))
    }

    func testAutoApplyWorkoutEffortSettingIsWiredAndDefaultsOff() throws {
        let keys = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let settings = try text(at: "Body/Views/BodySettingsView.swift")
        let store = try text(at: "Body/Services/HealthKitWorkoutStore.swift")

        XCTAssertTrue(keys.contains(#"static let autoApplyWorkoutEffortKey = "autoApplyWorkoutEffort""#))
        XCTAssertTrue(settings.contains("@AppStorage(BodyAppearancePreference.autoApplyWorkoutEffortKey) private var autoApplyWorkoutEffort = false"))
        XCTAssertTrue(settings.contains("BodyAutoApplyEffortToggleRow("))
        // The setting must gate the auto-write path in the store, not just the UI.
        XCTAssertTrue(store.contains("func autoApplyPredictedEffortIfNeeded(monthKeys:"))
        XCTAssertTrue(store.contains("BodyAppearancePreference.autoApplyWorkoutEffortKey"))
    }

    func testWorkoutsChartSwipeMonthSettingIsWiredAndDefaultsOn() throws {
        let keys = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let settings = try text(at: "Body/Views/BodySettingsView.swift")
        let workouts = try text(at: "Body/Views/BodyWorkoutsView.swift")

        XCTAssertTrue(keys.contains(#"static let workoutsChartSwipeSwitchesMonthKey = "workoutsChartSwipeSwitchesMonth""#))
        XCTAssertTrue(settings.contains("@AppStorage(BodyAppearancePreference.workoutsChartSwipeSwitchesMonthKey) private var workoutsChartSwipeSwitchesMonth = true"))
        XCTAssertTrue(settings.contains("BodyWorkoutMonthSwipeSettingsSheet("))
        XCTAssertTrue(settings.contains("BodyWorkoutMonthSwipeToggleRow("))
        // The setting must gate the actual gesture on the workouts charts,
        // not just render a toggle in Settings.
        XCTAssertTrue(workouts.contains("@AppStorage(BodyAppearancePreference.workoutsChartSwipeSwitchesMonthKey) private var workoutsChartSwipeSwitchesMonth = true"))
        XCTAssertTrue(workouts.contains("switchMonthForChartSwipe(translation:"))
        // The swipe must reuse the async month-selection path (loading badge,
        // dedup, timeout) rather than applying the month directly.
        XCTAssertTrue(workouts.contains("BodyWorkoutChartSwipe.adjacentMonthYear("))
        XCTAssertTrue(workouts.contains("requestMonthYearSelection("))
    }

    func testReadinessAICommentSettingIsWiredAndDefaultsOn() throws {
        let keys = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let settings = try text(at: "Body/Views/BodySettingsView.swift")
        let generator = try text(at: "Body/Services/ReadinessCommentGenerator.swift")

        XCTAssertTrue(keys.contains(#"static let showReadinessAICommentKey = "showReadinessAIComment""#))
        XCTAssertTrue(settings.contains("@AppStorage(BodyAppearancePreference.showReadinessAICommentKey) private var showReadinessAIComment = true"))
        XCTAssertTrue(settings.contains("BodyReadinessAIToggleRow("))
        // FoundationModels ships in iOS 26 while the app deploys to 18.0, so every
        // touch of the system model must stay behind an availability gate.
        XCTAssertTrue(generator.contains("if #available(iOS 26.0, *)"))

        // BodyMetricsKit compiles for watchOS, where FoundationModels does not
        // exist — the AI code must never leak into the shared readiness models.
        let readinessModels = try text(at: "BodyMetricsKit/ReadinessModels.swift")
        XCTAssertFalse(readinessModels.contains("FoundationModels"))
        XCTAssertFalse(keys.contains("FoundationModels"))
    }

    func testHomeBackgroundDefaultUsesBalancedBlueProfile() {
        XCTAssertEqual(BodyHomeBackground.rawValue(from: BodyHomeBackground.defaultColors), "30B5FF,0A85FF,0057D9")
        XCTAssertEqual(BodyHomeBackground.defaultSeparators[0], 0.33, accuracy: 0.0001)
        XCTAssertEqual(BodyHomeBackground.defaultSeparators[1], 0.67, accuracy: 0.0001)
        XCTAssertEqual(BodyHomeBackgroundProfile.appDefault.segmentSummary, "33% / 34% / 33%")
    }

    func testHomeBackgroundProfileStoreKeepsFixedDefaultAndCapsCustomProfiles() {
        let profiles = (0..<6).map { index in
            BodyHomeBackgroundProfile(
                id: "custom-\(index)",
                colorsRawValue: "30B5FF,0A85FF,0057D9",
                separatorsRawValue: "0.3300,0.6700"
            )
        }

        let rawValue = BodyHomeBackgroundProfileStore.rawValue(from: profiles)
        let customProfiles = BodyHomeBackgroundProfileStore.customProfiles(from: rawValue)
        let allProfiles = BodyHomeBackgroundProfileStore.allProfiles(from: rawValue)

        XCTAssertEqual(customProfiles.count, 4)
        XCTAssertEqual(allProfiles.count, 5)
        XCTAssertEqual(allProfiles.first?.id, BodyHomeBackgroundProfile.appDefaultID)
        XCTAssertFalse(customProfiles.contains { $0.id == BodyHomeBackgroundProfile.appDefaultID })
    }

    func testHomeBackgroundCustomProfileNamesArePersistedAndEditable() throws {
        let profile = BodyHomeBackgroundProfile.custom(
            name: "  Evening Blue  ",
            colors: BodyHomeBackground.defaultColors,
            separators: BodyHomeBackground.defaultSeparators
        )
        let rawValue = BodyHomeBackgroundProfileStore.rawValue(from: [profile])
        let decodedProfile = try XCTUnwrap(BodyHomeBackgroundProfileStore.customProfiles(from: rawValue).first)

        XCTAssertEqual(decodedProfile.displayName(defaultName: "Saved 1"), "Evening Blue")
        XCTAssertEqual(decodedProfile.renamed("  Ocean  ").displayName(defaultName: "Saved 1"), "Ocean")
        XCTAssertEqual(decodedProfile.renamed("   ").displayName(defaultName: "Saved 1"), "Saved 1")
    }

    func testSettingsSourceSheetExposesGlobalDefaultsAndCombineToggle() throws {
        let source = try text(at: "Body/Views/BodySettingsView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let engineSource = try healthKitFetchEngineText()

        XCTAssertTrue(source.contains("case source"))
        XCTAssertTrue(source.contains("BodySourceSettingsSheet(workoutStore: workoutStore)"))
        XCTAssertTrue(source.contains("Combine Sources with Same Name"))
        XCTAssertTrue(source.contains("Primary Data Source"))
        XCTAssertTrue(source.contains("Secondary Data Source"))
        XCTAssertTrue(source.contains("updateCombinesHealthDataSourcesByName"))
        XCTAssertTrue(source.contains("updateDefaultHealthDataSource"))
        XCTAssertTrue(source.contains("updateDefaultSecondaryHealthDataSource"))
        XCTAssertTrue(storeSource.contains("resolvedHealthDataSourceOption"))
        XCTAssertTrue(storeSource.contains("resolvedSecondaryHealthDataSourceOption"))
        XCTAssertTrue(engineSource.contains("selectedSecondaryHealthDataSourceOption(for: kind).isNoComparison"))
    }

    /// User-created custom sources are a three-layer Body Pro feature (fetch
    /// gate, render gate, watch-seed gate) whose layers can only disagree
    /// silently — a locked phone showing All Sources while the watch keeps
    /// filtering by the group is invisible until someone compares two screens.
    /// None of the three chokepoints is reachable from a unit test (live actor,
    /// main-actor store, HealthKit refresh), so the gates themselves are pinned
    /// here; their pure inputs are exercised in
    /// `HealthKitWorkoutStoreComputeSeedTests` and `BodyHealthSourceResolverTests`.
    func testCustomHealthSourceGroupsAreProGatedOnEveryLayer() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let engineSource = try healthKitFetchEngineText()
        let resolverSource = try text(at: "BodyWatch/WatchSourceResolver.swift")

        // Fetch gate: both engine chokepoints (the query resolution and the
        // option it reports) widen a custom pick to all sources while locked.
        XCTAssertTrue(engineSource.contains("func sourceQueryResolution("))
        XCTAssertEqual(
            engineSource.occurrenceCount(of: "guard !option.isCustomSource || BodyProEntitlement.isUnlocked else {"),
            2
        )
        XCTAssertTrue(engineSource.contains("static func registeringCustomGroupBuckets<Source>("))
        XCTAssertTrue(engineSource.contains("func customHealthSourceIDsWithData()"))

        // Render gate: the store's synchronous accessors apply the same gate, and
        // report the group's CURRENT name (a rename must never rewrite — and
        // re-sign — the stored selection).
        XCTAssertTrue(storeSource.contains("private func resolvedCustomHealthSourceOption("))
        XCTAssertTrue(storeSource.contains("guard BodyProEntitlement.isUnlocked,"))
        XCTAssertTrue(storeSource.contains("let group = customHealthSourceGroups.first(where: { $0.id == option.id })"))
        XCTAssertTrue(storeSource.contains("customIDsWithData.contains(option.id) ? group.option : absentFallback"))

        // Seed gate: a locked entitlement ships the neutralized selection AND
        // withholds the definitions, so the watch stops filtering too.
        XCTAssertTrue(storeSource.contains("let isProUnlocked = BodyProEntitlement.isUnlocked"))
        XCTAssertTrue(storeSource.contains("Self.selectionNeutralizingCustomSources(healthDataSourceSelection).rawValue"))
        XCTAssertTrue(storeSource.contains("let customHealthSourceGroupsRaw = isProUnlocked && !customHealthSourceGroups.isEmpty"))

        // Signature plumbing: the membership suffix is composed in ONE place and
        // read through the two selection-signature helpers, so a cache written
        // under one form is never hydrated against another.
        XCTAssertTrue(storeSource.contains("static func customSourceGroupsSignatureSuffix("))
        XCTAssertTrue(storeSource.contains("private func currentPrimarySelectionSignature() -> String"))
        XCTAssertTrue(storeSource.contains("private func currentSecondarySelectionSignature() -> String"))
        XCTAssertTrue(storeSource.contains(#"";groups[\(BodyCustomHealthSourceGroupStore.canonicalSignature(for: customGroups))]""#))

        // Watch: every `sourceOptionsAndMap` call site registers the group
        // buckets — a missed one leaves a synced `custom:` selection unresolved,
        // which strictly skips the read and freezes the compute on seed values.
        XCTAssertTrue(resolverSource.contains("customGroups: [BodyCustomHealthSourceGroup]"))
        XCTAssertEqual(resolverSource.occurrenceCount(of: "sourceOptionsAndMap("), 2)
        for callSite in resolverSource.components(separatedBy: "sourceOptionsAndMap(").dropFirst() {
            XCTAssertTrue(String(callSite.prefix(400)).contains("customGroups: customGroups"))
        }
        for caller in ["BodyWatch/WatchDeltaFetcher.swift", "BodyWatch/WatchHealthStore.swift"] {
            let callerSource = try text(at: caller)
            XCTAssertTrue(callerSource.contains("BodyCustomHealthSourceGroupStore.groups("), caller)
            XCTAssertTrue(callerSource.contains("customHealthSourceGroupsRaw ?? \"\""), caller)
            XCTAssertTrue(callerSource.contains("customGroups: customGroups,"), caller)
        }
    }

    func testReadinessDailySeriesUsesCachedBaselineContext() throws {
        let source = try text(at: "BodyMetricsKit/ReadinessScoreCalculator.swift")
        let dailySeriesStart = try XCTUnwrap(source.range(of: "static func dailySeries(")?.lowerBound)
        let nextDeclaration = try XCTUnwrap(source[dailySeriesStart...].range(of: "private static func autonomicReadings(")?.lowerBound)
        let dailySeriesBlock = String(source[dailySeriesStart..<nextDeclaration])

        XCTAssertTrue(source.contains("ReadinessDailySeriesContext"))
        XCTAssertTrue(dailySeriesBlock.contains("ReadinessDailySeriesContext("))
        XCTAssertFalse(dailySeriesBlock.contains("summary("))
    }

    func testHealthPermissionTogglesUseGreenOnAndRedOffSwitchColors() throws {
        let source = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(source.contains("private struct BodyPermissionSwitchToggleStyle: ToggleStyle"))
        XCTAssertTrue(source.contains("BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red)"))
        XCTAssertTrue(source.contains("configuration.isOn ? onColor : offColor"))
        XCTAssertTrue(source.contains("configuration.isOn.toggle()"))
        XCTAssertFalse(source.contains(".tint(permission.tintColor)"))
    }

    /// The Home grid must stay one flat `ForEach` of cards inside `BodyHomeCardGridLayout`.
    /// A `ForEach` of rows identified by their card names gave the card being dragged a new
    /// identity on every mid-drag reorder, and the destroyed view is what UIKit's cancelled
    /// set-down animation then crashed reading (`previewForCancelling` ->
    /// `UIViewSnapshotResponder.animatedPositionTranslation`, EXC_BAD_ACCESS).
    func testHomeCardGridRendersOneFlatForEachSoDraggedCardsKeepTheirIdentity() throws {
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("BodyHomeCardGridLayout(spacing: 14)"))
        XCTAssertTrue(source.contains("ForEach(visibleHomeCards) { card in"))
        XCTAssertTrue(source.contains(".bodyHomeCardSlots(card.slotCount)"))
        XCTAssertFalse(source.contains("ForEach(homeCardRows)"))
        // The dragged card is parked in an unobserved box: writing observed state from
        // `onDrag` re-evaluates this view while UIKit is building the drag session.
        XCTAssertTrue(source.contains("dragState.card = card"))
        XCTAssertFalse(source.contains("@State private var draggedHomeCard"))
    }

    func testHealthMetricChartSelectionAnnotationsFitWithinChartEdges() throws {
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("let bodyChartSelectionOverflowResolution"))
        XCTAssertTrue(source.contains("AnnotationOverflowResolution("))
        XCTAssertTrue(source.contains("x: .fit(to: .chart)"))
        XCTAssertTrue(source.contains("y: .disabled"))
        XCTAssertEqual(source.occurrenceCount(of: "overflowResolution: bodyChartSelectionOverflowResolution"), 12)
        XCTAssertFalse(source.contains(".annotation(position: .top, spacing: 8) {"))
        // The scrub-callout background uses the shared glass-chip recipe (flat
        // translucent fill + thin white rim) instead of a bespoke fill + shadow.
        XCTAssertTrue(source.contains("BodyGlassChip(\n                color: Color(.secondarySystemGroupedBackground),"))
        XCTAssertFalse(source.contains(".shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)"))
    }

    func testAppSheetsShareTheTintedGlassBackdrop() throws {
        let cardBackground = try text(at: "Body/Views/BodyCardBackground.swift")

        XCTAssertTrue(cardBackground.contains("func bodySheetBackground(_ base: Color = Color(.systemGroupedBackground))"))
        XCTAssertTrue(cardBackground.contains("static let glassTintOpacity = 0.50"))
        XCTAssertTrue(cardBackground.contains("Color.black.opacity(BodySheetBackgroundStyle.glassTintOpacity)"))

        // Every sheet the app styles itself routes through the shared modifier, so the tint
        // can't drift per sheet the way the hand-copied `#unavailable` snippet did.
        let expectations: [(file: String, tinted: Int, legacy: Int)] = [
            ("Body/Views/BodySettingsView.swift", 3, 0),
            // The custom-source editor lives in its own file (it would otherwise
            // have pushed the settings file's count to 5).
            ("Body/Views/BodyCustomSourceEditorSheet.swift", 1, 0),
            ("Body/Views/BodyWorkoutListSheet.swift", 1, 0),
            ("Body/Views/Health/BodyHealthDataSourcePickerSheet.swift", 1, 0),
            ("Body/Views/Health/BodyAddBasicsMeasurementSheet.swift", 1, 0),
            // Exactly one: this sheet used to darken itself twice, which compounded the tint.
            ("Body/Views/Health/SleepScoreSheet.swift", 1, 0),
            // The workout-detail and share backdrops keep their own tint→black gradient.
            ("Body/Views/BodyWorkoutsView.swift", 0, 1),
            // The type filter moved out of the workouts file into its own sheet.
            ("Body/Views/BodyWorkoutFilterView.swift", 1, 0),
            // The Details explanation sheet likewise lives in its own file, so the
            // workouts file above can keep its own backdrop and a count of zero.
            ("Body/Views/BodyWorkoutDetailsExplanationSheet.swift", 1, 0),
            // The Equivalent card's explanation sheet, same reasoning as the Details one.
            ("Body/Views/BodyEnergyEquivalentExplanationSheet.swift", 1, 0),
            // The readiness Impact by Activity explainer, likewise in its own file so the
            // metric detail view keeps no backdrop of its own.
            ("Body/Views/Health/BodyReadinessImpactExplanationSheet.swift", 1, 0),
            ("Body/Views/Health/BodyWorkoutShareSheet.swift", 0, 1)
        ]

        for expectation in expectations {
            let source = try text(at: expectation.file)
            XCTAssertEqual(
                source.occurrenceCount(of: ".bodySheetBackground("),
                expectation.tinted,
                expectation.file
            )
            XCTAssertEqual(
                source.occurrenceCount(of: "#unavailable(iOS 26.0)"),
                expectation.legacy,
                expectation.file
            )
        }
    }

    func testWorkoutShareFlowPresentsFullScreenWithGlassToolbarActions() throws {
        // The share flow is a full-screen page now, not a sheet.
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        XCTAssertTrue(workoutsSource.contains(".fullScreenCover(isPresented: $showsShareSheet)"))
        XCTAssertFalse(workoutsSource.contains(".sheet(isPresented: $showsShareSheet)"))
        // The Share button waits for the route fetch to settle (route or nil), not just
        // for a non-nil route, so route-less workouts get it too. It's always present
        // now — grayed out and inert via .disabled(!routeLoadSettled) rather than
        // conditionally inserted, so it never pops in mid-load.
        XCTAssertTrue(workoutsSource.contains(".disabled(!routeLoadSettled)"))
        // Scoped to the share-button overlay: `effectiveRoutePresence` legitimately
        // branches on `if routeLoadSettled` elsewhere in the file.
        let shareOverlayStart = try XCTUnwrap(workoutsSource.range(of: ".overlay(alignment: .topTrailing)")?.lowerBound)
        let shareOverlayEnd = try XCTUnwrap(workoutsSource.range(of: ".fullScreenCover(isPresented: $showsShareSheet)")?.lowerBound)
        XCTAssertFalse(workoutsSource[shareOverlayStart..<shareOverlayEnd].contains("if routeLoadSettled"))

        // A top-left ✕ close button and top-right Liquid Glass circle Share/Save
        // buttons replace the old bottom capsule bar.
        let shareSheetSource = try text(at: "Body/Views/Health/BodyWorkoutShareSheet.swift")
        XCTAssertTrue(shareSheetSource.contains("placement: .topBarLeading"))
        XCTAssertTrue(shareSheetSource.contains("\"xmark\""))
        // The badge beside the "Share" title reads "v6" — the reworked share card.
        XCTAssertTrue(shareSheetSource.contains(#"Text("v6")"#))
        XCTAssertFalse(shareSheetSource.contains(#"Text("v3")"#))
        XCTAssertFalse(shareSheetSource.contains(#"Text("Beta v2")"#))
        XCTAssertTrue(shareSheetSource.contains("\"square.and.arrow.up\""))
        XCTAssertTrue(shareSheetSource.contains("\"square.and.arrow.down\""))
        XCTAssertFalse(shareSheetSource.contains("shareBar"))
        XCTAssertFalse(shareSheetSource.contains("ShareActionChrome"))
        XCTAssertFalse(shareSheetSource.contains("safeAreaInset(edge: .bottom)"))
        // The route is optional now — a route-less workout shares the same flow with the
        // map tile dropped and the map load guarded against a nil route.
        XCTAssertTrue(shareSheetSource.contains("let route: WorkoutRoute?"))
        XCTAssertTrue(shareSheetSource.contains("if hasRoute {"))
        XCTAssertTrue(shareSheetSource.contains("guard let route else { return }"))

        // The plain "Route Only" route now draws at 90% of the fitted size (was 60%).
        let routeHeroSource = try text(at: "Body/Views/Health/BodyWorkoutRouteMapHero.swift")
        XCTAssertTrue(routeHeroSource.contains("sizeFactor: CGFloat = 0.9"))
    }

    func testWorkoutShareOptionRowsAndPhotoAdjustSteps() throws {
        let shareSheetSource = try text(at: "Body/Views/Health/BodyWorkoutShareSheet.swift")

        // The option strip was replaced by a trailing icon rail with expanding trays,
        // one open at a time.
        XCTAssertTrue(shareSheetSource.contains("RailOption"))
        XCTAssertTrue(shareSheetSource.contains("expandedOption"))

        // Aspect ratio and landscape arrangement are remembered across sessions behind
        // the policy seam, same pattern as the 2D/3D dimension.
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareAspectRatio.storageKey"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareLandscapeArrangement.storageKey"))
        XCTAssertTrue(shareSheetSource.contains("resolvedAspectRatio"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("2D")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("3D")"#))
        // The Route Style tray's Hide tile: stored under its own key, disabled on the
        // Map background with a hint, and any dimension pick shows the trace again.
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareRouteVisibility.storageKey"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Hide Route")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Hiding the route doesn't apply to the Map background.")"#))
        // Route-less workouts show an Icon row (Route Style slot) instead, with its own
        // storage key and Show/Hide tiles.
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareIconVisibility.storageKey"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Icon")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Show Icon")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Hide Icon")"#))
        // A route without usable altitude greys the 3D row out and says why.
        XCTAssertTrue(shareSheetSource.contains(#"Text("3D needs a route with elevation data.")"#))
        // Map snapshots are cached per ratio as well as per dimension.
        XCTAssertTrue(shareSheetSource.contains("MapSnapshotKey"))

        // Photo mode is two steps, switched by a chip strip in the tray position (no
        // segmented control, no Next button).
        XCTAssertTrue(shareSheetSource.contains("PhotoAdjustStep"))
        XCTAssertTrue(shareSheetSource.contains("mediaAdjustTray"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Reset Photo")"#))
        XCTAssertTrue(shareSheetSource.contains(#""Drag to move the photo. Pinch to zoom. Double-tap to reset.""#))
        XCTAssertTrue(shareSheetSource.contains(#""Drag to move. Pinch to resize. Double-tap to reset.""#))
        XCTAssertTrue(shareSheetSource.contains("clamped(imageSize:"))
        // While an import is in flight, the standard sync badge floats over the page
        // instead of a spinner on the tray tile.
        XCTAssertTrue(shareSheetSource.contains(#"BodySyncStatusBadgeLabel(icon: .spinner, text: "Importing media...")"#))

        // Video background: tile, load/create/save failure alerts.
        XCTAssertTrue(shareSheetSource.contains(#"Text("Your Video")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Couldn't Load Video")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Couldn't Create Video")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Couldn't Save Video")"#))

        // Free font row, plus the new ratio/arrangement/route-colour trays.
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareFontChoice"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareRouteColorChoice"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Ratio")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Arrange")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Route Color")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Route color doesn't apply to the Map background.")"#))

        // Body Pro picks which metrics the card shows, remembered per workout type.
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareMetricSelection.storageKey"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Metrics")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Pick up to 5 metrics.")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Requires Body Pro")"#))

        // Profile attribution: three independent toggles, free, avatar/nickname off by
        // default and the separator on, plus a caption while the tray is open with data
        // missing.
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareAvatarVisibility.storageKey"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareNicknameVisibility.storageKey"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareSeparatorVisibility.storageKey"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Show Avatar")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Show Nickname")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Show Separator")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Show your avatar or nickname first.")"#))
        XCTAssertTrue(shareSheetSource.contains(
            #"Text("Add a photo and name in Settings › Profile to show them on the card.")"#
        ))

        // The card computes its geometry from the aspect ratio, replacing the fixed
        // 9:16 layout constants.
        let cardSource = try text(at: "Body/Views/Health/BodyWorkoutShareCardView.swift")
        XCTAssertTrue(cardSource.contains("WorkoutShareCardGeometry"))
        XCTAssertTrue(cardSource.contains("fontDesign: Font.Design"))
        XCTAssertTrue(cardSource.contains("routeColor: Color"))
        // The route-less type glyph shrank from 56 pt to 30 pt.
        XCTAssertTrue(cardSource.contains("size: 30"))
        XCTAssertFalse(cardSource.contains("size: 56"))

        // Hero and card paint the ribbon through the same extracted painter.
        let routeHeroSource = try text(at: "Body/Views/Health/BodyWorkoutRouteMapHero.swift")
        XCTAssertTrue(routeHeroSource.contains("drawRibbon("))

        // The model exposes the new geometry type and aspect-ratio storage key.
        let cardModelSource = try text(at: "Body/Models/WorkoutShareCard.swift")
        XCTAssertTrue(cardModelSource.contains("struct WorkoutShareCardGeometry"))
        XCTAssertTrue(cardModelSource.contains("\"workoutShareAspectRatio\""))
    }

    func testWorkoutShareOptionRailOrder() throws {
        // Rail order: Font, Route Color, Route Style, Metrics, Profile, Background,
        // Ratio, Arrange — user's words (font, color, route, metrics, attribution,
        // media, ratio) with Arrange last per follow-up. Metrics is no longer the
        // last icon; Profile sits between Metrics and Background.
        let shareSheetSource = try text(at: "Body/Views/Health/BodyWorkoutShareSheet.swift")
        let railStart = try XCTUnwrap(shareSheetSource.range(of: "private func optionRail")?.lowerBound)
        let searchStart = shareSheetSource.index(railStart, offsetBy: 20)
        let nextFuncStart = try XCTUnwrap(
            shareSheetSource.range(of: "\n    private func ", range: searchStart..<shareSheetSource.endIndex)?.lowerBound
        )
        let railRegion = shareSheetSource[railStart..<nextFuncStart]

        let fontIndex = try XCTUnwrap(railRegion.range(of: #"Text("Font")"#)?.lowerBound)
        let routeColorIndex = try XCTUnwrap(railRegion.range(of: #"Text("Route Color")"#)?.lowerBound)
        let routeStyleIndex = try XCTUnwrap(railRegion.range(of: #"Text("Route Style")"#)?.lowerBound)
        let metricsIndex = try XCTUnwrap(railRegion.range(of: #"Text("Metrics")"#)?.lowerBound)
        let profileIndex = try XCTUnwrap(railRegion.range(of: #"Text("Profile")"#)?.lowerBound)
        let backgroundIndex = try XCTUnwrap(railRegion.range(of: #"Text("Background")"#)?.lowerBound)
        let ratioIndex = try XCTUnwrap(railRegion.range(of: #"Text("Ratio")"#)?.lowerBound)
        let arrangeIndex = try XCTUnwrap(railRegion.range(of: #"Text("Arrange")"#)?.lowerBound)

        XCTAssertLessThan(fontIndex, routeColorIndex)
        XCTAssertLessThan(routeColorIndex, routeStyleIndex)
        XCTAssertLessThan(routeStyleIndex, metricsIndex)
        XCTAssertLessThan(metricsIndex, profileIndex)
        XCTAssertLessThan(profileIndex, backgroundIndex)
        XCTAssertLessThan(backgroundIndex, ratioIndex)
        XCTAssertLessThan(ratioIndex, arrangeIndex)
    }

    func testWorkoutShareMonthSummaryContent() throws {
        // The month-summary card shares the workout sheet's chrome but drives a
        // separate init path, rail, and metric pool. Pin the seams so a refactor of
        // one doesn't silently orphan the other.
        let shareSheetSource = try text(at: "Body/Views/Health/BodyWorkoutShareSheet.swift")
        XCTAssertTrue(shareSheetSource.contains("init(monthSummary:"))
        XCTAssertTrue(shareSheetSource.contains("supportsLongImage: !isSummaryMode"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareMetricSelection.summaryStorageKey"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Chart Style")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Share Summary")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Share Workout")"#))
        XCTAssertTrue(shareSheetSource.contains("private func summaryOptionRail("))
        XCTAssertTrue(shareSheetSource.contains("summaryRatioTray"))
        XCTAssertTrue(shareSheetSource.contains("case chartStyle"))
        XCTAssertTrue(shareSheetSource.contains("activeTintType"))
        XCTAssertTrue(shareSheetSource.contains("summaryReferenceDate"))

        // The model owning the pool/geometry math for the summary card: chart style
        // enum, the summary struct itself, and the two localized chart-style names
        // (read via String(localized:) rather than Text, since they're used outside
        // SwiftUI view bodies).
        let monthSummarySource = try text(at: "Body/Models/WorkoutShareMonthSummary.swift")
        XCTAssertTrue(monthSummarySource.contains("enum WorkoutSummaryChartStyle"))
        XCTAssertTrue(monthSummarySource.contains("struct WorkoutShareMonthSummary"))
        XCTAssertTrue(monthSummarySource.contains(#"String(localized: "Calendar")"#))
        XCTAssertTrue(monthSummarySource.contains(#"String(localized: "Bar Chart")"#))
        // The three metrics that are always present regardless of pool/defaults.
        XCTAssertTrue(monthSummarySource.contains("\"summaryWorkouts\""))
        XCTAssertTrue(monthSummarySource.contains("\"summaryDuration\""))
        XCTAssertTrue(monthSummarySource.contains("\"summaryActiveEnergy\""))

        // The persistence key and resolution/toggle helpers the summary metrics tray
        // depends on, plus the geometry type driving the summary card's layout.
        let shareCardSource = try text(at: "Body/Models/WorkoutShareCard.swift")
        XCTAssertTrue(shareCardSource.contains("\"workoutShareSummaryMetricSelections\""))
        XCTAssertTrue(shareCardSource.contains("static func resolvedSummary("))
        XCTAssertTrue(shareCardSource.contains("static func togglingSummary("))
        XCTAssertTrue(shareCardSource.contains("struct WorkoutShareSummaryCardGeometry"))
        // Only the portraits and the chart-only square; a landscape remembered from a
        // workout share resolves away rather than rendering a shape the tray hides.
        XCTAssertTrue(shareCardSource.contains("static let supportedAspectRatios: [WorkoutShareAspectRatio] = [.portrait9x16, .portrait3x4, .square]"))
        XCTAssertTrue(shareCardSource.contains("case chartOnly"))
        XCTAssertTrue(shareCardSource.contains("supportsLandscape: Bool = true"))
        XCTAssertTrue(shareSheetSource.contains("supportsLandscape: !isSummaryMode"))
        XCTAssertTrue(shareSheetSource.contains("ForEach(WorkoutShareSummaryCardGeometry.supportedAspectRatios)"))
        XCTAssertTrue(shareSheetSource.contains("if activeAspectRatio != .square {"))
        // The month card's title and totals are set smaller than the workout card's
        // blocks — the chart is what the card leads with.
        XCTAssertTrue(shareCardSource.contains("static let titleFontSize: CGFloat = 22"))
        XCTAssertTrue(shareCardSource.contains("private static let metricScale: CGFloat = 0.8"))
        // Three totals at most on the month card, with its own caption.
        XCTAssertTrue(shareCardSource.contains("static let summaryMaximumCount = 3"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Pick up to 3 metrics.")"#))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareMetricSelection.summaryMaximumCount"))
        // The calendar keeps square cells: a five-week month must not stretch to the
        // six-row frame.
        let summaryCardSource = try text(at: "Body/Views/Health/BodyWorkoutShareSummaryCardView.swift")
        // The card reads its type off that geometry rather than carrying literals.
        XCTAssertTrue(summaryCardSource.contains("size: WorkoutShareSummaryCardGeometry.titleFontSize"))
        XCTAssertTrue(summaryCardSource.contains("size: geometry.metricValueSize"))
        XCTAssertTrue(summaryCardSource.contains("size: geometry.metricLabelSize"))
        XCTAssertTrue(summaryCardSource.contains("fillsAvailableHeight: false,"))
        XCTAssertFalse(summaryCardSource.contains("fillsAvailableHeight: true"))
        XCTAssertTrue(summaryCardSource.contains("scalesGlyphsToFit: true,"))
        let calendarViewSource = try text(at: "BodyShared/Components/WorkoutCalendarView.swift")
        XCTAssertTrue(calendarViewSource.contains("scalesGlyphsToFit: Bool = false,"))
        // The weekday letters are a stored choice on their own rail row, Show/Hide
        // tiles like the route-less card's Icon row rather than a tile in another tray.
        XCTAssertTrue(calendarViewSource.contains("showsWeekdayHeader: Bool = true,"))
        XCTAssertTrue(shareCardSource.contains("enum WorkoutShareWeekdayVisibility"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareWeekdayVisibility.storageKey"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Weekdays")"#))
        XCTAssertTrue(shareSheetSource.contains("case weekdays"))
        XCTAssertTrue(shareSheetSource.contains(#"railRow(.weekdays, symbol: "abc", label: Text("Weekdays"), trayWidth: trayWidth)"#))
        XCTAssertTrue(shareSheetSource.contains("private var weekdayTray: some View"))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Show Weekdays")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Hide Weekdays")"#))
        XCTAssertTrue(shareCardSource.contains("supportsLongImage: Bool = true"))

        // Widget row cap now takes an override so the summary card's bar chart can
        // show more rows than the home-screen widget style allows.
        let breakdownSource = try text(at: "BodyShared/Components/WorkoutTypeBreakdownView.swift")
        XCTAssertTrue(breakdownSource.contains("rowLimit: Int? = nil"))

        // The breakdown on the card is NOT the large widget's guise: it carries the
        // Workouts page's type on a leaner 42 pt row, across the full content width
        // (the bars start and end where the title and totals do).
        XCTAssertTrue(breakdownSource.contains("case shareCard"))
        XCTAssertTrue(shareCardSource.contains("private static let barRowHeight: CGFloat = 42"))
        XCTAssertFalse(shareCardSource.contains("barWidthFraction"))

        // How many of those bars is the user's pick (1 up to the month's own activity
        // count, five by default), and a pick past what the region holds shrinks the
        // chart rather than dropping bars.
        XCTAssertTrue(shareCardSource.contains("enum WorkoutShareSummaryBarCount"))
        XCTAssertTrue(shareCardSource.contains("\"workoutShareSummaryBarCount\""))
        XCTAssertTrue(shareCardSource.contains("static let defaultCount = 5"))
        XCTAssertTrue(shareCardSource.contains("var barContentScale: CGFloat"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareSummaryBarCount.storageKey"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareSummaryBarCount.options(availableTypeCount: summaryBarTypeCount)"))
        // Its own rail row (and rail option), not a second strip inside Chart Style.
        XCTAssertTrue(shareSheetSource.contains("case barCount"))
        XCTAssertTrue(shareSheetSource.contains("railRow(.barCount, symbol: \"list.number\", label: Text(\"Bars\"), trayWidth: trayWidth)"))
        XCTAssertTrue(shareSheetSource.contains("private func barCountTray("))
        XCTAssertTrue(shareSheetSource.contains(#"Text("How many activity bars the card shows.")"#))
        XCTAssertTrue(summaryCardSource.contains("barRowCount: barRowCount"))
        XCTAssertTrue(summaryCardSource.contains(".scaleEffect(scale, anchor: .top)"))

        // The new summary card view and the branding row it shares with the workout
        // card view (extracted so both cards draw the same wordmark/attribution).
        let summaryCardViewSource = try text(at: "Body/Views/Health/BodyWorkoutShareSummaryCardView.swift")
        XCTAssertTrue(summaryCardViewSource.contains("struct BodyWorkoutShareSummaryCardView: View"))
        XCTAssertTrue(summaryCardViewSource.contains("style: .shareCard,"))
        XCTAssertTrue(summaryCardViewSource.contains("WorkoutShareBrandingRow("))
        let cardViewSource = try text(at: "Body/Views/Health/BodyWorkoutShareCardView.swift")
        XCTAssertTrue(cardViewSource.contains("struct WorkoutShareBrandingRow: View"))

        // The workouts page: the share entry point, its accessibility label, and the
        // search field's focus-expand behavior (the four icon buttons fade out while
        // typing, and the keyboard has explicit exit paths).
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        XCTAssertTrue(workoutsSource.contains(".fullScreenCover(item: $monthSummaryShareRequest)"))
        XCTAssertTrue(workoutsSource.contains("BodyWorkoutShareSheet(monthSummary:"))
        XCTAssertTrue(workoutsSource.contains(#"accessibilityLabel("Share month summary")"#))
        XCTAssertTrue(workoutsSource.contains("@FocusState private var isSearchFocused"))
        XCTAssertTrue(workoutsSource.contains(".focused($isSearchFocused)"))
        XCTAssertTrue(workoutsSource.contains(".submitLabel(.done)"))
        XCTAssertTrue(workoutsSource.contains(".scrollDismissesKeyboard(.immediately)"))
        XCTAssertTrue(workoutsSource.contains("searchAndControlsRow(snapshot: displaySnapshot)"))

        // Scope to the row itself (same slicing technique as
        // testWorkoutShareOptionRailOrder) to confirm the fade-in/out is actually wired
        // to the buttons that disappear on focus, not just present somewhere on the page.
        let rowStart = try XCTUnwrap(
            workoutsSource.range(of: "private func searchAndControlsRow(")?.lowerBound
        )
        let rowSearchStart = workoutsSource.index(rowStart, offsetBy: 20)
        let rowNextFuncStart = try XCTUnwrap(
            workoutsSource.range(of: "\n    private func ", range: rowSearchStart..<workoutsSource.endIndex)?.lowerBound
        )
        let rowRegion = String(workoutsSource[rowStart..<rowNextFuncStart])
        XCTAssertGreaterThanOrEqual(rowRegion.occurrenceCount(of: ".transition(.opacity)"), 4)
        XCTAssertTrue(rowRegion.contains("if !isSearchFocused"))

        // Every new key needs both an en and zh-Hans translated stringUnit
        // (enforced separately at :4076); this just confirms the keys exist.
        let localizable = try text(at: "Body/Localizable.xcstrings")
        XCTAssertTrue(localizable.contains(#""Chart Style" : {"#))
        XCTAssertTrue(localizable.contains(#""How many activity bars the card shows." : {"#))
        XCTAssertTrue(localizable.contains(#""Bars" : {"#))
        XCTAssertTrue(localizable.contains(#""Show Weekdays" : {"#))
        XCTAssertTrue(localizable.contains(#""Hide Weekdays" : {"#))
        XCTAssertTrue(localizable.contains(#""Bar Chart" : {"#))
        XCTAssertTrue(localizable.contains(#""Share month summary" : {"#))
        XCTAssertTrue(localizable.contains(#""Share Summary" : {"#))
        XCTAssertTrue(localizable.contains(#""Active Days" : {"#))
        XCTAssertTrue(localizable.contains(#""Longest" : {"#))
        XCTAssertTrue(localizable.contains(#""Top Activity" : {"#))
    }

    func testWorkoutShareSummaryRailOrder() throws {
        // The summary rail drops Route Color/Route Style/Icon/Arrange (there's no
        // route or long-image mode in summary mode) and adds Chart Style between
        // Profile and Background. Same region-scoping technique as
        // testWorkoutShareOptionRailOrder, applied to the summary rail's own function.
        let shareSheetSource = try text(at: "Body/Views/Health/BodyWorkoutShareSheet.swift")
        let railStart = try XCTUnwrap(shareSheetSource.range(of: "private func summaryOptionRail")?.lowerBound)
        let searchStart = shareSheetSource.index(railStart, offsetBy: 20)
        let nextFuncStart = try XCTUnwrap(
            shareSheetSource.range(of: "\n    private func ", range: searchStart..<shareSheetSource.endIndex)?.lowerBound
        )
        let railRegion = shareSheetSource[railStart..<nextFuncStart]

        let fontIndex = try XCTUnwrap(railRegion.range(of: #"Text("Font")"#)?.lowerBound)
        let metricsIndex = try XCTUnwrap(railRegion.range(of: #"Text("Metrics")"#)?.lowerBound)
        let profileIndex = try XCTUnwrap(railRegion.range(of: #"Text("Profile")"#)?.lowerBound)
        let chartStyleIndex = try XCTUnwrap(railRegion.range(of: #"Text("Chart Style")"#)?.lowerBound)
        // Calendar only, in the same slot the bar chart's own row takes.
        let weekdaysIndex = try XCTUnwrap(railRegion.range(of: #"Text("Weekdays")"#)?.lowerBound)
        // Bar chart only, and only when the month has more than one activity to rank.
        let barsIndex = try XCTUnwrap(railRegion.range(of: #"Text("Bars")"#)?.lowerBound)
        let backgroundIndex = try XCTUnwrap(railRegion.range(of: #"Text("Background")"#)?.lowerBound)
        let ratioIndex = try XCTUnwrap(railRegion.range(of: #"Text("Ratio")"#)?.lowerBound)

        // The workout rail's order, with Chart Style in Route Style's slot and each
        // chart's own row directly under it.
        XCTAssertLessThan(fontIndex, chartStyleIndex)
        XCTAssertLessThan(chartStyleIndex, weekdaysIndex)
        XCTAssertLessThan(weekdaysIndex, barsIndex)
        XCTAssertLessThan(barsIndex, metricsIndex)
        XCTAssertLessThan(metricsIndex, profileIndex)
        XCTAssertLessThan(profileIndex, backgroundIndex)
        XCTAssertLessThan(backgroundIndex, ratioIndex)

        XCTAssertFalse(railRegion.contains(#"Text("Route Color")"#))
        XCTAssertFalse(railRegion.contains(#"Text("Route Style")"#))
        XCTAssertFalse(railRegion.contains(#"Text("Icon")"#))
        XCTAssertFalse(railRegion.contains(#"Text("Arrange")"#))
        XCTAssertFalse(railRegion.contains("longImageTile"))

        // The summary ratio tray also drops the long-image tile — there's no
        // long-image output style in summary mode.
        let trayStart = try XCTUnwrap(shareSheetSource.range(of: "private var summaryRatioTray")?.lowerBound)
        let traySearchStart = shareSheetSource.index(trayStart, offsetBy: 20)
        let trayNextDeclStart = try XCTUnwrap(
            shareSheetSource.range(of: "\n    private ", range: traySearchStart..<shareSheetSource.endIndex)?.lowerBound
        )
        let trayRegion = shareSheetSource[trayStart..<trayNextDeclStart]
        XCTAssertFalse(trayRegion.contains("longImageTile"))
    }

    func testWorkoutShareLongImageMode() throws {
        // The long image is its own output style under its own key — deliberately not a
        // sixth `WorkoutShareAspectRatio` case, which would join every `allCases` sweep,
        // the Pro gate, and the map-snapshot keys.
        let cardModelSource = try text(at: "Body/Models/WorkoutShareCard.swift")
        XCTAssertTrue(cardModelSource.contains("enum WorkoutShareOutputStyle"))
        XCTAssertTrue(cardModelSource.contains("\"workoutShareOutputStyle\""))
        XCTAssertTrue(cardModelSource.contains("\"workoutShareLongMetricSelections\""))
        // The two policy seams Share/Save branch on, plus the section rule.
        XCTAssertTrue(cardModelSource.contains("static func resolvedOutputStyle("))
        XCTAssertTrue(cardModelSource.contains("static func resolvedOutput("))
        XCTAssertTrue(cardModelSource.contains("static func longPreset("))
        XCTAssertTrue(cardModelSource.contains("enum WorkoutShareLongImageSections"))
        XCTAssertTrue(cardModelSource.contains("static func resolvedLong("))
        XCTAssertTrue(cardModelSource.contains("static func togglingLong("))

        let shareSheetSource = try text(at: "Body/Views/Health/BodyWorkoutShareSheet.swift")
        // The sixth Ratio tile, the uncapped metrics caption, and the disabled-media hint.
        XCTAssertTrue(shareSheetSource.contains(#"Text("Long Image")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("Pick the metrics for the long image.")"#))
        XCTAssertTrue(shareSheetSource.contains(#"Text("The long image uses a gradient background.")"#))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareOutputStyle.storageKey"))
        XCTAssertTrue(shareSheetSource.contains("WorkoutShareMetricSelection.longStorageKey"))
        // Share and Save both branch on the one resolved output, so a clip held under a
        // long image can't turn either into a video.
        XCTAssertTrue(shareSheetSource.contains("resolvedOutput("))
        XCTAssertTrue(shareSheetSource.contains("case .cardImage, .longImage:"))
        XCTAssertTrue(shareSheetSource.contains("if output == .video, let clip = renderableVideo {"))
        // Natural height: a nil height proposal plus the adaptive scale clamp.
        XCTAssertTrue(shareSheetSource.contains("ProposedViewSize(width: BodyWorkoutShareLongCardView.width, height: nil)"))
        XCTAssertTrue(shareSheetSource.contains("maximumLongOutputPixels"))
        // The detail page hands over everything the long image's charts need.
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        XCTAssertTrue(workoutsSource.contains("splitData: splitData,"))
        XCTAssertTrue(workoutsSource.contains("heartRateRecoveryBPM: heartRateRecoveryBPM"))
        XCTAssertTrue(workoutsSource.contains("enum WorkoutDetailChartPresentations"))
        // The cards the long image reuses are internal now — a copy of them in the
        // share view would be free to drift from the detail page.
        for card in [
            "BodyWorkoutHeartRateChartCard",
            "BodyWorkoutPaceCard",
            "BodyWorkoutElevationLineCard",
            "BodyWorkoutBucketedSeriesCard",
            "BodyWorkoutDetailMetricTile"
        ] {
            XCTAssertTrue(workoutsSource.contains("\nstruct \(card): View {"), "\(card) should be internal")
            XCTAssertFalse(workoutsSource.contains("private struct \(card): View {"))
        }
        // Both share exports paint the route through one extracted painter.
        let cardSource = try text(at: "Body/Views/Health/BodyWorkoutShareCardView.swift")
        XCTAssertTrue(cardSource.contains("struct WorkoutShareRouteTrace: View"))
        let longSource = try text(at: "Body/Views/Health/BodyWorkoutShareLongCardView.swift")
        XCTAssertTrue(longSource.contains("WorkoutShareRouteTrace("))
        XCTAssertTrue(longSource.contains("static let width: CGFloat = 360"))
        XCTAssertTrue(longSource.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    func testWorkoutShareDaylightPreset() throws {
        // Daylight is a third gradient preset — a pure-white card inverting Midnight's
        // ink. Behavioral ink/scheme resolution is covered by WorkoutShareCardTests and
        // WorkoutShareRenderTests; these are minimal source guards only.
        let cardModelSource = try text(at: "Body/Models/WorkoutShareCard.swift")
        XCTAssertTrue(cardModelSource.contains("case daylight"))
        XCTAssertTrue(cardModelSource.contains("enum WorkoutShareCardInk"))

        // The sheet forces the preview/export colour scheme off the resolved ink rather
        // than a hard-coded `.dark`.
        let shareSheetSource = try text(at: "Body/Views/Health/BodyWorkoutShareSheet.swift")
        XCTAssertTrue(shareSheetSource.contains(".environment(\\.colorScheme, activeInk == .dark ? .light : .dark)"))
        XCTAssertTrue(shareSheetSource.contains(".environment(\\.colorScheme, activeLongPreset.ink == .dark ? .light : .dark)"))
    }

    func testRouteStylePickerAndThreeDHero() throws {
        // Route Style rows are Star-Metric-style tiles (icon/title/subtitle/checkmark),
        // not the old unit-preference chip control — so the enum no longer conforms to
        // that private protocol.
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        XCTAssertTrue(settingsSource.contains("iconName: style.settingsIconName"))
        XCTAssertFalse(settingsSource.contains("extension BodyWorkoutRouteStyle: BodyUnitPreferenceOption"))

        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        XCTAssertTrue(workoutsSource.contains("case .threeD:"))
        XCTAssertTrue(workoutsSource.contains("BodyWorkoutRoute3DHero("))
        // The 3D hero rotates with a horizontal swipe on the tap gap, driven through an
        // observable so a drag frame redraws the hero rather than the whole sheet.
        XCTAssertTrue(workoutsSource.contains("routeYawRadiansPerPoint"))
        XCTAssertTrue(workoutsSource.contains("BodyWorkoutRouteYawState"))
        // A rotation swipe's release must not double as a tap that opens the map.
        XCTAssertTrue(workoutsSource.contains("guard !routeYawState.isSwiping else { return }"))

        let routeHeroSource = try text(at: "Body/Views/Health/BodyWorkoutRouteMapHero.swift")
        XCTAssertTrue(routeHeroSource.contains("sizeFactor: CGFloat = 0.9"))
        XCTAssertTrue(routeHeroSource.contains("enum BodyWorkoutRouteHeroFit"))

        // Picker order is 2D Map, 2D Plain, 3D Map, 3D Plain; only the two map-backed
        // styles draw their route into the snapshot rather than stroking it.
        XCTAssertEqual(BodyWorkoutRouteStyle.allCases.map(\.rawValue), ["map", "plain", "map3d", "3d"])
        XCTAssertFalse(BodyWorkoutRouteStyle.map3D.supportsRouteDraw)
    }

    func testWorkoutDetailReservesTheRouteHeroAndDrawsItProgressively() throws {
        // A cheap series-metadata probe answers "does this workout have a route?" long
        // before the fixes stream in, so the hero band can be reserved up front.
        let routeEngineSource = try text(at: "Body/Services/HealthKitFetchEngine+Route.swift")
        XCTAssertTrue(routeEngineSource.contains("func workoutHasRoute(workoutID: UUID) async throws -> Bool"))
        XCTAssertTrue(routeEngineSource.contains("limit: 1"))

        // The store splits the fixes off from the reverse geocode so the draw doesn't
        // queue behind a network round trip, and keeps a presence cache alongside the
        // route cache — cleared at the same gates (authorization, the Workouts
        // permission toggle, Clear Cache, and the eager background clear).
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        XCTAssertTrue(storeSource.contains("func loadWorkoutRouteCoordinates(for workout: WorkoutSummary) async -> WorkoutRoute?"))
        XCTAssertTrue(storeSource.contains("func workoutRoutePresence(for workout: WorkoutSummary) async -> BodyWorkoutRoutePresence"))
        XCTAssertTrue(storeSource.contains("func cachedWorkoutRoute(for workout: WorkoutSummary) -> WorkoutRoute?"))
        XCTAssertEqual(storeSource.occurrenceCount(of: "routePresenceCache.removeAll()"), 4)

        let routeModelSource = try text(at: "Body/Models/WorkoutRoute.swift")
        XCTAssertTrue(routeModelSource.contains("enum BodyWorkoutRoutePresence"))
        XCTAssertTrue(routeModelSource.contains("var reservesHero: Bool"))

        let routeStyleSource = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        // A fresh install opens routes as the 3D elevation ribbon with the draw on —
        // Map can't draw, so the two defaults have to move together.
        XCTAssertTrue(routeStyleSource.contains("static let defaultValue: BodyWorkoutRouteStyle = .threeD"))
        XCTAssertTrue(BodyWorkoutRouteStyle.defaultValue.supportsRouteDraw)

        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        XCTAssertTrue(workoutsSource.contains("@State private var routePresence: BodyWorkoutRoutePresence = .unknown"))
        XCTAssertTrue(workoutsSource.contains("effectiveRoutePresence.reservesHero"))
        XCTAssertTrue(workoutsSource.contains("private var reservedGapHeight: CGFloat"))
        XCTAssertTrue(workoutsSource.contains("BodyAppearancePreference.drawsWorkoutRouteOnLoadKey"))
        XCTAssertTrue(workoutsSource.contains("private var drawsRouteOnLoad = true"))
        // The probe must not sit on the critical path: `fetchWorkout` wraps a raw
        // HKSampleQuery with no cancellation, so awaiting it inline would let a stalled
        // read hide the route, the splits, and the Share button.
        XCTAssertTrue(workoutsSource.contains("let probeTask = Task { @MainActor in"))
        XCTAssertTrue(workoutsSource.contains("async let loadedCoordinates = workoutStore.loadWorkoutRouteCoordinates(for: workout)"))
        // Share settles before the splits are awaited, as it always has.
        let settledIndex = try XCTUnwrap(workoutsSource.range(of: "routeLoadSettled = true")?.lowerBound)
        let splitsIndex = try XCTUnwrap(workoutsSource.range(of: "splitData = await loadedSplitData")?.lowerBound)
        XCTAssertLessThan(settledIndex, splitsIndex)
        // The band is sized by an animatable height, never by inserting the gap: SwiftUI
        // lays an inserted fixed-height view out at full size on its first frame, which
        // is the ~324 pt snap this feature exists to remove.
        XCTAssertFalse(workoutsSource.contains("route == nil ? 60 : 24"))

        let routeHeroSource = try text(at: "Body/Views/Health/BodyWorkoutRouteMapHero.swift")
        XCTAssertTrue(routeHeroSource.contains("enum BodyWorkoutRouteReveal"))
        XCTAssertTrue(routeHeroSource.contains("TimelineView(.animation"))
        XCTAssertTrue(routeHeroSource.contains("trimmedPath(from: 0, to:"))
        XCTAssertTrue(routeHeroSource.contains("revealed: CGFloat = 1"))
        XCTAssertTrue(routeHeroSource.contains("struct BodyWorkoutRouteHeroShimmer"))
        // `var` with a default, not `let`: a `let` with a default value is left out of
        // the synthesized memberwise initializer, so no call site could opt in.
        XCTAssertTrue(routeHeroSource.contains("var drawsReveal: Bool = false"))
        XCTAssertFalse(routeHeroSource.contains("let drawsReveal: Bool = false"))
        // Only the styles that stroke their own trace draw. The map hero composites its
        // route into the snapshot, so it takes no reveal at all.
        XCTAssertTrue(routeStyleSource.contains("var supportsRouteDraw: Bool"))
        XCTAssertTrue(workoutsSource.contains("routeStyle.supportsRouteDraw"))
        XCTAssertFalse(workoutsSource.contains("BodyWorkoutRouteMapHero(route: route, tint: workout.type.color, targetCenterY: routeTargetCenterY, topInset: topSafeAreaInset, drawsReveal:"))
        // Every hero that can draw decides for itself whether Reduce Motion cancels it.
        XCTAssertGreaterThanOrEqual(
            routeHeroSource.occurrenceCount(of: "@Environment(\\.accessibilityReduceMotion) private var reduceMotion"),
            3
        )

        // The Draw Route toggle rides in the Route Style sheet, with its catalog strings.
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        XCTAssertTrue(settingsSource.contains("BodyAppearancePreference.drawsWorkoutRouteOnLoadKey"))
        XCTAssertTrue(settingsSource.contains("drawsRoute: $drawsWorkoutRouteOnLoad"))

        // Draw leads the sheet — it applies to every style below it, so it must sit above
        // the style card rather than trailing it.
        // Bounded by the struct itself rather than a fixed character budget, so adding a
        // line to the sheet can't silently slide the style rows out of the window and
        // turn this into a false pass.
        let sheetStart = try XCTUnwrap(settingsSource.range(of: "private struct BodyWorkoutRouteStyleSettingsSheet")?.upperBound)
        let sheetEnd = try XCTUnwrap(settingsSource.range(of: "\nprivate struct ", range: sheetStart..<settingsSource.endIndex)?.lowerBound)
        let sheetBody = settingsSource[sheetStart..<sheetEnd]
        let drawRow = try XCTUnwrap(sheetBody.range(of: #"Toggle("Draw Route", isOn: $drawsRoute)"#)?.lowerBound)
        let styleRows = try XCTUnwrap(sheetBody.range(of: "BodyStarMetricOptionRow(")?.lowerBound)
        XCTAssertLessThan(drawRow, styleRows)

        // With the draw on, the Workouts row reads "Draw · 3D" rather than just the style
        // — but never on Map, which can't draw whatever the stored switch says.
        XCTAssertTrue(settingsSource.contains("guard style.supportsRouteDraw, drawsWorkoutRouteOnLoad else { return style.title }"))
        XCTAssertTrue(settingsSource.contains(#"String(localized: "routeStyle.drawSummary")"#))
        // On Map the switch is dimmed and inert, and says why — the stored preference is
        // left alone so picking Plain or 3D restores it.
        XCTAssertTrue(settingsSource.contains("private var supportsDraw: Bool { selection.supportsRouteDraw }"))
        XCTAssertTrue(settingsSource.contains(".disabled(!supportsDraw)"))
        XCTAssertTrue(settingsSource.contains(#"supportsDraw ? "routeStyle.drawSubtitle" : "routeStyle.drawUnavailable""#))

        let catalog = try text(at: "Body/Localizable.xcstrings")
        XCTAssertTrue(catalog.contains("\"Draw Route\" : {"))
        XCTAssertTrue(catalog.contains("\"routeStyle.drawSubtitle\" : {"))
        XCTAssertTrue(catalog.contains("\"routeStyle.drawSummary\" : {"))
        XCTAssertTrue(catalog.contains("\"routeStyle.drawUnavailable\" : {"))
    }

    func testMetricDetailFloatsHeroChartCalloutAboveNavigationBar() throws {
        let detail = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")

        // The scrub callout is rendered by BodyHomeView on the topmost layer (above the
        // nav bar's back chevron/title), so the title no longer hides while scrubbing.
        XCTAssertTrue(detail.contains(".navigationTitle(String(localized: String.LocalizationValue(model.title)))"))
        XCTAssertFalse(detail.contains("isHeroChartSelectionActive"))
        // Range switches recreate the keyed hero chart, so the callout needs its own reset
        // or it sticks after a scrub-then-switch.
        XCTAssertTrue(detail.contains("floatingCallout?.callout = nil"))
        // Only the immersive hero floats its callout; the cards below keep the in-chart one.
        XCTAssertEqual(detail.occurrenceCount(of: "floatingCallout: immersive ? floatingCallout : nil"), 8)

        for file in [
            "Body/Views/Health/BodyMetricWarningCard.swift",
            "Body/Views/Health/Charts/MetricCharts.swift",
            "Body/Views/Health/Charts/BasicsCharts.swift",
            "Body/Views/Health/Charts/HeartRateRangeChart.swift",
            "Body/Views/Health/Charts/SourceComparisonCharts.swift"
        ] {
            let source = try text(at: file)
            XCTAssertTrue(source.contains(".bodyFloatingCalloutReporter(floatingCallout, selectionDate:"), file)
            // The in-chart annotation must stand down while the floating callout renders,
            // or the callout draws twice.
            XCTAssertTrue(source.contains("if floatingCallout == nil {"), file)
            XCTAssertFalse(source.contains("selectionActive"), file)
        }

        let sourceComparison = try text(at: "Body/Views/Health/Charts/SourceComparisonCharts.swift")
        XCTAssertEqual(sourceComparison.occurrenceCount(of: ".bodyFloatingCalloutReporter(floatingCallout, selectionDate:"), 3)

        // BodyHomeView hosts the layer above BOTH nav bars: the callout overlay must come
        // after the readiness detail overlay, and both detail sites must pass the state.
        let home = try text(at: "Body/Views/BodyHomeView.swift")
        XCTAssertTrue(home.contains("BodyChartFloatingCalloutLayer(state: heroChartCallout)"))
        XCTAssertEqual(home.occurrenceCount(of: "floatingCallout: heroChartCallout"), 2)
        if let readinessOverlayRange = home.range(of: "readinessDetailOverlay\n                    .accessibilityAddTraits(.isModal)"),
           let calloutLayerRange = home.range(of: "BodyChartFloatingCalloutLayer(state: heroChartCallout)") {
            XCTAssertTrue(readinessOverlayRange.lowerBound < calloutLayerRange.lowerBound)
        } else {
            XCTFail("Expected both the readiness detail overlay and the floating callout layer in BodyHomeView")
        }
    }

    func testHealthMetricChartDateDomainsFavorRightSidePadding() throws {
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("bodyHealthDetailChartLeadingDatePadding: TimeInterval = 2 * 60 * 60"))
        XCTAssertTrue(source.contains("bodyHealthDetailChartMinimumTrailingDatePadding: TimeInterval = 36 * 60 * 60"))
        XCTAssertTrue(source.contains("func bodyHealthDetailChartTrailingDatePadding(for selectedRange: BodyHealthTrendRange) -> TimeInterval"))
        XCTAssertTrue(source.contains("let rangeScaledPadding = Double(selectedRange.axisStrideDayCount) * 24 * 60 * 60 * 0.55"))
        XCTAssertTrue(source.contains("return max(bodyHealthDetailChartMinimumTrailingDatePadding, rangeScaledPadding)"))
        XCTAssertTrue(source.contains("func bodyHealthDetailChartXDomain(for dates: [Date], selectedRange: BodyHealthTrendRange, immersive: Bool = false, immersivePairedBars: Bool = false, pairedBarComparison: Bool = false) -> ClosedRange<Date>"))
        // Immersive charts (Y axis hidden) pad each edge by ~half a data bucket so the
        // first/last bar or point fits without clipping and no empty day appears. Week
        // single-mark charts bias slightly right (less space left, more right). Month charts
        // keep a half-bucket leading nudge with a full-bucket trailing; six-month/year charts
        // pin the first mark to the left wall (no leading padding) with a 1.5-bucket trailing.
        // Only the two-source paired-bar comparison chart is excluded and stays symmetric.
        // Non-immersive charts keep the small leading padding and favor right-side padding.
        XCTAssertTrue(source.contains("let bucketSeconds = Double(selectedRange.chartAggregationDayCount) * 24 * 60 * 60"))
        XCTAssertTrue(source.contains("if selectedRange == .recentWeek && !immersivePairedBars {"))
        XCTAssertTrue(source.contains("leadingDatePadding = 2 * 60 * 60"))
        XCTAssertTrue(source.contains("trailingDatePadding = 26 * 60 * 60"))
        XCTAssertTrue(source.contains("} else if !pairedBarComparison && selectedRange == .recentMonth {"))
        XCTAssertTrue(source.contains("leadingDatePadding = bucketSeconds * 0.5"))
        XCTAssertTrue(source.contains("trailingDatePadding = 28 * 60 * 60"))
        XCTAssertTrue(source.contains("} else if !pairedBarComparison && (selectedRange == .recentSixMonths || selectedRange == .recentYear) {"))
        XCTAssertTrue(source.contains("leadingDatePadding = 0"))
        XCTAssertTrue(source.contains("trailingDatePadding = bucketSeconds * 1.5"))
        XCTAssertTrue(source.contains("let halfBucketPadding = bucketSeconds * 0.5"))
        XCTAssertTrue(source.contains("leadingDatePadding = bodyHealthDetailChartLeadingDatePadding"))
        XCTAssertTrue(source.contains("trailingDatePadding = bodyHealthDetailChartTrailingDatePadding(for: selectedRange)"))
        XCTAssertEqual(
            source.occurrenceCount(of: "self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive:"),
            8
        )
        XCTAssertEqual(
            source.occurrenceCount(of: "bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive)"),
            5
        )
        XCTAssertEqual(
            source.occurrenceCount(of: "immersive: immersive, immersivePairedBars: true)"),
            1
        )
        XCTAssertEqual(
            source.occurrenceCount(of: "immersive: immersive, immersivePairedBars: true, pairedBarComparison: true)"),
            1
        )
        XCTAssertFalse(source.contains("bodyHealthDetailChartTrailingDatePadding: TimeInterval = 36 * 60 * 60"))
        XCTAssertFalse(source.contains("let leadingPadding: TimeInterval = 6 * 60 * 60"))
        XCTAssertFalse(source.contains("let trailingPadding: TimeInterval = 18 * 60 * 60"))
    }

    func testHealthMetricChartXDomainComputesExpectedPadding() {
        let hour: TimeInterval = 60 * 60
        let day: TimeInterval = 24 * hour
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let endDate = startDate.addingTimeInterval(3 * day)
        let dates = [endDate, startDate]

        let standardMonthDomain = bodyHealthDetailChartXDomain(for: dates, selectedRange: .recentMonth)
        XCTAssertEqual(standardMonthDomain.lowerBound.timeIntervalSince(startDate), -2 * hour, accuracy: 0.001)
        XCTAssertEqual(standardMonthDomain.upperBound.timeIntervalSince(endDate), 7 * day * 0.55, accuracy: 0.001)

        let immersiveWeekDomain = bodyHealthDetailChartXDomain(for: dates, selectedRange: .recentWeek, immersive: true)
        XCTAssertEqual(immersiveWeekDomain.lowerBound.timeIntervalSince(startDate), -2 * hour, accuracy: 0.001)
        XCTAssertEqual(immersiveWeekDomain.upperBound.timeIntervalSince(endDate), 26 * hour, accuracy: 0.001)

        let immersivePairedWeekDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentWeek,
            immersive: true,
            immersivePairedBars: true
        )
        XCTAssertEqual(immersivePairedWeekDomain.lowerBound.timeIntervalSince(startDate), -12 * hour, accuracy: 0.001)
        XCTAssertEqual(immersivePairedWeekDomain.upperBound.timeIntervalSince(endDate), 12 * hour, accuracy: 0.001)

        // Immersive month charts keep a half-bucket (12h) leading nudge with a 28h trailing
        // padding.
        let immersiveMonthDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentMonth,
            immersive: true
        )
        XCTAssertEqual(immersiveMonthDomain.lowerBound.timeIntervalSince(startDate), -12 * hour, accuracy: 0.001)
        XCTAssertEqual(immersiveMonthDomain.upperBound.timeIntervalSince(endDate), 28 * hour, accuracy: 0.001)

        // Single-source six-month charts pin the first mark to the left wall (no leading
        // padding) with a 1.5-bucket trailing padding (9 days).
        let immersiveSixMonthDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentSixMonths,
            immersive: true
        )
        XCTAssertEqual(immersiveSixMonthDomain.lowerBound.timeIntervalSince(startDate), 0, accuracy: 0.001)
        XCTAssertEqual(immersiveSixMonthDomain.upperBound.timeIntervalSince(endDate), 9 * day, accuracy: 0.001)

        // Single-source year charts do the same: no leading padding, trailing 18 days.
        let immersiveYearDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentYear,
            immersive: true
        )
        XCTAssertEqual(immersiveYearDomain.lowerBound.timeIntervalSince(startDate), 0, accuracy: 0.001)
        XCTAssertEqual(immersiveYearDomain.upperBound.timeIntervalSince(endDate), 18 * day, accuracy: 0.001)

        // The two-source paired-bar comparison chart keeps symmetric padding.
        let pairedBarSixMonthDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentSixMonths,
            immersive: true,
            immersivePairedBars: true,
            pairedBarComparison: true
        )
        XCTAssertEqual(pairedBarSixMonthDomain.lowerBound.timeIntervalSince(startDate), -3 * day, accuracy: 0.001)
        XCTAssertEqual(pairedBarSixMonthDomain.upperBound.timeIntervalSince(endDate), 3 * day, accuracy: 0.001)

        // Line/range comparison charts (paired bars but not the bar variant) still bias left.
        let rangeComparisonSixMonthDomain = bodyHealthDetailChartXDomain(
            for: dates,
            selectedRange: .recentSixMonths,
            immersive: true,
            immersivePairedBars: true
        )
        XCTAssertEqual(rangeComparisonSixMonthDomain.lowerBound.timeIntervalSince(startDate), 0, accuracy: 0.001)
        XCTAssertEqual(rangeComparisonSixMonthDomain.upperBound.timeIntervalSince(endDate), 9 * day, accuracy: 0.001)

        let emptyDateDomain = bodyHealthDetailChartXDomain(
            for: [],
            selectedRange: .recentWeek,
            immersive: true,
            immersivePairedBars: true
        )
        XCTAssertEqual(emptyDateDomain.upperBound.timeIntervalSince(emptyDateDomain.lowerBound), day, accuracy: 0.001)
    }

    func testHealthDashboardUpdatesRecalculateReadinessBeforeSaving() throws {
        let source = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let updateStart = try XCTUnwrap(source.range(of: "private func updateHealthDashboardSnapshot(")?.lowerBound)
        let saveStart = try XCTUnwrap(
            source.range(of: "HealthDashboardSnapshotStore.save(", range: updateStart..<source.endIndex)?.lowerBound
        )
        let updateBlock = String(source[updateStart..<saveStart])

        XCTAssertTrue(updateBlock.contains(".recalculatingReadiness("))
    }

    func testReadinessCardAndDetailAreRouted() throws {
        let source = try bodyHomeViewText()
        let cardStart = try XCTUnwrap(source.range(of: "private func readinessMetric(")?.lowerBound)
        let cardEnd = try XCTUnwrap(source.range(of: "private func energyMetric(", range: cardStart..<source.endIndex)?.lowerBound)
        let cardBlock = String(source[cardStart..<cardEnd])
        let whyStart = try XCTUnwrap(source.range(of: "private func readinessWhyCard(")?.lowerBound)
        let whyEnd = try XCTUnwrap(source.range(of: "@ViewBuilder\n    private var dataSourceFooter", range: whyStart..<source.endIndex)?.lowerBound)
        let whyBlock = String(source[whyStart..<whyEnd])

        XCTAssertTrue(source.contains("readinessMetric("))
        XCTAssertTrue(source.contains("case .readiness:"))
        XCTAssertTrue(source.contains("summary.readiness"))
        XCTAssertTrue(source.contains("trends.series(for: .readiness)"))
        XCTAssertTrue(source.contains("BodyReadinessStatusPresentation"))
        XCTAssertTrue(source.contains("BodyReadinessStatusBreakdownChart"))
        XCTAssertTrue(cardBlock.contains("unit: summary.score == nil ? \"\" : \"%\""))
        XCTAssertFalse(cardBlock.contains("BodyMetricDisplayValue(title: \"Status\""))
        XCTAssertTrue(source.contains("valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + \"%\" }"))
        XCTAssertTrue(whyBlock.contains("ReadinessStatus.displayOrder"))
        XCTAssertTrue(whyBlock.contains("About your score"))
        XCTAssertTrue(whyBlock.contains("status.scoreRangeText"))
        XCTAssertTrue(whyBlock.contains("status.explanation"))
        XCTAssertTrue(whyBlock.contains("BodyReadinessStatusPresentation.color(for: status)"))
        XCTAssertTrue(whyBlock.contains("activeStatus"))
        XCTAssertTrue(source.contains("@State private var activeReadinessTrendValue: Double?"))
        XCTAssertTrue(source.contains("private var activeReadinessStatus: ReadinessStatus?"))
        XCTAssertTrue(source.contains("readinessWhyCard(for: readiness, activeStatus: activeReadinessStatus)"))
        XCTAssertTrue(source.contains("activeHighlightedValue: activeTrendValueBinding"))
        XCTAssertTrue(source.contains("private var activeTrendValueBinding: Binding<Double?>?"))
        XCTAssertTrue(source.contains("case .readiness:\n            return $activeReadinessTrendValue"))
        XCTAssertFalse(whyBlock.contains("ForEach(readiness.components)"))
    }

    func testBasicsTrendCardsRouteThroughRegisteredNavigationDestination() throws {
        let source = try bodyHomeViewText()

        // The Basics page's Weight/Body Fat trend cards must push a `HomeMetricRoute`
        // (the type registered via `.navigationDestination(for: HomeMetricRoute.self)`
        // on the Home stack that hosts this page), not a bare `HealthMetricKind` — no
        // `navigationDestination(for: HealthMetricKind.self)` is registered anywhere,
        // which would make the cards inert. The `.basicsTrend` route (distinct from the
        // home trends section's `.trend`) also carries the card→detail zoom-morph source.
        XCTAssertTrue(source.contains("NavigationLink(value: HomeMetricRoute.basicsTrend(kind))"))
        XCTAssertTrue(source.contains(".matchedTransitionSource(id: HomeMetricRoute.basicsTrend(kind), in: zoomNamespace)"))
        XCTAssertFalse(source.contains("NavigationLink(value: kind)"))
        XCTAssertTrue(source.contains(".navigationDestination(for: HomeMetricRoute.self)"))
        XCTAssertFalse(source.contains(".navigationDestination(for: HealthMetricKind.self)"))
    }

    func testMetricDetailHeaderIconMatchesHomeMetricCardTintTreatment() throws {
        let source = try bodyHomeViewText()
        let cardIconStart = try XCTUnwrap(source.range(of: "Image(systemName: metric.symbolName)")?.lowerBound)
        let cardIconEnd = try XCTUnwrap(source.range(of: "private var valueRow", range: cardIconStart..<source.endIndex)?.lowerBound)
        let cardIconBlock = String(source[cardIconStart..<cardIconEnd])

        // The metric detail page no longer shows a header icon card — its current
        // value now reads large in the gradient hero — so only the home metric card
        // icon tint treatment is asserted here.
        XCTAssertTrue(cardIconBlock.contains(".foregroundColor(metric.symbolColor)"))
        XCTAssertTrue(cardIconBlock.contains(".fill(metric.symbolColor.opacity(0.16))"))
    }

    func testMetricDetailPagesUseRequestedCardOrdering() throws {
        let source = try bodyHomeViewText()
        // The header/selector/trend-card now live in the gradient hero; the cards
        // that scroll below it (and their ordering) live in `metricDetailCards`.
        let cardsStart = try XCTUnwrap(source.range(of: "private var metricDetailCards: some View")?.lowerBound)
        let cardsEnd = try XCTUnwrap(
            source.range(of: "private var metricHeroValueRow", range: cardsStart..<source.endIndex)?.lowerBound
        )
        let detailBodyBlock = String(source[cardsStart..<cardsEnd])
        let sleepSelectedCardsStart = try XCTUnwrap(detailBodyBlock.range(of: "selectedSleepCards")?.lowerBound)
        let sleepTrendCardStart = try XCTUnwrap(
            detailBodyBlock.range(of: "detailTrendComparisonCard", range: sleepSelectedCardsStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let sleepAboutStart = try XCTUnwrap(detailBodyBlock.range(of: "aboutSleepScoreCard")?.lowerBound)
        let dayViewStart = try XCTUnwrap(detailBodyBlock.range(of: "if supportsMetricDayView")?.lowerBound)
        let metricDayChartStart = try XCTUnwrap(
            detailBodyBlock.range(of: "metricDayChartCard", range: dayViewStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let metricActivityAveragesStart = try XCTUnwrap(
            detailBodyBlock.range(of: "metricActivityAveragesCard", range: metricDayChartStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let dayViewTrendCardStart = try XCTUnwrap(
            detailBodyBlock.range(of: "detailTrendComparisonCard", range: metricDayChartStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let dayViewElseStart = try XCTUnwrap(
            detailBodyBlock.range(of: "} else {", range: dayViewTrendCardStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let nonDayTrendCardStart = try XCTUnwrap(
            detailBodyBlock.range(of: "detailTrendComparisonCard", range: dayViewElseStart..<detailBodyBlock.endIndex)?.lowerBound
        )
        let readinessAboutStart = try XCTUnwrap(detailBodyBlock.range(of: "readinessWhyCard(for: readiness")?.lowerBound)
        // Scoped past the generic branch's trend card: the Vitals branch above has
        // its own (earlier) helpTextCard, and this ordering is about the generic one.
        let helpTextStart = try XCTUnwrap(
            detailBodyBlock.range(of: "helpTextCard", range: nonDayTrendCardStart..<detailBodyBlock.endIndex)?.lowerBound
        )

        XCTAssertLessThan(sleepSelectedCardsStart, sleepTrendCardStart)
        XCTAssertLessThan(sleepTrendCardStart, sleepAboutStart)
        XCTAssertLessThan(metricDayChartStart, dayViewTrendCardStart)
        XCTAssertLessThan(metricDayChartStart, metricActivityAveragesStart)
        XCTAssertLessThan(metricActivityAveragesStart, dayViewTrendCardStart)
        // The readiness "About your score" card sits after both branches' trend
        // cards, immediately above the About Readiness help-text card (shared by
        // the day-view and non-day branches).
        XCTAssertLessThan(dayViewTrendCardStart, dayViewElseStart)
        XCTAssertLessThan(nonDayTrendCardStart, readinessAboutStart)
        XCTAssertLessThan(readinessAboutStart, helpTextStart)
        XCTAssertLessThan(dayViewTrendCardStart, helpTextStart)
        XCTAssertEqual(detailBodyBlock.occurrenceCount(of: "detailTrendComparisonCard"), 3)
        XCTAssertEqual(detailBodyBlock.occurrenceCount(of: "readinessWhyCard(for: readiness"), 1)
        XCTAssertTrue(source.contains("BodyHomeTrendCardFactory.card("))
        XCTAssertTrue(source.contains("BodyHomeTrendCard(model: card, showsNavigationIndicator: false)"))
        XCTAssertTrue(source.contains("@StateObject private var trendComputationCache = BodyHomeTrendComputationCache()"))
        XCTAssertTrue(source.contains("model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .activeEnergy || model.kind == .readiness"))
        XCTAssertTrue(source.contains(#"return String(localized: "Heart Rate by Activity")"#))
        XCTAssertTrue(source.contains(#"return String(localized: "Average HRV")"#))
        XCTAssertTrue(source.contains(#"return String(localized: "Energy by Activity")"#))
        XCTAssertTrue(source.contains(#"return String(localized: "Impact by Activity")"#))
        XCTAssertFalse(source.contains("Activity Heart Rate"))
    }

    func testMetricWarningsAreWiredIntoHomeCardsAndDetail() throws {
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
        let heartRateCardStart = try XCTUnwrap(homeSource.range(of: "kind: .heartRate,")?.lowerBound)
        let heartRateCardEnd = try XCTUnwrap(
            homeSource.range(of: "kind: .restingHeartRate,", range: heartRateCardStart..<homeSource.endIndex)?.lowerBound
        )
        let heartRateCardBlock = String(homeSource[heartRateCardStart..<heartRateCardEnd])
        XCTAssertTrue(heartRateCardBlock.contains("warningSymbolName:"))

        let oxygenCardStart = try XCTUnwrap(homeSource.range(of: "kind: .oxygenSaturation,")?.lowerBound)
        let oxygenCardEnd = try XCTUnwrap(
            homeSource.range(of: "kind: .", range: homeSource.index(after: oxygenCardStart)..<homeSource.endIndex)?.lowerBound
        )
        let oxygenCardBlock = String(homeSource[oxygenCardStart..<oxygenCardEnd])
        XCTAssertTrue(oxygenCardBlock.contains("warningSymbolName:"))

        let cardSource = try text(at: "Body/Views/Health/BodyHealthMetricCard.swift")
        XCTAssertTrue(cardSource.contains("warningSymbolName"))

        let detailSource = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")
        let cardsStart = try XCTUnwrap(detailSource.range(of: "private var metricDetailCards: some View")?.lowerBound)
        let cardsEnd = try XCTUnwrap(
            detailSource.range(of: "private var metricHeroValueRow", range: cardsStart..<detailSource.endIndex)?.lowerBound
        )
        let detailBodyBlock = String(detailSource[cardsStart..<cardsEnd])
        let activityAveragesStart = try XCTUnwrap(detailBodyBlock.range(of: "metricActivityAveragesCard")?.lowerBound)
        XCTAssertNotNil(
            detailBodyBlock.range(of: "metricWarningCards", range: activityAveragesStart..<detailBodyBlock.endIndex),
            "metricWarningCards should appear after metricActivityAveragesCard in metricDetailCards"
        )

        let kitSource = try text(at: "BodyMetricsKit/MetricThresholdWarning.swift")
        XCTAssertTrue(kitSource.contains("case .lowHeartRate:\n            return 40"))
        XCTAssertTrue(kitSource.contains("case .highHeartRate:\n            return 120"))
        XCTAssertTrue(kitSource.contains("case .lowBloodOxygen:\n            return 90"))

        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        XCTAssertTrue(settingsSource.contains("case metricWarnings"))
        let warningsRowRange = try XCTUnwrap(settingsSource.range(of: "title: \"Warnings\""))
        let starMetricRowRange = try XCTUnwrap(settingsSource.range(of: "title: \"Star Metric\""))
        XCTAssertLessThan(warningsRowRange.lowerBound, starMetricRowRange.lowerBound)
    }

    func testReadinessDayViewKindStaysInSyncAcrossLists() throws {
        // `HealthMetricKind.dayViewKinds` and `supportsMetricDayView` are two
        // hand-maintained lists; readiness must appear in both or the feature
        // silently disappears.
        let detailSource = try bodyHomeViewText()
        let dayViewGateStart = try XCTUnwrap(detailSource.range(of: "private var supportsMetricDayView: Bool")?.lowerBound)
        let dayViewGateEnd = try XCTUnwrap(
            detailSource.range(of: "private var metricDayViewEnabled", range: dayViewGateStart..<detailSource.endIndex)?.lowerBound
        )
        let gateBlock = String(detailSource[dayViewGateStart..<dayViewGateEnd])
        let trueBranchEnd = try XCTUnwrap(gateBlock.range(of: "return true")?.lowerBound)
        XCTAssertTrue(gateBlock[..<trueBranchEnd].contains(".readiness"))

        let preferenceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        // Skip past the `[HealthMetricKind]` type annotation to the array literal.
        let dayViewKindsStart = try XCTUnwrap(preferenceSource.range(of: "static let dayViewKinds")?.lowerBound)
        let dayViewKindsLiteralStart = try XCTUnwrap(
            preferenceSource.range(of: "= [", range: dayViewKindsStart..<preferenceSource.endIndex)?.upperBound
        )
        let dayViewKindsEnd = try XCTUnwrap(
            preferenceSource.range(of: "]", range: dayViewKindsLiteralStart..<preferenceSource.endIndex)?.lowerBound
        )
        XCTAssertTrue(preferenceSource[dayViewKindsLiteralStart..<dayViewKindsEnd].contains(".readiness"))
    }

    func testLineHealthChartsDoNotRenderEmptyDatePlaceholderMarks() throws {
        let source = try bodyHomeViewText()

        XCTAssertFalse(source.contains("BodyLineChartPlaceholderSymbol"))
        XCTAssertFalse(source.contains("placeholderSymbolSize"))
        XCTAssertTrue(source.contains("placeholderBarYValue"))
    }

    func testLineHealthChartsUseStraightInterpolation() throws {
        let source = try bodyHomeViewText()

        XCTAssertFalse(source.contains(".interpolationMethod(.catmullRom)"))
        XCTAssertEqual(
            source.occurrenceCount(of: ".interpolationMethod("),
            source.occurrenceCount(of: ".interpolationMethod(.linear)")
        )
    }

    func testMetricDayLineChartUsesPreviewDotSymbols() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricDayChart")?.lowerBound)
        let chartEnd = try XCTUnwrap(
            source.range(of: "struct BodyHealthMetricDayRangeEntry", range: chartStart..<source.endIndex)?.lowerBound
        )
        let chartBlock = String(source[chartStart..<chartEnd])

        XCTAssertTrue(chartBlock.contains("BodyLineChartPreviewPointSymbol("))
        XCTAssertTrue(chartBlock.contains("isCurrent: isLatestEntry(entry)"))
        XCTAssertTrue(chartBlock.contains("pointDiameter: Self.pointDiameter"))
        XCTAssertTrue(chartBlock.contains("currentPointDiameter: Self.currentPointDiameter"))
        XCTAssertFalse(chartBlock.contains(".symbolSize(24)"))
    }

    func testHeartRateVariabilityDayChartUsesSleepAndWorkoutContextOverlay() throws {
        let source = try bodyHomeViewText()
        let detailStart = try XCTUnwrap(
            source.range(of: "case .heartRateVariability:\n            return metricDetail(")?.lowerBound
        )
        let detailBlock = String(source[detailStart...].prefix(900))
        let contextStart = try XCTUnwrap(source.range(of: "private var selectedMetricDayContextIntervals")?.lowerBound)
        let contextBlock = String(source[contextStart...].prefix(3_000))
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricDayChart")?.lowerBound)
        let chartEnd = try XCTUnwrap(
            source.range(of: "struct BodyHealthMetricDayRangeEntry", range: chartStart..<source.endIndex)?.lowerBound
        )
        let chartBlock = String(source[chartStart..<chartEnd])

        XCTAssertTrue(detailBlock.contains("sleepHistory: trends.sleepHistory"))
        XCTAssertTrue(contextBlock.contains("model.kind == .heartRate || model.kind == .heartRateVariability"))
        XCTAssertTrue(contextBlock.contains("stageSnapshot?.mainSession.dateInterval"))
        XCTAssertTrue(contextBlock.contains("stageSnapshot?.napSessions"))
        XCTAssertTrue(contextBlock.contains(#"symbolName: "bed.double.fill""#))
        XCTAssertTrue(contextBlock.contains(#"symbolName: "moon.zzz.fill""#))
        XCTAssertFalse(contextBlock.contains(#"symbolName: "moon.fill""#))
        XCTAssertTrue(contextBlock.contains("workouts(on: dayInterval)"))
        XCTAssertTrue(contextBlock.contains("color: workoutColorPalette.color(for: workout.type)"))
        XCTAssertFalse(contextBlock.contains("color: Color(red: 1.00, green: 0.38, blue: 0.12)"))
        XCTAssertTrue(chartBlock.contains(".foregroundStyle(interval.color)"))
        XCTAssertFalse(chartBlock.contains("interval.kind == .sleep ? Color.white : interval.color"))
    }

    func testStressAndActiveEnergyDetailModelsPassSleepHistoryForContextBands() throws {
        let source = try bodyHomeViewText()
        let activeEnergyStart = try XCTUnwrap(source.range(of: "case .activeEnergy:")?.lowerBound)
        let activeEnergyEnd = try XCTUnwrap(
            source.range(of: "case .restingEnergy:", range: activeEnergyStart..<source.endIndex)?.lowerBound
        )
        let activeEnergyBlock = String(source[activeEnergyStart..<activeEnergyEnd])

        let stressStart = try XCTUnwrap(source.range(of: "case .stress:")?.lowerBound)
        let stressBlock = String(source[stressStart...].prefix(2_500))

        XCTAssertTrue(activeEnergyBlock.contains("sleepHistory: trends.sleepHistory"))
        XCTAssertFalse(activeEnergyBlock.contains("sleepHistory: .empty"))
        XCTAssertTrue(stressBlock.contains("sleepHistory: trends.sleepHistory"))
        XCTAssertFalse(stressBlock.contains("sleepHistory: .empty"))
    }

    func testMetricCardPreviewStylesMatchRequestedChartKinds() throws {
        let source = try bodyHomeViewText()
        // Bounded by the NEXT declaration rather than a character count: the
        // preview struct grows (the pending/unavailable phases pushed it past
        // 7.8k), and a fixed prefix silently starts excluding the very lines
        // these assertions guard instead of failing loudly.
        let previewStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricCardTrendPreview")?.lowerBound)
        let previewEnd = try XCTUnwrap(source.range(of: "struct AnimatablePolyline", range: previewStart..<source.endIndex)?.lowerBound)
        let previewBlock = String(source[previewStart..<previewEnd])
        let heartRateCardStart = try XCTUnwrap(
            source.range(of: "kind: .heartRate,\n                title: \"Heart Rate\"")?.lowerBound
        )
        let restingHeartRateCardStart = try XCTUnwrap(source.range(of: "kind: .restingHeartRate,")?.lowerBound)
        let heartRateCardBlock = String(source[heartRateCardStart..<restingHeartRateCardStart])
        let heartRateVariabilityCardStart = try XCTUnwrap(source.range(of: "kind: .heartRateVariability,")?.lowerBound)
        let oxygenCardStart = try XCTUnwrap(source.range(of: "kind: .oxygenSaturation,")?.lowerBound)
        let heartRateVariabilityCardBlock = String(source[heartRateVariabilityCardStart..<oxygenCardStart])

        XCTAssertTrue(heartRateCardBlock.contains("chartPreview: trends.series(for: .heartRate)"))
        XCTAssertFalse(heartRateCardBlock.contains("chartRangePreview: trends.rangeSeries(for: .heartRate)"))
        XCTAssertFalse(heartRateCardBlock.contains("chartPreviewStyle: .range"))
        XCTAssertTrue(heartRateVariabilityCardBlock.contains("chartPreview: trends.series(for: .heartRateVariability)"))
        XCTAssertFalse(heartRateVariabilityCardBlock.contains("chartRangePreview: trends.rangeSeries(for: .heartRateVariability)"))
        XCTAssertFalse(heartRateVariabilityCardBlock.contains("chartPreviewStyle: .range"))
        XCTAssertTrue(source.contains("chartRangePreview: trends.rangeSeries(for: .oxygenSaturation)"))
        XCTAssertTrue(source.contains("chartRangePreview: trends.rangeSeries(for: .respiratoryRate)"))
        XCTAssertTrue(source.contains("chartPreviewStyle: .range"))
        XCTAssertTrue(previewBlock.contains("case .range:"))
        XCTAssertTrue(previewBlock.contains("rangePreview"))
        // The card model precomputes the preview points once (instead of the
        // preview view regrouping the series per render); the preview then
        // consumes the prepared range points.
        XCTAssertTrue(source.contains("BodyHomeMetricCardPreview.rangeCalendarPoints(from: $0, previewDayCount: previewDayCount)"))
        XCTAssertTrue(previewBlock.contains("let rangeCalendarPoints: [HealthTrendRangeCalendarPoint]"))
        XCTAssertTrue(previewBlock.contains("RoundedRectangle(cornerRadius: 2, style: .continuous)"))
        XCTAssertTrue(previewBlock.contains("Capsule(style: .continuous)"))
    }

    func testHeartRateRangeChartUsesStandardBarSelectionRule() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyHeartRateRangeTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(18_000))

        XCTAssertTrue(source.contains("private var usesRangeTrendChart: Bool"))
        XCTAssertTrue(source.contains("model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .oxygenSaturation || model.kind == .respiratoryRate"))
        XCTAssertTrue(source.contains("rangeSeries: workoutStore.healthTrends.rangeSeries(for: kind)"))
        XCTAssertTrue(source.contains("yDomain: metricRangeYDomain"))
        XCTAssertTrue(source.contains("return BodyHealthMetricRangeYDomain.bloodOxygen"))
        XCTAssertTrue(source.contains("return BodyHealthMetricRangeYDomain.respiratoryRate"))
        XCTAssertTrue(source.contains("ceil(minimum / 5) * 5 - 5"))
        XCTAssertTrue(source.contains("ceil(maximum / 5) * 5"))
        XCTAssertFalse(source.contains("floor((minimum - 5) / 5) * 5"))
        XCTAssertTrue(source.contains("showsAverageLineOverlay: model.kind == .heartRate || model.kind == .heartRateVariability"))
        XCTAssertTrue(chartBlock.contains("let showsAverageLineOverlay: Bool"))
        XCTAssertTrue(chartBlock.contains("private var rangeBarColor: Color"))
        XCTAssertTrue(chartBlock.contains("showsAverageLineOverlay ? Color.secondary.opacity(0.24) : symbolColor"))
        XCTAssertTrue(chartBlock.contains("private var averageLineOverlay: some ChartContent"))
        XCTAssertTrue(chartBlock.contains("LineMark("))
        XCTAssertTrue(chartBlock.contains(#"y: .value("Average \(title)", entry.value)"#))
        XCTAssertTrue(chartBlock.contains("BodyLineChartPreviewPointSymbol("))
        // Untrimmed history: the chart windows every range itself so the other
        // ranges' marks stay resident and morph instead of popping in.
        XCTAssertTrue(source.contains("} else if usesRangeTrendChart, let metricRangeSeries = model.rangeSeries {"))
        XCTAssertFalse(source.contains("rangeSeries: visibleMetricRangeSeries,"))
        XCTAssertTrue(chartBlock.contains("if let selectedRangePoint {\n                    RuleMark(x: .value(\"Selected Date\", selectedRangePoint.date, unit: .day))"))
        XCTAssertTrue(chartBlock.contains(".foregroundStyle(Color.secondary.opacity(0.48))"))
        XCTAssertTrue(chartBlock.contains(".lineStyle(StrokeStyle(lineWidth: 1.4))"))
        XCTAssertTrue(chartBlock.contains(".foregroundStyle(rangeBarColor)"))
        XCTAssertFalse(chartBlock.contains(".foregroundStyle(symbolColor.opacity(0.68))"))
        XCTAssertFalse(chartBlock.contains("width: .fixed(chartBarWidth + 5)"))
        XCTAssertFalse(chartBlock.contains(".foregroundStyle(Color.secondary.opacity(0.30))"))
    }

    func testWristTemperatureCardUsesLineChartDetailWithoutDayView() throws {
        let source = try bodyHomeViewText()
        let cardStart = try XCTUnwrap(source.range(of: "private func wristTemperatureMetric")?.lowerBound)
        let cardBlock = String(source[cardStart...].prefix(1_500))
        let factoryStart = try XCTUnwrap(source.range(of: "enum BodyHomeTrendCardFactory")?.lowerBound)
        let trendCardStart = try XCTUnwrap(
            source.range(of: "case .wristTemperature:", range: factoryStart..<source.endIndex)?.lowerBound
        )
        let trendCardBlock = String(source[trendCardStart...].prefix(1_100))
        let detailStart = try XCTUnwrap(source.range(of: "case .wristTemperature:")?.lowerBound)
        let detailBlock = String(source[detailStart...].prefix(3_000))
        let dayViewStart = try XCTUnwrap(source.range(of: "private var supportsMetricDayView")?.lowerBound)
        let dayViewBlock = String(source[dayViewStart...].prefix(700))

        XCTAssertTrue(cardBlock.contains(#"title: "Skin Temp""#))
        XCTAssertEqual(source.components(separatedBy: #"title: "Skin Temp""#).count - 1, 1)
        XCTAssertTrue(cardBlock.contains("chartPreviewStyle: .line"))
        XCTAssertTrue(trendCardBlock.contains(#"title: "Skin Temperature""#))
        XCTAssertTrue(detailBlock.contains(#"title: "Skin Temperature""#))
        XCTAssertTrue(detailBlock.contains("series: trends.wristTemperature.mapValues"))
        XCTAssertTrue(detailBlock.contains("daySeries: .empty"))
        XCTAssertTrue(detailBlock.contains("chartStyle: .line"))
        XCTAssertTrue(dayViewBlock.contains(".wristTemperature"))
    }

    func testTrainingLoadCardUsesLineChartWithCurrentIntervalWithoutUnitsOrDayView() throws {
        let source = try bodyHomeViewText()
        let cardStart = try XCTUnwrap(source.range(of: "metric(\n                kind: .trainingLoad")?.lowerBound)
        let cardBlock = String(source[cardStart...].prefix(1_100))
        let factoryStart = try XCTUnwrap(source.range(of: "enum BodyHomeTrendCardFactory")?.lowerBound)
        let trendCardStart = try XCTUnwrap(
            source.range(of: "case .trainingLoad:", range: factoryStart..<source.endIndex)?.lowerBound
        )
        let trendCardBlock = String(source[trendCardStart...].prefix(1_100))
        let detailStart = try XCTUnwrap(source.range(of: "case .trainingLoad:")?.lowerBound)
        let detailBlock = String(source[detailStart...].prefix(900))
        let dayViewStart = try XCTUnwrap(source.range(of: "private var supportsMetricDayView")?.lowerBound)
        let dayViewBlock = String(source[dayViewStart...].prefix(800))

        XCTAssertTrue(cardBlock.contains(#"title: "Training Load""#))
        XCTAssertTrue(cardBlock.contains(#"unit: """#))
        XCTAssertTrue(cardBlock.contains("decimals: 2"))
        XCTAssertFalse(cardBlock.contains(#"unit: "load""#))
        XCTAssertTrue(cardBlock.contains("chartStyle: .line"))
        XCTAssertTrue(cardBlock.contains("chartPreview: trends.series(for: .trainingLoad)"))
        XCTAssertTrue(trendCardBlock.contains(#"title: "Training Load""#))
        XCTAssertTrue(trendCardBlock.contains("chartStyle: .line"))
        XCTAssertTrue(trendCardBlock.contains("series: trends.series(for: .trainingLoad)"))
        XCTAssertTrue(trendCardBlock.contains("valueFormatter: { BodyValueFormat.numberText($0, decimals: 2) }"))
        XCTAssertFalse(trendCardBlock.contains(#"+ " load""#))
        XCTAssertTrue(detailBlock.contains(#"title: "Training Load""#))
        XCTAssertTrue(detailBlock.contains("summary: summary.trainingLoad"))
        XCTAssertTrue(detailBlock.contains(#"unit: """#))
        XCTAssertTrue(detailBlock.contains("decimals: 2"))
        XCTAssertFalse(detailBlock.contains(#"unit: "load""#))
        XCTAssertTrue(detailBlock.contains("chartStyle: .line"))
        XCTAssertTrue(detailBlock.contains("let trainingLoadInterval = BodyTrainingLoadIntervalPresentation.make(for: summary.trainingLoad.value)"))
        XCTAssertTrue(detailBlock.contains("highlightedRange: trainingLoadInterval"))
        XCTAssertTrue(detailBlock.contains("highlightedRangeResolver: BodyTrainingLoadIntervalPresentation.make(for:)"))
        XCTAssertTrue(dayViewBlock.contains(".trainingLoad"))
    }

    func testTrainingLoadTrendChartDrawsDynamicHorizontalCurrentIntervalBandWithoutInlineLabel() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(22_000))

        XCTAssertTrue(chartBlock.contains("let highlightedRange: BodyHealthMetricTrendHighlightedRange?"))
        XCTAssertTrue(chartBlock.contains("let highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)?"))
        XCTAssertTrue(chartBlock.contains("let displayedHighlightedRange = activeHighlightedRange"))
        XCTAssertTrue(chartBlock.contains("if let highlightedRange = displayedHighlightedRange,"))
        XCTAssertTrue(chartBlock.contains("private var activeHighlightedRange: BodyHealthMetricTrendHighlightedRange?"))
        XCTAssertTrue(chartBlock.contains("guard let highlightedRangeResolver, let activeHighlightSourceValue else {"))
        XCTAssertTrue(chartBlock.contains("return highlightedRangeResolver(activeHighlightSourceValue) ?? highlightedRange"))
        XCTAssertTrue(chartBlock.contains("private var activeHighlightSourceValue: Double?"))
        // Idle follows the last plotted point of the selected range (the dot
        // only while it is visible on the week chart), not the live summary
        // value: the band must track the line on screen in every range.
        XCTAssertTrue(chartBlock.contains("if showsCurrentValueDot, let currentValuePoint {"))
        XCTAssertTrue(chartBlock.contains("return visibleFinitePoints.last?.value"))
        XCTAssertFalse(chartBlock.contains("selectedTrendPoint?.value ?? currentValuePoint?.value"))
        XCTAssertTrue(chartBlock.contains(".chartBackground { chartProxy in"))
        XCTAssertTrue(chartBlock.contains("highlightedRange.lowerPlotBound(in: chartYDomain)"))
        XCTAssertTrue(chartBlock.contains("highlightedRange.upperPlotBound(in: chartYDomain)"))
        XCTAssertTrue(chartBlock.contains(".fill(highlightedRange.color.opacity(0.12))"))
        XCTAssertTrue(chartBlock.contains(".fill(highlightedRange.color.opacity(0.72))"))
        XCTAssertTrue(chartBlock.contains("highlightedRangeValues"))
        XCTAssertFalse(chartBlock.contains("Text(highlightedRange.title)"))
        XCTAssertFalse(chartBlock.contains("Highlighted Range Label"))
    }

    func testTrainingLoadDetailShowsIntervalDayBreakdownBelowLineChart() throws {
        let source = try bodyHomeViewText()
        // The day breakdown renders in `metricBreakdownChart`, placed below the hero
        // value row (which sits below the line chart) — so the big current value reads
        // directly under the line chart and the breakdown bars sit beneath it.
        let breakdownContainerStart = try XCTUnwrap(source.range(of: "private var metricBreakdownChart")?.lowerBound)
        let breakdownContainerBlock = String(source[breakdownContainerStart...].prefix(1_200))
        let breakdownStart = try XCTUnwrap(source.range(of: "struct BodyTrainingLoadIntervalBreakdownChart")?.lowerBound)
        let breakdownBlock = String(source[breakdownStart...].prefix(4_500))

        // Within the hero, the value row precedes the breakdown bars.
        let heroStart = try XCTUnwrap(source.range(of: "private var metricHero: some View")?.lowerBound)
        let heroEnd = try XCTUnwrap(
            source.range(of: "private var metricDetailCards", range: heroStart..<source.endIndex)?.lowerBound
        )
        let heroBlock = String(source[heroStart..<heroEnd])
        let valueRowIndex = try XCTUnwrap(heroBlock.range(of: "metricHeroValueRow")?.lowerBound)
        let breakdownIndex = try XCTUnwrap(heroBlock.range(of: "metricBreakdownChart")?.lowerBound)
        XCTAssertLessThan(valueRowIndex, breakdownIndex)

        XCTAssertTrue(breakdownContainerBlock.contains("if model.kind == .trainingLoad {"))
        XCTAssertTrue(breakdownContainerBlock.contains("BodyTrainingLoadIntervalBreakdownChart("))
        XCTAssertTrue(breakdownContainerBlock.contains("series: model.series"))
        XCTAssertTrue(breakdownContainerBlock.contains("selectedRange: selectedTrendRange"))
        XCTAssertTrue(breakdownBlock.contains("TrainingLoadIntervalBreakdown.entries("))
        XCTAssertTrue(breakdownBlock.contains("GeometryReader { geometry in"))
        XCTAssertTrue(breakdownBlock.contains("BodyGlassChip("))
        XCTAssertTrue(breakdownBlock.contains("dayCountText(for: entry.dayCount)"))
        XCTAssertTrue(breakdownBlock.contains("entry.interval.title"))
        XCTAssertTrue(breakdownBlock.contains("entry.interval.symbolName"))
    }

    func testTrainingLoadDetailShowsAboutYourIntervalCardAboveHelpText() throws {
        let source = try bodyHomeViewText()
        let cardsStart = try XCTUnwrap(source.range(of: "private var metricDetailCards: some View")?.lowerBound)
        let cardsEnd = try XCTUnwrap(
            source.range(of: "private var metricHeroValueRow", range: cardsStart..<source.endIndex)?.lowerBound
        )
        let cardsBlock = String(source[cardsStart..<cardsEnd])
        let intervalCardStart = try XCTUnwrap(cardsBlock.range(of: "trainingLoadIntervalCard(activeInterval:")?.lowerBound)
        let helpTextStart = try XCTUnwrap(
            cardsBlock.range(of: "helpTextCard", range: intervalCardStart..<cardsBlock.endIndex)?.lowerBound
        )
        let cardStart = try XCTUnwrap(source.range(of: "private func trainingLoadIntervalCard(")?.lowerBound)
        let cardEnd = try XCTUnwrap(
            source.range(of: "private func readinessWhyCard(", range: cardStart..<source.endIndex)?.lowerBound
        )
        let cardBlock = String(source[cardStart..<cardEnd])

        // Mirrors the readiness "About your score" card: the band list sits directly
        // above the About Training Load help-text card.
        XCTAssertLessThan(intervalCardStart, helpTextStart)
        XCTAssertTrue(cardBlock.contains(#"Text("About your interval")"#))
        XCTAssertTrue(cardBlock.contains("ForEach(TrainingLoadInterval.displayOrder, id: \\.self)"))
        XCTAssertTrue(cardBlock.contains("interval.rangeText"))
        XCTAssertTrue(cardBlock.contains("interval.explanation"))
        XCTAssertTrue(cardBlock.contains("BodyTrainingLoadIntervalPresentation.color(for: interval)"))
        XCTAssertTrue(cardBlock.contains(#"Text("Current")"#))
        // The Current chip follows the scrubbed point, falling back to the trend
        // chart's last plotted point (via the chart's active-value binding), and
        // to the live summary value only when the chart is empty.
        XCTAssertTrue(source.contains("private var activeTrainingLoadInterval: TrainingLoadInterval?"))
        XCTAssertTrue(source.contains("TrainingLoadInterval.interval(for: activeTrainingLoadTrendValue)"))
        XCTAssertTrue(source.contains("TrainingLoadInterval.interval(for: model.trainingLoadValue)"))
        XCTAssertTrue(source.contains("case .trainingLoad:\n            return $activeTrainingLoadTrendValue"))
    }

    func testHeartRateAndRespiratoryRateDayViewsDrawHourlyRangeBarsBehindTheAverageLine() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "private func chart(rangeBarWidth: CGFloat) -> some View")?.lowerBound)
        let chartEnd = try XCTUnwrap(
            source.range(of: "private var selectedBucket", range: chartStart..<source.endIndex)?.lowerBound
        )
        let chartBlock = String(source[chartStart..<chartEnd])
        let barsStart = try XCTUnwrap(chartBlock.range(of: "ForEach(rangeEntries)")?.lowerBound)
        let lineStart = try XCTUnwrap(
            chartBlock.range(of: "ForEach(lineSegments)", range: barsStart..<chartBlock.endIndex)?.lowerBound
        )

        // Bars must be emitted before the line/point marks so they render behind
        // them, and they carry the range chart's gray + capsule-end treatment.
        XCTAssertLessThan(barsStart, lineStart)
        XCTAssertTrue(chartBlock.contains("width: .fixed(rangeBarWidth)"))
        XCTAssertTrue(chartBlock.contains(".cornerRadius(rangeBarWidth / 2)"))
        XCTAssertTrue(chartBlock.contains(".foregroundStyle(Self.rangeBarColor)"))
        XCTAssertTrue(chartBlock.contains("bodyRangeChartPointSymbolSize(forBarWidth: rangeBarWidth)"))
        XCTAssertTrue(source.contains("private static let rangeBarColor = Color.secondary.opacity(0.24)"))
        // Only the two metrics whose long-range chart bars its min-max opt in, and
        // the domain has to grow to the extremes the bars reach or they clip at the
        // plot edges.
        XCTAssertTrue(source.contains("showsHourlyRangeBars: model.kind == .heartRate || model.kind == .respiratoryRate"))
        XCTAssertTrue(source.contains("let rangeEntries = showsHourlyRangeBars ? Self.makeRangeEntries(from: buckets) : []"))
        XCTAssertTrue(source.contains("rangeEntries.flatMap { [$0.lowValue, $0.highValue] }"))
    }

    func testVitalsCardDotsPreviewKeepsSkeletonWhileTheNightIsPending() throws {
        let source = try bodyHomeViewText()
        let previewStart = try XCTUnwrap(source.range(of: "private var dotsPreview: some View")?.lowerBound)
        let previewEnd = try XCTUnwrap(
            source.range(of: "struct DotPreviewLayout", range: previewStart..<source.endIndex)?.lowerBound
        )
        let previewBlock = String(source[previewStart..<previewEnd])

        // The three regions must keep drawing with no assessment, so the card fills
        // the skeleton in place instead of gaining a chart it didn't have.
        XCTAssertTrue(source.contains("|| chartPreviewStyle == .dots"))
        XCTAssertTrue(source.contains("var region: SleepVitalRegion?"))
        XCTAssertTrue(source.contains("private static let placeholderDotCount = VitalKind.allCases.count"))
        XCTAssertTrue(source.contains("PreviewDot(position: 0.5, region: nil)"))
        XCTAssertTrue(source.contains("return Color.secondary.opacity(0.45)"))
        XCTAssertTrue(source.contains("isAwaitingDots ? Color.secondary.opacity(0.24) : Color(red: 0.21, green: 0.30, blue: 0.45)"))
        // One ForEach over the resolved dots (skeleton or assessed) keeps ring
        // identity across the transition, so rings glide to their region instead
        // of the skeleton being replaced wholesale.
        XCTAssertEqual(previewBlock.occurrenceCount(of: "ForEach("), 1)
        XCTAssertTrue(previewBlock.contains("let dots = previewDots"))
        XCTAssertTrue(previewBlock.contains("dotColor(for: dot)"))
        XCTAssertTrue(previewBlock.contains("y: layout.dotY(for: dot.position)"))
        XCTAssertTrue(previewBlock.contains(".animation(refreshAnimation, value: dotEntries)"))
        // The three regions resize with the night's occupancy, so each must keep
        // a stable shape identity for SwiftUI to morph rather than replace it:
        // three unconditional RoundedRectangles, no Capsule, no ForEach over
        // regions, no `if` wrapping one of them.
        XCTAssertEqual(previewBlock.occurrenceCount(of: "RoundedRectangle(cornerRadius: layout.cornerRadius(for:"), 3)
        XCTAssertFalse(previewBlock.contains("Capsule("))
        XCTAssertTrue(previewBlock.contains("occupied: occupiedRegions(for: dots)"))
    }

    func testSummaryMetricValuesUseClockStyleNumericTransitions() throws {
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("struct BodyAnimatedMetricValueText: View"))
        XCTAssertTrue(source.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(source.contains(".contentTransition(reduceMotion ? .identity : .numericText())"))
        XCTAssertTrue(source.contains(".monospacedDigit()"))
        XCTAssertTrue(source.contains(".animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: value)"))
        XCTAssertGreaterThanOrEqual(source.occurrenceCount(of: "BodyAnimatedMetricValueText("), 3)
    }

    func testActivityRingGraphicAnimatesProgressWithCircularSweep() throws {
        let source = try text(at: "Body/Views/BodyActivityRingsDetailView.swift")
        let graphicStart = try XCTUnwrap(source.range(of: "private struct BodyActivityRingGraphic")?.lowerBound)
        let graphicBlock = String(source[graphicStart...].prefix(2_400))
        let arcStart = try XCTUnwrap(source.range(of: "private struct BodyActivityRingArc")?.lowerBound)
        let arcBlock = String(source[arcStart...].prefix(4_200))

        XCTAssertTrue(graphicBlock.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(graphicBlock.contains("private func sweepAnimation(ringIndex: Int) -> Animation?"))
        XCTAssertEqual(graphicBlock.occurrenceCount(of: "animation: sweepAnimation(ringIndex:"), 3)
        XCTAssertTrue(graphicBlock.contains(".smooth(duration: 0.75, extraBounce: 0)"))
        XCTAssertTrue(graphicBlock.contains(".delay(Double(ringIndex) * 0.05)"))
        XCTAssertTrue(source.contains("private struct BodyActivityRingHeadPosition: GeometryEffect"))
        XCTAssertTrue(source.contains("var animatableData: Double"))
        XCTAssertTrue(arcBlock.contains(".modifier(BodyActivityRingHeadPosition(progress: animatedHeadProgress, radius: radius))"))
        XCTAssertTrue(arcBlock.contains("setAnimatedProgress(nextProgress, animation: animation)"))
    }

    func testActivityRingsCalendarPadsScrollTargetsNotTheScrollTargetLayout() throws {
        let source = try text(at: "Body/Views/BodyActivityRingsDetailView.swift")
        // Bounded by the next declaration rather than a fixed character window: guards
        // in this file have silently stopped covering the lines they existed to protect
        // once the code above them grew.
        let viewStart = try XCTUnwrap(source.range(of: "struct BodyActivityRingsDetailView: View {")?.upperBound)
        let bodyEnd = try XCTUnwrap(
            source.range(of: "private func pinToCurrentMonth()", range: viewStart..<source.endIndex)?.lowerBound
        )
        // Comment lines are dropped first: the modifier chain is documented with a
        // comment that names `.scrollTargetLayout()` and the anchor, and a raw substring
        // search matches the prose before the code it describes.
        let bodyBlock = source[viewStart..<bodyEnd]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        // `.defaultScrollAnchor(.bottom, for: .alignment)` re-centers a scroll target
        // narrower than its container on BOTH axes (`.bottom` is UnitPoint(x: 0.5, y: 1)).
        // Padding the scroll-target layout instead of the month sections inside it left
        // every target inset by 18pt, and the anchor then added a matching 18pt of
        // contentOffset.x, so the calendar rendered 18pt left of center until the first
        // scroll re-clamped it. The padding must stay on the sections, which means it
        // appears BEFORE `.scrollTargetLayout()` in source order. Compared by position
        // rather than by matching indentation, so reflowing the chain can't break it.
        let paddingIndex = try XCTUnwrap(bodyBlock.range(of: ".padding(.horizontal, 18)")?.lowerBound)
        let scrollTargetIndex = try XCTUnwrap(bodyBlock.range(of: ".scrollTargetLayout()")?.lowerBound)
        XCTAssertLessThan(paddingIndex, scrollTargetIndex)
        XCTAssertEqual(bodyBlock.occurrenceCount(of: ".padding(.horizontal, 18)"), 1)
        XCTAssertTrue(bodyBlock.contains(".defaultScrollAnchor(.bottom, for: .alignment)"))
    }

    func testSupportedMetricDetailScreensExposeSwitchableDataSources() throws {
        let source = try bodyHomeViewText()
        let detailViewStart = try XCTUnwrap(source.range(of: "struct BodyHealthMetricDetailView")?.lowerBound)
        let pickerStart = try XCTUnwrap(source.range(of: "struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        // The detail view file is concatenated immediately before the picker sheet, so
        // bound the block by the picker declaration rather than a fixed char window the
        // ever-growing detail view keeps outrunning.
        let detailViewBlock = String(source[detailViewStart..<pickerStart])
        // 12k, not 8k: the custom-source rows (heart icon + Pro lock) grew the
        // picker enough that `updateHealthDataSource` — the last statement in the
        // file — sits ~350 chars inside the old window. This test asserts only
        // positives, so a window that runs past the file's end is harmless.
        let pickerBlock = String(source[pickerStart...].prefix(12_000))

        XCTAssertTrue(detailViewBlock.contains("model.kind.supportsHealthDataSourceSelection"))
        XCTAssertTrue(detailViewBlock.contains("workoutStore.selectedHealthDataSourceOption(for: model.kind)"))
        XCTAssertTrue(detailViewBlock.contains("BodyHealthDataSourcePickerSheet("))
        XCTAssertTrue(pickerBlock.contains("workoutStore.healthDataSourceOptions(for: kind)"))
        XCTAssertTrue(pickerBlock.contains("workoutStore.updateHealthDataSource(for: kind, option: option)"))
    }

    func testMetricDetailViewGatesProRangesAndDays() throws {
        let source = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")

        // Chart-range gate: non-Pro is clamped to Week, and the selector binds to that
        // effective range so a locked pill can't appear selected; locked taps route to
        // the paywall, not the binding.
        XCTAssertTrue(source.contains("isBodyProUnlocked ? selectedTrendRangeSelection : .recentWeek"))
        XCTAssertTrue(source.contains("get: { selectedTrendRange }"))
        XCTAssertTrue(source.contains("isProUnlocked: isBodyProUnlocked"))
        XCTAssertTrue(source.contains("onLockedRangeTap: { showBodyProPaywall = true }"))

        // Day-picker gate: a 3-day free window, and the effective selected day is clamped
        // so a locked day never renders.
        XCTAssertTrue(source.contains("static let freeDatePickerDayCount = 3"))
        XCTAssertTrue(source.contains("func isDatePickerDateLocked"))
        XCTAssertTrue(source.contains("func clampedDatePickerDay"))
        XCTAssertTrue(source.contains("clampedDatePickerDay(selectedMetricDate)"))
        XCTAssertTrue(source.contains("clampedDatePickerDay(selectedSleepDate)"))

        // Every day-selection surface routes through the shared guard, which opens the
        // paywall for a locked day *before* it can reach selectDate.
        let guardStart = try XCTUnwrap(source.range(of: "private func selectDatePickerDay")?.upperBound)
        let guardBlock = String(source[guardStart...].prefix(400))
        let paywallInGuard = try XCTUnwrap(guardBlock.range(of: "showBodyProPaywall = true"))
        let selectInGuard = try XCTUnwrap(guardBlock.range(of: "selectDate(date, for: picker)"))
        XCTAssertTrue(guardBlock.contains("isDatePickerDateLocked(date)"))
        XCTAssertLessThan(paywallInGuard.lowerBound, selectInGuard.lowerBound)
        // Both the date tiles and the Sleep Consistency chart call the guard, not selectDate.
        XCTAssertTrue(source.contains("selectDatePickerDay(dayStart, for: picker)"))
        XCTAssertTrue(source.contains("selectDatePickerDay(day, for: .sleep)"))
    }

    func testHealthDataSourcePickerRowsShowSourceNamesOnly() throws {
        let source = try bodyHomeViewText()
        let pickerStart = try XCTUnwrap(source.range(of: "struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        let pickerBlock = String(source[pickerStart...].prefix(8_000))

        XCTAssertTrue(pickerBlock.contains("Text(option.name)"))
        XCTAssertFalse(pickerBlock.contains("Only this source"))
        XCTAssertFalse(pickerBlock.contains("All available Apple Health sources"))
        XCTAssertFalse(pickerBlock.contains("Hide secondary comparison"))
        XCTAssertFalse(pickerBlock.contains("optionDetailText"))
    }

    func testHealthDataSourcePickerUsesTypedScopedUpdateState() throws {
        let source = try bodyHomeViewText()
        let pickerStart = try XCTUnwrap(source.range(of: "struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        let pickerBlock = String(source[pickerStart...].prefix(8_000))

        XCTAssertTrue(pickerBlock.contains("private enum SourceRole: Equatable"))
        XCTAssertTrue(pickerBlock.contains("private struct PendingSelection: Equatable"))
        XCTAssertTrue(pickerBlock.contains("@State private var updatingSelection: PendingSelection?"))
        XCTAssertTrue(pickerBlock.contains("role: SourceRole"))
        XCTAssertTrue(pickerBlock.contains("let isSelectionLocked = updatingSelection != nil"))
        XCTAssertTrue(pickerBlock.contains(".disabled(isSelected || isSelectionLocked)"))
        XCTAssertTrue(pickerBlock.contains("case .secondary:"))

        XCTAssertFalse(pickerBlock.contains("role: String"))
        XCTAssertFalse(pickerBlock.contains("updatingSelectionID"))
        XCTAssertFalse(pickerBlock.contains(".disabled(updatingSelectionID != nil || isSelected)"))
        XCTAssertFalse(pickerBlock.contains("let isSectionLocked = updatingSelection?.role == role"))
        XCTAssertFalse(pickerBlock.contains("role == \"secondary\""))
    }

    func testHealthDataSourcePickerStaysOpenAfterChangingSelection() throws {
        let source = try bodyHomeViewText()
        let pickerStart = try XCTUnwrap(source.range(of: "struct BodyHealthDataSourcePickerSheet")?.lowerBound)
        let pickerBlock = String(source[pickerStart...].prefix(8_000))
        let updateStart = try XCTUnwrap(pickerBlock.range(of: "private func updateSelection")?.lowerBound)
        let updateBlock = String(pickerBlock[updateStart...].prefix(1_200))

        XCTAssertTrue(pickerBlock.contains("Button(\"Done\")"))
        XCTAssertTrue(pickerBlock.contains("dismiss()"))
        XCTAssertTrue(updateBlock.contains("updatingSelection = nil"))
        XCTAssertFalse(updateBlock.contains("dismiss()"))
    }

    /// The "latest reading" queries must run inside the same window the daily
    /// trend charts are fetched over. An unbounded one is what let a card
    /// headline a value its own chart had no room for, at every range including
    /// Year — and it reads as a deliberate choice in source, so guard the shape
    /// rather than trusting a comment. Behavior itself is covered by
    /// `RecentTrendWindowTests`.
    func testLatestReadingQueriesAreBoundedToTheTrendWindow() throws {
        let engineSource = try healthKitFetchEngineText()
        let latestQuantityStart = try XCTUnwrap(
            engineSource.range(of: "private func latestQuantity(")?.lowerBound
        )
        let latestQuantityEnd = try XCTUnwrap(
            engineSource[latestQuantityStart...].range(of: "func fetchQuantitySampleSeries(")?.lowerBound
        )
        let latestQuantityBlock = String(engineSource[latestQuantityStart..<latestQuantityEnd])

        // Both ends bound: an unbounded upper end would let a post-anchor sample
        // headline a card whose chart is cut off at the anchor.
        XCTAssertTrue(latestQuantityBlock.contains("recentHealthTrendInterval(calendar: calendar)"))
        XCTAssertTrue(latestQuantityBlock.contains("startDate: interval.start"))
        XCTAssertTrue(latestQuantityBlock.contains("endDate: interval.end"))

        // The one derivation both the trend interval and the watch read from.
        XCTAssertTrue(
            engineSource.contains("BodyHealthTrendRange.recentTrendWindowStart(anchor: anchorOrDate, calendar: calendar)")
        )

        // The watch bounds its own local read the same way, so a recompute can
        // never reintroduce a reading older than the charts can show.
        let watchSource = try text(at: "BodyWatch/WatchDeltaFetcher.swift")
        XCTAssertTrue(watchSource.contains("BodyHealthTrendRange.recentTrendWindowStart(anchor: now, calendar: calendar)"))

        // ...and clears one that ages out afterwards at display time, because
        // `WatchComputeMerge` deliberately preserves a good local value when an
        // incoming push is blank.
        let snapshotSource = try text(at: "BodyWatchShared/Models/WatchMetricsSnapshot.swift")
        XCTAssertTrue(snapshotSource.contains("private func isOutOfTrendWindow("))
        XCTAssertTrue(snapshotSource.contains("static func recentTrendWindowStart(asOf now: Date) -> Date"))
    }

    func testHealthKitFetchesApplySourcePreferencesToRequestedMetrics() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let engineSource = try healthKitFetchEngineText()

        XCTAssertTrue(storeSource.contains("fetchHealthDataSourceOptions(calendar: calendar)"))
        XCTAssertTrue(engineSource.contains("sourcePredicate(for: sourceKind)"))
        XCTAssertTrue(engineSource.contains("combinedPredicate(startDate:"))
        XCTAssertTrue(engineSource.contains("sourceKind: .heartRate"))
        XCTAssertTrue(engineSource.contains("sourceKind: .sleep"))
        XCTAssertTrue(engineSource.contains("sourceKind: .basics"))
        XCTAssertTrue(engineSource.contains("sourceKind: .heartRateVariability"))
        XCTAssertTrue(engineSource.contains("sourceKind: .restingHeartRate"))
        XCTAssertTrue(engineSource.contains("sourceKind: .respiratoryRate"))
        XCTAssertTrue(engineSource.contains("sourceKind: .steps"))
        XCTAssertTrue(engineSource.contains("sourceKind: .oxygenSaturation"))
        XCTAssertTrue(engineSource.contains("sourceKind: .activeEnergy"))
        XCTAssertTrue(engineSource.contains("sourceKind: .restingEnergy"))
        XCTAssertTrue(engineSource.contains("sourceKind: .exerciseMinutes"))
        XCTAssertTrue(engineSource.contains("sourceKind: .wristTemperature"))
        XCTAssertTrue(engineSource.contains("sourceKind: .timeInDaylight"))
        XCTAssertTrue(engineSource.contains("case .oxygenSaturation:"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .bodyMass)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .bodyMassIndex)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .oxygenSaturation)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)"))
        XCTAssertTrue(engineSource.contains("HKObjectType.quantityType(forIdentifier: .appleExerciseTime)"))
        XCTAssertTrue(engineSource.contains("HKSourceQuery("))
        XCTAssertTrue(engineSource.contains("HKQuery.predicateForObjects(from: source)"))
        XCTAssertTrue(engineSource.contains("NSCompoundPredicate(orPredicateWithSubpredicates: sourcePredicates)"))
        XCTAssertFalse(engineSource.contains("HKQuery.predicateForObjects(from: Set(sources))"))
        XCTAssertTrue(engineSource.contains("BodyHealthDataSourceOption.individualSourceIdentityKey"))
        XCTAssertTrue(engineSource.contains("BodyHealthDataSourceOption.individualSourceID"))
        // Every source registers BOTH identity forms (plain bundle-ID and
        // name-disambiguated) so an ID persisted by the device that saw
        // same-bundle duplicates still resolves on a device that discovers
        // only the selected source.
        XCTAssertTrue(engineSource.contains("sourcesByID[plainID, default: []].append(source)"))
        XCTAssertTrue(engineSource.contains("sourcesByID[disambiguatedID, default: []].append(source)"))
        XCTAssertFalse(engineSource.contains("sourcesByID[source.bundleIdentifier] = [source]"))
    }

    func testSourceSelectableBarAndRangeDetailsUsePrimarySecondaryComparisonCharts() throws {
        let homeSource = try bodyHomeViewText()
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let trendCardStart = try XCTUnwrap(homeSource.range(of: "private func metricTrendChart")?.lowerBound)
        let trendCardBlock = String(homeSource[trendCardStart...].prefix(10_000))
        let comparisonChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthSourceComparisonBarChart")?.lowerBound)
        let comparisonChartBlock = String(homeSource[comparisonChartStart...].prefix(13_000))
        let rangeComparisonChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthSourceComparisonRangeChart")?.lowerBound)
        let rangeComparisonChartBlock = String(homeSource[rangeComparisonChartStart...].prefix(12_000))
        let rangeBandChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHeartRateRangeTrendChart")?.lowerBound)
        let rangeBandChartBlock = String(homeSource[rangeBandChartStart...].prefix(20_000))

        // The source legend moved from the trend-card header to the hero value row
        // (`heroValueTrailing`); the comparison charts stay in `metricTrendChart`.
        XCTAssertTrue(homeSource.contains("BodyHealthSourceLegend("))
        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceComparisonBarChart("))
        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceComparisonRangeChart("))
        XCTAssertTrue(trendCardBlock.contains("model.kind.usesSourceComparisonRangeBandLineChart"))
        XCTAssertTrue(trendCardBlock.contains("secondaryRangeSeries: sourceRangeComparisonTrend.secondary.series"))
        XCTAssertTrue(trendCardBlock.contains("sourceComparisonTrend"))
        XCTAssertTrue(trendCardBlock.contains("sourceRangeComparisonTrend"))
        XCTAssertTrue(homeSource.contains("Color(red: 0.58, green: 0.36, blue: 0.98)"))
        XCTAssertTrue(appearanceSource.contains("var usesSourceComparisonRangeBandLineChart: Bool"))
        XCTAssertTrue(comparisonChartBlock.contains("chartDate: point.date.addingTimeInterval"))
        // The Week pair is nudged fully into the day's column (both bars right of the
        // midnight gridline) instead of straddling it.
        XCTAssertTrue(comparisonChartBlock.contains("let pairShift: TimeInterval = selectedRange.sourceComparisonChartAggregationDayCount == 1 ? dateOffset * 2 : 0"))
        XCTAssertTrue(comparisonChartBlock.contains("chartDate: point.date.addingTimeInterval(pairShift - dateOffset)"))
        XCTAssertTrue(rangeComparisonChartBlock.contains("let pairShift: TimeInterval = selectedRange.sourceComparisonChartAggregationDayCount == 1 ? dateOffset * 2 : 0"))
        XCTAssertTrue(comparisonChartBlock.contains("x: .value(\"Date\", entry.chartDate)"))
        XCTAssertFalse(comparisonChartBlock.contains(".position(by: .value(\"Source\", entry.sourceRole.rawValue), axis: .horizontal)"))
        XCTAssertTrue(comparisonChartBlock.contains("sourceComparisonChartBarWidth(forAvailableWidth:"))
        XCTAssertTrue(comparisonChartBlock.contains("sourceComparisonChartCalendarPoints(to: selectedRange)"))
        XCTAssertTrue(comparisonChartBlock.contains("BodyChartSelectionValue("))
        XCTAssertTrue(rangeBandChartBlock.contains("secondaryRangePoints"))
        XCTAssertTrue(rangeBandChartBlock.contains("BarMark("))
        XCTAssertTrue(rangeBandChartBlock.contains("series: .value(\"Segment\", segment.id)"))
        XCTAssertTrue(rangeBandChartBlock.contains("BodyChartSelectionValue("))
        XCTAssertTrue(rangeComparisonChartBlock.contains("sourceComparisonRangeChartBarWidth(forAvailableWidth:"))
        XCTAssertTrue(rangeComparisonChartBlock.contains("sourceComparisonChartCalendarPoints(to: selectedRange)"))
        XCTAssertTrue(rangeComparisonChartBlock.contains("x: .value(\"Date\", entry.chartDate)"))
        XCTAssertTrue(storeSource.contains("func sourceComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceComparisonTrend?"))
        XCTAssertTrue(storeSource.contains("func sourceRangeComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceRangeComparisonTrend?"))
    }

    func testSourceSelectableLineDetailsUsePrimarySecondaryComparisonLines() throws {
        let homeSource = try bodyHomeViewText()
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let trendCardStart = try XCTUnwrap(homeSource.range(of: "private func metricTrendChart")?.lowerBound)
        let trendCardBlock = String(homeSource[trendCardStart...].prefix(9_000))
        let lineComparisonChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthSourceComparisonLineChart")?.lowerBound)
        // 12k: the floating-callout reporter added ~0.5k to the struct's body, pushing
        // `selectedValues` (the BodyChartSelectionValue construction) past the old 10k.
        let lineComparisonChartBlock = String(homeSource[lineComparisonChartStart...].prefix(16_000))

        XCTAssertTrue(appearanceSource.contains("var usesSourceComparisonLineChart: Bool"))
        XCTAssertTrue(trendCardBlock.contains("sourceLineComparisonTrend"))
        XCTAssertTrue(trendCardBlock.contains("BodyHealthSourceComparisonLineChart("))
        XCTAssertTrue(lineComparisonChartBlock.contains("comparison.primary.series.lineChartCalendarPoints(to: selectedRange)"))
        XCTAssertTrue(lineComparisonChartBlock.contains("comparison.secondary.series.lineChartCalendarPoints(to: selectedRange)"))
        XCTAssertTrue(lineComparisonChartBlock.contains("series: .value(\"Segment\", segment.id)"))
        XCTAssertTrue(lineComparisonChartBlock.contains("BodyChartSelectionValue("))
        XCTAssertTrue(storeSource.contains("func sourceLineComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceComparisonTrend?"))
    }

    func testSleepStageComparisonCardsShowTrailingSourceLabel() throws {
        let homeSource = try bodyHomeViewText()
        let selectedSleepCardsStart = try XCTUnwrap(
            homeSource.range(of: "private var selectedSleepCards: some View")?.lowerBound
        )
        let selectedSleepCardsBlock = String(homeSource[selectedSleepCardsStart...].prefix(2_500))
        let sleepStageCardStart = try XCTUnwrap(homeSource.range(of: "private func sleepStageCard")?.lowerBound)
        let sleepStageCardBlock = String(homeSource[sleepStageCardStart...].prefix(2_500))
        let sleepStageCardAndSummaryBlock = String(homeSource[sleepStageCardStart...].prefix(5_500))

        XCTAssertTrue(selectedSleepCardsBlock.contains("sourceName: sourceLineComparisonTrend.primary.sourceName"))
        XCTAssertTrue(selectedSleepCardsBlock.contains("sourceName: sourceLineComparisonTrend.secondary.sourceName"))
        XCTAssertFalse(selectedSleepCardsBlock.contains("title: \"Sleep Stages -"))
        XCTAssertTrue(sleepStageCardBlock.contains("sourceName: String? = nil"))
        XCTAssertTrue(sleepStageCardBlock.contains("HStack(alignment: .firstTextBaseline)"))
        XCTAssertTrue(sleepStageCardBlock.contains("Spacer(minLength: 12)"))
        XCTAssertTrue(sleepStageCardBlock.contains("if let sourceName"))
        XCTAssertTrue(sleepStageCardBlock.contains("Text(sourceName)"))
        XCTAssertTrue(sleepStageCardBlock.contains(".font(.system(.caption, design: .rounded))"))
        XCTAssertTrue(sleepStageCardBlock.contains(".foregroundColor(.secondary)"))

        let sleepChartStart = try XCTUnwrap(homeSource.range(of: "struct BodySleepStageChart")?.lowerBound)
        // The date-switch choreography (flat Core band + flatten state) sits
        // ahead of the axis builders now, so the inspected window is wider.
        let sleepChartBlock = String(homeSource[sleepChartStart...].prefix(8_000))
        XCTAssertTrue(sleepChartBlock.contains("Text(stage.axisLabel)"))
        // The summary call now lives inside the tap-to-toggle Button (durations <-> optimal
        // ranges), a little deeper in the card body, so widen the inspected window.
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("sleepStageDurationSummary(snapshot)"))
        // The restorative-sleep breakdown wraps the stage row in a VStack and
        // spaces stages with explicit Spacers (HStack(spacing: 0) + enumerated
        // ForEach) rather than the old fixed-spacing HStack.
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("HStack(spacing: 0)"))
        XCTAssertFalse(sleepStageCardAndSummaryBlock.contains("LazyVGrid"))
        XCTAssertFalse(sleepStageCardAndSummaryBlock.contains("GridItem(.flexible(), spacing: 10)"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("ForEach(Array(SleepStage.allCases.enumerated()), id: \\.element)"))
        XCTAssertFalse(sleepStageCardAndSummaryBlock.contains("Text(stage.displayName)"))
        XCTAssertFalse(sleepStageCardAndSummaryBlock.contains("Circle()"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("Rectangle()"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains(".frame(width: 28, height: 3)"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("BodyValueFormat.durationText(for: snapshot.duration(for: stage))"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains("VStack(alignment: .center, spacing: 7)"))
        XCTAssertTrue(sleepStageCardAndSummaryBlock.contains(".frame(maxWidth: .infinity, alignment: .center)"))
    }

    func testSleepDetailHeaderValuesUseNumericTransitions() throws {
        let source = try bodyHomeViewText()
        let sleepStageCardStart = try XCTUnwrap(source.range(of: "private func sleepStageCard")?.lowerBound)
        let sleepStageCardEnd = try XCTUnwrap(
            source.range(of: "private func sleepStageDurationSummary", range: sleepStageCardStart..<source.endIndex)?.lowerBound
        )
        let sleepStageCardBlock = String(source[sleepStageCardStart..<sleepStageCardEnd])
        let sleepConsistencyCardStart = try XCTUnwrap(source.range(of: "private var sleepConsistencyCard")?.lowerBound)
        let sleepConsistencyCardEnd = try XCTUnwrap(
            source.range(of: "private var sleepConsistencyChartModel", range: sleepConsistencyCardStart..<source.endIndex)?.lowerBound
        )
        let sleepConsistencyCardBlock = String(source[sleepConsistencyCardStart..<sleepConsistencyCardEnd])

        let durationSummaryStart = sleepStageCardEnd
        let durationSummaryEnd = try XCTUnwrap(
            source.range(of: "private func sleepStageBreakdownAccessibilityLabel", range: durationSummaryStart..<source.endIndex)?.lowerBound
        )
        let durationSummaryBlock = String(source[durationSummaryStart..<durationSummaryEnd])

        XCTAssertTrue(sleepStageCardBlock.contains("BodyAnimatedMetricValueText("))
        XCTAssertTrue(sleepStageCardBlock.contains("value: BodyValueFormat.sleepDurationText(for: snapshot.mergedAsleepDuration)"))
        XCTAssertTrue(sleepConsistencyCardBlock.contains("BodyAnimatedMetricValueText("))
        XCTAssertTrue(sleepConsistencyCardBlock.contains(#"value: "\(consistencyPercentage)%""#))

        // The plain-durations half of the breakdown toggle rolls its digits over
        // on a day switch, like the optimal-range bars it swaps with.
        XCTAssertTrue(durationSummaryBlock.contains(".bodyLegendNumberFlip(value: durationText)"))
        XCTAssertTrue(durationSummaryBlock.contains(".bodyLegendNumberFlip(value: restorativeText)"))
    }

    func testSleepStageBreakdownTogglesToOptimalRangeChart() throws {
        let source = try bodyHomeViewText()
        let appearanceSource = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private func sleepStageCard")?.lowerBound)
        let cardEnd = try XCTUnwrap(
            source.range(of: "private func sleepStageDurationSummary", range: cardStart..<source.endIndex)?.lowerBound
        )
        let cardBlock = String(source[cardStart..<cardEnd])

        // Persisted toggle key + property (defaults to the existing duration summary).
        XCTAssertTrue(appearanceSource.contains(#"static let sleepStageBreakdownShowsOptimalRangesKey = "sleepStageBreakdownShowsOptimalRanges""#))
        XCTAssertTrue(source.contains("@AppStorage(BodyAppearancePreference.sleepStageBreakdownShowsOptimalRangesKey) private var sleepStageShowsOptimalRanges = true"))

        // Tap-to-swap wiring lives inside sleepStageCard (durations <-> optimal ranges).
        XCTAssertTrue(cardBlock.contains("if sleepStageShowsOptimalRanges {"))
        XCTAssertTrue(cardBlock.contains("BodySleepStageOptimalRangeChart(snapshot: snapshot)"))
        XCTAssertTrue(cardBlock.contains("sleepStageDurationSummary(snapshot)"))
        XCTAssertTrue(cardBlock.contains("sleepStageShowsOptimalRanges.toggle()"))
        XCTAssertTrue(cardBlock.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(cardBlock.contains(".buttonStyle(.plain)"))

        // The collapsed Button keeps the per-stage values readable to VoiceOver via a spelled-out label.
        XCTAssertTrue(cardBlock.contains(".accessibilityLabel(sleepStageBreakdownAccessibilityLabel(snapshot))"))
        XCTAssertTrue(source.contains("private func sleepStageBreakdownAccessibilityLabel"))
        XCTAssertFalse(cardBlock.contains(#".accessibilityLabel(sleepStageShowsOptimalRanges ? "Stage optimal ranges""#))

        // New chart + display-only optimal bands (percent of time in bed).
        XCTAssertTrue(source.contains("struct BodySleepStageOptimalRangeChart: View"))
        XCTAssertTrue(source.contains("var optimalPercentageRange: ClosedRange<Double>"))
        XCTAssertTrue(source.contains("return 0.00...0.05"))
        XCTAssertTrue(source.contains("return 0.20...0.25"))
        XCTAssertTrue(source.contains("return 0.45...0.55"))
        XCTAssertTrue(source.contains("return 0.13...0.23"))
        XCTAssertTrue(source.contains(#"Text("Optimal Range")"#))

        // Bars grow/shrink when the selected day changes, gated on reduce-motion.
        let chartStart = try XCTUnwrap(source.range(of: "struct BodySleepStageOptimalRangeChart")?.lowerBound)
        let chartEnd = try XCTUnwrap(
            source.range(of: "struct BodySleepConsistencyChart", range: chartStart..<source.endIndex)?.lowerBound
        )
        let chartBlock = String(source[chartStart..<chartEnd])
        XCTAssertTrue(chartBlock.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(chartBlock.contains(".animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: fraction)"))

        // Percent and duration columns roll their digits over with the bars.
        XCTAssertEqual(chartBlock.components(separatedBy: ".bodyLegendNumberFlip(value: percentText)").count - 1, 2)
        XCTAssertEqual(chartBlock.components(separatedBy: ".bodyLegendNumberFlip(value: durationText)").count - 1, 2)
    }

    func testSourceSelectableDayChartsUsePrimarySecondaryComparisonLines() throws {
        let homeSource = try bodyHomeViewText()
        let engineSource = try healthKitFetchEngineText()
        let snapshotSource = try healthSummarySnapshotText()
        let dayChartCardStart = try XCTUnwrap(homeSource.range(of: "private var metricDayChartCard: some View")?.lowerBound)
        // Bounded by the NEXT declaration rather than a character count: a fixed
        // prefix silently drops the assertions below as soon as a branch of this
        // property grows, which turned a real guard into a passing no-op.
        let dayChartCardEnd = try XCTUnwrap(
            homeSource.range(of: "private var metricWarningCards", range: dayChartCardStart..<homeSource.endIndex)?.lowerBound
        )
        let dayChartCardBlock = String(homeSource[dayChartCardStart..<dayChartCardEnd])
        let dayChartStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthMetricDayChart")?.lowerBound)
        let dayChartEnd = try XCTUnwrap(
            homeSource.range(of: "struct BodyHealthMetricDayRangeEntry", range: dayChartStart..<homeSource.endIndex)?.lowerBound
        )
        let dayChartBlock = String(homeSource[dayChartStart..<dayChartEnd])

        XCTAssertTrue(dayChartCardBlock.contains("BodyHealthSourceLegend("))
        XCTAssertTrue(dayChartCardBlock.contains("selectedMetricSecondaryDaySeries"))
        XCTAssertTrue(dayChartCardBlock.contains("secondarySeries: selectedMetricSecondaryDaySeries"))
        XCTAssertTrue(dayChartBlock.contains("secondaryHourlyBuckets"))
        XCTAssertTrue(dayChartBlock.contains("series: .value(\"Segment\", segment.id)"))
        XCTAssertTrue(dayChartBlock.contains("BodyChartSelectionValue("))
        XCTAssertTrue(snapshotSource.contains("func secondaryDaySeries(for kind: HealthMetricKind) -> HealthTrendSeries"))
        XCTAssertTrue(engineSource.contains("func fetchSecondaryDaySamples("))
        XCTAssertTrue(engineSource.contains("for kind: HealthMetricKind,"))
        XCTAssertTrue(engineSource.contains("let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)"))
        XCTAssertTrue(engineSource.contains("sourceOption: secondaryOption"))
        XCTAssertTrue(engineSource.contains("trends.heartRateDaySamplesSecondary = resolvedTrend(await heartRateDaySamplesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.heartRateVariabilityDaySamplesSecondary = resolvedTrend(await heartRateVariabilityDaySamplesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.oxygenSaturationDaySamplesSecondary = resolvedTrend(await oxygenSaturationDaySamplesSecondary"))
        // Resting heart rate deliberately has NO intraday fetch: it is absent from
        // `supportsMetricDayView` / `HealthMetricKind.dayViewKinds`, so its day
        // samples were queried and persisted but never rendered.
        XCTAssertFalse(engineSource.contains("trends.restingHeartRateDaySamplesSecondary = resolvedTrend(await"))
        XCTAssertFalse(engineSource.contains("trends.restingHeartRateDaySamples = resolvedTrend(await"))
    }

    /// The per-metric refresh fetches comparison-source day samples incrementally
    /// (48h trailing overlap merged onto the cache) for the sample-based kinds, and
    /// deliberately NOT for the hourly cumulative kinds — their current-hour bucket
    /// overlaps and `mergeIntradaySamples` has no bucket dedupe, so an incremental
    /// merge would double-count today's energy/steps.
    func testSecondaryDaySamplesFetchIncrementallyExceptHourlyBuckets() throws {
        let engineSource = try healthKitFetchEngineText()

        XCTAssertTrue(engineSource.contains("private func fetchIncrementalSecondaryDaySamples("))
        // One definition plus one call site per sample-based kind (hr, hrv, spo2).
        XCTAssertEqual(engineSource.occurrenceCount(of: "fetchIncrementalSecondaryDaySamples("), 4)
        XCTAssertTrue(engineSource.contains("async let activeEnergyDaySamplesSecondary = fetchSecondaryDaySamples("))
        XCTAssertTrue(engineSource.contains("async let stepsDaySamplesSecondary = fetchSecondaryDaySamples("))
    }

    /// The source mutators push a new selection into the engine BEFORE they wait out
    /// an in-flight refresh, so the incremental day-sample merge can splice
    /// new-source points onto old-source ones. `refreshHealthMetric` must detect the
    /// mid-fetch signature change and drop the fetched day samples rather than
    /// publish — and persist — a mixed-source series.
    func testMetricRefreshDropsDaySamplesWhenSelectionChangesMidFetch() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        // Anchored on `performHealthMetricRefresh`, which now owns the fetch and
        // the mid-fetch signature check: `refreshHealthMetric` keeps only the
        // authorization step and the deadline wrapper, so slicing from there
        // measured past these lines instead of guarding them.
        let start = try XCTUnwrap(storeSource.range(of: "func performHealthMetricRefresh(")?.lowerBound)
        let block = String(storeSource[start...].prefix(3_000))

        XCTAssertTrue(block.contains("let capturedDaySampleSignatures = currentDaySampleSignatures()"))
        XCTAssertTrue(block.contains("currentDaySampleSignatures() == capturedDaySampleSignatures"))
        XCTAssertTrue(block.contains("strippingDaySamples()"))
    }

    /// Every `HealthDashboardSnapshotStore.save` rewrites the day-sample sidecar from
    /// the trends it is handed, and an empty payload overwrites an existing file. The
    /// warm workout-only resume can reach a save via
    /// `reapplyActivityReadinessAfterWorkouts`, so it must hydrate first or a
    /// relaunch inside the refresh TTL wipes the intraday cache off disk.
    func testWarmWorkoutRefreshHydratesDaySamplesBeforeAnyPersist() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let start = try XCTUnwrap(
            storeSource.range(of: "        reusesCachedWorkoutHeartRate: Bool = false\n    ) async {")?.lowerBound
        )
        let block = String(storeSource[start...].prefix(1_200))
        let hydrate = try XCTUnwrap(block.range(of: "await hydratePersistedDaySamplesIfNeeded()")?.lowerBound)
        let summaryGate = try XCTUnwrap(block.range(of: "if updatesHealthSummary {")?.lowerBound)

        XCTAssertLessThan(hydrate, summaryGate, "Hydration must run on both refresh paths, not only the dashboard one.")
    }

    /// Hydration reuses ONE memoized sidecar load for the whole session, so anything
    /// that invalidates comparison series has to be re-applied at merge time or the
    /// memo quietly restores them. Entitlement and the primary-collapse rule are not
    /// in the persisted signatures, so the store must pass them live.
    func testHydrationDropsComparisonSeriesTheCurrentSelectionResolvesAway() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")

        XCTAssertTrue(storeSource.contains("comparisonDisabledKinds: currentComparisonDisabledKinds()"))
        XCTAssertTrue(storeSource.contains("selectedSecondaryHealthDataSourceOption(for: $0).isNoComparison"))
    }

    /// The entitlement handler's invalidation has to reach the memoized sidecar
    /// load, not just `healthTrends` and the file — otherwise the corrective refresh
    /// it kicks off re-merges the pre-flip comparison samples from the memo and
    /// re-persists them. Order matters: hydrate (populate the memo + restore the
    /// primary scope), clear, strip the memo, then persist.
    func testProEntitlementChangeInvalidatesMemoizedComparisonDaySamples() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let start = try XCTUnwrap(storeSource.range(of: "BodyProEntitlement.didChangeNotification")?.lowerBound)
        let block = String(storeSource[start...].prefix(2_000))

        let hydrate = try XCTUnwrap(block.range(of: "await self.hydratePersistedDaySamplesIfNeeded()")?.lowerBound)
        let clear = try XCTUnwrap(block.range(of: "clearingSecondarySeries()")?.lowerBound)
        let invalidate = try XCTUnwrap(block.range(of: "await self.invalidateMemoizedComparisonDaySamples()")?.lowerBound)
        let persist = try XCTUnwrap(block.range(of: "self.persistDaySampleSidecar()")?.lowerBound)

        XCTAssertLessThan(hydrate, clear)
        XCTAssertLessThan(clear, invalidate)
        XCTAssertLessThan(invalidate, persist)
        // Re-point the memo, never nil it: a nil forces a re-read that can beat the
        // asynchronous sidecar write above and restore what was just cleared.
        XCTAssertTrue(storeSource.contains("persistedDaySamplesHydration = Task { stripped }"))
        XCTAssertFalse(block.contains("persistedDaySamplesHydration = nil"))
    }

    /// The Body Pro paywall is a sheet presented from the metric detail view, so
    /// buying or restoring leaves that view mounted. The entitlement handler empties
    /// the comparison day samples on any flip, so the detail's lazy intraday loader
    /// must be keyed on entitlement — a bare `.task` would not re-run and the paid
    /// comparison line would stay missing until the user left and reopened the page.
    func testMetricDetailIntradayLoaderRerunsOnEntitlementFlip() throws {
        let detailSource = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")

        // The paywall really is presented from this view (the premise for the key).
        XCTAssertTrue(detailSource.contains("$showBodyProPaywall"))
        XCTAssertTrue(detailSource.contains("""
        .task(id: isBodyProUnlocked) {
                    await workoutStore.loadIntradayMetricSamplesIfNeeded(model.kind)
                }
        """))
    }

    /// The intraday sidecar is the only cached series not restored synchronously in
    /// the store's init, so app entry hydrates it before the refresh sync. It has to
    /// be the SAME task body — sibling `.task` modifiers run concurrently, and the
    /// read must win against any save the refresh triggers.
    func testAppEntryHydratesDaySamplesBeforeSync() throws {
        let appSource = try text(at: "Body/BodyApp.swift")
        let hydrate = try XCTUnwrap(appSource.range(of: "hydratePersistedDaySamplesIfNeeded()")?.lowerBound)
        let sync = try XCTUnwrap(appSource.range(of: "await workoutStore.syncWhenAppBecomesActive()")?.lowerBound)

        XCTAssertLessThan(hydrate, sync)
        XCTAssertTrue(appSource.contains("if !workoutStore.needsInitialHealthDataLoad {"))
    }

    func testChartLegendHeadersFillAvailableWidth() throws {
        let source = try bodyHomeViewText()
        // The trend chart's "Last 7 Days" header was removed when it folded into the
        // gradient hero; only the metric day-chart card still carries a legend header.
        let dayChartCardStart = try XCTUnwrap(source.range(of: "private var metricDayChartCard: some View")?.lowerBound)
        let dayChartStart = try XCTUnwrap(
            source.range(of: "if selectedMetricDaySeries.isEmpty", range: dayChartCardStart..<source.endIndex)?.lowerBound
        )
        let dayHeaderBlock = String(source[dayChartCardStart..<dayChartStart])

        XCTAssertTrue(dayHeaderBlock.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
    }

    func testSourceLegendContentIsTrailingAligned() throws {
        let source = try bodyHomeViewText()
        let legendStart = try XCTUnwrap(source.range(of: "struct BodyHealthSourceLegend: View")?.lowerBound)
        let comparisonChartStart = try XCTUnwrap(
            source.range(of: "struct BodyHealthSourceComparisonLineChart", range: legendStart..<source.endIndex)?.lowerBound
        )
        let legendBlock = String(source[legendStart..<comparisonChartStart])

        XCTAssertTrue(legendBlock.contains("VStack(alignment: .trailing, spacing: 7)"))
        XCTAssertTrue(legendBlock.contains(".frame(maxWidth: 180, alignment: .trailing)"))
        XCTAssertFalse(legendBlock.contains("VStack(alignment: .leading, spacing: 7)"))
        XCTAssertFalse(legendBlock.contains(".frame(maxWidth: 180, alignment: .leading)"))
    }

    func testTwoLineHeroLegendsUseBottomRowAnchoring() throws {
        let source = try bodyHomeViewText()
        let sourceLegendStart = try XCTUnwrap(source.range(of: "struct BodyHealthSourceLegend: View")?.lowerBound)
        let sourceLegendEnd = try XCTUnwrap(
            source.range(of: "struct BodyHealthSourceComparisonLineChart", range: sourceLegendStart..<source.endIndex)?.lowerBound
        )
        let sourceLegendBlock = String(source[sourceLegendStart..<sourceLegendEnd])
        let basicsLegendStart = try XCTUnwrap(source.range(of: "struct BodyBasicsTrendLegend: View")?.lowerBound)
        let basicsLegendEnd = try XCTUnwrap(
            source.range(of: "struct BodyChartSelectionValue", range: basicsLegendStart..<source.endIndex)?.lowerBound
        )
        let basicsLegendBlock = String(source[basicsLegendStart..<basicsLegendEnd])
        let heroTrailingStart = try XCTUnwrap(source.range(of: "private var heroValueTrailing: some View")?.lowerBound)
        let heroTrailingEnd = try XCTUnwrap(
            source.range(of: "private func metricTrendChart", range: heroTrailingStart..<source.endIndex)?.lowerBound
        )
        let heroTrailingBlock = String(source[heroTrailingStart..<heroTrailingEnd])

        XCTAssertTrue(sourceLegendBlock.contains("ForEach(items)"))
        XCTAssertFalse(sourceLegendBlock.contains("ForEach(orderedItems)"))
        XCTAssertTrue(sourceLegendBlock.contains(".alignmentGuide(.firstTextBaseline) { dimensions in"))
        XCTAssertTrue(sourceLegendBlock.contains("dimensions[.lastTextBaseline]"))
        XCTAssertFalse(sourceLegendBlock.contains("dimensions[.firstTextBaseline]"))
        XCTAssertTrue(basicsLegendBlock.contains(".alignmentGuide(.firstTextBaseline) { dimensions in"))
        XCTAssertTrue(basicsLegendBlock.contains("dimensions[.lastTextBaseline]"))
        XCTAssertTrue(heroTrailingBlock.contains("BodyChartBaselineLegend()"))
        XCTAssertTrue(heroTrailingBlock.contains(".alignmentGuide(.firstTextBaseline) { dimensions in"))
        XCTAssertTrue(heroTrailingBlock.contains("dimensions[.lastTextBaseline]"))
        XCTAssertFalse(source.contains("sourceLabelSortOrder"))
        XCTAssertEqual(
            source.occurrenceCount(of: ".sorted { $0.sourceRole.rawValue < $1.sourceRole.rawValue }"),
            3
        )
    }

    func testBasicsLegendMatchesTrailingSourceLegendStyle() throws {
        let source = try bodyHomeViewText()
        let legendStart = try XCTUnwrap(source.range(of: "struct BodyBasicsTrendLegend: View")?.lowerBound)
        let selectionValueStart = try XCTUnwrap(
            source.range(of: "struct BodyChartSelectionValue", range: legendStart..<source.endIndex)?.lowerBound
        )
        let legendBlock = String(source[legendStart..<selectionValueStart])

        XCTAssertTrue(legendBlock.contains("VStack(alignment: .trailing, spacing: 7)"))
        XCTAssertTrue(legendBlock.contains(".frame(maxWidth: 180, alignment: .trailing)"))
        XCTAssertTrue(legendBlock.contains("HStack(spacing: 7)"))
        XCTAssertTrue(legendBlock.contains(".frame(width: 9, height: 9)"))
        XCTAssertTrue(legendBlock.contains(".font(.system(.subheadline, design: .rounded))"))
        XCTAssertTrue(legendBlock.contains(".minimumScaleFactor(0.68)"))
        XCTAssertFalse(legendBlock.contains("VStack(alignment: .leading, spacing: 5)"))
        XCTAssertFalse(legendBlock.contains(".padding(.trailing"))
        XCTAssertFalse(legendBlock.contains("basicsLegendTrailingAxisGutter"))
    }

    func testBasicsTrendChartKeepsTopAxisBelowLegendBand() throws {
        let source = try bodyHomeViewText()
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyBasicsTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(18_000))

        XCTAssertTrue(chartBlock.contains("private let normalizedYDomain = 0.0...1.1"))
        XCTAssertTrue(chartBlock.contains(".chartYScale(domain: normalizedYDomain)"))
        XCTAssertFalse(chartBlock.contains(".chartYScale(domain: 0...1)"))
    }

    func testBasicsChartsMorphAcrossRangeSwitchesLikeTheOtherTrendCharts() throws {
        let source = try text(at: "Body/Views/Health/Charts/BasicsCharts.swift")

        // A per-range id replaces the chart on every switch, which pops every
        // mark; both charts must keep a stable identity and animate instead.
        XCTAssertFalse(source.contains(".id(selectedRange.rawValue)"))
        XCTAssertTrue(source.contains(".id(\"basics-weight-body-fat\")"))
        XCTAssertTrue(source.contains(".id(\"basics-body-mass-index\")"))
        XCTAssertEqual(
            source.occurrenceCount(of: ".animation(reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0), value: selectedRange)"),
            2
        )
        // Every range's points stay resident, off-range ones invisible.
        XCTAssertEqual(source.occurrenceCount(of: "BodyHealthMetricTrendChart.makeTrendMarkEntries("), 3)
        XCTAssertEqual(source.occurrenceCount(of: "BodyHealthMetricTrendChart.makeTrendLineSegments("), 3)
        XCTAssertEqual(source.occurrenceCount(of: ".opacity(entry.showsDot ? 1 : 0)"), 6)
        XCTAssertEqual(source.occurrenceCount(of: ".accessibilityHidden(!entry.showsDot)"), 6)
        // Weight and body fat share segment start dates: unprefixed ids would
        // put both metrics in one series and join the two lines into one.
        XCTAssertTrue(source.contains("series: .value(\"Segment\", \"weight-\\(segment.id)\")"))
        XCTAssertTrue(source.contains("series: .value(\"Segment\", \"body-fat-\\(segment.id)\")"))
        XCTAssertFalse(source.contains("series: .value(\"Metric\", \"Weight\")"))
        XCTAssertFalse(source.contains("series: .value(\"Metric\", \"Body Fat\")"))
    }

    func testChartLegendNumbersFlipWhenTheirValuesChange() throws {
        let helpers = try text(at: "Body/Views/Health/ChartHelpers.swift")
        let comparison = try text(at: "Body/Views/Health/Charts/SourceComparisonCharts.swift")
        let detail = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")

        // Same motion as the hero value's digit flip, so a range switch rolls
        // the labels over in step with the chart they sit beside.
        XCTAssertTrue(helpers.contains("struct BodyLegendNumberFlip: ViewModifier"))
        XCTAssertTrue(helpers.contains(".contentTransition(reduceMotion ? .identity : .numericText())"))
        XCTAssertTrue(helpers.contains(".animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: value)"))
        XCTAssertTrue(helpers.contains(".monospacedDigit()"))

        // The Basics legend's averages, both source-legend forms, and the
        // "Avg …" / "Range …" header beside every other chart.
        XCTAssertTrue(helpers.contains(".bodyLegendNumberFlip(value: valueText)"))
        XCTAssertEqual(
            comparison.occurrenceCount(of: ".bodyLegendNumberFlip(value: averageText(for: item.averageValue))"),
            2
        )
        XCTAssertTrue(detail.contains(".bodyLegendNumberFlip(value: text)"))
    }

    func testMorphingRangeChartsReceiveUntrimmedHistory() throws {
        let detail = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")

        // Each of these charts windows every range itself to keep the other
        // ranges' marks resident. Handing one a series already limited to the
        // selected range leaves the longer ranges nothing older to morph from,
        // so their marks pop in — which is exactly what the morph avoids.
        XCTAssertTrue(detail.contains("if let basicsTrend = model.basicsTrend {"))
        XCTAssertTrue(detail.contains("trend: basicsTrend,"))
        XCTAssertTrue(detail.contains("series: bodyMassIndexTrend,"))
        XCTAssertTrue(detail.contains("nights: vitalsSnapshot.nights,"))
        XCTAssertFalse(detail.contains("trend: visibleBasicsTrend,"))
        XCTAssertFalse(detail.contains("series: visibleBodyMassIndexTrend,"))
        XCTAssertFalse(detail.contains("nights: visibleVitalsNights,"))
        // The range-limited values still back the readouts around the charts.
        XCTAssertTrue(detail.contains("visibleBodyMassIndexTrend.averageValue"))
        XCTAssertTrue(detail.contains("visibleBasicsTrend?.bodyFatHalfSpread"))
    }

    func testHealthKitFetchesBarAndRangeSecondarySourceComparisons() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let engineSource = try healthKitFetchEngineText()
        let snapshotSource = try healthSummarySnapshotText()

        XCTAssertTrue(storeSource.contains("@Published private(set) var secondaryHealthDataSourceSelection"))
        XCTAssertTrue(storeSource.contains("func selectedSecondaryHealthDataSourceOption(for kind: HealthMetricKind)"))
        XCTAssertTrue(storeSource.contains("func updateSecondaryHealthDataSource(for kind: HealthMetricKind"))
        XCTAssertTrue(engineSource.contains("func fetchSecondaryTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendSeries?"))
        XCTAssertTrue(engineSource.contains("func fetchSecondaryRangeTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendRangeSeries?"))
        XCTAssertTrue(engineSource.contains("let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)"))
        XCTAssertTrue(engineSource.contains("sourceOption: secondaryOption"))
        XCTAssertTrue(engineSource.contains("trends.activeEnergySecondary = resolvedTrend(await activeEnergySecondaryTrend"))
        XCTAssertTrue(engineSource.contains("trends.restingEnergySecondary = resolvedTrend(await restingEnergySecondaryTrend"))
        XCTAssertTrue(engineSource.contains("trends.exerciseMinutesSecondary = resolvedTrend(await exerciseMinutesSecondaryTrend"))
        XCTAssertTrue(engineSource.contains("trends.stepsSecondary = resolvedTrend(await stepsSecondaryTrend"))
        XCTAssertTrue(engineSource.contains("trends.heartRateRangesSecondary = resolvedTrend(await heartRateRangesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.heartRateVariabilityRangesSecondary = resolvedTrend(await heartRateVariabilityRangesSecondary"))
        XCTAssertTrue(engineSource.contains("trends.oxygenSaturationRangesSecondary = resolvedTrend(await oxygenSaturationRangesSecondary"))
        XCTAssertTrue(snapshotSource.contains("var activeEnergySecondary: HealthTrendSeries"))
        XCTAssertTrue(snapshotSource.contains("var restingEnergySecondary: HealthTrendSeries"))
        XCTAssertTrue(snapshotSource.contains("var exerciseMinutesSecondary: HealthTrendSeries"))
        XCTAssertTrue(snapshotSource.contains("var stepsSecondary: HealthTrendSeries"))
        XCTAssertTrue(snapshotSource.contains("var heartRateRangesSecondary: HealthTrendRangeSeries"))
        XCTAssertTrue(snapshotSource.contains("var heartRateVariabilityRangesSecondary: HealthTrendRangeSeries"))
        XCTAssertTrue(snapshotSource.contains("var oxygenSaturationRangesSecondary: HealthTrendRangeSeries"))
        XCTAssertTrue(snapshotSource.contains("next.restingEnergySecondary = refreshed.restingEnergySecondary"))
    }

    func testWorkoutDetailMetricReuseBranchDoesNotResurrectCachedValues() throws {
        // H12 regression guard: the cached-HR-reuse branch used to pass
        // `resolvedVO2 ?? cached.cardioFitnessVO2Max` / `resolvedCadence ??
        // cached.averageStepCadenceSPM`, so a successful query confirming a
        // detail metric absent could never clear the field on a passive
        // resume. Both fallbacks must stay gone, and all three call sites
        // must route through `resolvedWorkoutDetailMetric`.
        let engineSource = try healthKitFetchEngineText()

        XCTAssertFalse(engineSource.contains("?? cached.cardioFitnessVO2Max"))
        XCTAssertFalse(engineSource.contains("?? cached.averageStepCadenceSPM"))
        XCTAssertTrue(engineSource.contains("nonisolated static func resolvedWorkoutDetailMetric("))
        XCTAssertTrue(engineSource.contains("fetched: resolvedCardioFitness?[workout.uuid]"))
        XCTAssertTrue(engineSource.contains("fetched: resolvedStepCadence[workout.uuid]"))
        XCTAssertTrue(engineSource.contains("fetched: resolvedWorkoutDistance[workout.uuid]"))
    }

    /// Clearing the effort cache while the per-workout fan-out is suspended used
    /// to let the post-gather block repopulate the maps and enqueue a save AFTER
    /// the clear's ledger delete, recreating the file the user just wiped. Both
    /// clears must bump `effortCacheGeneration`, and `fetchEffortLevels` must
    /// capture it before the fan-out and skip the cache write when it changed.
    func testEffortFetchCannotResurrectAClearedLedger() throws {
        let engineSource = try text(at: "Body/Services/HealthKitFetchEngine.swift")

        XCTAssertTrue(engineSource.contains("private var effortCacheGeneration = 0"))
        // Once in each clear (full and scoped).
        XCTAssertEqual(engineSource.occurrenceCount(of: "effortCacheGeneration += 1"), 2)
        XCTAssertTrue(engineSource.contains("let generation = effortCacheGeneration"))
        XCTAssertTrue(engineSource.contains("guard effortCacheGeneration == generation else {"))
    }

    /// The tracked query wrappers hold a budget permit across their await, so a
    /// HealthKit callback that never arrives must not pin one until relaunch.
    /// BOTH wrappers resume with `cancelledValue` through `TrackedQueryResumeBox`
    /// on cancellation and both bail right after `acquire()` when the waiter was
    /// already cancelled; the semaphore's own wait stays uncancellable by design,
    /// so the bail must live in the wrappers. `trackedExternalHealthQuery` can't
    /// interrupt the other module's continuation, so it runs its body
    /// unstructured (hence `@Sendable`) and lets the orphan resume into the box's
    /// drop branch — a pre-query bail alone would still pin a permit for the
    /// whole of a stalled sleep/effort/daily-metric fetch.
    func testTrackedQueryWrappersReleaseTheirPermitOnCancellation() throws {
        let engineSource = try text(at: "Body/Services/HealthKitFetchEngine.swift")
        let budgetSource = try text(at: "Body/Services/HealthKitQueryBudget.swift")

        XCTAssertTrue(engineSource.contains("final class TrackedQueryResumeBox<Value>: @unchecked Sendable {"))
        XCTAssertTrue(engineSource.contains(
            "try await trackedHealthQuery(cancelledValue: .failure(CancellationError()), body).get()"
        ))
        XCTAssertTrue(engineSource.contains("_ body: @escaping @Sendable () async -> Value"))
        // One post-acquire bail and one cancellation resume per wrapper.
        XCTAssertEqual(engineSource.occurrenceCount(of: "if Task.isCancelled {"), 2)
        XCTAssertEqual(engineSource.occurrenceCount(of: "box.cancel(cancelledValue: cancelledValue())"), 2)
        XCTAssertFalse(budgetSource.contains("Task.isCancelled"))
        // The external bodies must not reach back into engine state, or the
        // unstructured hop would be an actor-isolation violation.
        XCTAssertFalse(engineSource.contains("store: healthStore,"))
    }

    /// Regression guard: Stress is DERIVED, never fetched, so `fetchHealthTrends`
    /// is the sole custodian of its state between refreshes. Every stress field
    /// used to default to empty in the snapshot it assembles, which silently
    /// wiped the recorded day history — and with it the baselines that outlive
    /// the ~32-day day-sample cache — on every full refresh. All of them must
    /// stay carried forward from the cached trends, the way `recordedReadiness`
    /// is; a new stress field added without a line here reintroduces the bug.
    func testFullRefreshCarriesForwardEveryStressTrendField() throws {
        let engineSource = try healthKitFetchEngineText()
        let assemblyStart = try XCTUnwrap(engineSource.range(of: "let trends = HealthTrendSnapshot(")?.lowerBound)
        // Window sized to the whole initializer call (~4.6k chars today).
        let assemblyBlock = String(engineSource[assemblyStart...].prefix(5_500))

        XCTAssertTrue(assemblyBlock.contains("stress: cachedStress,"))
        XCTAssertTrue(assemblyBlock.contains("stressRanges: cachedStressRanges,"))
        XCTAssertTrue(assemblyBlock.contains("heartbeatRMSSDDaySamples: cachedHeartbeatRMSSDDaySamples,"))
        XCTAssertTrue(assemblyBlock.contains("recordedStressDays: cachedRecordedStressDays,"))
        XCTAssertTrue(assemblyBlock.contains("recordedStressContext: cachedRecordedStressContext,"))
        XCTAssertTrue(assemblyBlock.contains("stressBackfillScannedThrough: cachedStressBackfillScannedThrough,"))
        XCTAssertTrue(assemblyBlock.contains("stressBackfillComplete: cachedStressBackfillComplete,"))
        XCTAssertTrue(engineSource.contains("let cachedRecordedStressDays = cachedTrends.recordedStressDays"))
        XCTAssertTrue(engineSource.contains("let cachedHeartbeatRMSSDDaySamples = cachedTrends.heartbeatRMSSDDaySamples"))
    }

    /// The same regression one layer up: neither readiness nor stress is fetched,
    /// so the summary leaf of the progressive publish always carries them empty.
    /// Publishing it as-is blanked the card for the length of every refresh —
    /// both must be carried over from the cached summary until
    /// `updateHealthDashboardSnapshot` recomputes them.
    func testProgressiveSummaryPublishCarriesDerivedMetricsForward() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let publishStart = try XCTUnwrap(
            storeSource.range(of: "healthSummary = result.summary")?.lowerBound
        )
        let publishBlock = String(storeSource[publishStart...].prefix(200))

        XCTAssertTrue(publishBlock.contains(".replacingMetric(.readiness, with: healthSummary)"))
        XCTAssertTrue(publishBlock.contains(".replacingMetric(.stress, with: healthSummary)"))
    }

    /// The full refresh runs the stress recompute ONCE, in the tail where the
    /// activity mask finally has workouts, and coalesces the three snapshot
    /// writes it used to perform into one after that tail settles. Both rest on
    /// the same carry: a fetched summary has no stress, so the dashboard publish
    /// must bring the live values forward or the Stress card blanks and the
    /// coalesced (or abandonment) write persists the blank.
    func testFullRefreshRecomputesStressOnceAndWritesOnce() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let refreshStart = try XCTUnwrap(
            storeSource.range(of: "private func refreshRecentMonths(")?.lowerBound
        )
        let refreshEnd = try XCTUnwrap(
            storeSource.range(
                of: "    private func refresh(\n        month: Int,",
                range: refreshStart..<storeSource.endIndex
            )?.lowerBound
        )
        let refreshBlock = String(storeSource[refreshStart..<refreshEnd])
        let updateStart = try XCTUnwrap(
            storeSource.range(of: "private func updateHealthDashboardSnapshot(")?.lowerBound
        )
        let updateBlock = String(storeSource[updateStart...].prefix(3_000))

        XCTAssertTrue(refreshBlock.contains("recomputesStress: false"))
        XCTAssertTrue(refreshBlock.contains("await recomputeStress(on: date, calendar: calendar, persists: false)"))
        XCTAssertTrue(
            refreshBlock.contains(
                "await reapplyActivityReadinessAfterWorkouts(date: date, calendar: calendar, persists: false)"
            )
        )
        XCTAssertEqual(refreshBlock.components(separatedBy: "persistDashboardSnapshot()").count - 1, 1)
        XCTAssertEqual(refreshBlock.components(separatedBy: "saveHealthWidgetSnapshot()").count - 1, 1)
        XCTAssertTrue(
            updateBlock.contains(
                "let carriedSummary = recomputesStress ? summary : summary.replacingMetric(.stress, with: healthSummary)"
            )
        )
    }

    func testSecondarySleepStageHistorySkipsVitalsHydration() throws {
        let sleepSource = try text(at: "Body/Services/HealthKitFetchEngine+Sleep.swift")
        let secondarySource = try text(at: "Body/Services/HealthKitFetchEngine+Secondary.swift")
        let fetchSleepHistoryStart = try XCTUnwrap(
            sleepSource.range(of: "func fetchDailySleepHistory(")?.lowerBound
        )
        let fetchSleepHistoryBlock = String(sleepSource[fetchSleepHistoryStart...].prefix(5_500))
        let fetchSecondarySleepStart = try XCTUnwrap(
            secondarySource.range(of: "func fetchSecondarySleepHistory")?.lowerBound
        )
        let fetchSecondarySleepBlock = String(secondarySource[fetchSecondarySleepStart...].prefix(1_000))

        XCTAssertTrue(fetchSleepHistoryBlock.contains("hydrateVitals: Bool = true"))
        XCTAssertTrue(fetchSleepHistoryBlock.contains("guard hydrateVitals else {"))
        XCTAssertTrue(fetchSleepHistoryBlock.contains("return SleepHistoryFetchResult(history: SleepHistorySnapshot(days: days), vitalsHadFailure: false)"))
        XCTAssertTrue(sleepSource.contains("BodySleepStageDisplayPreference.showsSubMinuteAwakeStages()"))
        XCTAssertTrue(sleepSource.contains("showsSubMinuteAwakeStages: showsSubMinuteAwakeStages"))
        XCTAssertTrue(sleepSource.contains("BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages()"))
        XCTAssertTrue(sleepSource.contains("showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages"))
        XCTAssertTrue(fetchSecondarySleepBlock.contains("hydrateVitals: false"))
    }

    /// Regression guard for the Stress input-only fetch tier: `.fullOnly` must
    /// stay the DEFAULT payload requirement, so a newly added dashboard leaf is
    /// suppressed for input-only kinds until it deliberately opts in with
    /// `.inputCapable`. Flipping the default (or dropping it) would silently
    /// re-fetch every stress dependency's full year payload again.
    func testDashboardMetricFetchDefaultsToFullPayloadOnly() throws {
        let engineSource = try healthKitFetchEngineText()

        XCTAssertTrue(engineSource.contains("payload: DashboardPayloadRequirement = .fullOnly"))
        XCTAssertTrue(engineSource.contains("case .fullOnly: selection.includesFullPayload(kind)"))
        XCTAssertTrue(engineSource.contains("case .inputCapable: selection.includes(kind)"))
    }

    /// The secondary (comparison-series) helper has no `.inputCapable` opt-in at
    /// all — Stress never reads a secondary series — so it must always gate on
    /// `includesFullPayload`, never the looser `includes`.
    func testSecondaryDashboardMetricFetchAlwaysRequiresFullPayload() throws {
        let engineSource = try text(at: "Body/Services/HealthKitFetchEngine.swift")
        let fetchSecondaryStart = try XCTUnwrap(
            engineSource.range(of: "func fetchSecondaryDashboardMetricIfNeeded")?.lowerBound
        )
        let fetchSecondaryBlock = String(engineSource[fetchSecondaryStart...].prefix(800))

        XCTAssertTrue(fetchSecondaryBlock.contains("guard selection.includesFullPayload(kind) else {"))
        XCTAssertFalse(fetchSecondaryBlock.contains(".inputCapable"))
    }

    /// Exactly three leaves opt into the input-capable tier (sleep summary,
    /// daily sleep history, and the HRV year pair) — the full set Stress needs
    /// beyond what its full-payload dependents already fetch. A fourth
    /// occurrence means a leaf was opted in without updating this guard (or the
    /// plan); a count under three means one of the three was dropped.
    func testExactlyThreeLeavesOptIntoInputCapablePayload() throws {
        let engineSource = try text(at: "Body/Services/HealthKitFetchEngine.swift")

        XCTAssertEqual(engineSource.occurrenceCount(of: "payload: .inputCapable"), 3)
    }

    /// The reduced-window sleep fetch: an input-only (stress-only) layout clamps
    /// to `stressInputSleepHistoryDays` — sized to cover the 56-day vitals
    /// baseline + recomputed-day reach with margin, ~3.6x less than the full
    /// year — and that clamp REPLACES the cached history, so it stays ahead of
    /// the phase-1 trend window (which merges instead) rather than combining
    /// with it. A full-payload layout takes the phase-1 window, or the whole
    /// year when there is no cached history to merge the window into.
    /// `hydrateVitals` is untouched by this parameter and must stay on in both
    /// modes, or Readiness/sleep-score baselines would degrade for stress-only
    /// layouts.
    func testSleepHistoryFetchClampsToStressInputWindowWhenNotFullPayload() throws {
        let engineSource = try text(at: "Body/Services/HealthKitFetchEngine.swift")

        XCTAssertTrue(engineSource.contains(
            """
            maxDays: selection.includesFullPayload(.sleep)
                                ? (cachedTrends.sleepHistory.isEmpty ? nil : trendWindowDays)
                                : Self.stressInputSleepHistoryDays,
            """
        ))
        XCTAssertTrue(engineSource.contains("static let stressInputSleepHistoryDays = 100"))
    }

    /// The two-phase trend window (RefreshOptimizationPlan-02 P0-A) rests on the
    /// merge living INSIDE the fetch layer: `fetchHealthTrends` splices the
    /// cached older-than-window points back on before it returns, so the
    /// readiness/stress recompute, the widget builder and the watch seed always
    /// see a full-span series. A windowed series escaping to the store would
    /// collapse the readiness chart and — via the abandonment path — persist the
    /// collapse. Phase 2 only runs when phase 1 actually shortened the window.
    func testPhaseOneTrendWindowMergesInsideTheFetchLayer() throws {
        let engineSource = try text(at: "Body/Services/HealthKitFetchEngine.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let fetchStart = try XCTUnwrap(engineSource.range(of: "func fetchHealthTrends(")?.lowerBound)
        let fetchEnd = try XCTUnwrap(
            engineSource.range(of: "return HealthTrendFetchResult(", range: fetchStart..<engineSource.endIndex)?.lowerBound
        )
        let fetchBlock = String(engineSource[fetchStart..<fetchEnd])

        XCTAssertTrue(fetchBlock.contains("trendWindowDays: Int? = nil"))
        XCTAssertTrue(fetchBlock.contains("Self.mergeWindowedTrend("))
        XCTAssertTrue(fetchBlock.contains("Self.mergeWindowedTrendRange("))
        XCTAssertTrue(fetchBlock.contains("Self.mergeWindowedSleepHistory("))

        // Phase 2 is fired, never awaited, and only after a windowed phase 1.
        XCTAssertTrue(storeSource.contains("if fetchedPartialTrendWindow {"))
        XCTAssertTrue(
            storeSource.contains("startFullTrendWindowLoadIfNeeded(selection: dashboardFetchSelection)")
        )
        XCTAssertTrue(storeSource.contains("trendWindowDays: nil"))
    }

    /// `refreshFetchedStressInputKinds` in `HealthKitWorkoutStore` must track the
    /// exact set of engine `.inputCapable` leaves that fetch during the
    /// dashboard refresh itself (sleep + HRV) — the third `.inputCapable` leaf,
    /// the sleep *summary*, doesn't add a new kind. The Stress input loader
    /// (heart-gated) is the only other path that ever reads a Stress
    /// dependency, so any kind missing from this set falsely reports
    /// "not fetched" for the permission sheet whenever Heart is off.
    func testRefreshFetchedStressInputKindsMatchesInputCapableAnnotations() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let setRange = try XCTUnwrap(
            storeSource.range(of: "private static let refreshFetchedStressInputKinds: Set<HealthMetricKind> = [")
        )
        let closeRange = try XCTUnwrap(storeSource.range(of: "]", range: setRange.upperBound..<storeSource.endIndex))
        let setBody = storeSource[setRange.upperBound..<closeRange.lowerBound]
        let kinds = setBody
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        XCTAssertEqual(Set(kinds), [".sleep", ".heartRateVariability"])
    }

    func testMetricDetailScreensPullToRefreshOnlyCurrentMetric() throws {
        let homeSource = try bodyHomeViewText()
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let detailViewStart = try XCTUnwrap(homeSource.range(of: "struct BodyHealthMetricDetailView")?.lowerBound)
        // Window covers the struct's stored properties + `init` + `body` opening, where the
        // custom pull-to-refresh trigger lives; widened as the property list grew (e.g. `zoomNamespace`,
        // metric warning threshold state).
        let detailViewBlock = String(homeSource[detailViewStart...].prefix(8_000))
        let refreshStart = try XCTUnwrap(storeSource.range(of: "func refreshHealthMetric(_ kind: HealthMetricKind")?.lowerBound)
        let refreshBlock = String(storeSource[refreshStart...].prefix(8_000))

        XCTAssertTrue(detailViewBlock.contains(".bodyPullToRefresh("))
        XCTAssertTrue(detailViewBlock.contains("await workoutStore.refreshHealthMetric(model.kind)"))
        XCTAssertTrue(refreshBlock.contains("let metricFetch = await engine.fetchHealthDashboardSnapshot("))
        XCTAssertTrue(refreshBlock.contains("for: kind"))
        XCTAssertTrue(refreshBlock.contains("existing: existing"))
        XCTAssertTrue(refreshBlock.contains("replacingMetric(kind, with: metricFetch.snapshot.summary)"))
        // Trends route through `fetchedTrends`, which is `metricFetch.snapshot.trends`
        // with the day samples stripped when the source selection changed mid-fetch
        // (see `testMetricRefreshDropsDaySamplesWhenSelectionChangesMidFetch`) — still
        // a single-metric replace, never a full-dashboard one.
        XCTAssertTrue(refreshBlock.contains("? metricFetch.snapshot.trends"))
        XCTAssertTrue(refreshBlock.contains("replacingMetric(kind, with: fetchedTrends)"))
        XCTAssertFalse(refreshBlock.contains("engine.fetchHealthSummary(calendar: calendar)"))
        XCTAssertFalse(refreshBlock.contains("engine.fetchHealthTrends(calendar: calendar"))
    }

    func testWorkoutsPullToRefreshOnlyRefreshesSelectedWorkoutMonth() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let refreshableStart = try XCTUnwrap(workoutsSource.range(of: ".bodyPullToRefresh(")?.lowerBound)
        let refreshableBlock = String(workoutsSource[refreshableStart...].prefix(500))
        let methodStart = try XCTUnwrap(storeSource.range(of: "func refreshWorkoutMonth(month: Int, year: Int")?.lowerBound)
        let methodBlock = String(storeSource[methodStart...].prefix(2_000))

        XCTAssertTrue(refreshableBlock.contains("await workoutStore.refreshWorkoutMonth(month: selectedMonth, year: selectedYear)"))
        XCTAssertFalse(refreshableBlock.contains("requestAuthorizationAndRefresh()"))
        XCTAssertTrue(methodBlock.contains("updatesHealthSummary: false"))
        XCTAssertFalse(methodBlock.contains("fetchHealthSummary(calendar: calendar)"))
        XCTAssertFalse(methodBlock.contains("fetchHealthTrends(calendar: calendar)"))
        XCTAssertFalse(methodBlock.contains("fetchActivityRingHistory(calendar: calendar)"))
    }

    func testWorkoutListAnimatesArrivalsKeyedOnWorkoutIdentity() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")

        // Membership, not the snapshot: every refresh republishes the month with
        // a fresh `generatedAt`, so a snapshot-derived key would animate the list
        // on every sync. A Set rather than an array, so a pure re-sort does not
        // fire the insertion animation and `selectedSortOption` keeps its own.
        XCTAssertTrue(workoutsSource.contains("let visibleWorkoutIDs = Set(visibleWorkouts.map(\\.id))"))
        XCTAssertTrue(workoutsSource.contains(".animation(workoutRowChangeAnimation, value: visibleWorkoutIDs)"))
        XCTAssertFalse(workoutsSource.contains("value: visibleWorkouts.map(\\.id)"))
        XCTAssertFalse(workoutsSource.contains("value: baseSnapshot"))

        // The keyed animation has to sit on the Group that spans both the list
        // and the empty state, and inside the month `.id` — see the comments at
        // the call site. Order in the source is the assertion.
        let listBlockStart = try XCTUnwrap(
            workoutsSource.range(of: ".animation(workoutRowChangeAnimation, value: visibleWorkoutIDs)")?.lowerBound
        )
        let listBlock = String(workoutsSource[listBlockStart...].prefix(300))
        XCTAssertTrue(listBlock.contains(".id(\"list-\\(monthIdentity)\")"))
        XCTAssertTrue(listBlock.contains(".transition(monthSwitchTransition)"))

        // Row fade lives on the button, outside the label holding the zoom source.
        XCTAssertTrue(workoutsSource.contains(".transition(workoutRowTransition)"))
        XCTAssertTrue(workoutsSource.contains("private var workoutRowTransition: AnyTransition"))
        XCTAssertTrue(workoutsSource.contains("private var workoutRowChangeAnimation: Animation?"))
        XCTAssertTrue(workoutsSource.contains("reduceMotion ? nil : .smooth(duration: 0.32, extraBounce: 0)"))
    }

    func testPullToRefreshUsesCustomTriggerWithNoSystemRefreshControl() throws {
        // No refreshable surface installs the system refresh control (and its
        // spinner); every scroll view uses the custom `.bodyPullToRefresh`
        // trigger so the floating sync badge is the only refresh UI.
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        let detailSource = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")

        for source in [homeSource, workoutsSource, detailSource] {
            XCTAssertFalse(source.contains(".refreshable"))
            XCTAssertTrue(source.contains(".bodyPullToRefresh("))
        }
    }

    func testWorkoutsPageShowsOneChartAtATimeWithAPersistedSwitch() throws {
        let source = try text(at: "Body/Views/BodyWorkoutsView.swift")
        let appearanceSource = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let calendarSource = try text(at: "BodyShared/Components/WorkoutCalendarView.swift")
        let breakdownSource = try text(at: "BodyShared/Components/WorkoutTypeBreakdownView.swift")
        let widgetSource = try text(at: "BodyWidgetExtension/WorkoutCalendarWidget.swift")

        XCTAssertTrue(appearanceSource.contains(#"static let workoutsChartShowsTypeBreakdownKey = "workoutsChartShowsTypeBreakdown""#))
        XCTAssertTrue(source.contains("@AppStorage(BodyAppearancePreference.workoutsChartShowsTypeBreakdownKey) private var workoutsChartShowsTypeBreakdown = false"))

        // One slot, one identity. The per-card ids are gone because the two
        // cards no longer occupy separate places on the page — and the month id
        // now sits on the calendar branch alone, so the breakdown survives a month
        // switch and morphs its bars instead of cross-fading the whole card.
        XCTAssertTrue(source.contains(".id(\"chart-\\(monthIdentity)\")"))
        let chartSlot = try XCTUnwrap(source.range(of: "if workoutsChartShowsTypeBreakdown {"))
        let breakdownBranch = String(source[chartSlot.upperBound...].prefix(180))
        XCTAssertTrue(breakdownBranch.contains("workoutTypeSummaryCard(snapshot: displaySnapshot"))
        XCTAssertFalse(breakdownBranch.contains("monthIdentity"))
        XCTAssertFalse(source.contains(".id(\"calendar-\\(monthIdentity)\")"))
        XCTAssertFalse(source.contains(".id(\"summary-\\(monthIdentity)\")"))

        // The breakdown moved above the workout list; it used to trail it.
        let summaryCall = try XCTUnwrap(source.range(of: "workoutTypeSummaryCard(snapshot: displaySnapshot, workouts: matchingWorkouts)"))
        let listStack = try XCTUnwrap(source.range(of: "LazyVStack(spacing: 12)"))
        XCTAssertLessThan(summaryCall.lowerBound, listStack.lowerBound)

        // On BOTH branches — one alone would fade the incoming card in over a
        // card that never faded out, which is a replace, not a cross-fade.
        XCTAssertEqual(source.occurrenceCount(of: ".transition(chartSwitchTransition)"), 2)
        // `withAnimation`, not `.animation(value:)` on the slot: the workout
        // list that has to move is the slot's sibling, outside that scope.
        XCTAssertTrue(source.contains("withAnimation(chartSwitchAnimation)"))
        XCTAssertEqual(source.occurrenceCount(of: "onSwitchChart: switchChart"), 2)

        // The handler is optional and defaulted, so the widgets — which pass
        // none — keep their exact pre-existing layout.
        XCTAssertTrue(calendarSource.contains("onSwitchChart: (() -> Void)? = nil"))
        XCTAssertTrue(breakdownSource.contains("onSwitchChart: (() -> Void)? = nil"))
        XCTAssertFalse(widgetSource.contains("onSwitchChart"))

        // The control shares the last bar's row, and it is the BAR that gives
        // up the room — `detailReserveWidth` still reads the full width, so a
        // long activity name is never squeezed to make space for the button.
        XCTAssertTrue(breakdownSource.contains("reservedTrailingWidth: reservedWidth"))
        XCTAssertTrue(breakdownSource.contains("availableWidth - reservedTrailingWidth - detailReserveWidth(for: availableWidth)"))
    }

    func testWorkoutTypeBreakdownBarsMorphAcrossRankSlots() throws {
        let breakdownSource = try text(at: "BodyShared/Components/WorkoutTypeBreakdownView.swift")

        // Rows are identified by their rank slot, never by the activity: a re-ranking
        // has to morph row 1 into the new leader rather than reorder the list.
        XCTAssertTrue(breakdownSource.contains("ForEach(rows.indices, id: \\.self)"))
        XCTAssertFalse(breakdownSource.contains("ForEach(Array(displayedBreakdown.enumerated())"))

        // Two snapshots on two clocks: bars/colors under the 0.45 s morph, the in-bar
        // percentages assigned outside it so the digits roll while the bars travel.
        XCTAssertTrue(breakdownSource.contains("@State private var displayedBreakdown: [WorkoutTypeBreakdown]?"))
        XCTAssertTrue(breakdownSource.contains("@State private var displayedTextBreakdown: [WorkoutTypeBreakdown]?"))
        XCTAssertTrue(breakdownSource.contains("withAnimation(morphs ? .easeInOut(duration: 0.45) : nil)"))
        let morphBlock = try XCTUnwrap(breakdownSource.range(of: "displayedBreakdown = breakdown"))
        let textAssignment = try XCTUnwrap(breakdownSource.range(of: "displayedTextBreakdown = breakdown"))
        XCTAssertLessThan(morphBlock.upperBound, textAssignment.lowerBound)

        // The widgets never run a `.task`, so every read falls back to the snapshot
        // they were handed — a widget must not render an empty chart.
        XCTAssertTrue(breakdownSource.contains("displayedBreakdown ?? snapshot.workoutTypeBreakdown"))
        XCTAssertTrue(breakdownSource.contains("displayedTextBreakdown ?? snapshot.workoutTypeBreakdown"))

        // Digits roll instead of cutting; the activity group cross-fades in its slot.
        XCTAssertTrue(breakdownSource.contains(".numericText(value: Double(percentage))"))
        XCTAssertTrue(breakdownSource.contains(".snappy(duration: 0.38, extraBounce: 0), value: percentage"))
        XCTAssertTrue(breakdownSource.contains(".id(entry.type)"))

        // Reduce Motion kills all three mechanisms, plus the inherited morph.
        XCTAssertTrue(breakdownSource.contains("&& !reduceMotion"))
        XCTAssertTrue(breakdownSource.contains("reduceMotion ? .identity : .numericText"))
        XCTAssertTrue(breakdownSource.contains("transaction.animation = nil"))
    }

    func testWorkoutChartsRenderFilteredSnapshotWhileCorpusCacheStaysUnfiltered() throws {
        // The calendar and type-breakdown charts must render the filtered
        // display snapshot so the filter sheet and search narrow them like the
        // cards list, while the search corpus cache must keep seeing the
        // unfiltered snapshot and full workout list — its key includes
        // `generatedAt`, so a filtered array would persist a partial corpus.
        let source = try text(at: "Body/Views/BodyWorkoutsView.swift")

        XCTAssertTrue(source.contains("workoutCalendarCard(snapshot: displaySnapshot)"))
        XCTAssertTrue(source.contains("workoutTypeSummaryCard(snapshot: displaySnapshot, workouts: matchingWorkouts)"))
        XCTAssertFalse(source.contains("snapshot: selectedSnapshot"))

        let calendarStart = try XCTUnwrap(source.range(of: "WorkoutCalendarView(")?.lowerBound)
        let calendarBlock = String(source[calendarStart...].prefix(200))
        XCTAssertTrue(calendarBlock.contains("snapshot: snapshot"))

        let breakdownStart = try XCTUnwrap(source.range(of: "WorkoutTypeBreakdownView(")?.lowerBound)
        let breakdownBlock = String(source[breakdownStart...].prefix(200))
        XCTAssertTrue(breakdownBlock.contains("snapshot: snapshot"))

        let corpusStart = try XCTUnwrap(source.range(of: "searchCorpusCache.entries(")?.lowerBound)
        let corpusBlock = String(source[corpusStart...].prefix(200))
        XCTAssertTrue(corpusBlock.contains("for: baseSnapshot"))
        XCTAssertTrue(corpusBlock.contains("workouts: allWorkouts"))
    }

    func testAggregatedHealthChartsWireRangeLabelsAndBarWidths() throws {
        let source = try bodyHomeViewText()

        XCTAssertFalse(source.contains("basicsLegendTrailingAxisGutter"))
        XCTAssertTrue(source.contains("func bodyChartSelectionDateText(for point: HealthTrendCalendarPoint) -> String?"))
        XCTAssertTrue(source.contains("func bodyChartSelectionDateText(for point: HealthTrendRangeCalendarPoint) -> String?"))
        XCTAssertEqual(source.occurrenceCount(of: "dateText: bodyChartSelectionDateText(for: selectedTrendPoint)"), 1)
        XCTAssertEqual(source.occurrenceCount(of: "dateText: bodyChartSelectionDateText(for: selectedPoint)"), 1)
        XCTAssertEqual(source.occurrenceCount(of: "dateText: bodyChartSelectionDateText(for: selectedRangePoint)"), 1)
        XCTAssertTrue(source.contains("dateText: selectedTrendDateText"))
        XCTAssertEqual(
            source.occurrenceCount(of: "let chartBarWidth = selectedRange.chartBarWidth(forAvailableWidth: proxy.size.width)"),
            1
        )
        XCTAssertEqual(
            source.occurrenceCount(of: "let chartBarWidth = selectedRange.heartRateRangeChartBarWidth(forAvailableWidth: proxy.size.width)"),
            2
        )
        XCTAssertEqual(source.occurrenceCount(of: "width: .fixed(chartBarWidth)"), 6)
    }

    func testBasicsWeightBodyFatMonthChartKeepsStandardPointMarks() throws {
        let source = try bodyHomeViewText()

        XCTAssertFalse(source.contains("private var showsWeightBodyFatPointMarks: Bool"))
        XCTAssertFalse(source.contains("selectedRange.showsPointMarks && selectedRange != .recentMonth"))
        XCTAssertFalse(source.contains("if showsWeightBodyFatPointMarks"))
        XCTAssertEqual(source.occurrenceCount(of: "if selectedRange.showsPointMarks"), 6)

        // Wide enough for both of this chart's gates (the range-morph rework
        // moved them apart), short of the BMI chart's own gate below.
        let chartStart = try XCTUnwrap(source.range(of: "struct BodyBasicsTrendChart")?.lowerBound)
        let chartBlock = String(source[chartStart...].prefix(12_000))
        XCTAssertEqual(chartBlock.occurrenceCount(of: "if selectedRange.showsPointMarks"), 2)
    }

    func testBasicsTrendLegendShowsAverageValuesBehindMetricLabels() throws {
        let source = try bodyHomeViewText()

        XCTAssertTrue(source.contains("weightAverageText: basicsWeightAverageText"))
        XCTAssertTrue(source.contains("bodyFatAverageText: basicsBodyFatAverageText"))
        XCTAssertTrue(source.contains("legendItem(title: \"Body Fat\", valueText: bodyFatAverageText, color: bodyFatColor)"))
        XCTAssertTrue(source.contains("legendItem(title: \"Weight\", valueText: weightAverageText, color: weightColor)"))
        let legendItemStart = try XCTUnwrap(source.range(of: "private func legendItem")?.lowerBound)
        let legendItemBlock = source[legendItemStart...].prefix(1_100)
        let averageTextStart = try XCTUnwrap(legendItemBlock.range(of: "Text(\"Avg \\(valueText)\")")?.lowerBound)
        let averageTextBlock = legendItemBlock[averageTextStart...].prefix(260)
        XCTAssertTrue(averageTextBlock.contains(".foregroundColor(.secondary)"))
        XCTAssertFalse(legendItemBlock.contains("Text(valueText)"))
        XCTAssertFalse(averageTextBlock.contains(".foregroundColor(.primary)"))
    }

    func testWorkoutDetailChartXAxisLabelsStayInsidePlotEdges() throws {
        let source = try text(at: "Body/Views/BodyWorkoutsView.swift")

        // The first and last x-axis marks sit at the plot edges and would otherwise
        // render half outside the card, so every plot clamps them by the same inset:
        // the heart-rate line chart (clock times), the elevation profile line and the
        // shared bucketed bar plot (HH:mm:ss).
        XCTAssertEqual(source.occurrenceCount(of: "private static let timeMarkLabelHorizontalInset: CGFloat = 24"), 3)
        // Heart rate positions its marks as SwiftUI text through `timeMarkLabelX`.
        XCTAssertTrue(source.contains("timeMarkLabelX(for: mark, in: plotRect)"))
        XCTAssertTrue(source.contains("return min(max(rawX, lowerBound), upperBound)"))
        XCTAssertTrue(source.contains("static let timeMarkFractions = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]"))
        XCTAssertTrue(source.contains("BodyWorkoutHeartRateChartMetrics.timeMarkFractions"))
        // The elevation and bucketed plots draw theirs into the canvas.
        XCTAssertTrue(source.contains("let lowerBound = plotRect.minX + Self.timeMarkLabelHorizontalInset"))
        XCTAssertTrue(source.contains("let upperBound = max(lowerBound, plotRect.maxX - Self.timeMarkLabelHorizontalInset)"))
        XCTAssertEqual(
            source.occurrenceCount(
                of: "at: CGPoint(x: min(max(rawX, lowerBound), upperBound), y: plotRect.maxY + Self.xAxisLabelOffset)"
            ),
            2
        )
        XCTAssertFalse(source.contains("x: plotRect.minX + plotRect.width * mark.fraction"))
    }

    func testSummaryTabUsesHealthDashboardIcon() throws {
        let source = try text(at: "Body/Views/MainTabView.swift")

        XCTAssertTrue(source.contains(#"case .summary: "waveform.path.ecg.text""#))
        XCTAssertTrue(source.contains(#"case .summary: "Summary""#))
        XCTAssertFalse(source.contains(#""house.fill""#))
    }

    func testAppWidgetAndWatchShareAppGroupEntitlement() throws {
        let appEntitlements = try propertyList(at: "Body/Body.entitlements")
        let widgetEntitlements = try propertyList(at: "BodyWidgetExtension.entitlements")
        let watchEntitlements = try propertyList(at: "BodyWatch/BodyWatch.entitlements")
        let watchWidgetEntitlements = try propertyList(at: "BodyWatchWidgetExtension/BodyWatchWidgetExtension.entitlements")

        XCTAssertEqual(
            appEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
        XCTAssertEqual(
            widgetEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
        XCTAssertEqual(
            watchEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
        XCTAssertEqual(
            watchWidgetEntitlements["com.apple.security.application-groups"] as? [String],
            ["group.com.zihengthedeveloper.Body"]
        )
    }

    func testAppDeclaresHealthKitEntitlement() throws {
        let appEntitlements = try propertyList(at: "Body/Body.entitlements")
        let watchEntitlements = try propertyList(at: "BodyWatch/BodyWatch.entitlements")

        XCTAssertEqual(appEntitlements["com.apple.developer.healthkit"] as? Bool, true)
        // The watch app runs its own HR/HRV HealthKit queries on the live path.
        XCTAssertEqual(watchEntitlements["com.apple.developer.healthkit"] as? Bool, true)
    }

    func testPrivacyManifestsDeclareUserDefaultsAndNoTracking() throws {
        // Per-target expected categories: app + iOS widget + watch app declare both
        // UserDefaults and FileTimestamp access; the watch widget (no UserDefaults use)
        // declares FileTimestamp only.
        let expectedCategoriesByPath: [String: Set<String>] = [
            "Body/PrivacyInfo.xcprivacy": ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp"],
            "BodyWidgetExtension/PrivacyInfo.xcprivacy": ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp"],
            "BodyWatch/PrivacyInfo.xcprivacy": ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp"],
            "BodyWatchWidgetExtension/PrivacyInfo.xcprivacy": ["NSPrivacyAccessedAPICategoryFileTimestamp"],
        ]

        for (path, expectedCategories) in expectedCategoriesByPath {
            let manifest = try propertyList(at: path)
            XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false, path)
            XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty, true, path)

            let accessedAPITypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]], path)
            let declaredCategories = Set(accessedAPITypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
            XCTAssertEqual(declaredCategories, expectedCategories, path)

            if expectedCategories.contains("NSPrivacyAccessedAPICategoryUserDefaults") {
                let userDefaultsDeclaration = accessedAPITypes.first {
                    $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
                }
                XCTAssertEqual(
                    userDefaultsDeclaration?["NSPrivacyAccessedAPITypeReasons"] as? [String],
                    ["CA92.1"],
                    path
                )
            }

            if expectedCategories.contains("NSPrivacyAccessedAPICategoryFileTimestamp") {
                let fileTimestampDeclaration = accessedAPITypes.first {
                    $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryFileTimestamp"
                }
                XCTAssertEqual(
                    fileTimestampDeclaration?["NSPrivacyAccessedAPITypeReasons"] as? [String],
                    ["C617.1"],
                    path
                )
            }
        }
    }

    func testProjectBuildSettingsMatchInitialReleasePlan() throws {
        let project = try text(at: "body.xcodeproj/project.pbxproj")

        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body.BodyWidgetExtension;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.BodyTests;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body.watchkitapp;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.zihengthedeveloper.Body.watchkitapp.WatchWidget;"))
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"BodyBlack BodyGray BodyPink BodyPurple BodyWhite\";"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSHealthShareUsageDescription"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSHealthUpdateUsageDescription"))
        // Every target that declares HealthKit read access (and carries the HealthKit
        // entitlement) must also declare NSHealthUpdateUsageDescription, or App Store
        // validation rejects the bundle. The watch app shipped Share without Update once.
        XCTAssertEqual(
            project.occurrenceCount(of: "INFOPLIST_KEY_NSHealthShareUsageDescription"),
            project.occurrenceCount(of: "INFOPLIST_KEY_NSHealthUpdateUsageDescription")
        )
        // The share card's Save button writes to the photo library; without this string
        // the add-only authorization prompt crashes the app. App target only (Debug +
        // Release) — the widget and watch never save.
        XCTAssertEqual(project.occurrenceCount(of: "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription"), 2)
        // The copy now covers video saves too, since the Save button can also write an
        // exported MP4 from the Your Video background.
        XCTAssertEqual(project.occurrenceCount(of: "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = \"Body saves the workout images and videos you create to your photo library.\";"), 2)
        XCTAssertTrue(project.contains("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;"))
        XCTAssertTrue(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 18.0;"))
        XCTAssertTrue(project.contains("TARGETED_DEVICE_FAMILY = \"1,2\";"))
        XCTAssertTrue(project.contains("SUPPORTS_MACCATALYST = NO;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";"))
        XCTAssertTrue(project.contains("MARKETING_VERSION = 1.1.0;"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 1;"))
        // All five targets (app, widget, tests, watch app, watch complications)
        // × Debug/Release must move together on a version bump — `contains`
        // alone would pass with a stale target left behind.
        XCTAssertEqual(project.occurrenceCount(of: "MARKETING_VERSION = 1.1.0;"), 10)
        XCTAssertEqual(project.occurrenceCount(of: "CURRENT_PROJECT_VERSION = 1;"), 10)
        XCTAssertTrue(project.contains("VALIDATE_PRODUCT = YES;"))
    }

    func testWatchMetricKindKeysMatchIOSWidgetStyling() throws {
        let pairs: [(kind: String, widgetMetric: HealthWidgetMetric)] = [
            (WatchMetricKindKey.trainingLoad, .trainingLoad),
            (WatchMetricKindKey.readiness, .readiness),
            (WatchMetricKindKey.sleep, .sleep),
            (WatchMetricKindKey.heartRate, .heartRate),
            (WatchMetricKindKey.heartRateVariability, .heartRateVariability),
            (WatchMetricKindKey.restingHeartRate, .restingHeartRate),
            (WatchMetricKindKey.wristTemperature, .wristTemperature)
        ]

        XCTAssertEqual(pairs.map(\.kind), WatchMetricKindKey.displayOrder)

        for (kind, widgetMetric) in pairs {
            XCTAssertEqual(kind, widgetMetric.rawValue)
            XCTAssertEqual(WatchMetricKindKey.symbolName(forKind: kind), widgetMetric.symbolName, kind)

            let tint = WatchMetricKindKey.tint(forKind: kind)
            let components = UIColor(widgetMetric.tintColor).cgColor.components ?? []
            XCTAssertGreaterThanOrEqual(components.count, 3, kind)
            XCTAssertEqual(Double(components[0]), tint.red, accuracy: 0.001, kind)
            XCTAssertEqual(Double(components[1]), tint.green, accuracy: 0.001, kind)
            XCTAssertEqual(Double(components[2]), tint.blue, accuracy: 0.001, kind)
        }

        // Exercise Minutes rides the watch snapshot for the rectangular
        // complication only: it has no dashboard card, no detail page and no
        // ring, so it must stay out of `displayOrder` (which drives
        // `orderedMetrics` everywhere in the watch app UI). Its key still has
        // to match the iOS widget metric's raw value, because the phone-side
        // trend lookup keys off it.
        XCTAssertFalse(WatchMetricKindKey.displayOrder.contains(WatchMetricKindKey.exerciseMinutes))
        XCTAssertEqual(WatchMetricKindKey.exerciseMinutes, HealthWidgetMetric.exerciseMinutes.rawValue)

        // Weekly Workout Time is the kind that complication actually reads now
        // (summed workout durations); `exerciseMinutes` above survives only as
        // the fallback for a cached snapshot from an older phone build. It has
        // no `HealthWidgetMetric` counterpart at all, so it can never join the
        // `pairs` table above, and it must stay out of `displayOrder` for the
        // same reason: no dashboard card, no detail page, no ring.
        XCTAssertFalse(WatchMetricKindKey.displayOrder.contains(WatchMetricKindKey.workoutMinutes))
    }

    func testVersionDocumentationAndSettingsFallbackMatchCurrentRelease() throws {
        let readme = try text(at: "README.md")
        let versionHistory = try text(at: "VersionHistory.md")
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(readme.contains("Current app version: **1.1.0 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.2 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.2 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.1 (build 9)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.1 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.1 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.1 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.1 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.1 (build 4)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.1 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.1 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 25)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 23)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 22)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 21)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 20)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 19)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 18)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 17)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 16)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 15)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 14)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 13)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 12)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 11)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 10)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 9)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 8)**"))
        XCTAssertTrue(readme.contains("floating sync status badge"))
        XCTAssertTrue(readme.contains("Share workout"))
        XCTAssertTrue(readme.contains("**Metric warnings**"))
        XCTAssertTrue(readme.contains("Low Heart Rate"))
        XCTAssertTrue(readme.contains("High Heart Rate"))
        XCTAssertTrue(readme.contains("Low Blood Oxygen"))
        XCTAssertTrue(readme.contains("Settings › About › Onboarding"))
        // The first-run intro paragraph.
        XCTAssertTrue(readme.contains("oooooooooh"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **1.0.0 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 17)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 16)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 15)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 13)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 12)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 11)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 10)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 9)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.12 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 13)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 12)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 11)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 10)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 9)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.11 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 21)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 19)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 18)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 17)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 16)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 15)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 14)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 13)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 12)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 11)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 10)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 9)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.10 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 13)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 12)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 11)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 10)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 9)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.9 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.8 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.7 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.6 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.6 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.6 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.6 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 11)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 10)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 9)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.5 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 8)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 7)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 6)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 5)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.3 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.2 (build 3)**"))
        XCTAssertTrue(versionHistory.contains("## 1.1.0 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.1.0 build 1."))
        XCTAssertTrue(versionHistory.contains("## 1.0.2 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.2 build 2."))
        XCTAssertTrue(versionHistory.contains("## 1.0.2 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.2 build 1."))
        XCTAssertTrue(versionHistory.contains("## 1.0.1 (build 9)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.1 build 9."))
        XCTAssertTrue(versionHistory.contains("## 1.0.1 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.1 build 8."))
        XCTAssertTrue(versionHistory.contains("## 1.0.1 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.1 build 7."))
        XCTAssertTrue(versionHistory.contains("## 1.0.1 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.1 build 6."))
        XCTAssertTrue(versionHistory.contains("## 1.0.1 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.1 build 5."))
        XCTAssertTrue(versionHistory.contains("## 1.0.1 (build 4)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.1 build 4."))
        XCTAssertTrue(versionHistory.contains("## 1.0.1 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.1 build 3."))
        XCTAssertTrue(versionHistory.contains("## 1.0.1 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.1 build 2."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 25)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 25."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 22)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 22."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 20)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 20."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 19)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 19."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 18)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 18."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 17)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 17."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 16)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 16."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 15)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 15."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 14)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 14."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 13)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 13."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 12)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 12."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 11)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 11."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 10)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 10."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 9)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 9."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 8."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 7."))
        XCTAssertTrue(versionHistory.contains("## 1.0.0 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 1.0.0 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 17)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 17."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 16)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 16."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 15)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 15."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 13)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 13."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 12)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 12."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 11)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 11."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 10)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 10."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 9)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 9."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 8."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.12 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.12 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 13)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 13."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 12)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 12."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 11)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 11."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 10)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 10."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 9)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 9."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 8."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.11 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.11 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 21)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 21."))
        XCTAssertTrue(versionHistory.contains("Vitals chart axis labels removed."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 19)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 19."))
        XCTAssertTrue(versionHistory.contains("Vitals chart region proportions."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 18)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 18."))
        XCTAssertTrue(versionHistory.contains("Vitals chart shape and outlier readouts."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 17)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 17."))
        XCTAssertTrue(versionHistory.contains("Vitals detail refinements."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 16)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 16."))
        XCTAssertTrue(versionHistory.contains("Vitals UI polish."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 15)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 15."))
        XCTAssertTrue(versionHistory.contains("New Vitals metric (Beta)."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 14)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 14."))
        XCTAssertTrue(versionHistory.contains("Activity Rings calendar month headers now count each ring's closed days."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 13)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 13."))
        XCTAssertTrue(versionHistory.contains("Share flow opens full screen with the whole card always visible."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 12)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 12."))
        XCTAssertTrue(versionHistory.contains("Photo share cards: move and resize the info block."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 11)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 11."))
        XCTAssertTrue(versionHistory.contains("Redesigned the share card for all non-map backgrounds."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 10)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 10."))
        XCTAssertTrue(versionHistory.contains("The readiness fill's front edge is now a sharp cut"))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 9)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 9."))
        XCTAssertTrue(versionHistory.contains("The Workouts page and workout widgets now follow the calendar into a new month"))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 8."))
        XCTAssertTrue(versionHistory.contains("The loading badge now plays random white pixel-grid animations"))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 7."))
        XCTAssertTrue(versionHistory.contains("Workouts filter and search now also narrow the calendar chart"))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 6."))
        XCTAssertTrue(versionHistory.contains("Chart scrub callouts now float on the topmost layer"))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 5."))
        XCTAssertTrue(versionHistory.contains("Added a current-readiness dot to the Readiness week chart."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 3."))
        XCTAssertTrue(versionHistory.contains("Added a Readiness day view."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.10 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.10 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 13)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 13."))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 12)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 12."))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 11)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 11."))
        XCTAssertTrue(versionHistory.contains("Sleep Stages chart"))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 10)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 10."))
        XCTAssertTrue(versionHistory.contains("workout share function"))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 9)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 9."))
        XCTAssertTrue(versionHistory.contains("Heart Rate by Activity"))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 8."))
        XCTAssertTrue(versionHistory.contains("Energy by Activity"))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 5."))
        XCTAssertTrue(versionHistory.contains("floating capsule status badge"))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.9 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.9 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 8."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.8 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.8 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.7 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.7 build 1."))
        XCTAssertFalse(versionHistory.contains("## 0.9.6 (build 5)"))
        XCTAssertFalse(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.6 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.6 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.6 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.6 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.6 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.6 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.6 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 11)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 11."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 10)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 10."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 9)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 9."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 8."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.5 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.5 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 8)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 8."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 7)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 7."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 6)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 6."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 5)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 5."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.3 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, watch, and test bundle version to 0.9.3 build 1."))
        XCTAssertTrue(versionHistory.contains("## 0.9.2 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.2 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.2 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.2 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.2 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.2 build 1."))
        XCTAssertFalse(readme.contains("Current app version: **0.9.2 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.2 (build 1)**"))
        XCTAssertTrue(versionHistory.contains("## 0.9.1 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.1 build 3."))
        XCTAssertTrue(versionHistory.contains("## 0.9.1 (build 2)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.1 build 2."))
        XCTAssertTrue(versionHistory.contains("## 0.9.1 (build 1)"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.9.1 build 1."))
        XCTAssertFalse(readme.contains("Current app version: **0.9.1 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.1 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.9.1 (build 1)**"))
        XCTAssertTrue(versionHistory.contains("## 0.7.0 (build 2)"))
        XCTAssertTrue(versionHistory.contains("## 0.7.0 (build 1)"))
        XCTAssertTrue(versionHistory.contains("## 0.6.0 (build 2)"))
        XCTAssertTrue(versionHistory.contains("## 0.6.0 (build 1)"))
        XCTAssertTrue(versionHistory.contains("## 0.5.6 (build 4)"))
        XCTAssertTrue(versionHistory.contains("## 0.5.6 (build 3)"))
        XCTAssertTrue(versionHistory.contains("Redesigned the workout detail heart rate chart"))
        XCTAssertTrue(versionHistory.contains("Added step-count day-line support"))
        XCTAssertTrue(versionHistory.contains("Readiness scoring now honors the configured sleep goal"))
        XCTAssertTrue(versionHistory.contains("Updated the app, widget, and test bundle version to 0.5.6 build 4."))
        XCTAssertFalse(readme.contains("Current app version: **0.5.6 (build 4)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.7.0 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.7.0 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.6.0 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.6.0 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.6 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.6 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.6 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.2 (build 4)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.2 (build 3)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.2 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.2 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.1 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.1 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.0 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.5.0 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.4.1"))
        XCTAssertFalse(readme.contains("Current app version: **0.3.5"))
        XCTAssertFalse(readme.contains("Current app version: **0.3.9 (build 2)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.3.4 (build 1)**"))
        XCTAssertFalse(readme.contains("Current app version: **0.3.3 (build 2)**"))
        XCTAssertFalse(settingsSource.contains(#"?? "1""#))
        // Version fallbacks are localized; both literal and String(localized:) forms count.
        XCTAssertGreaterThanOrEqual(
            settingsSource.occurrenceCount(of: #"?? "Unknown""#)
                + settingsSource.occurrenceCount(of: #"?? String(localized: "Unknown")"#),
            4
        )
    }

    func testHealthKitUsageDescriptionListsRequestedHealthCategories() throws {
        let project = try text(at: "body.xcodeproj/project.pbxproj")
        let usageDescription = "Body reads workouts, workout routes, Activity Rings, sleep, heart rate, HRV, beat-to-beat heart rhythm data, blood oxygen, respiratory rate, body measurements, energy, exercise minutes, skin temperature, daylight, steps, cardio fitness, power, cadence, running form, swim strokes, distance, date of birth, and biological sex from Apple Health to power your dashboard, charts, and widgets."

        XCTAssertEqual(project.occurrenceCount(of: usageDescription), 2)
        XCTAssertFalse(project.contains("Body reads workout, sleep, heart, and body measurement data"))
    }

    func testWorkoutRouteReadTypeIsRequested() throws {
        let readTypes = try text(at: "BodyWatchSnapshotKit/BodyHealthReadTypes.swift")
        XCTAssertTrue(readTypes.contains("HKSeriesType.workoutRoute()"))
    }

    func testWorkoutRouteCacheClearsAfterHealthKitAuthorizationGate() throws {
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")

        XCTAssertTrue(storeSource.contains("private func requestHealthKitAuthorization(allowPrompt: Bool = true) async throws"))
        XCTAssertTrue(storeSource.contains("try await engine.requestAuthorization("))
        XCTAssertTrue(storeSource.contains("routeCache.removeAll()"))
        XCTAssertEqual(storeSource.occurrenceCount(of: "try await engine.requestAuthorization("), 1)
        XCTAssertTrue(storeSource.contains("try await requestHealthKitAuthorization(allowPrompt:"))
        XCTAssertTrue(storeSource.contains("if permission == .workouts"))
    }

    func testHealthKitPermissionSheetOnlyOnUserInitiatedEntryPoints() throws {
        let engineSource = try healthKitFetchEngineText()
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")

        // `presentAuthorization` is the single place across every engine file
        // (including +Write) that touches the system `requestAuthorization(`
        // API, so passive callers can never trigger a second, uncoordinated
        // sheet.
        XCTAssertEqual(engineSource.occurrenceCount(of: "healthStore.requestAuthorization("), 1)
        guard let presentRange = engineSource.range(of: "func presentAuthorization(") else {
            XCTFail("Expected presentAuthorization(toShare:read:) in the fetch engine")
            return
        }
        let presentBlock = String(engineSource[presentRange.lowerBound...].prefix(400))
        XCTAssertTrue(presentBlock.contains("healthStore.requestAuthorization("))

        // The write path re-checks the live authorization status after the
        // sheet closes instead of trusting the sheet's own success flag, so a
        // silent denial still resolves as denied.
        guard let writeSource = try? text(at: "Body/Services/HealthKitFetchEngine+Write.swift") else {
            XCTFail("Expected Body/Services/HealthKitFetchEngine+Write.swift")
            return
        }
        guard let requestRange = writeSource.range(of: "func requestWorkoutEffortWriteAuthorization(") else {
            XCTFail("Expected requestWorkoutEffortWriteAuthorization() in HealthKitFetchEngine+Write.swift")
            return
        }
        let requestBlock = String(writeSource[requestRange.lowerBound...].prefix(2_500))
        // `.sharingDenied` must never fail fast here — devices report it while the
        // Health app shows Full Access — so the save stays the arbiter.
        XCTAssertTrue(requestBlock.contains("case .denied, .prompt:"))
        XCTAssertFalse(requestBlock.contains("underlying: HealthKitWorkoutError.authorizationDenied"))

        // Post-write refreshes stay passive, and the two automatic preloads
        // never allow a prompt.
        guard let refreshAfterWriteRange = storeSource.range(of: "func refreshAfterWrite(") else {
            XCTFail("Expected refreshAfterWrite(_:) in HealthKitWorkoutStore.swift")
            return
        }
        let refreshAfterWriteBlock = String(storeSource[refreshAfterWriteRange.lowerBound...].prefix(1_000))
        XCTAssertTrue(refreshAfterWriteBlock.contains("intent: .passiveResume"))

        guard let ensureComparisonRange = storeSource.range(of: "func ensureComparisonMonthsLoaded(") else {
            XCTFail("Expected ensureComparisonMonthsLoaded(for:) in HealthKitWorkoutStore.swift")
            return
        }
        let ensureComparisonBlock = String(storeSource[ensureComparisonRange.lowerBound...].prefix(1_500))
        XCTAssertTrue(ensureComparisonBlock.contains("allowPrompt: false"))

        guard let loadRecentRange = storeSource.range(of: "func loadRecentWorkoutMonthsIfNeeded(") else {
            XCTFail("Expected loadRecentWorkoutMonthsIfNeeded(date:) in HealthKitWorkoutStore.swift")
            return
        }
        let loadRecentBlock = String(storeSource[loadRecentRange.lowerBound...].prefix(1_500))
        XCTAssertTrue(loadRecentBlock.contains("allowPrompt: false"))
    }

    func testWorkoutDetailPresentsFullScreenPushDragToDismiss() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        let sheetStart = try XCTUnwrap(workoutsSource.range(of: "struct BodyWorkoutDetailSheet")?.lowerBound)
        let sheetBlock = String(workoutsSource[sheetStart...].prefix(6_000))

        // Workout details open as a full-bleed navigation push (so the tab bar stays
        // visible), the map bleeds under the status bar, and the nav bar is hidden. There
        // is no close (✕) button — a top-left glass chevron Back button stands in for the
        // hidden nav bar's back button instead, alongside the zoom transition's
        // drag-to-dismiss.
        XCTAssertTrue(workoutsSource.contains(".navigationDestination(item: $selectedWorkoutForDetails) { workout in"))
        XCTAssertTrue(workoutsSource.contains(".navigationTransition(.zoom(sourceID: workout.id, in: workoutZoom))"))
        XCTAssertTrue(workoutsSource.contains("async let loadedRoute = workoutStore.loadWorkoutRoute(for: workout)"))
        XCTAssertTrue(workoutsSource.contains("async let loadedSplitData = workoutStore.loadWorkoutSplitData(for: workout)"))
        // The route lands via a cancel-checked local so a cancelled reload can't flip a
        // routed page to routeless before the Share button settles.
        XCTAssertTrue(workoutsSource.contains("let resolvedRoute = await loadedRoute"))
        XCTAssertTrue(workoutsSource.contains("route = resolvedRoute"))
        XCTAssertTrue(workoutsSource.contains(".ignoresSafeArea(edges: .top)"))
        XCTAssertTrue(workoutsSource.contains(".toolbar(.hidden, for: .navigationBar)"))
        XCTAssertFalse(sheetBlock.contains(#"Image(systemName: "xmark")"#))
        XCTAssertFalse(sheetBlock.contains("private var closeButton"))
        // The detail now has a glass Back button top-left (chevron, not an ✕ close
        // button), so `dismiss` drives it instead of being absent.
        XCTAssertTrue(sheetBlock.contains("@Environment(\\.dismiss) private var dismiss"))
        XCTAssertFalse(sheetBlock.contains("distanceMeters ?? 0"))
        XCTAssertFalse(workoutsSource.contains(".fullScreenCover(item: $selectedWorkoutForDetails)"))
        XCTAssertFalse(workoutsSource.contains("selectedDetent"))
        XCTAssertFalse(sheetBlock.contains(".presentationDetents"))
        XCTAssertTrue(workoutsSource.contains(#"Image(systemName: "chevron.backward")"#))
        XCTAssertTrue(workoutsSource.contains(".modifier(BodyWorkoutBackButtonBackground())"))
    }

    func testActivityAverageRowsRollTheirNumbersOnADaySwitch() throws {
        let source = try bodyHomeViewText()
        let rowStart = try XCTUnwrap(source.range(of: "private func metricActivityAverageRow")?.lowerBound)
        let rowEnd = try XCTUnwrap(
            source.range(of: "private func activityAverageTimeRangeText", range: rowStart..<source.endIndex)?.lowerBound
        )
        let rowBlock = String(source[rowStart..<rowEnd])

        // Rows are keyed by position, never by activity or date: either of those is
        // replaced the moment the day's activities differ, and then the icon, the name,
        // and the numbers could only pop in.
        XCTAssertFalse(source.contains("private func dayStableActivityAverageRows("))
        XCTAssertTrue(source.contains("ForEach(Array(rows.enumerated()), id: \\.offset)"))

        XCTAssertTrue(rowBlock.contains(".bodyLegendNumberFlip(value: valueText)"))
        XCTAssertTrue(rowBlock.contains(".bodyLegendNumberFlip(value: timeRangeText)"))
        // A symbol `Image` ignores `contentTransition`, so the icon crossfades by
        // overlaying the outgoing and incoming glyphs in the tile instead.
        XCTAssertTrue(rowBlock.contains(".transition(.opacity)"))
        XCTAssertTrue(rowBlock.contains(".id(row.symbolName)"))
        XCTAssertTrue(rowBlock.contains("value: row.activity.id"))
        // The activity name and the source name are words, so they crossfade instead.
        XCTAssertTrue(rowBlock.contains(".contentTransition(reduceMotion ? .identity : .opacity)"))
        XCTAssertTrue(rowBlock.contains("value: row.title"))
        XCTAssertTrue(rowBlock.contains("value: source)"))
    }

    func testWorkoutDetailsComparisonLegendNamesEachStateAndBadgesRollOver() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")

        // The legend is one Text whose string changes, so the wording crossfades
        // between states instead of a view being swapped in and out.
        XCTAssertTrue(workoutsSource.contains("private struct BodyWorkoutComparisonLegend: View"))
        XCTAssertTrue(workoutsSource.contains(#"case .ready:"#))
        XCTAssertTrue(workoutsSource.contains(#"return String(localized: "vs 30-day avg")"#))
        XCTAssertTrue(workoutsSource.contains(#"return String(localized: "Calculating…")"#))
        XCTAssertTrue(workoutsSource.contains(#"return String(localized: "Not enough history yet")"#))
        XCTAssertTrue(workoutsSource.contains(".contentTransition(reduceMotion ? .identity : .opacity)"))
        XCTAssertTrue(workoutsSource.contains("if let availability = presentation.comparisonAvailability {"))
        XCTAssertFalse(workoutsSource.contains("let showsComparisonLegend = metrics.contains { $0.comparison != nil }"))

        // The badge digits roll from the "0%" stand-in to the measured percentage.
        XCTAssertTrue(workoutsSource.contains(".bodyLegendNumberFlip(value: comparison.badgeText)"))

        // The settled flag is what keeps "Calculating…" from lasting forever when the
        // months can never load.
        XCTAssertTrue(workoutsSource.contains("comparisonLoadSettled: comparisonMonthsSettled"))
        XCTAssertTrue(workoutsSource.contains("comparisonMonthsSettled = false"))
        XCTAssertTrue(workoutsSource.contains("comparisonMonthsSettled = true"))
    }

    func testReadinessImpactCardExplainsItselfInASheet() throws {
        let detailSource = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")
        let sheetSource = try text(at: "Body/Views/Health/BodyReadinessImpactExplanationSheet.swift")

        // A question-mark button sits at the trailing edge of the Impact by Activity
        // heading — readiness only, since the other kinds' rows are plain averages — and
        // opens the explainer at half height, draggable to full.
        XCTAssertTrue(detailSource.contains(#"Image(systemName: "questionmark.circle")"#))
        XCTAssertTrue(detailSource.contains("if model.kind == .readiness {"))
        XCTAssertTrue(detailSource.contains("showsReadinessImpactExplanation = true"))
        XCTAssertTrue(detailSource.contains(".sheet(isPresented: $showsReadinessImpactExplanation)"))
        XCTAssertTrue(detailSource.contains(".presentationDetents([.medium, .large])"))
        XCTAssertTrue(detailSource.contains("BodyReadinessImpactExplanationSheet()"))
        // Dismissed by the grabber; no toolbar Done button, like the app's other popups.
        XCTAssertFalse(sheetSource.contains(#"Button("Done")"#))

        // The 18 pt glyph is padded out to the 44 pt minimum target and the padding is
        // cancelled again, so the heading's baseline doesn't move.
        XCTAssertTrue(detailSource.contains("private static let activityImpactHelpTapSlop: CGFloat = 13"))
        XCTAssertTrue(detailSource.contains(".padding(Self.activityImpactHelpTapSlop)"))
        XCTAssertTrue(detailSource.contains(".padding(-Self.activityImpactHelpTapSlop)"))

        // The sheet's whole reason for existing: the sub-5% softening that lets the listed
        // impacts sum past the day's starting score, plus the cap that shapes each row.
        XCTAssertTrue(sheetSource.contains("Why the Total Can Exceed Your Score"))
        XCTAssertTrue(sheetSource.contains("The Daily Ceiling"))
        // One shared title for the nav bar, the intro card, and the button's label.
        XCTAssertTrue(sheetSource.contains("static var sheetTitle: String"))
        XCTAssertTrue(detailSource.contains(".accessibilityLabel(BodyReadinessImpactExplanationSheet.sheetTitle)"))
    }

    func testWorkoutDetailsCardExplainsItsMetricsInASheet() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        let sheetSource = try text(at: "Body/Views/BodyWorkoutDetailsExplanationSheet.swift")

        // A question-mark button sits at the trailing edge of the Details heading and
        // opens the explanation sheet at full height.
        XCTAssertTrue(workoutsSource.contains(#"Image(systemName: "questionmark.circle")"#))
        XCTAssertTrue(workoutsSource.contains("showsDetailsExplanation = true"))
        XCTAssertTrue(workoutsSource.contains(".sheet(isPresented: $showsDetailsExplanation)"))
        // Half height by default, draggable to full, and dismissed by the grabber:
        // the sheet carries no toolbar Done button, like the app's other popups.
        XCTAssertTrue(workoutsSource.contains(".presentationDetents([.medium, .large])"))
        XCTAssertTrue(workoutsSource.contains(".presentationDragIndicator(.visible)"))
        XCTAssertFalse(sheetSource.contains(#"Button("Done")"#))

        // The 18 pt glyph is padded out to the 44 pt minimum target and the padding is
        // cancelled again, so the header's height and the "Details" baseline don't move.
        XCTAssertTrue(workoutsSource.contains("private static let detailsHelpTapSlop: CGFloat = 13"))
        XCTAssertTrue(workoutsSource.contains(".padding(Self.detailsHelpTapSlop)"))
        XCTAssertTrue(workoutsSource.contains(".padding(-Self.detailsHelpTapSlop)"))

        // The card and the sheet read one shared list, so the sheet can never describe
        // a tile the grid isn't showing (including the lazily appended HR Recovery).
        XCTAssertTrue(workoutsSource.contains("private func resolvedDetailMetrics(presentation: WorkoutDetailPresentation) -> [WorkoutDetailMetric]"))
        XCTAssertTrue(workoutsSource.contains("let metrics = resolvedDetailMetrics(presentation: presentation)"))
        XCTAssertTrue(workoutsSource.contains("metrics: resolvedDetailMetrics(presentation: presentation)"))

        // Row headings reuse each tile's own localized, unit-correct title rather than
        // a second copy of the metric names.
        XCTAssertTrue(sheetSource.contains("title: metric.title"))
        // Explanations are keyed on Kind, so "Avg Pace" can mean per km/mi for a run and
        // per 100 m/yd for a swim without the two sharing one string.
        XCTAssertTrue(sheetSource.contains("static func explanation(for kind: WorkoutDetailMetric.Kind) -> String"))
        XCTAssertTrue(sheetSource.contains("case .swimPace:"))
        // The comparison paragraph is dropped when the card shows no badges to explain.
        XCTAssertTrue(sheetSource.contains("if showsComparison {"))
        // The user-facing copy deliberately avoids dashes used as punctuation. Scoped to
        // the localized literals: the file's own comments keep the house em-dash style.
        let copyLines = sheetSource
            .components(separatedBy: "\n")
            .filter { $0.contains("String(localized:") }
        XCTAssertGreaterThanOrEqual(copyLines.count, 20, "expected one explanation per metric kind plus the header copy")
        for line in copyLines {
            XCTAssertFalse(line.contains("—"), "em dash in explanation copy: \(line.trimmingCharacters(in: .whitespaces).prefix(60))")
            XCTAssertFalse(line.contains("–"), "en dash in explanation copy: \(line.trimmingCharacters(in: .whitespaces).prefix(60))")
        }
    }

    func testWorkoutListSheetRowsOpenFullScreenDetail() throws {
        let source = try text(at: "Body/Views/BodyWorkoutListSheet.swift")

        // The calendar-day / workout-type list popups make their rows tappable into
        // the same full-screen workout detail used by the Workouts list.
        XCTAssertTrue(source.contains("@State private var selectedWorkout: WorkoutSummary?"))
        XCTAssertTrue(source.contains("selectedWorkout = workout"))
        XCTAssertTrue(source.contains(".matchedTransitionSource(id: workout.id, in: workoutZoom)"))
        XCTAssertTrue(source.contains(".fullScreenCover(item: $selectedWorkout) { workout in"))
        XCTAssertTrue(source.contains("BodyWorkoutDetailSheet(workout: workout)"))
        XCTAssertTrue(source.contains(".navigationTransition(.zoom(sourceID: workout.id, in: workoutZoom))"))
        // The Done button was removed; the popups dismiss via the sheet grabber.
        XCTAssertFalse(source.contains(#"Button("Done")"#))
        XCTAssertTrue(source.contains(".toolbar(.hidden, for: .navigationBar)"))
    }

    func testWorkoutCustomNamePlumbing() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")

        XCTAssertGreaterThanOrEqual(
            workoutsSource.occurrenceCount(of: "customName: workoutStore.workoutCustomNames[workout.id]"),
            2
        )
        XCTAssertTrue(workoutsSource.contains(".alert(\"Rename Workout\""))
        XCTAssertGreaterThanOrEqual(workoutsSource.occurrenceCount(of: "workoutCustomNames"), 4)

        let listSheetSource = try text(at: "Body/Views/BodyWorkoutListSheet.swift")
        XCTAssertTrue(listSheetSource.contains("customName: workoutStore.workoutCustomNames[workout.id]"))
        XCTAssertTrue(listSheetSource.contains("Text(customName ?? workout.type.displayName)"))

        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        XCTAssertTrue(storeSource.contains("func setCustomName(_ name: String?, workoutID: UUID)"))
        XCTAssertTrue(storeSource.contains("workoutCustomNamesKey = \"workoutCustomNames\""))

        let summarySource = try text(at: "BodyMetricsKit/WorkoutSummary.swift")
        XCTAssertTrue(summarySource.contains("static func normalizedCustomName(_ raw: String?) -> String?"))
    }

    func testWorkoutHeartRateSeriesReadFailureIsNotCachedAsEmpty() throws {
        // The detail sheet re-reads heart rate at full resolution because the summary
        // only carries a <=96-point downsample. The engine read must therefore throw
        // on a failure (a dismissed sheet, a locked device) rather than answer `[]`,
        // which the store would otherwise cache as confirmed-absent for the session.
        let seriesSource = try text(at: "Body/Services/HealthKitFetchEngine+MetricSeries.swift")
        XCTAssertTrue(seriesSource.contains("func workoutHeartRateSamples(workoutID: UUID) async throws -> [WorkoutHeartRateSample]"))
        // Must be a series-sample read: the watch stores workout heart rate as series
        // samples, and a plain HKSampleQuery would return one aggregated entry per
        // series blob instead of the readings inside it.
        XCTAssertTrue(seriesSource.contains("HKQuantitySeriesSampleQueryDescriptor("))
        XCTAssertTrue(seriesSource.contains("beatsPerMinute.isFinite, beatsPerMinute > 0"))

        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        XCTAssertTrue(storeSource.contains("private var heartRateSeriesCache: [UUID: [WorkoutHeartRateSample]] = [:]"))
        XCTAssertTrue(storeSource.contains("func loadWorkoutHeartRateSeries(for workout: WorkoutSummary) async -> [WorkoutHeartRateSample]?"))

        let loadStart = try XCTUnwrap(storeSource.range(of: "func loadWorkoutHeartRateSeries(for workout: WorkoutSummary) async -> [WorkoutHeartRateSample]?")?.lowerBound)
        let loadBlock = String(storeSource[loadStart...].prefix(1_400))
        // Heart data rides the Heart toggle, and the load must not pin a result taken
        // under a stale cache generation.
        XCTAssertTrue(loadBlock.contains("guard permissionSelection.includes(.heart) else {"))
        XCTAssertTrue(loadBlock.contains("Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch)"))
        // An empty read is only cached once the workout has settled; a recent one may
        // still be syncing samples from the watch.
        XCTAssertTrue(loadBlock.contains("} else if Date().timeIntervalSince(workout.effectiveEndDate) > 24 * 60 * 60 {"))

        // The catch must return an UNCACHED nil so reopening the sheet retries, the
        // same rule the splits load follows.
        let catchStart = try XCTUnwrap(loadBlock.range(of: "} catch {")?.lowerBound)
        let catchBlock = String(loadBlock[catchStart...].prefix(210))
        XCTAssertTrue(catchBlock.contains("return nil"))
        XCTAssertFalse(catchBlock.contains("heartRateSeriesCache["))

        // Cleared at every gate the sibling detail caches are: the authorization
        // gate, both permission toggles that can change what it holds (Workouts and
        // Heart), Clear Cache, and the eager clear when the app enters the
        // background.
        XCTAssertEqual(storeSource.occurrenceCount(of: "heartRateSeriesCache.removeAll()"), 5)
    }

    func testWorkoutStepSamplesPropagateReadFailuresInsteadOfSwallowingErrors() throws {
        let splitsSource = try text(at: "Body/Services/HealthKitFetchEngine+Splits.swift")

        // H8: a cancelled/transient step-sample read (dismissed detail sheet, XPC
        // drop) must propagate like the distance/route reads and `fetchWorkout(id:)`
        // already do, instead of collapsing to an empty cadence column that the
        // store then caches as confirmed data for the rest of the session.
        XCTAssertTrue(splitsSource.contains("private func workoutStepSamples(for workout: HKWorkout, type: BodyWorkoutType) async throws -> [WorkoutStepSample]"))
        XCTAssertTrue(splitsSource.contains("private func readWorkoutStepSamples(for workout: HKWorkout, stepType: HKQuantityType) async throws -> [WorkoutStepSample]"))
        XCTAssertTrue(splitsSource.contains("stepSamples: try await workoutStepSamples(for: workout, type: type)"))
        XCTAssertFalse(splitsSource.contains("catch {\n            return []\n        }"))

        // The store's catch must keep returning an UNCACHED `.empty` so a retry on
        // reopen can recover — it must not also write the negative result into
        // `distanceSampleCache`, which would make it permanent for the session.
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let loadStart = try XCTUnwrap(storeSource.range(of: "func loadWorkoutSplitData(for workout: WorkoutSummary) async -> WorkoutSplitData")?.lowerBound)
        let loadBlock = String(storeSource[loadStart...].prefix(900))
        let catchStart = try XCTUnwrap(loadBlock.range(of: "} catch {")?.lowerBound)
        let catchBlock = String(loadBlock[catchStart...].prefix(195))

        XCTAssertTrue(catchBlock.contains("return .empty"))
        XCTAssertFalse(catchBlock.contains("distanceSampleCache["))
    }

    func testDaySampleSidecarIsPersistedFromEnoughCallSites() throws {
        // `persistDaySampleSidecar()` is what makes the day-sample sidecar durable —
        // including the lazily fetched intraday merge that lets the metric detail
        // Day View render cached data instantly on the next launch. Guard the call
        // count so a future refactor can't silently drop that persistence. The
        // three deliberate full-strip sites call `truncatePersistedDaySamples()`
        // instead (H-17: a save of an all-empty payload now merges into a
        // populated sidecar rather than truncating it, so truncation there is
        // explicit), which is why the count is lower than the pre-Phase-3 11.
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")

        XCTAssertGreaterThanOrEqual(storeSource.occurrenceCount(of: "persistDaySampleSidecar()"), 6)
    }

    func testBackgroundWarningRefreshIsRegisteredAndScoped() throws {
        // Info.plist must declare the background mode and the exact task
        // identifier the scheduler registers/submits, or BGTaskScheduler
        // silently refuses to run the task on device.
        let infoPlist = try text(at: "Body/Info.plist")
        XCTAssertTrue(infoPlist.contains("<string>fetch</string>"))
        XCTAssertTrue(infoPlist.contains("<string>com.zihengthedeveloper.Body.warningRefresh</string>"))

        let schedulerSource = try text(at: "Body/Services/BodyBackgroundRefreshScheduler.swift")
        XCTAssertTrue(schedulerSource.contains(#"static let taskIdentifier = "com.zihengthedeveloper.Body.warningRefresh""#))
        XCTAssertTrue(infoPlist.contains("com.zihengthedeveloper.Body.warningRefresh"))
        XCTAssertTrue(schedulerSource.contains("com.zihengthedeveloper.Body.warningRefresh"))

        // The background evaluator must stay off the main actor and must not
        // reach into `HealthKitWorkoutStore`'s @MainActor-isolated store
        // surface — only its `nonisolated` custom-groups loader, which is the
        // one piece of that store the evaluator legitimately needs.
        let evaluatorSource = try text(at: "Body/Services/MetricWarningBackgroundEvaluator.swift")
        XCTAssertTrue(evaluatorSource.contains("actor MetricWarningBackgroundEvaluator"))
        XCTAssertFalse(evaluatorSource.contains("@MainActor"))
        XCTAssertTrue(evaluatorSource.contains("HealthKitWorkoutStore.loadCustomHealthSourceGroups(defaults:"))
        XCTAssertEqual(evaluatorSource.occurrenceCount(of: "HealthKitWorkoutStore."), 1)
    }

    func testTestPlanCoversCurrentBranchAndBodyProSurface() throws {
        let testPlan = try text(at: "TestPlan.md")

        XCTAssertTrue(testPlan.contains("branch `body-v1.1.0`"))
        XCTAssertFalse(testPlan.contains("branch `body-v1.0.2`"))
        XCTAssertFalse(testPlan.contains("branch `body-1.0.1`"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.12`"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.11`"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.10`"))
        XCTAssertTrue(testPlan.contains("app version 1.1.0 build 1)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.2 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 4)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.1 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 25)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 23)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 22)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 21)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 20)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 19)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 18)"))
        XCTAssertTrue(testPlan.contains("Settings › About › Onboarding"))
        // The first-run intro's automated and manual coverage.
        XCTAssertTrue(testPlan.contains("BodyIntroAnimationTests"))
        XCTAssertTrue(testPlan.contains("intro plays"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 17)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 16)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 15)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 14)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 1.0.0 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 17)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 16)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 15)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.12 build 1)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.11 build 1)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 21)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 19)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 18)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 17)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 16)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 15)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.10 build 1)"))
        XCTAssertTrue(testPlan.contains("sync status badge"))
        XCTAssertTrue(testPlan.contains("Energy by Activity"))
        XCTAssertTrue(testPlan.contains("Low Heart Rate"))
        XCTAssertTrue(testPlan.contains("High Heart Rate"))
        XCTAssertTrue(testPlan.contains("Low Blood Oxygen"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.9`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 13)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 12)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.9 build 1)"))
        XCTAssertFalse(testPlan.contains("branch `body-0.9.8`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.8 build 1)"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.9.7`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.7 build 1)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.6 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.6 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.6 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.6 build 1)"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.9.6`"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.9.5`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 11)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 10)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 9)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 8)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 7)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 6)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 5)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 3)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 2)"))
        XCTAssertFalse(testPlan.contains("app version 0.9.5 build 1)"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.9.3`"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 8"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 7"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 6"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 5"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 3"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 2"))
        XCTAssertFalse(testPlan.contains("app version 0.9.3 build 1"))
        XCTAssertFalse(testPlan.contains("app version 0.9.2 build 1"))
        XCTAssertFalse(testPlan.contains("app version 0.9.1 build 3"))
        XCTAssertFalse(testPlan.contains("app version 0.9.1 build 2"))
        XCTAssertFalse(testPlan.contains("app version 0.9.1 build 1"))
        XCTAssertFalse(testPlan.contains("app version 0.7.0 build 1"))
        XCTAssertFalse(testPlan.contains("branch `body-v0.6.0`"))
        XCTAssertFalse(testPlan.contains("app version 0.6.0 build 2"))
        XCTAssertFalse(testPlan.contains("branch `codex/body-v0.3.0`"))
        XCTAssertFalse(testPlan.contains("branch `codex/body-v0.3.4`"))
        XCTAssertTrue(testPlan.contains("Body/Views/BodyProView.swift"))
        XCTAssertTrue(testPlan.contains("Body Pro entry navigation"))
        XCTAssertTrue(testPlan.contains("Body Pro icon flip"))
        XCTAssertFalse(testPlan.contains("version-card unlock"))
        XCTAssertFalse(testPlan.contains("creator-surprise icon sheet"))
    }

    func testWorkoutsMonthLoadShowsFloatingLoadingCapsule() throws {
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")

        XCTAssertTrue(workoutsSource.contains("@State private var pendingMonthSelection: PendingMonthSelection?"))
        XCTAssertTrue(workoutsSource.contains("if pendingMonthSelection != nil {"))
        XCTAssertTrue(workoutsSource.contains("BodySyncStatusBadgeLabel(icon: .spinner, text: \"Loading data...\")"))
        XCTAssertFalse(workoutsSource.contains("bodyPullToRefreshLoadingOverlay"))
        XCTAssertFalse(workoutsSource.contains("BodyWorkoutMonthLoadingBanner"))
        XCTAssertFalse(workoutsSource.contains("withTaskGroup"))
        XCTAssertTrue(workoutsSource.contains("pendingMonthSelection = PendingMonthSelection(request: token, monthYear: monthYear)"))
        XCTAssertTrue(workoutsSource.contains("await workoutStore.loadMonthIfNeeded(month: monthYear.month, year: monthYear.year)"))
        XCTAssertTrue(workoutsSource.contains("private func monthLoadTask(for monthYear: BodyMonthYear) -> Task<Bool, Never>"))
        XCTAssertTrue(workoutsSource.contains("func finishPendingMonthSelection(token: UUID, didLoad: Bool?)"))
        XCTAssertTrue(workoutsSource.contains("guard let pending = pendingMonthSelection, pending.request == token else"))
        XCTAssertTrue(workoutsSource.contains("try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)"))
        XCTAssertTrue(workoutsSource.contains("if didLoad == true {"))
        XCTAssertTrue(workoutsSource.contains("applyMonthSelection(pending.monthYear)"))
        XCTAssertTrue(workoutsSource.contains("return false"))
    }

    func testHealthSyncBadgeIsWiredIntoMainTabWithGlassAndMaterialFallback() throws {
        let mainTabSource = try text(at: "Body/Views/MainTabView.swift")
        let badgeSource = try text(at: "Body/Views/BodyHealthSyncBadge.swift")
        let homeSource = try text(at: "Body/Views/BodyHomeView.swift")
        let metricDetailSource = try text(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")
        let workoutsSource = try text(at: "Body/Views/BodyWorkoutsView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let xcstrings = try text(at: "Body/Localizable.xcstrings")

        XCTAssertTrue(mainTabSource.contains(".overlay(alignment: .top) {"))
        XCTAssertTrue(mainTabSource.contains("BodyHealthSyncBadge(isSuppressed: isFirstLaunchOverlayPresented || showsOnboarding)"))

        XCTAssertTrue(badgeSource.contains("import Accessibility"))
        XCTAssertTrue(badgeSource.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(badgeSource.contains(".glassEffect(.regular, in: .capsule)"))
        XCTAssertTrue(badgeSource.contains(".fill(.regularMaterial)"))
        XCTAssertTrue(badgeSource.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(badgeSource.contains("syncBadgeSuccessCount != successCountAtSyncStart"))
        XCTAssertTrue(storeSource.contains("@Published private(set) var syncBadgeSuccessCount = 0"))
        XCTAssertTrue(badgeSource.contains("struct BodySyncStatusBadgeLabel"))
        XCTAssertTrue(badgeSource.contains("\"Loading data...\""))
        XCTAssertFalse(badgeSource.contains("Syncing health data"))
        XCTAssertTrue(badgeSource.contains("\"Health data updated\""))
        XCTAssertTrue(badgeSource.contains(".accessibilityAddTraits(.updatesFrequently)"))

        // The loading icon is the native white pixel-grid loader (SwiftPixelGrid
        // design), driven from wall-clock time via TimelineView (no
        // onAppear-started animation), picking a random delay pattern per
        // appearance, with the system ProgressView kept as the Reduce Motion
        // fallback.
        XCTAssertTrue(badgeSource.contains("struct BodyPixelGridLoader"))
        XCTAssertTrue(badgeSource.contains("patterns.randomElement()"))
        XCTAssertTrue(badgeSource.contains("TimelineView(.animation"))
        XCTAssertTrue(badgeSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(badgeSource.contains("if reduceMotion {"))
        XCTAssertTrue(badgeSource.contains("ProgressView().controlSize(.small).tint(.secondary)"))
        XCTAssertTrue(badgeSource.contains("BodyPixelGridLoader()"))

        XCTAssertFalse(homeSource.contains("bodyPullToRefreshLoadingOverlay"))
        XCTAssertFalse(homeSource.contains("BodyDataLoadingOverlay"))
        XCTAssertFalse(metricDetailSource.contains("bodyPullToRefreshLoadingOverlay"))
        XCTAssertFalse(metricDetailSource.contains("BodyDataLoadingOverlay"))
        XCTAssertFalse(workoutsSource.contains("bodyPullToRefreshLoadingOverlay"))
        XCTAssertFalse(workoutsSource.contains("BodyDataLoadingOverlay"))

        XCTAssertTrue(xcstrings.contains("\"Loading data...\" : {"))
        XCTAssertFalse(xcstrings.contains("\"Syncing health data…\" : {"))
        XCTAssertTrue(xcstrings.contains("\"Health data updated\" : {"))
    }

    func testDeadChartsViewAndHealthCardAccessoryBranchAreRemoved() throws {
        let oldChartsViewURL = projectRoot.appendingPathComponent("Body/Views/BodyChartsView.swift")
        let chartsSource = try text(at: "Body/Views/BodyWorkoutListSheet.swift")
        let homeSource = try bodyHomeViewText()

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldChartsViewURL.path))
        XCTAssertFalse(chartsSource.contains("struct BodyChartsView"))
        XCTAssertFalse(chartsSource.contains("BodyChartsScrollTransitionShade"))
        XCTAssertFalse(chartsSource.contains("BodyChartsLoadingBanner"))
        XCTAssertFalse(homeSource.contains("AccessoryMetric"))
        XCTAssertFalse(homeSource.contains("accessoryMetrics"))
        XCTAssertFalse(homeSource.contains("accessoryContent"))
        XCTAssertFalse(homeSource.contains("accessoryMetricStrip"))
    }

    func testSleepAndMetricDayPickersShareDateTileHelper() throws {
        let homeSource = try bodyHomeViewText()

        XCTAssertTrue(homeSource.contains("private var recentDatePickerDates: [Date]"))
        XCTAssertTrue(homeSource.contains("private func datePicker("))
        XCTAssertTrue(homeSource.contains("private func dateTile("))
        XCTAssertTrue(homeSource.contains("BodyDateSliderTileLabel.primaryText(for: dayStart, today: today, calendar: calendar)"))
        XCTAssertFalse(homeSource.contains("private var sleepDatePickerDates"))
        XCTAssertFalse(homeSource.contains("private var metricDatePickerDates"))
        XCTAssertFalse(homeSource.contains("private func sleepDateTile"))
        XCTAssertFalse(homeSource.contains("private func metricDateTile"))
        XCTAssertFalse(homeSource.contains("Text(dayStart.formatted(.dateTime.weekday(.abbreviated)))"))
    }

    func testProjectDateMathUsesBodyGregorianForSleepAxisAndWidgetTimeline() throws {
        let homeSource = try bodyHomeViewText()
        let widgetSource = try text(at: "BodyWidgetExtension/WorkoutCalendarWidget.swift")

        XCTAssertFalse(homeSource.contains("let calendar = Calendar.current"))
        XCTAssertFalse(widgetSource.contains("Calendar.current"))
        XCTAssertTrue(homeSource.contains("let calendar = Calendar.bodyGregorian"))
        XCTAssertTrue(widgetSource.contains("let calendar = Calendar.bodyGregorian"))
        XCTAssertTrue(widgetSource.contains("calendar.date(byAdding: .minute"))
    }

    func testAppIconAssetsIncludePrimaryAndAlternateOptions() throws {
        // Every shipping app icon is an Icon Composer (.icon) bundle at its target
        // root — primary AppIcon plus five color alternates, and the watch + widget.
        let iconBundles = [
            "Body/AppIcon.icon/icon.json",
            "Body/BodyBlack.icon/icon.json",
            "Body/BodyGray.icon/icon.json",
            "Body/BodyPink.icon/icon.json",
            "Body/BodyPurple.icon/icon.json",
            "Body/BodyWhite.icon/icon.json",
            "BodyWatch/AppIcon.icon/icon.json",
            "BodyWidgetExtension/AppIcon.icon/icon.json"
        ]

        for path in iconBundles {
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
            XCTAssertGreaterThan(data.count, 0, path)
        }

        // In-app icon-picker thumbnails, one per standard color.
        let previewAssets = [
            "Body/Assets.xcassets/BodyIcon01.imageset/BodyIcon01.png",
            "Body/Assets.xcassets/BodyIconBlack.imageset/BodyIconBlack.png",
            "Body/Assets.xcassets/BodyIconGray.imageset/BodyIconGray.png",
            "Body/Assets.xcassets/BodyIconPink.imageset/BodyIconPink.png",
            "Body/Assets.xcassets/BodyIconPurple.imageset/BodyIconPurple.png",
            "Body/Assets.xcassets/BodyIconWhite.imageset/BodyIconWhite.png"
        ]

        for path in previewAssets {
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
            XCTAssertGreaterThan(data.count, 0, path)
        }

        // The legacy .appiconset artwork and the removed "Present" creator-surprise
        // alternates (icons + preview thumbnails) must no longer exist.
        let removedPaths = [
            "Body/Assets.xcassets/AppIcon.appiconset",
            "Body/Assets.xcassets/BodyBlack.appiconset",
            "Body/Assets.xcassets/BodyClassicAlt.appiconset",
            "Body/Assets.xcassets/BodyBlackAlt.appiconset",
            "Body/Assets.xcassets/BodyGrayAlt.appiconset",
            "Body/Assets.xcassets/BodyPinkAlt.appiconset",
            "Body/Assets.xcassets/BodyPurpleAlt.appiconset",
            "Body/Assets.xcassets/BodyWhiteAlt.appiconset",
            "Body/Assets.xcassets/BodyIconClassicAlt.imageset",
            "Body/Assets.xcassets/BodyIconBlackAlt.imageset",
            "Body/Assets.xcassets/BodyIconWhiteAlt.imageset",
            "BodyWidgetExtension/Assets.xcassets/AppIcon.appiconset"
        ]

        for path in removedPaths {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent(path).path),
                path
            )
        }
    }

    func testSettingsExposesStandardAppIconOptionsWithoutCreatorSurprise() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let appearanceSource = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")

        // The "Present" creator-surprise icons and their version-tap unlock were removed.
        XCTAssertFalse(settingsSource.contains("versionTapCount"))
        XCTAssertFalse(settingsSource.contains("creatorSurpriseIconsUnlocked"))
        XCTAssertFalse(settingsSource.contains("showingCreatorSurprise"))
        XCTAssertFalse(settingsSource.contains("BodyCreatorSurpriseOverlay"))
        XCTAssertFalse(settingsSource.contains("BodyCreatorRibbon"))
        XCTAssertFalse(settingsSource.contains("availableOptions(includeCreatorSurprises:"))
        XCTAssertFalse(settingsSource.contains(#"descriptor: "Present""#))
        XCTAssertFalse(appearanceSource.contains("creatorSurpriseIconsUnlockedKey"))

        // The six standard color options remain.
        let requiredLabels = [
            #"displayName: "Classic""#,
            #"descriptor: "Original""#,
            #"displayName: "Rose""#,
            #"descriptor: "Pink""#,
            #"displayName: "Violet""#,
            #"descriptor: "Purple""#,
            #"displayName: "Midnight""#,
            #"descriptor: "Black""#,
            #"displayName: "Neutral""#,
            #"descriptor: "Gray""#,
            #"displayName: "Light""#,
            #"descriptor: "White""#
        ]

        for label in requiredLabels {
            XCTAssertTrue(settingsSource.contains(label), label)
        }
    }

    func testSettingsMetricsSectionGroupsUnitsSummaryCardsAndTrendControls() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let homeSource = try bodyHomeViewText()
        let appearanceSource = try text(at: "Body/Models/BodyAppearancePreference.swift")
        let appearanceStart = try XCTUnwrap(settingsSource.range(of: "private var appearanceSection: some View")?.lowerBound)
        let appearanceBlock = String(settingsSource[appearanceStart...].prefix(2_500))
        let metricsStart = try XCTUnwrap(settingsSource.range(of: "private var metricsSection: some View")?.lowerBound)
        let metricsBlock = String(settingsSource[metricsStart...].prefix(4_000))
        let stackStart = try XCTUnwrap(
            settingsSource.range(of: "VStack(alignment: .leading, spacing: 22) {")?.lowerBound
        )
        let settingsStack = String(settingsSource[stackStart...].prefix(400))
        let appearanceSectionRange = try XCTUnwrap(settingsStack.range(of: "appearanceSection"))
        let metricsSectionRange = try XCTUnwrap(settingsStack.range(of: "metricsSection"))
        let dataSectionRange = try XCTUnwrap(settingsStack.range(of: "dataSection"))
        let iconRange = try XCTUnwrap(appearanceBlock.range(of: #"title: "Icon""#))
        let sleepRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Sleep""#))
        let unitsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Units""#))
        let summaryCardsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Summary Cards""#))
        let trendCardsRange = try XCTUnwrap(metricsBlock.range(of: #"title: "Trend Cards""#))

        XCTAssertLessThan(appearanceSectionRange.lowerBound, metricsSectionRange.lowerBound)
        XCTAssertLessThan(metricsSectionRange.lowerBound, dataSectionRange.lowerBound)
        XCTAssertTrue(metricsBlock.contains(#"BodySettingsCardSection("Metrics")"#))
        XCTAssertLessThan(sleepRange.lowerBound, unitsRange.lowerBound)
        XCTAssertLessThan(unitsRange.lowerBound, summaryCardsRange.lowerBound)
        XCTAssertLessThan(summaryCardsRange.lowerBound, trendCardsRange.lowerBound)
        XCTAssertFalse(metricsBlock.contains(#"title: "Sleep Goal""#))
        XCTAssertFalse(appearanceBlock.contains(#"title: "Summary Cards""#))
        XCTAssertFalse(appearanceBlock.contains(#"title: "Charts Range""#))
        XCTAssertFalse(appearanceBlock.contains(#"title: "Trend Cards""#))
        XCTAssertFalse(settingsSource.contains("private var unitSection: some View"))
        XCTAssertFalse(settingsSource.contains(#"title: "Measurement""#))
        XCTAssertTrue(settingsSource.contains(#"BodySettingsAboutSheetScaffold(title: "Trend Cards")"#))
        XCTAssertFalse(settingsSource.contains(#".navigationTitle("Default Trend Range")"#))
        XCTAssertFalse(settingsSource.contains(#"BodySettingsAboutSheetScaffold(title: "Home Trend Cards")"#))
        XCTAssertLessThan(iconRange.lowerBound, appearanceBlock.endIndex)
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.summaryCardSelectionKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.showsLeadingTrailingAwakeSleepStagesKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey)"))
        XCTAssertTrue(settingsSource.contains("case .sleepDurationGoal:"))
        XCTAssertTrue(settingsSource.contains("case .summaryCards:"))
        XCTAssertTrue(settingsSource.contains("case .homeTrendCards:"))
        XCTAssertTrue(settingsSource.contains("BodySleepSettingsSheet("))
        XCTAssertTrue(settingsSource.contains(#"BodySettingsAboutSheetScaffold(title: "Sleep")"#))
        XCTAssertTrue(settingsSource.contains(#"BodySettingsCardSection("Sleep Stages")"#))
        XCTAssertTrue(settingsSource.contains(#"Text("Show Awake Under 1 Min")"#))
        XCTAssertTrue(settingsSource.contains("Toggle(\"Show Awake Under 1 Min\""))
        XCTAssertTrue(settingsSource.contains(".onChange(of: showsSubMinuteAwakeSleepStages)"))
        XCTAssertTrue(settingsSource.contains(#"Text("Show Awake at Start & End")"#))
        XCTAssertTrue(settingsSource.contains("Toggle(\"Show Awake at Start & End\""))
        XCTAssertTrue(settingsSource.contains(".onChange(of: showsLeadingTrailingAwakeSleepStages)"))
        XCTAssertTrue(settingsSource.contains("BodySummaryCardsSettingsSheet("))
        XCTAssertTrue(settingsSource.contains("BodyHomeTrendCardsSettingsSheet("))
        XCTAssertTrue(settingsSource.contains("ForEach(BodyHomeCardKind.defaultOrder)"))
        XCTAssertTrue(settingsSource.contains("ForEach(BodyHomeTrendCardKind.defaultOrder)"))
        XCTAssertTrue(settingsSource.contains("BodySummaryCardToggleRow("))
        XCTAssertTrue(settingsSource.contains("BodyHomeTrendCardToggleRow("))
        XCTAssertTrue(appearanceSource.contains("var betaVersionLabel: LocalizedStringKey?"))
        XCTAssertTrue(appearanceSource.contains("var isBeta: Bool"))
        XCTAssertTrue(appearanceSource.contains("case .readiness:"))
        XCTAssertTrue(settingsSource.contains("if let betaVersionLabel = card.betaVersionLabel"))
        XCTAssertEqual(settingsSource.occurrenceCount(of: #"Text("v1")"#), 1)
        XCTAssertEqual(settingsSource.occurrenceCount(of: #"Text("v2")"#), 0)
        XCTAssertEqual(settingsSource.occurrenceCount(of: #"Text("v3")"#), 1)
        // The Readiness AI sheet's toggle row carries the only Beta v2 badge; the
        // Stress summary-card row carries its own "Beta v1" chip via betaVersionLabel.
        XCTAssertEqual(settingsSource.occurrenceCount(of: #"Text("Beta v2")"#), 1)
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.defaultTrendRangeKey)"))
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey)"))
        XCTAssertTrue(homeSource.contains("@AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey)"))
        XCTAssertTrue(homeSource.contains("initialTrendRange: defaultTrendRange"))
        XCTAssertTrue(homeSource.contains("idealSleepDuration: sleepDurationGoal"))
        XCTAssertTrue(homeSource.contains("BodyHomeTrendCardFactory.cards("))
        XCTAssertTrue(homeSource.contains("selection: homeTrendCardSelection"))
    }

    func testSettingsThemeRowIsRemovedForDarkThemeGate() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let appearanceStart = try XCTUnwrap(settingsSource.range(of: "private var appearanceSection: some View")?.lowerBound)
        let appearanceBlock = String(settingsSource[appearanceStart...].prefix(2_000))
        let backgroundRange = try XCTUnwrap(appearanceBlock.range(of: #"title: "Background""#))

        let firstRowRange = try XCTUnwrap(appearanceBlock.range(of: #"BodySettingsRowLabel("#))
        XCTAssertLessThan(firstRowRange.lowerBound, backgroundRange.lowerBound)
        XCTAssertFalse(appearanceBlock.contains(#"title: "Theme""#))
        XCTAssertFalse(appearanceBlock.contains("currentTheme"))
        XCTAssertFalse(settingsSource.contains("selectedThemeRawValue"))
        XCTAssertFalse(settingsSource.contains("BodyAppTheme"))
        XCTAssertFalse(appearanceBlock.contains("Theme selection is disabled"))
        XCTAssertFalse(appearanceBlock.contains("activeSheet = .theme"))
        XCTAssertFalse(settingsSource.contains("BodyThemePickerSheet"))
        XCTAssertFalse(settingsSource.contains("case theme"))
        XCTAssertFalse(settingsSource.contains("case .theme"))
    }

    func testSettingsUnitsPageHasSystemToggleAndIndependentUnitControls() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let appearanceSource = try text(at: "BodyMetricsKit/BodyHealthSelections.swift")
        let formatterSource = try text(at: "BodyMetricsKit/WorkoutSummary.swift")

        let unitSheetStart = try XCTUnwrap(settingsSource.range(of: "private struct BodyUnitPreferencePickerSheet")?.lowerBound)
        let unitSheetBlock = String(settingsSource[unitSheetStart...].prefix(8_000))

        XCTAssertTrue(appearanceSource.contains("followsSystemUnitsKey"))
        XCTAssertTrue(appearanceSource.contains("selectedWeightUnitKey"))
        XCTAssertTrue(appearanceSource.contains("selectedDistanceUnitKey"))
        XCTAssertTrue(appearanceSource.contains("selectedEnergyUnitKey"))
        XCTAssertTrue(appearanceSource.contains("selectedTemperatureUnitKey"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.followsSystemUnitsKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.selectedWeightUnitKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.selectedDistanceUnitKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.selectedEnergyUnitKey)"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey)"))
        XCTAssertTrue(unitSheetBlock.contains(#"Toggle("Follow System""#))
        XCTAssertTrue(unitSheetBlock.contains(#"title: "Weight""#))
        XCTAssertTrue(unitSheetBlock.contains(#"title: "Distance""#))
        XCTAssertTrue(unitSheetBlock.contains(#"title: "Energy""#))
        XCTAssertTrue(unitSheetBlock.contains(#"title: "Temperature""#))
        XCTAssertTrue(unitSheetBlock.contains("BodyValueFormat.WeightUnitPreference.allCases"))
        XCTAssertTrue(unitSheetBlock.contains("BodyValueFormat.DistanceUnitPreference.allCases"))
        XCTAssertTrue(unitSheetBlock.contains("BodyValueFormat.EnergyUnitPreference.allCases"))
        XCTAssertTrue(unitSheetBlock.contains("BodyValueFormat.TemperatureUnitPreference.allCases"))
        XCTAssertTrue(unitSheetBlock.contains("isEnabled: !followsSystemUnits"))
        XCTAssertTrue(unitSheetBlock.contains(".disabled(followsSystemUnits)"))
        XCTAssertTrue(formatterSource.contains("enum WeightUnitPreference"))
        XCTAssertTrue(formatterSource.contains("enum DistanceUnitPreference"))
        XCTAssertTrue(formatterSource.contains("enum EnergyUnitPreference"))
        XCTAssertTrue(formatterSource.contains("enum TemperatureUnitPreference"))
    }

    func testSettingsDataSectionExposesSyncStatusAndCacheControls() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let dataStart = try XCTUnwrap(settingsSource.range(of: "private var dataSection: some View")?.lowerBound)
        let dataBlock = String(settingsSource[dataStart...].prefix(3_000))
        XCTAssertTrue(dataBlock.contains("BodySettingsDataTab.allCases"))
        XCTAssertTrue(dataBlock.contains("activeSheet = tab.sheet"))
        XCTAssertTrue(dataBlock.contains("dataValue(for: tab)"))
        XCTAssertTrue(settingsSource.contains("return permissionSummaryText"))
        XCTAssertFalse(settingsSource.contains(#""Grant Access""#))
        XCTAssertTrue(settingsSource.contains(#"return "Data Refresh""#))
        XCTAssertFalse(settingsSource.contains(#"return "Health Data Sync""#))
        XCTAssertTrue(settingsSource.contains(#"return "Cache""#))
        XCTAssertTrue(settingsSource.contains("case .syncStatus:"))
        XCTAssertTrue(settingsSource.contains("case .cache:"))
        XCTAssertTrue(settingsSource.contains("case .permissions:"))
        XCTAssertTrue(settingsSource.contains("BodyHealthPermissionsSettingsSheet(workoutStore: workoutStore)"))
        XCTAssertTrue(settingsSource.contains("BodyCacheSettingsSheet(workoutStore: workoutStore)"))
        XCTAssertTrue(settingsSource.contains("workoutStore.healthSyncStatusSummaryText"))
        XCTAssertTrue(settingsSource.contains("workoutStore.cacheStatus.summaryText"))
    }

    func testDataRefreshStatusSheetShowsLastRefreshWithoutDetailBullet() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let storeSource = try text(at: "Body/Services/HealthKitWorkoutStore.swift")
        let sheetStart = try XCTUnwrap(settingsSource.range(of: "private struct BodyHealthSyncStatusSettingsSheet")?.lowerBound)
        let sheetBlock = String(settingsSource[sheetStart...].prefix(2_500))
        let statusTextStart = try XCTUnwrap(storeSource.range(of: "var healthSyncStatusLastRefreshText")?.lowerBound)
        let statusTextBlock = String(storeSource[statusTextStart...].prefix(500))

        XCTAssertTrue(sheetBlock.contains(#"BodySettingsAboutSheetScaffold(title: "Data Refresh")"#))
        XCTAssertTrue(sheetBlock.contains(#""Last refreshed: \(lastSuccessfulRefreshText)""#))
        XCTAssertFalse(sheetBlock.contains("workoutStore.healthSyncStatusDetailText"))
        XCTAssertFalse(sheetBlock.contains(#""Last successful refresh: \(lastSuccessfulRefreshText)""#))
        XCTAssertTrue(storeSource.contains("healthSyncStatusLastRefreshText"))
        XCTAssertFalse(storeSource.contains(#"return "Updated""#))
        XCTAssertTrue(statusTextBlock.contains("date.formatted(.dateTime.month(.abbreviated).day().hour().minute())"))
        XCTAssertFalse(statusTextBlock.contains("date.formatted(date: .abbreviated, time: .shortened)"))
    }

    func testHowToUseGuideMovedOutOfSettings() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")

        XCTAssertTrue(settingsSource.contains(#"private let howToUseURLString = "https://docs.ijustinz.com/body/how-to-use""#))
        XCTAssertFalse(settingsSource.contains("BodyHowToUseGuideSection"))
        XCTAssertFalse(settingsSource.contains("BodyHowToUseGuideCard"))
        XCTAssertFalse(settingsSource.contains(#"title: "Connect Apple Health""#))
    }

    func testBodyProPageUsesCoinStyleSettingsEntryAndIconAssets() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let bodyProSource = try text(at: "Body/Views/BodyProView.swift")
        let settingsStackStart = try XCTUnwrap(
            settingsSource.range(of: "VStack(alignment: .leading, spacing: 22) {")?.lowerBound
        )
        let settingsStack = String(settingsSource[settingsStackStart...].prefix(420))
        let aboutSectionRange = try XCTUnwrap(settingsStack.range(of: "aboutSection"))
        let bodyProEntryRange = try XCTUnwrap(settingsStack.range(of: "bodyProEntryCard"))
        let profileEntryRange = try XCTUnwrap(settingsStack.range(of: "profileEntryCard"))
        let appearanceRange = try XCTUnwrap(settingsStack.range(of: "appearanceSection"))

        XCTAssertTrue(settingsSource.contains("bodyProEntryCard"))
        XCTAssertLessThan(aboutSectionRange.lowerBound, bodyProEntryRange.lowerBound)
        // The profile card is the first thing in Settings, above Appearance.
        XCTAssertLessThan(profileEntryRange.lowerBound, appearanceRange.lowerBound)
        XCTAssertTrue(settingsSource.contains("NavigationLink {"))
        XCTAssertTrue(settingsSource.contains("BodyProView()"))
        XCTAssertTrue(settingsSource.contains("BodySettingsTypography.sectionTitleFontSize"))
        XCTAssertTrue(bodyProSource.contains("BodyProFlippableIcon"))
        XCTAssertTrue(bodyProSource.contains("BodyProIconGlow()"))
        XCTAssertTrue(bodyProSource.contains("private struct BodyProIconGlow"))
        XCTAssertTrue(bodyProSource.contains("RadialGradient("))
        XCTAssertTrue(bodyProSource.contains("BodyProPalette.gold.opacity(0.28)"))
        XCTAssertTrue(bodyProSource.contains("BodyProPalette.gold.opacity(0.10)"))
        XCTAssertTrue(bodyProSource.contains("BodyProPalette.gold.opacity(0.08)"))
        XCTAssertFalse(bodyProSource.contains("BodyProPalette.gold.opacity(0.42)"))
        XCTAssertTrue(bodyProSource.contains("BodyAppearancePreference.bodyProIconAssetName(showsBack:"))
        XCTAssertTrue(bodyProSource.contains(#"Text("Unlock All Pro Features")"#))
        XCTAssertFalse(bodyProSource.contains(#"Text("Unlock Body Pro")"#))
        XCTAssertTrue(bodyProSource.contains("private struct BodyProFeatureCheckmark"))
        XCTAssertEqual(bodyProSource.occurrenceCount(of: "BodyProFeatureCheckmark()"), 2)
        XCTAssertFalse(bodyProSource.contains("HStack(alignment: .top, spacing: 14)"))
        XCTAssertFalse(bodyProSource.contains(".padding(.top, 2)"))
        XCTAssertFalse(bodyProSource.contains(".padding(.top, 8)"))
        XCTAssertEqual(bodyProSource.occurrenceCount(of: "BodyProFeature("), 11)
        XCTAssertTrue(bodyProSource.contains("Longer-Range Charts"))
        XCTAssertTrue(bodyProSource.contains("Full Day History"))
        XCTAssertTrue(bodyProSource.contains("Custom Backgrounds"))
        XCTAssertTrue(bodyProSource.contains("Secondary Data Source"))
        XCTAssertTrue(bodyProSource.contains("Custom Data Sources"))
        XCTAssertTrue(bodyProSource.contains("Photo Activity Share"))
        XCTAssertTrue(bodyProSource.contains("3D Route Share"))
        XCTAssertTrue(bodyProSource.contains("Share Card Sizes"))
        XCTAssertTrue(bodyProSource.contains("Share Card Metrics"))
        XCTAssertFalse(bodyProSource.contains("Six-Month and Year Charts"))
        XCTAssertTrue(bodyProSource.contains("Body Widgets"))
        // StoreKit purchase wiring replaced the placeholder stubs.
        XCTAssertTrue(bodyProSource.contains("BodyProStore"))
        XCTAssertTrue(bodyProSource.contains("proStore?.purchase()"))
        XCTAssertTrue(bodyProSource.contains("proStore?.restore()"))
        XCTAssertTrue(bodyProSource.contains("offerCodeRedemption"))
        // Resolve-gating: a checking state shows until entitlement resolves, the
        // purchase action is disabled while a flow is active, and Restore/Redeem
        // stay available during a pending (Ask-to-Buy/SCA) approval.
        XCTAssertTrue(bodyProSource.contains("hasResolved"))
        XCTAssertTrue(bodyProSource.contains("BodyProCheckingCard"))
        XCTAssertTrue(bodyProSource.contains("isPurchaseFlowActive"))
        XCTAssertTrue(bodyProSource.contains("isRestoreOrRedeemDisabled"))
        XCTAssertFalse(bodyProSource.contains("not available in this build"))
        XCTAssertTrue(bodyProSource.contains("Future Pro Updates"))
        // No guessed storefront price: a loading placeholder shows until the
        // StoreKit product resolves, and an unavailable/retry card on failure.
        XCTAssertFalse(bodyProSource.contains("$9.99"))
        XCTAssertTrue(bodyProSource.contains("Loading price…"))
        XCTAssertTrue(bodyProSource.contains("BodyProUnavailableCard"))
        XCTAssertFalse(bodyProSource.contains("$0.89"))
        XCTAssertFalse(bodyProSource.contains("$2.59"))
        XCTAssertFalse(bodyProSource.contains("$8.99"))
        XCTAssertFalse(bodyProSource.contains("$15.99"))

        let proIconPaths = [
            "Body/Assets.xcassets/BodyProIcon.imageset/BodyProIcon.png",
            "Body/Assets.xcassets/BodyProIconBack.imageset/BodyProIconBack.png"
        ]

        for path in proIconPaths {
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
            XCTAssertGreaterThan(data.count, 0, path)
        }
    }

    /// Pins the RevenueCat monetization wiring that can't be exercised without a configured
    /// SDK and a running store: the entitlement source of truth, purchase/restore/pending
    /// handling, the absence of the retired native-StoreKit plumbing, and the shared App
    /// Group flag. The persistence and change-notification behavior of that flag is exercised
    /// at runtime in `BodyProEntitlementTests`.
    func testBodyProStoreRevenueCatWiringIsGuarded() throws {
        let storeSource = try text(at: "Body/Services/BodyProStore.swift")
        let configSource = try text(at: "Body/Services/RevenueCatConfiguration.swift")
        let entitlementSource = try text(at: "BodyShared/Services/BodyProEntitlement.swift")
        let widgetSource = try text(at: "BodyWidgetExtension/HealthMetricWidget.swift")

        // Backed by RevenueCat, keyed to the single non-consumable that unlocks Pro. The
        // product id is retained — the store fetches it directly for the display price.
        XCTAssertTrue(storeSource.contains("import RevenueCat"))
        XCTAssertTrue(storeSource.contains(#"static let lifetimeProductID = "com.zihengthedeveloper.body.pro.lifetime""#))
        XCTAssertTrue(storeSource.contains("static let entitlementID"))

        // Entitlement source of truth: RevenueCat CustomerInfo. The stream catches
        // this-device / post-call updates; purchase / restore / customerInfo cover the rest.
        XCTAssertTrue(storeSource.contains("Purchases.shared.customerInfoStream"))
        XCTAssertTrue(storeSource.contains("Purchases.shared.purchase(product:"))
        XCTAssertTrue(storeSource.contains("Purchases.shared.restorePurchases()"))
        XCTAssertTrue(storeSource.contains("entitlements[Self.entitlementID]?.isActive == true"))

        // The explicit launch/foreground refresh must force a network fetch, not read the
        // stale local cache — otherwise refunds / other-device purchases never propagate.
        // `.fetchCurrent` is the non-default policy that guarantees this.
        XCTAssertTrue(storeSource.contains("customerInfo(fetchPolicy: .fetchCurrent)"))

        // Pending (Ask-to-Buy / SCA): a pending purchase never unlocks, and the pending
        // state clears once the entitlement actually unlocks (so Restore/Redeem re-enable).
        XCTAssertTrue(storeSource.contains(".paymentPendingError"))
        XCTAssertTrue(storeSource.contains("if unlocked && purchaseState == .pending"))

        // A completed, non-cancelled purchase whose entitlement isn't active must not fall
        // back to the buy card: purchase() does one bounded network re-check (the second
        // `.fetchCurrent` call site) and otherwise parks in `.completedNotUnlocked`, which
        // the entitlement stream clears on the late unlock. Restore distinguishes three
        // outcomes — unlocked, lifetime product owned but entitlement inactive (the same
        // recovery state, never a false "no purchases"), and genuinely nothing to restore.
        XCTAssertTrue(storeSource.contains("case completedNotUnlocked"))
        XCTAssertGreaterThanOrEqual(storeSource.occurrenceCount(of: "customerInfo(fetchPolicy: .fetchCurrent)"), 2)
        XCTAssertTrue(storeSource.contains("purchaseState = isPro ? .idle : .completedNotUnlocked"))
        XCTAssertTrue(storeSource.contains("if unlocked && purchaseState == .completedNotUnlocked"))
        XCTAssertTrue(storeSource.contains("allPurchasedProductIdentifiers.contains(Self.lifetimeProductID)"))
        XCTAssertTrue(storeSource.contains(#".failed(String(localized: "No purchases to restore."))"#))

        // The paywall must not re-offer an enabled buy card while a completed purchase
        // awaits its entitlement: the state renders a dedicated recovery card and counts
        // as purchase-flow-active (Restore stays the recovery path).
        let proViewSource = try text(at: "Body/Views/BodyProView.swift")
        XCTAssertTrue(proViewSource.contains("BodyProVerifyingPurchaseCard()"))
        XCTAssertTrue(proViewSource.contains("case .purchasing, .restoring, .pending, .completedNotUnlocked:"))

        // Migration guards: the native StoreKit plumbing is gone. RevenueCat verifies,
        // encodes revocation into `isActive`, and auto-finishes transactions; re-introducing
        // any of these would double-handle purchases or fight the SDK (observer mode).
        XCTAssertFalse(storeSource.contains("Transaction.updates"))
        XCTAssertFalse(storeSource.contains("Transaction.currentEntitlements"))
        XCTAssertFalse(storeSource.contains("transaction.finish()"))
        XCTAssertFalse(storeSource.contains("AppStore.sync()"))
        XCTAssertFalse(storeSource.contains("purchasesAreCompletedBy: .myApp"))
        XCTAssertFalse(storeSource.contains("recordPurchase"))

        // Configuration: one auditable place for the public key + entitlement id, configured
        // once, using RevenueCat's default (SDK-completed) purchase mode. The key and
        // entitlement id must be the real dashboard values — a reverted placeholder key or a
        // wrong entitlement identifier would silently make every entitlement read inactive.
        XCTAssertTrue(configSource.contains(#"static let publicAPIKey = "appl_"#))
        XCTAssertFalse(configSource.contains("REPLACE_ME"))
        XCTAssertFalse(configSource.contains("test_iZhxBFYdgodhOoQkJoDgLpmweay"))
        XCTAssertTrue(configSource.contains(#"static let proEntitlementID = "Body: Health Dashboard Pro""#))
        XCTAssertTrue(configSource.contains("guard !Purchases.isConfigured"))
        XCTAssertTrue(configSource.contains("Purchases.configure(with:"))

        // Shared App Group flag: synchronous source of truth for the widget process and
        // the non-SwiftUI stores; falls back to locked and posts only on a real change.
        XCTAssertTrue(entitlementSource.contains("UserDefaults(suiteName: WorkoutSnapshotStore.appGroupIdentifier)"))
        XCTAssertTrue(entitlementSource.contains("?? false"))
        XCTAssertTrue(entitlementSource.contains("defaults.bool(forKey: unlockedKey) != unlocked"))
        XCTAssertTrue(entitlementSource.contains("NotificationCenter.default.post(name: didChangeNotification"))

        // Widget gating: the gallery/preview shows the unlocked widget so users see what
        // Pro unlocks; the live timeline respects the cached flag.
        XCTAssertTrue(widgetSource.contains("usePlaceholderWhenEmpty || BodyProEntitlement.isUnlocked"))
    }

    func testShareTrayScrollerPinsItsAnchorAndAlwaysFadesBothEdges() throws {
        let shareSheetSource = try text(at: "Body/Views/Health/BodyWorkoutShareSheet.swift")

        // The resting offset is owned by `ScrollPosition`, not by the initial-offset
        // anchor: a tray whose width only settles on a later layout pass was left at the
        // leading edge with its last tiles cut off behind the rail.
        XCTAssertTrue(shareSheetSource.contains("@State private var position: ScrollPosition"))
        XCTAssertTrue(shareSheetSource.contains(".scrollPosition($position)"))
        XCTAssertTrue(shareSheetSource.contains(".defaultScrollAnchor(anchor, for: .alignment)"))
        XCTAssertTrue(shareSheetSource.contains(".onChange(of: contentWidth) { pinToAnchor() }"))
        XCTAssertTrue(shareSheetSource.contains(".onChange(of: viewportWidth) { pinToAnchor() }"))
        XCTAssertTrue(shareSheetSource.contains("struct OptionTileContentWidthKey: PreferenceKey"))
        XCTAssertTrue(shareSheetSource.contains("struct OptionTileViewportWidthKey: PreferenceKey"))
        // Pinning must not inherit the tray-open animation.
        XCTAssertTrue(shareSheetSource.contains("transaction.disablesAnimations = true"))

        // A row the user has scrolled stays put: a metric chip widens when it is picked,
        // and re-pinning on that width change threw the row back to its first chip.
        XCTAssertTrue(shareSheetSource.contains("@State private var hasUserScrolled = false"))
        XCTAssertTrue(shareSheetSource.contains("guard !hasUserScrolled else {"))
        XCTAssertTrue(shareSheetSource.contains("if phase == .tracking || phase == .interacting {"))

        // Both edges fade unconditionally. The matching content margin means an edge
        // with nothing behind it fades an empty gutter, so there is no overflow state
        // to get stuck — which is what left tiles hard-cut before.
        XCTAssertFalse(shareSheetSource.contains("EdgeOverflow"))
        XCTAssertFalse(shareSheetSource.contains("onScrollGeometryChange(for: EdgeOverflow.self)"))
        XCTAssertTrue(shareSheetSource.contains(".contentMargins(.horizontal, fade, for: .scrollContent)"))
        XCTAssertEqual(shareSheetSource.occurrenceCount(of: ".frame(width: fade)"), 2)
    }

    func testWidgetFamiliesArePinnedPerWidget() throws {
        let widgetSource = try text(at: "BodyWidgetExtension/WorkoutCalendarWidget.swift")
        let breakdownSource = try text(at: "BodyShared/Components/WorkoutTypeBreakdownView.swift")

        XCTAssertEqual(widgetSource.occurrenceCount(of: ".supportedFamilies([.systemLarge])"), 1)
        XCTAssertEqual(widgetSource.occurrenceCount(of: ".supportedFamilies([.systemMedium, .systemLarge])"), 1)
        XCTAssertTrue(widgetSource.contains("style: .widgetLarge"))
        XCTAssertTrue(widgetSource.contains(".padding(14)"))
        XCTAssertTrue(widgetSource.contains("family == .systemMedium ? .widgetMedium : .widgetLarge"))
        XCTAssertTrue(breakdownSource.contains("case .app:"))
        // The app shows every activity. Unbounded rather than the live snapshot's
        // count, which would truncate the morph's outgoing arrangement for a frame
        // whenever the incoming month has fewer activity types.
        XCTAssertTrue(breakdownSource.contains("return .max"))
        XCTAssertTrue(breakdownSource.contains("case .widgetMedium:"))
        XCTAssertTrue(breakdownSource.contains("return 2"))
        XCTAssertTrue(breakdownSource.contains("case .widgetLarge:"))
        XCTAssertTrue(breakdownSource.contains("return 5"))
    }

    func testExerciseWeekWidgetsArePinnedToAccessoryRectangular() throws {
        let phoneSource = try text(at: "BodyWidgetExtension/ExerciseWeekWidget.swift")
        let watchSource = try text(at: "BodyWatchWidgetExtension/ExerciseWeekComplication.swift")
        let phoneBundle = try text(at: "BodyWidgetExtension/BodyWidgetExtensionBundle.swift")
        let watchBundle = try text(at: "BodyWatchWidgetExtension/BodyWatchComplicationsBundle.swift")

        // Both are lock screen / rectangular-slot only. Widening either family
        // list silently ships an unlaid-out bar chart into a circular or corner
        // slot, so the pin is asserted exactly once per file.
        XCTAssertEqual(phoneSource.occurrenceCount(of: ".supportedFamilies([.accessoryRectangular])"), 1)
        XCTAssertEqual(watchSource.occurrenceCount(of: ".supportedFamilies([.accessoryRectangular])"), 1)

        // The iPhone widget is Pro-gated; the watch complication is deliberately
        // free, which also keeps the watch extension free of App Group
        // UserDefaults reads (its PrivacyInfo.xcprivacy is pinned to
        // FileTimestamp only, guarded above).
        XCTAssertTrue(phoneSource.contains("BodyProEntitlement.isUnlocked"))
        XCTAssertFalse(watchSource.contains("BodyProEntitlement"))

        // RGB(1, 47, 167) bars in full-color contexts; tinted faces recolor.
        XCTAssertTrue(watchSource.contains("1.0/255.0"))
        XCTAssertTrue(watchSource.contains("47.0/255.0"))
        XCTAssertTrue(watchSource.contains("167.0/255.0"))

        // Both surfaces draw summed workout durations: the iPhone widget reads
        // the workout month snapshots straight out of the App Group, and the
        // complication reads the `workoutMinutes` metric off the pushed
        // snapshot. Losing either line silently reverts a surface to the
        // activity-ring exercise minutes it used to show.
        XCTAssertTrue(phoneSource.contains("WorkoutSnapshotStore.load()"))
        XCTAssertTrue(phoneSource.contains("WorkoutSnapshotStore.loadPrevious()"))
        XCTAssertFalse(phoneSource.contains("HealthWidgetSnapshotStore"))
        XCTAssertTrue(watchSource.contains("metric(forKind: WatchMetricKindKey.workoutMinutes)"))
        // The legacy kind stays as the fallback for a cached snapshot pushed by
        // an older phone build, which carries no `workoutMinutes` metric.
        XCTAssertTrue(watchSource.contains("?? entry.snapshot.metric(forKind: WatchMetricKindKey.exerciseMinutes)"))

        // A widget type that is never registered in its bundle compiles and
        // ships, but never appears in the gallery — the silent failure this
        // pair of assertions exists to catch.
        XCTAssertTrue(phoneBundle.contains("BodyExerciseWeekWidget()"))
        XCTAssertTrue(watchBundle.contains("ExerciseWeekComplication()"))
    }

    func testSleepStagesComplicationIsPinnedToAccessoryRectangularAndMirrorsStageColors() throws {
        let complicationSource = try text(at: "BodyWatchWidgetExtension/SleepStagesComplication.swift")
        let watchBundle = try text(at: "BodyWatchWidgetExtension/BodyWatchComplicationsBundle.swift")
        let healthWidgetSnapshotSource = try text(at: "BodyShared/Models/HealthWidgetSnapshot.swift")

        // Rectangular-slot only, like Weekly Workout Time above: a full-width
        // stage bar has nowhere to lay out in a circular or corner slot.
        XCTAssertEqual(complicationSource.occurrenceCount(of: ".supportedFamilies([.accessoryRectangular])"), 1)

        // Free, like Weekly Workout Time — no Body Pro gate.
        XCTAssertFalse(complicationSource.contains("BodyProEntitlement"))

        // Draws the main-session-only stage segments off the pushed snapshot
        // and deep-links to the Sleep detail page, not a generic metric page.
        XCTAssertTrue(complicationSource.contains("snapshot.sleepStages"))
        XCTAssertTrue(complicationSource.contains("WatchMetricKindKey.sleep"))

        // The bar's stage colors are private literals in this file, but they
        // must mirror `HealthWidgetSleepStage.color` in `HealthWidgetSnapshot`
        // exactly, or the watch bar silently drifts from the iPhone Sleep
        // Stages widget's palette.
        let stageColorLiterals = [
            "Color(red: 1.00, green: 0.31, blue: 0.22)", // awake
            "Color(red: 0.42, green: 0.80, blue: 1.00)", // rem
            "Color(red: 0.24, green: 0.56, blue: 1.00)", // core
            "Color(red: 0.25, green: 0.25, blue: 0.82)" // deep
        ]
        for literal in stageColorLiterals {
            XCTAssertTrue(complicationSource.contains(literal), literal)
            XCTAssertTrue(healthWidgetSnapshotSource.contains(literal), literal)
        }

        // A widget type that is never registered in its bundle compiles and
        // ships, but never appears in the gallery — the silent failure this
        // assertion exists to catch.
        XCTAssertTrue(watchBundle.contains("SleepStagesComplication()"))

        // The picker lists Weekly Workout Time first and Sleep Stages second,
        // ahead of the metric rings.
        let exerciseWeekIndex = try XCTUnwrap(watchBundle.range(of: "ExerciseWeekComplication()")?.lowerBound)
        let sleepStagesIndex = try XCTUnwrap(watchBundle.range(of: "SleepStagesComplication()")?.lowerBound)
        let readinessIndex = try XCTUnwrap(watchBundle.range(of: "ReadinessComplication()")?.lowerBound)
        XCTAssertLessThan(exerciseWeekIndex, sleepStagesIndex)
        XCTAssertLessThan(sleepStagesIndex, readinessIndex)
    }

    func testProjectDeclaresSimplifiedChineseLocalization() throws {
        let project = try text(at: "body.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains(#""zh-Hans","#))
        XCTAssertTrue(project.contains("developmentRegion = en;"))
    }

    func testChineseLocalizationCatalogsAreComplete() throws {
        let catalogPaths = [
            "Body/Localizable.xcstrings",
            "Body/InfoPlist.xcstrings",
            "BodyMetricsKit/BodyMetricsKit.xcstrings",
            "BodyShared/BodyShared.xcstrings",
            "BodyWatchShared/BodyWatchShared.xcstrings",
            "BodyWatchSnapshotKit/BodyWatchSnapshotKit.xcstrings",
            "BodyWatch/Localizable.xcstrings",
            "BodyWatch/InfoPlist.xcstrings",
            "BodyWidgetExtension/Localizable.xcstrings",
            "BodyWatchWidgetExtension/Localizable.xcstrings"
        ]

        for path in catalogPaths {
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(path))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], path)
            XCTAssertEqual(root["sourceLanguage"] as? String, "en", path)
            let strings = try XCTUnwrap(root["strings"] as? [String: Any], path)
            XCTAssertFalse(strings.isEmpty, "\(path) has no entries")

            for (key, rawEntry) in strings {
                // Xcode's string-catalog build phase intermittently re-injects an
                // empty-key placeholder ("" with no localizations) into the app
                // catalog on recompile. It is never user-facing, so skip it rather
                // than fail the Chinese-coverage check on every unrelated UI change.
                if key.isEmpty { continue }

                let entry = try XCTUnwrap(rawEntry as? [String: Any], "\(path) \(key)")
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "\(path) \(key)")
                for language in ["en", "zh-Hans"] {
                    let localization = try XCTUnwrap(
                        localizations[language] as? [String: Any],
                        "\(path) \(key) missing \(language)"
                    )
                    let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any], "\(path) \(key) \(language)")
                    XCTAssertEqual(unit["state"] as? String, "translated", "\(path) \(key) \(language)")
                    let value = try XCTUnwrap(unit["value"] as? String, "\(path) \(key) \(language)")
                    XCTAssertFalse(value.isEmpty, "\(path) \(key) \(language)")
                }
            }
        }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Concatenates every Swift file backing `BodyHomeView`. The original
    /// 8,600-line `BodyHomeView.swift` was split into focused peer files
    /// (Body/Views/Health/...) — tests that grep for substrings on this view's
    /// surface should look across all of them, not just the main file.
    private func bodyHomeViewText() throws -> String {
        let files = [
            "Body/Views/BodyHomeView.swift",
            "Body/Views/Health/BodyHealthMetricCard.swift",
            "Body/Views/Health/BodyHealthMetricDetailView.swift",
            "Body/Views/Health/BodyMetricWarningCard.swift",
            "Body/Views/Health/BodyHealthDataSourcePickerSheet.swift",
            "Body/Views/Health/BodyHomeTrendCard.swift",
            "Body/Views/Health/BodyHealthNoticeBanner.swift",
            "Body/Views/Health/SleepScoreSheet.swift",
            "Body/Views/Health/ChartHelpers.swift",
            "Body/Views/Health/Charts/MetricCharts.swift",
            "Body/Views/Health/Charts/BasicsCharts.swift",
            "Body/Views/Health/Charts/HeartRateRangeChart.swift",
            "Body/Views/Health/Charts/SourceComparisonCharts.swift",
            "Body/Views/Health/Charts/SleepCharts.swift",
            "Body/Views/Health/Charts/TrainingLoadCharts.swift",
            "Body/Views/Health/Charts/ReadinessChart.swift",
            "Body/Views/Health/Charts/VitalsCharts.swift"
        ]
        return try files.compactMap { file -> String? in
            try? text(at: file)
        }.joined(separator: "\n")
    }

    /// Concatenates every Swift file backing the health summary / dashboard /
    /// trend / activity-ring / sleep / source-comparison / training-load
    /// models. The original 3,300-line `HealthSummarySnapshot.swift` was split
    /// into focused peer files; tests that grep for snapshot substrings should
    /// look across all of them, not just the main file.
    private func healthSummarySnapshotText() throws -> String {
        let files = [
            "BodyMetricsKit/HealthSummarySnapshot.swift",
            "BodyMetricsKit/ActivityRings.swift",
            "BodyMetricsKit/Sleep.swift",
            "Body/Models/SourceComparison.swift",
            "BodyMetricsKit/TrainingLoadCalculator.swift",
            "BodyMetricsKit/HealthTrend.swift"
        ]
        return try files.map { try text(at: $0) }.joined(separator: "\n")
    }

    /// Concatenates every Swift file backing `HealthKitFetchEngine`. The engine
    /// was split across the main actor file and one or more `+...swift`
    /// extension files; tests that grep for engine substrings should look across
    /// the whole engine, not just the main file.
    ///
    /// The `BodyWatchSnapshotKit` files are part of that surface too: the
    /// engine's HealthKit query leaves (source discovery + resolution, quantity
    /// queries, sleep queries/grouping, workout query + mapping) were MOVED
    /// there so Body and BodyWatch compile the same fetch code, and the engine
    /// now calls in. Grepping the engine alone would silently stop covering
    /// them.
    private func healthKitFetchEngineText() throws -> String {
        let files = [
            "Body/Services/HealthKitFetchEngine.swift",
            "Body/Services/HealthKitFetchEngine+SampleParsers.swift",
            "Body/Services/HealthKitFetchEngine+Sleep.swift",
            "Body/Services/HealthKitFetchEngine+TrainingLoad.swift",
            "Body/Services/HealthKitFetchEngine+ActivityRings.swift",
            "Body/Services/HealthKitFetchEngine+SourceOptions.swift",
            "Body/Services/HealthKitFetchEngine+Secondary.swift",
            "Body/Services/HealthKitFetchEngine+IntradaySamples.swift",
            "Body/Services/HealthKitFetchEngine+Write.swift",
            "BodyWatchSnapshotKit/BodyHealthSourceResolver.swift",
            "BodyWatchSnapshotKit/BodyHealthQuantityFetch.swift",
            "BodyWatchSnapshotKit/BodySleepFetch.swift",
            "BodyWatchSnapshotKit/BodyWorkoutFetch.swift"
        ]
        return try files.map { try text(at: $0) }.joined(separator: "\n")
    }

    private func propertyList(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent(relativePath))
        var format = PropertyListSerialization.PropertyListFormat.xml
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )
        return try XCTUnwrap(propertyList as? [String: Any])
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
