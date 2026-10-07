//
//  WatchDailyTotalComplicationScreenshotTests.swift
//  BodyWatchTests
//
//  Opt-in writer for the Steps, Active Energy and Resting Energy circular
//  complication renders in `watch-widgets-screenshots/`
//  (`37-complication-steps-circular` to `39-complication-resting-energy-circular`),
//  from the gallery placeholder's sample totals. It touches the worktree, so
//  it skips unless `BODY_WATCH_WIDGET_SCREENSHOTS=1` is in the environment.
//  Not a snapshot test.
//
//  The widget extension isn't compiled into any test target, so this draws
//  the ring itself through the shared `WatchMetricRingView`, on the canvas the
//  folder's other circular images use (6x). The layout values it repeats are
//  asserted against the widget source first, so a change there fails here
//  instead of rendering a stale design.
//

import SwiftUI
import XCTest
@testable import BodyWatch

@MainActor
final class WatchDailyTotalComplicationScreenshotTests: XCTestCase {
    private static let scale: CGFloat = 6
    private static let circularCanvas = CGSize(width: 67, height: 67)
    private static let circularSlot: CGFloat = 47
    private static let circularFontScale = (base: 0.35, compact: 0.255)

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Run it with:
    /// `TEST_RUNNER_BODY_WATCH_WIDGET_SCREENSHOTS=1 SCHEME=BodyWatchTests PLANS=BodyWatch DEST=… ./test.sh -only-testing:BodyWatchTests/WatchDailyTotalComplicationScreenshotTests`
    func testWritesDailyTotalComplicationScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BODY_WATCH_WIDGET_SCREENSHOTS"] == "1",
            "Set BODY_WATCH_WIDGET_SCREENSHOTS=1 to regenerate the daily total complication screenshots"
        )
        try assertTheMirrorMatchesTheWidgetSource()

        let directory = root.appendingPathComponent("watch-widgets-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let snapshot = WatchMetricsSnapshot.placeholder
        let cases: [(name: String, kind: String)] = [
            ("37-complication-steps-circular", WatchMetricKindKey.steps),
            ("38-complication-active-energy-circular", WatchMetricKindKey.activeEnergy),
            ("39-complication-resting-energy-circular", WatchMetricKindKey.restingEnergy)
        ]
        for item in cases {
            let metric = try XCTUnwrap(snapshot.metric(forKind: item.kind), item.kind)
            let circular = WatchMetricRingView(
                fillFraction: metric.fillFraction,
                value: metric.displayValue,
                unit: "",
                symbolName: WatchMetricKindKey.symbolName(forKind: item.kind),
                tint: WatchMetricKindKey.tint(forKind: item.kind),
                showsUnit: false,
                showsGlyph: true,
                valueFontScale: metric.displayValue.filter(\.isNumber).count >= 3 ? Self.circularFontScale.compact : Self.circularFontScale.base
            )
            .padding(1)
            .frame(width: Self.circularSlot, height: Self.circularSlot)
            .frame(width: Self.circularCanvas.width, height: Self.circularCanvas.height)
            .background(Color.black)
            try write(circular, name: item.name, to: directory)
        }
    }

    /// The values this render repeats, as the widget source spells them.
    private func assertTheMirrorMatchesTheWidgetSource() throws {
        let source = try String(contentsOf: root.appendingPathComponent("BodyWatchWidgetExtension/DailyTotalWeekComplications.swift"), encoding: .utf8)
        let shared = try String(contentsOf: root.appendingPathComponent("BodyWatchWidgetExtension/WatchComplicationView.swift"), encoding: .utf8)
        for snippet in [
            "fillFraction: metric.fillFraction,",
            "value: metric.displayValue,",
            "symbolName: WatchMetricKindKey.symbolName(forKind: metricKind),",
            "tint: WatchMetricKindKey.tint(forKind: metricKind),",
            "showsUnit: false,",
            "showsGlyph: true,",
            "valueFontScale: complicationRingFontScale(for: metric.displayValue, base: ComplicationRingFontScale.circular.base, compact: ComplicationRingFontScale.circular.compact)",
            ")\n                .padding(1)"
        ] {
            XCTAssertTrue(source.contains(snippet), snippet)
        }
        XCTAssertTrue(shared.contains("static let circular = (base: 0.35, compact: 0.255)"))
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
