//
//  SleepConsistencyChartModelTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class SleepConsistencyChartModelTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    func testNightCrossingMidnightProducesNegativeBedOffset() throws {
        let day = try date(2026, 6, 10)
        let snapshot = SleepStageSnapshot(date: day, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 9, 23, 30), endDate: try date(2026, 6, 10, 3, 0)),
            SleepStageSegment(stage: .rem, startDate: try date(2026, 6, 10, 3, 0), endDate: try date(2026, 6, 10, 7, 45))
        ])

        let model = SleepConsistencyChartModel.make(entries: [(day: day, snapshot: snapshot)], calendar: calendar)

        let night = try XCTUnwrap(model.nights.first)
        XCTAssertEqual(night.day, day)
        XCTAssertEqual(night.bedOffsetHours, -0.5, accuracy: 0.001)
        XCTAssertEqual(night.wakeOffsetHours, 7.75, accuracy: 0.001)
        XCTAssertEqual(night.slices.count, 2)
        XCTAssertEqual(night.slices[0].stage, .core)
        XCTAssertEqual(night.slices[0].startOffsetHours, -0.5, accuracy: 0.001)
        XCTAssertEqual(night.slices[0].endOffsetHours, 3.0, accuracy: 0.001)
        XCTAssertEqual(night.slices[1].stage, .rem)
        XCTAssertEqual(night.slices[1].startOffsetHours, 3.0, accuracy: 0.001)
        XCTAssertEqual(night.slices[1].endOffsetHours, 7.75, accuracy: 0.001)
    }

    func testNightStartingAfterMidnightProducesPositiveOffsets() throws {
        let day = try date(2026, 6, 10)
        let snapshot = SleepStageSnapshot(date: day, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 10, 1, 15), endDate: try date(2026, 6, 10, 9, 0))
        ])

        let model = SleepConsistencyChartModel.make(entries: [(day: day, snapshot: snapshot)], calendar: calendar)

        let night = try XCTUnwrap(model.nights.first)
        XCTAssertEqual(night.bedOffsetHours, 1.25, accuracy: 0.001)
        XCTAssertEqual(night.wakeOffsetHours, 9.0, accuracy: 0.001)
    }

    func testAveragesAcrossNights() throws {
        let firstDay = try date(2026, 6, 9)
        let secondDay = try date(2026, 6, 10)
        let firstSnapshot = SleepStageSnapshot(date: firstDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 8, 23, 0), endDate: try date(2026, 6, 9, 7, 0))
        ])
        let secondSnapshot = SleepStageSnapshot(date: secondDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 10, 2, 0), endDate: try date(2026, 6, 10, 9, 0))
        ])

        let model = SleepConsistencyChartModel.make(
            entries: [(day: firstDay, snapshot: firstSnapshot), (day: secondDay, snapshot: secondSnapshot)],
            calendar: calendar
        )

        XCTAssertEqual(try XCTUnwrap(model.averageBedOffsetHours), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(model.averageWakeOffsetHours), 8.0, accuracy: 0.001)
    }

    func testMissingDaysKeepSlotsWithoutNights() throws {
        let firstDay = try date(2026, 6, 8)
        let middleDay = try date(2026, 6, 9)
        let lastDay = try date(2026, 6, 10)
        let firstSnapshot = SleepStageSnapshot(date: firstDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 7, 23, 0), endDate: try date(2026, 6, 8, 7, 0))
        ])
        let lastSnapshot = SleepStageSnapshot(date: lastDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 9, 23, 0), endDate: try date(2026, 6, 10, 7, 0))
        ])

        let model = SleepConsistencyChartModel.make(
            entries: [
                (day: firstDay, snapshot: firstSnapshot),
                (day: middleDay, snapshot: nil),
                (day: lastDay, snapshot: lastSnapshot)
            ],
            calendar: calendar
        )

        XCTAssertEqual(model.days, [firstDay, middleDay, lastDay])
        XCTAssertEqual(model.nights.map(\.day), [firstDay, lastDay])
    }

    func testEmptyEntriesProduceEmptyModel() throws {
        let day = try date(2026, 6, 10)

        let model = SleepConsistencyChartModel.make(
            entries: [
                (day: day, snapshot: nil),
                (day: try date(2026, 6, 11), snapshot: SleepStageSnapshot(date: nil, segments: []))
            ],
            calendar: calendar
        )

        XCTAssertTrue(model.nights.isEmpty)
        XCTAssertNil(model.averageBedOffsetHours)
        XCTAssertNil(model.averageWakeOffsetHours)
    }

    func testDomainPadsBedAndWakeByHalfHour() throws {
        let day = try date(2026, 6, 10)
        let snapshot = SleepStageSnapshot(date: day, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 9, 23, 30), endDate: try date(2026, 6, 10, 7, 45))
        ])

        let model = SleepConsistencyChartModel.make(entries: [(day: day, snapshot: snapshot)], calendar: calendar)

        XCTAssertEqual(model.yDomainHours.lowerBound, -1.0, accuracy: 0.001)
        XCTAssertEqual(model.yDomainHours.upperBound, 8.25, accuracy: 0.001)
    }

    func testGridOffsetsEveryTwoHoursSuppressedNearAverages() throws {
        let day = try date(2026, 6, 10)
        let snapshot = SleepStageSnapshot(date: day, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 9, 23, 30), endDate: try date(2026, 6, 10, 7, 45))
        ])

        let model = SleepConsistencyChartModel.make(entries: [(day: day, snapshot: snapshot)], calendar: calendar)

        // Domain is -1.0...8.25; candidates 0, 2, 4, 6, 8. The averages sit at
        // -0.5 and 7.75, so 0 and 8 fall inside the suppression window.
        XCTAssertEqual(model.gridHourOffsets, [2, 4, 6])
    }

    func testClockDateNormalizesOffsetsIntoDay() throws {
        let day = try date(2026, 6, 10)

        let beforeMidnight = SleepConsistencyChartModel.clockDate(forOffsetHours: -0.5, on: day, calendar: calendar)
        let beforeComponents = calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(beforeMidnight))
        XCTAssertEqual(beforeComponents.hour, 23)
        XCTAssertEqual(beforeComponents.minute, 30)

        let afterMidnight = SleepConsistencyChartModel.clockDate(forOffsetHours: 1.0 + 46.0 / 60.0, on: day, calendar: calendar)
        let afterComponents = calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(afterMidnight))
        XCTAssertEqual(afterComponents.hour, 1)
        XCTAssertEqual(afterComponents.minute, 46)

        let wrapped = SleepConsistencyChartModel.clockDate(forOffsetHours: 25.5, on: day, calendar: calendar)
        let wrappedComponents = calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(wrapped))
        XCTAssertEqual(wrappedComponents.hour, 1)
        XCTAssertEqual(wrappedComponents.minute, 30)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }
}
