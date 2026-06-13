//
//  BodySettingsView.swift
//  Body
//

import SwiftUI
import UIKit

struct BodySettingsView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @AppStorage(BodyAppearancePreference.selectedThemeKey) private var selectedThemeRawValue = BodyAppTheme.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedWeightUnitKey) private var selectedWeightUnitRawValue = BodyValueFormat.WeightUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue = BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey) private var sleepDurationGoalMinutes = BodySleepDurationGoal.defaultMinutes
    @AppStorage(BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey) private var showsSubMinuteAwakeSleepStages = BodySleepStageDisplayPreference.defaultShowsSubMinuteAwakeStages
    @AppStorage(BodyAppearancePreference.summaryCardSelectionKey) private var summaryCardSelectionRawValue = BodySummaryCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.defaultTrendRangeKey) private var defaultTrendRangeRawValue = BodyHealthTrendRange.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey) private var homeTrendCardSelectionRawValue = BodyHomeTrendCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.metricDayViewSelectionKey) private var metricDayViewSelectionRawValue = BodyMetricDayViewSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.bodyProIconShowsBackKey) private var bodyProIconShowsBack = false
    @AppStorage(BodyAppearancePreference.creatorSurpriseIconsUnlockedKey) private var creatorSurpriseIconsUnlocked = false
    @State private var activeSheet: BodySettingsSheet?
    @State private var selectedAppIconName: String?
    @State private var showingAppIconError = false
    @State private var appIconErrorMessage = ""
    @State private var versionTapCount = 0
    @State private var showingCreatorSurprise = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
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

                if showingCreatorSurprise {
                    BodyCreatorSurpriseOverlay(
                        onChooseIcons: openCreatorSurpriseIcons,
                        onDismiss: {
                            showingCreatorSurprise = false
                        }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showingCreatorSurprise)
            .onAppear {
                selectedAppIconName = UIApplication.shared.alternateIconName
                versionTapCount = 0
            }
            .sheet(item: $activeSheet) { sheet in
                settingsSheet(for: sheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
            .bodyCardBackground(cornerRadius: 28)
        }
        .buttonStyle(.plain)
    }

    private var appearanceSection: some View {
        BodySettingsCardSection("Appearance") {
            Button {
                activeSheet = .theme
            } label: {
                BodySettingsRowLabel(
                    title: "Theme",
                    value: currentTheme.displayName,
                    iconName: currentTheme.iconName,
                    tintColor: currentTheme.tintColor,
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
                    tintColor: .indigo,
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
        if let sheet = tab.sheet {
            Button {
                activeSheet = sheet
            } label: {
                BodySettingsRowLabel(
                    title: tab.title,
                    value: nil,
                    iconName: tab.iconName,
                    tintColor: tab.tintColor,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                handleVersionCardTap()
            } label: {
                BodySettingsRowLabel(
                    title: tab.title,
                    value: appVersionDisplay,
                    iconName: tab.iconName,
                    tintColor: tab.tintColor
                )
            }
            .buttonStyle(.plain)
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
                    iconName: "ruler.fill",
                    tintColor: .teal,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                activeSheet = .defaultTrendRange
            } label: {
                BodySettingsRowLabel(
                    title: "Charts Range",
                    value: currentDefaultTrendRange.displayName,
                    iconName: currentDefaultTrendRange.iconName,
                    tintColor: currentDefaultTrendRange.tintColor,
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
                    iconName: "rectangle.grid.2x2.fill",
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
                    iconName: "clock.fill",
                    tintColor: .indigo,
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
        }
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

    private var currentTheme: BodyAppTheme {
        BodyAppTheme.storedValue(from: selectedThemeRawValue)
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

    private var currentDefaultTrendRange: BodyHealthTrendRange {
        BodyHealthTrendRange.storedValue(from: defaultTrendRangeRawValue)
    }

    private var currentHomeTrendCardSelection: BodyHomeTrendCardSelection {
        BodyHomeTrendCardSelection.storedValue(from: homeTrendCardSelectionRawValue)
    }

    private var currentMetricDayViewSelection: BodyMetricDayViewSelection {
        BodyMetricDayViewSelection.storedValue(from: metricDayViewSelectionRawValue)
    }

    private var selectedTheme: Binding<BodyAppTheme> {
        Binding {
            currentTheme
        } set: { theme in
            selectedThemeRawValue = theme.rawValue
        }
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

    private var defaultTrendRange: Binding<BodyHealthTrendRange> {
        Binding {
            currentDefaultTrendRange
        } set: { range in
            defaultTrendRangeRawValue = range.rawValue
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
        case .theme:
            BodyThemePickerSheet(selectedTheme: selectedTheme)
        case .appIcon:
            BodyAppIconPickerSheet(
                selectedIconName: selectedAppIconName,
                showsCreatorSurprises: creatorSurpriseIconsUnlocked,
                onSelect: changeAppIcon
            )
        case .summaryCards:
            BodySummaryCardsSettingsSheet(selection: summaryCardSelection)
        case .defaultTrendRange:
            BodyDefaultTrendRangePickerSheet(selectedRange: defaultTrendRange)
        case .homeTrendCards:
            BodyHomeTrendCardsSettingsSheet(selection: homeTrendCardSelection)
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
        case .howToUse:
            BodyHowToUseSettingsSheet()
        case .feedback:
            BodyFeedbackSettingsSheet()
        case .privacy:
            BodyPrivacySettingsSheet()
        case .disclaimer:
            BodyDisclaimerSettingsSheet()
        case .copyright:
            BodyCopyrightSettingsSheet()
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

    private func handleVersionCardTap() {
        versionTapCount += 1
        playSelectionHaptic()

        guard versionTapCount >= 5 else {
            return
        }

        versionTapCount = 0
        creatorSurpriseIconsUnlocked = true
        showingCreatorSurprise = true
        playSuccessHaptic()
    }

    private func openCreatorSurpriseIcons() {
        showingCreatorSurprise = false

        Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            activeSheet = .appIcon
        }
    }

    private func playSelectionHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    private func playSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}

enum BodySettingsSheet: String, Identifiable {
    case theme
    case appIcon
    case sleepDurationGoal
    case summaryCards
    case defaultTrendRange
    case homeTrendCards
    case dayView
    case units
    case source
    case permissions
    case syncStatus
    case cache
    case howToUse
    case feedback
    case privacy
    case disclaimer
    case copyright

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
            return .cyan
        case .permissions:
            return .green
        case .syncStatus:
            return .blue
        case .cache:
            return .orange
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
    case feedback
    case privacy
    case disclaimer
    case copyright
    case version

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .howToUse:
            return "How to Use"
        case .feedback:
            return "Feedback"
        case .privacy:
            return "Privacy"
        case .disclaimer:
            return "Disclaimer"
        case .copyright:
            return "Copyright"
        case .version:
            return "Version"
        }
    }

    var iconName: String {
        switch self {
        case .howToUse:
            return "questionmark.circle.fill"
        case .feedback:
            return "bubble.left.and.bubble.right.fill"
        case .privacy:
            return "hand.raised.fill"
        case .disclaimer:
            return "exclamationmark.triangle.fill"
        case .copyright:
            return "c.circle.fill"
        case .version:
            return "info.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .howToUse:
            return .teal
        case .feedback:
            return .blue
        case .privacy:
            return .green
        case .disclaimer:
            return .yellow
        case .copyright:
            return .purple
        case .version:
            return .gray
        }
    }

    var opensSheet: Bool {
        sheet != nil
    }

    var sheet: BodySettingsSheet? {
        switch self {
        case .howToUse:
            return .howToUse
        case .feedback:
            return .feedback
        case .privacy:
            return .privacy
        case .disclaimer:
            return .disclaimer
        case .copyright:
            return .copyright
        case .version:
            return nil
        }
    }
}

private struct BodyThemePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTheme: BodyAppTheme

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(BodyAppTheme.allCases) { theme in
                            Button {
                                selectedTheme = theme
                                dismiss()
                            } label: {
                                BodySymbolSelectionTile(
                                    title: theme.displayName,
                                    subtitle: theme.selectionSubtitle,
                                    iconName: theme.iconName,
                                    tintColor: theme.tintColor,
                                    isSelected: selectedTheme == theme
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
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
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        BodySettingsCardSection("System") {
                            Toggle("Follow System", isOn: $followsSystemUnits)
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .tint(.teal)
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

private struct BodyDefaultTrendRangePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedRange: BodyHealthTrendRange

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(BodyHealthTrendRange.allCases) { range in
                            Button {
                                selectedRange = range
                                dismiss()
                            } label: {
                                BodySymbolSelectionTile(
                                    title: range.displayName,
                                    subtitle: range.selectionSubtitle,
                                    iconName: range.iconName,
                                    tintColor: range.tintColor,
                                    isSelected: selectedRange == range
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Charts Range")
            .navigationBarTitleDisplayMode(.inline)
        }
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
            .bodyCardBackground()
        }
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
            .bodyCardBackground()
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
            .bodyCardBackground()
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
                    selectedOption: workoutStore.defaultSecondaryHealthDataSourceOption,
                    role: .secondary,
                    tintColor: .purple
                )
            }
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
            .bodyCardBackground()
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
                .bodyCardBackground()
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
                .bodyCardBackground()
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
        .bodyCardBackground()
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
    var isCreatorSurprise = false

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

    static let creatorSurprises: [BodyAppIconOption] = [
        BodyAppIconOption(
            id: "classicPresent",
            displayName: "Classic",
            descriptor: "Present",
            alternateIconName: "BodyClassicAlt",
            previewAssetName: "BodyIconClassicAlt",
            isCreatorSurprise: true
        ),
        BodyAppIconOption(
            id: "rosePresent",
            displayName: "Rose",
            descriptor: "Present",
            alternateIconName: "BodyPinkAlt",
            previewAssetName: "BodyIconPinkAlt",
            isCreatorSurprise: true
        ),
        BodyAppIconOption(
            id: "violetPresent",
            displayName: "Violet",
            descriptor: "Present",
            alternateIconName: "BodyPurpleAlt",
            previewAssetName: "BodyIconPurpleAlt",
            isCreatorSurprise: true
        ),
        BodyAppIconOption(
            id: "midnightPresent",
            displayName: "Midnight",
            descriptor: "Present",
            alternateIconName: "BodyBlackAlt",
            previewAssetName: "BodyIconBlackAlt",
            isCreatorSurprise: true
        ),
        BodyAppIconOption(
            id: "neutralPresent",
            displayName: "Neutral",
            descriptor: "Present",
            alternateIconName: "BodyGrayAlt",
            previewAssetName: "BodyIconGrayAlt",
            isCreatorSurprise: true
        ),
        BodyAppIconOption(
            id: "lightPresent",
            displayName: "Light",
            descriptor: "Present",
            alternateIconName: "BodyWhiteAlt",
            previewAssetName: "BodyIconWhiteAlt",
            isCreatorSurprise: true
        )
    ]

    static let all: [BodyAppIconOption] = standard + creatorSurprises

    static func availableOptions(includeCreatorSurprises: Bool) -> [BodyAppIconOption] {
        includeCreatorSurprises ? all : standard
    }

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
            .bodyCardBackground()
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
        }
    }
}

private enum BodySettingsRowAccessory {
    case none
    case chevron
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
    let showsCreatorSurprises: Bool
    let onSelect: (BodyAppIconOption) -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var options: [BodyAppIconOption] {
        let availableOptions = BodyAppIconOption.availableOptions(includeCreatorSurprises: showsCreatorSurprises)

        guard let selectedOption = BodyAppIconOption.all.first(where: { $0.alternateIconName == selectedIconName }),
              !availableOptions.contains(selectedOption) else {
            return availableOptions
        }

        return availableOptions + [selectedOption]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

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
        .bodyCardBackground()
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: isSelected)
    }
}

private struct BodyCreatorSurpriseOverlay: View {
    let onChooseIcons: () -> Void
    let onDismiss: () -> Void

    @State private var ribbonsAreFalling = false

    private let ribbons = BodyCreatorRibbon.all

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                ForEach(ribbons) { ribbon in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ribbon.color)
                        .frame(width: ribbon.width, height: ribbon.height)
                        .rotationEffect(.degrees(ribbonsAreFalling ? ribbon.endRotation : ribbon.startRotation))
                        .offset(
                            x: ribbon.xOffset(in: proxy.size.width),
                            y: ribbonsAreFalling
                                ? proxy.size.height + ribbon.endYOffset
                                : -proxy.size.height * 0.45 - ribbon.startYOffset
                        )
                        .opacity(ribbonsAreFalling ? 0.95 : 0)
                        .animation(
                            .linear(duration: ribbon.duration)
                                .delay(ribbon.delay)
                                .repeatForever(autoreverses: false),
                            value: ribbonsAreFalling
                        )
                }

                VStack(spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.yellow)
                        .frame(width: 76, height: 76)
                        .background(
                            Circle()
                                .fill(Color.yellow.opacity(0.18))
                        )

                    VStack(spacing: 8) {
                        Text("Surprise Unlocked")
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("You unlocked a surprise from the creator.")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("Six Present app icons are now available.")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        Button {
                            onDismiss()
                        } label: {
                            Text("Later")
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onChooseIcons()
                        } label: {
                            Text("Choose Icons")
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(Color(.systemBackground))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.accentColor)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .frame(maxWidth: 360)
                .bodyCardBackground()
                .padding(.horizontal, 24)
            }
            .onAppear {
                ribbonsAreFalling = true
            }
        }
    }
}

private struct BodyCreatorRibbon: Identifiable {
    let id: Int
    let xFraction: CGFloat
    let width: CGFloat
    let height: CGFloat
    let startRotation: Double
    let endRotation: Double
    let startYOffset: CGFloat
    let endYOffset: CGFloat
    let delay: Double
    let duration: Double
    let color: Color

    func xOffset(in width: CGFloat) -> CGFloat {
        (xFraction - 0.5) * width
    }

    static let all: [BodyCreatorRibbon] = {
        let palette: [Color] = [.pink, .yellow, .blue, .green, .purple, .orange, .cyan, .mint, .red, .indigo]
        let columns: [CGFloat] = [0.04, 0.09, 0.14, 0.19, 0.24, 0.29, 0.34, 0.39, 0.44, 0.49, 0.54, 0.59, 0.64, 0.69, 0.74, 0.79, 0.84, 0.89, 0.94]

        return (0..<48).map { index in
            let column = columns[index % columns.count]
            let jitter = CGFloat(((index * 37) % 9) - 4) / 100
            let xFraction = min(max(column + jitter, 0.03), 0.97)

            return BodyCreatorRibbon(
                id: index,
                xFraction: xFraction,
                width: CGFloat(6 + (index * 5) % 8),
                height: CGFloat(28 + (index * 11) % 34),
                startRotation: Double(((index * 23) % 90) - 45),
                endRotation: Double(((index * 61) % 560) - 280),
                startYOffset: CGFloat((index * 29) % 220),
                endYOffset: CGFloat((index * 43) % 260),
                delay: Double(index % 16) * 0.09,
                duration: 2.4 + Double((index * 7) % 12) * 0.11,
                color: palette[index % palette.count]
            )
        }
    }()
}

private struct BodyHowToUseSettingsSheet: View {
    private let sections: [BodyHowToUseGuideSection] = [
        BodyHowToUseGuideSection(
            title: "Connect Apple Health",
            iconName: "heart.text.square.fill",
            tintColor: .red,
            steps: [
                "Grant read permission when Body asks for Apple Health access. Use a real device for complete Health data.",
                "Open Data > Source to set default primary and secondary Apple Health sources or combine duplicate source names.",
                "Open Data > Permissions to choose which Apple Health categories Body uses inside the app.",
                "Open Data > Data Refresh to see the last refresh time or run Refresh Now."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Read Summary",
            iconName: "rectangle.grid.2x2.fill",
            tintColor: .blue,
            steps: [
                "Summary shows Activity Rings, Sleep, Basics, Training Load, heart, respiratory, energy, daylight, steps, and body metric cards.",
                "Tap a card to open details with trend ranges, day views when available, and metric-specific context.",
                "Pull down on Summary after new Health data is recorded to refresh the dashboard. A Loading data overlay stays on screen until the refresh finishes so you know work is in progress."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Customize Metrics",
            iconName: "slider.horizontal.3",
            tintColor: .teal,
            steps: [
                "Use Metrics > Units to follow the system or choose weight, distance, energy, and temperature units manually.",
                "Use Metrics > Summary Cards, Charts Range, and Trend Cards to decide what appears on Summary and which default range charts open with.",
                "Use Appearance to change theme and icon separately from metric behavior."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Sleep Details",
            iconName: "bed.double.fill",
            tintColor: Color(red: 0.20, green: 0.72, blue: 1.00),
            steps: [
                "Use the Sleep date slider to choose the day you want to inspect.",
                "Tap the Sleep Score card to see the score breakdown.",
                "Press the Sleep Stages chart to inspect a stage segment's duration and start/end time."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Day Views",
            iconName: "chart.xyaxis.line",
            tintColor: .indigo,
            steps: [
                "Heart Rate, Resting Heart Rate, HRV, Respiratory Rate, and Blood Oxygen include a Day View below the range trend.",
                "Choose a day with the date slider.",
                "Heart Rate also overlays sleep and workout windows; press the chart to reveal the raw readings behind each hourly point.",
                "The legend shows just the average when a single source is active and switches to a per-source breakdown when a secondary source is selected."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Compare Two Sources",
            iconName: "rectangle.split.2x1.fill",
            tintColor: .pink,
            steps: [
                "Open a supported metric detail (Sleep, Heart Rate, Resting Heart Rate, HRV, Blood Oxygen, Steps, Active Energy, Resting Energy, Exercise Minutes).",
                "Use Data > Source for app-wide primary and secondary defaults, or tap the source picker on a metric detail to override that metric.",
                "Primary and secondary share the same x-axis buckets so bars and lines line up. The legend lists each source with its average across the selected range.",
                "Changing the secondary source triggers a focused refresh of that metric; the Loading data overlay stays until the new comparison data is ready."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Workouts",
            iconName: "figure.run",
            tintColor: .orange,
            steps: [
                "Open Workouts to browse, search, sort, and filter your Apple Health workout history.",
                "Tap a workout to view duration, calories, heart rate, distance when available, effort, and source.",
                "Use the month controls to inspect older workout history.",
                "Pull down to refresh the selected month; the Loading data overlay stays until the refresh finishes."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Manage Cache",
            iconName: "internaldrive.fill",
            tintColor: .purple,
            steps: [
                "Use Data > Cache to review cached dashboard, workout, and Activity Ring data.",
                "Clear Cache removes local snapshots; Rebuild Cache refreshes Apple Health and rebuilds the local files.",
                "Workout widgets read Body's shared cached snapshot, so open the app and refresh when widget data looks stale.",
                "Widget backgrounds can use System, Black, or White styling."
            ]
        )
    ]

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "How to Use") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    BodyHowToUseGuideCard(section: section)
                }
            }
        }
    }
}

private struct BodyFeedbackSettingsSheet: View {
    @Environment(\.openURL) private var openURL

    private let supportEmailAddress = "zihengthedeveloper@gmail.com"

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Feedback") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    BodySettingsPopupActionRow(
                        title: "Email",
                        subtitle: supportEmailAddress,
                        iconName: "envelope.fill",
                        tintColor: .blue
                    ) {
                        openSupportEmail()
                    }
                }
                .bodyCardBackground()

                VStack(spacing: 0) {
                    BodySettingsPopupActionRow(
                        title: "Follow on IG",
                        subtitle: "Coming soon",
                        iconName: "camera.fill",
                        tintColor: .pink,
                        isEnabled: false
                    ) { }
                }
                .bodyCardBackground()

                VStack(spacing: 0) {
                    BodySettingsPopupActionRow(
                        title: "Follow on Red",
                        subtitle: "Coming soon",
                        iconName: "heart.fill",
                        tintColor: .red,
                        isEnabled: false
                    ) { }
                }
                .bodyCardBackground()
            }
        }
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

private struct BodyPrivacySettingsSheet: View {
    private let sections: [BodySettingsInfoSection] = [
        BodySettingsInfoSection(
            title: "Apple Health Access",
            iconName: "heart.text.square.fill",
            tintColor: .red,
            details: [
                "Body requests read-only access to workouts, Activity Rings, exercise, steps, daylight, sleep, heart, respiratory, blood oxygen, body measurement, and energy data.",
                "Body does not write health samples back to Apple Health."
            ]
        ),
        BodySettingsInfoSection(
            title: "Local-First Data",
            iconName: "iphone",
            tintColor: .green,
            details: [
                "Health summaries, workout snapshots, widget snapshots, appearance choices, unit preferences, and app icon choices stay on this device.",
                "Widgets read a cached snapshot from the shared app group. Widgets do not query HealthKit directly."
            ]
        ),
        BodySettingsInfoSection(
            title: "Network Access",
            iconName: "network",
            tintColor: .blue,
            details: [
                "Body does not send Apple Health data to external analytics, advertising, tracking, or AI services.",
                "Feedback email is optional. If you choose Feedback, your email app prepares a message with app version, device, system, locale, and time zone details so you can review it before sending."
            ]
        ),
        BodySettingsInfoSection(
            title: "Your Control",
            iconName: "hand.raised.fill",
            tintColor: .orange,
            details: [
                "You can change Body's Health permissions in the Health app or iOS Settings.",
                "Deleting Body removes the app's local cache and settings from the device."
            ]
        ),
        BodySettingsInfoSection(
            title: "App Store Privacy",
            iconName: "doc.text.fill",
            tintColor: .gray,
            details: [
                "A public Privacy Policy URL is required for App Store distribution.",
                "The App Store privacy details should match this app behavior and any future services added to Body."
            ]
        )
    ]

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Privacy") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    BodySettingsInfoCard(section: section)
                }
            }
        }
    }
}

private struct BodyDisclaimerSettingsSheet: View {
    private let section = BodySettingsInfoSection(
        title: "Disclaimer",
        iconName: "exclamationmark.triangle.fill",
        tintColor: .yellow,
        details: [
            "Body is for personal health awareness and visualization.",
            "Body does not provide medical diagnosis, treatment, fitness prescriptions, or professional health advice.",
            "Sleep scores, trends, charts, and summaries are estimates based on available Apple Health data. Talk with a qualified clinician for health concerns or unusual changes."
        ]
    )

    var body: some View {
        BodySettingsAboutSheetScaffold(title: "Disclaimer") {
            BodySettingsInfoCard(section: section)
        }
    }
}

private struct BodyCopyrightSettingsSheet: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Copyright")
                                .font(.system(size: BodySettingsTypography.sectionTitleFontSize, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            Text("Copyright (c) 2026 Ziheng Zhong. All rights reserved.")
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Body reads Apple Health data locally to power the app and widgets.")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .bodyCardBackground()
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Copyright")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
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
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

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
            BodySettingsRowLabel(
                title: title,
                value: subtitle,
                iconName: iconName,
                tintColor: tintColor,
                accessory: isEnabled ? .chevron : .none
            )
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.65)
    }
}

private struct BodyHowToUseGuideSection: Identifiable {
    let title: String
    let iconName: String
    let tintColor: Color
    let steps: [String]

    var id: String {
        title
    }
}

private struct BodyHowToUseGuideCard: View {
    let section: BodyHowToUseGuideSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                BodySettingsIconTile(iconName: section.iconName, color: section.tintColor)

                Text(section.title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(section.tintColor)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(section.tintColor.opacity(0.14)))

                        Text(step)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
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
        .bodyCardBackground()
    }
}

#Preview {
    BodySettingsView()
        .environmentObject(HealthKitWorkoutStore())
}
