//
//  StressDayNightCard.swift
//  Body
//

import SwiftUI

/// The selected day's Stress split at the sleep line, for the Stress page's Day and
/// Night card. Day is every window that is not sleep: last night's main session, the
/// day's naps and tonight's main session are all sleep. Night is the main session that
/// ended that morning, whole, so its minutes before midnight come from the day before's
/// windows. A nap leaves Day without joining Night, which reads the night's own span.
struct StressDayNightSplit: Equatable {
    /// The highest scored window, the earliest one on a tie.
    struct Peak: Equatable {
        var score: Int
        var start: Date
    }

    /// One side's windows rolled up the way `StressScoreCalculator.daySummary` rolls
    /// up a day.
    struct Period: Equatable {
        /// What the side covers: wake to bedtime (or now) for Day, the night's own
        /// span for Night.
        var interval: DateInterval
        var minutesByBand: [StressBand: Int] = [:]
        var activityMinutes = 0
        var scoredWindowCount = 0
        var averageScore: Int?
        var peak: Peak?
        /// Scored minutes above Peace, the restless time when the side is the night.
        var restlessMinutes = 0
        /// Where the restless minutes start, only while they are one unbroken
        /// stretch: a gap, movement or a calm window between two ends a stretch.
        var restlessStart: Date?

        var totalScoredMinutes: Int {
            StressBand.displayOrder.reduce(0) { $0 + minutesByBand[$1, default: 0] }
        }

        /// Percent of the scored minutes in Peace, nil with nothing scored.
        var peaceShare: Int? {
            let total = totalScoredMinutes
            guard total > 0 else {
                return nil
            }

            return Int((Double(minutesByBand[.rest, default: 0]) / Double(total) * 100).rounded())
        }
    }

    /// How the Day side's span reads: a bare "12:00 AM to 12:00 AM" says nothing.
    enum DaySpan: Equatable {
        /// Today, from wake (or midnight) on.
        case toNow(start: Date)
        /// A past day with no sleep in it.
        case allDay
        /// A past day whose bedtime came after midnight.
        case toMidnight(start: Date)
        case range(start: Date, end: Date)
    }

    /// The fewest scored windows, two hours, before the night reads a share: overnight
    /// heart rate can be sparse, and three scored windows out of thirty would read 100%.
    static let minimumNightScoredWindowCount = 8

    var day: Period
    /// nil when no main sleep session ended on the day.
    var night: Period?
    /// Today's Day runs to now rather than to a bedtime.
    var isToday: Bool
    var daySpan: DaySpan

    var nightHasEnoughData: Bool {
        (night?.scoredWindowCount ?? 0) >= Self.minimumNightScoredWindowCount
    }

    /// - Parameters:
    ///   - windowsByDay: Stress windows keyed by day start; reads `day` and the day before.
    ///   - night: the main sleep session that ended on `day`.
    ///   - naps: the day's naps.
    ///   - tonight: the main session that ends the next day; its minutes before
    ///     midnight are sleep, not Day.
    static func make(
        day: Date,
        windowsByDay: [Date: [StressWindow]],
        night: DateInterval?,
        naps: [DateInterval] = [],
        tonight: DateInterval? = nil,
        now: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> StressDayNightSplit {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let previousDayStart = calendar.date(byAdding: .day, value: -1, to: dayStart)
            ?? dayStart.addingTimeInterval(-86_400)
        let isToday = calendar.isDate(dayStart, inSameDayAs: now)
        let dayWindows = (windowsByDay[dayStart] ?? []).sorted { $0.interval.start < $1.interval.start }
        let sleep = [night, tonight].compactMap { $0 } + naps

        // Wake stays inside the day and the bedtime (or now) never lands before it:
        // `DateInterval` traps on an end before its start.
        let wake = min(max(night?.end ?? dayStart, dayStart), dayEnd)
        var bedtime = isToday ? now : dayEnd
        if let tonight, tonight.start < bedtime {
            bedtime = tonight.start
        }
        let dayInterval = DateInterval(start: wake, end: max(wake, min(bedtime, dayEnd)))

        let dayPeriod = period(
            interval: dayInterval,
            windows: dayWindows.filter { window in
                !sleep.contains { overlaps(window.interval, $0) }
            }
        )

        let nightPeriod = night.map { night in
            period(
                interval: night,
                windows: ((windowsByDay[previousDayStart] ?? []) + dayWindows)
                    .filter { overlaps($0.interval, night) }
                    .sorted { $0.interval.start < $1.interval.start }
            )
        }

        let daySpan: DaySpan
        if isToday {
            daySpan = .toNow(start: dayInterval.start)
        } else if dayInterval.end < dayEnd {
            daySpan = .range(start: dayInterval.start, end: dayInterval.end)
        } else if dayInterval.start > dayStart {
            daySpan = .toMidnight(start: dayInterval.start)
        } else {
            daySpan = .allDay
        }

        return StressDayNightSplit(
            day: dayPeriod,
            night: nightPeriod,
            isToday: isToday,
            daySpan: daySpan
        )
    }

    /// `windows` in time order, every window of the span included, so an unscored
    /// gap between two restless windows ends their stretch.
    private static func period(interval: DateInterval, windows: [StressWindow]) -> Period {
        var period = Period(interval: interval)
        var scoreTotal = 0.0
        var restlessStretchCount = 0
        var inRestlessStretch = false

        for window in windows {
            let minutes = Int((window.interval.duration / 60).rounded())
            guard let score = window.score else {
                if window.state == .activity {
                    period.activityMinutes += minutes
                }
                inRestlessStretch = false
                continue
            }

            let band = StressBand.band(for: score)
            let roundedScore = Int(score.rounded())
            period.scoredWindowCount += 1
            scoreTotal += score
            period.minutesByBand[band, default: 0] += minutes
            if roundedScore > (period.peak?.score ?? -1) {
                period.peak = Peak(score: roundedScore, start: window.interval.start)
            }

            guard band != .rest else {
                inRestlessStretch = false
                continue
            }

            period.restlessMinutes += minutes
            if !inRestlessStretch {
                restlessStretchCount += 1
                if restlessStretchCount == 1 {
                    period.restlessStart = window.interval.start
                }
            }
            inRestlessStretch = true
        }

        if period.scoredWindowCount > 0 {
            period.averageScore = Int((scoreTotal / Double(period.scoredWindowCount)).rounded())
        }
        if restlessStretchCount > 1 {
            period.restlessStart = nil
        }

        return period
    }

    /// The calculator's own overlap rule, so a window sleep only touches (the one you
    /// wake up in) counts as sleep here as it does for the quiet heart rate.
    private static func overlaps(_ first: DateInterval, _ second: DateInterval) -> Bool {
        first.start < second.end && first.end > second.start
    }
}

/// Stress's Day and Night card, under the Day View: the selected day's waking
/// windows beside the night that ended that morning. Day leads with its average
/// and Night with its share in Peace, because a sleeping heart rate sits far below
/// the awake baseline every window is scored against, so a night's average reads
/// close to zero whatever the night was like.
struct BodyStressDayNightCard: View {
    let split: StressDayNightSplit

    private static let timeFormat = Date.FormatStyle.dateTime.hour().minute()
    private static let tileCornerRadius: CGFloat = 18
    /// The card's own translucent fill (`bodyCardBackground(translucent:)` is
    /// `Color.primary` at 0.06), so the tiles read as the same white glass, one layer up.
    private static let tileFillOpacity = 0.06

    /// What a tile's last line says. One tile shape for every state, so switching
    /// days rolls the numbers over in place instead of swapping the tile out.
    private enum DetailLine {
        case peak(StressDayNightSplit.Peak)
        case restless(minutes: Int, start: Date?, band: StressBand)
        case noRestless
        case notEnoughData
        case none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("stress.dayNight.title")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            HStack(alignment: .top, spacing: 10) {
                dayTile
                nightTile
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private var dayTile: some View {
        let day = split.day
        let band = day.averageScore.map { StressBand.band(for: $0) }
        let span: Text
        switch split.daySpan {
        case .toNow(let start):
            span = Text("stress.dayNight.spanToNow \(start, format: Self.timeFormat)")
        case .allDay:
            span = Text("stress.dayNight.allDay")
        case .toMidnight(let start):
            span = Text("stress.dayNight.spanToMidnight \(start, format: Self.timeFormat)")
        case .range(let start, let end):
            span = Text("stress.dayNight.span \(start, format: Self.timeFormat) \(end, format: Self.timeFormat)")
        }

        return tile(
            symbolName: "sun.max.fill",
            symbolColor: .orange,
            title: "stress.dayNight.day",
            value: day.averageScore.map { "\($0)" } ?? "--",
            band: band,
            span: span,
            spanKey: "\(day.interval.start.timeIntervalSince1970)-\(split.isToday ? 0 : day.interval.end.timeIntervalSince1970)",
            segments: Self.segments(for: day),
            detail: day.peak.map(DetailLine.peak) ?? .none
        )
    }

    private var nightTile: some View {
        let night = split.night
        let showsShare = split.nightHasEnoughData
        let value: String
        if showsShare, let share = night?.peaceShare {
            value = "\(share)%"
        } else {
            value = "--"
        }

        let span: Text
        if let night {
            span = Text("stress.dayNight.span \(night.interval.start, format: Self.timeFormat) \(night.interval.end, format: Self.timeFormat)")
        } else {
            span = Text("stress.dayNight.noSleep")
        }

        let detail: DetailLine
        if night == nil {
            detail = .none
        } else if !showsShare {
            detail = .notEnoughData
        } else if let night, night.restlessMinutes > 0 {
            detail = .restless(
                minutes: night.restlessMinutes,
                start: night.restlessStart,
                band: night.peak.map { StressBand.band(for: $0.score) } ?? .low
            )
        } else {
            detail = .noRestless
        }

        return tile(
            symbolName: "moon.fill",
            symbolColor: .indigo,
            title: "stress.dayNight.night",
            value: value,
            band: showsShare ? .rest : nil,
            span: span,
            spanKey: night.map { "\($0.interval.start.timeIntervalSince1970)-\($0.interval.end.timeIntervalSince1970)" } ?? "none",
            segments: Self.segments(for: showsShare ? night : nil),
            detail: detail
        )
    }

    /// `band` is the headline's level, named beside its number in the primary text
    /// color: the level colors stay on the bar and the detail dot, and the tile is
    /// white glass whatever the band, like the card around it. Without a band the
    /// number reads "--" in secondary.
    private func tile(
        symbolName: String,
        symbolColor: Color,
        title: LocalizedStringKey,
        value: String,
        band: StressBand?,
        span: Text,
        spanKey: String,
        segments: [BodyStressDayNightBar.Segment],
        detail: DetailLine
    ) -> some View {
        let valueColor: Color = band == nil ? .secondary : .primary

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(symbolColor)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                BodyAnimatedMetricValueText(
                    value: value,
                    fontSize: 26,
                    color: valueColor,
                    minimumScaleFactor: 0.7
                )

                if let band {
                    Text(band.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            span
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .bodyLegendNumberFlip(value: spanKey)

            BodyStressDayNightBar(segments: segments)
                .padding(.vertical, 2)

            detailLine(detail)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            BodyGlassChip(color: .primary, cornerRadius: Self.tileCornerRadius, fillOpacity: Self.tileFillOpacity)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func detailLine(_ line: DetailLine) -> some View {
        switch line {
        case .peak(let peak):
            dotLine(
                color: BodyStressBandPresentation.color(for: StressBand.band(for: peak.score)),
                text: Text("stress.dayNight.peak \(peak.score) \(peak.start, format: Self.timeFormat)")
            )
        case .restless(let minutes, let start, let band):
            dotLine(color: BodyStressBandPresentation.color(for: band), text: Self.restlessText(minutes: minutes, start: start))
        case .noRestless:
            dotLine(color: BodyStressBandPresentation.color(for: .rest), text: Text("stress.dayNight.noRestless"))
        case .notEnoughData:
            dotLine(color: nil, text: Text("stress.dayNight.notEnoughData"))
        case .none:
            EmptyView()
        }
    }

    /// The time only when the restless minutes are one stretch: "at 3:15 AM" over
    /// two stretches would name just the first of them.
    private static func restlessText(minutes: Int, start: Date?) -> Text {
        let duration = BodyValueFormat.durationText(for: TimeInterval(minutes) * 60)
        guard let start else {
            return Text("stress.dayNight.restless \(duration)")
        }

        return Text("stress.dayNight.restlessAt \(duration) \(start, format: timeFormat)")
    }

    private func dotLine(color: Color?, text: Text) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
            }

            text
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The four bands in the Day View breakdown's order, then movement in its gray.
    /// All five always, empty or not, so the bar's segments morph between days.
    private static func segments(for period: StressDayNightSplit.Period?) -> [BodyStressDayNightBar.Segment] {
        StressBand.displayOrder.map { band in
            BodyStressDayNightBar.Segment(
                id: band.rawValue,
                color: BodyStressBandPresentation.color(for: band),
                minutes: period?.minutesByBand[band, default: 0] ?? 0
            )
        } + [
            BodyStressDayNightBar.Segment(
                id: "activity",
                color: BodyStressBandPresentation.activityColor,
                minutes: period?.activityMinutes ?? 0
            )
        ]
    }
}

/// A tile's time in each level as one capsule, on the breakdown rows' gray track.
struct BodyStressDayNightBar: View {
    struct Segment: Equatable, Identifiable {
        var id: String
        var color: Color
        var minutes: Int
    }

    let segments: [Segment]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 8
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let frames = Self.segmentFrames(minutes: segments.map(\.minutes), width: proxy.size.width, gap: gap)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))

                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: frames[index].width)
                        .offset(x: frames[index].x)
                }
            }
            .frame(width: proxy.size.width, height: height, alignment: .leading)
            .clipShape(Capsule())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: segments.map(\.minutes))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Each segment's offset and drawn width: its share of the width, less a gap
    /// after every drawn segment but the last. An empty segment draws nothing.
    static func segmentFrames(minutes: [Int], width: CGFloat, gap: CGFloat) -> [(x: CGFloat, width: CGFloat)] {
        let total = minutes.reduce(0, +)
        guard total > 0, width > 0 else {
            return minutes.map { _ in (x: 0, width: 0) }
        }

        let lastDrawnIndex = minutes.lastIndex { $0 > 0 }
        var x: CGFloat = 0
        return minutes.enumerated().map { index, value in
            let share = width * CGFloat(value) / CGFloat(total)
            let drawn = value > 0 ? max(0, share - (index == lastDrawnIndex ? 0 : gap)) : 0
            defer { x += share }
            return (x: x, width: drawn)
        }
    }
}
