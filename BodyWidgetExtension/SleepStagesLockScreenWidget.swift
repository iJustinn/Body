//
//  SleepStagesLockScreenWidget.swift
//  BodyWidgetExtension
//
//  iPhone/iPad Lock Screen widget (accessoryRectangular) carrying the watch
//  Sleep Stages complication's layout: a header total, one horizontal bar of
//  the night's stages, and a bed/wake time row underneath. Reads the same App
//  Group snapshot as the medium Sleep Stages widget (today's main session
//  only, empty until today's own sleep is recorded). No configuration, so this
//  is a plain StaticConfiguration like the Weekly Workout Time widget: a Lock
//  Screen widget has no background of its own for BodyWidgetConfigurationIntent
//  to pick. Pro-gated, matching the other Body widgets on iOS.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SleepStagesLockScreenEntry: TimelineEntry {
    let date: Date
    let sleep: HealthWidgetSleepStages
    let isPro: Bool
}

struct SleepStagesLockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepStagesLockScreenEntry {
        SleepStagesLockScreenEntry(date: Date(), sleep: HealthWidgetSnapshot.placeholder.sleep, isPro: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepStagesLockScreenEntry) -> Void) {
        completion(loadEntry(usePlaceholderWhenEmpty: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepStagesLockScreenEntry>) -> Void) {
        let entry = loadEntry(usePlaceholderWhenEmpty: false)
        let nextRefresh = Calendar.bodyGregorian.date(byAdding: .minute, value: 30, to: entry.date)
            ?? entry.date.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry(usePlaceholderWhenEmpty: Bool) -> SleepStagesLockScreenEntry {
        let now = Date()
        let resolved = SleepStagesEntryBuilder.resolve(
            snapshot: HealthWidgetSnapshotStore.load(),
            usePlaceholderWhenEmpty: usePlaceholderWhenEmpty,
            // Preview/gallery shows the real widget; the live timeline respects the flag.
            isPro: usePlaceholderWhenEmpty || BodyProEntitlement.isUnlocked,
            now: now
        )
        return SleepStagesLockScreenEntry(date: now, sleep: resolved.snapshot.sleep, isPro: resolved.isPro)
    }
}

// MARK: - Widget

struct BodySleepStagesLockScreenWidget: Widget {
    let kind = "BodySleepStagesLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepStagesLockScreenProvider()) { entry in
            Group {
                if entry.isPro {
                    SleepStagesLockScreenView(sleep: entry.sleep)
                } else {
                    BodyAccessoryLockedView()
                }
            }
            .containerBackground(.clear, for: .widget)
        }
        .supportedFamilies([.accessoryRectangular])
        .configurationDisplayName("Sleep Stages")
        .description("View today's sleep stages.")
        .contentMarginsDisabled()
    }
}

// MARK: - Unlocked view

/// Mirrors `SleepStagesComplication` on the watch: the same header, one-bar
/// hypnogram, and time row, laid out at the same sizes. Stage colors are the
/// shared `HealthWidgetSleepStage` palette here, since BodyShared is linked
/// into this target (the watch extension duplicates the literals instead).
private struct SleepStagesLockScreenView: View {
    let sleep: HealthWidgetSleepStages

    @Environment(\.widgetRenderingMode) private var renderingMode

    private static let barCornerRadius: CGFloat = 3

    private var segments: [HealthWidgetSleepSegment] {
        sleep.segments.sorted { $0.startDate < $1.startDate }
    }

    private var spanStart: Date? { segments.first?.startDate }
    private var spanEnd: Date? { segments.map(\.endDate).max() }

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
                Text(String(localized: "No sleep data yet", table: "BodyShared"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        let (hours, minutes) = Self.hoursAndMinutes(from: sleep.asleepDuration)
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
                ForEach(segments) { segment in
                    let x = start.distance(to: segment.startDate) / total
                    let width = segment.duration / total
                    Rectangle()
                        .foregroundStyle(stageStyle(segment.stage))
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

    /// Lock Screen widgets render in vibrant mode, which maps every color onto
    /// a luminance-derived monochrome ramp. The four stage colors land close
    /// together there (Awake and Core within a few percent), so the bar would
    /// read as one flat block. Vibrant and accented modes therefore draw
    /// explicit opacities, brightest for Deep down to faintest for Awake, and
    /// only a full-color context gets the real palette.
    private func stageStyle(_ stage: HealthWidgetSleepStage) -> Color {
        guard renderingMode != .fullColor else { return stage.color }
        switch stage {
        case .deep: return .primary
        case .core: return .primary.opacity(0.72)
        case .rem: return .primary.opacity(0.48)
        case .awake: return .primary.opacity(0.24)
        }
    }

    private static func timeLabel(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private static func hoursAndMinutes(from duration: TimeInterval) -> (Int, Int) {
        let totalMinutes = Int((duration / 60).rounded())
        return (totalMinutes / 60, totalMinutes % 60)
    }
}
