//
//  BodyWorkoutFilterView.swift
//  Body
//
//  Picks which workout types the Workouts page shows for the month on screen.
//  Lives in its own file (rather than inside `BodyWorkoutsView`) and follows
//  the custom-source editor's glass-card sheet idiom instead of a plain `List`.
//

import SwiftUI

struct BodyWorkoutFilterView: View {
    @Binding var selectedWorkoutTypes: Set<BodyWorkoutType>
    let workoutTypes: [BodyWorkoutType]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tempSelectedWorkoutTypes: Set<BodyWorkoutType>

    init(selectedWorkoutTypes: Binding<Set<BodyWorkoutType>>, workoutTypes: [BodyWorkoutType]) {
        self._selectedWorkoutTypes = selectedWorkoutTypes
        self.workoutTypes = workoutTypes
        self._tempSelectedWorkoutTypes = State(initialValue: selectedWorkoutTypes.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    typesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .bodySheetBackground()
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        selectedWorkoutTypes = tempSelectedWorkoutTypes
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var typesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Workout Types",
                detail: "Select which workout types to display"
            )

            if workoutTypes.isEmpty {
                Text("No workout types for this month")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(workoutTypes) { workoutType in
                        typeRow(workoutType)
                    }
                }

                bulkActions
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

    private func typeRow(_ workoutType: BodyWorkoutType) -> some View {
        let isSelected = tempSelectedWorkoutTypes.contains(workoutType)
        return Button {
            animated {
                tempSelectedWorkoutTypes = BodyWorkoutFilterLogic.toggled(
                    workoutType,
                    in: tempSelectedWorkoutTypes
                )
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workoutType.symbolName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(workoutType.color)
                    .frame(width: 34, height: 34)
                    .background(workoutType.color.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                Text(workoutType.displayName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer(minLength: 8)

                // The unselected state keeps a hollow circle rather than empty
                // space, so the row's tap affordance reads without a selection.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(isSelected ? workoutType.color : Color.secondary.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(workoutType.displayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var bulkActions: some View {
        // Accessibility text sizes overflow two side-by-side pills, so they
        // stack instead of clipping their labels.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                selectAllButton

                deselectAllButton
            }

            VStack(spacing: 12) {
                selectAllButton

                deselectAllButton
            }
        }
    }

    private var selectAllButton: some View {
        // Only the types listed for this month are touched; selections made in
        // another month stay where they are.
        let isDisabled = Set(workoutTypes).isSubset(of: tempSelectedWorkoutTypes)
        return Button {
            animated {
                tempSelectedWorkoutTypes.formUnion(workoutTypes)
            }
        } label: {
            bulkActionLabel("Select All")
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var deselectAllButton: some View {
        let isDisabled = tempSelectedWorkoutTypes.isDisjoint(with: workoutTypes)
        return Button {
            animated {
                tempSelectedWorkoutTypes.subtract(workoutTypes)
            }
        } label: {
            bulkActionLabel("Deselect All")
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private func bulkActionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.accentColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .bodyWorkoutsToolbarCardBackground()
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func animated(_ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(.snappy(duration: 0.25)) {
                changes()
            }
        }
    }
}
