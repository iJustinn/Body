//
//  MetricWarningNotificationLedgerTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class MetricWarningNotificationLedgerTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(kind: MetricWarningKind, start: Date) -> MetricWarningEvent {
        MetricWarningEvent(
            kind: kind,
            startDate: start,
            endDate: start,
            extremeValue: kind.defaultThreshold,
            sampleCount: 1
        )
    }

    func testFirstWarningOfDayFires() {
        let ledger = MetricWarningNotificationLedger.defaultValue
        let event = event(kind: .lowHeartRate, start: date(2025, 3, 14, 9))

        XCTAssertTrue(ledger.shouldNotify(kind: .lowHeartRate, event: event, calendar: calendar))
    }

    func testSameKindSameDayDoesNotFireAgain() {
        var ledger = MetricWarningNotificationLedger.defaultValue
        ledger.markNotified(kind: .lowHeartRate, on: date(2025, 3, 14, 9), calendar: calendar)

        let laterEvent = event(kind: .lowHeartRate, start: date(2025, 3, 14, 20))

        XCTAssertFalse(ledger.shouldNotify(kind: .lowHeartRate, event: laterEvent, calendar: calendar))
    }

    func testKindsAreIndependent() {
        var ledger = MetricWarningNotificationLedger.defaultValue
        ledger.markNotified(kind: .lowHeartRate, on: date(2025, 3, 14, 9), calendar: calendar)

        let highHeartRateEvent = event(kind: .highHeartRate, start: date(2025, 3, 14, 9))
        let bloodOxygenEvent = event(kind: .lowBloodOxygen, start: date(2025, 3, 14, 9))

        XCTAssertTrue(ledger.shouldNotify(kind: .highHeartRate, event: highHeartRateEvent, calendar: calendar))
        XCTAssertTrue(ledger.shouldNotify(kind: .lowBloodOxygen, event: bloodOxygenEvent, calendar: calendar))
    }

    func testNextCalendarDayFiresAgain() {
        var ledger = MetricWarningNotificationLedger.defaultValue
        ledger.markNotified(kind: .lowHeartRate, on: date(2025, 3, 14, 23, 59), calendar: calendar)

        let nextDayEvent = event(kind: .lowHeartRate, start: date(2025, 3, 15, 0, 1))

        XCTAssertTrue(ledger.shouldNotify(kind: .lowHeartRate, event: nextDayEvent, calendar: calendar))
    }

    func testCorruptStorageStringDecodesToEmptyLedger() {
        XCTAssertEqual(MetricWarningNotificationLedger.storedValue(from: "not json"), .defaultValue)
        XCTAssertEqual(MetricWarningNotificationLedger.storedValue(from: ""), .defaultValue)
        XCTAssertEqual(MetricWarningNotificationLedger.storedValue(from: "   "), .defaultValue)
    }

    func testEncodeDecodeRoundTripPreservesEntries() {
        var ledger = MetricWarningNotificationLedger.defaultValue
        ledger.markNotified(kind: .lowHeartRate, on: date(2025, 3, 14, 9), calendar: calendar)
        ledger.markNotified(kind: .highHeartRate, on: date(2025, 3, 15, 9), calendar: calendar)

        let decoded = MetricWarningNotificationLedger.storedValue(from: ledger.rawValue)

        XCTAssertEqual(decoded, ledger)
        XCTAssertFalse(decoded.shouldNotify(
            kind: .lowHeartRate,
            event: event(kind: .lowHeartRate, start: date(2025, 3, 14, 21)),
            calendar: calendar
        ))
        XCTAssertFalse(decoded.shouldNotify(
            kind: .highHeartRate,
            event: event(kind: .highHeartRate, start: date(2025, 3, 15, 21)),
            calendar: calendar
        ))
    }
}
