//
//  WatchComplicationScreenshotTests.swift
//  BodyWatchTests
//
//  Opt-in writer for the Stress complication's renders in
//  `watch-widgets-screenshots/`: `35-complication-stress-circular` and
//  `36-complication-stress-rectangular`, from the gallery placeholder (a
//  Relaxed 42). It touches the worktree, so it skips unless
//  `BODY_WATCH_WIDGET_SCREENSHOTS=1` is in the environment. Not a snapshot
//  test.
//
//  The widget extension isn't compiled into any test target, so this draws
//  `StressComplication`'s layout itself through the shared
//  `WatchMetricRingView`, on the canvas the folder's other complication
//  images use (6x, the rectangular slot outlined). The layout values it
//  repeats are asserted against the widget source first, so a change there
//  fails here instead of rendering a stale design.
//

import SwiftUI
import XCTest
@testable import BodyWatch

@MainActor
final class WatchComplicationScreenshotTests: XCTestCase {
    private static let scale: CGFloat = 6
    private static let circularCanvas = CGSize(width: 67, height: 67)
    private static let circularSlot: CGFloat = 47
    private static let rectangularCanvas = CGSize(width: 206, height: 96)
    private static let rectangularSlot = CGSize(width: 185, height: 75)
    private static let rectangularInset: CGFloat = 6.7
    private static let circularFontScale = (base: 0.35, compact: 0.255)
    private static let rectangularFontScale = (base: 0.40, compact: 0.34)

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Run it with:
    /// `TEST_RUNNER_BODY_WATCH_WIDGET_SCREENSHOTS=1 SCHEME=BodyWatchTests PLANS=BodyWatch DEST=… ./test.sh -only-testing:BodyWatchTests/WatchComplicationScreenshotTests`
    func testWritesStressComplicationScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BODY_WATCH_WIDGET_SCREENSHOTS"] == "1",
            "Set BODY_WATCH_WIDGET_SCREENSHOTS=1 to regenerate the Stress complication screenshots"
        )
        try assertTheMirrorMatchesTheWidgetSource()

        let directory = root.appendingPathComponent("watch-widgets-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The gallery placeholder, which the complication draws without the
        // age check: its timeline ends on a Relaxed 42.
        let snapshot = WatchMetricsSnapshot.placeholder
        let metric = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.stress))
        let timeline = try XCTUnwrap(snapshot.stressTimeline)
        let score = try XCTUnwrap(timeline.latestScoredWindow?.score)
        let tint = WatchMetricKindKey.tint(forKind: WatchMetricKindKey.stress)
        let label = try XCTUnwrap(timeline.latestBand?.label)

        let circular = ring(score: score, tint: tint, showsGlyph: true, fontScale: Self.circularFontScale)
            .padding(1)
            .frame(width: Self.circularSlot, height: Self.circularSlot)
            .frame(width: Self.circularCanvas.width, height: Self.circularCanvas.height)
            .background(Color.black)
        try write(circular, name: "35-complication-stress-circular", to: directory)

        let row = HStack(spacing: 8) {
            ring(score: score, tint: tint, showsGlyph: false, fontScale: Self.rectangularFontScale)
                .frame(width: 46, height: 46)
                .offset(y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(metric.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        let rectangular = row
            .padding(.horizontal, Self.rectangularInset)
            .frame(width: Self.rectangularSlot.width, height: Self.rectangularSlot.height)
            // The slot's outline, as the folder's other rectangular images
            // show it. The complication draws no border of its own.
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(white: 0.27), lineWidth: 0.7)
            )
            .frame(width: Self.rectangularCanvas.width, height: Self.rectangularCanvas.height)
            .background(Color.black)
        try write(rectangular, name: "36-complication-stress-rectangular", to: directory)
    }

    /// `StressComplication`'s ring, as its `ring(showsGlyph:fontScale:)` builds it.
    private func ring(score: Int, tint: WatchMetricColor, showsGlyph: Bool, fontScale: (base: Double, compact: Double)) -> some View {
        let text = "\(score)"
        return WatchMetricRingView(
            fillFraction: Double(score) / 100,
            value: text,
            unit: "",
            symbolName: WatchMetricKindKey.symbolName(forKind: WatchMetricKindKey.stress),
            tint: tint,
            showsUnit: false,
            showsGlyph: showsGlyph,
            valueFontScale: text.filter(\.isNumber).count >= 3 ? fontScale.compact : fontScale.base
        )
    }

    /// The values this render repeats, as the widget source spells them.
    private func assertTheMirrorMatchesTheWidgetSource() throws {
        let stress = try String(contentsOf: root.appendingPathComponent("BodyWatchWidgetExtension/StressComplication.swift"), encoding: .utf8)
        let shared = try String(contentsOf: root.appendingPathComponent("BodyWatchWidgetExtension/WatchComplicationView.swift"), encoding: .utf8)

        for snippet in [
            "ring(showsGlyph: true, fontScale: ComplicationRingFontScale.circular)\n                    .padding(1)",
            "ring(showsGlyph: false, fontScale: ComplicationRingFontScale.rectangular)\n                    .frame(width: 46, height: 46)",
            ".offset(y: 2)",
            "HStack(spacing: 8)",
            "VStack(alignment: .leading, spacing: 1)",
            "Text(metric.title)",
            "reading.map { Double($0.score) / 100 }",
            "symbolName: WatchMetricKindKey.symbolName(forKind: WatchMetricKindKey.stress)",
            "private let tint = WatchMetricKindKey.tint(forKind: WatchMetricKindKey.stress)"
        ] {
            XCTAssertTrue(stress.contains(snippet), snippet)
        }
        XCTAssertEqual(stress.components(separatedBy: ".font(.headline)\n                        .lineLimit(1)\n                        .minimumScaleFactor(0.7)").count - 1, 2)
        XCTAssertTrue(shared.contains("static let circular = (base: 0.35, compact: 0.255)"))
        XCTAssertTrue(shared.contains("static let rectangular = (base: 0.40, compact: 0.34)"))
        XCTAssertTrue(shared.contains("text.filter(\\.isNumber).count >= 3 ? compact : base"))
    }

    private func write<Content: View>(_ content: Content, name: String, to directory: URL) throws {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark))
        renderer.scale = Self.scale
        let image = try XCTUnwrap(renderer.uiImage, name)
        let data = try XCTUnwrap(image.pngData(), name)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
