//
//  BodyMonthYearPicker.swift
//  Body
//

import SwiftUI

struct BodyMonthYear: Identifiable, Equatable {
    var id: String { "\(month)-\(year)" }

    let month: Int
    let year: Int

    var displayName: String {
        guard let date = Calendar.bodyGregorian.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return "\(month) \(year)"
        }

        return BodyDateFormatterCache.formatter(dateFormat: "MMMM yyyy").string(from: date)
    }

    func isFuture(relativeTo date: Date = Date(), calendar: Calendar = .bodyGregorian) -> Bool {
        let currentMonth = calendar.component(.month, from: date)
        let currentYear = calendar.component(.year, from: date)
        return year > currentYear || (year == currentYear && month > currentMonth)
    }
}

struct BodyMonthYearPicker: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int

    private let monthsToShow: Int
    private let allowFutureMonths: Bool
    private let onMonthYearChanged: (() -> Void)?
    private let onMonthYearRequested: ((BodyMonthYear) -> Bool)?

    @State private var monthYearList: [BodyMonthYear]
    @State private var selectedIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isSyncingSelectedIndex = false

    private let pickerHeight: CGFloat = 74

    init(
        selectedMonth: Binding<Int>,
        selectedYear: Binding<Int>,
        monthsToShow: Int = 36,
        allowFutureMonths: Bool = false,
        onMonthYearChanged: (() -> Void)? = nil,
        onMonthYearRequested: ((BodyMonthYear) -> Bool)? = nil
    ) {
        self._selectedMonth = selectedMonth
        self._selectedYear = selectedYear
        self.monthsToShow = monthsToShow
        self.allowFutureMonths = allowFutureMonths
        self.onMonthYearChanged = onMonthYearChanged
        self.onMonthYearRequested = onMonthYearRequested

        let list = Self.monthYearList(monthsToShow: monthsToShow)
        self._monthYearList = State(initialValue: list)
        let initialIndex = list.firstIndex {
            $0.month == selectedMonth.wrappedValue && $0.year == selectedYear.wrappedValue
        } ?? 0
        self._selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let sideSpacing = width * 0.36

            ZStack {
                ForEach(visibleMonthIndices, id: \.self) { index in
                    let itemOffset = CGFloat(index - selectedIndex) * sideSpacing + dragOffset
                    let distanceFromCenter = min(abs(itemOffset / sideSpacing), 1.4)

                    BodyMonthYearCarouselItem(
                        monthYear: monthYearList[index],
                        distanceFromCenter: distanceFromCenter
                    )
                    .frame(width: itemWidth(for: distanceFromCenter, availableWidth: width))
                    .position(x: width / 2 + itemOffset, y: pickerHeight / 2)
                    .zIndex(10 - Double(distanceFromCenter))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3) {
                        guard index == selectedIndex else {
                            return
                        }

                        returnToCurrentMonth()
                    }
                }
            }
            .frame(width: width, height: pickerHeight)
            .clipped()
            .mask(monthCarouselEdgeMask(width: width))
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                monthPreviewTapZone(direction: -1, width: width * 0.34)
            }
            .overlay(alignment: .trailing) {
                monthPreviewTapZone(direction: 1, width: width * 0.34)
            }
            .gesture(monthDragGesture(sideSpacing: sideSpacing))
        }
        .frame(height: pickerHeight)
        .onChange(of: selectedIndex) {
            if isSyncingSelectedIndex {
                isSyncingSelectedIndex = false
                return
            }

            guard monthYearList.indices.contains(selectedIndex) else {
                return
            }

            let monthYear = monthYearList[selectedIndex]
            if !allowFutureMonths && monthYear.isFuture() {
                syncSelectedIndex()
            } else if let onMonthYearRequested {
                let shouldKeepSelection = onMonthYearRequested(monthYear)
                if !shouldKeepSelection {
                    syncSelectedIndex()
                }
            } else {
                selectedMonth = monthYear.month
                selectedYear = monthYear.year
                onMonthYearChanged?()
            }
        }
        .onAppear {
            syncSelectedIndex()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshMonthYearListIfNeeded()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshMonthYearListIfNeeded()
            }
        }
        .onChange(of: selectedMonth) {
            syncSelectedIndex()
        }
        .onChange(of: selectedYear) {
            syncSelectedIndex()
        }
    }

    static func monthYearList(
        monthsToShow: Int,
        relativeTo date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> [BodyMonthYear] {
        let totalMonths = max(monthsToShow, 1)
        let currentMonthComponents = calendar.dateComponents([.year, .month], from: date)

        var list: [BodyMonthYear] = []
        if let currentMonthStart = calendar.date(from: currentMonthComponents) {
            for offset in (0..<totalMonths).reversed() {
                guard let date = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else {
                    continue
                }

                list.append(
                    BodyMonthYear(
                        month: calendar.component(.month, from: date),
                        year: calendar.component(.year, from: date)
                    )
                )
            }
        }

        return list
    }

    private func refreshMonthYearListIfNeeded(relativeTo date: Date = Date()) {
        let updatedList = Self.monthYearList(monthsToShow: monthsToShow, relativeTo: date)
        guard updatedList != monthYearList else {
            return
        }

        monthYearList = updatedList
        syncSelectedIndex(in: updatedList)
    }

    private var visibleMonthIndices: [Int] {
        guard !monthYearList.isEmpty else {
            return []
        }

        let lowerBound = max(monthYearList.startIndex, selectedIndex - 2)
        let upperBound = min(monthYearList.index(before: monthYearList.endIndex), selectedIndex + 2)
        return Array(lowerBound...upperBound)
    }

    private func itemWidth(for distanceFromCenter: CGFloat, availableWidth: CGFloat) -> CGFloat {
        distanceFromCenter < 0.5 ? min(availableWidth * 0.62, 240) : min(availableWidth * 0.28, 120)
    }

    private func syncSelectedIndex() {
        syncSelectedIndex(in: monthYearList)
    }

    private func syncSelectedIndex(in list: [BodyMonthYear]) {
        guard let index = list.firstIndex(where: { $0.month == selectedMonth && $0.year == selectedYear }),
              selectedIndex != index else {
            return
        }

        isSyncingSelectedIndex = true
        selectedIndex = index
    }

    private func monthDragGesture(sideSpacing: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = resistedDragOffset(value.translation.width)
            }
            .onEnded { value in
                let predictedOffset = resistedDragOffset(value.predictedEndTranslation.width)
                let threshold = sideSpacing * 0.35
                var targetIndex = selectedIndex

                if predictedOffset < -threshold {
                    targetIndex = min(selectedIndex + 1, monthYearList.count - 1)
                } else if predictedOffset > threshold {
                    targetIndex = max(selectedIndex - 1, 0)
                }

                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    moveToMonthIndex(targetIndex)
                    dragOffset = 0
                }
            }
    }

    private func resistedDragOffset(_ offset: CGFloat) -> CGFloat {
        if selectedIndex == monthYearList.startIndex && offset > 0 {
            return offset * 0.24
        }

        if selectedIndex == monthYearList.index(before: monthYearList.endIndex) && offset < 0 {
            return offset * 0.24
        }

        return offset
    }

    private func monthPreviewTapZone(direction: Int, width: CGFloat) -> some View {
        ZStack {
            if monthYearList.indices.contains(selectedIndex + direction) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        moveToMonthIndex(selectedIndex + direction)
                        dragOffset = 0
                    }
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(direction < 0 ? "Previous month" : "Next month")
            }
        }
        .frame(width: width, height: pickerHeight)
    }

    /// Fades the carousel's off-center months to transparent at both edges (background-agnostic),
    /// replacing the previous opaque-background gradient so the page background shows through.
    private func monthCarouselEdgeMask(width: CGFloat) -> some View {
        let fade = width * 0.26
        return HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
            Rectangle().fill(Color.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
        }
    }

    private func moveToMonthIndex(_ index: Int) {
        guard monthYearList.indices.contains(index) else {
            return
        }

        selectedIndex = index
    }

    private func returnToCurrentMonth() {
        let calendar = Calendar.bodyGregorian
        let today = Date()
        refreshMonthYearListIfNeeded(relativeTo: today)
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)

        guard let currentMonthIndex = monthYearList.firstIndex(where: { $0.month == currentMonth && $0.year == currentYear }) else {
            return
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            moveToMonthIndex(currentMonthIndex)
            dragOffset = 0
        }
    }
}

private struct BodyMonthYearCarouselItem: View {
    let monthYear: BodyMonthYear
    let distanceFromCenter: CGFloat

    private var monthName: String {
        guard let date = Calendar.bodyGregorian.date(from: DateComponents(year: monthYear.year, month: monthYear.month, day: 1)) else {
            return "\(monthYear.month)"
        }

        return BodyDateFormatterCache.formatter(dateFormat: "MMMM").string(from: date)
    }

    private var clampedDistance: CGFloat {
        min(max(distanceFromCenter, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(monthName)
                .font(.system(size: 34 - (14 * clampedDistance), weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(Double(1 - (0.52 * clampedDistance))))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(height: 44)

            Text(String(monthYear.year))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary.opacity(Double(0.72 - (0.32 * clampedDistance))))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(monthName) \(monthYear.year)")
    }
}
