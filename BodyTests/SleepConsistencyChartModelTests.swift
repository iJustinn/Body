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

        let span = try XCTUnwrap(night.spans.first)
        XCTAssertEqual(night.spans.count, 1)
        XCTAssertEqual(span.startOffsetHours, -0.5, accuracy: 0.001)
        XCTAssertEqual(span.endOffsetHours, 7.75, accuracy: 0.001)
        XCTAssertFalse(span.isCutAtStart)
        XCTAssertFalse(span.isCutAtEnd)
        XCTAssertEqual(span.slices.count, 2)
        XCTAssertEqual(span.slices[0].stage, .core)
        XCTAssertEqual(span.slices[0].startOffsetHours, -0.5, accuracy: 0.001)
        XCTAssertEqual(span.slices[0].endOffsetHours, 3.0, accuracy: 0.001)
        XCTAssertEqual(span.slices[1].stage, .rem)
        XCTAssertEqual(span.slices[1].startOffsetHours, 3.0, accuracy: 0.001)
        XCTAssertEqual(span.slices[1].endOffsetHours, 7.75, accuracy: 0.001)
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
        XCTAssertEqual(model.consistencyPercentage, 70)
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
        XCTAssertNil(model.consistencyPercentage)
    }

    func testConsistencyPercentageRequiresAtLeastTwoNights() throws {
        let day = try date(2026, 6, 10)
        let snapshot = SleepStageSnapshot(date: day, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 9, 23, 0), endDate: try date(2026, 6, 10, 7, 0))
        ])

        let model = SleepConsistencyChartModel.make(entries: [(day: day, snapshot: snapshot)], calendar: calendar)

        XCTAssertNil(model.consistencyPercentage)
    }

    func testConsistencyPercentageScoresStableSleepAsPerfect() throws {
        let firstDay = try date(2026, 6, 9)
        let secondDay = try date(2026, 6, 10)
        let firstSnapshot = SleepStageSnapshot(date: firstDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 8, 23, 0), endDate: try date(2026, 6, 9, 7, 0))
        ])
        let secondSnapshot = SleepStageSnapshot(date: secondDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 9, 23, 30), endDate: try date(2026, 6, 10, 7, 30))
        ])

        let model = SleepConsistencyChartModel.make(
            entries: [(day: firstDay, snapshot: firstSnapshot), (day: secondDay, snapshot: secondSnapshot)],
            calendar: calendar
        )

        XCTAssertEqual(model.consistencyPercentage, 100)
    }

    func testConsistencyPercentageScoresOppositeSleepWindowsAsZero() throws {
        let firstDay = try date(2026, 6, 10)
        let secondDay = try date(2026, 6, 11)
        let overnightSnapshot = SleepStageSnapshot(date: firstDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 9, 22, 0), endDate: try date(2026, 6, 10, 6, 0))
        ])
        let daytimeSnapshot = SleepStageSnapshot(date: secondDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 11, 10, 0), endDate: try date(2026, 6, 11, 18, 0))
        ])

        let model = SleepConsistencyChartModel.make(
            entries: [(day: firstDay, snapshot: overnightSnapshot), (day: secondDay, snapshot: daytimeSnapshot)],
            calendar: calendar
        )

        XCTAssertEqual(model.consistencyPercentage, 0)
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

    func testDaySleepCrossingSixPMSplitsIntoWrappedSpans() throws {
        let day = try date(2026, 6, 10)
        let snapshot = SleepStageSnapshot(date: day, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 10, 13, 30), endDate: try date(2026, 6, 10, 19, 0)),
            SleepStageSegment(stage: .rem, startDate: try date(2026, 6, 10, 19, 0), endDate: try date(2026, 6, 10, 22, 30))
        ])

        let model = SleepConsistencyChartModel.make(entries: [(day: day, snapshot: snapshot)], calendar: calendar)

        let night = try XCTUnwrap(model.nights.first)
        XCTAssertEqual(night.bedOffsetHours, 13.5, accuracy: 0.001)
        XCTAssertEqual(night.wakeOffsetHours, 22.5, accuracy: 0.001)
        XCTAssertEqual(night.spans.count, 2)

        let bottom = try XCTUnwrap(night.spans.first)
        XCTAssertEqual(bottom.startOffsetHours, 13.5, accuracy: 0.001)
        XCTAssertEqual(bottom.endOffsetHours, 18.0, accuracy: 0.001)
        XCTAssertFalse(bottom.isCutAtStart)
        XCTAssertTrue(bottom.isCutAtEnd)
        XCTAssertEqual(bottom.slices.count, 1)
        XCTAssertEqual(bottom.slices[0].stage, .core)
        XCTAssertEqual(bottom.slices[0].startOffsetHours, 13.5, accuracy: 0.001)
        XCTAssertEqual(bottom.slices[0].endOffsetHours, 18.0, accuracy: 0.001)

        let top = try XCTUnwrap(night.spans.last)
        XCTAssertEqual(top.startOffsetHours, -6.0, accuracy: 0.001)
        XCTAssertEqual(top.endOffsetHours, -1.5, accuracy: 0.001)
        XCTAssertTrue(top.isCutAtStart)
        XCTAssertFalse(top.isCutAtEnd)
        XCTAssertEqual(top.slices.count, 2)
        XCTAssertEqual(top.slices[0].stage, .core)
        XCTAssertEqual(top.slices[0].startOffsetHours, -6.0, accuracy: 0.001)
        XCTAssertEqual(top.slices[0].endOffsetHours, -5.0, accuracy: 0.001)
        XCTAssertEqual(top.slices[1].stage, .rem)
        XCTAssertEqual(top.slices[1].startOffsetHours, -5.0, accuracy: 0.001)
        XCTAssertEqual(top.slices[1].endOffsetHours, -1.5, accuracy: 0.001)

        XCTAssertNil(model.averageBedOffsetHours)
        XCTAssertNil(model.averageWakeOffsetHours)
    }

    func testEveningBedtimeCrossingSixPMSplits() throws {
        let day = try date(2026, 6, 10)
        let snapshot = SleepStageSnapshot(date: day, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 9, 17, 30), endDate: try date(2026, 6, 10, 1, 30))
        ])

        let model = SleepConsistencyChartModel.make(entries: [(day: day, snapshot: snapshot)], calendar: calendar)

        let night = try XCTUnwrap(model.nights.first)
        XCTAssertEqual(night.bedOffsetHours, 17.5, accuracy: 0.001)
        XCTAssertEqual(night.wakeOffsetHours, 25.5, accuracy: 0.001)
        XCTAssertEqual(night.spans.count, 2)
        XCTAssertEqual(night.spans[0].startOffsetHours, 17.5, accuracy: 0.001)
        XCTAssertEqual(night.spans[0].endOffsetHours, 18.0, accuracy: 0.001)
        XCTAssertTrue(night.spans[0].isCutAtEnd)
        XCTAssertEqual(night.spans[1].startOffsetHours, -6.0, accuracy: 0.001)
        XCTAssertEqual(night.spans[1].endOffsetHours, 1.5, accuracy: 0.001)
        XCTAssertTrue(night.spans[1].isCutAtStart)
    }

    func testSameDayEveningSessionCanonicalizesWithoutSplit() throws {
        let day = try date(2026, 6, 10)
        let snapshot = SleepStageSnapshot(date: day, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 10, 19, 0), endDate: try date(2026, 6, 10, 23, 0))
        ])

        let model = SleepConsistencyChartModel.make(entries: [(day: day, snapshot: snapshot)], calendar: calendar)

        let night = try XCTUnwrap(model.nights.first)
        XCTAssertEqual(night.bedOffsetHours, -5.0, accuracy: 0.001)
        XCTAssertEqual(night.wakeOffsetHours, -1.0, accuracy: 0.001)

        let span = try XCTUnwrap(night.spans.first)
        XCTAssertEqual(night.spans.count, 1)
        XCTAssertFalse(span.isCutAtStart)
        XCTAssertFalse(span.isCutAtEnd)
        XCTAssertEqual(span.slices.count, 1)
        XCTAssertEqual(span.slices[0].startOffsetHours, -5.0, accuracy: 0.001)
        XCTAssertEqual(span.slices[0].endOffsetHours, -1.0, accuracy: 0.001)
    }

    func testTimezoneShiftWindowClampsDomainWidensGridAndHidesAverages() throws {
        let firstDay = try date(2026, 6, 9)
        let secondDay = try date(2026, 6, 10)
        let normalNight = SleepStageSnapshot(date: firstDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 8, 23, 0), endDate: try date(2026, 6, 9, 7, 0))
        ])
        let shiftedNight = SleepStageSnapshot(date: secondDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 10, 13, 30), endDate: try date(2026, 6, 10, 22, 30))
        ])

        let model = SleepConsistencyChartModel.make(
            entries: [(day: firstDay, snapshot: normalNight), (day: secondDay, snapshot: shiftedNight)],
            calendar: calendar
        )

        XCTAssertNil(model.averageBedOffsetHours)
        XCTAssertNil(model.averageWakeOffsetHours)
        XCTAssertEqual(model.yDomainHours.lowerBound, -6.0, accuracy: 0.001)
        XCTAssertEqual(model.yDomainHours.upperBound, 18.0, accuracy: 0.001)
        XCTAssertEqual(model.gridHourOffsets, [-4, 0, 4, 8, 12, 16])
    }

    func testSeamStraddlingBedtimesHideAveragesWithoutWrap() throws {
        let firstDay = try date(2026, 6, 9)
        let secondDay = try date(2026, 6, 10)
        let lateEvening = SleepStageSnapshot(date: firstDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 8, 18, 30), endDate: try date(2026, 6, 9, 1, 0))
        ])
        let afternoonNap = SleepStageSnapshot(date: secondDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 10, 17, 30), endDate: try date(2026, 6, 10, 17, 45))
        ])

        let model = SleepConsistencyChartModel.make(
            entries: [(day: firstDay, snapshot: lateEvening), (day: secondDay, snapshot: afternoonNap)],
            calendar: calendar
        )

        XCTAssertTrue(model.nights.allSatisfy { $0.spans.count == 1 })
        XCTAssertNil(model.averageBedOffsetHours)
        XCTAssertNil(model.averageWakeOffsetHours)
    }

    func testExactBoundaryOffsetsAndSeamSlices() throws {
        let firstDay = try date(2026, 6, 9)
        let secondDay = try date(2026, 6, 10)
        let thirdDay = try date(2026, 6, 11)
        // Bed exactly at the window start (18:00 the prior evening).
        let bedAtWindowStart = SleepStageSnapshot(date: firstDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 8, 18, 0), endDate: try date(2026, 6, 9, 2, 0))
        ])
        // Wake exactly at 18:00 must stay a single uncut span.
        let wakeAtBoundary = SleepStageSnapshot(date: secondDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 10, 10, 0), endDate: try date(2026, 6, 10, 18, 0))
        ])
        // A slice flipping exactly at 18:00 lands wholly in one span each.
        let sliceAtBoundary = SleepStageSnapshot(date: thirdDay, segments: [
            SleepStageSegment(stage: .core, startDate: try date(2026, 6, 11, 16, 0), endDate: try date(2026, 6, 11, 18, 0)),
            SleepStageSegment(stage: .rem, startDate: try date(2026, 6, 11, 18, 0), endDate: try date(2026, 6, 11, 20, 0))
        ])

        let model = SleepConsistencyChartModel.make(
            entries: [
                (day: firstDay, snapshot: bedAtWindowStart),
                (day: secondDay, snapshot: wakeAtBoundary),
                (day: thirdDay, snapshot: sliceAtBoundary)
            ],
            calendar: calendar
        )

        let first = try XCTUnwrap(model.nights.first { $0.day == firstDay })
        XCTAssertEqual(first.bedOffsetHours, -6.0, accuracy: 0.001)
        XCTAssertEqual(first.spans.count, 1)

        let second = try XCTUnwrap(model.nights.first { $0.day == secondDay })
        XCTAssertEqual(second.spans.count, 1)
        XCTAssertEqual(second.spans[0].endOffsetHours, 18.0, accuracy: 0.001)
        XCTAssertFalse(second.spans[0].isCutAtEnd)

        let third = try XCTUnwrap(model.nights.first { $0.day == thirdDay })
        XCTAssertEqual(third.spans.count, 2)
        XCTAssertEqual(third.spans[0].slices.map(\.stage), [.core])
        XCTAssertEqual(third.spans[0].slices[0].startOffsetHours, 16.0, accuracy: 0.001)
        XCTAssertEqual(third.spans[0].slices[0].endOffsetHours, 18.0, accuracy: 0.001)
        XCTAssertEqual(third.spans[1].slices.map(\.stage), [.rem])
        XCTAssertEqual(third.spans[1].slices[0].startOffsetHours, -6.0, accuracy: 0.001)
        XCTAssertEqual(third.spans[1].slices[0].endOffsetHours, -4.0, accuracy: 0.001)
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
