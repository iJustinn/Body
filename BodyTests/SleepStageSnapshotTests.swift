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

    // MARK: napSessions

    /// Night 23:30–07:45 as the main session, plus whatever nap segments the
    /// case needs.
    private func snapshotWithNight(napSegments: [SleepStageSegment]) -> SleepStageSnapshot {
        let bedtime = date(day: 9, hour: 23, minute: 30)
        let wake = date(7, 45)
        return SleepStageSnapshot(
            date: date(0),
            segments: [SleepStageSegment(stage: .core, startDate: bedtime, endDate: wake)] + napSegments,
            timeZoneIdentifier: "Europe/London",
            mainSessionInterval: DateInterval(start: bedtime, end: wake)
        )
    }

    func testNapSessionsSplitAfternoonNapFromTheNight() {
        let nap = SleepStageSegment(stage: .core, startDate: date(14), endDate: date(15, 12))
        let snapshot = snapshotWithNight(napSegments: [nap])

        let naps = snapshot.napSessions
        XCTAssertEqual(naps.count, 1)
        XCTAssertEqual(naps.first?.segments, [nap])
        // Metadata rides along, but the nap is no longer inside a main session.
        XCTAssertEqual(naps.first?.date, snapshot.date)
        XCTAssertEqual(naps.first?.timeZoneIdentifier, "Europe/London")
        XCTAssertNil(naps.first?.mainSessionInterval)

        // The night's own card is untouched.
        XCTAssertEqual(snapshot.mainSession.segments, [
            SleepStageSegment(stage: .core, startDate: date(day: 9, hour: 23, minute: 30), endDate: date(7, 45))
        ])
        XCTAssertEqual(snapshot.napsSnapshot.segments, [nap])
    }

    func testNapSessionsSplitOnTwoHourGapOnly() {
        // 10:40 → 14:00 is more than the 2h session gap: two naps.
        let morningNap = SleepStageSegment(stage: .core, startDate: date(10), endDate: date(10, 40))
        let afternoonNap = SleepStageSegment(stage: .core, startDate: date(14), endDate: date(14, 50))
        let split = snapshotWithNight(napSegments: [morningNap, afternoonNap])

        XCTAssertEqual(split.napSessions.map(\.segments), [[morningNap], [afternoonNap]])
        XCTAssertEqual(split.napsSnapshot.segments, [morningNap, afternoonNap])

        // 10:40 → 12:30 is inside the gap: one nap spanning both blocks.
        let secondBlock = SleepStageSegment(stage: .core, startDate: date(12, 30), endDate: date(13, 10))
        let joined = snapshotWithNight(napSegments: [morningNap, secondBlock])

        XCTAssertEqual(joined.napSessions.map(\.segments), [[morningNap, secondBlock]])
    }

    func testNapSessionsMeasureGapFromLatestEndSoFar() {
        // An aggregate 14:00–17:00 sample with detailed samples nested inside it.
        // Measured from the previous segment's end, 14:30 → 16:50 would look like
        // a 2h20 gap and wrongly split one nap in two.
        let aggregate = SleepStageSegment(stage: .core, startDate: date(14), endDate: date(17))
        let firstDetail = SleepStageSegment(stage: .core, startDate: date(14, 5), endDate: date(14, 30))
        let lastDetail = SleepStageSegment(stage: .deep, startDate: date(16, 50), endDate: date(17))
        let snapshot = snapshotWithNight(napSegments: [aggregate, firstDetail, lastDetail])

        XCTAssertEqual(snapshot.napSessions.map(\.segments), [[aggregate, firstDetail, lastDetail]])
    }

    func testNapSessionsAreEmptyWithoutMainSessionInterval() {
        // Old caches and fixtures carry no interval, so there's no night to
        // separate naps from; the snapshot must not spawn phantom nap cards.
        let snapshot = SleepStageSnapshot(date: date(0), segments: [
            SleepStageSegment(stage: .core, startDate: date(day: 9, hour: 23, minute: 30), endDate: date(7, 45)),
            SleepStageSegment(stage: .core, startDate: date(14), endDate: date(15, 12))
        ])

        XCTAssertNil(snapshot.mainSessionInterval)
        XCTAssertTrue(snapshot.napSessions.isEmpty)
        XCTAssertTrue(snapshot.napsSnapshot.isEmpty)
    }

    func testNapSessionsDropAwakeOnlyAndVeryShortGroups() {
        let snapshot = snapshotWithNight(napSegments: [
            SleepStageSegment(stage: .awake, startDate: date(10), endDate: date(11)),
            SleepStageSegment(stage: .core, startDate: date(18), endDate: date(18, 3))
        ])

        XCTAssertTrue(snapshot.napSessions.isEmpty)
        XCTAssertTrue(snapshot.napsSnapshot.isEmpty)
    }

    func testNapSessionsAreEmptyWithoutSegmentsOutsideMainSession() {
        let snapshot = snapshotWithNight(napSegments: [])

        XCTAssertTrue(snapshot.napSessions.isEmpty)
        XCTAssertTrue(snapshot.napsSnapshot.isEmpty)
        XCTAssertEqual(snapshot.napsSnapshot.date, snapshot.date)
    }
}
