//
//  WatchPageScreenshotTests.swift
//  BodyWatchTests
//
//  Opt-in writer for `watch-pages-screenshots/`: one full page render each
//  for the Heart Rate and HRV detail pages at this simulator's screen size,
//  the first screen (the 7-day chart with its daily ranges) with the "Last 8
//  hours" chart below it. It touches the worktree, so it skips unless
//  `BODY_WATCH_PAGE_SCREENSHOTS=1` is in the environment. Not a snapshot
//  test.
//
//  `ImageRenderer` draws a watchOS `ScrollView` blank, so a page whose chart
//  makes it scroll can't be rendered as is. The render stacks the page's
//  first screen (rendered without the chart, which leaves it unchanged) over
//  the chart section exactly as `WatchMetricDetailView` lays it out below the
//  value row (same frame and padding), on the black the page's gradient ends in.
//

import SwiftUI
import WatchKit
import XCTest
@testable import BodyWatch

@MainActor
final class WatchPageScreenshotTests: XCTestCase {
    /// Run it with:
    /// `TEST_RUNNER_BODY_WATCH_PAGE_SCREENSHOTS=1 SCHEME=BodyWatchTests PLANS=BodyWatch DEST=… ./test.sh -only-testing:BodyWatchTests/WatchPageScreenshotTests`
    func testWritesWatchPageScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BODY_WATCH_PAGE_SCREENSHOTS"] == "1",
            "Set BODY_WATCH_PAGE_SCREENSHOTS=1 to regenerate the watch page screenshots"
        )

        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("watch-pages-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A fixed afternoon, so the weekday and hour labels don't move between runs.
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 15, minute: 7)) ?? Date()
        let cases: [(name: String, metric: WatchMetric)] = [
            ("01-heart-rate", heartRate),
            ("02-hrv", hrv)
        ]

        let device = WKInterfaceDevice.current()
        let screen = device.screenBounds.size
        for item in cases {
            let page = VStack(spacing: 0) {
                WatchMetricDetailView(metric: item.metric, generatedAt: now, referenceDate: now)
                    .frame(width: screen.width, height: screen.height)
                WatchIntradayChartView(
                    chart: .preview(kind: item.metric.kind, now: now),
                    kind: item.metric.kind,
                    tint: Color(WatchMetricKindKey.tint(forKind: item.metric.kind))
                )
                .frame(height: 86)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .padding(.horizontal, 8)
                .frame(width: screen.width)
            }
            .background(Color.black)

            let renderer = ImageRenderer(content: page)
            renderer.scale = device.screenScale
            let image = try XCTUnwrap(renderer.uiImage, item.name)
            let data = try XCTUnwrap(image.pngData(), item.name)
            try data.write(to: directory.appendingPathComponent("\(item.name).png"))
        }
    }

    private var heartRate: WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.heartRate,
            title: "Heart Rate",
            displayValue: "64",
            unit: "bpm",
            score: nil,
            fillFraction: 0.45,
            rawValue: 64,
            rangeMin: 54,
            rangeMax: 72,
            weekly: [58, 64, nil, 55, 72, 61, 64],
            weeklyRanges: [
                .init(low: 47, high: 131), .init(low: 49, high: 152), nil, .init(low: 46, high: 118),
                .init(low: 52, high: 166), .init(low: 48, high: 139), .init(low: 50, high: 127)
            ]
        )
    }

    private var hrv: WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.heartRateVariability,
            title: "HRV",
            displayValue: "38",
            unit: "ms",
            score: nil,
            fillFraction: 0.4,
            rawValue: 38,
            rangeMin: 25,
            rangeMax: 70,
            weekly: [44, 51, 39, nil, 47, 42, 38],
            weeklyRanges: [
                .init(low: 24, high: 66), .init(low: 29, high: 78), .init(low: 22, high: 61), nil,
                .init(low: 31, high: 84), .init(low: 27, high: 70), .init(low: 25, high: 62)
            ]
        )
    }
}
