//
//  WatchPageScreenshotTests.swift
//  BodyWatchTests
//
//  Opt-in writer for `watch-pages-screenshots/`: one full page render each
//  for the Heart Rate, HRV and Stress detail pages at this simulator's screen
//  size, the first screen (the 7-day chart with its daily ranges) with the
//  "Last 8 hours" (Stress: "Last 12 hours") chart below it, the same for the
//  Steps and Active Energy pages (their 7 day bars and today's total, then the
//  "Last 8 hours" slot bars), and one screen for Resting Energy (no intraday
//  chart, like the iPhone). It touches the worktree, so it skips unless
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

        for item in cases {
            try writePage(item.name, metric: item.metric, now: now, to: directory) {
                WatchIntradayChartView(
                    chart: .preview(kind: item.metric.kind, now: now),
                    tint: Color(WatchMetricKindKey.tint(forKind: item.metric.kind)),
                    style: .range
                )
            }
        }

        try writePage("03-stress", metric: stress(now: now), now: now, to: directory) {
            WatchStressChartView(timeline: .preview(now: now), now: now, palette: .builtIn)
        }

        // The day's running totals: the 7 day bars and today's total, then,
        // where the page has one, the last 8 hours as a bar per 30 minute slot.
        for item in dailyTotals(now: now) {
            try writePage(item.name, metric: item.metric, now: now, to: directory) {
                if WatchIntradayChartStore.chartKinds.contains(item.metric.kind) {
                    WatchIntradayChartView(
                        chart: .preview(kind: item.metric.kind, now: now),
                        tint: Color(WatchMetricKindKey.tint(forKind: item.metric.kind)),
                        style: .totals
                    )
                }
            }
        }
    }

    /// Stacks the page's first screen over `chart`, framed and padded as
    /// `WatchMetricDetailView` lays a chart section out, and writes the PNG.
    private func writePage<Chart: View>(
        _ name: String,
        metric: WatchMetric,
        now: Date,
        to directory: URL,
        @ViewBuilder chart: () -> Chart
    ) throws {
        let device = WKInterfaceDevice.current()
        let screen = device.screenBounds.size
        let page = VStack(spacing: 0) {
            WatchMetricDetailView(metric: metric, generatedAt: now, referenceDate: now)
                .frame(width: screen.width, height: screen.height)
            chart()
                .frame(height: 86)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .padding(.horizontal, 8)
                .frame(width: screen.width)
        }
        .background(Color.black)

        let renderer = ImageRenderer(content: page)
        renderer.scale = device.screenScale
        let image = try XCTUnwrap(renderer.uiImage, name)
        let data = try XCTUnwrap(image.pngData(), name)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
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

    /// Steps, Active Energy and Resting Energy: today's total so far and a
    /// week of daily totals, built on `now` so the headline survives the
    /// midnight check.
    private func dailyTotals(now: Date) -> [(name: String, metric: WatchMetric)] {
        func total(_ kind: String, title: String, displayValue: String, unit: String, weekly: [Double?], usesKilojoules: Bool? = nil) -> WatchMetric {
            let high = weekly.compactMap { $0 }.max() ?? 0
            let today = weekly.last ?? nil
            return WatchMetric(
                kind: kind,
                title: title,
                displayValue: displayValue,
                unit: unit,
                score: nil,
                fillFraction: high > 0 ? (today ?? 0) / high : 0,
                rawValue: today,
                rangeMin: 0,
                rangeMax: high,
                weekly: weekly,
                weeklyAsOf: now,
                usesKilojoules: usesKilojoules
            )
        }
        return [
            ("05-steps", total(WatchMetricKindKey.steps, title: "Steps", displayValue: "8,432", unit: "", weekly: [6_210, 9_870, 7_540, 11_020, 4_980, 8_300, 8_432])),
            ("06-active-energy", total(WatchMetricKindKey.activeEnergy, title: "Active Energy", displayValue: "512", unit: "kcal", weekly: [430, 610, 380, 720, 290, 540, 512], usesKilojoules: false)),
            ("07-resting-energy", total(WatchMetricKindKey.restingEnergy, title: "Resting Energy", displayValue: "1,640", unit: "kcal", weekly: [1_610, 1_655, 1_590, 1_632, 1_601, 1_668, 1_640], usesKilojoules: false))
        ]
    }

    /// Today's average in the Relaxed band, the status word beside it, and a
    /// week with each day's low to high range.
    private func stress(now: Date) -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.stress,
            title: "Stress",
            displayValue: "42",
            unit: "",
            score: 42,
            fillFraction: 0.42,
            rawValue: 42,
            rangeMin: 0,
            rangeMax: 100,
            levelMin: 25.5,
            levelMax: 50.5,
            tint: WatchMetricColor(red: 0.20, green: 0.80, blue: 0.45),
            weekly: [38, 51, 44, nil, 35, 47, 42],
            weeklyAsOf: now,
            weeklyRanges: [
                .init(low: 9, high: 78), .init(low: 12, high: 86), .init(low: 10, high: 74), nil,
                .init(low: 8, high: 69), .init(low: 11, high: 81), .init(low: 9, high: 82)
            ],
            statusBand: WatchStatusBand(min: 25.5, max: 50.5, label: "Relaxed")
        )
    }
}
