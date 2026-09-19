//
//  PhoneWidgetScreenshotTests.swift
//  BodyTests
//
//  Opt-in writer for `phone-widgets-screenshots/`: rasterizes the shared views the
//  home screen widgets are built from, at widget size with the widget's padding and
//  background, in light and dark, plus the metric widgets on the Gradient background
//  and every widget under the Home Screen's Clear appearance (`*_clear.png`).
//  It touches the worktree, so it skips unless `BODY_WIDGET_SCREENSHOTS=1` is in the
//  environment. Not a snapshot test.
//
//  The lock screen widgets keep their views private to the extension, so they are
//  not covered here.
//

import XCTest
import SwiftUI
import UIKit
import WidgetKit
@testable import Body

@MainActor
final class PhoneWidgetScreenshotTests: XCTestCase {
    private static let small = CGSize(width: 170, height: 170)
    private static let medium = CGSize(width: 364, height: 170)
    private static let large = CGSize(width: 364, height: 382)

    /// Run it with:
    /// `TEST_RUNNER_BODY_WIDGET_SCREENSHOTS=1 xcodebuild … -only-testing:BodyTests/PhoneWidgetScreenshotTests`
    func testWritesPhoneWidgetScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BODY_WIDGET_SCREENSHOTS"] == "1",
            "Set BODY_WIDGET_SCREENSHOTS=1 to regenerate the phone widget screenshots"
        )

        let directory = BodyTestSupport.projectRoot
            .appendingPathComponent("phone-widgets-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let health = HealthWidgetSnapshot.placeholder
        let workouts = WorkoutMonthSnapshot.placeholder
        let palette = BodyWorkoutColorPalette.builtIn

        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .light ? "light" : "dark"

            let base = scheme == .light ? Color.white : Color.black

            /// `tint` draws the Gradient background (mirrors `bodyWidgetBackground`).
            func write<Content: View>(
                _ name: String,
                size: CGSize,
                tint: Color? = nil,
                @ViewBuilder content: () -> Content
            ) throws {
                let view = content()
                    .frame(width: size.width, height: size.height)
                    .background {
                        if let tint {
                            LinearGradient(
                                stops: [
                                    .init(color: tint.opacity(0.45), location: 0),
                                    .init(color: .clear, location: 0.5)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .background(base)
                        } else {
                            base
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let data = try XCTUnwrap(renderer.uiImage?.pngData(), "no PNG for \(name)")
                try data.write(to: directory.appendingPathComponent("\(name)_\(tag).png"))
            }

            for metric in HealthWidgetMetric.allCases {
                try write("metric_small_\(metric.rawValue)", size: Self.small) {
                    HealthWidgetMetricCardView(metric: metric, trend: health.trend(for: metric))
                        .padding(.horizontal, 15)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }
                try write("metric_small_\(metric.rawValue)_gradient", size: Self.small, tint: metric.tintColor) {
                    HealthWidgetMetricCardView(metric: metric, trend: health.trend(for: metric))
                        .padding(.horizontal, 15)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }
                try write("trend_medium_\(metric.rawValue)_week_gradient", size: Self.medium, tint: metric.tintColor) {
                    HealthWidgetTrendChartView(metric: metric, range: .week, trend: health.trend(for: metric))
                        .padding(14)
                }
                for range in [HealthWidgetTrendRange.week, .month] {
                    try write("trend_medium_\(metric.rawValue)_\(range.rawValue)", size: Self.medium) {
                        HealthWidgetTrendChartView(metric: metric, range: range, trend: health.trend(for: metric))
                            .padding(14)
                    }
                }
            }

            try write("sleep_stages_medium", size: Self.medium) {
                HealthWidgetSleepStagesView(sleep: health.sleep).padding(14)
            }
            try write("sleep_stages_medium_gradient", size: Self.medium, tint: HealthWidgetMetric.sleep.tintColor) {
                HealthWidgetSleepStagesView(sleep: health.sleep).padding(14)
            }
            try write("workout_types_medium", size: Self.medium) {
                WorkoutTypeBreakdownView(snapshot: workouts, palette: palette, style: .widgetMedium).padding(12)
            }
            try write("workout_types_large", size: Self.large) {
                WorkoutTypeBreakdownView(snapshot: workouts, palette: palette, style: .widgetLarge).padding(14)
            }
            try write("workout_calendar_large", size: Self.large) {
                WorkoutCalendarView(
                    snapshot: workouts,
                    palette: palette,
                    style: .widgetLarge,
                    referenceDate: workouts.generatedAt
                )
                .padding(14)
            }
        }

        // The Home Screen's Clear appearance: iOS drops the container background and
        // redraws the content by opacity alone, in white, on glass over the wallpaper.
        func writeClear<Content: View>(_ name: String, size: CGSize, @ViewBuilder content: () -> Content) throws {
            let view = content()
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
                .environment(\.widgetRenderingMode, .accented)
            let data = try XCTUnwrap(Self.clearAppearance(of: view, size: size)?.pngData(), "no PNG for \(name)")
            try data.write(to: directory.appendingPathComponent("\(name)_clear.png"))
        }

        for metric in HealthWidgetMetric.allCases {
            try writeClear("metric_small_\(metric.rawValue)", size: Self.small) {
                HealthWidgetMetricCardView(metric: metric, trend: health.trend(for: metric))
                    .padding(.horizontal, 15)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }
            try writeClear("trend_medium_\(metric.rawValue)_week", size: Self.medium) {
                HealthWidgetTrendChartView(metric: metric, range: .week, trend: health.trend(for: metric))
                    .padding(14)
            }
        }
        try writeClear("sleep_stages_medium", size: Self.medium) {
            HealthWidgetSleepStagesView(sleep: health.sleep).padding(14)
        }
        try writeClear("workout_types_medium", size: Self.medium) {
            WorkoutTypeBreakdownView(snapshot: workouts, palette: palette, style: .widgetMedium).padding(12)
        }
        try writeClear("workout_types_large", size: Self.large) {
            WorkoutTypeBreakdownView(snapshot: workouts, palette: palette, style: .widgetLarge).padding(14)
        }
        try writeClear("workout_calendar_large", size: Self.large) {
            WorkoutCalendarView(snapshot: workouts, palette: palette, style: .widgetLarge, referenceDate: workouts.generatedAt)
                .padding(14)
        }
    }

    /// An approximation of accented rendering: the content's alpha, filled white, on a
    /// frosted panel over a sample wallpaper. Color is discarded, as iOS does.
    private static func clearAppearance<Content: View>(of view: Content, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let content = renderer.cgImage else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let inset: CGFloat = 16
        let canvas = CGRect(origin: .zero, size: CGSize(width: size.width + inset * 2, height: size.height + inset * 2))
        let panel = canvas.insetBy(dx: inset, dy: inset)
        return UIGraphicsImageRenderer(bounds: canvas, format: format).image { context in
            let cg = context.cgContext
            let wallpaper = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.16, green: 0.24, blue: 0.45, alpha: 1).cgColor,
                    UIColor(red: 0.42, green: 0.22, blue: 0.40, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 1]
            )!
            cg.drawLinearGradient(wallpaper, start: .zero, end: CGPoint(x: canvas.maxX, y: canvas.maxY), options: [])

            UIColor.white.withAlphaComponent(0.14).setFill()
            UIBezierPath(roundedRect: panel, cornerRadius: 22).fill()

            // `clip(to:mask:)` draws the image upside down in UIKit's flipped space.
            cg.saveGState()
            cg.translateBy(x: 0, y: canvas.height)
            cg.scaleBy(x: 1, y: -1)
            let flippedPanel = CGRect(x: panel.minX, y: canvas.height - panel.maxY, width: panel.width, height: panel.height)
            cg.clip(to: flippedPanel, mask: content)
            UIColor.white.withAlphaComponent(0.92).setFill()
            cg.fill(flippedPanel)
            cg.restoreGState()
        }
    }
}
