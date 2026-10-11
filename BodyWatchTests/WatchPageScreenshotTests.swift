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
//  chart, like the iPhone). Two more show the warning cards: the Heart Rate
//  page with its "Last 8 hours" chart followed by a folded Low Heart Rate
//  card and an unfolded High Heart Rate one, and a Skin Temp page (no chart)
//  with one unfolded High Skin Temperature card. One more shows the Blood
//  Oxygen page: the week's dots with each day's range and "97 %", then the
//  "Last 8 hours" chart (the snapshot's chart on the device, the preview
//  here, its value axis capped just above 100%), then an unfolded Low Blood
//  Oxygen card. It touches the worktree, so
//  it skips unless `BODY_WATCH_PAGE_SCREENSHOTS=1` is in the environment. Not
//  a snapshot test.
//
//  `ImageRenderer` draws a watchOS `ScrollView` blank, so a page whose chart
//  or warnings make it scroll can't be rendered as is. The render stacks the
//  page's first screen (rendered without the chart and the warnings, which
//  leaves it unchanged) over the chart section and then the warning section,
//  exactly as `WatchMetricDetailView` lays them out below the value row (same
//  frame and padding), on the black the page's gradient ends in, in the
//  dark color scheme the watch always uses.
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
                if WatchIntradayChartStore.chartKinds.contains(item.metric.kind)
                    || WatchMetricDetailView.snapshotChartKinds.contains(item.metric.kind) {
                    WatchIntradayChartView(
                        chart: .preview(kind: item.metric.kind, now: now),
                        tint: Color(WatchMetricKindKey.tint(forKind: item.metric.kind)),
                        style: .totals
                    )
                }
            }
        }

        // The warning cards after the page's last chart: Low Heart Rate folded
        // (header only, chevron pointing left), High Heart Rate unfolded (the
        // sentence and the workout footnote, chevron pointing down).
        let heartWarnings = [
            warning(.lowHeartRate, threshold: 40, hour: 3, minute: 12, now: now),
            warning(.highHeartRate, threshold: 120, hour: 11, minute: 40, now: now)
        ]
        try writePage(
            "09-heart-rate-warnings",
            metric: heartRate,
            now: now,
            warnings: WatchMetricWarnings.rows(
                forCardKind: WatchMetricKindKey.heartRate,
                in: heartWarnings,
                isFolded: { $0.kind == MetricWarningKind.lowHeartRate.rawValue }
            ),
            to: directory
        ) {
            WatchIntradayChartView(
                chart: .preview(kind: WatchMetricKindKey.heartRate, now: now),
                tint: Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.heartRate)),
                style: .range
            )
        }

        // Skin Temp has no chart below its value row: the card follows it.
        try writePage(
            "10-skin-temperature-warning",
            metric: skinTemperature(now: now),
            now: now,
            warnings: WatchMetricWarnings.rows(
                forCardKind: WatchMetricKindKey.wristTemperature,
                in: [warning(.highWristTemperature, threshold: 38.0, hour: 4, minute: 25, now: now)],
                isFolded: { _ in false }
            ),
            to: directory
        )

        // Blood Oxygen: the week's dots and daily ranges, the "Last 8 hours"
        // chart the page draws from the snapshot, and an unfolded Low Blood
        // Oxygen card after it.
        try writePage(
            "12-blood-oxygen",
            metric: bloodOxygen(now: now),
            now: now,
            warnings: WatchMetricWarnings.rows(
                forCardKind: WatchMetricKindKey.oxygenSaturation,
                in: [warning(.lowBloodOxygen, threshold: 90, hour: 3, minute: 48, now: now)],
                isFolded: { _ in false }
            ),
            to: directory
        ) {
            WatchIntradayChartView(
                chart: .preview(kind: WatchMetricKindKey.oxygenSaturation, now: now),
                tint: Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.oxygenSaturation)),
                style: .range,
                valueCeiling: WatchMetricKindKey.valueCeiling(forKind: WatchMetricKindKey.oxygenSaturation)
            )
        }
    }

    /// A page with warnings and no chart section.
    private func writePage(
        _ name: String,
        metric: WatchMetric,
        now: Date,
        warnings: [WatchMetricWarningRow],
        to directory: URL
    ) throws {
        try writePage(name, metric: metric, now: now, warnings: warnings, to: directory) { EmptyView() }
    }

    /// Stacks the page's first screen over `chart`, framed and padded as
    /// `WatchMetricDetailView` lays a chart section out, then over `warnings`
    /// as its warning section, and writes the PNG. An `EmptyView` chart
    /// leaves the chart section out (a page with nothing below its value row
    /// but its warnings).
    private func writePage<Chart: View>(
        _ name: String,
        metric: WatchMetric,
        now: Date,
        warnings: [WatchMetricWarningRow] = [],
        to directory: URL,
        @ViewBuilder chart: () -> Chart
    ) throws {
        let device = WKInterfaceDevice.current()
        let screen = device.screenBounds.size
        let page = VStack(spacing: 0) {
            WatchMetricDetailView(metric: metric, generatedAt: now, referenceDate: now)
                .frame(width: screen.width, height: screen.height)
            if Chart.self != EmptyView.self {
                chart()
                    .frame(height: WatchMetricDetailView.intradayChartHeight(forKind: metric.kind))
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 8)
                    .frame(width: screen.width)
            }
            if !warnings.isEmpty {
                WatchMetricWarningSection(
                    rows: warnings,
                    usesFahrenheit: metric.usesFahrenheit ?? metric.unit.contains("F"),
                    onToggleFold: { _ in }
                )
                .padding(.horizontal, 8)
                .frame(width: screen.width)
            }
        }
        .background(Color.black)
        // The watch is always dark, but `ImageRenderer` renders light, which
        // would draw the warning cards' secondary text dark gray.
        .environment(\.colorScheme, .dark)

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

    /// A warning the phone pushed for `now`'s day, starting at `hour`:`minute`,
    /// keyed like the phone's fold entries ("lowHeartRate@2026-10-01").
    private func warning(_ kind: MetricWarningKind, threshold: Double, hour: Int, minute: Int, now: Date) -> WatchMetricWarning {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        let dayKey = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return WatchMetricWarning(
            kind: kind.rawValue,
            startDate: start,
            threshold: threshold,
            foldKey: "\(kind.rawValue)@\(dayKey)",
            isFolded: false
        )
    }

    /// Blood Oxygen: the latest reading (the preview chart's latest slot) and
    /// a week of daily averages with each day's low to high range, built on
    /// `now` so the headline survives the midnight check.
    private func bloodOxygen(now: Date) -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.oxygenSaturation,
            title: "Blood Oxygen",
            displayValue: "97",
            unit: "%",
            score: nil,
            fillFraction: 0.67,
            rawValue: 97,
            rangeMin: 95,
            rangeMax: 98,
            weekly: [96, 97, nil, 95, 98, 96, 97],
            weeklyAsOf: now,
            weeklyRanges: [
                .init(low: 91, high: 100), .init(low: 93, high: 99), nil, .init(low: 89, high: 99),
                .init(low: 94, high: 100), .init(low: 92, high: 99), .init(low: 93, high: 100)
            ]
        )
    }

    /// Skin Temp in Celsius: last night's reading and a week of nightly
    /// readings, built on `now` so the headline survives the midnight check.
    private func skinTemperature(now: Date) -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.wristTemperature,
            title: "Skin Temp",
            displayValue: "34.6",
            unit: "°C",
            score: nil,
            fillFraction: 0.7,
            rawValue: 34.6,
            rangeMin: 33.8,
            rangeMax: 34.9,
            weekly: [34.1, 33.9, 34.3, nil, 34.0, 33.8, 34.6],
            weeklyAsOf: now,
            usesFahrenheit: false
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

    /// The current reading (the preview timeline's latest window) in the
    /// Relaxed band with the status word beside it, and a week of daily
    /// averages with each day's low to high range.
    private func stress(now: Date) -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.stress,
            title: "Stress",
            displayValue: "37",
            unit: "",
            score: 37,
            fillFraction: 0.37,
            rawValue: 37,
            rangeMin: 0,
            rangeMax: 100,
            levelMin: 25.5,
            levelMax: 50.5,
            tint: WatchMetricColor(red: 0.20, green: 0.80, blue: 0.45),
            weekly: [38, 51, 44, nil, 35, 47, 52],
            weeklyAsOf: now,
            weeklyRanges: [
                .init(low: 9, high: 78), .init(low: 12, high: 86), .init(low: 10, high: 74), nil,
                .init(low: 8, high: 69), .init(low: 11, high: 81), .init(low: 9, high: 82)
            ],
            statusBand: WatchStatusBand(min: 25.5, max: 50.5, label: "Relaxed")
        )
    }
}
