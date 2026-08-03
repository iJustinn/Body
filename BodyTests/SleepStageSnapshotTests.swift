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
        date(day: 10, hour: hour, minute: minute)
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute)
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

    func testSleepStartAndEndDatesExcludeAwakeSegments() {
        // Leading and trailing awake segments bound the in-bed window but not
        // the asleep window.
        let snapshot = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .awake, startDate: date(0), endDate: date(0, 30)),
            SleepStageSegment(stage: .core, startDate: date(0, 30), endDate: date(7)),
            SleepStageSegment(stage: .awake, startDate: date(7), endDate: date(7, 45))
        ])

        XCTAssertEqual(snapshot.sleepStartDate, date(0, 30))
        XCTAssertEqual(snapshot.sleepEndDate, date(7))
        XCTAssertEqual(snapshot.dateInterval?.end, date(7, 45))
    }

    func testSleepStartAndEndDatesAreNilWithoutAsleepSegments() {
        let awakeOnly = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .awake, startDate: date(0), endDate: date(1))
        ])

        XCTAssertNil(awakeOnly.sleepStartDate)
        XCTAssertNil(awakeOnly.sleepEndDate)
        XCTAssertNil(SleepStageSnapshot.empty.sleepEndDate)
    }

    func testDecodesLegacyCacheWithoutTimeZoneIdentifier() throws {
        // An old on-disk cache predates `timeZoneIdentifier`; a payload missing
        // the key must still decode (one nested failure would discard the whole
        // dashboard cache), leaving the field nil.
        let snapshot = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .core, startDate: date(0), endDate: date(8))
        ], timeZoneIdentifier: "Europe/London")

        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object["timeZoneIdentifier"])
        object.removeValue(forKey: "timeZoneIdentifier")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SleepStageSnapshot.self, from: stripped)
        XCTAssertNil(decoded.timeZoneIdentifier)
        XCTAssertEqual(decoded.segments.count, 1)
        XCTAssertEqual(decoded.segments.first?.stage, .core)
    }

    // MARK: mainSession

    func testMainSessionWithoutIntervalReturnsWholeSnapshot() {
        // Fixtures and old caches carry no interval, so the main-session view must
        // degrade to the whole-day snapshot rather than dropping the day's sleep.
        let snapshot = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .core, startDate: date(day: 9, hour: 23, minute: 30), endDate: date(7, 45)),
            SleepStageSegment(stage: .core, startDate: date(14), endDate: date(15, 12))
        ])

        XCTAssertNil(snapshot.mainSessionInterval)
        XCTAssertEqual(snapshot.mainSession, snapshot)
    }

    func testMainSessionKeepsOnlyNightSegmentsAndPreservesMetadata() {
        // Wake-day snapshot holding the night 23:30–07:45 plus a 14:00–15:12 nap.
        let bedtime = date(day: 9, hour: 23, minute: 30)
        let wake = date(7, 45)
        let napStart = date(14)
        let napEnd = date(15, 12)
        let nightSegments = [
            SleepStageSegment(stage: .core, startDate: bedtime, endDate: date(3)),
            SleepStageSegment(stage: .deep, startDate: date(3), endDate: date(4)),
            SleepStageSegment(stage: .rem, startDate: date(4), endDate: wake)
        ]
        let snapshot = SleepStageSnapshot(
            date: date(0),
            segments: nightSegments + [
                SleepStageSegment(stage: .core, startDate: napStart, endDate: napEnd)
            ],
            timeZoneIdentifier: "Europe/London",
            mainSessionInterval: DateInterval(start: bedtime, end: wake)
        )

        let mainSession = snapshot.mainSession
        XCTAssertEqual(mainSession.segments, nightSegments)
        XCTAssertEqual(mainSession.date, snapshot.date)
        XCTAssertEqual(mainSession.timeZoneIdentifier, "Europe/London")
        XCTAssertEqual(mainSession.mainSessionInterval, snapshot.mainSessionInterval)

        // The whole-day snapshot's wake time is the nap's end; the main session's
        // is the night's.
        XCTAssertEqual(snapshot.sleepEndDate, napEnd)
        XCTAssertEqual(mainSession.sleepStartDate, bedtime)
        XCTAssertEqual(mainSession.sleepEndDate, wake)
    }

    func testDecodesLegacyCacheWithoutMainSessionIntervalAndRoundTripsWithIt() throws {
        let bedtime = date(day: 9, hour: 23, minute: 30)
        let wake = date(7, 45)
        let snapshot = SleepStageSnapshot(
            date: date(0),
            segments: [
                SleepStageSegment(stage: .core, startDate: bedtime, endDate: wake),
                SleepStageSegment(stage: .core, startDate: date(14), endDate: date(15, 12))
            ],
            mainSessionInterval: DateInterval(start: bedtime, end: wake)
        )

        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object["mainSessionInterval"])
        object.removeValue(forKey: "mainSessionInterval")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        // An old on-disk cache predates the key; it must still decode (one nested
        // failure discards the whole dashboard cache) with the field nil.
        let legacy = try JSONDecoder().decode(SleepStageSnapshot.self, from: stripped)
        XCTAssertNil(legacy.mainSessionInterval)
        XCTAssertEqual(legacy.segments, snapshot.segments)
        XCTAssertEqual(legacy.mainSession, legacy)

        // With the field present the round-trip preserves it.
        let roundTripped = try JSONDecoder().decode(SleepStageSnapshot.self, from: encoded)
        XCTAssertEqual(roundTripped, snapshot)
        XCTAssertEqual(roundTripped.mainSessionInterval, DateInterval(start: bedtime, end: wake))
        XCTAssertEqual(roundTripped.mainSession.segments, [
            SleepStageSegment(stage: .core, startDate: bedtime, endDate: wake)
        ])
    }
}
