//
//  WorkoutShareSummaryRenderTests.swift
//  BodyTests
//
//  The month-summary card's rasterization, the mirror of `WorkoutShareRenderTests`
//  for `BodyWorkoutShareSummaryCardView`: proves `ImageRenderer` produces an image at
//  the exact pixel size for every ratio × chart style, that both charts actually draw
//  inside the region the geometry gave them, that the ink follows the preset, that the
//  photo transform moves the backdrop, and that five metrics never reach the branding
//  zone. Not a snapshot test.
//
//  `testWritesSummaryShareExamples` is the opt-in sample writer — it is the one test
//  here that touches the worktree, so it skips unless `BODY_SHARE_EXAMPLES=1` is in the
//  environment.
//

import XCTest
import SwiftUI
import CoreGraphics
import UIKit
@testable import Body

@MainActor
final class WorkoutShareSummaryRenderTests: XCTestCase {
    /// The renderer's scale, and therefore the factor between the geometry's card
    /// points and the pixels every probe below samples.
    private static let scale: CGFloat = 3

    /// A fixed "today" so the calendar's highlighted day — and every sample PNG — is
    /// the same on every run. Inside the fixture month, so the highlight actually draws.
    private static let referenceDate = Date(timeIntervalSince1970: 1_747_310_400) // 2025-05-15

    private static let fixtureMonth = 5
    private static let fixtureYear = 2_025

    /// A busy month: six activity types (so the breakdown chart has more rows than any
    /// ratio will draw), spread across enough days to fill most of the calendar grid,
    /// and carrying distance and energy so the metric pool offers all seven options.
    private func fixtureSnapshot() -> WorkoutMonthSnapshot {
        let calendar = Calendar.bodyGregorian
        let types: [BodyWorkoutType] = [.running, .cycling, .strengthTraining, .swimming, .walking, .yoga]
        let start = calendar.date(
            from: DateComponents(year: Self.fixtureYear, month: Self.fixtureMonth, day: 1, hour: 8)
        ) ?? Date(timeIntervalSince1970: 0)
        let workouts: [WorkoutSummary] = (0..<26).map { index in
            WorkoutSummary(
                type: types[index % types.count],
                startDate: calendar.date(byAdding: .day, value: index, to: start) ?? start,
                duration: TimeInterval(1_500 + index * 120),
                activeEnergyKilocalories: Double(240 + index * 11),
                // Only the distance-carrying types get one, the way a real month reads.
                distanceMeters: index % 6 <= 1 ? Double(5_000 + index * 300) : nil
            )
        }
        return WorkoutMonthSnapshot.make(
            month: Self.fixtureMonth,
            year: Self.fixtureYear,
            workouts: workouts,
            calendar: calendar,
            generatedAt: Self.referenceDate
        )
    }

    private func fixtureMetrics(count: Int) -> [WorkoutShareSummaryMetricOption] {
        let pool = WorkoutShareSummaryMetricsBuilder.availableMetrics(
            snapshot: fixtureSnapshot(),
            distanceUnitPreference: .kilometers,
            energyUnitPreference: .kilocalories,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertGreaterThanOrEqual(pool.count, count, "fixture month must offer at least \(count) metrics")
        return Array(pool.prefix(count))
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

    private func makeSummaryRenderer(
        chartStyle: WorkoutSummaryChartStyle = .calendar,
        showsWeekdayHeader: Bool = true,
        aspectRatio: WorkoutShareAspectRatio = .portrait9x16,
        background: WorkoutShareCardBackground = .preset(.midnight),
        metricCount: Int = 3,
        photoTransform: WorkoutSharePhotoTransform = .identity,
        infoTransform: WorkoutShareInfoTransform = .identity,
        fontDesign: Font.Design = .rounded,
        attribution: WorkoutShareAttribution = .empty,
        /// What the sheet's exporter picks from the resolved ink: `.dark` for the
        /// dark-backed presets, `.light` for Daylight — the charts read `.primary`.
        colorScheme: ColorScheme = .dark
    ) -> ImageRenderer<some View> {
        let snapshot = fixtureSnapshot()
        let card = BodyWorkoutShareSummaryCardView(
            summary: WorkoutShareMonthSummary(snapshot: snapshot, initialChartStyle: chartStyle),
            palette: .builtIn,
            chartStyle: chartStyle,
            showsWeekdayHeader: showsWeekdayHeader,
            metrics: fixtureMetrics(count: metricCount),
            background: background,
            aspectRatio: aspectRatio,
            infoTransform: infoTransform,
            photoTransform: photoTransform,
            fontDesign: fontDesign,
            attribution: attribution,
            referenceDate: Self.referenceDate
        )
        let renderer = ImageRenderer(
            content: card
                .frame(width: aspectRatio.cardSize.width, height: aspectRatio.cardSize.height)
                .environment(\.colorScheme, colorScheme)
                .dynamicTypeSize(.large)
        )
        renderer.scale = Self.scale
        return renderer
    }

    // MARK: - Pixel size

    /// Every ratio × chart style rasterizes at points × 3, with 9:16 pinned to the
    /// original 1080×1920 literal the workout card also produces.
    func testSummaryCardRendersToExactPixelSizeForEveryRatioAndStyle() throws {
        for aspectRatio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
            for chartStyle in WorkoutSummaryChartStyle.allCases {
                let renderer = makeSummaryRenderer(chartStyle: chartStyle, aspectRatio: aspectRatio)
                let image = try XCTUnwrap(
                    renderer.uiImage, "ImageRenderer produced no image for \(aspectRatio.rawValue)/\(chartStyle.rawValue)"
                )
                let cgImage = try XCTUnwrap(image.cgImage)
                let size = aspectRatio.cardSize
                XCTAssertEqual(cgImage.width, Int(size.width * Self.scale), "\(aspectRatio.rawValue)/\(chartStyle.rawValue)")
                XCTAssertEqual(cgImage.height, Int(size.height * Self.scale), "\(aspectRatio.rawValue)/\(chartStyle.rawValue)")
            }
        }

        let defaultImage = try XCTUnwrap(makeSummaryRenderer().uiImage?.cgImage)
        XCTAssertEqual(defaultImage.width, 1_080)
        XCTAssertEqual(defaultImage.height, 1_920)
    }

    // MARK: - The charts actually draw

    /// The calendar grid's day cells are tinted by their workout's type — a chromatic
    /// colour, unlike the card's white/black ink and the flat black Midnight backdrop.
    /// Sampled in the geometry's own `chartRect`, so moving the region can't leave this
    /// probe scanning empty background.
    func testCalendarChartDrawsInsideItsRegion() throws {
        for aspectRatio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
            let image = try XCTUnwrap(makeSummaryRenderer(chartStyle: .calendar, aspectRatio: aspectRatio).uiImage?.cgImage)
            let geometry = WorkoutShareSummaryCardGeometry(aspectRatio: aspectRatio, metricCount: 3)
            XCTAssertTrue(
                Self.containsChromaticPixel(in: image, region: Self.pixelRect(geometry.chartRect, in: image)),
                "Calendar grid drew no workout-type colour inside its chart region on \(aspectRatio.rawValue)"
            )
        }
    }

    /// The breakdown chart's bars carry the same type colours — same probe, other view.
    func testBarChartDrawsInsideItsRegion() throws {
        for aspectRatio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
            let image = try XCTUnwrap(makeSummaryRenderer(chartStyle: .bar, aspectRatio: aspectRatio).uiImage?.cgImage)
            let geometry = WorkoutShareSummaryCardGeometry(aspectRatio: aspectRatio, metricCount: 3)
            XCTAssertTrue(
                Self.containsChromaticPixel(in: image, region: Self.pixelRect(geometry.chartRect, in: image)),
                "Breakdown bars drew no workout-type colour inside the chart region on \(aspectRatio.rawValue)"
            )
        }
    }

    // MARK: - Ink polarity

    /// Daylight is a white card whose ink is black, and the sheet hands the render the
    /// inverted `.light` scheme so the charts' `.primary` resolves dark too. The title
    /// slot must therefore carry near-black pixels.
    func testDaylightPresetDrawsDarkTitleInk() throws {
        let image = try XCTUnwrap(
            makeSummaryRenderer(background: .preset(.daylight), colorScheme: .light).uiImage?.cgImage
        )
        let geometry = WorkoutShareSummaryCardGeometry(aspectRatio: .portrait9x16, metricCount: 3)
        let titleRect = geometry.titleRect.offsetBy(dx: 0, dy: geometry.verticalShift(for: .calendar))
        XCTAssertTrue(
            Self.containsNearBlackPixel(in: image, region: Self.pixelRect(titleRect, in: image)),
            "Daylight title region had no dark ink"
        )
    }

    /// Midnight is the mirror: white ink over a flat black card, `.dark` scheme.
    func testMidnightPresetDrawsLightTitleInk() throws {
        let image = try XCTUnwrap(
            makeSummaryRenderer(background: .preset(.midnight), colorScheme: .dark).uiImage?.cgImage
        )
        let geometry = WorkoutShareSummaryCardGeometry(aspectRatio: .portrait9x16, metricCount: 3)
        let titleRect = geometry.titleRect.offsetBy(dx: 0, dy: geometry.verticalShift(for: .calendar))
        XCTAssertTrue(
            Self.containsNearWhitePixel(in: image, region: Self.pixelRect(titleRect, in: image)),
            "Midnight title region had no light ink"
        )
    }

    // MARK: - Photo background

    /// The photo transform has to move the summary card's backdrop too, not just the
    /// workout card's. At scale 2 the two-tone image's midline sits at card y 320;
    /// sliding it down 160 pt moves that boundary to y 480, so a row at y 400 flips
    /// from green to red. Sampled at the card's left edge, clear of the chart.
    func testPhotoTransformOffsetMovesTheSummaryBackdrop() throws {
        let photo = twoToneImage()
        let sampleRect = CGRect(x: 4, y: 390, width: 14, height: 20)

        let centered = try XCTUnwrap(
            makeSummaryRenderer(
                background: .photo(photo),
                photoTransform: WorkoutSharePhotoTransform(offset: .zero, scale: 2)
            ).uiImage?.cgImage
        )
        let centeredColor = Self.averageColor(in: centered, region: Self.pixelRect(sampleRect, in: centered))
        XCTAssertGreaterThan(
            centeredColor.green, centeredColor.red, "Untranslated photo should show its lower (green) half at y 400"
        )

        let shifted = try XCTUnwrap(
            makeSummaryRenderer(
                background: .photo(photo),
                photoTransform: WorkoutSharePhotoTransform(offset: CGSize(width: 0, height: 160), scale: 2)
            ).uiImage?.cgImage
        )
        let shiftedColor = Self.averageColor(in: shifted, region: Self.pixelRect(sampleRect, in: shifted))
        XCTAssertGreaterThan(shiftedColor.red, shiftedColor.green, "Photo transform's offset did not move the backdrop")
    }

    // MARK: - Branding zone

    /// The pinned wordmark owns the bottom strip: at the worst case (five metrics, the
    /// count that pushes the chart hardest) neither the metrics nor the chart may reach
    /// into it on any ratio — first as geometry, then as pixels either side of the
    /// centred mark on the default card.
    func testFiveMetricsStayClearOfTheBrandingZone() throws {
        let zoneTop: (CGSize) -> CGFloat = { $0.height - WorkoutShareCardGeometry.brandingZoneHeight }

        for aspectRatio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
            for chartStyle in WorkoutSummaryChartStyle.allCases {
                let geometry = WorkoutShareSummaryCardGeometry(aspectRatio: aspectRatio, metricCount: 3)
                let limit = zoneTop(geometry.size)
                XCTAssertLessThanOrEqual(geometry.metricsRect.maxY, limit, "metrics reach the branding zone on \(aspectRatio.rawValue)")
                XCTAssertLessThanOrEqual(geometry.chartRect.maxY, limit, "chart reaches the branding zone on \(aspectRatio.rawValue)")
            }
        }

        // Pixels: the branding row is centred, so the strip from the card's left edge to
        // x 70 inside the zone belongs to nothing and stays flat black over Midnight.
        for chartStyle in WorkoutSummaryChartStyle.allCases {
            let image = try XCTUnwrap(makeSummaryRenderer(chartStyle: chartStyle, metricCount: 3).uiImage?.cgImage)
            let size = WorkoutShareAspectRatio.portrait9x16.cardSize
            let band = CGRect(
                x: 0,
                y: zoneTop(size),
                width: 70,
                height: WorkoutShareCardGeometry.brandingZoneHeight
            )
            XCTAssertFalse(
                Self.containsNonBlackPixel(in: image, region: Self.pixelRect(band, in: image)),
                "Content spilled into the branding zone beside the wordmark with 5 metrics (\(chartStyle.rawValue))"
            )
        }
    }

    // MARK: - Sample PNGs (opt-in)

    /// Writes `share-examples/*_summary.png` for the coordinator's visual review.
    /// Skipped unless `BODY_SHARE_EXAMPLES=1` is set: it is the only test here that
    /// writes to the repo, and an ordinary run must leave the worktree clean.
    ///
    /// Run it with:
    /// `TEST_RUNNER_BODY_SHARE_EXAMPLES=1 xcodebuild … -only-testing:BodyTests/WorkoutShareSummaryRenderTests/testWritesSummaryShareExamples`
    func testWritesSummaryShareExamples() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BODY_SHARE_EXAMPLES"] == "1",
            "Set BODY_SHARE_EXAMPLES=1 to regenerate the sample share cards"
        )

        // BodyTests/WorkoutShareSummaryRenderTests.swift → BodyTests → repo root.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = repoRoot.appendingPathComponent("share-examples", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for metricCount in [1, 2, 3] {
            for aspectRatio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
                for chartStyle in WorkoutSummaryChartStyle.allCases {
                    for preset in [BodyWorkoutSharePreset.midnight, .daylight] {
                        let renderer = makeSummaryRenderer(
                            chartStyle: chartStyle,
                            showsWeekdayHeader: true,
                            aspectRatio: aspectRatio,
                            background: .preset(preset),
                            metricCount: metricCount,
                            colorScheme: preset.ink == .dark ? .light : .dark
                        )
                        let image = try XCTUnwrap(
                            renderer.uiImage?.pngData(),
                            "no PNG for \(metricCount)/\(aspectRatio.rawValue)/\(chartStyle.rawValue)/\(preset.rawValue)"
                        )
                        // "9:16" is not a filename; the tag is the ratio with its colon
                        // swapped for an x, so the samples sort by shape.
                        let ratioTag = aspectRatio.rawValue.replacingOccurrences(of: ":", with: "x")
                        let name = "\(metricCount)_\(ratioTag)_\(chartStyle.rawValue)_\(preset.rawValue)_summary.png"
                        try image.write(to: directory.appendingPathComponent(name))
                    }
                }
            }
        }

        // One calendar without its weekday letters, so the toggle can be eyeballed too.
        let hidden = try XCTUnwrap(
            makeSummaryRenderer(chartStyle: .calendar, showsWeekdayHeader: false, metricCount: 2).uiImage?.pngData()
        )
        try hidden.write(to: directory.appendingPathComponent("2_9x16_calendar_midnight_noweekdays_summary.png"))
    }

    // MARK: - Pixel probes

    /// A card-point rect × the renderer's scale, clamped to the image so a geometry
    /// change can't index out of bounds.
    private static func pixelRect(_ rect: CGRect, in cgImage: CGImage) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    }

    /// Any pixel with real hue in it — the channels spread far enough apart that it
    /// can't be the card's white/black ink, its greys, or a flat preset backdrop. That
    /// is exactly what a workout type's colour looks like, whichever type it is, so the
    /// probe survives a palette tweak that a hard-coded colour wouldn't.
    private static func containsChromaticPixel(in cgImage: CGImage, region: CGRect, spread: Int = 40) -> Bool {
        containsPixel(in: cgImage, region: region) { red, green, blue in
            let channels = [Int(red), Int(green), Int(blue)]
            guard let low = channels.min(), let high = channels.max() else { return false }
            return high - low >= spread
        }
    }

    private static func containsNearBlackPixel(in cgImage: CGImage, region: CGRect, threshold: UInt8 = 110) -> Bool {
        containsPixel(in: cgImage, region: region) { red, green, blue in
            red <= threshold && green <= threshold && blue <= threshold
        }
    }

    private static func containsNearWhitePixel(in cgImage: CGImage, region: CGRect, threshold: UInt8 = 200) -> Bool {
        containsPixel(in: cgImage, region: region) { red, green, blue in
            red >= threshold && green >= threshold && blue >= threshold
        }
    }

    /// Anything the flat Midnight backdrop isn't. The threshold rather than an exact
    /// zero because both the scrims and antialiasing leave near-black values behind.
    private static func containsNonBlackPixel(in cgImage: CGImage, region: CGRect, threshold: UInt8 = 24) -> Bool {
        containsPixel(in: cgImage, region: region) { red, green, blue in
            red > threshold || green > threshold || blue > threshold
        }
    }

    /// Draws the CGImage into an RGBA8 buffer and scans `region` for any pixel matching
    /// `matches` — the general form of every probe above.
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
}
