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

enum WorkoutCalendarDaySelection {
    static func isSelectable(_ day: WorkoutDaySummary, hasSelectionHandler: Bool) -> Bool {
        hasSelectionHandler && day.workoutCount > 0
    }
}

struct WorkoutCalendarCountMarker: Equatable {
    let symbolName: String

    static func symbolNames(for workoutCount: Int) -> [String] {
        markers(for: workoutCount).map(\.symbolName)
    }

    static func markers(for workoutCount: Int) -> [WorkoutCalendarCountMarker] {
        switch workoutCount {
        case ..<1:
            return []
        case 1:
            return [star]
        case 2:
            return [star, star]
        case 3:
            return [moon]
        case 4:
            return [moon, star]
        case 5:
            return [moon, star, star]
        case 6:
            return [moon, moon]
        case 7:
            return [moon, moon, star]
        case 8:
            return [sun]
        case 9:
            return [sun, star]
        case 10:
            return [sun, star, star]
        case 11:
            return [sun, moon]
        case 12:
            return [sun, moon, star]
        default:
            return [flame]
        }
    }

    var fontSize: CGFloat {
        symbolName == Self.star.symbolName ? 7 : 8
    }

    var opacity: Double {
        symbolName == Self.star.symbolName ? 0.76 : 0.78
    }

    private static let star = WorkoutCalendarCountMarker(symbolName: "star.fill")
    private static let moon = WorkoutCalendarCountMarker(symbolName: "moon.fill")
    private static let sun = WorkoutCalendarCountMarker(symbolName: "sun.max.fill")
    private static let flame = WorkoutCalendarCountMarker(symbolName: "flame.fill")
}

struct WorkoutCalendarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: WorkoutMonthSnapshot
    let style: WorkoutCalendarDisplayStyle
    let fillsAvailableHeight: Bool
    let referenceDate: Date
    let onSelectDay: ((WorkoutDaySummary) -> Void)?

    init(
        snapshot: WorkoutMonthSnapshot,
        style: WorkoutCalendarDisplayStyle = .app,
        fillsAvailableHeight: Bool = true,
        referenceDate: Date = Date(),
        onSelectDay: ((WorkoutDaySummary) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.style = style
        self.fillsAvailableHeight = fillsAvailableHeight
        self.referenceDate = referenceDate
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
                    GeometryReader { proxy in
                        calendarCell(
                            calendarCells[index],
                            glyphScale: glyphScale(forCellSide: min(proxy.size.width, proxy.size.height))
                        )
                    }
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

    private func calendarCell(_ day: WorkoutDaySummary?, glyphScale: CGFloat) -> some View {
        Group {
            if let day {
                calendarCellContent(day, glyphScale: glyphScale)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .onTapGesture {
                        if WorkoutCalendarDaySelection.isSelectable(day, hasSelectionHandler: onSelectDay != nil) {
                            onSelectDay?(day)
                        }
                    }
            } else {
                Color.clear
            }
        }
    }

    private func calendarCellContent(_ day: WorkoutDaySummary, glyphScale: CGFloat) -> some View {
        let markerRowHeight = 9 * glyphScale

        return ZStack {
            cellBackground(for: day)

            VStack(spacing: 3 * glyphScale) {
                if let workoutType = day.primaryWorkoutType {
                    Image(systemName: workoutType.symbolName)
                        .font(.system(size: workoutIconSize * glyphScale, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(workoutType.calendarContentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    workoutMarkers(
                        count: day.workoutCount,
                        color: workoutType.calendarContentColor,
                        glyphScale: glyphScale
                    )
                } else {
                    Text("\(day.day)")
                        .font(.system(size: 22 * glyphScale, weight: .bold, design: .rounded))
                        .foregroundColor(snapshot.isToday(day, reference: referenceDate) ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Color.clear
                        .frame(height: markerRowHeight)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: day))
        .accessibilityHint(WorkoutCalendarDaySelection.isSelectable(day, hasSelectionHandler: onSelectDay != nil) ? "Open workouts for this day" : "")
    }

    private var calendarCells: [WorkoutDaySummary?] {
        Array(repeating: nil, count: snapshot.leadingBlankDayCount) + snapshot.days.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        Calendar.bodyGregorian.bodyRotatedVeryShortWeekdaySymbols()
    }

    @ViewBuilder
    private func cellBackground(for day: WorkoutDaySummary) -> some View {
        if day.workoutCount > 0 {
            BodyGlassChip(
                color: day.primaryWorkoutType?.color ?? Color(red: 0.09, green: 0.56, blue: 0.88),
                cornerRadius: 9,
                showsRim: false
            )
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10))
        }
    }

    @ViewBuilder
    private func workoutMarkers(count: Int, color: Color, glyphScale: CGFloat) -> some View {
        HStack(spacing: 2 * glyphScale) {
            ForEach(Array(WorkoutCalendarCountMarker.markers(for: count).enumerated()), id: \.offset) { _, marker in
                Image(systemName: marker.symbolName)
                    .font(.system(size: marker.fontSize * glyphScale, weight: .bold))
                    .foregroundColor(color.opacity(marker.opacity))
            }
        }
        .frame(height: 9 * glyphScale)
        .offset(y: -2 * glyphScale)
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

    /// Calendar cells are square and grow with the available width (7 per row),
    /// but the glyphs inside them used a fixed point size, so on an iPad's much
    /// larger cells they looked tiny. Scale the in-cell glyphs proportionally to
    /// the cell side, floored at 1× so iPhone and the widgets — whose cells sit
    /// at or below this reference size — render exactly as before and only the
    /// roomier iPad layout scales up.
    private static let referenceCellSide: CGFloat = 50

    private func glyphScale(forCellSide side: CGFloat) -> CGFloat {
        guard side > Self.referenceCellSide else { return 1 }
        return side / Self.referenceCellSide
    }
}
