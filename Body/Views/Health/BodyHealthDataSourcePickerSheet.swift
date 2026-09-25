//
//  BodyHealthDataSourcePickerSheet.swift
//  Body
//

import OSLog
import SwiftUI

struct BodyHealthDataSourcePickerSheet: View {
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "SourcePicker")

    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitWorkoutStore.self) private var workoutStore

    let kind: HealthMetricKind
    let accentColor: Color

    @State private var updatingSelection: PendingSelection?
    @State private var showBodyProPaywall = false
    @State private var fallbackNotice: FallbackNotice?

    // Read through the store rather than the `BodyProEntitlement` static: the static is
    // invisible to observation, while `isProUnlocked` also reads the store's entitlement
    // generation, so a flip re-runs this body and nothing else.
    private var isSecondaryLocked: Bool {
        !workoutStore.isProUnlocked
    }

    private enum SourceRole: Equatable {
        case primary
        case secondary
    }

    private struct PendingSelection: Equatable {
        let role: SourceRole
        let optionID: String
    }

    /// Shown under a section after a tap that was saved but resolved away, so the
    /// checkmark staying put explains itself.
    private struct FallbackNotice: Equatable {
        let role: SourceRole
        let text: String
    }

    private var selectedOption: BodyHealthDataSourceOption {
        workoutStore.selectedHealthDataSourceOption(for: kind)
    }

    private var selectedSecondaryOption: BodyHealthDataSourceOption {
        workoutStore.selectedSecondaryHealthDataSourceOption(for: kind)
    }

    private var options: [BodyHealthDataSourceOption] {
        workoutStore.healthDataSourceOptions(for: kind)
    }

    private var secondaryOptions: [BodyHealthDataSourceOption] {
        workoutStore.secondaryHealthDataSourceOptions(for: kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sourceSection(
                        title: "Primary Source",
                        detail: "Used for the summary value and primary chart bars.",
                        options: options,
                        selectedOption: selectedOption,
                        role: .primary
                    )

                    if kind.supportsSecondaryHealthDataSourceSelection {
                        sourceSection(
                            title: "Secondary Source",
                            detail: "Used for the comparison bars on this chart.",
                            options: secondaryOptions,
                            selectedOption: selectedSecondaryOption,
                            role: .secondary
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .bodySheetBackground()
            .navigationTitle("\(kind.sourcePickerTitle) Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showBodyProPaywall) {
                NavigationStack { BodyProView(showsCloseButton: true) }
            }
        }
    }

    private func sourceSection(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        options: [BodyHealthDataSourceOption],
        selectedOption: BodyHealthDataSourceOption,
        role: SourceRole
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(detail)
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(options) { option in
                    sourceOptionButton(option, selectedOption: selectedOption, role: role)
                }
            }

            if let fallbackNotice, fallbackNotice.role == role {
                Label(fallbackNotice.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func sourceOptionButton(
        _ option: BodyHealthDataSourceOption,
        selectedOption: BodyHealthDataSourceOption,
        role: SourceRole
    ) -> some View {
        let isSelected = selectedOption.id == option.id
        let isThisRowUpdating = updatingSelection == PendingSelection(role: role, optionID: option.id)
        let isSelectionLocked = updatingSelection != nil
        let isProLocked = (role == .secondary || option.isCustomSource) && isSecondaryLocked
        let hasNoData = !isProLocked
            && !workoutStore.healthDataSourceOptionTakesEffect(option, for: kind, secondary: role == .secondary)
        return Button {
            updateSelection(option, role: role)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: rowIconName(for: option, role: role))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 34, height: 34)
                    .background(accentColor.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .opacity(hasNoData ? 0.5 : 1)

                Spacer(minLength: 8)

                if isThisRowUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(accentColor)
                } else if isProLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                } else if hasNoData {
                    Text("No data")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSelected || isSelectionLocked)
    }

    private func rowIconName(for option: BodyHealthDataSourceOption, role: SourceRole) -> String {
        if option.isCustomSource {
            return workoutStore.customHealthSourceIconName(for: option.id)
        }

        if option.isAllSources || option.isNoComparison {
            return optionIconName(for: role)
        }
        return BodyHealthSourceIcon.systemImageName(
            name: option.name,
            bundleIdentifier: option.iconBundleIdentifierHint,
            fallback: optionIconName(for: role)
        )
    }

    private func optionIconName(for role: SourceRole) -> String {
        switch role {
        case .primary:
            return "heart.text.square"
        case .secondary:
            return "square.text.square"
        }
    }

    private func updateSelection(_ option: BodyHealthDataSourceOption, role: SourceRole) {
        if isSecondaryLocked, role == .secondary || option.isCustomSource {
            showBodyProPaywall = true
            return
        }
        updatingSelection = PendingSelection(role: role, optionID: option.id)
        fallbackNotice = nil
        Task {
            switch role {
            case .secondary:
                await workoutStore.updateSecondaryHealthDataSource(for: kind, option: option)
            case .primary:
                await workoutStore.updateHealthDataSource(for: kind, option: option)
            }
            showFallbackNoticeIfNeeded(for: option, role: role)
            updatingSelection = nil
        }
    }

    private func showFallbackNoticeIfNeeded(for option: BodyHealthDataSourceOption, role: SourceRole) {
        let resolved = role == .secondary ? selectedSecondaryOption : selectedOption
        guard resolved.id != option.id else { return }

        let listed = (role == .secondary ? secondaryOptions : options).contains { $0.id == option.id }
        Self.logger.notice(
            "Source tap fell back: kind=\(kind.rawValue, privacy: .public) tapped=\(option.id, privacy: .public) resolved=\(resolved.id, privacy: .public) listed=\(listed, privacy: .public)"
        )

        let text = resolved.isNoComparison
            ? String(localized: "\(option.name) has no \(kind.sourcePickerTitle) data yet, so no comparison is shown.")
            : String(localized: "\(option.name) has no \(kind.sourcePickerTitle) data yet, so \(resolved.name) is still used.")
        fallbackNotice = FallbackNotice(role: role, text: text)
        BodyConfirmationHaptics.play(.warning)
        AccessibilityNotification.Announcement(text).post()
    }
}

