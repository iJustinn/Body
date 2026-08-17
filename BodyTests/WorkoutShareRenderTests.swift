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
        arrangement: WorkoutShareLandscapeArrangement = .stacked
    ) -> ImageRenderer<some View> {
        let workout = fixtureWorkout()
        let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
        let isRouteless = layout == .routeless
        let routeCoordinates = coordinates ?? fixtureCoordinates()
        let card = BodyWorkoutShareCardView(
            presentation: presentation,
            metrics: isRouteless ? [] : WorkoutShareMetricsBuilder.metrics(for: presentation, type: workout.type),
            centeredMetrics: isRouteless
                ? WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: workout.type)
                : WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: workout.type),
            routePoints: withRoute ? WorkoutShareRouteProjection.normalizedPoints(for: routeCoordinates) : nil,
            route3D: withRoute ? WorkoutRoute3DProjection.projected(for: routeCoordinates) : nil,
            dimension: dimension,
            locality: "Cupertino",
            type: workout.type,
            background: background,
            layout: layout,
            aspectRatio: aspectRatio,
            arrangement: arrangement,
            infoTransform: infoTransform,
            photoTransform: photoTransform,
            fontDesign: fontDesign,
            routeColor: routeColor
        )
        let renderer = ImageRenderer(
            content: card
                .frame(width: aspectRatio.cardSize.width, height: aspectRatio.cardSize.height)
                .environment(\.colorScheme, .dark)
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
            (.portrait4x5, 1_080, 1_350),
            (.landscape5x4, 1_350, 1_080),
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

    /// Card points × the renderer's scale 3, clamped to the rendered image's actual pixel
    /// bounds — not a fixed 1080×1920 literal, since the card can now render at any of the
    /// five aspect ratios.
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
