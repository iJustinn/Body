//
//  WorkoutShareRenderTests.swift
//  BodyTests
//
//  Smoke test for the share card's rasterization: proves `ImageRenderer` produces a
//  non-nil, exactly-1080×1920-px image for all three layouts and that the route Canvas
//  actually draws (route-blue pixels appear over a dark preset). Not a snapshot test.
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

    private func makeRenderer(
        layout: WorkoutShareCardLayout = .centered,
        infoTransform: WorkoutShareInfoTransform = .identity,
        withRoute: Bool = true
    ) -> ImageRenderer<some View> {
        let workout = fixtureWorkout()
        let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
        let isRouteless = layout == .routeless
        let card = BodyWorkoutShareCardView(
            presentation: presentation,
            metrics: isRouteless ? [] : WorkoutShareMetricsBuilder.metrics(for: presentation, type: workout.type),
            centeredMetrics: isRouteless
                ? WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: workout.type)
                : WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: workout.type),
            routePoints: withRoute ? WorkoutShareRouteProjection.normalizedPoints(for: fixtureCoordinates()) : nil,
            locality: "Cupertino",
            type: workout.type,
            background: .preset(.midnight),
            layout: layout,
            infoTransform: infoTransform
        )
        let renderer = ImageRenderer(
            content: card
                .frame(width: 360, height: 640)
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

        // Assert the true pixel dimensions (points × scale), not the point size.
        XCTAssertEqual(cgImage.width, 1_080)
        XCTAssertEqual(cgImage.height, 1_920)
    }

    /// The classic layout is a different view tree (header + bottom row), so it gets its
    /// own size assertion — a layout that overflowed 360×640 would still be clipped, but
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
    /// metric stack. The fixture (running, with energy recorded) produces 4 metrics, so
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
        // catch the glyph regardless of the exact block height for 4 metrics.
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

        // The centered layout's route region, taken from the card's own constants and
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

    /// `BodyWorkoutShareCardView.centeredRoute*` (card points, optionally shifted by an
    /// info transform's offset) × the renderer's scale 3, clamped to the image so a
    /// future geometry change can't index out of bounds.
    private static func centeredRouteRegionInPixels(of cgImage: CGImage, offsetBy offset: CGSize = .zero) -> CGRect {
        let scale: CGFloat = 3
        let size = BodyWorkoutShareCardView.centeredRouteSize
        let center = BodyWorkoutShareCardView.centeredRouteCenter
        let region = CGRect(
            x: (center.x + offset.width - size / 2) * scale,
            y: (center.y + offset.height - size / 2) * scale,
            width: size * scale,
            height: size * scale
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
