//
//  BodyWorkoutMonthPicker.swift
//  Body
//

import SwiftUI

/// A compact native wheel of the carousel's reachable months ("2026年 7月" /
/// "July 2026" rows) shown as an anchored popover from the workouts search bar,
/// with a confirm button that jumps the month carousel to the chosen month.
/// A single wheel over the valid list means no clamping is needed — every row
/// is selectable, and labels localize automatically.
struct BodyWorkoutMonthPicker: View {
    let onSelect: (BodyMonthYear) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickedID: String

    private let monthYears: [BodyMonthYear]

    init(
        selectedMonth: Int,
        selectedYear: Int,
        monthsToShow: Int = 36,
        onSelect: @escaping (BodyMonthYear) -> Void
    ) {
        self.onSelect = onSelect

        let list = BodyMonthYearPicker.monthYearList(monthsToShow: monthsToShow)
        self.monthYears = list
        let current = BodyMonthYear(month: selectedMonth, year: selectedYear)
        self._pickedID = State(initialValue: list.contains(current) ? current.id : (list.last?.id ?? current.id))
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Go to Month", selection: $pickedID) {
                ForEach(monthYears) { monthYear in
                    Text(monthYear.displayName).tag(monthYear.id)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 172)

            Button("Go to Month") {
                if let monthYear = monthYears.first(where: { $0.id == pickedID }) {
                    onSelect(monthYear)
                }
                dismiss()
            }
            .buttonStyle(.borderless)
            .padding(.bottom, 14)
        }
        .frame(width: 210)
    }
}
