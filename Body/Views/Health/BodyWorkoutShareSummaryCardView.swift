//
//  BodyWorkoutShareSummaryCardView.swift
//  Body
//
//  The month-summary share card: the same exported object as
//  `BodyWorkoutShareCardView` (same ratios, same backgrounds, same scrims, same
//  pinned wordmark, `ImageRenderer.scale = 3`), with a month's chart where a single
//  workout's route trace would be. Its content is a title, one to five metric blocks,
//  and either the calendar grid or the activity breakdown — the very views the
//  Workouts page draws, in their `.widgetLarge` guise.
//  No layout number is written here: `WorkoutShareSummaryCardGeometry` derives every
//  rect from the ratio and the metric count, so the card and its render tests can't
//  drift apart. Unlike the workout card this one is *not* fully
//  environment-independent: the two chart views are shared with the app and colour
//  their type off `.primary`/`.secondary`, so the sheet inverts `colorScheme` from the
//  resolved ink before rendering — exactly as it already does for the long image.
//

import SwiftUI
import UIKit

struct BodyWorkoutShareSummaryCardView: View {
    let summary: WorkoutShareMonthSummary
    /// Which chart the card draws. Session state on the sheet — changing it here never
    /// moves the Workouts page's own toggle.
    let chartStyle: WorkoutSummaryChartStyle
    /// Already resolved through the Pro gate by the sheet; the card never re-checks it.
    let metrics: [WorkoutShareSummaryMetricOption]
    /// `.map` never reaches this card — a month has no route — but the case is handled
    /// so the switch stays exhaustive and a future background can't compile away.
    let background: WorkoutShareCardBackground
    let aspectRatio: WorkoutShareAspectRatio
    /// Where the user dragged and pinched the title/metrics/chart block, as one unit.
    let infoTransform: WorkoutShareInfoTransform
    /// How the photo background is panned and zoomed. Only `.photo` reads it.
    let photoTransform: WorkoutSharePhotoTransform
    /// Type design for everything but the brand wordmark and the charts' own type.
    let fontDesign: Font.Design
    let attribution: WorkoutShareAttribution
    /// The "today" the calendar highlights. Captured once by the sheet so the preview
    /// and the export can't disagree across midnight.
    let referenceDate: Date

    /// Every frame the card draws with, recomputed per access — a value type derived
    /// from two inputs is cheaper than caching it.
    private var geometry: WorkoutShareSummaryCardGeometry {
        WorkoutShareSummaryCardGeometry(aspectRatio: aspectRatio, metricCount: metrics.count)
    }

    /// The workout card's geometry for this ratio, read only for the scrim heights and
    /// the branding baseline — the two numbers both cards must share exactly.
    private var cardGeometry: WorkoutShareCardGeometry {
        WorkoutShareCardGeometry(aspectRatio: aspectRatio, layout: .centered, arrangement: .stacked)
    }

    /// Which way the ink runs, read from the background that is *actually* drawn: a
    /// photo or a video frame is dark-backed by the scrims and takes the light ink even
    /// while a Daylight preset stays selected in the tray.
    private var ink: WorkoutShareCardInk {
        switch background {
        case .preset(let preset): return preset.ink
        case .photo, .map, .video: return .light
        }
    }

    var body: some View {
        let size = geometry.size
        return ZStack(alignment: .bottom) {
            ZStack {
                backgroundLayer
                scrims
            }

            infoBlock
                // Explicitly card-sized so the `.position` calls inside keep resolving
                // against the full card once the block is scaled and offset.
                .frame(width: size.width, height: size.height)
                // Offset after scale, so a drag stays 1:1 with card points at any zoom.
                .scaleEffect(infoTransform.scale, anchor: .center)
                .offset(infoTransform.offset)

            WorkoutShareBrandingRow(ink: ink, attribution: attribution)
                .padding(.bottom, WorkoutShareCardGeometry.brandingBottomPadding)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        let size = geometry.size
        switch background {
        case .preset(let preset):
            preset.gradient(tint: summary.tintType.color)
        case .photo(let image):
            // Scale then offset, then clip: the fill's overhang beyond the card must
            // survive until after the transform, because the clamp lets the photo pan
            // exactly by that overhang — clipping it first would leave a bare strip.
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(photoTransform.scale, anchor: .center)
                .offset(photoTransform.offset)
                .frame(width: size.width, height: size.height)
                .clipped()
        case .map:
            // Unreachable: the sheet never offers the map tile in summary mode (there
            // is no route to snapshot). Drawn as Midnight rather than left empty so an
            // impossible state still produces a legible card instead of a bare frame.
            BodyWorkoutSharePreset.midnight.gradient(tint: summary.tintType.color)
        case .video:
            // Deliberately empty, sized so the ZStack still gets the card's frame from
            // its background layer. `ImageRenderer.isOpaque` is false, so the rendered
            // overlay keeps this transparency and the video shows through it.
            Color.clear
                .frame(width: size.width, height: size.height)
        }
    }

    /// The workout card's scrims, at the same heights and opacities — `isMap: false`
    /// always, since a summary card never carries map tiles.
    private var scrims: some View {
        let scrim = ink.scrim

        return VStack(spacing: 0) {
            LinearGradient(
                colors: [scrim.opacity(0.45), scrim.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: cardGeometry.topScrimHeight(isMap: false))

            Spacer(minLength: 0)

            LinearGradient(
                colors: [scrim.opacity(0), scrim.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: cardGeometry.bottomScrimHeight(isMap: false))
        }
    }

    // MARK: - Info block

    /// Fixed regions rather than a flowing stack: the card's height is known, so the
    /// title, the metrics, and the chart each own an absolute slot from
    /// `WorkoutShareSummaryCardGeometry` and no metric count can push the chart into
    /// the branding zone.
    private var infoBlock: some View {
        let size = geometry.size
        let titleRect = geometry.titleRect
        let metricsRect = geometry.metricsRect
        let chartRect = geometry.chartRect
        let chartSize = geometry.chartFrame(for: chartStyle)
        // The whole group slides down by half the chart's slack, so the totals stay
        // tight against the chart instead of the chart centering itself away from them.
        let shift = geometry.verticalShift(for: chartStyle)

        return ZStack {
            // The square is the chart alone: no title, no metrics — the geometry hands
            // back empty rects there, and drawing into them would only leave stray text.
            if geometry.arrangement == .stacked {
            Text(summary.title)
                .font(.system(size: 26, weight: .bold, design: fontDesign))
                .foregroundColor(ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: titleRect.width, height: titleRect.height, alignment: .center)
                .position(x: titleRect.midX, y: titleRect.midY + shift)

            metricBlocks
                .frame(width: metricsRect.width, height: metricsRect.height)
                .position(x: metricsRect.midX, y: metricsRect.midY + shift)
            }

            chart
                // Top-aligned: the frame is sized for a six-week month, and a five-week
                // grid centered in it would drift away from the totals above.
                .frame(width: chartSize.width, height: chartSize.height, alignment: .top)
                .position(x: chartRect.midX, y: chartRect.minY + shift + chartSize.height / 2)
        }
        .frame(width: size.width, height: size.height)
        // The same halo the workout card's blocks carry, so the ink stays legible when
        // the block is dragged into a bright photo area the scrims don't reach.
        .shadow(color: ink.legibilityShadow, radius: 5, x: 0, y: 1.5)
    }

    /// The workout card's centered blocks — label over value — wrapped into rows of
    /// `metricsPerRow`, at the size the geometry picked for this ratio and count.
    private var metricBlocks: some View {
        let style = geometry.metricBlockStyle
        let spacing: CGFloat = 24
        let perRow = CGFloat(max(1, geometry.metricsPerRow))
        // Explicit equal columns: an HStack of flexible blocks hands a longer value
        // more room than its neighbour, which then truncates instead of scaling.
        let columnWidth = (geometry.metricsRect.width - spacing * (perRow - 1)) / perRow
        return VStack(spacing: style.rowGap) {
            ForEach(Array(metricRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row) { metric in
                        metricBlock(metric, style: style)
                            // A row height that stays the geometry's whatever size
                            // the values landed at.
                            .frame(width: columnWidth, height: style.rowHeight)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    /// The picked metrics in rows of at most `metricsPerRow`. A short last row keeps
    /// its blocks' widths (`maxWidth: .infinity` splits whatever the row has), which
    /// centers a lone fifth block under the pair or trio above it.
    private var metricRows: [[WorkoutShareSummaryMetricOption]] {
        let perRow = max(1, geometry.metricsPerRow)
        return stride(from: 0, to: metrics.count, by: perRow).map { start in
            Array(metrics[start..<min(start + perRow, metrics.count)])
        }
    }

    private func metricBlock(
        _ metric: WorkoutShareSummaryMetricOption,
        style: WorkoutShareCardGeometry.MetricBlockStyle
    ) -> some View {
        // The floor sits on each text, not the stack: through the stack a narrow
        // side-by-side column truncated the value ("21h 4…") instead of shrinking it.
        // A row splits the card's width between up to three values, so a long one
        // ("1,240 kcal") needs to shrink further than usual before it would rather
        // truncate.
        VStack(spacing: 2) {
            Text(metric.value)
                .font(.system(size: style.valueSize, weight: .bold, design: fontDesign))
                .foregroundColor(ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(metric.title)
                .font(.system(size: style.labelSize, weight: .semibold, design: fontDesign))
                .foregroundColor(ink.primary.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
    }

    /// The page's own charts, in the guise the large widget uses: capped rows, no
    /// switch control, nothing selectable. They colour their type off `.primary` /
    /// `.secondary`, which the sheet's inverted `colorScheme` resolves for the ink.
    @ViewBuilder
    private var chart: some View {
        switch chartStyle {
        case .calendar:
            // Natural height, not filled: the frame is sized for six week rows, and a
            // five-row month stretched over it would draw pills instead of squares.
            // The grid sits centered in the frame's width-driven square cells.
            WorkoutCalendarView(
                snapshot: summary.snapshot,
                style: .widgetLarge,
                fillsAvailableHeight: false,
                scalesGlyphsToFit: true,
                referenceDate: referenceDate,
                onSelectDay: nil,
                onSwitchChart: nil
            )
        case .bar:
            WorkoutTypeBreakdownView(
                snapshot: summary.snapshot,
                style: .widgetLarge,
                rowLimit: geometry.barRowLimit,
                onSelectType: nil,
                onSwitchChart: nil
            )
        }
    }
}

/// Shared preview fixture: a busy 26-workout May.
private func previewSummaryCard(
    chartStyle: WorkoutSummaryChartStyle = .calendar,
    aspectRatio: WorkoutShareAspectRatio = .portrait9x16,
    preset: BodyWorkoutSharePreset = .midnight,
    metricCount: Int = 3
) -> some View {
    let calendar = Calendar.bodyGregorian
    let start = calendar.date(from: DateComponents(year: 2_025, month: 5, day: 1, hour: 8)) ?? Date()
    let types: [BodyWorkoutType] = [.running, .cycling, .strengthTraining, .swimming, .walking, .yoga]
    let workouts: [WorkoutSummary] = (0..<24).map { index in
        WorkoutSummary(
            type: types[index % types.count],
            startDate: calendar.date(byAdding: .day, value: index, to: start) ?? start,
            duration: TimeInterval(1_500 + index * 90),
            activeEnergyKilocalories: Double(220 + index * 8),
            distanceMeters: index % 3 == 0 ? Double(4_000 + index * 250) : nil
        )
    }
    let snapshot = WorkoutMonthSnapshot.make(month: 5, year: 2_025, workouts: workouts, calendar: calendar)
    let options = WorkoutShareSummaryMetricsBuilder.availableMetrics(
        snapshot: snapshot,
        distanceUnitPreference: .kilometers,
        energyUnitPreference: .kilocalories
    )
    return BodyWorkoutShareSummaryCardView(
        summary: WorkoutShareMonthSummary(snapshot: snapshot, initialChartStyle: chartStyle),
        chartStyle: chartStyle,
        metrics: Array(options.prefix(metricCount)),
        background: .preset(preset),
        aspectRatio: aspectRatio,
        infoTransform: .identity,
        photoTransform: .identity,
        fontDesign: .rounded,
        attribution: .empty,
        referenceDate: start
    )
    .environment(\.colorScheme, preset.ink == .dark ? .light : .dark)
    .frame(width: aspectRatio.cardSize.width, height: aspectRatio.cardSize.height)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
}

#Preview("Calendar 9:16") {
    previewSummaryCard(chartStyle: .calendar)
}

#Preview("Bar 9:16") {
    previewSummaryCard(chartStyle: .bar, metricCount: 5)
}

#Preview("Calendar 16:9") {
    previewSummaryCard(chartStyle: .calendar, aspectRatio: .landscape16x9)
}

#Preview("Bar 1:1 Daylight") {
    previewSummaryCard(chartStyle: .bar, aspectRatio: .square, preset: .daylight, metricCount: 4)
}
