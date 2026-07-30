//
//  BodyMetricDayViewSelectionTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class BodyMetricDayViewSelectionTests: XCTestCase {
    func testEmptyStoredValueDecodesToDefaultIncludingReadiness() {
        let selection = BodyMetricDayViewSelection.storedValue(from: "")

        XCTAssertEqual(selection, .defaultValue)
        XCTAssertTrue(selection.includes(.readiness))
    }

    func testPreReadinessDefaultStoredValueUpgradesToIncludeReadiness() {
        // A selection persisted before the readiness day view shipped: every
        // then-available kind enabled. Readiness could not have been deselected,
        // so the stored value upgrades to the current default.
        let legacyDefault = "heartRate,heartRateVariability,respiratoryRate,oxygenSaturation,activeEnergy,steps"
        let selection = BodyMetricDayViewSelection.storedValue(from: legacyDefault)

        XCTAssertEqual(selection, .defaultValue)
        XCTAssertTrue(selection.includes(.readiness))
    }

    func testCustomSubsetStoredValueIsPreservedWithoutReadiness() {
        let selection = BodyMetricDayViewSelection.storedValue(from: "heartRate,steps")

        XCTAssertEqual(selection.enabledKinds, [.heartRate, .steps])
        XCTAssertFalse(selection.includes(.readiness))
    }

    func testNoneStoredValueStaysEmpty() {
        let selection = BodyMetricDayViewSelection.storedValue(from: "none")

        XCTAssertTrue(selection.enabledKinds.isEmpty)
        XCTAssertFalse(selection.includes(.readiness))
    }

    func testDeselectingOnlyReadinessSticksAfterRoundTrip() {
        // "All kinds except readiness" matches the legacy default's kind set, but
        // a value written by the current build carries the format marker, so the
        // deselection is authoritative and must NOT be upgraded back to all-on.
        let deselected = BodyMetricDayViewSelection.defaultValue.setting(.readiness, isEnabled: false)
        let decoded = BodyMetricDayViewSelection.storedValue(from: deselected.rawValue)

        XCTAssertEqual(decoded.enabledKinds, deselected.enabledKinds)
        XCTAssertFalse(decoded.includes(.readiness))
    }

    func testEverySelectionRoundTripsThroughRawValue() {
        let selections: [BodyMetricDayViewSelection] = [
            .defaultValue,
            .defaultValue.setting(.readiness, isEnabled: false),
            .defaultValue.setting(.steps, isEnabled: false),
            BodyMetricDayViewSelection(enabledKinds: [.readiness]),
            BodyMetricDayViewSelection(enabledKinds: [])
        ]

        for selection in selections {
            XCTAssertEqual(
                BodyMetricDayViewSelection.storedValue(from: selection.rawValue).enabledKinds,
                selection.enabledKinds
            )
        }
    }
}
