//
//  BodyDateFormatterCacheTests.swift
//  BodyTests
//
//  S-02: BodyDateFormatterCache is a process-wide dictionary keyed by a
//  string built from (format/template, calendar, locale, timeZone). These
//  tests pin the identity contract (same key returns the same instance,
//  different key returns a distinct one) and that reusing a cached instance
//  never mutates its dateFormat out from under an earlier caller, for every
//  call-site shape in the production code.
//

import XCTest
@testable import Body

final class BodyDateFormatterCacheTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let frFR = Locale(identifier: "fr_FR")
    private let utc = TimeZone(identifier: "UTC")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    // MARK: - Identity

    func testSameKeyReturnsSameInstance() {
        let a = BodyDateFormatterCache.formatter(dateFormat: "yyyy-MM-dd", locale: enUS, timeZone: utc)
        let b = BodyDateFormatterCache.formatter(dateFormat: "yyyy-MM-dd", locale: enUS, timeZone: utc)
        XCTAssertTrue(a === b)
    }

    func testDifferentLocaleReturnsDistinctInstance() {
        let a = BodyDateFormatterCache.formatter(dateFormat: "yyyy-MM-dd", locale: enUS, timeZone: utc)
        let b = BodyDateFormatterCache.formatter(dateFormat: "yyyy-MM-dd", locale: frFR, timeZone: utc)
        XCTAssertFalse(a === b)
    }

    func testDifferentTimeZoneReturnsDistinctInstance() {
        let a = BodyDateFormatterCache.formatter(dateFormat: "yyyy-MM-dd", locale: enUS, timeZone: utc)
        let b = BodyDateFormatterCache.formatter(dateFormat: "yyyy-MM-dd", locale: enUS, timeZone: tokyo)
        XCTAssertFalse(a === b)
    }

    func testDifferentFirstWeekdayReturnsDistinctInstance() {
        var mondayFirst = Calendar.bodyGregorian
        mondayFirst.firstWeekday = 2
        var sundayFirst = Calendar.bodyGregorian
        sundayFirst.firstWeekday = 1

        let a = BodyDateFormatterCache.formatter(dateFormat: "yyyy-MM-dd", calendar: mondayFirst, locale: enUS, timeZone: utc)
        let b = BodyDateFormatterCache.formatter(dateFormat: "yyyy-MM-dd", calendar: sundayFirst, locale: enUS, timeZone: utc)
        XCTAssertFalse(a === b)
    }

    func testTemplateAndRawFormatKeysDoNotCollide() {
        // "yMMMM" as a raw dateFormat vs. as a template must not share a cache
        // slot; the template variant prefixes its key with "tpl:".
        let raw = BodyDateFormatterCache.formatter(dateFormat: "yMMMM", locale: enUS, timeZone: utc)
        let template = BodyDateFormatterCache.formatter(template: "yMMMM", locale: enUS, timeZone: utc)
        XCTAssertFalse(raw === template)
    }

    // MARK: - Production call-site shapes stay stable after reuse

    func testYMMMMTemplateShapeStaysStable() {
        // BodyMonthYearPicker.swift:19, WorkoutMonthSnapshot.swift:146
        let first = BodyDateFormatterCache.formatter(template: "yMMMM")
        let expected = first.dateFormat
        _ = BodyDateFormatterCache.formatter(template: "yMMMM")
        XCTAssertEqual(first.dateFormat, expected)
    }

    func testMMMMTemplateShapeStaysStable() {
        // BodyMonthYearPicker.swift:349, BodyWorkoutsView.swift:471
        let first = BodyDateFormatterCache.formatter(template: "MMMM")
        let expected = first.dateFormat
        _ = BodyDateFormatterCache.formatter(template: "MMMM")
        XCTAssertEqual(first.dateFormat, expected)
    }

    func testYyyyMMddPOSIXShapeStaysStable() {
        // HealthKitWorkoutStore.swift's recentTimeZoneIdentifiersByDay
        let posix = Locale(identifier: "en_US_POSIX")
        let first = BodyDateFormatterCache.formatter(
            dateFormat: "yyyy-MM-dd",
            calendar: .bodyGregorian,
            locale: posix,
            timeZone: utc
        )
        let expected = first.dateFormat
        _ = BodyDateFormatterCache.formatter(
            dateFormat: "yyyy-MM-dd",
            calendar: .bodyGregorian,
            locale: posix,
            timeZone: utc
        )
        XCTAssertEqual(first.dateFormat, expected)
        XCTAssertEqual(first.dateFormat, "yyyy-MM-dd")
    }

    func testEmptySymbolsShapeStaysStable() {
        // Calendar.bodyRotatedVeryShortWeekdaySymbols, WorkoutMonthSnapshot.swift:316
        let calendar = Calendar.bodyGregorian
        let first = BodyDateFormatterCache.formatter(dateFormat: "", calendar: calendar, locale: enUS)
        let expected = first.dateFormat
        _ = BodyDateFormatterCache.formatter(dateFormat: "", calendar: calendar, locale: enUS)
        XCTAssertEqual(first.dateFormat, expected)
    }
}
