//
//  BodySettingsView.swift
//  Body
//

import SafariServices
import SwiftUI
import UIKit

struct BodySettingsView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(BodyProStore.self) private var proStore: BodyProStore?
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
    @AppStorage(BodyAppearancePreference.summaryCardSelectionKey) private var summaryCardSelectionRawValue = BodySummaryCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.starredMetricKey) private var starredMetricRawValue = BodyHomeCardKind.readiness.rawValue
    @AppStorage(BodyAppearancePreference.homeBackgroundEnabledKey) private var homeBackgroundEnabled = true
    @AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey) private var homeTrendCardSelectionRawValue = BodyHomeTrendCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.metricDayViewSelectionKey) private var metricDayViewSelectionRawValue = BodyMetricDayViewSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.bodyProIconShowsBackKey) private var bodyProIconShowsBack = false
    @State private var activeSheet: BodySettingsSheet?
    @State private var showBodyProPaywall = false
    @State private var selectedAppIconName: String?
    @State private var showingAppIconError = false
    @State private var appIconErrorMessage = ""
    @State private var showingHowToUseBrowser = false
    @State private var showingPrivacyBrowser = false

    private let howToUseURLString = "https://docs.ijustinz.com/body/how-to-use"
    private let privacyPolicyURLString = "https://docs.ijustinz.com/body/privacy"

    var body: some View {
        NavigationStack {
            ZStack {
                BodyAppBackground()
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        appearanceSection
                        metricsSection
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
            .alert("Couldn't Change Icon", isPresented: $showingAppIconError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(appIconErrorMessage)
            }
            .onChange(of: showsSubMinuteAwakeSleepStages) {
                Task {
                    await workoutStore.requestAuthorizationAndRefresh()
                }
            }
            // Re-publish the watch snapshot when a display pref changes so the
            // watch reflects it without waiting for the next refresh.
            .onChange(of: sleepDurationGoalMinutes) { workoutStore.publishWatchSnapshot() }
            .onChange(of: selectedTemperatureUnitRawValue) { workoutStore.publishWatchSnapshot() }
            .onChange(of: followsSystemUnits) { workoutStore.publishWatchSnapshot() }
            .onChange(of: showSleepScore) { workoutStore.publishWatchSnapshot() }
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
            .bodyCardBackground(cornerRadius: 28, translucent: true)
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
                activeSheet = .appIcon
            } label: {
                BodySettingsRowLabel(
                    title: "Icon",
                    value: currentAppIconOption.displayName,
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
                        title: tab.title,
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
            }
        }
    }

    @ViewBuilder
    private func aboutRow(for tab: BodySettingsAboutTab) -> some View {
        Button {
            switch tab {
            case .howToUse:
                showingHowToUseBrowser = true
            case .privacy:
                showingPrivacyBrowser = true
            case .version:
                break
            case .more:
                if let sheet = tab.sheet {
                    activeSheet = sheet
                }
            }
        } label: {
            BodySettingsRowLabel(
                title: tab.title,
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
        case .more:
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

    private var starredMetric: Binding<BodyHomeCardKind?> {
        Binding {
            BodyHomeCardKind.starredMetric(from: starredMetricRawValue)
        } set: { newValue in
            starredMetricRawValue = newValue?.rawValue ?? ""
        }
    }

    private var starredMetricSummaryText: String {
        BodyHomeCardKind.starredMetric(from: starredMetricRawValue)?.title ?? "None"
    }

    private var homeBackgroundSummaryText: String {
        homeBackgroundEnabled ? "On" : "Off"
    }

    private var settingsDivider: some View {
        Divider()
            .padding(.leading, 76)
    }

    private var appVersionDisplay: String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
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
            return "System"
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

    @ViewBuilder
    private func settingsSheet(for sheet: BodySettingsSheet) -> some View {
        switch sheet {
        case .homeBackground:
            BodyHomeBackgroundSheet()
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
        case .sleepDurationGoal:
            BodySleepSettingsSheet(
                goalMinutes: sleepDurationGoal,
                showsSubMinuteAwakeStages: $showsSubMinuteAwakeSleepStages
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
            appIconErrorMessage = "This device does not support alternate app icons."
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

enum BodySettingsSheet: String, Identifiable {
    case homeBackground
    case appIcon
    case sleepDurationGoal
    case summaryCards
    case homeTrendCards
    case starMetric
    case dayView
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
        case .howToUse, .privacy, .version:
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
                // On iOS 26+ the sheet's default Liquid Glass background shows through;
                // older systems keep the opaque grouped background.
                if #unavailable(iOS 26.0) {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }

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
            .navigationTitle("Units")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BodyUnitPreferenceControlRow<Option: BodyUnitPreferenceOption>: View
where Option.AllCases: RandomAccessCollection {
    let title: String
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

            Text(subtitle)
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
                    title: "None",
                    subtitle: "No metric pinned to the top of Home",
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
                    let defaultTitle = profile.id == BodyHomeBackgroundProfile.appDefaultID ? "App Default" : "Saved \(index)"
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
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .bodyCardBackground(translucent: true)
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
        let defaultName = "Saved \(customProfiles.count + 1)"
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
                .accessibilityLabel("Delete \(title)")
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

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .topLeading) {
                BodyActivityRingsCard.heroBackground(colors: colors, separators: separators)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                ForEach(separators.indices, id: \.self) { index in
                    BodyHomeBackgroundSeparatorHandle()
                        .frame(width: 30, height: geo.size.height)
                        .contentShape(Rectangle())
                        .position(x: CGFloat(separators[index]) * width, y: geo.size.height / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("bgPreview"))
                                .onChanged { value in
                                    guard width > 0 else { return }
                                    let raw = Double(value.location.x / width)
                                    let lower = index > 0 ? separators[index - 1] + 0.06 : 0.06
                                    let upper = index < separators.count - 1 ? separators[index + 1] - 0.06 : 0.94
                                    separators[index] = min(max(raw, lower), upper)
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

    private let bubbleSizes: [CGFloat] = [66, 50, 58]

    var body: some View {
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

                ForEach(colors.indices, id: \.self) { index in
                    Circle()
                        .fill(colors[index])
                        .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                        .frame(width: bubbleSize(index), height: bubbleSize(index))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                        .position(position(for: colors[index], center: center, radius: radius))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("colorWheel"))
                                .onChanged { value in
                                    colors[index] = Self.color(at: value.location, center: center, radius: radius)
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

                    Text("Beta v2")
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

                    if card.isBeta {
                        Text("Beta v2")
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

private struct BodySourceSettingsSheet: View {
    @ObservedObject var workoutStore: HealthKitWorkoutStore
    @State private var updatingSelection: PendingSelection?
    @State private var showBodyProPaywall = false

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

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Source") {
            VStack(spacing: 18) {
                BodySettingsCardSection("Options") {
                    combineSourcesToggle
                }

                sourceOptionSection(
                    title: "Primary Data Source",
                    options: workoutStore.healthDataSourceDefaultOptions(),
                    selectedOption: workoutStore.defaultHealthDataSourceOption,
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
        title: String,
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
        let isProLocked = role == .secondary && isSecondaryLocked
        return Button {
            updateSelection(option, role: role)
        } label: {
            HStack(spacing: 14) {
                BodySettingsIconTile(iconName: optionIconName(for: option, role: role), color: tintColor)

                Text(option.name)
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
        if option.isNoComparison {
            return "minus.circle.fill"
        }

        switch role {
        case .primary:
            return "heart.text.square.fill"
        case .secondary:
            return "square.stack.3d.up.fill"
        }
    }

    private func updateSelection(_ option: BodyHealthDataSourceOption, role: Role) {
        if role == .secondary, isSecondaryLocked {
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

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Permissions") {
            VStack(spacing: 0) {
                ForEach(BodyHealthPermission.allCases) { permission in
                    BodyHealthPermissionToggleRow(
                        permission: permission,
                        isEnabled: Binding {
                            workoutStore.permissionSelection.includes(permission)
                        } set: { isEnabled in
                            Task {
                                await workoutStore.updateHealthPermission(permission, isEnabled: isEnabled)
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
        }
    }
}

private struct BodyHealthPermissionToggleRow: View {
    let permission: BodyHealthPermission
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
            }

            Spacer(minLength: 12)

            Toggle(permission.title, isOn: $isEnabled)
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
                            value: workoutStore.isRefreshing ? "Refreshing" : nil,
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
            title: "Status",
            iconName: "arrow.triangle.2.circlepath",
            tintColor: .blue,
            details: [
                "Last refreshed: \(lastSuccessfulRefreshText)",
                workoutStore.healthDataNotice ?? "No health data notice is currently shown."
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
                            value: workoutStore.isRefreshing ? "Refreshing" : nil,
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
                        workoutStore.clearLocalCache()
                    } label: {
                        BodySettingsRowLabel(
                            title: "Clear Cache",
                            value: nil,
                            iconName: "trash.fill",
                            tintColor: .red,
                            accessory: .chevron
                        )
                    }
                    .buttonStyle(.plain)
                }
                .bodyCardBackground(translucent: true)
            }
        }
    }

    private var cacheStatusSection: BodySettingsInfoSection {
        BodySettingsInfoSection(
            title: "Local Cache",
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

private struct BodyAppIconOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let descriptor: String
    let alternateIconName: String?
    let previewAssetName: String

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
    static let sectionTitleFontSize: CGFloat = 29
}

private struct BodySettingsCardSection<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
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
            .bodyCardBackground(translucent: true)
        }
    }
}

private struct BodySettingsRowLabel: View {
    let title: String
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
        .padding(.horizontal, 18)
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

private struct BodySettingsIconTile: View {
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
                // On iOS 26+ the sheet's default Liquid Glass background shows through;
                // older systems keep the opaque grouped background.
                if #unavailable(iOS 26.0) {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }

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
                Text(option.displayName)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(option.descriptor)
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
        title: "Disclaimer",
        iconName: "exclamationmark.triangle.fill",
        tintColor: .gray,
        details: [
            "Body is for personal health awareness and visualization.",
            "Body does not provide medical diagnosis, treatment, fitness prescriptions, or professional health advice.",
            "Sleep scores, trends, charts, and summaries are estimates based on available Apple Health data. Talk with a qualified clinician for health concerns or unusual changes."
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
            URLQueryItem(name: "subject", value: "Body Support"),
            URLQueryItem(name: "body", value: supportEmailBody)
        ]
        return components.url
    }

    private var supportEmailBody: String {
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

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
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // On iOS 26+ the sheet's default Liquid Glass background shows through;
                // older systems keep the opaque grouped background.
                if #unavailable(iOS 26.0) {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }

                ScrollView(.vertical, showsIndicators: false) {
                    content
                        .padding()
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BodySettingsPopupActionRow: View {
    let title: String
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
}
