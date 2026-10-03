//
//  BodyStressDayBreakdownRowsTests.swift
//  BodyTests
//
//  Renders the Stress Day View breakdown both ways, as rows and as one bar, in
//  English and Simplified Chinese: proves each lays out, on a narrow phone too,
//  and, with BODY_RENDER_OUTPUT_DIR set, writes the PNGs so the layout can be
//  reviewed by eye. Also spells out the tap-to-switch Button's VoiceOver label.
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

@MainActor
final class BodyStressDayBreakdownRowsTests: XCTestCase {
    /// An iPhone 18 Pro's card content: 393 pt less the 16 pt gutters and the
    /// card's 18 pt padding.
    private static let contentWidth: CGFloat = 325
    /// A 375 pt iPhone's (an SE or mini).
    private static let narrowContentWidth: CGFloat = 307
    private static let scale: CGFloat = 2

    /// The day in the request's screenshot: 73% Peace, 9% Relaxed, 18% Activity.
    private let quietDay = StressDaySummary(
        date: Date(timeIntervalSince1970: 1_790_000_000),
        averageScore: 9,
        minutesByBand: [.rest: 480, .low: 60],
        scoredWindowCount: 36,
        activityMinutes: 120
    )

    /// Every level and Activity, Peace past ten hours: the widest the bar view's
    /// five columns get.
    private let fullDay = StressDaySummary(
        date: Date(timeIntervalSince1970: 1_790_000_000),
        averageScore: 31,
        minutesByBand: [.rest: 630, .low: 285, .medium: 150, .high: 45],
        scoredWindowCount: 74,
        activityMinutes: 135
    )

    private func render(
        _ summary: StressDaySummary,
        showsBar: Bool,
        locale: Locale,
        width: CGFloat = contentWidth
    ) -> UIImage? {
        let card = BodyStressDayBreakdownRows(summary: summary, showsBar: showsBar)
            .frame(width: width)
            .padding(18)
            .bodyCardBackground(translucent: true)
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .environment(\.locale, locale)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = Self.scale
        return renderer.uiImage
    }

    func testRowsAndBarRenderInEnglishAndSimplifiedChinese() throws {
        for (summary, name) in [(quietDay, "quiet"), (fullDay, "full")] {
            for identifier in ["en", "zh-Hans"] {
                let locale = Locale(identifier: identifier)
                let rows = try XCTUnwrap(render(summary, showsBar: false, locale: locale), "\(name)/rows/\(identifier)")
                let bar = try XCTUnwrap(render(summary, showsBar: true, locale: locale), "\(name)/bar/\(identifier)")

                XCTAssertEqual(rows.size.width, Self.contentWidth + 68, accuracy: 0.5, "\(name)/rows/\(identifier)")
                XCTAssertEqual(bar.size.width, Self.contentWidth + 68, accuracy: 0.5, "\(name)/bar/\(identifier)")
                // One bar and a row of columns stand well short of five rows.
                XCTAssertLessThan(bar.size.height, rows.size.height - 40, "\(name)/\(identifier)")

                write(rows, name: "stress-breakdown-\(name)-rows-\(identifier).png")
                write(bar, name: "stress-breakdown-\(name)-bar-\(identifier).png")
            }
        }
    }

    func testTheBarFitsANarrowPhone() throws {
        for identifier in ["en", "zh-Hans"] {
            let image = try XCTUnwrap(
                render(fullDay, showsBar: true, locale: Locale(identifier: identifier), width: Self.narrowContentWidth),
                identifier
            )
            XCTAssertEqual(image.size.width, Self.narrowContentWidth + 68, accuracy: 0.5, identifier)

            write(image, name: "stress-breakdown-narrow-bar-\(identifier).png")
        }
    }

    func testTheSwitchReadsEveryShareAndTime() {
        let label = BodyStressDayBreakdownRows.accessibilityLabel(for: quietDay)

        XCTAssertTrue(label.hasPrefix("Stress breakdown. "), label)
        for (title, percent, minutes) in [
            (StressBand.rest.title, 73, 480),
            (StressBand.low.title, 9, 60),
            (StressBand.medium.title, 0, 0),
            (StressBand.high.title, 0, 0),
            (BodyStressBandPresentation.activityTitle, 18, 120)
        ] {
            let duration = BodyValueFormat.durationText(for: TimeInterval(minutes) * 60)
            XCTAssertTrue(label.contains("\(title) \(percent) percent, \(duration)"), label)
        }

        XCTAssertEqual(BodyStressDayBreakdownRows.accessibilityLabel(for: nil), "No Stress yet today")
    }

    private func write(_ image: UIImage, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["BODY_RENDER_OUTPUT_DIR"],
              let data = image.pngData() else {
            return
        }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? data.write(to: url.appendingPathComponent(name))
    }
}
