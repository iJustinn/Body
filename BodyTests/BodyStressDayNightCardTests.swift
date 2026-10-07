//
//  BodyStressDayNightCardTests.swift
//  BodyTests
//
//  Renders the Stress page's Day and Night card in English and Simplified Chinese
//  for each state a tile can be in: proves it lays out at all, and, with
//  BODY_RENDER_OUTPUT_DIR set, writes the PNGs so the layout can be reviewed by eye.
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

@MainActor
final class BodyStressDayNightCardTests: XCTestCase {
    /// An iPhone 18 Pro's page column: 393 pt less the 16 pt gutters.
    private static let cardWidth: CGFloat = 361
    /// A 375 pt iPhone's column (an SE or mini), about a foldable's 344 pt pane.
    private static let narrowCardWidth: CGFloat = 343
    private static let scale: CGFloat = 2

    private let calendar = Calendar.current

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private func time(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
        return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
    }

    /// Today at 3:40 PM: a Relaxed day so far after a night with one restless stretch.
    private var fullDay: StressDayNightSplit {
        StressDayNightSplit(
            day: StressDayNightSplit.Period(
                interval: DateInterval(start: time(7, 12), end: time(15, 40)),
                minutesByBand: [.rest: 90, .low: 255, .medium: 75, .high: 30],
                activityMinutes: 60,
                scoredWindowCount: 30,
                averageScore: 41,
                peak: StressDayNightSplit.Peak(score: 81, start: time(13, 30))
            ),
            night: StressDayNightSplit.Period(
                interval: DateInterval(start: time(23, 38, dayOffset: -1), end: time(7, 12)),
                minutesByBand: [.rest: 405, .low: 30],
                scoredWindowCount: 29,
                averageScore: 5,
                peak: StressDayNightSplit.Peak(score: 34, start: time(3, 30)),
                restlessMinutes: 30,
                restlessStart: time(3, 15)
            ),
            isToday: true,
            daySpan: .toNow(start: time(7, 12))
        )
    }

    /// A past day with no sleep recorded, so the whole day is Day.
    private var noSleep: StressDayNightSplit {
        StressDayNightSplit(
            day: StressDayNightSplit.Period(
                interval: DateInterval(start: time(0, 0, dayOffset: -2), end: time(0, 0, dayOffset: -1)),
                minutesByBand: [.rest: 300, .low: 420, .medium: 120],
                activityMinutes: 45,
                scoredWindowCount: 56,
                averageScore: 33,
                peak: StressDayNightSplit.Peak(score: 64, start: time(10, 45, dayOffset: -2))
            ),
            night: nil,
            isToday: false,
            daySpan: .allDay
        )
    }

    /// A past day whose night was too sparse to read, after a Stressed evening.
    private var sparseNight: StressDayNightSplit {
        StressDayNightSplit(
            day: StressDayNightSplit.Period(
                interval: DateInterval(start: time(6, 50, dayOffset: -3), end: time(22, 55, dayOffset: -3)),
                minutesByBand: [.rest: 60, .low: 300, .medium: 240, .high: 120],
                activityMinutes: 90,
                scoredWindowCount: 48,
                averageScore: 52,
                peak: StressDayNightSplit.Peak(score: 88, start: time(18, 15, dayOffset: -3))
            ),
            night: StressDayNightSplit.Period(
                interval: DateInterval(start: time(23, 50, dayOffset: -4), end: time(6, 50, dayOffset: -3)),
                minutesByBand: [.rest: 75],
                scoredWindowCount: 5,
                averageScore: 2
            ),
            isToday: false,
            daySpan: .range(start: time(6, 50, dayOffset: -3), end: time(22, 55, dayOffset: -3))
        )
    }

    /// A past day with two restless stretches in the night, so no single time, and a
    /// bedtime after midnight.
    private var restlessNight: StressDayNightSplit {
        StressDayNightSplit(
            day: StressDayNightSplit.Period(
                interval: DateInterval(start: time(7, 5, dayOffset: -1), end: time(0, 0)),
                minutesByBand: [.rest: 240, .low: 480, .medium: 90],
                activityMinutes: 75,
                scoredWindowCount: 54,
                averageScore: 38,
                peak: StressDayNightSplit.Peak(score: 72, start: time(16, 0, dayOffset: -1))
            ),
            night: StressDayNightSplit.Period(
                interval: DateInterval(start: time(23, 52, dayOffset: -2), end: time(7, 5, dayOffset: -1)),
                minutesByBand: [.rest: 360, .low: 30, .medium: 15],
                scoredWindowCount: 27,
                averageScore: 7,
                peak: StressDayNightSplit.Peak(score: 58, start: time(1, 45, dayOffset: -1)),
                restlessMinutes: 45
            ),
            isToday: false,
            daySpan: .toMidnight(start: time(7, 5, dayOffset: -1))
        )
    }

    /// The widest headlines on both sides: a Stressed day and a night all in Peace.
    private var widestHeadlines: StressDayNightSplit {
        StressDayNightSplit(
            day: StressDayNightSplit.Period(
                interval: DateInterval(start: time(6, 30, dayOffset: -1), end: time(23, 45, dayOffset: -1)),
                minutesByBand: [.low: 120, .medium: 300, .high: 420],
                activityMinutes: 30,
                scoredWindowCount: 56,
                averageScore: 88,
                peak: StressDayNightSplit.Peak(score: 100, start: time(11, 45, dayOffset: -1))
            ),
            night: StressDayNightSplit.Period(
                interval: DateInterval(start: time(22, 55, dayOffset: -2), end: time(6, 30, dayOffset: -1)),
                minutesByBand: [.rest: 450],
                scoredWindowCount: 30,
                averageScore: 2
            ),
            isToday: false,
            daySpan: .range(start: time(6, 30, dayOffset: -1), end: time(23, 45, dayOffset: -1))
        )
    }

    private func render(_ split: StressDayNightSplit, locale: Locale, width: CGFloat = cardWidth) -> UIImage? {
        let card = BodyStressDayNightCard(split: split)
            .frame(width: width)
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .environment(\.locale, locale)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = Self.scale
        return renderer.uiImage
    }

    func testEveryStateRendersInEnglishAndSimplifiedChinese() throws {
        let states: [(StressDayNightSplit, String)] = [
            (fullDay, "today"),
            (noSleep, "noSleep"),
            (sparseNight, "sparseNight"),
            (restlessNight, "restlessNight")
        ]

        for (split, name) in states {
            for identifier in ["en", "zh-Hans"] {
                let image = try XCTUnwrap(render(split, locale: Locale(identifier: identifier)), "\(name)/\(identifier)")
                XCTAssertEqual(image.size.width, Self.cardWidth + 32, accuracy: 0.5, "\(name)/\(identifier)")
                XCTAssertGreaterThan(image.size.height, 150, "\(name)/\(identifier)")

                write(image, name: "stress-day-night-\(name)-\(identifier).png")
            }
        }
    }

    func testTheWidestHeadlinesFitANarrowPhone() throws {
        for identifier in ["en", "zh-Hans"] {
            let image = try XCTUnwrap(
                render(widestHeadlines, locale: Locale(identifier: identifier), width: Self.narrowCardWidth),
                identifier
            )
            XCTAssertEqual(image.size.width, Self.narrowCardWidth + 32, accuracy: 0.5, identifier)

            write(image, name: "stress-day-night-narrow-\(identifier).png")
        }
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
