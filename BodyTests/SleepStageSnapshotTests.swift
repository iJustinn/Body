//
//  SleepStageSnapshotTests.swift
//  BodyTests
//
//  Locks `SleepStageSnapshot.mergedAsleepDuration` — the union-of-asleep-time
//  measure the watch uses for its displayed Sleep duration (and the readiness
//  it feeds). Overlapping HealthKit sleep samples (an aggregate `asleep` plus
//  detailed `asleepCore/REM/Deep` over the same window, or multiple sources)
//  must collapse into their union instead of double-counting; the raw
//  per-stage `asleepDuration` sum is what produced the inflated 26h on-watch
//  nights, so these also assert the two measures differ when samples overlap.
//

import XCTest
@testable import Body

final class SleepStageSnapshotTests: XCTestCase {
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 6, day: 10, hour: hour, minute: minute)
        )!
    }

    func testOverlappingAsleepSegmentsMergeIntoUnion() {
        // 8h aggregate sleep with detailed stages nested inside the same window.
        let snapshot = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .core, startDate: date(0), endDate: date(8)),
            SleepStageSegment(stage: .rem, startDate: date(2), endDate: date(6)),
            SleepStageSegment(stage: .deep, startDate: date(1), endDate: date(2))
        ])

        // Raw per-stage sum double-counts the nested stages (8 + 4 + 1 = 13h).
        XCTAssertEqual(snapshot.asleepDuration, 13 * 3600, accuracy: 1)
        // Merged collapses them to the wall-clock union (00:00–08:00 = 8h).
        XCTAssertEqual(snapshot.mergedAsleepDuration, 8 * 3600, accuracy: 1)
        XCTAssertNotEqual(snapshot.mergedAsleepDuration, snapshot.asleepDuration)
    }

    func testAdjacentSegmentsMergeAndGapsAreExcluded() {
        // Touching blocks form one union with no double count.
        let adjacent = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .core, startDate: date(0), endDate: date(4)),
            SleepStageSegment(stage: .deep, startDate: date(4), endDate: date(6))
        ])
        XCTAssertEqual(adjacent.mergedAsleepDuration, 6 * 3600, accuracy: 1)

        // A gap between blocks is excluded; the blocks themselves still sum.
        let gapped = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .core, startDate: date(0), endDate: date(4)),
            SleepStageSegment(stage: .deep, startDate: date(5), endDate: date(6))
        ])
        XCTAssertEqual(gapped.mergedAsleepDuration, 5 * 3600, accuracy: 1)
    }

    func testAwakeSegmentsExcludedFromMergedDuration() {
        let snapshot = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .core, startDate: date(0), endDate: date(8)),
            SleepStageSegment(stage: .awake, startDate: date(3), endDate: date(4))
        ])
        // Only asleep stages count toward the union; awake is ignored.
        XCTAssertEqual(snapshot.mergedAsleepDuration, 8 * 3600, accuracy: 1)
    }

    func testEmptySnapshotHasZeroMergedDuration() {
        XCTAssertEqual(SleepStageSnapshot.empty.mergedAsleepDuration, 0)
    }
}
