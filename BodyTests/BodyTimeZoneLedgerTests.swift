//
//  BodyTimeZoneLedgerTests.swift
//  BodyTests
//
//  Covers the device time-zone ledger that back-fills a night's zone when its
//  sleep samples carry no HealthKit metadata (e.g. Apple Watch).
//

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
}
