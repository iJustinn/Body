//
//  BodyCustomSourceEditorSheet.swift
//  Body
//
//  Create or edit a custom source — a named group of discovered Apple Health
//  sources that behaves like a single selectable source everywhere. Lives in
//  its own file (rather than inside `BodySettingsView`) because the membership
//  checklist is substantial enough to stand alone.
//

import SwiftUI

struct BodyCustomSourceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workoutStore: HealthKitWorkoutStore

    /// `nil` when creating a new custom source.
    let group: BodyCustomHealthSourceGroup?

    @State private var name: String
    @State private var selectedIdentityKeys: Set<String>
    @State private var isSaving = false
    @State private var isConfirmingDelete = false

    private let tintColor = Color.cyan

    init(workoutStore: HealthKitWorkoutStore, group: BodyCustomHealthSourceGroup?) {
        _workoutStore = ObservedObject(wrappedValue: workoutStore)
        self.group = group
        _name = State(initialValue: group?.name ?? "")
        // Seeded from the stored membership, not from the discovered list, so
        // members that aren't visible right now (a source that hasn't written
        // data since, another device's app) survive an edit instead of being
        // silently dropped on save.
        _selectedIdentityKeys = State(initialValue: Set(group?.memberIdentityKeys ?? []))
    }

    private var discoveredSources: [BodyDiscoveredHealthSource] {
        workoutStore.discoveredIndividualHealthSources
    }

    private var canSave: Bool {
        !isSaving && selectedIdentityKeys.count >= BodyCustomHealthSourceGroupStore.minimumMemberCount
    }

    private var resolvedName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? String(localized: "Custom Source") : trimmedName
    }

    private var navigationTitle: LocalizedStringKey {
        group == nil ? "New Custom Source" : "Custom Source"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    nameSection

                    sourcesSection

                    if group != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .bodySheetBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Save") {
                            save()
                        }
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
            }
            .alert("Delete \"\(group?.name ?? "")\"?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive, action: deleteGroup)

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This custom source will be removed.")
            }
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Name",
                detail: "Shown wherever this source can be picked."
            )

            TextField("Custom Source", text: $name)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .textInputAutocapitalization(.words)
                .disabled(isSaving)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Select Sources",
                detail: "Pick at least two sources to merge into this one."
            )

            if discoveredSources.isEmpty {
                Text("No sources discovered yet.")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(discoveredSources) { source in
                        sourceRow(source)
                    }
                }
            }
        }
    }

    private func sectionHeader(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
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
    }

    private func sourceRow(_ source: BodyDiscoveredHealthSource) -> some View {
        let isSelected = selectedIdentityKeys.contains(source.identityKey)
        return Button {
            toggleSelection(of: source)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: rowIconName(for: source))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(tintColor)
                    .frame(width: 34, height: 34)
                    .background(tintColor.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(source.name)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(tintColor)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private var deleteButton: some View {
        Button {
            isConfirmingDelete = true
        } label: {
            Text("Delete Custom Source")
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func rowIconName(for source: BodyDiscoveredHealthSource) -> String {
        BodyHealthSourceIcon.systemImageName(
            name: source.name,
            bundleIdentifier: source.bundleIdentifier,
            fallback: "heart.text.square"
        )
    }

    private func toggleSelection(of source: BodyDiscoveredHealthSource) {
        if selectedIdentityKeys.contains(source.identityKey) {
            selectedIdentityKeys.remove(source.identityKey)
        } else {
            selectedIdentityKeys.insert(source.identityKey)
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        let memberIdentityKeys = Array(selectedIdentityKeys)
        let savedName = resolvedName
        Task {
            if let group {
                await workoutStore.updateCustomHealthSourceGroupMembers(
                    id: group.id,
                    memberIdentityKeys: memberIdentityKeys
                )

                if savedName != group.name {
                    await workoutStore.renameCustomHealthSourceGroup(id: group.id, name: savedName)
                }
            } else {
                await workoutStore.addCustomHealthSourceGroup(
                    name: savedName,
                    memberIdentityKeys: memberIdentityKeys
                )
            }
            isSaving = false
            dismiss()
        }
    }

    private func deleteGroup() {
        guard let group else { return }
        isSaving = true
        Task {
            await workoutStore.deleteCustomHealthSourceGroup(id: group.id)
            isSaving = false
            dismiss()
        }
    }
}
