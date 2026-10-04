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

    func testUnfoldingRestoresOnlyThatWarning() {
        let now = date(2026, 9, 26, 12)
        let night = BodyRadarNight(date: calendar.startOfDay(for: date(2026, 9, 26)), state: .minorSigns)
        let folded = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(event(.highHeartRate, date(2026, 9, 26, 9)), now: now)
            .dismissing(event(.lowBloodOxygen, date(2026, 9, 26, 9)), now: now)
            .dismissing(night, now: now)

        let unfolded = folded.unfolding(event(.highHeartRate, date(2026, 9, 26, 15)))
        XCTAssertFalse(unfolded.contains(event(.highHeartRate, date(2026, 9, 26, 9))))
        XCTAssertTrue(unfolded.contains(event(.lowBloodOxygen, date(2026, 9, 26, 9))))
        XCTAssertTrue(unfolded.contains(night))

        let radarUnfolded = unfolded.unfolding(night)
        XCTAssertFalse(radarUnfolded.contains(night))
        XCTAssertTrue(radarUnfolded.contains(event(.lowBloodOxygen, date(2026, 9, 26, 9))))
        XCTAssertEqual(BodyDismissedMetricWarnings.storedValue(from: radarUnfolded.rawValue), radarUnfolded)
    }

    func testUnfoldingAWarningThatWasNeverFoldedChangesNothing() {
        let folded = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(event(.highHeartRate, date(2026, 9, 26)), now: date(2026, 9, 26))

        XCTAssertEqual(folded.unfolding(event(.lowHeartRate, date(2026, 9, 26))), folded)
    }

    func testDismissingPrunesEntriesPastTheRetentionWindow() {
        let old = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(event(.highHeartRate, date(2026, 6, 1)), now: date(2026, 6, 1))
        let next = old.dismissing(event(.lowHeartRate, date(2026, 9, 26)), now: date(2026, 9, 26))

        XCTAssertFalse(next.contains(event(.highHeartRate, date(2026, 6, 1))))
        XCTAssertTrue(next.contains(event(.lowHeartRate, date(2026, 9, 26))))
    }

    /// A watch fold record carries the entry itself, which must fold exactly
    /// what the event based fold does.
    func testDismissingAnEntryMatchesDismissingItsEvent() {
        let now = date(2026, 9, 26, 12)
        let warning = event(.highHeartRate, date(2026, 9, 26, 9))
        let key = BodyDismissedMetricWarnings.entryKey(for: warning)

        let byEntry = BodyDismissedMetricWarnings.storedValue(from: "").dismissing(entry: key, now: now)

        XCTAssertEqual(byEntry, BodyDismissedMetricWarnings.storedValue(from: "").dismissing(warning, now: now))
        XCTAssertTrue(byEntry.contains(event(.highHeartRate, date(2026, 9, 26, 15))))
    }

    func testDismissingAnEntryPrunesLikeTheEventPath() {
        let old = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(event(.highHeartRate, date(2026, 6, 1)), now: date(2026, 6, 1))
        let key = BodyDismissedMetricWarnings.entryKey(for: event(.lowHeartRate, date(2026, 9, 26)))

        let next = old.dismissing(entry: key, now: date(2026, 9, 26))

        XCTAssertEqual(next.entries, [key])
    }

    func testUnfoldingAnEntryRestoresOnlyThatWarning() {
        let now = date(2026, 9, 26, 12)
        let high = event(.highHeartRate, date(2026, 9, 26, 9))
        let low = event(.lowHeartRate, date(2026, 9, 26, 9))
        let folded = BodyDismissedMetricWarnings.storedValue(from: "")
            .dismissing(high, now: now)
            .dismissing(low, now: now)

        let unfolded = folded.unfolding(entry: BodyDismissedMetricWarnings.entryKey(for: high))

        XCTAssertEqual(unfolded, folded.unfolding(high))
        XCTAssertFalse(unfolded.contains(high))
        XCTAssertTrue(unfolded.contains(low))
        // An entry that was never folded changes nothing.
        XCTAssertEqual(unfolded.unfolding(entry: "highHeartRate@2026-09-25"), unfolded)
    }

    /// `isRetained` is the cutoff `dismissing` prunes with: an entry it keeps
    /// survives the next fold, one it drops is pruned by it.
    func testIsRetainedFollowsTheDismissalCutoff() {
        let now = date(2026, 9, 26, 12)
        let lastKeptDay = calendar.date(byAdding: .day, value: -BodyDismissedMetricWarnings.retentionDayCount, to: now)!
        let firstDroppedDay = calendar.date(byAdding: .day, value: -1, to: lastKeptDay)!
        let kept = BodyDismissedMetricWarnings.entryKey(for: event(.highHeartRate, lastKeptDay))
        let dropped = BodyDismissedMetricWarnings.entryKey(for: event(.highHeartRate, firstDroppedDay))

        XCTAssertTrue(BodyDismissedMetricWarnings.isRetained(kept, now: now, calendar: calendar))
        XCTAssertFalse(BodyDismissedMetricWarnings.isRetained(dropped, now: now, calendar: calendar))
        XCTAssertTrue(BodyDismissedMetricWarnings.isRetained(
            BodyDismissedMetricWarnings.entryKey(for: event(.lowHeartRate, now)),
            now: now,
            calendar: calendar
        ))

        let next = BodyDismissedMetricWarnings(entries: [kept, dropped])
            .dismissing(event(.lowHeartRate, now), now: now)
        XCTAssertTrue(next.entries.contains(kept))
        XCTAssertFalse(next.entries.contains(dropped))
    }
}
