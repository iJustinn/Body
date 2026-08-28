//
//  BodySettingsView.swift
//  Body
//

import RevenueCatUI
import SafariServices
import SwiftUI
import UIKit
import UserNotifications

struct BodySettingsView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @Environment(ReadinessCommentGenerator.self) private var readinessComment
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedWeightUnitKey) private var selectedWeightUnitRawValue = BodyValueFormat.WeightUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue = BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey) private var sleepDurationGoalMinutes = BodySleepDurationGoal.defaultMinutes
    // Observed here (its toggle lives in a sub-view sharing this key) so a change
    // re-publishes the phone-owned watch prefs immediately.
    @AppStorage(BodyAppearancePreference.showSleepScoreKey) private var showSleepScore = true
    @AppStorage(BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey) private var showsSubMinuteAwakeSleepStages = BodySleepStageDisplayPreference.defaultShowsSubMinuteAwakeStages
    @AppStorage(BodyAppearancePreference.showsLeadingTrailingAwakeSleepStagesKey) private var showsLeadingTrailingAwakeSleepStages = BodySleepStageDisplayPreference.defaultShowsLeadingTrailingAwakeStages
    @AppStorage(BodyAppearancePreference.summaryCardSelectionKey) private var summaryCardSelectionRawValue = BodySummaryCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.starredMetricKey) private var starredMetricRawValue = BodyHomeCardKind.readiness.rawValue
    @AppStorage(BodyAppearancePreference.homeBackgroundEnabledKey) private var homeBackgroundEnabled = true
    @AppStorage(BodyAppearancePreference.workoutColorOverridesKey, store: BodyWorkoutColorStore.sharedDefaults)
    private var workoutColorOverridesRawValue = ""
    @AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey) private var homeTrendCardSelectionRawValue = BodyHomeTrendCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.metricDayViewSelectionKey) private var metricDayViewSelectionRawValue = BodyMetricDayViewSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.metricWarningsKey) private var metricWarningSelectionRawValue = BodyMetricWarningSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.metricWarningThresholdsKey) private var metricWarningThresholdsRawValue = BodyMetricWarningThresholds.defaultRawValue
    @AppStorage(BodyAppearancePreference.workoutEffortCardEnabledKey) private var workoutEffortCardEnabled = true
    @AppStorage(BodyAppearancePreference.showWorkoutEffortSuggestionsKey) private var showWorkoutEffortSuggestions = true
    @AppStorage(BodyAppearancePreference.autoApplyWorkoutEffortKey) private var autoApplyWorkoutEffort = false
    @AppStorage(BodyAppearancePreference.workoutsChartSwipeSwitchesMonthKey) private var workoutsChartSwipeSwitchesMonth = true
    @AppStorage(BodyAppearancePreference.showReadinessAICommentKey) private var showReadinessAIComment = true
    @AppStorage(BodyAppearancePreference.workoutRouteStyleKey) private var workoutRouteStyleRawValue = BodyWorkoutRouteStyle.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.drawsWorkoutRouteOnLoadKey) private var drawsWorkoutRouteOnLoad = true
    @AppStorage(BodyAppearancePreference.workoutEquivalentHapticsEnabledKey) private var workoutEquivalentHapticsEnabled = true
    @AppStorage(BodyAppearancePreference.workoutEquivalentCardEnabledKey) private var workoutEquivalentCardEnabled = true
    @AppStorage(BodyAppearancePreference.bodyProIconShowsBackKey) private var bodyProIconShowsBack = false
    @AppStorage(BodyAppearancePreference.profileNameKey) private var profileName = ""
    // Empty `Data` is "no photo" — `@AppStorage` has no optional-Data overload.
    @AppStorage(BodyAppearancePreference.profileAvatarDataKey) private var profileAvatarData = Data()
    @State private var activeSheet: BodySettingsSheet?
    @State private var showBodyProPaywall = false
    @State private var showCustomerCenter = false
    @State private var selectedAppIconName: String?
    @State private var showingAppIconError = false
    @State private var appIconErrorMessage = ""
    @State private var showingHowToUseBrowser = false
    @State private var showingPrivacyBrowser = false
    @State private var showingOnboarding = false

    private let howToUseURLString = "https://docs.ijustinz.com/body/how-to-use"
    private let privacyPolicyURLString = "https://docs.ijustinz.com/body/privacy"

    var body: some View {
        NavigationStack {
            ZStack {
                BodyAppBackground()
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        profileEntryCard
                        appearanceSection
                        metricsSection
                        workoutsSection
                        aiSection
                        dataSection
                        aboutSection
                        bodyProEntryCard
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                    .readableContentColumn()
                }

            }
            .onAppear {
                selectedAppIconName = UIApplication.shared.alternateIconName
            }
            .sheet(item: $activeSheet) { sheet in
                settingsSheet(for: sheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showBodyProPaywall) {
                NavigationStack { BodyProView() }
            }
            .sheet(isPresented: $showCustomerCenter) {
                CustomerCenterView()
            }
            .sheet(isPresented: $showingPrivacyBrowser) {
                if let url = URL(string: privacyPolicyURLString) {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showingHowToUseBrowser) {
                if let url = URL(string: howToUseURLString) {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                BodyOnboardingView(mode: .revisit)
            }
            .alert("Couldn't Change Icon", isPresented: $showingAppIconError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(appIconErrorMessage)
            }
            .onChange(of: showsSubMinuteAwakeSleepStages) {
                Task {
                    await workoutStore.refetchAfterSleepDisplayPreferenceChange()
                }
            }
            .onChange(of: showsLeadingTrailingAwakeSleepStages) {
                Task {
                    await workoutStore.refetchAfterSleepDisplayPreferenceChange()
                }
            }
            // Republish both companion snapshots (widget + watch) when a
            // formatting-only pref changes, without waiting for the next
            // refresh.
            .onChange(of: sleepDurationGoalMinutes) { workoutStore.republishCompanionSnapshots() }
            .onChange(of: selectedTemperatureUnitRawValue) { workoutStore.republishCompanionSnapshots() }
            .onChange(of: followsSystemUnits) { workoutStore.republishCompanionSnapshots() }
            .onChange(of: showSleepScore) { workoutStore.republishCompanionSnapshots() }
            .onChange(of: selectedEnergyUnitRawValue) { workoutStore.republishCompanionSnapshots() }
            .onChange(of: selectedWeightUnitRawValue) { workoutStore.republishCompanionSnapshots() }
        }
    }

    private var profileEntryCard: some View {
        NavigationLink {
            BodyProfileView()
        } label: {
            HStack(spacing: 15) {
                Group {
                    if let profileAvatarImage {
                        Image(uiImage: profileAvatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundColor(.white)
                            .frame(width: 58, height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(profileCardTitle)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(profileCardSubtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .bodyCardBackground(cornerRadius: 26, translucent: true)
        }
        .buttonStyle(.plain)
    }

    /// The stored name once set, otherwise the generic card title.
    private var profileCardTitle: String {
        BodyUserProfile.displayName(from: profileName) ?? String(localized: "Your Profile")
    }

    private var profileAvatarImage: UIImage? {
        profileAvatarData.isEmpty ? nil : UIImage(data: profileAvatarData)
    }

    /// Asks only for the piece that is still missing; once both are set the row
    /// stops asking and carries the day's encouragement instead.
    private var profileCardSubtitle: LocalizedStringKey {
        switch (BodyUserProfile.displayName(from: profileName) != nil, profileAvatarImage != nil) {
        case (true, true):
            return BodyProfileMotivation.line(for: Date())
        case (true, false):
            return "Add a photo"
        case (false, true):
            return "Add a name"
        case (false, false):
            return "Add a name and photo"
        }
    }

    private var bodyProEntryCard: some View {
        NavigationLink {
            BodyProView()
        } label: {
            HStack(spacing: 15) {
                Image(BodyAppearancePreference.bodyProIconAssetName(showsBack: bodyProIconShowsBack))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Body Pro")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Unlock premium features")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .bodyCardBackground(cornerRadius: 26, translucent: true)
        }
        .buttonStyle(.plain)
    }

    private var appearanceSection: some View {
        BodySettingsCardSection("Appearance") {
            Button {
                if proStore?.isPro ?? false {
                    activeSheet = .homeBackground
                } else {
                    showBodyProPaywall = true
                }
            } label: {
                BodySettingsRowLabel(
                    title: "Background",
                    value: homeBackgroundSummaryText,
                    iconName: "paintpalette.fill",
                    tintColor: .teal,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                if proStore?.isPro ?? false {
                    activeSheet = .workoutColors
                } else {
                    showBodyProPaywall = true
                }
            } label: {
                BodySettingsRowLabel(
                    title: "Workouts",
                    value: workoutColorsSummaryText,
                    iconName: "figure.mixed.cardio",
                    tintColor: .teal,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .appIcon
            } label: {
                BodySettingsRowLabel(
                    title: "Icon",
                    value: currentAppIconOption.localizedDisplayName,
                    iconName: "app.fill",
                    tintColor: .gray,
                    accessory: .chevron
                )
            }
            .disabled(!UIApplication.shared.supportsAlternateIcons)
            .buttonStyle(.plain)
        }
    }

    private var dataSection: some View {
        BodySettingsCardSection("Data") {
            ForEach(BodySettingsDataTab.allCases) { tab in
                Button {
                    activeSheet = tab.sheet
                } label: {
                    BodySettingsRowLabel(
                        title: LocalizedStringKey(tab.title),
                        value: dataValue(for: tab),
                        iconName: tab.iconName,
                        tintColor: tab.tintColor,
                        accessory: .chevron
                    )
                }
                .buttonStyle(.plain)

                if tab != BodySettingsDataTab.allCases.last {
                    settingsDivider
                }
            }
        }
    }

    private var aboutSection: some View {
        BodySettingsCardSection("About") {
            ForEach(BodySettingsAboutTab.allCases) { tab in
                aboutRow(for: tab)

                if tab != .version {
                    settingsDivider
                }

                // Manage Purchases (RevenueCat Customer Center) sits just above "More".
                if tab == .onboarding {
                    managePurchasesRow
                    settingsDivider
                }
            }
        }
    }

    // RevenueCat Customer Center: restore, manage, and get help with purchases.
    private var managePurchasesRow: some View {
        Button {
            showCustomerCenter = true
        } label: {
            BodySettingsRowLabel(
                title: "Manage Purchases",
                value: nil,
                iconName: "person.crop.circle",
                tintColor: .gray,
                accessory: .chevron
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func aboutRow(for tab: BodySettingsAboutTab) -> some View {
        Button {
            switch tab {
            case .howToUse:
                showingHowToUseBrowser = true
            case .privacy:
                showingPrivacyBrowser = true
            case .onboarding:
                showingOnboarding = true
            case .version:
                break
            case .more:
                if let sheet = tab.sheet {
                    activeSheet = sheet
                }
            }
        } label: {
            BodySettingsRowLabel(
                title: LocalizedStringKey(tab.title),
                value: tab == .version ? appVersionDisplay : nil,
                iconName: tab.iconName,
                tintColor: tab.tintColor,
                accessory: aboutAccessory(for: tab)
            )
        }
        .buttonStyle(.plain)
    }

    private func aboutAccessory(for tab: BodySettingsAboutTab) -> BodySettingsRowAccessory {
        switch tab {
        case .howToUse, .privacy:
            return .externalLink
        case .onboarding, .more:
            return .chevron
        case .version:
            return .none
        }
    }

    private var metricsSection: some View {
        BodySettingsCardSection("Metrics") {
            Button {
                activeSheet = .sleepDurationGoal
            } label: {
                BodySettingsRowLabel(
                    title: "Sleep",
                    value: sleepDurationGoalText,
                    iconName: "bed.double.fill",
                    tintColor: Color(red: 0.20, green: 0.72, blue: 1.00),
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .units
            } label: {
                BodySettingsRowLabel(
                    title: "Units",
                    value: unitsSummaryText,
                    iconName: "pencil.and.ruler.fill",
                    tintColor: .blue,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .summaryCards
            } label: {
                BodySettingsRowLabel(
                    title: "Summary Cards",
                    value: summaryCardsSummaryText,
                    iconName: "square.grid.2x2",
                    tintColor: .pink,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .dayView
            } label: {
                BodySettingsRowLabel(
                    title: "Day View",
                    value: dayViewSummaryText,
                    iconName: "chart.line.flattrend.xyaxis",
                    tintColor: .orange,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .homeTrendCards
            } label: {
                BodySettingsRowLabel(
                    title: "Trend Cards",
                    value: homeTrendCardsSummaryText,
                    iconName: "chart.line.uptrend.xyaxis",
                    tintColor: .orange,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .metricWarnings
            } label: {
                BodySettingsRowLabel(
                    title: "Warnings",
                    value: metricWarningsSummaryText,
                    iconName: "exclamationmark.triangle.fill",
                    tintColor: .yellow,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .starMetric
            } label: {
                BodySettingsRowLabel(
                    title: "Star Metric",
                    value: starredMetricSummaryText,
                    iconName: "star.fill",
                    tintColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var workoutsSection: some View {
        BodySettingsCardSection("Workouts") {
            Button {
                activeSheet = .workoutRouteStyle
            } label: {
                BodySettingsRowLabel(
                    title: "Route Style",
                    value: workoutRouteStyleSummaryText,
                    iconName: "map.fill",
                    tintColor: .blue,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .workoutEquivalents
            } label: {
                BodySettingsRowLabel(
                    title: "Workout Equivalents",
                    value: workoutEquivalentsSummaryText,
                    iconName: "fork.knife",
                    tintColor: .purple,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .effortSuggestions
            } label: {
                BodySettingsRowLabel(
                    title: "Workout Effort",
                    value: workoutEffortSummaryText,
                    iconName: "speedometer",
                    tintColor: .purple,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .workoutMonthSwipe
            } label: {
                BodySettingsRowLabel(
                    title: "Month Swipe",
                    value: workoutsChartSwipeSummaryText,
                    iconName: "arrow.left.arrow.right",
                    tintColor: .indigo,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var aiSection: some View {
        BodySettingsCardSection("settings.section.ai") {
            Button {
                activeSheet = .aiReadiness
            } label: {
                BodySettingsRowLabel(
                    title: "Readiness",
                    value: readinessAISummaryText,
                    iconName: BodyAppleIntelligenceGlyph.symbolName,
                    tintColor: .indigo,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var starredMetric: Binding<BodyHomeCardKind?> {
        Binding {
            BodyHomeCardKind.starredMetric(from: starredMetricRawValue)
        } set: { newValue in
            starredMetricRawValue = newValue?.rawValue ?? ""
        }
    }

    private var starredMetricSummaryText: String {
        BodyHomeCardKind.starredMetric(from: starredMetricRawValue)?.title ?? String(localized: "None")
    }

    private var homeBackgroundSummaryText: String {
        homeBackgroundEnabled ? String(localized: "On") : String(localized: "Off")
    }

    // The row's summary reflects the card toggle — the sheet's master switch —
    // not the suggestion sub-settings.
    private var workoutEffortSummaryText: String {
        workoutEffortCardEnabled ? String(localized: "On") : String(localized: "Off")
    }

    private var workoutsChartSwipeSummaryText: String {
        workoutsChartSwipeSwitchesMonth ? String(localized: "On") : String(localized: "Off")
    }

    // The row's summary reflects the card toggle — the sheet's master switch —
    // not the vibration sub-setting.
    private var workoutEquivalentsSummaryText: String {
        workoutEquivalentCardEnabled ? String(localized: "On") : String(localized: "Off")
    }

    private var readinessAISummaryText: String {
        guard readinessComment.isSupported else { return String(localized: "Unavailable") }
        return showReadinessAIComment ? String(localized: "On") : String(localized: "Off")
    }

    private var workoutRouteStyleSummaryText: String {
        let style = BodyWorkoutRouteStyle.storedValue(from: workoutRouteStyleRawValue)
        // Draw is the sheet's first control now, so the summary leads with it when it's
        // on — "Draw · 3D". Off is the quieter state and reads as just the style, as does
        // Map, which never draws however the stored switch is set.
        guard style.supportsRouteDraw, drawsWorkoutRouteOnLoad else { return style.title }
        return "\(String(localized: "routeStyle.drawSummary")) · \(style.title)"
    }

    private var workoutColorsSummaryText: String {
        // A locked palette resolves to the built-ins, so the row reads "Default"
        // while Pro is off even though the picks are still in storage.
        let palette = BodyWorkoutColorPalette(
            rawOverrides: workoutColorOverridesRawValue,
            isProUnlocked: proStore?.isPro ?? false
        )
        return palette.isCustomized
            ? String(localized: "workoutColors.custom", defaultValue: "Custom")
            : String(localized: "workoutColors.default", defaultValue: "Default")
    }

    private var settingsDivider: some View {
        Divider()
            .padding(.leading, 76)
    }

    private var appVersionDisplay: String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? String(localized: "Unknown")
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? String(localized: "Unknown")
        return "\(appVersion) (\(buildNumber))"
    }

    private var permissionSummaryText: String {
        "\(workoutStore.permissionSelection.enabledCount)/\(BodyHealthPermission.allCases.count)"
    }

    private var summaryCardsSummaryText: String {
        "\(currentSummaryCardSelection.enabledCount)/\(BodyHomeCardKind.defaultOrder.count)"
    }

    private var homeTrendCardsSummaryText: String {
        "\(currentHomeTrendCardSelection.enabledCount)/\(BodyHomeTrendCardKind.defaultOrder.count)"
    }

    private var dayViewSummaryText: String {
        "\(currentMetricDayViewSelection.enabledCount)/\(HealthMetricKind.dayViewKinds.count)"
    }

    private var metricWarningsSummaryText: String {
        "\(currentMetricWarningSelection.enabledCount)/\(currentMetricWarningSelection.totalCount)"
    }

    private func dataValue(for tab: BodySettingsDataTab) -> String {
        switch tab {
        case .source:
            return sourceSummaryText
        case .permissions:
            return permissionSummaryText
        case .syncStatus:
            return workoutStore.healthSyncStatusSummaryText
        case .cache:
            return workoutStore.cacheStatus.summaryText
        }
    }

    private var currentAppIconOption: BodyAppIconOption {
        BodyAppIconOption.option(named: selectedAppIconName)
    }

    private var currentWeightUnit: BodyValueFormat.WeightUnitPreference {
        BodyValueFormat.WeightUnitPreference.storedValue(from: selectedWeightUnitRawValue)
    }

    private var currentDistanceUnit: BodyValueFormat.DistanceUnitPreference {
        BodyValueFormat.DistanceUnitPreference.storedValue(from: selectedDistanceUnitRawValue)
    }

    private var currentEnergyUnit: BodyValueFormat.EnergyUnitPreference {
        BodyValueFormat.EnergyUnitPreference.storedValue(from: selectedEnergyUnitRawValue)
    }

    private var currentTemperatureUnit: BodyValueFormat.TemperatureUnitPreference {
        BodyValueFormat.TemperatureUnitPreference.storedValue(from: selectedTemperatureUnitRawValue)
    }

    private var unitsSummaryText: String {
        if followsSystemUnits {
            return String(localized: "System")
        }

        return [
            currentWeightUnit.unitLabel,
            currentDistanceUnit.unitLabel,
            currentEnergyUnit.unitLabel,
            currentTemperatureUnit.unitLabel
        ].joined(separator: ", ")
    }

    private var sleepDurationGoalText: String {
        BodySleepDurationGoal.displayText(for: sleepDurationGoalMinutes)
    }

    private var sourceSummaryText: String {
        let primaryName = workoutStore.defaultHealthDataSourceOption.name
        let secondaryOption = workoutStore.defaultSecondaryHealthDataSourceOption
        guard !secondaryOption.isNoComparison else {
            return primaryName
        }

        return "\(primaryName) / \(secondaryOption.name)"
    }

    private var currentSummaryCardSelection: BodySummaryCardSelection {
        BodySummaryCardSelection.storedValue(from: summaryCardSelectionRawValue)
    }

    private var currentHomeTrendCardSelection: BodyHomeTrendCardSelection {
        BodyHomeTrendCardSelection.storedValue(from: homeTrendCardSelectionRawValue)
    }

    private var currentMetricDayViewSelection: BodyMetricDayViewSelection {
        BodyMetricDayViewSelection.storedValue(from: metricDayViewSelectionRawValue)
    }

    private var currentMetricWarningSelection: BodyMetricWarningSelection {
        BodyMetricWarningSelection.storedValue(from: metricWarningSelectionRawValue)
    }

    private var followsSystemUnitsBinding: Binding<Bool> {
        Binding {
            followsSystemUnits
        } set: { followsSystem in
            followsSystemUnits = followsSystem
        }
    }

    private var selectedWeightUnit: Binding<BodyValueFormat.WeightUnitPreference> {
        Binding {
            currentWeightUnit
        } set: { unit in
            selectedWeightUnitRawValue = unit.rawValue
        }
    }

    private var selectedDistanceUnit: Binding<BodyValueFormat.DistanceUnitPreference> {
        Binding {
            currentDistanceUnit
        } set: { unit in
            selectedDistanceUnitRawValue = unit.rawValue
        }
    }

    private var selectedEnergyUnit: Binding<BodyValueFormat.EnergyUnitPreference> {
        Binding {
            currentEnergyUnit
        } set: { unit in
            selectedEnergyUnitRawValue = unit.rawValue
        }
    }

    private var selectedTemperatureUnit: Binding<BodyValueFormat.TemperatureUnitPreference> {
        Binding {
            currentTemperatureUnit
        } set: { unit in
            selectedTemperatureUnitRawValue = unit.rawValue
        }
    }

    private var sleepDurationGoal: Binding<Int> {
        Binding {
            BodySleepDurationGoal.storedMinutes(from: sleepDurationGoalMinutes)
        } set: { minutes in
            sleepDurationGoalMinutes = BodySleepDurationGoal.storedMinutes(from: minutes)
        }
    }

    private var summaryCardSelection: Binding<BodySummaryCardSelection> {
        Binding {
            currentSummaryCardSelection
        } set: { selection in
            summaryCardSelectionRawValue = selection.rawValue
        }
    }

    private var homeTrendCardSelection: Binding<BodyHomeTrendCardSelection> {
        Binding {
            currentHomeTrendCardSelection
        } set: { selection in
            homeTrendCardSelectionRawValue = selection.rawValue
        }
    }

    private var metricDayViewSelection: Binding<BodyMetricDayViewSelection> {
        Binding {
            currentMetricDayViewSelection
        } set: { selection in
            metricDayViewSelectionRawValue = selection.rawValue
        }
    }

    private var metricWarningSelection: Binding<BodyMetricWarningSelection> {
        Binding {
            currentMetricWarningSelection
        } set: { selection in
            metricWarningSelectionRawValue = selection.rawValue
        }
    }

    private var metricWarningThresholds: Binding<BodyMetricWarningThresholds> {
        Binding {
            BodyMetricWarningThresholds.storedValue(from: metricWarningThresholdsRawValue)
        } set: { thresholds in
            metricWarningThresholdsRawValue = thresholds.rawValue
        }
    }

    private var workoutRouteStyle: Binding<BodyWorkoutRouteStyle> {
        Binding {
            BodyWorkoutRouteStyle.storedValue(from: workoutRouteStyleRawValue)
        } set: { style in
            workoutRouteStyleRawValue = style.rawValue
        }
    }

    @ViewBuilder
    private func settingsSheet(for sheet: BodySettingsSheet) -> some View {
        switch sheet {
        case .homeBackground:
            BodyHomeBackgroundSheet()
        case .workoutColors:
            BodyWorkoutColorsSheet()
        case .appIcon:
            BodyAppIconPickerSheet(
                selectedIconName: selectedAppIconName,
                onSelect: changeAppIcon
            )
        case .summaryCards:
            BodySummaryCardsSettingsSheet(selection: summaryCardSelection)
        case .homeTrendCards:
            BodyHomeTrendCardsSettingsSheet(selection: homeTrendCardSelection)
        case .starMetric:
            BodyStarMetricPickerSheet(selection: starredMetric)
        case .dayView:
            BodyMetricDayViewSettingsSheet(selection: metricDayViewSelection)
        case .metricWarnings:
            BodyMetricWarningsSettingsSheet(
                selection: metricWarningSelection,
                thresholds: metricWarningThresholds,
                workoutStore: workoutStore
            )
        case .effortSuggestions:
            BodyWorkoutEffortSettingsSheet(
                cardEnabled: $workoutEffortCardEnabled,
                isEnabled: $showWorkoutEffortSuggestions,
                autoApply: $autoApplyWorkoutEffort,
                workoutStore: workoutStore
            )
        case .workoutEquivalents:
            BodyWorkoutEquivalentsSettingsSheet(hapticsEnabled: $workoutEquivalentHapticsEnabled)
        case .workoutRouteStyle:
            BodyWorkoutRouteStyleSettingsSheet(selection: workoutRouteStyle, drawsRoute: $drawsWorkoutRouteOnLoad)
        case .workoutMonthSwipe:
            BodyWorkoutMonthSwipeSettingsSheet(isEnabled: $workoutsChartSwipeSwitchesMonth)
        case .aiReadiness:
            BodyReadinessAISettingsSheet(
                isEnabled: $showReadinessAIComment,
                isSupported: readinessComment.isSupported
            )
        case .sleepDurationGoal:
            BodySleepSettingsSheet(
                goalMinutes: sleepDurationGoal,
                showsSubMinuteAwakeStages: $showsSubMinuteAwakeSleepStages,
                showsLeadingTrailingAwakeStages: $showsLeadingTrailingAwakeSleepStages
            )
        case .units:
            BodyUnitPreferencePickerSheet(
                followsSystemUnits: followsSystemUnitsBinding,
                selectedWeightUnit: selectedWeightUnit,
                selectedDistanceUnit: selectedDistanceUnit,
                selectedEnergyUnit: selectedEnergyUnit,
                selectedTemperatureUnit: selectedTemperatureUnit
            )
        case .permissions:
            BodyHealthPermissionsSettingsSheet(workoutStore: workoutStore)
        case .source:
            BodySourceSettingsSheet(workoutStore: workoutStore)
        case .syncStatus:
            BodyHealthSyncStatusSettingsSheet(workoutStore: workoutStore)
        case .cache:
            BodyCacheSettingsSheet(workoutStore: workoutStore)
        case .more:
            BodyMoreSettingsSheet()
        }
    }

    private func changeAppIcon(to option: BodyAppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else {
            appIconErrorMessage = String(localized: "This device does not support alternate app icons.")
            showingAppIconError = true
            return
        }

        guard selectedAppIconName != option.alternateIconName else {
            activeSheet = nil
            return
        }

        UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
            DispatchQueue.main.async {
                if let error {
                    appIconErrorMessage = error.localizedDescription
                    showingAppIconError = true
                    return
                }

                selectedAppIconName = UIApplication.shared.alternateIconName
                activeSheet = nil
            }
        }
    }

}

/// Hand-written encouragement for the profile card once a name and photo are
/// both set. The line is picked from the day's ordinal rather than at random so
/// it holds still through every re-render and turns over at midnight.
enum BodyProfileMotivation {
    static let lines: [LocalizedStringKey] = [
        "Consistency beats intensity.",
        "Show up for yourself today.",
        "Small efforts, stacked.",
        "Rest is part of the work.",
        "Progress, not perfection.",
        "One more day of showing up.",
        "Strong is built daily.",
        "Move now, thank yourself later.",
        "Every session counts.",
        "Steady beats fast."
    ]

    static func line(for date: Date, calendar: Calendar = .bodyGregorian) -> LocalizedStringKey {
        // Whole local days from a fixed reference. (`ordinality(of: .day, in: .era,)`
        // reads differently at 07:00 and 23:00 of the same day, so the line would
        // shift mid-day.)
        let day = calendar.dateComponents(
            [.day],
            from: Date(timeIntervalSinceReferenceDate: 0),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        return lines[((day % lines.count) + lines.count) % lines.count]
    }
}

enum BodySettingsSheet: String, Identifiable {
    case homeBackground
    case workoutColors
    case appIcon
    case sleepDurationGoal
    case summaryCards
    case homeTrendCards
    case starMetric
    case dayView
    case metricWarnings
    case effortSuggestions
    case workoutEquivalents
    case workoutRouteStyle
    case workoutMonthSwipe
    case aiReadiness
    case units
    case source
    case permissions
    case syncStatus
    case cache
    case more

    var id: String {
        rawValue
    }
}

enum BodySettingsDataTab: String, CaseIterable, Identifiable {
    case source
    case permissions
    case syncStatus
    case cache

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .permissions:
            return "Permissions"
        case .syncStatus:
            return "Data Refresh"
        case .cache:
            return "Cache"
        }
    }

    var iconName: String {
        switch self {
        case .source:
            return "heart.text.square.fill"
        case .permissions:
            return "checkmark.shield.fill"
        case .syncStatus:
            return "arrow.triangle.2.circlepath"
        case .cache:
            return "internaldrive.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .source:
            return .green
        case .permissions:
            return .green
        case .syncStatus:
            return .gray
        case .cache:
            return .gray
        }
    }

    var sheet: BodySettingsSheet? {
        switch self {
        case .source:
            return .source
        case .permissions:
            return .permissions
        case .syncStatus:
            return .syncStatus
        case .cache:
            return .cache
        }
    }
}

enum BodySettingsAboutTab: String, CaseIterable, Identifiable {
    case howToUse
    case privacy
    case onboarding
    case more
    case version

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .howToUse:
            return "How to Use"
        case .privacy:
            return "Privacy"
        case .onboarding:
            return "Onboarding"
        case .more:
            return "More"
        case .version:
            return "Version"
        }
    }

    var iconName: String {
        switch self {
        case .howToUse:
            return "questionmark.circle.fill"
        case .privacy:
            return "hand.raised.fill"
        case .onboarding:
            return "sparkles"
        case .more:
            return "ellipsis.circle.fill"
        case .version:
            return "info.circle.fill"
        }
    }

    var tintColor: Color {
        .gray
    }

    var opensSheet: Bool {
        sheet != nil
    }

    var sheet: BodySettingsSheet? {
        switch self {
        case .more:
            return .more
        case .howToUse, .privacy, .onboarding, .version:
            return nil
        }
    }
}

private protocol BodyUnitPreferenceOption: CaseIterable, Equatable, Identifiable {
    var displayName: String { get }
    var unitLabel: String { get }
}

extension BodyValueFormat.WeightUnitPreference: BodyUnitPreferenceOption { }
extension BodyValueFormat.DistanceUnitPreference: BodyUnitPreferenceOption { }
extension BodyValueFormat.EnergyUnitPreference: BodyUnitPreferenceOption { }
extension BodyValueFormat.TemperatureUnitPreference: BodyUnitPreferenceOption { }

private struct BodySleepSettingsSheet: View {
    @Binding var goalMinutes: Int
    @Binding var showsSubMinuteAwakeStages: Bool
    @Binding var showsLeadingTrailingAwakeStages: Bool

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Sleep") {
            BodySettingsCardSection("Goal") {
                Stepper(
                    value: $goalMinutes,
                    in: BodySleepDurationGoal.minimumMinutes...BodySleepDurationGoal.maximumMinutes,
                    step: BodySleepDurationGoal.stepMinutes
                ) {
                    BodySettingsRowLabel(
                        title: "Amount",
                        value: BodySleepDurationGoal.displayText(for: goalMinutes),
                        iconName: "bed.double.fill",
                        tintColor: Color(red: 0.20, green: 0.72, blue: 1.00)
                    )
                }
                .padding(.trailing, 18)
            }

            BodySettingsCardSection("Sleep Stages") {
                HStack(spacing: 14) {
                    BodySettingsIconTile(
                        iconName: "waveform.path.ecg",
                        color: Color(red: 1.00, green: 0.31, blue: 0.22)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Show Awake Under 1 Min")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("Include very short Awake intervals in sleep stages")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Toggle("Show Awake Under 1 Min", isOn: $showsSubMinuteAwakeStages)
                        .labelsHidden()
                        .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                        .accessibilityValue(showsSubMinuteAwakeStages ? "On" : "Off")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)

                HStack(spacing: 14) {
                    BodySettingsIconTile(
                        iconName: "waveform.path.ecg",
                        color: Color(red: 1.00, green: 0.31, blue: 0.22)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Show Awake at Start & End")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("Include leading and trailing Awake in sleep stages")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Toggle("Show Awake at Start & End", isOn: $showsLeadingTrailingAwakeStages)
                        .labelsHidden()
                        .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                        .accessibilityValue(showsLeadingTrailingAwakeStages ? "On" : "Off")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            }
        }
    }
}

private struct BodyUnitPreferencePickerSheet: View {
    @Binding var followsSystemUnits: Bool
    @Binding var selectedWeightUnit: BodyValueFormat.WeightUnitPreference
    @Binding var selectedDistanceUnit: BodyValueFormat.DistanceUnitPreference
    @Binding var selectedEnergyUnit: BodyValueFormat.EnergyUnitPreference
    @Binding var selectedTemperatureUnit: BodyValueFormat.TemperatureUnitPreference

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        BodySettingsCardSection("System") {
                            Toggle("Follow System", isOn: $followsSystemUnits)
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .tint(.blue)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .frame(minHeight: 70)
                        }

                        BodySettingsCardSection("Units") {
                            BodyUnitPreferenceControlRow(
                                title: "Weight",
                                iconName: "scalemass.fill",
                                tintColor: .purple,
                                options: BodyValueFormat.WeightUnitPreference.allCases,
                                selection: $selectedWeightUnit,
                                isEnabled: !followsSystemUnits
                            )
                            .disabled(followsSystemUnits)

                            Divider()
                                .padding(.leading, 18)

                            BodyUnitPreferenceControlRow(
                                title: "Distance",
                                iconName: "ruler.fill",
                                tintColor: .teal,
                                options: BodyValueFormat.DistanceUnitPreference.allCases,
                                selection: $selectedDistanceUnit,
                                isEnabled: !followsSystemUnits
                            )
                            .disabled(followsSystemUnits)

                            Divider()
                                .padding(.leading, 18)

                            BodyUnitPreferenceControlRow(
                                title: "Energy",
                                iconName: "bolt.fill",
                                tintColor: .orange,
                                options: BodyValueFormat.EnergyUnitPreference.allCases,
                                selection: $selectedEnergyUnit,
                                isEnabled: !followsSystemUnits
                            )
                            .disabled(followsSystemUnits)

                            Divider()
                                .padding(.leading, 18)

                            BodyUnitPreferenceControlRow(
                                title: "Temperature",
                                iconName: "thermometer.medium",
                                tintColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                                options: BodyValueFormat.TemperatureUnitPreference.allCases,
                                selection: $selectedTemperatureUnit,
                                isEnabled: !followsSystemUnits
                            )
                            .disabled(followsSystemUnits)
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .bodySheetBackground()
            .navigationTitle("Units")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BodyWorkoutRouteStyleSettingsSheet: View {
    @Binding var selection: BodyWorkoutRouteStyle
    @Binding var drawsRoute: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var supportsDraw: Bool { selection.supportsRouteDraw }

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Route Style") {
            // Draw leads the sheet: it applies to whichever style is picked below, so it
            // reads as the setting for all of them rather than a footnote to the last one.
            // A bare card rather than a titled `BodySettingsCardSection` — the style card
            // carries no section title either, and mixing the two reads as a mistake.
            HStack(spacing: 14) {
                BodySettingsIconTile(iconName: "scribble.variable", color: .blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Draw Route")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    // Says why it's unavailable rather than leaving a greyed switch
                    // unexplained — the same treatment the share page's dimmed trays get.
                    Text(supportsDraw ? "routeStyle.drawSubtitle" : "routeStyle.drawUnavailable")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("Draw Route", isOn: $drawsRoute)
                    .labelsHidden()
                    .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                    .accessibilityValue(drawsRoute ? "On" : "Off")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            // Dimmed and inert on Map, whose route is baked into the map snapshot and has
            // no stroke to grow. The stored preference is untouched, so picking Plain or
            // 3D again brings back whatever it was set to.
            .opacity(supportsDraw ? 1 : 0.4)
            .disabled(!supportsDraw)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: supportsDraw)
            .bodyCardBackground(translucent: true)

            VStack(spacing: 0) {
                ForEach(Array(BodyWorkoutRouteStyle.allCases.enumerated()), id: \.element) { index, style in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 76)
                    }

                    BodyStarMetricOptionRow(
                        title: style.title,
                        subtitle: style.subtitle,
                        iconName: style.settingsIconName,
                        tintColor: .blue,
                        isSelected: selection == style
                    ) {
                        selection = style
                    }
                }
            }
            .bodyCardBackground(translucent: true)
        }
    }
}

private extension BodyWorkoutRouteStyle {
    var settingsIconName: String {
        switch self {
        case .map:
            "map.fill"
        case .plain:
            "graph.2d"
        case .threeD:
            "move.3d"
        }
    }
}

private struct BodyUnitPreferenceControlRow<Option: BodyUnitPreferenceOption>: View
where Option.AllCases: RandomAccessCollection {
    let title: LocalizedStringKey
    let iconName: String
    let tintColor: Color
    let options: Option.AllCases
    @Binding var selection: Option
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BodySettingsIconTile(
                    iconName: iconName,
                    color: isEnabled ? tintColor : .gray
                )

                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(isEnabled ? .primary : .secondary)

                Spacer(minLength: 12)
            }

            HStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        BodyUnitChoiceButton(
                            title: option.unitLabel,
                            subtitle: option.displayName,
                            tintColor: tintColor,
                            isSelected: selection == option,
                            isEnabled: isEnabled
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BodyUnitChoiceButton: View {
    let title: String
    let subtitle: String
    let tintColor: Color
    let isSelected: Bool
    let isEnabled: Bool

    private var effectiveTintColor: Color {
        isEnabled ? tintColor : .gray
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // `subtitle` carries the unit's English display name (e.g. "Kilograms");
            // resolve it as a catalog key so it localizes.
            Text(LocalizedStringKey(subtitle))
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundColor(isSelected && isEnabled ? .white : effectiveTintColor)
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected && isEnabled ? effectiveTintColor : effectiveTintColor.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(effectiveTintColor.opacity(isSelected ? 0.9 : 0.24), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct BodySummaryCardsSettingsSheet: View {
    @Binding var selection: BodySummaryCardSelection
    @AppStorage(BodyAppearancePreference.showSleepScoreKey) private var showSleepScore = true

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Summary Cards") {
            VStack(spacing: 0) {
                ForEach(BodyHomeCardKind.defaultOrder) { card in
                    BodySummaryCardToggleRow(
                        card: card,
                        isEnabled: Binding {
                            selection.includes(card)
                        } set: { isEnabled in
                            selection = selection.setting(card, isEnabled: isEnabled)
                        }
                    )

                    if card == .sleep {
                        Divider()
                            .padding(.leading, 76)

                        BodySleepScoreToggleRow(isEnabled: $showSleepScore)
                    }

                    if card.id != BodyHomeCardKind.defaultOrder.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .bodyCardBackground(translucent: true)
        }
    }
}

private struct BodyStarMetricPickerSheet: View {
    @Binding var selection: BodyHomeCardKind?

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Star Metric") {
            VStack(spacing: 0) {
                BodyStarMetricOptionRow(
                    title: String(localized: "None"),
                    subtitle: String(localized: "No metric pinned to the top of Home"),
                    iconName: "circle.slash",
                    tintColor: .secondary,
                    isSelected: selection == nil
                ) {
                    selection = nil
                }

                ForEach(BodyHomeCardKind.starEligible) { card in
                    Divider()
                        .padding(.leading, 76)

                    BodyStarMetricOptionRow(
                        title: card.title,
                        subtitle: card.subtitle,
                        iconName: card.iconName,
                        tintColor: card.tintColor,
                        isSelected: selection == card
                    ) {
                        selection = card
                    }
                }
            }
            .bodyCardBackground(translucent: true)
        }
    }
}

private struct BodyHomeBackgroundSheet: View {
    @AppStorage(BodyAppearancePreference.homeBackgroundEnabledKey) private var enabled = true
    @AppStorage(BodyAppearancePreference.homeBackgroundColorsKey) private var colorsRawValue = ""
    @AppStorage(BodyAppearancePreference.homeBackgroundSeparatorsKey) private var separatorsRawValue = ""
    @AppStorage(BodyAppearancePreference.homeBackgroundProfilesKey) private var profilesRawValue = ""
    @State private var profileBeingRenamed: BodyHomeBackgroundProfile?
    @State private var renameProfileName = ""
    @State private var profileBeingDeleted: BodyHomeBackgroundProfile?
    @State private var deleteProfileName = ""

    private var colors: Binding<[Color]> {
        Binding {
            var parsed = BodyHomeBackground.colors(from: colorsRawValue)
            while parsed.count < 3 {
                parsed.append(BodyHomeBackground.defaultColors[parsed.count])
            }
            return Array(parsed.prefix(3))
        } set: {
            colorsRawValue = BodyHomeBackground.rawValue(from: $0)
        }
    }

    private var separators: Binding<[Double]> {
        Binding {
            BodyHomeBackground.normalizedSeparators(
                BodyHomeBackground.separators(from: separatorsRawValue),
                count: 3
            )
        } set: {
            separatorsRawValue = BodyHomeBackground.rawValue(fromSeparators: $0)
        }
    }

    private var customProfiles: [BodyHomeBackgroundProfile] {
        BodyHomeBackgroundProfileStore.customProfiles(from: profilesRawValue)
    }

    private var profiles: [BodyHomeBackgroundProfile] {
        BodyHomeBackgroundProfileStore.allProfiles(from: profilesRawValue)
    }

    private var currentProfileFingerprint: String {
        BodyHomeBackgroundProfile.fingerprint(colors: colors.wrappedValue, separators: separators.wrappedValue)
    }

    private var canSaveCurrentProfile: Bool {
        !profiles.contains { $0.fingerprint == currentProfileFingerprint }
            && customProfiles.count < BodyHomeBackgroundProfileStore.maximumCustomProfileCount
    }

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Background") {
            VStack(spacing: 20) {
                showToggleRow

                BodyHomeBackgroundPreview(colors: colors.wrappedValue, separators: separators)
                    .frame(height: 180)
                    .opacity(enabled ? 1 : 0.35)
                    .allowsHitTesting(enabled)

                BodyHomeBackgroundColorWheel(colors: colors)
                    .frame(height: 300)
                    .opacity(enabled ? 1 : 0.35)
                    .allowsHitTesting(enabled)

                profilesSection
                    .opacity(enabled ? 1 : 0.35)
                    .allowsHitTesting(enabled)

                Text("Drag a color around the spectrum to recolor it, or drag a divider on the preview to change how much space each color takes.")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("Rename Profile", isPresented: isRenamingProfile) {
            TextField("Profile Name", text: $renameProfileName)

            Button("Save", action: commitProfileRename)

            Button(role: .cancel, action: discardProfileRename) {
                Text("Cancel")
            }
        }
        .alert("Delete \"\(deleteProfileName)\"?", isPresented: isConfirmingDelete) {
            Button("Delete", role: .destructive, action: confirmProfileDeletion)

            Button("Cancel", role: .cancel, action: discardProfileDeletion)
        } message: {
            Text("This profile will be removed.")
        }
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Profiles")
                    .font(.system(size: BodySettingsTypography.sectionTitleFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                Button(action: saveCurrentProfile) {
                    Label("Save Current", systemImage: "plus.circle.fill")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(canSaveCurrentProfile ? .blue : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill((canSaveCurrentProfile ? Color.blue : Color.secondary).opacity(0.14))
                )
                .disabled(!canSaveCurrentProfile)
            }

            VStack(spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    let defaultTitle = profile.id == BodyHomeBackgroundProfile.appDefaultID ? String(localized: "App Default") : String(localized: "Saved \(index)")
                    let title = profile.displayName(defaultName: defaultTitle)
                    let canEditProfile = profile.id != BodyHomeBackgroundProfile.appDefaultID

                    BodyHomeBackgroundProfileRow(
                        profile: profile,
                        title: title,
                        isSelected: profile.fingerprint == currentProfileFingerprint,
                        canEdit: canEditProfile,
                        onSelect: {
                            applyProfile(profile)
                        },
                        onRename: {
                            beginRenamingProfile(profile, defaultName: defaultTitle)
                        },
                        onDelete: {
                            beginDeletingProfile(profile, name: title)
                        }
                    )

                    if index < profiles.count - 1 {
                        Divider()
                            .padding(.leading, 86)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .bodyCardBackground(cornerRadius: 26, translucent: true)
        }
    }

    private var showToggleRow: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: "paintpalette.fill", color: .teal)

            VStack(alignment: .leading, spacing: 3) {
                Text("Show Background")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Shown on Home, Workouts, and Settings")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 12)

            Toggle("Show Background", isOn: $enabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private var isRenamingProfile: Binding<Bool> {
        Binding {
            profileBeingRenamed != nil
        } set: { isPresented in
            if !isPresented {
                discardProfileRename()
            }
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding {
            profileBeingDeleted != nil
        } set: { isPresented in
            if !isPresented {
                discardProfileDeletion()
            }
        }
    }

    private func saveCurrentProfile() {
        guard canSaveCurrentProfile else { return }
        let defaultName = String(localized: "Saved \(customProfiles.count + 1)")
        let nextProfile = BodyHomeBackgroundProfile.custom(
            name: defaultName,
            colors: colors.wrappedValue,
            separators: separators.wrappedValue
        )
        storeCustomProfiles(customProfiles + [nextProfile])
    }

    private func applyProfile(_ profile: BodyHomeBackgroundProfile) {
        if profile.id == BodyHomeBackgroundProfile.appDefaultID {
            colorsRawValue = ""
            separatorsRawValue = ""
        } else {
            colorsRawValue = profile.colorsRawValue
            separatorsRawValue = profile.separatorsRawValue
        }
    }

    private func beginDeletingProfile(_ profile: BodyHomeBackgroundProfile, name: String) {
        guard profile.id != BodyHomeBackgroundProfile.appDefaultID else { return }
        profileBeingDeleted = profile
        deleteProfileName = name
    }

    private func confirmProfileDeletion() {
        guard let profileBeingDeleted else { return }
        storeCustomProfiles(customProfiles.filter { $0.id != profileBeingDeleted.id })
        discardProfileDeletion()
    }

    private func discardProfileDeletion() {
        profileBeingDeleted = nil
        deleteProfileName = ""
    }

    private func beginRenamingProfile(_ profile: BodyHomeBackgroundProfile, defaultName: String) {
        guard profile.id != BodyHomeBackgroundProfile.appDefaultID else { return }
        profileBeingRenamed = profile
        renameProfileName = profile.displayName(defaultName: defaultName)
    }

    private func commitProfileRename() {
        guard let profileBeingRenamed else { return }
        storeCustomProfiles(
            customProfiles.map { profile in
                profile.id == profileBeingRenamed.id ? profile.renamed(renameProfileName) : profile
            }
        )
        discardProfileRename()
    }

    private func discardProfileRename() {
        profileBeingRenamed = nil
        renameProfileName = ""
    }

    private func storeCustomProfiles(_ profiles: [BodyHomeBackgroundProfile]) {
        profilesRawValue = BodyHomeBackgroundProfileStore.rawValue(from: profiles)
    }
}

private struct BodyHomeBackgroundProfileRow: View {
    let profile: BodyHomeBackgroundProfile
    let title: String
    let isSelected: Bool
    let canEdit: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var revealsDelete = false
    @State private var dragWidth: CGFloat = 0
    @State private var didSwipe = false

    private let deleteActionWidth: CGFloat = 82

    private var contentOffset: CGFloat {
        let settled: CGFloat = revealsDelete ? -deleteActionWidth : 0
        return max(-deleteActionWidth, min(0, settled + dragWidth))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if canEdit {
                Button(role: .destructive) {
                    closeDelete()
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "accessibility.deleteProfile", defaultValue: "Delete \(title)"))
                .frame(width: max(0, -contentOffset), alignment: .trailing)
                .clipped()
            }

            rowContent
                .offset(x: contentOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard canEdit else { return }
                            // Only follow horizontal swipes so vertical scrolling still works.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            didSwipe = true
                            dragWidth = value.translation.width
                        }
                        .onEnded { value in
                            guard canEdit else { return }
                            let settled: CGFloat = revealsDelete ? -deleteActionWidth : 0
                            let projected = settled + value.predictedEndTranslation.width
                            withAnimation(.easeOut(duration: 0.2)) {
                                revealsDelete = projected < -deleteActionWidth / 2
                                dragWidth = 0
                            }
                        }
                )
        }
        .clipped()
    }

    private var rowContent: some View {
        ZStack(alignment: .leading) {
            Button(action: selectOrCloseDelete) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 14) {
                BodyHomeBackgroundProfileSwatch(colors: profile.colors, separators: profile.separators)

                profileText

                Spacer(minLength: 12)

                if isSelected, !revealsDelete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .allowsHitTesting(false)

            if canEdit, !revealsDelete {
                // Mirror the row's leading layout (hidden swatch + hidden summary)
                // so the tappable title lands exactly on the real title line above
                // the summary, instead of relying on hard-coded offsets.
                HStack(spacing: 14) {
                    BodyHomeBackgroundProfileSwatch(colors: profile.colors, separators: profile.separators)
                        .hidden()

                    VStack(alignment: .leading, spacing: 3) {
                        Button(action: onRename) {
                            Text(title)
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rename \(title)")

                        Text(profile.segmentSummary)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .hidden()
                    }

                    Spacer(minLength: 12)
                }
            }
        }
        .padding(.leading, 14)
        .padding(.vertical, 12)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
        .background(Color.clear)
    }

    private func selectOrCloseDelete() {
        // The full-row button fires on release of a swipe; ignore that tap so it
        // doesn't immediately re-close the delete action the swipe just revealed.
        if didSwipe {
            didSwipe = false
            return
        }
        if revealsDelete {
            closeDelete()
        } else {
            onSelect()
        }
    }

    private func closeDelete() {
        withAnimation(.easeOut(duration: 0.2)) {
            revealsDelete = false
            dragWidth = 0
        }
    }

    private var profileText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(canEdit && !revealsDelete ? 0 : 1)

            Text(profile.segmentSummary)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

private struct BodyHomeBackgroundProfileSwatch: View {
    let colors: [Color]
    let separators: [Double]

    var body: some View {
        BodyActivityRingsCard.heroBackground(colors: colors, separators: separators)
            .frame(width: 58, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
    }
}

private struct BodyHomeBackgroundPreview: View {
    let colors: [Color]
    @Binding var separators: [Double]
    /// Live positions while a handle is being dragged; the @AppStorage-backed
    /// `separators` binding is only written once, on gesture end, so a drag no
    /// longer persists (and re-encodes the raw string) on every frame.
    @State private var draftSeparators: [Double]?

    var body: some View {
        let activeSeparators = draftSeparators ?? separators
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .topLeading) {
                BodyActivityRingsCard.heroBackground(colors: colors, separators: activeSeparators)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                ForEach(activeSeparators.indices, id: \.self) { index in
                    BodyHomeBackgroundSeparatorHandle()
                        .frame(width: 30, height: geo.size.height)
                        .contentShape(Rectangle())
                        .position(x: CGFloat(activeSeparators[index]) * width, y: geo.size.height / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("bgPreview"))
                                .onChanged { value in
                                    guard width > 0 else { return }
                                    var working = draftSeparators ?? separators
                                    let raw = Double(value.location.x / width)
                                    let lower = index > 0 ? working[index - 1] + 0.06 : 0.06
                                    let upper = index < working.count - 1 ? working[index + 1] - 0.06 : 0.94
                                    working[index] = min(max(raw, lower), upper)
                                    draftSeparators = working
                                }
                                .onEnded { _ in
                                    if let draftSeparators {
                                        separators = draftSeparators
                                    }
                                    draftSeparators = nil
                                }
                        )
                }
            }
            .coordinateSpace(name: "bgPreview")
        }
    }
}

private struct BodyHomeBackgroundSeparatorHandle: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(.white)
                .frame(width: 3)
                .shadow(color: .black.opacity(0.3), radius: 2)

            Circle()
                .fill(.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .overlay(
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                )
        }
    }
}

/// A circular HSV spectrum with one draggable bubble per mix color. Dragging a bubble
/// sets that color's hue from the angle and saturation from the distance to the center.
private struct BodyHomeBackgroundColorWheel: View {
    @Binding var colors: [Color]
    /// Live bubble colors while one is being dragged; the @AppStorage-backed
    /// `colors` binding is only written once, on gesture end, so a drag no longer
    /// persists (and re-encodes the raw string) on every frame.
    @State private var draftColors: [Color]?

    private let bubbleSizes: [CGFloat] = [66, 50, 58]

    var body: some View {
        let activeColors = draftColors ?? colors
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                ZStack {
                    AngularGradient(gradient: Gradient(colors: Self.hueRing), center: .center)
                    RadialGradient(
                        gradient: Gradient(colors: [.white, .white.opacity(0)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                }
                .frame(width: side, height: side)
                .clipShape(Circle())
                .position(center)

                ForEach(activeColors.indices, id: \.self) { index in
                    Circle()
                        .fill(activeColors[index])
                        .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                        .frame(width: bubbleSize(index), height: bubbleSize(index))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                        .position(position(for: activeColors[index], center: center, radius: radius))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("colorWheel"))
                                .onChanged { value in
                                    var working = draftColors ?? colors
                                    working[index] = Self.color(at: value.location, center: center, radius: radius)
                                    draftColors = working
                                }
                                .onEnded { _ in
                                    if let draftColors {
                                        colors = draftColors
                                    }
                                    draftColors = nil
                                }
                        )
                }
            }
            .coordinateSpace(name: "colorWheel")
        }
    }

    private static let hueRing: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12.0)
        .map { Color(hue: $0, saturation: 1, brightness: 1) }

    private func bubbleSize(_ index: Int) -> CGFloat {
        bubbleSizes.indices.contains(index) ? bubbleSizes[index] : 56
    }

    private func position(for color: Color, center: CGPoint, radius: CGFloat) -> CGPoint {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let angle = Double(h) * 2 * .pi
        let dist = Double(min(s, 1)) * Double(radius)
        return CGPoint(
            x: center.x + CGFloat(cos(angle) * dist),
            y: center.y + CGFloat(sin(angle) * dist)
        )
    }

    private static func color(at point: CGPoint, center: CGPoint, radius: CGFloat) -> Color {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let dist = min((dx * dx + dy * dy).squareRoot(), Double(radius))
        var angle = atan2(dy, dx) / (2 * .pi)
        if angle < 0 { angle += 1 }
        let saturation = radius > 0 ? dist / Double(radius) : 0
        return Color(hue: angle, saturation: saturation, brightness: 1)
    }
}

/// Hue/saturation/brightness is the editor's only draft state: round-tripping
/// through RGB loses hue and saturation the moment brightness reaches 0.
/// The calendar's rendering of a workout color — a solid tile with the glyph in
/// the same contrast color the month grid uses — shown beside the tinted-glyph
/// tile so both of the app's workout color styles preview at once.
private struct BodyWorkoutCalendarStyleTile: View {
    let iconName: String
    let hex: UInt32

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 21, weight: .semibold))
            .foregroundColor(BodyWorkoutType.luminance(hex: hex) > 0.58 ? Color.black.opacity(0.82) : .white)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BodyWorkoutType.attachedWorkoutColor(hex: hex))
            )
    }
}

private struct BodyWorkoutColorDraft: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hex: UInt32) {
        let color = UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }

    var hex: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(
            hue: CGFloat(hue),
            saturation: CGFloat(saturation),
            brightness: CGFloat(brightness),
            alpha: 1
        ).getRed(&r, green: &g, blue: &b, alpha: &a)

        let red = UInt32((max(0, min(1, r)) * 255).rounded())
        let green = UInt32((max(0, min(1, g)) * 255).rounded())
        let blue = UInt32((max(0, min(1, b)) * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

private struct BodyWorkoutColorsSheet: View {
    @AppStorage(BodyAppearancePreference.workoutColorOverridesKey, store: BodyWorkoutColorStore.sharedDefaults)
    private var overridesRawValue = ""
    @AppStorage(BodyAppearancePreference.knownWorkoutTypesKey, store: BodyWorkoutColorStore.sharedDefaults)
    private var knownWorkoutTypesRawValue = ""
    @State private var editedType: BodyWorkoutType?
    @State private var isConfirmingResetAll = false

    private var overrides: [BodyWorkoutType: UInt32] {
        BodyWorkoutColorOverrides.overrides(from: overridesRawValue)
    }

    /// Always resolved unlocked: the row that opens this sheet is Pro-gated, so
    /// reaching it means the entitlement is active.
    private var palette: BodyWorkoutColorPalette {
        BodyWorkoutColorPalette(rawOverrides: overridesRawValue, isProUnlocked: true)
    }

    /// The census plus anything already customized, so a type whose overrides
    /// outlived its workouts stays reachable (and resettable).
    private var workoutTypes: [BodyWorkoutType] {
        BodyKnownWorkoutTypesCensus.types(from: knownWorkoutTypesRawValue)
            .union(overrides.keys)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Workout Colors") {
            VStack(alignment: .leading, spacing: 20) {
                if workoutTypes.isEmpty {
                    emptyState
                } else {
                    typesCard

                    if !overrides.isEmpty {
                        resetAllButton
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                Text(String(localized: "workoutColors.footer", defaultValue: "Tap a workout to give it your own color. Everything that shows that workout uses it."))
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $editedType) { type in
            BodyWorkoutColorEditorView(type: type, overridesRawValue: $overridesRawValue)
        }
        .alert(
            String(localized: "workoutColors.resetAllTitle", defaultValue: "Reset all workout colors?"),
            isPresented: $isConfirmingResetAll
        ) {
            Button(String(localized: "workoutColors.resetAllConfirm", defaultValue: "Reset"), role: .destructive) {
                overridesRawValue = ""
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text(String(localized: "workoutColors.resetAllMessage", defaultValue: "Every workout type goes back to its built-in color."))
        }
    }

    private var typesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(workoutTypes.enumerated()), id: \.element.id) { index, type in
                Button {
                    editedType = type
                } label: {
                    typeRow(for: type)
                }
                .buttonStyle(.plain)

                if index < workoutTypes.count - 1 {
                    Divider()
                        .padding(.leading, 134)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .bodyCardBackground(cornerRadius: 26, translucent: true)
    }

    private func typeRow(for type: BodyWorkoutType) -> some View {
        HStack(spacing: 14) {
            BodyWorkoutCalendarStyleTile(iconName: type.symbolName, hex: palette.resolvedHex(for: type))

            BodySettingsIconTile(iconName: type.symbolName, color: palette.color(for: type))

            Text(type.displayName)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            // Marks the types whose color was customized, so an edit is findable
            // at a glance among the built-in rows.
            if overrides[type] != nil {
                Image(systemName: "pencil")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(.secondary)
            }

            Text("#\(BodyWorkoutColorOverrides.hexText(from: palette.resolvedHex(for: type)))")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(.caption, weight: .bold))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var resetAllButton: some View {
        Button {
            isConfirmingResetAll = true
        } label: {
            Label(
                String(localized: "workoutColors.resetAll", defaultValue: "Reset All"),
                systemImage: "arrow.counterclockwise"
            )
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.red)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(Color.red.opacity(0.14)))
    }

    private var emptyState: some View {
        Text(String(localized: "workoutColors.empty", defaultValue: "No workouts yet. Workout types appear here once you've logged them."))
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BodyWorkoutColorEditorView: View {
    let type: BodyWorkoutType
    @Binding var overridesRawValue: String

    private enum Field: Hashable {
        case hex
        case red
        case green
        case blue
    }

    @State private var draft: BodyWorkoutColorDraft
    /// Each text field edits its own string while focused and only feeds the HSB
    /// draft on submit or focus loss, so no field observes another and there is
    /// no reciprocal update loop.
    @State private var hexText = ""
    @State private var redText = ""
    @State private var greenText = ""
    @State private var blueText = ""
    @FocusState private var focusedField: Field?

    init(type: BodyWorkoutType, overridesRawValue: Binding<String>) {
        self.type = type
        _overridesRawValue = overridesRawValue
        let stored = BodyWorkoutColorOverrides.overrides(from: overridesRawValue.wrappedValue)
        _draft = State(initialValue: BodyWorkoutColorDraft(hex: stored[type] ?? type.colorHex))
    }

    private var hasOverride: Bool {
        BodyWorkoutColorOverrides.overrides(from: overridesRawValue)[type] != nil
    }

    var body: some View {
        // `displayName` is already localized (BodyMetricsKit table); wrapping it as a
        // key is a pass-through — an unmatched key renders as itself.
        BodySettingsAboutSheetScaffold(title: LocalizedStringKey(type.displayName)) {
            VStack(alignment: .leading, spacing: 20) {
                previewRow

                BodyWorkoutColorWheel(
                    hue: $draft.hue,
                    saturation: $draft.saturation,
                    brightness: draft.brightness,
                    onCommit: commitDraft
                )
                .frame(height: 300)

                brightnessSection

                valuesSection

                resetButton
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear(perform: syncTextFields)
        .onChange(of: focusedField) { previous, _ in
            commitText(for: previous)
        }
        .onSubmit {
            commitText(for: focusedField)
            focusedField = nil
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button(String(localized: "workoutColors.doneEditing", defaultValue: "Done")) {
                    focusedField = nil
                }
            }
        }
    }

    private var previewRow: some View {
        HStack(spacing: 14) {
            BodyWorkoutCalendarStyleTile(iconName: type.symbolName, hex: draft.hex)

            BodySettingsIconTile(iconName: type.symbolName, color: draft.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(type.displayName)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("#\(BodyWorkoutColorOverrides.hexText(from: draft.hex))")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .bodyCardBackground(cornerRadius: 26, translucent: true)
    }

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "workoutColors.brightness", defaultValue: "Brightness"))
                .font(.system(size: BodySettingsTypography.sectionTitleFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: draft.hue, saturation: draft.saturation, brightness: 0),
                                Color(hue: draft.hue, saturation: draft.saturation, brightness: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 10)

                Slider(value: $draft.brightness, in: 0...1) { isEditing in
                    if !isEditing {
                        commitDraft()
                    }
                }
                .tint(draft.color)
                .accessibilityLabel(String(localized: "workoutColors.brightness", defaultValue: "Brightness"))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .bodyCardBackground(cornerRadius: 26, translucent: true)
        }
    }

    private var valuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "workoutColors.values", defaultValue: "Values"))
                .font(.system(size: BodySettingsTypography.sectionTitleFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 0) {
                fieldRow(
                    title: String(localized: "workoutColors.hex", defaultValue: "Hex"),
                    placeholder: String(localized: "workoutColors.hexPlaceholder", defaultValue: "RRGGBB"),
                    text: $hexText,
                    field: .hex,
                    keyboard: .asciiCapable
                )

                Divider()

                fieldRow(
                    title: String(localized: "workoutColors.red", defaultValue: "Red"),
                    placeholder: "0",
                    text: $redText,
                    field: .red,
                    keyboard: .numberPad
                )

                Divider()

                fieldRow(
                    title: String(localized: "workoutColors.green", defaultValue: "Green"),
                    placeholder: "0",
                    text: $greenText,
                    field: .green,
                    keyboard: .numberPad
                )

                Divider()

                fieldRow(
                    title: String(localized: "workoutColors.blue", defaultValue: "Blue"),
                    placeholder: "0",
                    text: $blueText,
                    field: .blue,
                    keyboard: .numberPad
                )
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .bodyCardBackground(cornerRadius: 26, translucent: true)
        }
    }

    private func fieldRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer(minLength: 12)

            TextField(placeholder, text: text)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focusedField, equals: field)
                .frame(width: 110)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 14)
    }

    private var resetButton: some View {
        Button(action: resetToDefault) {
            Label(
                String(localized: "workoutColors.reset", defaultValue: "Reset to Default"),
                systemImage: "arrow.counterclockwise"
            )
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(hasOverride ? .red : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill((hasOverride ? Color.red : Color.secondary).opacity(0.14))
        )
        .disabled(!hasOverride)
    }

    /// Persists on gesture end, slider end, and field commit — never per frame —
    /// so a drag doesn't re-encode the shared raw string on every tick.
    private func commitDraft() {
        var parsed = BodyWorkoutColorOverrides.overrides(from: overridesRawValue)
        parsed[type] = draft.hex
        // The codec drops entries that merely restate the built-in color, so a
        // draft dragged back onto the default clears the override on its own.
        overridesRawValue = BodyWorkoutColorOverrides.rawValue(from: parsed)
        syncTextFields()
    }

    private func resetToDefault() {
        var parsed = BodyWorkoutColorOverrides.overrides(from: overridesRawValue)
        parsed.removeValue(forKey: type)
        overridesRawValue = BodyWorkoutColorOverrides.rawValue(from: parsed)
        draft = BodyWorkoutColorDraft(hex: type.colorHex)
        syncTextFields()
    }

    private func syncTextFields() {
        let hex = draft.hex
        hexText = BodyWorkoutColorOverrides.hexText(from: hex)
        redText = String((hex >> 16) & 0xFF)
        greenText = String((hex >> 8) & 0xFF)
        blueText = String(hex & 0xFF)
    }

    /// Validates one field's string and folds it into the HSB draft. Anything
    /// unparseable simply snaps back to the current value.
    private func commitText(for field: Field?) {
        guard let field else { return }

        switch field {
        case .hex:
            var text = hexText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if text.hasPrefix("#") {
                text.removeFirst()
            }
            guard text.count == 6,
                  text.allSatisfy({ $0.isHexDigit }),
                  let hex = UInt32(text, radix: 16) else {
                syncTextFields()
                return
            }
            draft = BodyWorkoutColorDraft(hex: hex)
        case .red, .green, .blue:
            let source: String
            switch field {
            case .red:
                source = redText
            case .green:
                source = greenText
            default:
                source = blueText
            }

            guard let component = UInt32(source.trimmingCharacters(in: .whitespacesAndNewlines)),
                  component <= 255 else {
                syncTextFields()
                return
            }

            let hex = draft.hex
            var red = (hex >> 16) & 0xFF
            var green = (hex >> 8) & 0xFF
            var blue = hex & 0xFF
            switch field {
            case .red:
                red = component
            case .green:
                green = component
            default:
                blue = component
            }
            draft = BodyWorkoutColorDraft(hex: (red << 16) | (green << 8) | blue)
        }

        commitDraft()
    }
}

/// Single-bubble sibling of `BodyHomeBackgroundColorWheel`: the drag sets hue and
/// saturation only, and the ring is rendered at the draft's brightness so what the
/// wheel shows is what the color will be.
private struct BodyWorkoutColorWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    let brightness: Double
    let onCommit: () -> Void

    private let bubbleSize: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                ZStack {
                    AngularGradient(gradient: Gradient(colors: hueRing), center: .center)
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(hue: 0, saturation: 0, brightness: brightness),
                            Color(hue: 0, saturation: 0, brightness: brightness).opacity(0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                }
                .frame(width: side, height: side)
                .clipShape(Circle())
                .position(center)

                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                    .frame(width: bubbleSize, height: bubbleSize)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    .position(bubblePosition(center: center, radius: radius))
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("workoutColorWheel"))
                            .onChanged { value in
                                update(with: value.location, center: center, radius: radius)
                            }
                            .onEnded { _ in
                                onCommit()
                            }
                    )
            }
            .coordinateSpace(name: "workoutColorWheel")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "accessibility.workoutColorWheel", defaultValue: "Color wheel"))
        .accessibilityHint(String(localized: "accessibility.workoutColorWheelHint", defaultValue: "Drag to set hue and saturation. Use the Brightness slider and the Hex and RGB fields to set exact values."))
    }

    private var hueRing: [Color] {
        stride(from: 0.0, through: 1.0, by: 1.0 / 12.0)
            .map { Color(hue: $0, saturation: 1, brightness: brightness) }
    }

    private func bubblePosition(center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = hue * 2 * .pi
        let dist = min(saturation, 1) * Double(radius)
        return CGPoint(
            x: center.x + CGFloat(cos(angle) * dist),
            y: center.y + CGFloat(sin(angle) * dist)
        )
    }

    private func update(with point: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let dist = min((dx * dx + dy * dy).squareRoot(), Double(radius))
        var angle = atan2(dy, dx) / (2 * .pi)
        if angle < 0 { angle += 1 }
        hue = angle
        saturation = radius > 0 ? dist / Double(radius) : 0
    }
}

private struct BodyStarMetricOptionRow: View {
    let title: String
    let subtitle: String
    let iconName: String
    let tintColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                BodySettingsIconTile(iconName: iconName, color: tintColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(tintColor)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BodySleepScoreToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "moon.stars.fill",
                color: Color(red: 0.20, green: 0.72, blue: 1.00)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Sleep Score")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("v3")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.14), in: Capsule())
                }

                Text("Nightly score from sleep stages, vitals, and timing")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Sleep Score", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyWorkoutEffortSettingsSheet: View {
    @Binding var cardEnabled: Bool
    @Binding var isEnabled: Bool
    @Binding var autoApply: Bool
    @ObservedObject var workoutStore: HealthKitWorkoutStore
    @State private var showsWorkoutEffortWriteDenied = false
    /// Retains the immediate opt-in auto-apply pass so switching Auto-Apply off
    /// (or leaving the sheet) cancels the in-flight batch instead of letting it
    /// finish writing after the user reversed the decision.
    @State private var autoApplyTask: Task<Void, Never>?

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Workout Effort") {
            VStack(alignment: .leading, spacing: 22) {
                // Each setting sits in its own section so its footer explains only that
                // option.
                VStack(alignment: .leading, spacing: 12) {
                    BodySettingsCardSection("Effort Card") {
                        BodyWorkoutEffortCardToggleRow(isEnabled: $cardEnabled)
                    }

                    Text("Show the Effort card on workout detail pages. Off, the card disappears everywhere and nothing below applies.")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    BodySettingsCardSection("Effort Suggestions") {
                        BodyEffortSuggestionToggleRow(isEnabled: $isEnabled)
                            // Subordinate to the Effort card: nowhere to show a
                            // prediction while the card is hidden.
                            .disabled(!cardEnabled)
                            .opacity(cardEnabled ? 1 : 0.4)
                    }

                    Text("When on, Body estimates a 1-10 effort for each workout from available workout, heart-rate, recent history, and readiness data. The suggestion appears on workout details and pre-fills unrated effort edits; your saved ratings stay in control, and unchanged accepted suggestions are excluded from future calibration.")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    BodySettingsCardSection("Auto-Apply Effort") {
                        BodyAutoApplyEffortToggleRow(isEnabled: $autoApply)
                            // Subordinate to Effort Suggestions: no prediction to apply
                            // while suggestions (or the card above them) are off.
                            .disabled(!autoApplyAvailable)
                            .opacity(autoApplyAvailable ? 1 : 0.4)
                    }
                    // Request write access at the moment of intent. If the user denies it,
                    // reset the toggle and explain; otherwise fill eligible recent workouts
                    // right away instead of waiting for the next refresh.
                    .onChange(of: autoApply) {
                        guard autoApply else {
                            // Turned off: cancel any in-flight opt-in pass so it
                            // stops mid-batch instead of finishing writes.
                            autoApplyTask?.cancel()
                            autoApplyTask = nil
                            return
                        }
                        autoApplyTask?.cancel()
                        autoApplyTask = Task {
                            if await workoutStore.requestWorkoutEffortWriteAuthorization() {
                                await workoutStore.autoApplyPredictedEffortNow()
                            } else {
                                autoApply = false
                                showsWorkoutEffortWriteDenied = true
                            }
                        }
                    }
                    .alert("Auto-Apply Needs Permission", isPresented: $showsWorkoutEffortWriteDenied) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Auto-Apply needs permission to update Workouts in Apple Health. Allow it in Settings › Health › Data Access & Devices › Body, then switch Auto-Apply back on.")
                    }

                    autoApplyExplanation
                }
            }
        }
        .onDisappear {
            autoApplyTask?.cancel()
            autoApplyTask = nil
        }
    }

    private var autoApplyAvailable: Bool {
        cardEnabled && isEnabled
    }

    // Spells out the auto-apply eligibility rules so it's clear why some unrated
    // workouts get filled and others are left blank.
    private var autoApplyExplanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When on, Body fills in effort for you, but only when it's confident. Some workouts get filled and others are left for you to rate:")
                .fontWeight(.semibold)
            autoApplyRule("Unrated only. Body never changes an effort you or your Apple Watch already set.")
            autoApplyRule("About an hour after a workout ends. Body waits so a rating from your Apple Watch has time to sync first.")
            autoApplyRule("Only the past 2 days. Body fills workouts that ended within the last 48 hours and leaves older ones alone.")
            autoApplyRule("Enough data. Only workouts with heart-rate data get a prediction; sessions without heart rate stay blank for you to rate.")
            Text("Re-rate any workout anytime to override Body's value.")
                .fontWeight(.semibold)
        }
        .font(.system(.footnote, design: .rounded))
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    private func autoApplyRule(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: "•")
            Text(text)
        }
    }
}

private struct BodyWorkoutEffortCardToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "rectangle.portrait.on.rectangle.portrait.fill",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Effort Card")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Show effort on workout details")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Effort Card", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// Internal (not private) so onboarding can offer the same setting.
struct BodyEffortSuggestionToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "speedometer",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Effort Suggestions")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("v1")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.14), in: Capsule())
                }

                Text("Body's predicted effort on every workout")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Effort Suggestions", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyWorkoutEquivalentsSettingsSheet: View {
    @Binding var hapticsEnabled: Bool
    @AppStorage(BodyAppearancePreference.workoutEquivalentHiddenFoodsKey) private var hiddenFoodsRawValue = BodyEquivalentFoodSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.workoutEquivalentPrefersMoreItemsKey) private var prefersMoreItems = false
    @AppStorage(BodyAppearancePreference.workoutEquivalentUsesTotalEnergyKey) private var usesTotalEnergy = false
    @AppStorage(BodyAppearancePreference.workoutEquivalentCardEnabledKey) private var cardEnabled = true
    @AppStorage(BodyAppearancePreference.workoutEquivalentEmojiScaleKey) private var emojiScale = 1.0

    private var foodSelection: Binding<BodyEquivalentFoodSelection> {
        Binding {
            BodyEquivalentFoodSelection.storedValue(from: hiddenFoodsRawValue)
        } set: { newValue in
            hiddenFoodsRawValue = newValue.rawValue
        }
    }

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Workout Equivalents") {
            VStack(alignment: .leading, spacing: 12) {
                BodyWorkoutEquivalentCardToggleRow(isEnabled: $cardEnabled)
                    .bodyCardBackground(translucent: true)

                Text("Show the Equivalent card on workout detail pages. Off, the card disappears everywhere and nothing below applies.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                BodyWorkoutEquivalentEmojiSizeRow(scale: $emojiScale)
                    .bodyCardBackground(translucent: true)

                BodyWorkoutEquivalentHapticsToggleRow(isEnabled: $hapticsEnabled)
                    .bodyCardBackground(translucent: true)

                Text("Vibration plays a soft tap whenever two foods collide in the Equivalent card. Turn it off if you'd rather the card stay silent.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                BodyWorkoutEquivalentTotalEnergyToggleRow(isEnabled: $usesTotalEnergy)
                    .bodyCardBackground(translucent: true)

                Text("Total Energy represents everything the workout burned, resting energy included. Off, the card shows only the active energy the workout itself added.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                BodyWorkoutEquivalentMoreItemsToggleRow(isEnabled: $prefersMoreItems)
                    .bodyCardBackground(translucent: true)

                Text("More Food Items fills the card with more, smaller foods, like five snacks instead of one burger. Off, the card shows the fewest foods that cover the workout's energy.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(EnergyEquivalent.foods) { food in
                        BodyEquivalentFoodToggleRow(
                            food: food,
                            isEnabled: Binding {
                                foodSelection.wrappedValue.isVisible(food)
                            } set: { isVisible in
                                foodSelection.wrappedValue = foodSelection.wrappedValue.setting(food, isVisible: isVisible)
                            }
                        )

                        if food.id != EnergyEquivalent.foods.last?.id {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .bodyCardBackground(translucent: true)
            }
        }
    }
}

private struct BodyWorkoutEquivalentHapticsToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "fork.knife",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Collision Vibration")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Light haptics when foods bump into each other")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Collision Vibration", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyWorkoutEquivalentCardToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "rectangle.portrait.on.rectangle.portrait.fill",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Equivalent Card")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Show food equivalents on workout details")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Equivalent Card", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyWorkoutEquivalentEmojiSizeRow: View {
    @Binding var scale: Double

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "textformat.size",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Emoji Size")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Slider(value: $scale, in: 0.7...1.3) {
                    Text("Emoji Size")
                } minimumValueLabel: {
                    // `verbatim` keeps the decorative emoji out of the string
                    // catalog; the LocalizedStringKey initializer extracts it as a
                    // translatable key with no localizations.
                    Text(verbatim: "🍔")
                        .font(.system(size: 13))
                } maximumValueLabel: {
                    Text(verbatim: "🍔")
                        .font(.system(size: 22))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyWorkoutEquivalentTotalEnergyToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "flame.fill",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Total Energy")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Include resting energy, not just the active burn")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Total Energy", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyWorkoutEquivalentMoreItemsToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "circle.hexagongrid.fill",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("More Food Items")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Prefer many small foods over a few large ones")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("More Food Items", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyEquivalentFoodToggleRow: View {
    let food: EnergyEquivalent.Food
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(food.emoji)
                .font(.system(size: 30))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("equivalent.food.kcalFormat \(Int(food.kilocalories))")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            Toggle(isOn: $isEnabled) {
                Text(food.name)
            }
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyWorkoutMonthSwipeSettingsSheet: View {
    @Binding var isEnabled: Bool

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Month Swipe") {
            VStack(alignment: .leading, spacing: 12) {
                BodySettingsCardSection("Workouts Chart") {
                    BodyWorkoutMonthSwipeToggleRow(isEnabled: $isEnabled)
                }

                Text("When on, swiping left or right on the workouts calendar or type breakdown switches to the next or previous month, the same as the month picker. When off, the chart ignores horizontal swipes.")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct BodyWorkoutMonthSwipeToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "arrow.left.arrow.right",
                color: .indigo
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Month Swipe")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Swipe the chart to change month")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Month Swipe", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyReadinessAISettingsSheet: View {
    @Binding var isEnabled: Bool
    let isSupported: Bool

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Readiness") {
            VStack(alignment: .leading, spacing: 12) {
                BodySettingsCardSection("Apple Intelligence") {
                    BodyReadinessAIToggleRow(isEnabled: $isEnabled)
                        // Nothing to generate without an available on-device model.
                        .disabled(!isSupported)
                        .opacity(isSupported ? 1 : 0.4)
                }

                explanation
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var explanation: some View {
        if isSupported {
            Text("When on, Apple Intelligence writes a short comment about what's shaping today's readiness score, including your heart rate, HRV, sleep, and training signals. Everything runs on your device, and your health data never leaves it. When off or unavailable, Body shows its built-in explanation instead.")
        } else {
            Text("Apple Intelligence readiness comments need a supported device with Apple Intelligence turned on in Settings. Body's built-in explanation is shown instead.")
        }
    }
}

private struct BodyReadinessAIToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: BodyAppleIntelligenceGlyph.symbolName,
                color: .indigo
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Readiness Comment")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("Beta v2")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.14), in: Capsule())
                }

                Text("AI comment on today's score")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Readiness Comment", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// Internal (not private) so onboarding can offer the same setting.
struct BodyAutoApplyEffortToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(
                iconName: "wand.and.stars",
                color: .purple
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Auto-Apply Effort")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Save predictions to unrated workouts")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Auto-Apply Effort", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodySummaryCardToggleRow: View {
    let card: BodyHomeCardKind
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: card.iconName, color: card.tintColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(card.title)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let betaVersionLabel = card.betaVersionLabel {
                        Text(betaVersionLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.14), in: Capsule())
                    }
                }

                Text(card.subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(card.title, isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyHomeTrendCardsSettingsSheet: View {
    @Binding var selection: BodyHomeTrendCardSelection

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Trend Cards") {
            VStack(spacing: 0) {
                ForEach(BodyHomeTrendCardKind.defaultOrder) { card in
                    BodyHomeTrendCardToggleRow(
                        card: card,
                        isEnabled: Binding {
                            selection.includes(card)
                        } set: { isEnabled in
                            selection = selection.setting(card, isEnabled: isEnabled)
                        }
                    )

                    if card.id != BodyHomeTrendCardKind.defaultOrder.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .bodyCardBackground(translucent: true)
        }
    }
}

private struct BodyHomeTrendCardToggleRow: View {
    let card: BodyHomeTrendCardKind
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: card.iconName, color: card.tintColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(card.subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(card.title, isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyMetricDayViewSettingsSheet: View {
    @Binding var selection: BodyMetricDayViewSelection

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Day View") {
            VStack(spacing: 0) {
                ForEach(HealthMetricKind.dayViewKinds) { kind in
                    BodyMetricDayViewToggleRow(
                        kind: kind,
                        isEnabled: Binding {
                            selection.includes(kind)
                        } set: { isEnabled in
                            selection = selection.setting(kind, isEnabled: isEnabled)
                        }
                    )

                    if kind.id != HealthMetricKind.dayViewKinds.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .bodyCardBackground(translucent: true)
        }
    }
}

private struct BodyMetricDayViewToggleRow: View {
    let kind: HealthMetricKind
    @Binding var isEnabled: Bool

    private var card: BodyHomeTrendCardKind {
        BodyHomeTrendCardKind(metricKind: kind) ?? .heartRate
    }

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: card.iconName, color: card.tintColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Hour-by-hour chart for a chosen day")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(card.title, isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyMetricWarningsSettingsSheet: View {
    @Binding var selection: BodyMetricWarningSelection
    @Binding var thresholds: BodyMetricWarningThresholds
    @ObservedObject var workoutStore: HealthKitWorkoutStore

    @AppStorage(BodyAppearancePreference.metricWarningNotificationsKey) private var metricWarningNotificationsEnabled = false

    /// Needed for the high heart rate default, which tracks zone 3's lower bound.
    @State private var resolvedMaxHeartRate: Double?

    /// Set when the system denied the notification request, so the row can tell
    /// the user to turn notifications on in Settings.
    @State private var notificationsDenied = false

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Warnings") {
            VStack(alignment: .leading, spacing: 12) {
                BodyMetricWarningNotificationsRow(isEnabled: Binding {
                    metricWarningNotificationsEnabled
                } set: { isEnabled in
                    metricWarningNotificationsEnabled = isEnabled
                    if isEnabled {
                        Task { await enableNotifications() }
                    } else {
                        notificationsDenied = false
                        BodyBackgroundRefreshScheduler.cancelPending()
                    }
                })
                .bodyCardBackground(translucent: true)

                Text("When on, Body periodically checks in the background and sends a notification the first time a warning is detected each day. Checks are scheduled by the system and are not real-time.")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                if notificationsDenied {
                    Text("Notifications are turned off for Body. Enable them in Settings to get warning alerts.")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                ForEach(MetricWarningKind.allCases) { kind in
                    VStack(spacing: 0) {
                        BodyMetricWarningToggleRow(
                            kind: kind,
                            threshold: threshold(for: kind),
                            isEnabled: Binding {
                                selection.includes(kind)
                            } set: { isEnabled in
                                selection = selection.setting(kind, isEnabled: isEnabled)
                            }
                        )

                        Divider()
                            .padding(.leading, 18)

                        BodyMetricWarningThresholdRow(
                            kind: kind,
                            threshold: threshold(for: kind),
                            isDefault: thresholds.override(for: kind) == nil,
                            defaultValue: defaultThreshold(for: kind),
                            isEnabled: selection.includes(kind),
                            onChange: { value in
                                thresholds = thresholds.setting(kind, to: value)
                                workoutStore.metricWarningThresholdsDidChange(for: kind.metric)
                            }
                        )
                    }
                    .bodyCardBackground(translucent: true)
                }

                Text("Warnings appear on the Home card and the metric's detail page.")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .task {
            resolvedMaxHeartRate = await workoutStore.userMaxHeartRate()
            await reflectNotificationAuthorization()
        }
    }

    /// Asks for notification permission; reverts the toggle when it is refused.
    private func enableNotifications() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        if granted {
            notificationsDenied = false
            BodyBackgroundRefreshScheduler.schedule()
        } else {
            metricWarningNotificationsEnabled = false
            notificationsDenied = true
        }
    }

    /// Turns the toggle back off when the user revoked notifications elsewhere.
    private func reflectNotificationAuthorization() async {
        guard metricWarningNotificationsEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied {
            metricWarningNotificationsEnabled = false
            notificationsDenied = true
            BodyBackgroundRefreshScheduler.cancelPending()
        }
    }

    /// The limit currently in effect: the user's override, else the default.
    private func threshold(for kind: MetricWarningKind) -> Int {
        Int(thresholds.threshold(for: kind, maxHeartRate: resolvedMaxHeartRate).rounded())
    }

    private func defaultThreshold(for kind: MetricWarningKind) -> Int {
        Int(BodyMetricWarningThresholds.defaultValue
            .threshold(for: kind, maxHeartRate: resolvedMaxHeartRate)
            .rounded())
    }
}

private struct BodyMetricWarningNotificationsRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: "bell.badge.fill", color: .yellow)

            VStack(alignment: .leading, spacing: 3) {
                Text("Notify Me")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Send a notification when a warning is detected")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Notify Me", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BodyMetricWarningToggleRow: View {
    let kind: MetricWarningKind
    let threshold: Int
    @Binding var isEnabled: Bool

    private var title: LocalizedStringKey {
        switch kind {
        case .lowHeartRate:
            return "Low Heart Rate"
        case .highHeartRate:
            return "High Heart Rate"
        case .lowBloodOxygen:
            return "Low Blood Oxygen"
        }
    }

    private var subtitle: String {
        switch kind {
        case .lowHeartRate:
            return String(localized: "Any reading below \(threshold) bpm today")
        case .highHeartRate:
            return String(localized: "Any reading above \(threshold) bpm today, outside workouts")
        case .lowBloodOxygen:
            return String(localized: "Any reading below \(threshold)% today")
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: "exclamationmark.triangle.fill", color: .yellow)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The custom-limit row under each warning toggle: a value pill that opens a
/// wheel picker, plus a way back to the default.
private struct BodyMetricWarningThresholdRow: View {
    let kind: MetricWarningKind
    let threshold: Int
    let isDefault: Bool
    let defaultValue: Int
    let isEnabled: Bool
    let onChange: (Int?) -> Void

    @State private var showingPicker = false
    @State private var pickedValue = 0

    private var thresholdValues: [Int] {
        Array(stride(
            from: kind.thresholdRange.lowerBound,
            through: kind.thresholdRange.upperBound,
            by: kind.thresholdStep
        ))
    }

    private func valueText(_ value: Int) -> String {
        switch kind {
        case .lowHeartRate, .highHeartRate:
            return String(localized: "\(value) bpm")
        case .lowBloodOxygen:
            return String(localized: "\(value)%")
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("Threshold")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer(minLength: 12)

            Button {
                pickedValue = threshold
                showingPicker = true
            } label: {
                Text(valueText(threshold))
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPicker) {
                picker
                    .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }

    private var picker: some View {
        VStack(spacing: 8) {
            Picker("Threshold", selection: $pickedValue) {
                ForEach(thresholdValues, id: \.self) { value in
                    Text(valueText(value))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(width: 210, height: 172)
            .onChange(of: pickedValue) { _, newValue in
                onChange(newValue)
            }

            Button {
                onChange(nil)
                showingPicker = false
            } label: {
                VStack(spacing: 2) {
                    Text("Use Default")

                    Text(String(localized: "Default: \(valueText(defaultValue))"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .disabled(isDefault)
            .padding(.bottom, 14)
        }
        .frame(width: 210)
    }
}

private struct BodyCustomSourceEditorTarget: Identifiable {
    /// `nil` when the editor is opened to create a new custom source.
    let group: BodyCustomHealthSourceGroup?

    var id: String { group?.id ?? "new" }
}

private struct BodySourceSettingsSheet: View {
    @ObservedObject var workoutStore: HealthKitWorkoutStore
    @State private var updatingSelection: PendingSelection?
    @State private var showBodyProPaywall = false
    @State private var customSourceEditorTarget: BodyCustomSourceEditorTarget?

    // Cached entitlement read (this is a sheet); reactive via the observed `workoutStore`.
    private var isSecondaryLocked: Bool {
        !BodyProEntitlement.isUnlocked
    }

    fileprivate enum Role: String, Equatable {
        case primary
        case secondary
    }

    private struct PendingSelection: Equatable {
        let role: Role
        let optionID: String
    }

    private var customSourceGroups: [BodyCustomHealthSourceGroup] {
        workoutStore.customHealthSourceGroups
    }

    private var canAddCustomSource: Bool {
        customSourceGroups.count < BodyCustomHealthSourceGroupStore.maximumGroupCount
    }

    // While locked, a custom primary resolves to All Sources — show the
    // checkmark there, not on the (still-persisted) paid source.
    private var effectiveDefaultOption: BodyHealthDataSourceOption {
        let option = workoutStore.defaultHealthDataSourceOption
        return isSecondaryLocked && option.isCustomSource ? .allSources : option
    }

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Source") {
            VStack(spacing: 18) {
                BodySettingsCardSection("Options") {
                    combineSourcesToggle
                }

                customSourcesSection

                sourceOptionSection(
                    title: "Primary Data Source",
                    options: workoutStore.healthDataSourceDefaultOptions(),
                    selectedOption: effectiveDefaultOption,
                    role: .primary,
                    tintColor: .cyan
                )

                sourceOptionSection(
                    title: "Secondary Data Source",
                    options: workoutStore.secondaryHealthDataSourceDefaultOptions(),
                    // While locked, the effective secondary is No Comparison — show the
                    // checkmark there, not on the (still-persisted) paid source.
                    selectedOption: isSecondaryLocked ? .noComparison : workoutStore.defaultSecondaryHealthDataSourceOption,
                    role: .secondary,
                    tintColor: .purple
                )
            }
        }
        .sheet(isPresented: $showBodyProPaywall) {
            NavigationStack { BodyProView() }
        }
        .sheet(item: $customSourceEditorTarget) { target in
            BodyCustomSourceEditorSheet(workoutStore: workoutStore, group: target.group)
        }
    }

    private var customSourcesSection: some View {
        BodySettingsCardSection("Custom Sources") {
            ForEach(customSourceGroups) { group in
                customSourceRow(group)

                if group.id != customSourceGroups.last?.id || canAddCustomSource {
                    Divider()
                        .padding(.leading, 76)
                }
            }

            if canAddCustomSource {
                newCustomSourceRow
            }
        }
    }

    private func customSourceRow(_ group: BodyCustomHealthSourceGroup) -> some View {
        Button {
            if isSecondaryLocked {
                showBodyProPaywall = true
            } else {
                customSourceEditorTarget = BodyCustomSourceEditorTarget(group: group)
            }
        } label: {
            HStack(spacing: 14) {
                BodySettingsIconTile(
                    iconName: workoutStore.customHealthSourceIconName(for: group.id),
                    color: .cyan
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("\(group.memberIdentityKeys.count) sources")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 12)

                if isSecondaryLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newCustomSourceRow: some View {
        Button {
            if isSecondaryLocked {
                showBodyProPaywall = true
            } else {
                customSourceEditorTarget = BodyCustomSourceEditorTarget(group: nil)
            }
        } label: {
            HStack(spacing: 14) {
                BodySettingsIconTile(iconName: "plus", color: .cyan)

                Text("New Custom Source")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 12)

                if isSecondaryLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var combineSourcesToggle: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: "rectangle.stack.fill", color: .cyan)

            VStack(alignment: .leading, spacing: 3) {
                Text("Combine Sources with Same Name")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Group duplicate source names into one choice")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Combine Sources with Same Name", isOn: Binding {
                workoutStore.combinesHealthDataSourcesByName
            } set: { combines in
                Task {
                    await workoutStore.updateCombinesHealthDataSourcesByName(combines)
                }
            })
            .labelsHidden()
            .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
            .accessibilityValue(workoutStore.combinesHealthDataSourcesByName ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
    }

    private func sourceOptionSection(
        title: LocalizedStringKey,
        options: [BodyHealthDataSourceOption],
        selectedOption: BodyHealthDataSourceOption,
        role: Role,
        tintColor: Color
    ) -> some View {
        BodySettingsCardSection(title) {
            ForEach(options) { option in
                sourceOptionButton(
                    option,
                    selectedOption: selectedOption,
                    role: role,
                    tintColor: tintColor
                )

                if option.id != options.last?.id {
                    Divider()
                        .padding(.leading, 76)
                }
            }
        }
    }

    private func sourceOptionButton(
        _ option: BodyHealthDataSourceOption,
        selectedOption: BodyHealthDataSourceOption,
        role: Role,
        tintColor: Color
    ) -> some View {
        let isSelected = selectedOption.id == option.id
        let isThisRowUpdating = updatingSelection == PendingSelection(role: role, optionID: option.id)
        // Lock only the rows in the same section while a selection in that
        // section is in flight — the other role's rows stay tappable.
        let isSectionLocked = updatingSelection?.role == role
        let isProLocked = (role == .secondary || option.isCustomSource) && isSecondaryLocked
        return Button {
            updateSelection(option, role: role)
        } label: {
            HStack(spacing: 14) {
                BodySettingsIconTile(iconName: optionIconName(for: option, role: role), color: tintColor)

                Text(option.isNoComparison ? String(localized: "No Comparison") : option.name)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 12)

                if isThisRowUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(tintColor)
                } else if isProLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelected || isSectionLocked)
    }

    private func optionIconName(for option: BodyHealthDataSourceOption, role: Role) -> String {
        if option.isCustomSource {
            return workoutStore.customHealthSourceIconName(for: option.id)
        }

        if option.isNoComparison {
            return "minus.circle.fill"
        }

        let fallback: String
        switch role {
        case .primary:
            fallback = "heart.text.square"
        case .secondary:
            fallback = "square.text.square"
        }

        if option.isAllSources {
            return fallback
        }

        return BodyHealthSourceIcon.systemImageName(
            name: option.name,
            bundleIdentifier: option.iconBundleIdentifierHint,
            fallback: fallback
        )
    }

    private func updateSelection(_ option: BodyHealthDataSourceOption, role: Role) {
        if isSecondaryLocked, role == .secondary || option.isCustomSource {
            showBodyProPaywall = true
            return
        }
        updatingSelection = PendingSelection(role: role, optionID: option.id)
        Task {
            switch role {
            case .primary:
                await workoutStore.updateDefaultHealthDataSource(option: option)
            case .secondary:
                await workoutStore.updateDefaultSecondaryHealthDataSource(option: option)
            }
            updatingSelection = nil
        }
    }
}

private struct BodyHealthPermissionsSettingsSheet: View {
    @ObservedObject var workoutStore: HealthKitWorkoutStore
    /// Sampled when the sheet appears (and again after a toggle settles) rather
    /// than observed, so the footers stay put instead of flickering through
    /// intermediate values while a refresh publishes.
    @State private var accessStates: [BodyHealthPermission: BodyHealthPermissionAccessState] = [:]

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Permissions") {
            VStack(spacing: 0) {
                ForEach(BodyHealthPermission.allCases) { permission in
                    BodyHealthPermissionToggleRow(
                        permission: permission,
                        accessState: accessStates[permission],
                        isEnabled: Binding {
                            workoutStore.permissionSelection.includes(permission)
                        } set: { isEnabled in
                            Task {
                                await workoutStore.updateHealthPermission(permission, isEnabled: isEnabled)
                                accessStates = workoutStore.healthPermissionAccessStates()
                            }
                        }
                    )

                    if permission.id != BodyHealthPermission.allCases.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .bodyCardBackground(translucent: true)
            .onAppear {
                accessStates = workoutStore.healthPermissionAccessStates()
            }

            Text("Each switch controls which Apple Health category Body reads. Turning one on asks Apple Health for access if needed and refreshes the dashboard. Turning one off stops Body from reading that category and removes its data from the app and from the local cache. Body only ever reads, and Apple Health stays in charge: a category that is turned off in the Health app simply shows as empty here, and you can change that under Settings, Health, Data Access and Devices.")
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 12)
        }
    }
}

private struct BodyHealthPermissionToggleRow: View {
    let permission: BodyHealthPermission
    let accessState: BodyHealthPermissionAccessState?
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: permission.iconName, color: permission.tintColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(permission.title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(permission.subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let accessState {
                    Text(accessState.footerText)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(accessState.wantsAttention ? .orange : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Toggle(permission.title, isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(BodyPermissionSwitchToggleStyle(onColor: .green, offColor: .red))
                .accessibilityValue(isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(accessState?.footerText ?? "")
    }
}

private struct BodyHealthSyncStatusSettingsSheet: View {
    @ObservedObject var workoutStore: HealthKitWorkoutStore

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Data Refresh") {
            VStack(spacing: 14) {
                BodySettingsInfoCard(section: syncStatusSection)

                VStack(spacing: 0) {
                    Button {
                        Task {
                            await workoutStore.requestAuthorizationAndRefresh()
                        }
                    } label: {
                        BodySettingsRowLabel(
                            title: "Refresh Now",
                            value: workoutStore.isRefreshing ? String(localized: "Refreshing") : nil,
                            iconName: "arrow.clockwise",
                            tintColor: .blue,
                            accessory: .chevron
                        )
                    }
                    .disabled(workoutStore.isRefreshing)
                    .buttonStyle(.plain)
                    .opacity(workoutStore.isRefreshing ? 0.65 : 1)
                }
                .bodyCardBackground(translucent: true)
            }
        }
    }

    private var syncStatusSection: BodySettingsInfoSection {
        BodySettingsInfoSection(
            title: String(localized: "Status"),
            iconName: "arrow.triangle.2.circlepath",
            tintColor: .blue,
            details: [
                String(localized: "Last refreshed: \(lastSuccessfulRefreshText)"),
                workoutStore.healthDataNotice ?? String(localized: "No health data notice is currently shown.")
            ]
        )
    }

    private var lastSuccessfulRefreshText: String {
        workoutStore.healthSyncStatusLastRefreshText
    }
}

private struct BodyCacheSettingsSheet: View {
    @ObservedObject var workoutStore: HealthKitWorkoutStore

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Cache") {
            VStack(spacing: 14) {
                BodySettingsInfoCard(section: cacheStatusSection)

                VStack(spacing: 0) {
                    Button {
                        Task {
                            await workoutStore.requestAuthorizationAndRefresh()
                        }
                    } label: {
                        BodySettingsRowLabel(
                            title: "Rebuild Cache",
                            value: workoutStore.isRefreshing ? String(localized: "Refreshing") : nil,
                            iconName: "arrow.clockwise.circle.fill",
                            tintColor: .blue,
                            accessory: .chevron
                        )
                    }
                    .disabled(workoutStore.isRefreshing)
                    .buttonStyle(.plain)
                    .opacity(workoutStore.isRefreshing ? 0.65 : 1)

                    Divider()
                        .padding(.leading, 76)

                    Button(role: .destructive) {
                        Task {
                            await workoutStore.clearLocalCache()
                        }
                    } label: {
                        BodySettingsRowLabel(
                            title: "Clear Cache",
                            value: nil,
                            iconName: "trash.fill",
                            tintColor: .red,
                            accessory: .chevron
                        )
                    }
                    .disabled(workoutStore.isRefreshing)
                    .buttonStyle(.plain)
                    .opacity(workoutStore.isRefreshing ? 0.65 : 1)
                }
                .bodyCardBackground(translucent: true)
            }
        }
    }

    private var cacheStatusSection: BodySettingsInfoSection {
        BodySettingsInfoSection(
            title: String(localized: "Local Cache"),
            iconName: "internaldrive.fill",
            tintColor: .orange,
            details: workoutStore.cacheStatus.detailLines
        )
    }
}

private struct BodyPermissionSwitchToggleStyle: ToggleStyle {
    let onColor: Color
    let offColor: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? onColor : offColor)

                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: 52, height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct BodySymbolSelectionTile: View {
    let title: String
    let subtitle: String
    let iconName: String
    let tintColor: Color
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(tintColor)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(tintColor.opacity(0.14))
                    )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tintColor)
                        .background(Circle().fill(Color(.systemBackground)))
                        .offset(x: 6, y: -6)
                }
            }

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)

                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 132)
        .bodyCardBackground(translucent: true)
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: isSelected)
    }
}

struct BodyAppIconOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let descriptor: String
    let alternateIconName: String?
    let previewAssetName: String

    /// `displayName`/`descriptor` stay as English catalog keys; these resolve them
    /// for display so the stored literals remain stable for lookups and tests.
    var localizedDisplayName: String {
        String(localized: String.LocalizationValue(displayName))
    }

    var localizedDescriptor: String {
        String(localized: String.LocalizationValue(descriptor))
    }

    static let standard: [BodyAppIconOption] = [
        BodyAppIconOption(
            id: "body01",
            displayName: "Classic",
            descriptor: "Original",
            alternateIconName: nil,
            previewAssetName: "BodyIcon01"
        ),
        BodyAppIconOption(
            id: "pink",
            displayName: "Rose",
            descriptor: "Pink",
            alternateIconName: "BodyPink",
            previewAssetName: "BodyIconPink"
        ),
        BodyAppIconOption(
            id: "purple",
            displayName: "Violet",
            descriptor: "Purple",
            alternateIconName: "BodyPurple",
            previewAssetName: "BodyIconPurple"
        ),
        BodyAppIconOption(
            id: "black",
            displayName: "Midnight",
            descriptor: "Black",
            alternateIconName: "BodyBlack",
            previewAssetName: "BodyIconBlack"
        ),
        BodyAppIconOption(
            id: "gray",
            displayName: "Neutral",
            descriptor: "Gray",
            alternateIconName: "BodyGray",
            previewAssetName: "BodyIconGray"
        ),
        BodyAppIconOption(
            id: "white",
            displayName: "Light",
            descriptor: "White",
            alternateIconName: "BodyWhite",
            previewAssetName: "BodyIconWhite"
        )
    ]

    static let all: [BodyAppIconOption] = standard

    static func option(named alternateIconName: String?) -> BodyAppIconOption {
        all.first { $0.alternateIconName == alternateIconName } ?? all[0]
    }
}

private enum BodySettingsTypography {
    static let sectionTitleFontSize: CGFloat = 25
}

struct BodySettingsCardSection<Content: View>: View {
    let title: LocalizedStringKey
    private let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: BodySettingsTypography.sectionTitleFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 0) {
                content
            }
            .bodyCardBackground(cornerRadius: 26, translucent: true)
        }
    }
}

private struct BodySettingsRowLabel: View {
    let title: LocalizedStringKey
    let value: String?
    let iconName: String
    let tintColor: Color
    var accessory: BodySettingsRowAccessory = .none

    var body: some View {
        HStack(spacing: 14) {
            BodySettingsIconTile(iconName: iconName, color: tintColor)

            Text(title)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
            }

            accessoryIcon
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var accessoryIcon: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(.caption, weight: .bold))
                .foregroundColor(.secondary.opacity(0.7))
        case .externalLink:
            Image(systemName: "arrow.up.right")
                .font(.system(.caption, weight: .bold))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

private enum BodySettingsRowAccessory {
    case none
    case chevron
    case externalLink
}

struct BodySettingsIconTile: View {
    let iconName: String
    let color: Color

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 21, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.14))
            )
    }
}

private struct BodyAppIconPickerSheet: View {
    let selectedIconName: String?
    let onSelect: (BodyAppIconOption) -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var options: [BodyAppIconOption] {
        BodyAppIconOption.all
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option)
                            } label: {
                                BodyAppIconSelectionTile(
                                    option: option,
                                    isSelected: option.alternateIconName == selectedIconName
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .bodySheetBackground()
            .navigationTitle("App Icon")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BodyAppIconSelectionTile: View {
    let option: BodyAppIconOption
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(option.previewAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.indigo)
                        .background(Circle().fill(Color(.systemBackground)))
                        .offset(x: 6, y: -6)
                }
            }

            VStack(spacing: 3) {
                Text(option.localizedDisplayName)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(option.localizedDescriptor)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 142)
        .bodyCardBackground(translucent: true)
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: isSelected)
    }
}

private struct BodyMoreSettingsSheet: View {
    @Environment(\.openURL) private var openURL

    private let supportEmailAddress = "zihengthedeveloper@gmail.com"

    private let disclaimerSection = BodySettingsInfoSection(
        title: String(localized: "Disclaimer"),
        iconName: "exclamationmark.triangle.fill",
        tintColor: .gray,
        details: [
            String(localized: "Body is for personal health awareness and visualization."),
            String(localized: "Body does not provide medical diagnosis, treatment, fitness prescriptions, or professional health advice."),
            String(localized: "Sleep scores, trends, charts, and summaries are estimates based on available Apple Health data. Talk with a qualified clinician for health concerns or unusual changes.")
        ]
    )

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "More") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    BodySettingsPopupActionRow(
                        title: "Feedback Email",
                        subtitle: supportEmailAddress,
                        iconName: "envelope.fill",
                        tintColor: .gray
                    ) {
                        openSupportEmail()
                    }
                }
                .bodyCardBackground(translucent: true)

                BodySettingsInfoCard(section: disclaimerSection)

                copyrightCard
            }
        }
    }

    private var copyrightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BodySettingsIconTile(iconName: "c.circle.fill", color: .gray)

                Text("Copyright")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Copyright (c) 2026 Ziheng Zhong. All rights reserved.")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Body reads Apple Health data locally to power the app and widgets.")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private func openSupportEmail() {
        guard let url = supportEmailURL else {
            return
        }

        openURL(url)
    }

    private var supportEmailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "Body Support")),
            URLQueryItem(name: "body", value: supportEmailBody)
        ]
        return components.url
    }

    private var supportEmailBody: String {
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? String(localized: "Unknown")
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? String(localized: "Unknown")

        return """


        ---
        App: Body
        Version: \(appVersion) (\(buildNumber))
        Device: \(device.model)
        System: \(device.systemName) \(device.systemVersion)
        Locale: \(Locale.current.identifier)
        Time Zone: \(TimeZone.current.identifier)
        """
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}

private struct BodySettingsAboutSheetScaffold<Content: View>: View {
    let title: LocalizedStringKey
    private let content: Content

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding()
                    .padding(.bottom, 24)
            }
            .bodySheetBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BodySettingsPopupActionRow: View {
    let title: LocalizedStringKey
    let subtitle: String
    let iconName: String
    let tintColor: Color
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 14) {
                BodySettingsIconTile(iconName: iconName, color: tintColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 12)

                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.65)
    }
}

private struct BodySettingsInfoSection: Identifiable {
    let title: String
    let iconName: String
    let tintColor: Color
    let details: [String]

    var id: String {
        title
    }
}

private struct BodySettingsInfoCard: View {
    let section: BodySettingsInfoSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BodySettingsIconTile(iconName: section.iconName, color: section.tintColor)

                Text(section.title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(section.tintColor.opacity(0.72))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)

                        Text(detail)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }
}

#Preview {
    BodySettingsView()
        .environmentObject(HealthKitWorkoutStore())
        .environment(ReadinessCommentGenerator())
}
