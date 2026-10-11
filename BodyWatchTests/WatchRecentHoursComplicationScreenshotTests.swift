//
//  WatchRecentHoursComplicationScreenshotTests.swift
//  BodyWatchTests
//
//  Opt-in writer for the intraday chart complications' renders in
//  `watch-widgets-screenshots/`: `42-complication-stress-chart-rectangular`,
//  `43-complication-heart-rate-chart-rectangular`,
//  `44-complication-hrv-chart-rectangular` and
//  `56-complication-blood-oxygen-chart-rectangular`, from the gallery
//  placeholder (a Relaxed 42, 62 bpm, 48 ms and 97 %) drawn up to its data's
//  own end, as the gallery draws it. It touches the worktree, so it skips unless
//  `BODY_WATCH_WIDGET_SCREENSHOTS=1` is in the environment. Not a snapshot
//  test.
//
//  The widget extension isn't compiled into any test target, so this builds
//  the spoken reading and the chart's content itself and draws them
//  through the shared `WatchRecentHoursChartView`, on the canvas the folder's
//  other rectangular images use (6x, the slot outlined), inset by the
//  widget's `edgeInset` on every edge but the bottom's `bottomInset`, as on a
//  Smart Stack card, whose own margins are wider. The widget source it mirrors is asserted first, so a
//  change there fails here instead of rendering a stale design.
//

import SwiftUI
import XCTest
@testable import BodyWatch

@MainActor
final class WatchRecentHoursComplicationScreenshotTests: XCTestCase {
    private static let scale: CGFloat = 6
    private static let rectangularCanvas = CGSize(width: 206, height: 96)
    private static let rectangularSlot = CGSize(width: 185, height: 75)
    /// The widget's caps on each edge's content margin.
    private static let insets = EdgeInsets(top: 5, leading: 5, bottom: 3, trailing: 5)

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Run it with:
    /// `TEST_RUNNER_BODY_WATCH_WIDGET_SCREENSHOTS=1 SCHEME=BodyWatchTests PLANS=BodyWatch DEST=… ./test.sh -only-testing:BodyWatchTests/WatchRecentHoursComplicationScreenshotTests`
    func testWritesIntradayChartComplicationScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BODY_WATCH_WIDGET_SCREENSHOTS"] == "1",
            "Set BODY_WATCH_WIDGET_SCREENSHOTS=1 to regenerate the intraday chart complication screenshots"
        )
        try assertTheMirrorMatchesTheWidgetSource()

        let directory = root.appendingPathComponent("watch-widgets-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = WatchMetricsSnapshot.placeholder
        let palette = BodyWorkoutColorPalette(rawOverrides: snapshot.workoutColorOverrides ?? "", isProUnlocked: true)

        // Stress: the placeholder's latest window, which the complication
        // reads without the age check, and its band, over the timeline's
        // last 12 hours.
        let stress = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.stress))
        let timeline = try XCTUnwrap(snapshot.stressTimeline)
        let score = try XCTUnwrap(timeline.latestScoredWindow?.score)
        let band = try XCTUnwrap(timeline.latestBand?.label)
        let stressReading = "\(score) \(band)"
        XCTAssertEqual(stressReading, "42 Relaxed")
        try write(
            WatchRecentHoursChartView(
                title: stress.title,
                reading: stressReading,
                content: .stress(timeline),
                now: timeline.end,
                emptyText: "Nothing to chart yet",
                palette: palette
            ),
            name: "42-complication-stress-chart-rectangular",
            to: directory
        )

        // Heart Rate, HRV and Blood Oxygen: the card's value and unit over
        // the slots kept in `heartCharts`, up to the read's end, Blood
        // Oxygen's axis capped at its 100% ceiling.
        let cases: [(name: String, kind: String, reading: String)] = [
            ("43-complication-heart-rate-chart-rectangular", WatchMetricKindKey.heartRate, "62 bpm"),
            ("44-complication-hrv-chart-rectangular", WatchMetricKindKey.heartRateVariability, "48 ms"),
            ("56-complication-blood-oxygen-chart-rectangular", WatchMetricKindKey.oxygenSaturation, "97 %")
        ]
        for item in cases {
            let metric = try XCTUnwrap(snapshot.metric(forKind: item.kind), item.kind)
            let chart = try XCTUnwrap(snapshot.heartCharts?[item.kind], item.kind)
            let reading = metric.hasValue ? (metric.unit.isEmpty ? metric.displayValue : "\(metric.displayValue) \(metric.unit)") : "--"
            XCTAssertEqual(reading, item.reading, item.kind)
            try write(
                WatchRecentHoursChartView(
                    title: metric.title,
                    reading: reading,
                    content: .readings(chart.buckets, tint: Color(WatchMetricKindKey.tint(forKind: item.kind))),
                    now: chart.window.end,
                    emptyText: "Nothing to chart yet",
                    valueCeiling: WatchMetricKindKey.valueCeiling(forKind: item.kind),
                    palette: palette
                ),
                name: item.name,
                to: directory
            )
        }
    }

    /// What this render repeats, as the widget source spells it: the view's
    /// arguments, ceiling and palette, the two reading builders, the
    /// gallery's anchor, the clear background, and the margins: the system's
    /// off, each edge capped.
    private func assertTheMirrorMatchesTheWidgetSource() throws {
        let source = try String(contentsOf: root.appendingPathComponent("BodyWatchWidgetExtension/RecentHoursComplications.swift"), encoding: .utf8)
        for snippet in [
            "title: metric.title,",
            "reading: reading(for: metric),",
            "emptyText: String(localized: \"Nothing to chart yet\")",
            "guard let reading = latestStressReading(in: entry) else { return \"--\" }",
            "guard let band = entry.snapshot.stressTimeline?.latestBand?.label else { return \"\\(reading.score)\" }",
            "return \"\\(reading.score) \\(band)\"",
            "guard metric.hasValue else { return \"--\" }",
            "return metric.unit.isEmpty ? metric.displayValue : \"\\(metric.displayValue) \\(metric.unit)\"",
            "return .stress(entry.snapshot.stressTimeline)",
            "entry.snapshot.heartCharts?[metricKind]?.buckets ?? [],",
            "tint: Color(WatchMetricKindKey.tint(forKind: metricKind))",
            "valueCeiling: WatchMetricKindKey.valueCeiling(forKind: metricKind),",
            "guard entry.snapshot.generatedAt == .distantPast else { return entry.date }",
            "let end = isStress ? entry.snapshot.stressTimeline?.end : entry.snapshot.heartCharts?[metricKind]?.window.end",
            ".containerBackground(.clear, for: .widget)",
            "@Environment(\\.widgetContentMargins) private var margins",
            "private static let edgeInset: CGFloat = 5",
            "private static let bottomInset: CGFloat = 3",
            "top: min(margins.top, Self.edgeInset),",
            "leading: min(margins.leading, Self.edgeInset),",
            "bottom: min(margins.bottom, Self.bottomInset),",
            "trailing: min(margins.trailing, Self.edgeInset)",
            ".padding(insets)",
            "palette: BodyWorkoutColorPalette(rawOverrides: entry.snapshot.workoutColorOverrides ?? \"\", isProUnlocked: true)"
        ] {
            XCTAssertTrue(source.contains(snippet), snippet)
        }
        XCTAssertEqual(source.components(separatedBy: ".contentMarginsDisabled()").count - 1, 4)
    }

    /// The complication's content area in the rectangular slot, on the
    /// folder's canvas.
    private func write<Content: View>(_ content: Content, name: String, to directory: URL) throws {
        let framed = content
            .padding(Self.insets)
            .frame(width: Self.rectangularSlot.width, height: Self.rectangularSlot.height)
            // The slot's outline, as the folder's other rectangular images
            // show it. The complication draws no border of its own.
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(white: 0.27), lineWidth: 0.7)
            )
            .frame(width: Self.rectangularCanvas.width, height: Self.rectangularCanvas.height)
            .background(Color.black)
        let renderer = ImageRenderer(content: framed.environment(\.colorScheme, .dark))
        renderer.scale = Self.scale
        let image = try XCTUnwrap(renderer.uiImage, name)
        let data = try XCTUnwrap(image.pngData(), name)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
