//
//  SleepStagesComplication.swift
//  BodyWatchWidgetExtension
//
//  Watch complication (accessoryRectangular only): a header total plus one
//  horizontal bar showing last night's sleep stages (main session only),
//  colored per stage, with a start/end time axis below. Free (not Pro-gated),
//  matching the exercise complication. Reuses the existing
//  `WatchMetricProvider`/`WatchMetricEntry`, which already carries the whole
//  snapshot; the timeline provider's `sanitized()` nils out `sleepStages` for
//  a stale night, so this view just reads `entry.snapshot.sleepStages`.
//

import SwiftUI
import WidgetKit

struct SleepStagesComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchSleepStages", provider: WatchMetricProvider()) { entry in
            SleepStagesComplicationView(entry: entry)
                // Tapping the complication opens the Sleep detail page directly.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.sleep))
        }
        .configurationDisplayName(String(localized: "Sleep Stages"))
        .description(String(localized: "Last night's sleep stages."))
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct SleepStagesComplicationView: View {
    let entry: WatchMetricEntry

    private static let barCornerRadius: CGFloat = 3

    private var segments: [WatchSleepStageSegment] {
        (entry.snapshot.sleepStages ?? []).sorted { $0.startDate < $1.startDate }
    }

    private var spanStart: Date? { segments.first?.startDate }
    private var spanEnd: Date? { segments.last?.endDate }

    private var asleepDuration: TimeInterval {
        segments
            .filter { $0.stage != "awake" }
            .reduce(0) { $0 + max(0, $1.endDate.timeIntervalSince($1.startDate)) }
    }

    var body: some View {
        Group {
            if let start = spanStart, let end = spanEnd, end > start {
                VStack(alignment: .leading, spacing: 3) {
                    header
                    barRow(start: start, end: end)
                        .frame(maxHeight: .infinity)
                    timeRow(start: start, end: end)
                }
            } else {
                Text("No sleep data yet")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var header: some View {
        let (hours, minutes) = Self.hoursAndMinutes(from: asleepDuration)
        // One format key (like "%lld MIN THIS WEEK") so the whole phrase,
        // unit letters included, is translatable as a unit.
        return Text("\(hours)H \(minutes)M ASLEEP")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// One bar spanning `[start, end]`; each segment is a rectangle positioned
    /// and sized proportionally to its time within that span. Segments are
    /// drawn in a `ZStack` (rather than an `HStack` of spacers) so gaps and
    /// widths come straight from the timestamps instead of accumulating
    /// rounding error across many flexible-width views. The outer clip is the
    /// only rounding, so only the bar's two outer ends are rounded.
    private func barRow(start: Date, end: Date) -> some View {
        let total = end.timeIntervalSince(start)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let x = start.distance(to: segment.startDate) / total
                    let width = max(0, segment.endDate.timeIntervalSince(segment.startDate)) / total
                    Rectangle()
                        .foregroundStyle(Self.stageColor(segment.stage))
                        .frame(width: proxy.size.width * CGFloat(width), height: proxy.size.height)
                        .offset(x: proxy.size.width * CGFloat(x))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.barCornerRadius, style: .continuous))
    }

    private func timeRow(start: Date, end: Date) -> some View {
        HStack {
            Text(Self.timeLabel(start))
            Spacer()
            Text(Self.timeLabel(end))
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private static func timeLabel(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private static func hoursAndMinutes(from duration: TimeInterval) -> (Int, Int) {
        let totalMinutes = Int((duration / 60).rounded())
        return (totalMinutes / 60, totalMinutes % 60)
    }

    /// Mirrors `HealthWidgetSleepStage.color` (BodyShared/Models/HealthWidgetSnapshot.swift).
    /// BodyShared isn't linked into this target, so these four literals are
    /// duplicated here rather than shared. Tinted watch faces recolor
    /// everything to the face tint, same as the other complications in this
    /// bundle.
    private static func stageColor(_ raw: String) -> Color {
        switch raw {
        case "awake": return Color(red: 1.00, green: 0.31, blue: 0.22)
        case "rem": return Color(red: 0.42, green: 0.80, blue: 1.00)
        case "core": return Color(red: 0.24, green: 0.56, blue: 1.00)
        case "deep": return Color(red: 0.25, green: 0.25, blue: 0.82)
        default: return Color.gray
        }
    }
}
