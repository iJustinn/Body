//
//  DayRingScreenshotTests.swift
//  BodyTests
//
//  Opt-in writer for `app-screenshots/`: rasterizes the Day Ring hero at phone width on
//  the dark page for the merged workout bars, one PNG per case. It touches the
//  worktree, so it skips unless `BODY_DAYRING_SCREENSHOTS=1` is in the environment.
//  Not a snapshot test.
//

import XCTest
import SwiftUI
import UIKit
@testable import Body

@MainActor
final class DayRingScreenshotTests: XCTestCase {
    private var calendar: Calendar { .bodyGregorian }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute))!
    }

    private func workout(_ type: BodyWorkoutType, _ start: Date, minutes: Int) -> WorkoutSummary {
        WorkoutSummary(id: UUID(), type: type, startDate: start, duration: TimeInterval(minutes * 60), endDate: start.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// Run it with:
    /// `TEST_RUNNER_BODY_DAYRING_SCREENSHOTS=1 xcodebuild … -only-testing:BodyTests/DayRingScreenshotTests`
    func testWritesDayRingMergedWorkoutScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BODY_DAYRING_SCREENSHOTS"] == "1",
            "Set BODY_DAYRING_SCREENSHOTS=1 to regenerate the Day Ring screenshots"
        )

        let directory = BodyTestSupport.projectRoot.appendingPathComponent("app-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sleep = [SleepStageSegment(stage: .core, startDate: date(0), endDate: date(6, 30))]
        let cases: [(name: String, workouts: [WorkoutSummary])] = [
            ("day-ring-merged-same-type-x3", [
                workout(.running, date(12, 0), minutes: 5),
                workout(.running, date(12, 8), minutes: 5),
                workout(.running, date(12, 16), minutes: 5)
            ]),
            ("day-ring-merged-walk-run", [
                workout(.walking, date(12, 0), minutes: 5),
                workout(.running, date(12, 8), minutes: 5)
            ]),
            ("day-ring-merged-walk-run-strength", [
                workout(.walking, date(12, 0), minutes: 5),
                workout(.running, date(12, 8), minutes: 12),
                workout(.strengthTraining, date(12, 23), minutes: 5)
            ])
        ]

        let width: CGFloat = 393
        for item in cases {
            let hero = BodyDayRingHero(
                sleepSegments: sleep,
                workouts: item.workouts,
                width: width,
                previewDate: date(19, 30)
            )
            .frame(width: width, height: BodyReadinessArcGeometry.heroHeight(width: width), alignment: .topLeading)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: hero)
            renderer.scale = 3
            let data = try XCTUnwrap(renderer.uiImage?.pngData(), "no PNG for \(item.name)")
            try data.write(to: directory.appendingPathComponent("\(item.name).png"))
        }
    }
}
