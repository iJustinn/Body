//
//  BodyTimeZoneLedgerTests.swift
//  BodyTests
//
//  Covers the device time-zone ledger that back-fills a night's zone when its
//  sleep samples carry no HealthKit metadata (e.g. Apple Watch).
//

import HealthKit
import XCTest
@testable import Body

final class BodyTimeZoneLedgerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var ledger: BodyTimeZoneLedger!

    private let newYork = "America/New_York"
    private let london = "Europe/London"

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "BodyTests.TimeZoneLedger.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ledger = BodyTimeZoneLedger(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        ledger = nil
        try super.tearDownWithError()
    }

    /// Noon on the given day in the current calendar, so end-of-day lookups land
    /// unambiguously on the intended day regardless of the machine's zone.
    private func day(_ day: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 6, day: day, hour: 12)
        ))
    }

    func testFirstRecordSeedsLedger() throws {
        ledger.recordCurrentZone(now: try day(10), zone: try XCTUnwrap(TimeZone(identifier: newYork)))

        XCTAssertEqual(ledger.loadRecords().count, 1)
        XCTAssertEqual(ledger.zoneIdentifier(on: try day(10)), newYork)
    }

    func testSameZoneDoesNotAppendDuplicate() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: newYork))
        ledger.recordCurrentZone(now: try day(10), zone: zone)
        ledger.recordCurrentZone(now: try day(11), zone: zone)
        ledger.recordCurrentZone(now: try day(12), zone: zone)

        XCTAssertEqual(ledger.loadRecords().count, 1)
        XCTAssertEqual(ledger.zoneIdentifier(on: try day(12)), newYork)
    }

    func testZoneChangeAppendsNewRecord() throws {
        ledger.recordCurrentZone(now: try day(10), zone: try XCTUnwrap(TimeZone(identifier: newYork)))
        ledger.recordCurrentZone(now: try day(16), zone: try XCTUnwrap(TimeZone(identifier: london)))

        XCTAssertEqual(ledger.loadRecords().count, 2)
    }

    func testLookupResolvesLatestRecordOnAndAfterEffectiveDay() throws {
        ledger.recordCurrentZone(now: try day(10), zone: try XCTUnwrap(TimeZone(identifier: newYork)))
        ledger.recordCurrentZone(now: try day(16), zone: try XCTUnwrap(TimeZone(identifier: london)))

        // Before the change: New York. On and after the change day: London.
        XCTAssertEqual(ledger.zoneIdentifier(on: try day(15)), newYork)
        XCTAssertEqual(ledger.zoneIdentifier(on: try day(16)), london)
        XCTAssertEqual(ledger.zoneIdentifier(on: try day(20)), london)
    }

    func testLookupIsNilBeforeFirstRecord() throws {
        ledger.recordCurrentZone(now: try day(10), zone: try XCTUnwrap(TimeZone(identifier: newYork)))

        // A day that predates the first record stays unknown rather than being
        // back-filled with the first known zone.
        XCTAssertNil(ledger.zoneIdentifier(on: try day(9)))
    }

    func testLookupBoundaryIsTrueMidnightOnDSTFallBackDay() throws {
        // Nov 1 2026 in New York is a 25-hour fall-back day: startOfDay + 86_400
        // is 23:00 that evening, not the next midnight. A change recorded in the
        // 23:00–24:00 gap must still count as in effect on Nov 1's lookup.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: newYork))
        let dstLedger = BodyTimeZoneLedger(defaults: defaults, calendar: calendar)

        let october = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)
        ))
        let lateFallBackEvening = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 30)
        ))
        let fallBackNoon = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)
        ))
        dstLedger.recordCurrentZone(now: october, zone: try XCTUnwrap(TimeZone(identifier: newYork)))
        dstLedger.recordCurrentZone(now: lateFallBackEvening, zone: try XCTUnwrap(TimeZone(identifier: london)))

        XCTAssertEqual(dstLedger.zoneIdentifier(on: fallBackNoon), london)
    }

    func testRecordsAreSortedByEffectiveDateOnLoad() throws {
        // A clock rollback (manual date change, NTP correction) can append a
        // record that is older than the one before it. Storage order would then
        // make the London record the last one and answer every later day with it.
        ledger.recordCurrentZone(now: try day(16), zone: try XCTUnwrap(TimeZone(identifier: newYork)))
        ledger.recordCurrentZone(now: try day(10), zone: try XCTUnwrap(TimeZone(identifier: london)))

        XCTAssertEqual(ledger.loadRecords().map(\.identifier), [london, newYork])
        XCTAssertEqual(ledger.zoneIdentifier(on: try day(20)), newYork)
    }

    func testSnapshotDayLookupMatchesTheLedgerOnDSTFallBackDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: newYork))
        let dstLedger = BodyTimeZoneLedger(defaults: defaults, calendar: calendar)

        let october = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)
        ))
        let lateFallBackEvening = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 30)
        ))
        let fallBackNoon = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)
        ))
        dstLedger.recordCurrentZone(now: october, zone: try XCTUnwrap(TimeZone(identifier: newYork)))
        dstLedger.recordCurrentZone(now: lateFallBackEvening, zone: try XCTUnwrap(TimeZone(identifier: london)))

        // Both pinned to London rather than compared with each other: the ledger's
        // day lookup forwards to the snapshot's, so an equality between the two
        // would hold whatever either of them answered.
        XCTAssertEqual(dstLedger.snapshot().zoneIdentifier(on: fallBackNoon), london)
        XCTAssertEqual(dstLedger.zoneIdentifier(on: fallBackNoon), london)
    }

    /// The instant lookup's boundary is inclusive (`<=`), so a workout that starts
    /// in the same second the zone was recorded reads as the new zone.
    func testInstantLookupIncludesTheRecordsOwnInstant() throws {
        let change = try day(15)
        ledger.recordCurrentZone(now: try day(10), zone: try XCTUnwrap(TimeZone(identifier: newYork)))
        ledger.recordCurrentZone(now: change, zone: try XCTUnwrap(TimeZone(identifier: london)))

        XCTAssertEqual(ledger.snapshot().zoneIdentifier(at: change), london)
    }

    /// Unknown history stays unknown: before the first record there is no zone to
    /// name, and the caller falls back to its own calendar rather than to today's
    /// zone dressed up as history.
    func testInstantLookupIsNilBeforeTheFirstRecord() throws {
        ledger.recordCurrentZone(now: try day(10), zone: try XCTUnwrap(TimeZone(identifier: newYork)))

        XCTAssertNil(ledger.snapshot().zoneIdentifier(at: try day(9)))
    }

    /// The instant lookup is what workouts use: a zone change partway through a
    /// day splits that day, instead of naming the whole day by the zone in
    /// effect at its end.
    func testInstantLookupSplitsTheDayTheZoneChanged() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func instant(day: Int, hour: Int) throws -> Date {
            try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour)))
        }

        ledger.recordCurrentZone(now: try instant(day: 10, hour: 12), zone: try XCTUnwrap(TimeZone(identifier: newYork)))
        ledger.recordCurrentZone(now: try instant(day: 15, hour: 10), zone: try XCTUnwrap(TimeZone(identifier: london)))

        let resolver = ledger.snapshot()
        XCTAssertEqual(resolver.zoneIdentifier(at: try instant(day: 15, hour: 6)), newYork)
        XCTAssertEqual(resolver.zoneIdentifier(at: try instant(day: 15, hour: 12)), london)
        // The day-scoped lookup, by contrast, names the whole day London.
        XCTAssertEqual(resolver.zoneIdentifier(on: try instant(day: 15, hour: 6)), london)

        // Zone-independent: the answer cannot depend on the calendar the ledger
        // happens to hold, unlike the day-scoped rule.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let tokyoResolver = BodyTimeZoneLedger(defaults: defaults, calendar: tokyo).snapshot()
        XCTAssertEqual(tokyoResolver.zoneIdentifier(at: try instant(day: 15, hour: 6)), newYork)
        XCTAssertEqual(tokyoResolver.zoneIdentifier(at: try instant(day: 15, hour: 12)), london)
    }

    /// The Workouts tab refreshes a month without going through either sleep
    /// fetch, so `fetchWorkouts` seeds the ledger itself, before its query runs
    /// (here the query is cancelled and never answers).
    func testFetchWorkoutsRecordsTheCurrentZone() async throws {
        let engine = HealthKitFetchEngine(
            permission: .defaultValue,
            healthDataSourceSelection: BodyHealthDataSourceSelection(selectedOptions: [:]),
            secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection(selectedOptions: [:]),
            combinesHealthDataSourcesByName: false,
            healthStore: FakeHealthStore(),
            timeZoneLedger: ledger
        )

        let task = Task {
            try await engine.fetchWorkouts(month: 6, year: 2026, calendar: .bodyGregorian)
        }
        task.cancel()
        _ = try? await task.value

        XCTAssertEqual(ledger.loadRecords().count, 1)
        XCTAssertEqual(ledger.loadRecords().first?.identifier, TimeZone.current.identifier)
    }
}
