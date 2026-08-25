//
//  BodyWorkoutShareLongCardView.swift
//  Body
//
//  The "long image": the workout detail page, poured into one tall shareable
//  picture. Fixed 360 pt wide (the share card's width) and *naturally* tall — the
//  root fixes its vertical size to its content and `ImageRenderer` is given a nil
//  height proposal, so a workout with twenty splits simply produces a taller image.
//
//  Value-driven and environment-independent like `BodyWorkoutShareCardView`: every
//  presentation arrives already built (by the same `WorkoutDetailChartPresentations`
//  functions the detail page uses, so the two can't drift), and which sections draw is
//  decided by the pure `WorkoutShareLongImageSections` policy rather than by any state
//  in here. Background is always a gradient preset — the long image never draws a map,
//  a photo, or a video frame.
//

import SwiftUI
import UIKit

struct BodyWorkoutShareLongCardView: View {
    /// The card's width, and the width `ImageRenderer` proposes. The same 360 pt as the
    /// 9:16 share card, so the two exports read as one family.
    static let width: CGFloat = 360
    /// Horizontal inset of everything but the chart cards' own padding.
    private static let margin: CGFloat = 24

    let presentation: WorkoutDetailPresentation
    /// The Details tiles this image shows, already narrowed to the picked metrics and in
    /// pool order. Real `WorkoutDetailMetric`s rather than `WorkoutShareMetric`s, so the
    /// "vs 30-day avg" comparison badges survive into the export.
    let tiles: [WorkoutDetailMetric]
    /// Already normalized by `WorkoutShareRouteProjection`; nil (or Hide Route) collapses
    /// the trace section into the route-less glyph.
    let routePoints: [CGPoint]?
    let route3D: WorkoutRoute3DProjection.Projected3D?
    /// Already resolved through `WorkoutShareBackgroundPolicy.resolvedDimension`.
    let dimension: WorkoutShareRouteDimension
    /// Only read when there's no trace to draw — the same rule the card follows.
    let iconHidden: Bool
    let locality: String?
    let type: BodyWorkoutType
    /// Resolved workout colors (built-in defaults plus any Pro customization), passed in
    /// like every other value here rather than read from the environment — an
    /// `ImageRenderer` root doesn't inherit it, and this view stays environment-independent.
    let palette: BodyWorkoutColorPalette
    let preset: BodyWorkoutSharePreset
    let fontDesign: Font.Design
    let routeColor: Color
    /// Which chart sections draw — `WorkoutShareLongImageSections.sections(…)`'s answer,
    /// passed in so the view holds no policy of its own.
    let sections: WorkoutShareLongImageSections.Visibility
    let heartRateSamples: [WorkoutHeartRateSample]
    let maxHeartRate: Double?
    let paceOrSpeed: WorkoutBucketedSeriesPresentation?
    let splits: WorkoutSplitsPresentation?
    let elevation: WorkoutElevationLinePresentation?
    let cadence: WorkoutBucketedSeriesPresentation?
    let power: WorkoutBucketedSeriesPresentation?
    let strideLength: WorkoutBucketedSeriesPresentation?
    let groundContact: WorkoutBucketedSeriesPresentation?
    let verticalOscillation: WorkoutBucketedSeriesPresentation?
    /// The Settings profile avatar/name drawn beside the watermark. Defaulted so
    /// existing call sites (tests, previews) compile unchanged.
    var attribution: WorkoutShareAttribution = .empty

    /// The trace draws only when there are points and the layout isn't the route-less
    /// one — same rule as the card, so Hide Route lands here as `routePoints == nil`.
    private var showsTrace: Bool { routePoints != nil }

    private var ribbon: WorkoutRoute3DProjection.Projected3D? {
        guard showsTrace, dimension == .threeD else { return nil }
        return route3D
    }

    /// The long image never draws a map, a photo, or a clip, so its ink comes straight
    /// from the preset it paints — nothing else can be behind the text.
    private var ink: WorkoutShareCardInk { preset.ink }

    /// The header chip's glyph. On the light ink it's the card's own white-on-tint
    /// treatment; on a white card the chip has to carry its own contrast, so the glyph
    /// takes the luminance-aware colour the calendar uses on the same tints — a
    /// high-luminance type (yellow, mint) gets a dark glyph instead of an invisible
    /// white one.
    private var chipGlyphColor: Color {
        ink == .dark ? palette.contentColor(for: type) : .white
    }

    /// A 45%-alpha tint chip washes out to near-white on a white card, taking the glyph
    /// with it — so the dark ink gets the full-strength tint the glyph colour was
    /// computed against.
    private var chipFillOpacity: Double {
        ink == .dark ? 1 : 0.45
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            routeSection
            if !tiles.isEmpty {
                tileGrid
            }
            chartSections
            branding
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 28)
        .padding(.bottom, WorkoutShareCardGeometry.brandingBottomPadding)
        .frame(width: Self.width)
        // The whole point of the long image: the height comes from the content, not
        // from a proposal. Everything above stays inside the fixed 360 pt width.
        .fixedSize(horizontal: false, vertical: true)
        .background(preset.gradient(tint: palette.color(for: type)))
    }

    // MARK: - Header (the classic card's arrangement, one column wider)

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: type.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(chipGlyphColor)
                    .frame(width: 46, height: 46)
                    .background(palette.color(for: type).opacity(chipFillOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.system(size: 24, weight: .bold, design: fontDesign))
                        .foregroundColor(ink.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    if let locality {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(locality)
                                .font(.system(size: 14, weight: .medium, design: fontDesign))
                                .lineLimit(1)
                        }
                        .foregroundColor(ink.primary(0.7))
                    }

                    Text("\(presentation.dateTitle) - \(presentation.timeRangeText)")
                        .font(.system(size: 14, weight: .medium, design: fontDesign))
                        .foregroundColor(ink.primary(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 24) {
                if let heroValue = presentation.heroDistanceValue, let heroUnit = presentation.heroDistanceUnit {
                    headerNumber(value: heroValue, unit: heroUnit, caption: Text("Distance"))
                }
                headerNumber(value: presentation.durationClockText, unit: nil, caption: Text("Duration"))
                Spacer(minLength: 0)
            }
        }
    }

    private func headerNumber(value: String, unit: String?, caption: Text) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: fontDesign))
                    .foregroundColor(ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.system(size: 16, weight: .semibold, design: fontDesign))
                        .foregroundColor(ink.primary(0.85))
                }
            }
            caption
                .font(.system(size: 12, weight: .semibold, design: fontDesign))
                .foregroundColor(ink.primary(0.6))
        }
    }

    // MARK: - Route

    /// The same painter the share card uses, in a square region so the projection isn't
    /// distorted. A workout with no trace (or with Hide Route on) shows the type glyph
    /// instead — unless that's hidden too, in which case the section collapses and the
    /// header's chip is left carrying the workout's identity.
    @ViewBuilder
    private var routeSection: some View {
        if showsTrace {
            WorkoutShareRouteTrace(
                routePoints: routePoints,
                ribbon: ribbon,
                routeColor: routeColor,
                bottomAnchored: true,
                shadowColor: ink.legibilityShadow
            )
            .frame(width: Self.width - Self.margin * 2, height: Self.width - Self.margin * 2)
            .accessibilityHidden(true)
        } else if !iconHidden {
            Image(systemName: type.symbolName)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ink.primary)
                .shadow(color: ink.legibilityShadow, radius: 5, x: 0, y: 1.5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
                .accessibilityLabel(Text(type.displayName))
        }
    }

    // MARK: - Tiles

    /// Two columns of the detail page's own tiles, comparison badges and all. Chunked
    /// by hand rather than with a `LazyVGrid`: this tree is rasterized under a nil
    /// height proposal, and a lazy container has no business guessing at that.
    private var tileGrid: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(tileRows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row, id: \.kind) { tile in
                        BodyWorkoutDetailMetricTile(
                            title: tile.title,
                            value: tile.value,
                            comparison: tile.comparison
                        )
                    }
                    // Keeps a lone trailing tile in the left column instead of
                    // stretching it across the width.
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    private var tileRows: [[WorkoutDetailMetric]] {
        stride(from: 0, to: tiles.count, by: 2).map { start in
            Array(tiles[start..<min(start + 2, tiles.count)])
        }
    }

    // MARK: - Charts

    /// The detail page's cards, in the detail page's order, each drawn when the policy
    /// says so. `floatingCallout: nil` throughout — nothing is scrubbing a still image.
    @ViewBuilder
    private var chartSections: some View {
        if sections.heartRate {
            BodyWorkoutHeartRateChartCard(
                samples: heartRateSamples,
                maxHeartRate: maxHeartRate,
                floatingCallout: nil
            )
        }
        if sections.showsPaceCard {
            BodyWorkoutPaceCard(
                presentation: sections.pace ? paceOrSpeed : nil,
                splits: sections.splits ? splits : nil,
                floatingCallout: nil
            )
        }
        if sections.elevation, let elevation {
            BodyWorkoutElevationLineCard(presentation: elevation, floatingCallout: nil)
        }
        if sections.cadence, let cadence {
            BodyWorkoutBucketedSeriesCard(presentation: cadence, floatingCallout: nil)
        }
        if sections.power, let power {
            BodyWorkoutBucketedSeriesCard(presentation: power, floatingCallout: nil)
        }
        if sections.strideLength, let strideLength {
            BodyWorkoutBucketedSeriesCard(presentation: strideLength, floatingCallout: nil)
        }
        if sections.groundContact, let groundContact {
            BodyWorkoutBucketedSeriesCard(presentation: groundContact, floatingCallout: nil)
        }
        if sections.verticalOscillation, let verticalOscillation {
            BodyWorkoutBucketedSeriesCard(presentation: verticalOscillation, floatingCallout: nil)
        }
    }

    // MARK: - Branding

    /// The share card's wordmark at the same size, pinned to the bottom of however tall
    /// this image turned out. Same attribution extension as the share card, but with no
    /// width cap on `@name` — the long image is a fixed 360 pt wide with no metrics
    /// sharing the row, so there's no budget to protect.
    private var branding: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image("BodyIcon01")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .accessibilityHidden(true)
                // verbatim: brand wordmark, never localized — see the share card.
                Text(verbatim: "ohmybody")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(ink.primary(0.6))
            }
            .layoutPriority(1)
            .fixedSize()

            if !attribution.isEmpty {
                if attribution.showsSeparator {
                    // verbatim: see the share card's branding.
                    Text(verbatim: "–")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(ink.primary(0.6))
                }

                if let avatar = attribution.avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(ink.primary(0.3), lineWidth: 1)
                        )
                        .accessibilityHidden(true)
                        .layoutPriority(1)
                        .fixedSize()
                }

                if let name = attribution.name {
                    // verbatim: see the share card's branding.
                    Text(verbatim: "@" + name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(ink.primary(0.6))
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview("Long image") {
    let workout = WorkoutSummary(
        type: .running,
        startDate: Date(timeIntervalSince1970: 1_700_000_000),
        duration: 1_920,
        activeEnergyKilocalories: 412,
        distanceMeters: 8_200,
        averageHeartRateBeatsPerMinute: 154
    )
    let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
    let coordinates: [RouteCoordinate] = (0..<40).map { index in
        let t = Double(index) / 39
        return RouteCoordinate(
            latitude: 37.3230 + 0.010 * sin(t * .pi * 2),
            longitude: -122.0322 + 0.012 * t,
            speed: 3,
            altitude: 40 + 160 * t
        )
    }
    return ScrollView {
        BodyWorkoutShareLongCardView(
            presentation: presentation,
            tiles: presentation.detailMetrics,
            routePoints: WorkoutShareRouteProjection.normalizedPoints(for: coordinates),
            route3D: WorkoutRoute3DProjection.projected(for: coordinates),
            dimension: .twoD,
            iconHidden: false,
            locality: "Cupertino",
            type: .running,
            palette: .builtIn,
            preset: .midnight,
            fontDesign: .rounded,
            routeColor: BodyWorkoutShareCardView.defaultRouteColor,
            sections: WorkoutShareLongImageSections.Visibility(),
            heartRateSamples: [],
            maxHeartRate: nil,
            paceOrSpeed: nil,
            splits: nil,
            elevation: nil,
            cadence: nil,
            power: nil,
            strideLength: nil,
            groundContact: nil,
            verticalOscillation: nil
        )
    }
    .environment(\.colorScheme, .dark)
}
