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
