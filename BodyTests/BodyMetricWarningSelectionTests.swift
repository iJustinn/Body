//
//  BodyMetricWarningSelectionTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class BodyMetricWarningSelectionTests: XCTestCase {
    func testEmptyStoredValueDecodesToAllKindsEnabled() {
        let selection = BodyMetricWarningSelection.storedValue(from: "")

        XCTAssertEqual(selection, .defaultValue)
        XCTAssertEqual(selection.enabledCount, selection.totalCount)
        XCTAssertTrue(selection.includes(.highHeartRate))
    }

    func testUnknownTokensFallBackToTheDefault() {
        let selection = BodyMetricWarningSelection.storedValue(from: "lowBloodPressure")

        XCTAssertEqual(selection, .defaultValue)
    }

    func testCustomSubsetStoredValueIsPreserved() {
        let selection = BodyMetricWarningSelection.storedValue(from: "lowHeartRate,lowBloodOxygen")

        XCTAssertEqual(selection.enabledKinds, [.lowHeartRate, .lowBloodOxygen])
        XCTAssertFalse(selection.includes(.highHeartRate))
        XCTAssertEqual(selection.enabledCount, 2)
    }

    func testNoneStoredValueStaysEmpty() {
        let selection = BodyMetricWarningSelection.storedValue(from: "none")

        XCTAssertTrue(selection.enabledKinds.isEmpty)
        XCTAssertFalse(selection.includes(.lowHeartRate))
    }

    func testSettingAKindOffThenOnRoundTrips() {
        let off = BodyMetricWarningSelection.defaultValue.setting(.lowHeartRate, isEnabled: false)
        XCTAssertFalse(off.includes(.lowHeartRate))

        let on = off.setting(.lowHeartRate, isEnabled: true)
        XCTAssertEqual(on, .defaultValue)
    }

    func testEverySelectionRoundTripsThroughRawValue() {
        let selections: [BodyMetricWarningSelection] = [
            .defaultValue,
            .defaultValue.setting(.highHeartRate, isEnabled: false),
            BodyMetricWarningSelection(enabledKinds: [.lowBloodOxygen]),
            BodyMetricWarningSelection(enabledKinds: [])
        ]

        for selection in selections {
            XCTAssertEqual(
                BodyMetricWarningSelection.storedValue(from: selection.rawValue).enabledKinds,
                selection.enabledKinds
            )
        }
    }
}

final class BodyDismissedMetricWarningsTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func event(_ kind: MetricWarningKind, _ date: Date) -> MetricWarningEvent {
        MetricWarningEvent(kind: kind, startDate: date, endDate: date, extremeValue: 130, sampleCount: 1)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testEmptyStoredValueDismissesNothing() {
        let dismissed = BodyDismissedMetricWarnings.storedValue(from: "")

        XCTAssertTrue(dismissed.entries.isEmpty)
        XCTAssertFalse(dismissed.contains(event(.highHeartRate, date(2026, 9, 26))))
    }

    func testDismissingHidesThatKindForTheWholeDayOnly() {
        let now = date(2026, 9, 26, 12)
        let dismissed = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(event(.highHeartRate, date(2026, 9, 26, 9)), now: now)

        // A later refresh can report a different onset on the same day.
        XCTAssertTrue(dismissed.contains(event(.highHeartRate, date(2026, 9, 26, 15))))
        XCTAssertFalse(dismissed.contains(event(.lowHeartRate, date(2026, 9, 26, 9))))
        XCTAssertFalse(dismissed.contains(event(.highHeartRate, date(2026, 9, 27, 9))))
    }

    func testDismissalsRoundTripThroughRawValue() {
        let now = date(2026, 9, 26, 12)
        let dismissed = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(event(.highHeartRate, date(2026, 9, 25)), now: now)
            .dismissing(event(.lowBloodOxygen, date(2026, 9, 26)), now: now)

        XCTAssertEqual(BodyDismissedMetricWarnings.storedValue(from: dismissed.rawValue), dismissed)
    }

    func testDismissingABodyRadarNightHidesOnlyThatNight() {
        let night = BodyRadarNight(date: calendar.startOfDay(for: date(2026, 9, 26)), state: .minorSigns)
        let nextNight = BodyRadarNight(date: calendar.startOfDay(for: date(2026, 9, 27)), state: .majorSigns)
        let dismissed = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(night, now: date(2026, 9, 26, 12))

        XCTAssertTrue(dismissed.contains(night))
        XCTAssertFalse(dismissed.contains(nextNight))
        // A threshold warning on the same day is its own card.
        XCTAssertFalse(dismissed.contains(event(.highHeartRate, date(2026, 9, 26))))
    }

    func testDismissingPrunesEntriesPastTheRetentionWindow() {
        let old = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(event(.highHeartRate, date(2026, 6, 1)), now: date(2026, 6, 1))
        let next = old.dismissing(event(.lowHeartRate, date(2026, 9, 26)), now: date(2026, 9, 26))

        XCTAssertFalse(next.contains(event(.highHeartRate, date(2026, 6, 1))))
        XCTAssertTrue(next.contains(event(.lowHeartRate, date(2026, 9, 26))))
    }
}
