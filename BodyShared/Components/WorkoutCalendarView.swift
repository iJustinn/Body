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

/// One slot in the month grid. `day` carries an index into `snapshot.days`
/// rather than the summary itself, so the layout can be computed — and tested —
/// from nothing but two counts.
enum WorkoutCalendarCellKind: Equatable {
    case blank
    case day(index: Int)
    case switchControl
}

struct WorkoutCalendarView: View {
    let snapshot: WorkoutMonthSnapshot
    /// Resolved workout colors (built-in defaults plus any Pro customization). Rendered
    /// in both the app and the widget extension, so this is an explicit stored property
    /// rather than an `@Environment` read — the widget's timeline entry supplies its own
    /// entry-derived palette, which the environment can't carry across the process.
    let palette: BodyWorkoutColorPalette
    let style: WorkoutCalendarDisplayStyle
    let fillsAvailableHeight: Bool
    /// Shrinks the icons, markers, and numbers along with cells smaller than the
    /// reference side instead of letting them overflow. Off for the app and widgets,
    /// whose cells never drop that far.
    let scalesGlyphsToFit: Bool
    /// The row of weekday letters above the grid. Always on in the app and widgets;
    /// the share card lets the user drop it.
    let showsWeekdayHeader: Bool
    let referenceDate: Date
    let onSelectDay: ((WorkoutDaySummary) -> Void)?
    /// Nil in the widgets, which have no second chart to switch to — and which
    /// therefore lay out exactly as they did before this control existed.
    let onSwitchChart: (() -> Void)?

    init(
        snapshot: WorkoutMonthSnapshot,
        palette: BodyWorkoutColorPalette,
        style: WorkoutCalendarDisplayStyle = .app,
        fillsAvailableHeight: Bool = true,
        scalesGlyphsToFit: Bool = false,
        showsWeekdayHeader: Bool = true,
        referenceDate: Date = Date(),
        onSelectDay: ((WorkoutDaySummary) -> Void)? = nil,
        onSwitchChart: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.palette = palette
        self.style = style
        self.fillsAvailableHeight = fillsAvailableHeight
        self.scalesGlyphsToFit = scalesGlyphsToFit
        self.showsWeekdayHeader = showsWeekdayHeader
        self.referenceDate = referenceDate
        self.onSelectDay = onSelectDay
        self.onSwitchChart = onSwitchChart
    }

    var body: some View {
        let columnSpacing: CGFloat = 7
        let rowSpacing: CGFloat = 7
        let weekdayHeight: CGFloat = 18
        let weekdaySpacing: CGFloat = 10
        let columns = Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 7)

        VStack(spacing: weekdaySpacing) {
            if showsWeekdayHeader {
                weekdayHeader(columnSpacing: columnSpacing, height: weekdayHeight)
            }

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

    @ViewBuilder
    private func calendarCell(_ kind: WorkoutCalendarCellKind, glyphScale: CGFloat) -> some View {
        switch kind {
        case .blank:
            Color.clear
        case let .day(index):
            let day = snapshot.days[index]
            calendarCellContent(day, glyphScale: glyphScale)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onTapGesture {
                    if WorkoutCalendarDaySelection.isSelectable(day, hasSelectionHandler: onSelectDay != nil) {
                        onSelectDay?(day)
                    }
                }
        case .switchControl:
            switchControlCell(glyphScale: glyphScale)
        }
    }

    /// Reads as an empty day cell wearing a chart glyph, because it is one —
    /// it occupies a real grid slot, so it can never overlap a date.
    private func switchControlCell(glyphScale: CGFloat) -> some View {
        Button {
            onSwitchChart?()
        } label: {
            ZStack {
                // The workout cards' own fill — `bodyCardBackground(translucent:)`
                // is `Color.primary.opacity(0.06)` — under the rim the day cells
                // pass up, so the control reads as a control rather than as one
                // more date.
                BodyGlassChip(color: .primary, cornerRadius: 9, fillOpacity: 0.06)

                Image(systemName: "chart.bar.yaxis")
                    .font(.system(size: workoutIconSize * glyphScale, weight: .bold))
                    // The day numbers' own grey, so the control sits at the
                    // same weight as the dates it shares the grid with.
                    .foregroundColor(.secondary)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Show activity breakdown", table: "BodyShared"))
        .accessibilityHint(String(localized: "Switches between the workout calendar and the activity breakdown", table: "BodyShared"))
        // Otherwise VoiceOver reaches it only after all 28-31 day cells.
        .accessibilitySortPriority(1)
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
                        .foregroundColor(palette.contentColor(for: workoutType))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    workoutMarkers(
                        count: day.workoutCount,
                        color: palette.contentColor(for: workoutType),
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
        .accessibilityHint(WorkoutCalendarDaySelection.isSelectable(day, hasSelectionHandler: onSelectDay != nil) ? String(localized: "Open workouts for this day", table: "BodyShared") : "")
    }

    private var calendarCells: [WorkoutCalendarCellKind] {
        Self.cellLayout(
            leadingBlankDayCount: snapshot.leadingBlankDayCount,
            dayCount: snapshot.days.count,
            includesSwitchControl: onSwitchChart != nil
        )
    }

    static func cellLayout(
        leadingBlankDayCount: Int,
        dayCount: Int,
        includesSwitchControl: Bool
    ) -> [WorkoutCalendarCellKind] {
        var cells = Array(repeating: WorkoutCalendarCellKind.blank, count: leadingBlankDayCount)
        cells.append(contentsOf: (0..<dayCount).map { .day(index: $0) })

        guard includesSwitchControl else { return cells }

        // With `cells.count == 7k + r`, padding by `6 - r` lands the control at
        // `7k + 6` — the last column, for every month. When `r == 0` those six
        // blanks are a whole new row, which is exactly the "the calendar fills
        // its final row" case where the control has nowhere else to go.
        cells.append(contentsOf: Array(repeating: .blank, count: 6 - (cells.count % 7)))
        cells.append(.switchControl)
        return cells
    }

    private var weekdaySymbols: [String] {
        Calendar.bodyGregorian.bodyRotatedVeryShortWeekdaySymbols()
    }

    @ViewBuilder
    private func cellBackground(for day: WorkoutDaySummary) -> some View {
        if day.workoutCount > 0 {
            BodyGlassChip(
                color: day.primaryWorkoutType.map { palette.color(for: $0) } ?? Color(red: 0.09, green: 0.56, blue: 0.88),
                cornerRadius: 9,
                showsRim: false
            )
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.1))
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
            return String(localized: "\(dateText), no workouts", table: "BodyShared")
        }

        let workoutCountText = BodyValueFormat.workoutCountText(day.workoutCount)
        let workoutTypeText = day.primaryWorkoutType?.displayName ?? String(localized: "workout", table: "BodyShared")
        return String(
            localized: "calendar.day.workouts.summary",
            defaultValue: "\(dateText), \(workoutCountText), \(workoutTypeText)",
            table: "BodyShared"
        )
    }

    private func accessibleDateText(for day: WorkoutDaySummary) -> String {
        let components = day.dateKey.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3,
              let date = Calendar.bodyGregorian.date(
                from: DateComponents(year: components[0], month: components[1], day: components[2])
              ) else {
            return String(localized: "Day \(day.day)", table: "BodyShared")
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
        // Below the reference the glyphs hold their size, so a narrow cell overflows
        // into a pill — only the share card, whose grid can be 30-odd points a cell,
        // asks for them to shrink with it.
        guard side > Self.referenceCellSide || scalesGlyphsToFit else { return 1 }
        return side / Self.referenceCellSide
    }
}
