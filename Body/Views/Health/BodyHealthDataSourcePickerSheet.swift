//
//  BodyHealthDataSourcePickerSheet.swift
//  Body
//

import SwiftUI

struct BodyHealthDataSourcePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore

    let kind: HealthMetricKind
    let accentColor: Color

    @State private var updatingSelection: PendingSelection?
    @State private var showBodyProPaywall = false

    // Read the cached entitlement directly (not the environment store) since this is a
    // sheet; it stays reactive because the view observes `workoutStore`, which re-renders
    // on the entitlement-change notification.
    private var isSecondaryLocked: Bool {
        !BodyProEntitlement.isUnlocked
    }

    private enum SourceRole: Equatable {
        case primary
        case secondary
    }

    private struct PendingSelection: Equatable {
        let role: SourceRole
        let optionID: String
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
                NavigationStack { BodyProView() }
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
        let isProLocked = role == .secondary && isSecondaryLocked
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
        if role == .secondary, isSecondaryLocked {
            showBodyProPaywall = true
            return
        }
        updatingSelection = PendingSelection(role: role, optionID: option.id)
        Task {
            switch role {
            case .secondary:
                await workoutStore.updateSecondaryHealthDataSource(for: kind, option: option)
            case .primary:
                await workoutStore.updateHealthDataSource(for: kind, option: option)
            }
            updatingSelection = nil
        }
    }
}

