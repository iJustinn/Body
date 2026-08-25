//
//  WorkoutShareRenderTests.swift
//  BodyTests
//
//  Smoke test for the share card's rasterization: proves `ImageRenderer` produces a
//  non-nil image at the exact pixel size for every layout and aspect ratio, and that
//  the route Canvas actually draws (route-blue pixels appear over a dark preset). Not
//  a snapshot test.
//

import XCTest
import SwiftUI
import CoreGraphics
import UIKit
@testable import Body

@MainActor
final class WorkoutShareRenderTests: XCTestCase {
    private func fixtureWorkout() -> WorkoutSummary {
        WorkoutSummary(
            type: .running,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 1_920,
            activeEnergyKilocalories: 412,
            distanceMeters: 8_200,
            averageHeartRateBeatsPerMinute: 154
        )
    }

    /// A diagonal route: normalized, it spans the unit square corner to corner, so the
    /// stroke crosses the whole route region wherever that region is placed.
    private func fixtureCoordinates() -> [RouteCoordinate] {
        (0..<40).map { index in
            let t = Double(index) / 39
            return RouteCoordinate(
                latitude: 37.3000 + 0.020 * t,
                longitude: -122.1000 + 0.020 * t,
                speed: 3
            )
        }
    }

    /// A due-east route at constant latitude, so every projected point sits at y 0.5 —
    /// the ground trace is a horizontal line whose bottom-anchored position is exactly
    /// the drawing rect's bottom edge. Its altitudes are two fixes at 0 m and eight at
    /// 100 m, which pins the trimmed percentile range to [0, 100] and so the ribbon's
    /// high points to a lift of 0.05 + 0.30 × 0.5 = 0.20 ground spans.
    private func flatFixtureCoordinates() -> [RouteCoordinate] {
        (0..<10).map { index in
            RouteCoordinate(
                latitude: 37.3000,
                longitude: -122.1000 + 0.004 * Double(index),
                speed: 3,
                altitude: index < 2 ? 0 : 100
            )
        }
    }

    /// A 360×640 image, red above the midline and green below it — so a photo transform
    /// that actually moved the backdrop shows a different half at a given card row.
    private func twoToneImage() -> UIImage {
        let size = CGSize(width: 360, height: 640)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
        }
    }

    private func makeRenderer(
        layout: WorkoutShareCardLayout = .centered,
        infoTransform: WorkoutShareInfoTransform = .identity,
        withRoute: Bool = true,
        coordinates: [RouteCoordinate]? = nil,
        dimension: WorkoutShareRouteDimension = .twoD,
        background: WorkoutShareCardBackground = .preset(.midnight),
        photoTransform: WorkoutSharePhotoTransform = .identity,
        fontDesign: Font.Design = .rounded,
        routeColor: Color = BodyWorkoutShareCardView.defaultRouteColor,
        aspectRatio: WorkoutShareAspectRatio = .portrait9x16,
        arrangement: WorkoutShareLandscapeArrangement = .stacked,
        centeredMetrics: [WorkoutShareMetric]? = nil,
        iconHidden: Bool = false,
        attribution: WorkoutShareAttribution = .empty,
        /// What the sheet's exporter picks from the resolved ink: `.dark` for the
        /// dark-backed backgrounds every existing sweep uses, `.light` for Daylight.
        colorScheme: ColorScheme = .dark
    ) -> ImageRenderer<some View> {
        let workout = fixtureWorkout()
        let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
        let isRouteless = layout == .routeless
        let routeCoordinates = coordinates ?? fixtureCoordinates()
        let card = BodyWorkoutShareCardView(
            presentation: presentation,
            metrics: isRouteless ? [] : WorkoutShareMetricsBuilder.metrics(for: presentation, type: workout.type),
            centeredMetrics: centeredMetrics ?? (isRouteless
                ? WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: workout.type)
                : WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: workout.type)),
            routePoints: withRoute ? WorkoutShareRouteProjection.normalizedPoints(for: routeCoordinates) : nil,
            route3D: withRoute ? WorkoutRoute3DProjection.projected(for: routeCoordinates) : nil,
            dimension: dimension,
            iconHidden: iconHidden,
            locality: "Cupertino",
            type: workout.type,
            palette: .builtIn,
            background: background,
            layout: layout,
            aspectRatio: aspectRatio,
            arrangement: arrangement,
            infoTransform: infoTransform,
            photoTransform: photoTransform,
            fontDesign: fontDesign,
            routeColor: routeColor,
            attribution: attribution
        )
        let renderer = ImageRenderer(
            content: card
                .frame(width: aspectRatio.cardSize.width, height: aspectRatio.cardSize.height)
                .environment(\.colorScheme, colorScheme)
                .dynamicTypeSize(.large)
        )
        renderer.scale = 3
        return renderer
    }

    func testCardRendersToExactPixelSize() throws {
        let renderer = makeRenderer()
        let image = try XCTUnwrap(renderer.uiImage, "ImageRenderer produced no image")
        let cgImage = try XCTUnwrap(image.cgImage, "Rendered image had no backing CGImage")

        // Assert the true pixel dimensions (points × scale), not the point size. 9:16 is
        // the default ratio, so this stays pinned to the original 1080×1920 literal.
        XCTAssertEqual(cgImage.width, 1_080)
        XCTAssertEqual(cgImage.height, 1_920)
    }

    /// The classic layout is a different view tree (header + bottom row), so it gets its
    /// own size assertion — a layout that overflowed its frame would still be clipped, but
    /// a broken tree that fails to render wouldn't be caught by the centered test.
    func testClassicLayoutRendersToExactPixelSize() throws {
        let renderer = makeRenderer(layout: .classic)
        let image = try XCTUnwrap(renderer.uiImage, "ImageRenderer produced no image")
        let cgImage = try XCTUnwrap(image.cgImage, "Rendered image had no backing CGImage")

        XCTAssertEqual(cgImage.width, 1_080)
        XCTAssertEqual(cgImage.height, 1_920)
    }

    /// The route-less layout is a third view tree (glyph + metric stack, no header, no
    /// trace) — same reasoning as the classic layout's own size test above.
    func testRoutelessLayoutRendersToExactPixelSize() throws {
        let renderer = makeRenderer(layout: .routeless, withRoute: false)
        let image = try XCTUnwrap(renderer.uiImage, "ImageRenderer produced no image")
        let cgImage = try XCTUnwrap(image.cgImage, "Rendered image had no backing CGImage")

        XCTAssertEqual(cgImage.width, 1_080)
        XCTAssertEqual(cgImage.height, 1_920)
    }

    /// The route-less card's only identity is the workout-type SF Symbol drawn above the
    /// metric stack. The fixture (running, with energy recorded) produces 3 metrics, so
    /// the glyph+stack block is centered at card y 320 the same way the plan's geometry
    /// describes. Rather than pin the glyph's exact frame (a layout tweak would silently
    /// break that), this samples a generous band above the stack's vertical center and
    /// just requires it isn't empty — the flat black Midnight background otherwise makes
    /// any non-black pixel proof the glyph rasterized.
    func testRoutelessGlyphAreaRasterizesOverDarkPreset() throws {
        let renderer = makeRenderer(layout: .routeless, withRoute: false)
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        let scale: CGFloat = 3
        // Card points: x 150–210 is centered on the 360 pt card; y 100–260 covers the
        // upper-center band above the metric stack's y 320 anchor, generous enough to
        // catch the glyph regardless of the exact block height for 3 metrics.
        let region = CGRect(x: 150, y: 100, width: 60, height: 160)
        let pixelRegion = CGRect(
            x: region.minX * scale,
            y: region.minY * scale,
            width: region.width * scale,
            height: region.height * scale
        ).intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        XCTAssertTrue(
            Self.containsNonBlackPixel(in: cgImage, region: pixelRegion),
            "Glyph area over Midnight had no non-black pixels — the type symbol did not rasterize"
        )
    }

    /// Same premise as `testRoutelessGlyphAreaRasterizesOverDarkPreset`, `iconHidden:
    /// true`: the block recenters around the same point, so hiding the glyph only
    /// reclaims the top half of the space it and its gap used (the block's center is
    /// fixed, so the bottom half of that space is exactly where the metrics now start).
    /// That reclaimed band — strictly between the shown block's old top and the hidden
    /// block's new top — must be empty over Midnight.
    func testRoutelessGlyphAreaIsEmptyWhenIconHidden() throws {
        let renderer = makeRenderer(layout: .routeless, withRoute: false, iconHidden: true)
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        let workout = fixtureWorkout()
        let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
        let metricCount = WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: workout.type).count
        let geo = WorkoutShareCardGeometry(
            aspectRatio: .portrait9x16, layout: .routeless, arrangement: .stacked, metricCount: metricCount
        )
        // 9:16 keeps the route-less block on the card's own vertical center (the axis
        // is `.vertical` there — see `testRoutelessRowsWrapOnlyOnTheNarrowCards`).
        let centerY = geo.size.height / 2
        let shownTop = centerY - (Self.routelessGlyphHeight + Self.routelessGlyphGap + geo.metricContentHeight) / 2
        let hiddenTop = centerY - geo.metricContentHeight / 2
        let vacatedHeight = hiddenTop - shownTop
        XCTAssertGreaterThan(vacatedHeight, 4, "test's own geometry math left no band to sample")

        let region = Self.pixelRect(
            x: 100, y: shownTop + 2, width: 160, height: vacatedHeight - 4, in: cgImage
        )
        XCTAssertFalse(
            Self.containsNonBlackPixel(in: cgImage, region: region),
            "Vacated glyph band had non-black pixels with the icon hidden"
        )

        // A hidden glyph shrinks the block but doesn't move it off-screen: the metrics
        // starting at the new top, and the pinned branding strip below them, still draw.
        let belowVacatedBand = Self.pixelRect(
            x: 0, y: hiddenTop, width: 360, height: geo.size.height - hiddenTop, in: cgImage
        )
        XCTAssertTrue(
            Self.containsNonBlackPixel(in: cgImage, region: belowVacatedBand),
            "Metrics/branding didn't draw below the vacated glyph band"
        )
    }

    func testRouteAreaRasterizesOverDarkPreset() throws {
        let renderer = makeRenderer()
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        // The centered layout's route region, taken from the card's own geometry and
        // scaled to pixels, so moving the region can't silently leave this test sampling
        // empty background. The diagonal fixture route spans the region corner to corner.
        let sample = Self.centeredRouteRegionInPixels(of: cgImage)
        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: sample),
            "Route trace region had no route-blue pixels — the Canvas did not rasterize"
        )
    }

    /// The export has to match the preview, so a moved info block must actually move the
    /// trace's pixels rather than just be accepted by the card's initializer. 300 pt is
    /// more than the 260 pt region is tall, so the shifted and default bands are
    /// disjoint. The bottom-pinned branding does land inside the shifted band, but it's
    /// white — never route blue — so it can't satisfy the check on its own.
    func testOffsetInfoTransformMovesTheRouteTrace() throws {
        let offset = CGSize(width: 0, height: 300)
        let renderer = makeRenderer(infoTransform: WorkoutShareInfoTransform(offset: offset, scale: 1))
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: Self.centeredRouteRegionInPixels(of: cgImage, offsetBy: offset)),
            "Route trace did not follow the info transform's offset"
        )
        XCTAssertFalse(
            Self.containsRouteBluePixel(in: cgImage, region: Self.centeredRouteRegionInPixels(of: cgImage)),
            "Route trace still drew in its default region despite the offset"
        )
    }

    // MARK: - Bottom-anchored route

    /// The centered layout pins the route's lowest drawn point to the drawing rect's
    /// bottom edge (y 288), so the gap to the metric stack is the same for a tall route
    /// and a flat one. The flat fixture projects to a horizontal line at y 0.5, which
    /// unanchored would draw at card y ≈ 117 — a third of the card higher.
    func testFlatRouteIsBottomAnchoredToTheDrawingRect() throws {
        let renderer = makeRenderer(coordinates: flatFixtureCoordinates())
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: Self.pixelRect(x: 60, y: 282, width: 240, height: 6, in: cgImage)),
            "Flat route did not draw just above the drawing rect's bottom edge"
        )
        XCTAssertFalse(
            // Stops short of the pinned branding, whose app-icon artwork is blue.
            Self.containsRouteBluePixel(in: cgImage, region: Self.pixelRect(x: 0, y: 300, width: 360, height: 280, in: cgImage)),
            "Route drew below the drawing rect's bottom edge"
        )
        XCTAssertFalse(
            Self.containsRouteBluePixel(in: cgImage, region: Self.pixelRect(x: 0, y: 60, width: 360, height: 200, in: cgImage)),
            "Route still drew in its unanchored, vertically centered position"
        )
    }

    // MARK: - Branding watermark

    /// No probe existed for the branding strip before the watermark shrank (18/15 →
    /// 15/13 pt icon/wordmark) — every other render test deliberately stops above it
    /// (see the comment above). This proves the shrunk mark still draws: a broad
    /// bottom-center band spanning the whole 56 pt branding zone must not be all
    /// background over the flat Midnight preset.
    func testBrandingWatermarkRasterizesInTheZone() throws {
        let renderer = makeRenderer()
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        // Card points: x 108–252 is the middle 40% of the 360 pt card's width, y
        // 584–640 is the full 56 pt branding zone at the card's bottom edge.
        let region = Self.pixelRect(x: 108, y: 584, width: 144, height: 56, in: cgImage)
        XCTAssertTrue(
            Self.containsNonBlackPixel(in: cgImage, region: region),
            "Branding zone had no non-background pixels — the shrunk watermark did not rasterize"
        )
    }

    // MARK: - 3D ribbon

    /// The ribbon lifts the flat fixture's high points 0.20 ground spans — 0.20 × 236 ≈
    /// 47 pt — above the bottom-anchored ground line at y 288, so its lit top edge lands
    /// near card y 241. The 2D fallback draws only at y 288, which is what makes this
    /// test fail rather than silently pass if the card ever ignores `.threeD`.
    func testThreeDRibbonDrawsALiftedLineTheFlatTraceNeverReaches() throws {
        let threeD = try XCTUnwrap(makeRenderer(coordinates: flatFixtureCoordinates(), dimension: .threeD).uiImage?.cgImage)
        let liftedBand = Self.pixelRect(x: 150, y: 235, width: 100, height: 12, in: threeD)
        XCTAssertTrue(
            Self.containsRouteBluePixel(in: threeD, region: liftedBand),
            "3D ribbon drew no lifted line above the ground trace"
        )

        let twoD = try XCTUnwrap(makeRenderer(coordinates: flatFixtureCoordinates(), dimension: .twoD).uiImage?.cgImage)
        XCTAssertFalse(
            Self.containsRouteBluePixel(in: twoD, region: liftedBand),
            "The 2D trace drew where only the lifted ribbon should reach"
        )
    }

    func testThreeDCardRendersToExactPixelSize() throws {
        let renderer = makeRenderer(coordinates: flatFixtureCoordinates(), dimension: .threeD)
        let cgImage = try XCTUnwrap(renderer.uiImage?.cgImage)

        XCTAssertEqual(cgImage.width, 1_080)
        XCTAssertEqual(cgImage.height, 1_920)
    }

    /// A route with no altitude can't project a ribbon, so `.threeD` falls back to the
    /// flat trace rather than drawing nothing.
    func testThreeDWithoutAltitudeStillDrawsTheFlatTrace() throws {
        let renderer = makeRenderer(dimension: .threeD)
        let cgImage = try XCTUnwrap(renderer.uiImage?.cgImage)

        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: Self.centeredRouteRegionInPixels(of: cgImage)),
            "A 3D card with no usable altitude drew no route at all"
        )
    }

    // MARK: - Font and route colour

    /// Serif and monospaced digits are wider than the rounded default; the metric values
    /// shrink to fit rather than pushing the card past its fixed 360×640.
    func testSerifCardRendersToExactPixelSize() throws {
        let renderer = makeRenderer(fontDesign: .serif)
        let cgImage = try XCTUnwrap(renderer.uiImage?.cgImage)

        XCTAssertEqual(cgImage.width, 1_080)
        XCTAssertEqual(cgImage.height, 1_920)
    }

    /// The route colour reaches the Canvas, not just the initializer: a white route over
    /// Midnight leaves near-white pixels where the default blue never would.
    func testWhiteRouteColorDrawsWhitePixelsInTheRouteRegion() throws {
        let renderer = makeRenderer(routeColor: .white)
        let cgImage = try XCTUnwrap(renderer.uiImage?.cgImage)
        let region = Self.centeredRouteRegionInPixels(of: cgImage)

        XCTAssertTrue(
            Self.containsPixel(in: cgImage, region: region) { red, green, blue in
                red > 200 && green > 200 && blue > 200
            },
            "White route colour produced no near-white pixels in the route region"
        )
        XCTAssertFalse(
            Self.containsRouteBluePixel(in: cgImage, region: region),
            "Route still drew in the default blue despite a white route colour"
        )
    }

    // MARK: - Photo transform

    /// The photo transform has to move the backdrop's pixels, not just be accepted by the
    /// card. At scale 2 the two-tone image's midline sits at card y 320; sliding it down
    /// 160 pt moves that boundary to y 480, so a row at y 400 flips from green to red.
    /// Sampled at the card's left edge, clear of the metric stack's white text.
    func testPhotoTransformOffsetMovesTheBackdrop() throws {
        let photo = twoToneImage()

        let centered = try XCTUnwrap(
            makeRenderer(
                background: .photo(photo),
                photoTransform: WorkoutSharePhotoTransform(offset: .zero, scale: 2)
            ).uiImage?.cgImage
        )
        let sample = Self.pixelRect(x: 4, y: 390, width: 14, height: 20, in: centered)
        let centeredColor = Self.averageColor(in: centered, region: sample)
        XCTAssertGreaterThan(centeredColor.green, centeredColor.red, "Untranslated photo should show its lower (green) half at y 400")

        let shifted = try XCTUnwrap(
            makeRenderer(
                background: .photo(photo),
                photoTransform: WorkoutSharePhotoTransform(offset: CGSize(width: 0, height: 160), scale: 2)
            ).uiImage?.cgImage
        )
        let shiftedColor = Self.averageColor(in: shifted, region: sample)
        XCTAssertGreaterThan(shiftedColor.red, shiftedColor.green, "Photo transform's offset did not move the backdrop")
    }

    /// A landscape photo's `scaledToFill` overhang must survive until after the pan: the
    /// clamp lets a 1280×640 photo (fill width 1280 → 460 pt of overhang each side) slide
    /// by that much at scale 1, and clipping the fill to the card first would drag a bare
    /// strip in from the edge. Left half green, right half red: panned 400 pt right, the
    /// card's left edge must show the photo's green half, not the black card behind it.
    func testLandscapePhotoPannedByItsOverhangStillCoversTheCard() throws {
        let size = CGSize(width: 1_280, height: 640)
        let photo = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            UIColor.red.setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
        let transform = WorkoutSharePhotoTransform(offset: CGSize(width: 400, height: 0), scale: 1)
            .clamped(imageSize: size, cardSize: WorkoutShareAspectRatio.portrait9x16.cardSize)
        XCTAssertEqual(transform.offset.width, 400, accuracy: 0.001, "fixture pan must be inside the clamp")

        let image = try XCTUnwrap(
            makeRenderer(background: .photo(photo), photoTransform: transform).uiImage?.cgImage
        )
        // Left edge, mid-height: under the scrims' clear band and clear of the trace.
        let color = Self.averageColor(in: image, region: Self.pixelRect(x: 2, y: 310, width: 10, height: 20, in: image))
        XCTAssertGreaterThan(color.green, 0.5, "Panned photo left a bare strip at the card's edge")
        XCTAssertGreaterThan(color.green, color.red)
    }

    // MARK: - Aspect ratios

    /// Every ratio is 1080 px on its short side at scale 3 (`WorkoutShareAspectRatio`'s
    /// own doc comment); 9:16 is covered above, so this checks the other four.
    func testNewAspectRatiosRenderToExactPixelSize() throws {
        let expectations: [(ratio: WorkoutShareAspectRatio, width: Int, height: Int)] = [
            (.landscape16x9, 1_920, 1_080),
            (.portrait3x4, 1_080, 1_440),
            (.landscape4x3, 1_440, 1_080),
            (.square, 1_080, 1_080)
        ]
        for expectation in expectations {
            let cgImage = try XCTUnwrap(
                makeRenderer(aspectRatio: expectation.ratio).uiImage?.cgImage,
                "no image for \(expectation.ratio.rawValue)"
            )
            XCTAssertEqual(cgImage.width, expectation.width, "\(expectation.ratio.rawValue) width")
            XCTAssertEqual(cgImage.height, expectation.height, "\(expectation.ratio.rawValue) height")
        }
    }

    /// The classic layout is its own view tree (see `testClassicLayoutRendersToExactPixelSize`);
    /// this proves it also survives a landscape frame rather than only ever being exercised at 9:16.
    func testLandscapeClassicLayoutRendersToExactPixelSize() throws {
        let cgImage = try XCTUnwrap(makeRenderer(layout: .classic, aspectRatio: .landscape16x9).uiImage?.cgImage)
        XCTAssertEqual(cgImage.width, 1_920)
        XCTAssertEqual(cgImage.height, 1_080)
    }

    /// Same reasoning for the route-less layout.
    func testLandscapeRoutelessLayoutRendersToExactPixelSize() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(layout: .routeless, withRoute: false, aspectRatio: .landscape16x9).uiImage?.cgImage
        )
        XCTAssertEqual(cgImage.width, 1_920)
        XCTAssertEqual(cgImage.height, 1_080)
    }

    /// Every ratio, route-less, in one sweep — the route-less card is the shortest view
    /// tree (glyph + stack, no header, no trace), so this is cheap insurance that none of
    /// the five shapes silently fails to render.
    func testAllRatiosRenderRoutelessToExactPixelSize() throws {
        for ratio in WorkoutShareAspectRatio.allCases {
            let cgImage = try XCTUnwrap(
                makeRenderer(layout: .routeless, withRoute: false, aspectRatio: ratio).uiImage?.cgImage,
                "no image for \(ratio.rawValue)"
            )
            XCTAssertEqual(cgImage.width, Int(ratio.cardSize.width * 3), "\(ratio.rawValue) width")
            XCTAssertEqual(cgImage.height, Int(ratio.cardSize.height * 3), "\(ratio.rawValue) height")
        }
    }

    /// `.sideBySide` is only meaningful on a landscape card with a trace: the route
    /// square sits in the left half and the metric column in the right half, and the two
    /// must never bleed into each other.
    func testSideBySideDrawsTheRouteInTheLeftHalfOnly() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(aspectRatio: .landscape16x9, arrangement: .sideBySide).uiImage?.cgImage
        )
        let leftHalf = Self.pixelRect(x: 0, y: 0, width: 320, height: 360, in: cgImage)
        let rightHalf = Self.pixelRect(x: 320, y: 0, width: 320, height: 360, in: cgImage)

        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: leftHalf),
            "Side-by-side route did not draw in the left half"
        )
        XCTAssertFalse(
            Self.containsRouteBluePixel(in: cgImage, region: rightHalf),
            "Side-by-side route leaked into the metrics half"
        )
    }

    /// `.routeOverRow` (a short, non-9:16, non-side-by-side card) stacks a route square
    /// above a metric row: the route must stay inside its own region, never touching the
    /// metrics below it. (The pinned branding zone isn't sampled here — its app-icon
    /// artwork is itself blue, the same confound `testFlatRouteIsBottomAnchoredToTheDrawingRect`
    /// works around; `WorkoutShareCardTests.testRouteOverRowMetricsSitAboveTheBrandingZone`
    /// covers that clearance at the geometry level instead.)
    func testRouteOverRowKeepsTheRouteAboveTheMetricsRow() throws {
        let cgImage = try XCTUnwrap(makeRenderer(aspectRatio: .square).uiImage?.cgImage)
        let geometry = WorkoutShareCardGeometry(aspectRatio: .square, layout: .centered, arrangement: .stacked)
        let routeRect = geometry.centeredRouteRect
        let metricsRect = geometry.metricsFrame

        let routePixels = Self.pixelRect(x: routeRect.minX, y: routeRect.minY, width: routeRect.width, height: routeRect.height, in: cgImage)
        let metricsPixels = Self.pixelRect(x: metricsRect.minX, y: metricsRect.minY, width: metricsRect.width, height: metricsRect.height, in: cgImage)

        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: routePixels),
            "Route-over-row layout drew no route inside its own region"
        )
        XCTAssertFalse(
            Self.containsRouteBluePixel(in: cgImage, region: metricsPixels),
            "Route bled into the metrics row"
        )
    }

    /// `WorkoutSharePhotoTransform.clamped(imageSize:cardSize:)` must clamp against the
    /// card it's actually being drawn on, not a fixed 9:16 assumption: a 360×640 photo on
    /// a 640×360 landscape card fills the width and overhangs on height, so a vertical pan
    /// should clamp to exactly that overhang.
    func testLandscapePhotoTransformClampsAgainstTheLandscapeCard() throws {
        let cardSize = WorkoutShareAspectRatio.landscape16x9.cardSize
        let photo = twoToneImage()

        let aspect = photo.size.width / photo.size.height
        let fillHeight = max(cardSize.height, cardSize.width / aspect)
        let expectedOverhang = max(0, (fillHeight - cardSize.height) / 2)

        let transform = WorkoutSharePhotoTransform(offset: CGSize(width: 0, height: expectedOverhang * 2), scale: 1)
            .clamped(imageSize: photo.size, cardSize: cardSize)
        XCTAssertEqual(transform.offset.height, expectedOverhang, accuracy: 0.001, "vertical pan should clamp to the fill's overhang")

        let cgImage = try XCTUnwrap(
            makeRenderer(background: .photo(photo), photoTransform: transform, aspectRatio: .landscape16x9).uiImage?.cgImage
        )
        XCTAssertEqual(cgImage.width, 1_920)
        XCTAssertEqual(cgImage.height, 1_080)
    }

    // MARK: - Five metrics

    /// A deliberate five-metric pick with the widest values the card realistically
    /// carries — a pace with a foot mark and a quote, and an hours-long clock — so the
    /// rows are exercised at the point where the blocks have to shrink to fit.
    private func fiveMetrics() -> [WorkoutShareMetric] {
        [
            WorkoutShareMetric(title: "Distance", value: "8.20 km"),
            WorkoutShareMetric(title: "Pace", value: "7'48\"/km"),
            WorkoutShareMetric(title: "Time", value: "1:23:45"),
            WorkoutShareMetric(title: "Active kcal", value: "412 kcal"),
            WorkoutShareMetric(title: "Avg HR", value: "154 bpm")
        ]
    }

    /// The route-less card stacks its 30 pt type glyph over the blocks with a 20 pt gap;
    /// the glyph's line box is estimated rather than pinned, which is why the probe bands
    /// below only cover the middle half of each row.
    private static let routelessGlyphHeight: CGFloat = 36
    private static let routelessGlyphGap: CGFloat = 20

    /// Where the first metric row's top edge lands, in card points — the one number the
    /// per-row probes need that the geometry doesn't state outright, because each of the
    /// card's four block sites anchors the grid differently (top-anchored in the column,
    /// exactly frame-sized over a row, centred in the side-by-side frame, and centred on
    /// a point with no trace above it).
    private func metricRowsTop(_ geometry: WorkoutShareCardGeometry, showsTrace: Bool) -> CGFloat {
        let brandingZone = WorkoutShareCardGeometry.brandingZoneHeight
        if geometry.layout == .routeless {
            let center = geometry.routelessMetricsAxis == .vertical
                ? geometry.size.height / 2
                : (geometry.size.height - brandingZone) / 2
            let block = Self.routelessGlyphHeight + Self.routelessGlyphGap + geometry.metricContentHeight
            return center - block / 2 + Self.routelessGlyphHeight + Self.routelessGlyphGap
        }
        guard showsTrace else {
            let center = geometry.centeredMode == .column
                ? geometry.size.height / 2
                : (geometry.size.height - brandingZone) / 2
            return center - geometry.metricContentHeight / 2
        }
        switch geometry.centeredMode {
        case .column, .routeOverRow:
            return geometry.metricsFrame.minY
        case .sideBySide:
            // The grid is centred in a frame that runs the card's full usable height.
            return geometry.metricsFrame.minY + (geometry.metricsFrame.height - geometry.metricContentHeight) / 2
        }
    }

    /// The middle half of each metric row, full card width — deliberately loose, since
    /// the exact glyph metrics of a row are the renderer's business and only "the row
    /// drew something here" is being asserted.
    private func metricRowBands(_ geometry: WorkoutShareCardGeometry, showsTrace: Bool) -> [CGRect] {
        let style = geometry.metricBlockStyle
        let top = metricRowsTop(geometry, showsTrace: showsTrace)
        return geometry.metricRowSizes.indices.map { index in
            let rowTop = top + CGFloat(index) * (style.rowHeight + style.rowGap)
            return CGRect(
                x: 12,
                y: rowTop + style.rowHeight * 0.25,
                width: geometry.size.width - 24,
                height: style.rowHeight * 0.5
            )
        }
    }

    /// Every shape a five-metric pick can land on: the card still rasterizes at its exact
    /// export size, every wrapped row actually draws, and the strip between the last row
    /// and the branding zone stays empty — the failure mode the row/grid logic exists to
    /// prevent is a block bleeding into the wordmark.
    func testFiveMetricCardsDrawEveryRowClearOfTheBranding() throws {
        let cases: [(
            name: String,
            ratio: WorkoutShareAspectRatio,
            arrangement: WorkoutShareLandscapeArrangement,
            layout: WorkoutShareCardLayout,
            withRoute: Bool,
            font: Font.Design
        )] = [
            // Compact two-row grid over a shrunken route square, in the widest type the
            // card offers — the min-scale path.
            ("square centered", .square, .stacked, .centered, true, .monospaced),
            ("9:16 column", .portrait9x16, .stacked, .centered, true, .rounded),
            ("4:3 side by side", .landscape4x3, .sideBySide, .centered, true, .rounded),
            ("16:9 stacked", .landscape16x9, .stacked, .centered, true, .rounded),
            ("square route-less", .square, .stacked, .routeless, false, .rounded),
            // A route that projects to nothing: centered layout, no trace, blocks only.
            ("square traceless centered", .square, .stacked, .centered, false, .rounded)
        ]

        for testCase in cases {
            let geometry = WorkoutShareCardGeometry(
                aspectRatio: testCase.ratio,
                layout: testCase.layout,
                arrangement: testCase.arrangement,
                metricCount: 5
            )
            let cgImage = try XCTUnwrap(
                makeRenderer(
                    layout: testCase.layout,
                    withRoute: testCase.withRoute,
                    fontDesign: testCase.font,
                    aspectRatio: testCase.ratio,
                    arrangement: testCase.arrangement,
                    centeredMetrics: fiveMetrics()
                ).uiImage?.cgImage,
                "no image for \(testCase.name)"
            )

            XCTAssertEqual(cgImage.width, Int(testCase.ratio.cardSize.width * 3), "\(testCase.name) width")
            XCTAssertEqual(cgImage.height, Int(testCase.ratio.cardSize.height * 3), "\(testCase.name) height")

            let showsTrace = testCase.withRoute && testCase.layout != .routeless
            let bands = metricRowBands(geometry, showsTrace: showsTrace)
            XCTAssertEqual(bands.count, geometry.metricRowSizes.count)
            for (index, band) in bands.enumerated() {
                XCTAssertTrue(
                    Self.containsNonBlackPixel(
                        in: cgImage,
                        region: Self.pixelRect(x: band.minX, y: band.minY, width: band.width, height: band.height, in: cgImage)
                    ),
                    "\(testCase.name) row \(index) (\(geometry.metricRowSizes[index]) blocks) drew nothing at \(band)"
                )
            }

            // 4 pt of slack for the rows' real glyph metrics, then everything down to the
            // branding zone has to be bare background.
            let contentBottom = metricRowsTop(geometry, showsTrace: showsTrace) + geometry.metricContentHeight + 4
            let brandingTop = geometry.size.height - WorkoutShareCardGeometry.brandingZoneHeight
            if brandingTop - contentBottom >= 4 {
                XCTAssertFalse(
                    Self.containsNonBlackPixel(
                        in: cgImage,
                        region: Self.pixelRect(
                            x: 0,
                            y: contentBottom,
                            width: geometry.size.width,
                            height: brandingTop - contentBottom,
                            in: cgImage
                        )
                    ),
                    "\(testCase.name) drew into the strip above the branding zone"
                )
            }
        }
    }

    /// With five blocks the route square gives up height to the rows, so the trace has to
    /// follow it — it must still rasterize inside the (smaller) region the geometry moved
    /// it to, and never below the metrics' top edge.
    func testFiveMetricRouteStaysAboveTheMetricRows() throws {
        for ratio in [WorkoutShareAspectRatio.square, .portrait9x16, .landscape16x9] {
            let geometry = WorkoutShareCardGeometry(
                aspectRatio: ratio,
                layout: .centered,
                arrangement: .stacked,
                metricCount: 5
            )
            let cgImage = try XCTUnwrap(
                makeRenderer(aspectRatio: ratio, centeredMetrics: fiveMetrics()).uiImage?.cgImage,
                "no image for \(ratio.rawValue)"
            )
            let route = geometry.centeredRouteRect
            XCTAssertLessThanOrEqual(
                route.maxY - WorkoutShareCardGeometry.routeInset,
                geometry.centeredMetricsTopY,
                "\(ratio.rawValue) route region overlaps the metric rows"
            )
            XCTAssertTrue(
                Self.containsRouteBluePixel(
                    in: cgImage,
                    region: Self.pixelRect(x: route.minX, y: route.minY, width: route.width, height: route.height, in: cgImage)
                ),
                "\(ratio.rawValue) drew no trace in its five-metric route region"
            )
            XCTAssertFalse(
                Self.containsRouteBluePixel(
                    in: cgImage,
                    region: Self.pixelRect(
                        x: 0,
                        y: geometry.centeredMetricsTopY,
                        width: geometry.size.width,
                        height: geometry.metricContentHeight,
                        in: cgImage
                    )
                ),
                "\(ratio.rawValue) route bled into the metric rows"
            )
        }
    }

    /// Side by side splits the card at the midline whatever the metric count is: five
    /// blocks wrap into three rows in the right half and never reach the trace.
    func testFiveMetricSideBySideKeepsTheRouteInTheLeftHalf() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(
                aspectRatio: .landscape4x3,
                arrangement: .sideBySide,
                centeredMetrics: fiveMetrics()
            ).uiImage?.cgImage
        )
        let geometry = WorkoutShareCardGeometry(
            aspectRatio: .landscape4x3,
            layout: .centered,
            arrangement: .sideBySide,
            metricCount: 5
        )
        XCTAssertEqual(geometry.metricRowSizes, [2, 2, 1])

        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: Self.pixelRect(x: 0, y: 0, width: 240, height: 360, in: cgImage)),
            "Five-metric side-by-side route did not draw in the left half"
        )
        XCTAssertFalse(
            Self.containsRouteBluePixel(in: cgImage, region: Self.pixelRect(x: 240, y: 0, width: 240, height: 360, in: cgImage)),
            "Five-metric side-by-side route leaked into the metrics half"
        )
    }

    /// Card points × the renderer's scale 3, clamped to the rendered image's actual pixel
    /// bounds — not a fixed 1080×1920 literal, since the card can now render at any of the
    /// five aspect ratios.
    // MARK: - Long image

    /// Heart-rate samples across the fixture workout, so the long image's heart-rate
    /// section has something to draw.
    private func fixtureHeartRateSamples(count: Int = 40) -> [WorkoutHeartRateSample] {
        let workout = fixtureWorkout()
        return (0..<count).map { index in
            WorkoutHeartRateSample(
                date: workout.startDate.addingTimeInterval(Double(index) / Double(count) * workout.duration),
                beatsPerMinute: 130 + Double(index % 20)
            )
        }
    }

    /// One distance sample every 10 s at a steady 3 m/s, for `unitCount` kilometres —
    /// the input the splits table is built from. 40 km is the tall-output stress case.
    private func fixtureSplitData(kilometers: Int) -> WorkoutSplitData {
        let start = fixtureWorkout().startDate
        let seconds = Double(kilometers) * 1_000 / 3
        let stepCount = Int(seconds / 10)
        let samples = (0..<stepCount).map { index in
            WorkoutDistanceSample(
                startDate: start.addingTimeInterval(Double(index) * 10),
                endDate: start.addingTimeInterval(Double(index + 1) * 10),
                meters: 30
            )
        }
        return WorkoutSplitData(distanceSamples: samples, segments: [], stepSamples: [])
    }

    /// The long image at scale 1 — the size pass the sheet's exporter also takes before
    /// it decides how far it can upscale.
    private func makeLongRenderer(
        selectedIDs: [String]? = nil,
        splitKilometers: Int = 5,
        heartRateSampleCount: Int = 40,
        withRoute: Bool = true,
        preset: BodyWorkoutSharePreset = .midnight,
        attribution: WorkoutShareAttribution = .empty,
        /// The exporter's scheme, which follows the preset's ink: the long image's chart
        /// cards are `colorScheme`-adaptive, so a Daylight export has to render `.light`
        /// or its tiles would stay dark-on-white.
        colorScheme: ColorScheme = .dark
    ) -> ImageRenderer<some View> {
        let workout = WorkoutSummary(
            type: .running,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: Double(splitKilometers) * 1_000 / 3,
            activeEnergyKilocalories: 412,
            distanceMeters: Double(splitKilometers) * 1_000,
            averageHeartRateBeatsPerMinute: 154,
            heartRateSamples: fixtureHeartRateSamples(count: heartRateSampleCount)
        )
        let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
        let available = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: workout.type)
        let ids = selectedIDs ?? available.map(\.id)
        let splits = WorkoutDetailChartPresentations.splits(
            workout: workout,
            splitData: fixtureSplitData(kilometers: splitKilometers),
            distanceUnitPreference: .kilometers
        )
        let sections = WorkoutShareLongImageSections.sections(
            available: available,
            selectedIDs: ids,
            data: WorkoutShareLongImageSections.Availability(
                heartRate: !presentation.heartRateSamples.isEmpty,
                splits: splits != nil
            )
        )
        let coordinates = fixtureCoordinates()
        let card = BodyWorkoutShareLongCardView(
            presentation: presentation,
            tiles: ids.compactMap { id in
                presentation.detailMetrics.first { WorkoutShareMetricOption.key(for: $0.kind) == id }
            },
            routePoints: withRoute ? WorkoutShareRouteProjection.normalizedPoints(for: coordinates) : nil,
            route3D: withRoute ? WorkoutRoute3DProjection.projected(for: coordinates) : nil,
            dimension: .twoD,
            iconHidden: false,
            locality: "Cupertino",
            type: workout.type,
            palette: .builtIn,
            preset: preset,
            fontDesign: .rounded,
            routeColor: BodyWorkoutShareCardView.defaultRouteColor,
            sections: sections,
            heartRateSamples: presentation.heartRateSamples,
            maxHeartRate: 190,
            paceOrSpeed: nil,
            splits: splits,
            elevation: nil,
            cadence: nil,
            power: nil,
            strideLength: nil,
            groundContact: nil,
            verticalOscillation: nil,
            attribution: attribution
        )
        let renderer = ImageRenderer(
            content: card
                .frame(width: BodyWorkoutShareLongCardView.width)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, colorScheme)
                .dynamicTypeSize(.large)
                .transaction { $0.disablesAnimations = true }
        )
        renderer.proposedSize = ProposedViewSize(width: BodyWorkoutShareLongCardView.width, height: nil)
        renderer.scale = 1
        return renderer
    }

    /// The long image is exactly the card's width and taller than any card ratio, and
    /// its wordmark is the last thing on it.
    func testLongImageRendersAtCardWidthAndNaturalHeight() throws {
        let renderer = makeLongRenderer()
        let image = try XCTUnwrap(renderer.uiImage, "ImageRenderer produced no long image")
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, Int(BodyWorkoutShareLongCardView.width))
        XCTAssertGreaterThan(
            cgImage.height,
            Int(WorkoutShareAspectRatio.portrait9x16.cardSize.height),
            "the long image should be taller than the tallest card"
        )

        // The wordmark sits in the branding zone at the very bottom, centred — the only
        // ink down there over Midnight's flat black.
        let brandingBand = CGRect(
            x: 0.3 * CGFloat(cgImage.width),
            y: CGFloat(cgImage.height) - WorkoutShareCardGeometry.brandingZoneHeight,
            width: 0.4 * CGFloat(cgImage.width),
            height: WorkoutShareCardGeometry.brandingZoneHeight
        )
        XCTAssertTrue(
            Self.containsNonBlackPixel(in: cgImage, region: brandingBand),
            "the branding strip at the bottom of the long image had no ink"
        )
    }

    /// The long image's branding row has no metrics sharing it, so attribution only
    /// needs to prove it renders without breaking the natural-height layout.
    func testLongImageWithAttributionRendersAtCardWidth() throws {
        let renderer = makeLongRenderer(
            attribution: WorkoutShareAttribution(avatar: solidAvatarImage(), name: "Justin")
        )
        let cgImage = try XCTUnwrap(renderer.uiImage?.cgImage, "ImageRenderer produced no long image")

        XCTAssertEqual(cgImage.width, Int(BodyWorkoutShareLongCardView.width))
    }

    /// A deselected chip takes its whole section off the image: the policy says so, and
    /// the raster gets shorter by more than a rounding error because of it.
    func testDeselectingAChipRemovesItsLongImageSection() throws {
        let workout = fixtureWorkout()
        let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
        let available = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: workout.type)
        let withoutHeartRate = available.map(\.id).filter { $0 != "avgHeartRate" && $0 != "maxHeartRate" }

        // The policy's answer first — the raster only confirms it took effect.
        let sections = WorkoutShareLongImageSections.sections(
            available: available,
            selectedIDs: withoutHeartRate,
            data: WorkoutShareLongImageSections.Availability(heartRate: true, splits: true)
        )
        XCTAssertFalse(sections.heartRate)
        XCTAssertTrue(sections.splits)

        let full = try XCTUnwrap(makeLongRenderer().uiImage?.cgImage)
        let trimmed = try XCTUnwrap(makeLongRenderer(selectedIDs: withoutHeartRate).uiImage?.cgImage)

        XCTAssertEqual(trimmed.width, full.width)
        XCTAssertLessThan(
            trimmed.height,
            full.height - 200,
            "dropping the heart-rate chip should remove the whole heart-rate card, not just a tile"
        )
    }

    /// A workout with dozens of splits produces an image thousands of points tall. The
    /// exporter backs its scale off so the bitmap stays bounded, and only refuses — into
    /// the "Couldn't Create Image" alert — when even 1x wouldn't fit.
    func testTallLongImageClampsItsExportScale() throws {
        // The rule itself, at the heights that matter.
        XCTAssertEqual(BodyWorkoutShareSheet.longExportScale(forHeight: 640), 3)
        XCTAssertEqual(BodyWorkoutShareSheet.longExportScale(forHeight: 4_000), 3)
        XCTAssertEqual(try XCTUnwrap(BodyWorkoutShareSheet.longExportScale(forHeight: 6_000)), 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(BodyWorkoutShareSheet.longExportScale(forHeight: 12_000)), 1, accuracy: 0.0001)
        XCTAssertNil(
            BodyWorkoutShareSheet.longExportScale(forHeight: 20_000),
            "an image too tall to rasterize even at 1x must refuse rather than allocate"
        )
        XCTAssertNil(BodyWorkoutShareSheet.longExportScale(forHeight: 0))

        // And a real 40-split workout: very tall, still exportable, and its clamped
        // output stays inside the budget.
        let renderer = makeLongRenderer(splitKilometers: 40)
        let image = try XCTUnwrap(renderer.uiImage)
        let heightPoints = image.size.height
        XCTAssertGreaterThan(heightPoints, 1_500, "40 splits should produce a very tall image")

        let scale = try XCTUnwrap(BodyWorkoutShareSheet.longExportScale(forHeight: heightPoints))
        XCTAssertLessThanOrEqual(heightPoints * scale, 12_000)
    }

    // MARK: - Daylight ink polarity
    //
    // Every sweep above stays pinned to Midnight, whose "empty band is black"
    // assertions are the inverse of what a white card produces. These are targeted
    // probes instead: the Daylight card must be near-white where nothing drew, and
    // carry near-black ink where the light presets carry white.

    /// A flat, single-colour 360×640 backdrop — a "photo" whose every pixel is known,
    /// so a probe can tell the card's own ink apart from the picture behind it.
    private func flatImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 360, height: 640)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// The Daylight 9:16 card: white where nothing drew, black ink in the metric stack,
    /// and the route still in its own colour (the trace is the user's pick, not ink).
    func testDaylightCardDrawsDarkInkOnAWhiteCard() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(background: .preset(.daylight), colorScheme: .light).uiImage?.cgImage
        )

        // A corner the card never draws in: Daylight's flat white, scrim included.
        let corner = Self.averageColor(in: cgImage, region: Self.pixelRect(x: 0, y: 0, width: 20, height: 20, in: cgImage))
        XCTAssertGreaterThan(corner.red, 240, "the Daylight card's corner was not near-white")
        XCTAssertGreaterThan(corner.green, 240)
        XCTAssertGreaterThan(corner.blue, 240)

        XCTAssertTrue(
            Self.containsNearBlackPixel(
                in: cgImage,
                region: Self.pixelRect(x: 30, y: 335, width: 300, height: 225, in: cgImage)
            ),
            "the Daylight card's metric stack had no dark ink — the text is still white on white"
        )

        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: Self.centeredRouteRegionInPixels(of: cgImage)),
            "the route trace did not draw on the Daylight card"
        )
    }

    /// The route-less tree (type glyph + stack, no trace) flips too — its glyph is the
    /// card's only identity, so a white one on a white card would erase it.
    func testDaylightRoutelessCardDrawsDarkInk() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(
                layout: .routeless,
                withRoute: false,
                background: .preset(.daylight),
                colorScheme: .light
            ).uiImage?.cgImage
        )

        // The same band `testRoutelessGlyphAreaRasterizesOverDarkPreset` samples, read
        // the other way round: dark ink on white rather than any ink on black.
        XCTAssertTrue(
            Self.containsNearBlackPixel(
                in: cgImage,
                region: Self.pixelRect(x: 150, y: 100, width: 60, height: 160, in: cgImage)
            ),
            "the Daylight route-less card's type glyph did not draw in dark ink"
        )

        let corner = Self.averageColor(in: cgImage, region: Self.pixelRect(x: 0, y: 0, width: 20, height: 20, in: cgImage))
        XCTAssertGreaterThan(corner.red, 240, "the Daylight route-less card's corner was not near-white")
    }

    /// Five metrics take the grid path (uniform block sizing plus the grid's own
    /// shadow), which is a different set of colour literals from the three-block stack.
    func testDaylightFiveMetricCardDrawsDarkInk() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(
                background: .preset(.daylight),
                centeredMetrics: fiveMetrics(),
                colorScheme: .light
            ).uiImage?.cgImage
        )

        // Five compact rows on 9:16 run from card y 238 to 572 (the geometry shrinks the
        // route square to make room); sample well inside that.
        XCTAssertTrue(
            Self.containsNearBlackPixel(
                in: cgImage,
                region: Self.pixelRect(x: 30, y: 250, width: 300, height: 310, in: cgImage)
            ),
            "the Daylight five-metric grid had no dark ink"
        )
    }

    /// The wordmark alone, not the whole branding strip: `BodyIcon01` is a colourful
    /// asset that draws the same on either ink, so a broad band probe would pass even
    /// with an invisible white-on-white "Body".
    func testDaylightWordmarkDrawsDarkInk() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(background: .preset(.daylight), colorScheme: .light).uiImage?.cgImage
        )

        // Card points: the branding HStack is centred on x 180 and its bottom edge sits
        // `brandingBottomPadding` (26) above the card's, so x 180–202 is inside the
        // wordmark and clear of the icon to its left.
        XCTAssertTrue(
            Self.containsNearBlackPixel(
                in: cgImage,
                region: Self.pixelRect(x: 180, y: 600, width: 22, height: 12, in: cgImage),
                threshold: 150
            ),
            "the Daylight wordmark did not draw in dark ink"
        )
    }

    /// A small solid-colour square, standing in for a decoded profile photo — its exact
    /// pixels don't matter, only that something opaque and dark-edged lands where the
    /// avatar chip is drawn.
    private func solidAvatarImage(_ color: UIColor = .black) -> UIImage {
        let size = CGSize(width: 60, height: 60)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// With attribution set, the branding strip grows past the wordmark: a wide band to
    /// its right — background-only with no attribution (`testDaylightWordmarkAbsentAttributionLeavesBandBlank`
    /// below) — now carries the dash, avatar, and `@name`.
    func testDaylightAttributionDrawsDarkInkRightOfWordmark() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(
                background: .preset(.daylight),
                attribution: WorkoutShareAttribution(avatar: solidAvatarImage(), name: "Justin"),
                colorScheme: .light
            ).uiImage?.cgImage
        )

        XCTAssertTrue(
            Self.containsNearBlackPixel(
                in: cgImage,
                region: Self.pixelRect(x: 250, y: 600, width: 80, height: 12, in: cgImage),
                threshold: 150
            ),
            "the attribution did not draw in dark ink beside the wordmark"
        )
    }

    /// Turning the separator off takes the dash out of the branding row and nothing
    /// else: the same attribution renders, but the row's ink spans fewer pixels. A span
    /// rather than a fixed probe, because the row is centred — dropping a glyph shifts
    /// everything left of it, so no single point stays put between the two renders.
    func testHidingTheSeparatorNarrowsTheBrandingRow() throws {
        func brandingInkWidth(showsSeparator: Bool) throws -> Int {
            let cgImage = try XCTUnwrap(
                makeRenderer(
                    background: .preset(.daylight),
                    attribution: WorkoutShareAttribution(
                        avatar: solidAvatarImage(),
                        name: "Justin",
                        showsSeparator: showsSeparator
                    ),
                    colorScheme: .light
                ).uiImage?.cgImage
            )
            let band = Self.pixelRect(x: 0, y: 600, width: 360, height: 12, in: cgImage)
            return try XCTUnwrap(
                Self.nearBlackInkWidth(in: cgImage, region: band, threshold: 150),
                "the branding row drew no dark ink"
            )
        }

        let withDash = try brandingInkWidth(showsSeparator: true)
        let withoutDash = try brandingInkWidth(showsSeparator: false)

        XCTAssertLessThan(
            withoutDash, withDash,
            "hiding the separator should narrow the branding row by the dash's width"
        )
    }

    /// Control for the test above: the same render with no attribution leaves the wide
    /// right-of-wordmark band untouched — proving the ink there comes from the
    /// attribution, not from some other element drifting into the probe.
    func testDaylightWordmarkAbsentAttributionLeavesBandBlank() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(background: .preset(.daylight), attribution: .empty, colorScheme: .light).uiImage?.cgImage
        )

        XCTAssertFalse(
            Self.containsNearBlackPixel(
                in: cgImage,
                region: Self.pixelRect(x: 250, y: 600, width: 80, height: 12, in: cgImage),
                threshold: 150
            ),
            "the branding band right of the wordmark should be empty with no attribution"
        )
    }

    /// Ink follows the background that actually renders, never the stored preference: a
    /// photo is dark-backed by its scrims, so it keeps the light ink and the black
    /// legibility halo even when the tray still says Daylight. The block is moved off
    /// its default slot to prove the rule holds wherever it lands.
    func testBrightPhotoKeepsLightInkAndItsBlackShadow() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(
                infoTransform: WorkoutShareInfoTransform(offset: CGSize(width: 20, height: 30), scale: 1),
                withRoute: false,
                background: .photo(flatImage(.white)),
                colorScheme: .dark
            ).uiImage?.cgImage
        )

        // The moved metric stack, entirely inside the clear band between the scrims.
        let block = Self.pixelRect(x: 44, y: 250, width: 296, height: 200, in: cgImage)

        XCTAssertFalse(
            Self.containsNearBlackPixel(in: cgImage, region: block, threshold: 100),
            "the metrics over a white photo drew in dark ink — the background did not win"
        )
        // White text on a white photo is only visible through its halo, so a region that
        // is *uniformly* white means the black shadow stopped being drawn.
        XCTAssertTrue(
            Self.containsPixel(in: cgImage, region: block) { red, green, blue in
                red < 235 && green < 235 && blue < 235
            },
            "the black legibility shadow did not draw over a white photo"
        )
    }

    /// The map's composited snapshot is dark-backed by the classic layout's heavier
    /// scrims, so its header keeps white ink whatever preset is stored.
    func testMapBackgroundKeepsLightInk() throws {
        let cgImage = try XCTUnwrap(
            makeRenderer(layout: .classic, background: .map(flatImage(.white))).uiImage?.cgImage
        )

        XCTAssertTrue(
            Self.containsNearWhitePixel(
                in: cgImage,
                region: Self.pixelRect(x: 24, y: 88, width: 256, height: 24, in: cgImage)
            ),
            "the map card's title lost its white ink"
        )
    }

    /// The video overlay draws no background of its own — the frames come from under it
    /// — so it is light ink by the same rule, over transparency.
    func testVideoOverlayKeepsLightInk() throws {
        let cgImage = try XCTUnwrap(makeRenderer(background: .video).uiImage?.cgImage)

        XCTAssertTrue(
            Self.containsNearWhitePixel(
                in: cgImage,
                region: Self.pixelRect(x: 30, y: 335, width: 300, height: 225, in: cgImage)
            ),
            "the video overlay's metrics lost their white ink"
        )
    }

    /// The Daylight long image: near-white background, dark ink in the header band.
    func testDaylightLongImageDrawsDarkInkOnWhite() throws {
        let cgImage = try XCTUnwrap(
            makeLongRenderer(preset: .daylight, colorScheme: .light).uiImage?.cgImage
        )

        // Scale 1 here, so these are image pixels directly. The top-left corner is
        // inside the 24 pt margin — nothing but the preset's white.
        let corner = Self.averageColor(in: cgImage, region: CGRect(x: 0, y: 0, width: 12, height: 12))
        XCTAssertGreaterThan(corner.red, 240, "the Daylight long image's corner was not near-white")

        // The title, right of the 46 pt type chip and below the 28 pt top padding.
        XCTAssertTrue(
            Self.containsNearBlackPixel(in: cgImage, region: CGRect(x: 84, y: 30, width: 250, height: 26)),
            "the Daylight long image's header had no dark ink"
        )
    }

    /// The trace's legibility halo is a 2D-only contract: the flat polyline is stroked
    /// through a shadow filter, and the 3D ribbon deliberately draws bare (a halo on its
    /// filled quads would smear rather than outline). Both are rendered over the same
    /// flat mid-grey photo, where a black halo is measurable, and the band just below
    /// the shared bottom-anchored ground line is compared.
    func testFlatTraceIsHaloedAndTheThreeDRibbonIsNot() throws {
        let photo = flatImage(UIColor(white: 0.5, alpha: 1))
        let twoD = try XCTUnwrap(
            makeRenderer(coordinates: flatFixtureCoordinates(), background: .photo(photo)).uiImage?.cgImage
        )
        let threeD = try XCTUnwrap(
            makeRenderer(
                coordinates: flatFixtureCoordinates(),
                dimension: .threeD,
                background: .photo(photo)
            ).uiImage?.cgImage
        )

        // Just under the ground line at card y 288 (stroke half-width 2.5), still inside
        // the route Canvas, and above the metric stack at y 330.
        let band = Self.pixelRect(x: 100, y: 294, width: 160, height: 5, in: twoD)
        let flat = Self.averageColor(in: twoD, region: band)
        let ribbon = Self.averageColor(in: threeD, region: band)

        XCTAssertLessThan(
            flat.red, ribbon.red - 3,
            "the 2D trace drew no shadow below its stroke"
        )
        XCTAssertEqual(
            ribbon.red, 127.5, accuracy: 3,
            "the 3D ribbon grew a shadow — it draws bare by design; see WorkoutShareRouteTrace"
        )
    }

    private static func pixelRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, in cgImage: CGImage) -> CGRect {
        let scale: CGFloat = 3
        return CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
            .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    }

    /// `WorkoutShareCardGeometry(...).centeredRouteRect` (card points, optionally shifted
    /// by an info transform's offset) × the renderer's scale 3, clamped to the image so a
    /// future geometry change can't index out of bounds. Defaults to 9:16/stacked, which
    /// reproduces the original 260×260 region centered at (180, 170).
    private static func centeredRouteRegionInPixels(
        of cgImage: CGImage,
        aspectRatio: WorkoutShareAspectRatio = .portrait9x16,
        arrangement: WorkoutShareLandscapeArrangement = .stacked,
        offsetBy offset: CGSize = .zero
    ) -> CGRect {
        let scale: CGFloat = 3
        let rect = WorkoutShareCardGeometry(aspectRatio: aspectRatio, layout: .centered, arrangement: arrangement).centeredRouteRect
        let region = CGRect(
            x: (rect.minX + offset.width) * scale,
            y: (rect.minY + offset.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        return region.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    }

    /// Draws the CGImage into an RGBA8 buffer and scans `region` for a pixel matching the
    /// card's route stroke (#0128F4). The thresholds are loose on every channel because the
    /// stroke carries a shadow filter, which darkens and desaturates its edges — only the
    /// "mostly blue, little red/green" shape of the color is asserted, not the exact value.
    private static func containsRouteBluePixel(in cgImage: CGImage, region: CGRect) -> Bool {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let offset = y * bytesPerRow + x * 4
                if pixels[offset + 2] > 180, pixels[offset] < 90, pixels[offset + 1] < 120 {
                    return true
                }
            }
        }
        return false
    }

    /// Draws the CGImage into an RGBA8 buffer and scans `region` for any pixel matching
    /// `matches` — the general form of the colour probes above.
    private static func containsPixel(
        in cgImage: CGImage,
        region: CGRect,
        matches: (UInt8, UInt8, UInt8) -> Bool
    ) -> Bool {
        guard let pixels = rgbaPixels(of: cgImage) else { return false }
        let bytesPerRow = cgImage.width * 4
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let offset = y * bytesPerRow + x * 4
                if matches(pixels[offset], pixels[offset + 1], pixels[offset + 2]) {
                    return true
                }
            }
        }
        return false
    }

    /// Mean channel values over `region`, for probes that care about which of two flat
    /// colours fills an area rather than whether a thin stroke touched it.
    private static func averageColor(in cgImage: CGImage, region: CGRect) -> (red: Double, green: Double, blue: Double) {
        guard let pixels = rgbaPixels(of: cgImage) else { return (0, 0, 0) }
        let bytesPerRow = cgImage.width * 4
        var totals = (red: 0.0, green: 0.0, blue: 0.0)
        var count = 0.0
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let offset = y * bytesPerRow + x * 4
                totals.red += Double(pixels[offset])
                totals.green += Double(pixels[offset + 1])
                totals.blue += Double(pixels[offset + 2])
                count += 1
            }
        }
        guard count > 0 else { return (0, 0, 0) }
        return (totals.red / count, totals.green / count, totals.blue / count)
    }

    private static func rgbaPixels(of cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// The mirror of `containsNonBlackPixel` for the Daylight card: any pixel dark on
    /// every channel, i.e. the dark ink actually landed somewhere in `region`. A
    /// threshold rather than an exact match, because text is antialiased and the
    /// secondary strengths (`ink.primary(0.6)`) are greys, not black.
    private static func containsNearBlackPixel(in cgImage: CGImage, region: CGRect, threshold: UInt8 = 110) -> Bool {
        containsPixel(in: cgImage, region: region) { red, green, blue in
            red <= threshold && green <= threshold && blue <= threshold
        }
    }

    /// How many pixels wide the dark ink in `region` spans, leftmost to rightmost — for
    /// probes that compare two renders of a centred row, where absolute positions move
    /// but the total extent is the thing under test. Nil when nothing dark drew.
    private static func nearBlackInkWidth(in cgImage: CGImage, region: CGRect, threshold: UInt8 = 110) -> Int? {
        guard let pixels = rgbaPixels(of: cgImage) else { return nil }
        let bytesPerRow = cgImage.width * 4
        var minX: Int?
        var maxX: Int?
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let offset = y * bytesPerRow + x * 4
                guard pixels[offset] <= threshold,
                      pixels[offset + 1] <= threshold,
                      pixels[offset + 2] <= threshold else { continue }
                minX = min(minX ?? x, x)
                maxX = max(maxX ?? x, x)
            }
        }
        guard let minX, let maxX else { return nil }
        return maxX - minX + 1
    }

    /// The same probe for the light ink — used where a background must keep white text
    /// even though a Daylight preset is stored.
    private static func containsNearWhitePixel(in cgImage: CGImage, region: CGRect, threshold: UInt8 = 200) -> Bool {
        containsPixel(in: cgImage, region: region) { red, green, blue in
            red >= threshold && green >= threshold && blue >= threshold
        }
    }

    /// Draws the CGImage into an RGBA8 buffer and scans `region` for any pixel that
    /// isn't Midnight's flat black background — a loose check for "something drew here"
    /// rather than a match on any particular color.
    private static func containsNonBlackPixel(in cgImage: CGImage, region: CGRect) -> Bool {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let offset = y * bytesPerRow + x * 4
                if pixels[offset] > 10 || pixels[offset + 1] > 10 || pixels[offset + 2] > 10 {
                    return true
                }
            }
        }
        return false
    }
}

