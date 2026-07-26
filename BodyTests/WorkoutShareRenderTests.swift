//
//  WorkoutShareRenderTests.swift
//  BodyTests
//
//  Smoke test for the share card's rasterization: proves `ImageRenderer` produces a
//  non-nil, exactly-1080×1920-px image and that the route Canvas actually draws
//  (route-blue pixels appear over a dark preset). Not a snapshot test.
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

    /// A diagonal route so the trace passes through the unit-square center (0.5, 0.5),
    /// which maps to the card center — where the render test samples for stroke pixels.
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

    private func makeRenderer() -> ImageRenderer<some View> {
        let workout = fixtureWorkout()
        let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
        let card = BodyWorkoutShareCardView(
            presentation: presentation,
            metrics: WorkoutShareMetricsBuilder.metrics(for: presentation, type: workout.type),
            routePoints: WorkoutShareRouteProjection.normalizedPoints(for: fixtureCoordinates()),
            locality: "Cupertino",
            type: workout.type,
            background: .preset(.midnight)
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

    func testRouteAreaRasterizesOverDarkPreset() throws {
        let renderer = makeRenderer()
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        // Sample a wide band across the route hero's area: the diagonal stroke must
        // cross the card's vertical middle somewhere, but its exact x depends on
        // header/metrics heights — a broad band keeps the test robust to layout tweaks.
        let sample = CGRect(
            x: cgImage.width / 4,
            y: cgImage.height / 2 - 150,
            width: cgImage.width / 2,
            height: 300
        )
        XCTAssertTrue(
            Self.containsRouteBluePixel(in: cgImage, region: sample),
            "Route trace region had no route-blue pixels — the Canvas did not rasterize"
        )
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
}
