//
//  BodySettingsView.swift
//  Body
//

import SwiftUI
import UIKit

struct BodySettingsView: View {
    @AppStorage(BodyAppearancePreference.selectedThemeKey) private var selectedThemeRawValue = BodyAppTheme.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedAccentKey) private var selectedAccentRawValue = BodyAppAccent.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedUnitPreferenceKey) private var selectedUnitPreferenceRawValue = BodyValueFormat.UnitPreference.defaultValue.rawValue
    @State private var activeSheet: BodySettingsSheet?
    @State private var selectedAppIconName: String?
    @State private var showingAppIconError = false
    @State private var appIconErrorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        appearanceSection
                        unitSection
                        aboutSection
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
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
            .alert("Couldn't Change Icon", isPresented: $showingAppIconError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(appIconErrorMessage)
            }
        }
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
                activeSheet = .appAccent
            } label: {
                BodySettingsRowLabel(
                    title: "App Accent",
                    value: currentAccent.displayName,
                    iconName: "paintpalette.fill",
                    tintColor: currentAccent.color,
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
            BodySettingsRowLabel(
                title: tab.title,
                value: appVersionDisplay,
                iconName: tab.iconName,
                tintColor: tab.tintColor
            )
        }
    }

    private var unitSection: some View {
        BodySettingsCardSection("Units") {
            Button {
                activeSheet = .units
            } label: {
                BodySettingsRowLabel(
                    title: "Measurement",
                    value: currentUnitPreference.displayName,
                    iconName: "ruler.fill",
                    tintColor: .teal,
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
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.6"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "7"
        return "\(appVersion) (\(buildNumber))"
    }

    private var currentAppIconOption: BodyAppIconOption {
        BodyAppIconOption.option(named: selectedAppIconName)
    }

    private var currentTheme: BodyAppTheme {
        BodyAppTheme.storedValue(from: selectedThemeRawValue)
    }

    private var currentAccent: BodyAppAccent {
        BodyAppAccent.storedValue(from: selectedAccentRawValue)
    }

    private var currentUnitPreference: BodyValueFormat.UnitPreference {
        BodyValueFormat.UnitPreference.storedValue(from: selectedUnitPreferenceRawValue)
    }

    private var selectedTheme: Binding<BodyAppTheme> {
        Binding {
            currentTheme
        } set: { theme in
            selectedThemeRawValue = theme.rawValue
        }
    }

    private var selectedAccent: Binding<BodyAppAccent> {
        Binding {
            currentAccent
        } set: { accent in
            selectedAccentRawValue = accent.rawValue
        }
    }

    private var selectedUnitPreference: Binding<BodyValueFormat.UnitPreference> {
        Binding {
            currentUnitPreference
        } set: { unitPreference in
            selectedUnitPreferenceRawValue = unitPreference.rawValue
        }
    }

    @ViewBuilder
    private func settingsSheet(for sheet: BodySettingsSheet) -> some View {
        switch sheet {
        case .theme:
            BodyThemePickerSheet(selectedTheme: selectedTheme)
        case .appAccent:
            BodyAccentPickerSheet(selectedAccent: selectedAccent)
        case .appIcon:
            BodyAppIconPickerSheet(
                selectedIconName: selectedAppIconName,
                onSelect: changeAppIcon
            )
        case .units:
            BodyUnitPreferencePickerSheet(selectedUnitPreference: selectedUnitPreference)
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
}

enum BodySettingsSheet: String, Identifiable {
    case theme
    case appAccent
    case appIcon
    case units
    case howToUse
    case feedback
    case privacy
    case disclaimer
    case copyright

    var id: String {
        rawValue
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BodyAccentPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedAccent: BodyAppAccent

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
                        ForEach(BodyAppAccent.allCases) { accent in
                            Button {
                                selectedAccent = accent
                                dismiss()
                            } label: {
                                BodySymbolSelectionTile(
                                    title: accent.displayName,
                                    subtitle: accent.selectionSubtitle,
                                    iconName: accent.iconName,
                                    tintColor: accent.color,
                                    isSelected: selectedAccent == accent
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BodyUnitPreferencePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedUnitPreference: BodyValueFormat.UnitPreference

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
                        ForEach(BodyValueFormat.UnitPreference.allCases) { unitPreference in
                            Button {
                                selectedUnitPreference = unitPreference
                                dismiss()
                            } label: {
                                BodySymbolSelectionTile(
                                    title: unitPreference.displayName,
                                    subtitle: unitPreference.selectionSubtitle,
                                    iconName: iconName(for: unitPreference),
                                    tintColor: tintColor(for: unitPreference),
                                    isSelected: selectedUnitPreference == unitPreference
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func iconName(for unitPreference: BodyValueFormat.UnitPreference) -> String {
        switch unitPreference {
        case .system:
            return "iphone"
        case .metric:
            return "scalemass.fill"
        case .imperial:
            return "ruler.fill"
        }
    }

    private func tintColor(for unitPreference: BodyValueFormat.UnitPreference) -> Color {
        switch unitPreference {
        case .system:
            return .blue
        case .metric:
            return .green
        case .imperial:
            return .orange
        }
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

    static let all: [BodyAppIconOption] = [
        BodyAppIconOption(
            id: "body01",
            displayName: "Classic",
            descriptor: "Original",
            alternateIconName: nil,
            previewAssetName: "BodyIcon01"
        ),
        BodyAppIconOption(
            id: "white",
            displayName: "Light",
            descriptor: "White",
            alternateIconName: "BodyWhite",
            previewAssetName: "BodyIconWhite"
        ),
        BodyAppIconOption(
            id: "pink",
            displayName: "Rose",
            descriptor: "Pink",
            alternateIconName: "BodyPink",
            previewAssetName: "BodyIconPink"
        ),
        BodyAppIconOption(
            id: "classicAlt",
            displayName: "Classic Alt",
            descriptor: "Alternate",
            alternateIconName: "BodyClassicAlt",
            previewAssetName: "BodyIconClassicAlt"
        ),
        BodyAppIconOption(
            id: "lightAlt",
            displayName: "Light Alt",
            descriptor: "Alternate",
            alternateIconName: "BodyWhiteAlt",
            previewAssetName: "BodyIconWhiteAlt"
        ),
        BodyAppIconOption(
            id: "roseAlt",
            displayName: "Rose Alt",
            descriptor: "Alternate",
            alternateIconName: "BodyPinkAlt",
            previewAssetName: "BodyIconPinkAlt"
        )
    ]

    static func option(named alternateIconName: String?) -> BodyAppIconOption {
        all.first { $0.alternateIconName == alternateIconName } ?? all[0]
    }
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
                .font(.system(size: 22, weight: .bold, design: .rounded))
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
    @Environment(\.dismiss) private var dismiss
    let selectedIconName: String?
    let onSelect: (BodyAppIconOption) -> Void

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
                        ForEach(BodyAppIconOption.all) { option in
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
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

private struct BodyHowToUseSettingsSheet: View {
    private let sections: [BodyHowToUseGuideSection] = [
        BodyHowToUseGuideSection(
            title: "Connect Apple Health",
            iconName: "heart.text.square.fill",
            tintColor: .red,
            steps: [
                "Grant read permission when Body asks for Apple Health access.",
                "Use a real device for complete Health data. Some HealthKit data is limited or empty in Simulator.",
                "Pull down on Home to refresh the dashboard after new workouts, sleep, or vitals are recorded."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Read Home",
            iconName: "rectangle.grid.2x2.fill",
            tintColor: .blue,
            steps: [
                "Home shows Activity Rings, Sleep, Basics, resting heart rate, HRV, blood oxygen, respiratory rate, active energy, and resting energy.",
                "Tap a card to open its secondary screen with recent Week and Month trends.",
                "Use Settings to change appearance, app accent, icon, and measurement units."
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
                "Resting Heart Rate, HRV, Respiratory Rate, and Blood Oxygen include a Day View below the Week/Month trend.",
                "Choose a day with the date slider.",
                "The chart averages multiple readings in the same hour; press the chart to reveal the raw readings behind that hourly point."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Workouts",
            iconName: "figure.run",
            tintColor: .orange,
            steps: [
                "Open Workouts to browse, search, sort, and filter your Apple Health workout history.",
                "Tap a workout to view duration, calories, heart rate, distance when available, effort, and source.",
                "Use the month controls to inspect older workout history."
            ]
        ),
        BodyHowToUseGuideSection(
            title: "Charts & Widgets",
            iconName: "square.grid.2x2.fill",
            tintColor: .purple,
            steps: [
                "Charts shows monthly workout calendars and workout-type breakdowns.",
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
                "Body requests read-only access to workouts, Activity Rings, sleep, heart, respiratory, blood oxygen, body measurement, and energy data.",
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Copyright")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Copyright")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BodySettingsAboutSheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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
}
