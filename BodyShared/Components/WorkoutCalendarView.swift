//
//  WorkoutCalendarView.swift
//  Body
//

import SwiftUI

enum WorkoutCalendarDisplayStyle: Equatable {
    case app
    case widgetMedium
    case widgetLarge
}

struct WorkoutCalendarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: WorkoutMonthSnapshot
    let style: WorkoutCalendarDisplayStyle
    let fillsAvailableHeight: Bool
    let onSelectDay: ((WorkoutDaySummary) -> Void)?

    init(
        snapshot: WorkoutMonthSnapshot,
        style: WorkoutCalendarDisplayStyle = .app,
        fillsAvailableHeight: Bool = true,
        onSelectDay: ((WorkoutDaySummary) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.style = style
        self.fillsAvailableHeight = fillsAvailableHeight
        self.onSelectDay = onSelectDay
    }

    var body: some View {
        let columnSpacing: CGFloat = 7
        let rowSpacing: CGFloat = 7
        let weekdayHeight: CGFloat = 18
        let weekdaySpacing: CGFloat = 10
        let columns = Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 7)

        VStack(spacing: weekdaySpacing) {
            weekdayHeader(columnSpacing: columnSpacing, height: weekdayHeight)

            LazyVGrid(columns: columns, spacing: rowSpacing) {
                ForEach(calendarCells.indices, id: \.self) { index in
                    calendarCell(calendarCells[index])
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
    }

    private func weekdayHeader(columnSpacing: CGFloat, height: CGFloat) -> some View {
        let symbols = weekdaySymbols

        return HStack(spacing: columnSpacing) {
            ForEach(symbols.indices, id: \.self) { index in
                Text(symbols[index])
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func calendarCell(_ day: WorkoutDaySummary?) -> some View {
        Group {
            if let day {
                calendarCellContent(day)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .onTapGesture {
                        onSelectDay?(day)
                    }
            } else {
                Color.clear
            }
        }
    }

    private func calendarCellContent(_ day: WorkoutDaySummary) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(cellFill(for: day))

            VStack(spacing: 3) {
                if let workoutType = day.primaryWorkoutType {
                    Image(systemName: workoutType.symbolName)
                        .font(.system(size: workoutIconSize, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(workoutType.calendarContentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("\(day.day)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if day.workoutCount > 0 {
                    workoutMarkers(
                        count: day.workoutCount,
                        color: day.primaryWorkoutType?.calendarContentColor ?? .white
                    )
                } else {
                    Color.clear
                        .frame(height: 9)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: day))
        .accessibilityHint(onSelectDay == nil ? "" : "Open workouts for this day")
    }

    private var calendarCells: [WorkoutDaySummary?] {
        Array(repeating: nil, count: snapshot.leadingBlankDayCount) + snapshot.days.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = DateFormatter().veryShortStandaloneWeekdaySymbols ?? []
        let fallback = ["S", "M", "T", "W", "T", "F", "S"]
        let source = symbols.isEmpty ? fallback : symbols
        let startIndex = max(0, Calendar.bodyGregorian.firstWeekday - 1)
        return Array(source[startIndex...]) + Array(source[..<startIndex])
    }

    private func cellFill(for day: WorkoutDaySummary) -> Color {
        guard day.workoutCount > 0 else {
            return Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10)
        }

        return day.primaryWorkoutType?.color ?? Color(red: 0.09, green: 0.56, blue: 0.88)
    }

    @ViewBuilder
    private func workoutMarkers(count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            if count >= 13 {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color.opacity(0.78))
            } else {
                ForEach(0..<moonCount(for: count), id: \.self) { _ in
                    Image(systemName: "moon.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(color.opacity(0.78))
                }

                ForEach(0..<starCount(for: count), id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(color.opacity(0.76))
                }
            }
        }
        .frame(height: 9)
        .offset(y: -2)
    }

    private func accessibilityLabel(for day: WorkoutDaySummary) -> String {
        let dateText = accessibleDateText(for: day)
        guard day.workoutCount > 0 else {
            return "\(dateText), no workouts"
        }

        let workoutCountText = BodyValueFormat.workoutCountText(day.workoutCount)
        let workoutTypeText = day.primaryWorkoutType?.displayName ?? "workout"
        return "\(dateText), \(workoutCountText), \(workoutTypeText)"
    }

    private func accessibleDateText(for day: WorkoutDaySummary) -> String {
        let components = day.dateKey.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3,
              let date = Calendar.bodyGregorian.date(
                from: DateComponents(year: components[0], month: components[1], day: components[2])
              ) else {
            return "Day \(day.day)"
        }

        return date.formatted(.dateTime.month(.wide).day())
    }

    private func moonCount(for workoutCount: Int) -> Int {
        min(workoutCount / 4, 3)
    }

    private func starCount(for workoutCount: Int) -> Int {
        workoutCount % 4
    }

    private var workoutIconSize: CGFloat {
        switch style {
        case .app:
            return 22
        case .widgetLarge:
            return 18
        case .widgetMedium:
            return 16
        }
    }
}
