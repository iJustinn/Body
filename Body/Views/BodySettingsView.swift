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
            Button {
                activeSheet = .copyright
            } label: {
                BodySettingsRowLabel(
                    title: "Copyright",
                    value: nil,
                    iconName: "c.circle.fill",
                    tintColor: .purple,
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            BodySettingsRowLabel(
                title: "Version",
                value: appVersionDisplay,
                iconName: "info.circle.fill",
                tintColor: .gray
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
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
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

private enum BodySettingsSheet: String, Identifiable {
    case theme
    case appAccent
    case appIcon
    case units
    case copyright

    var id: String {
        rawValue
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
            id: "body02",
            displayName: "Clean",
            descriptor: "Alternate",
            alternateIconName: "Body02",
            previewAssetName: "BodyIcon02"
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
        }
    }
}

#Preview {
    BodySettingsView()
}
