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

    func testV2MarkedStoredValueUpgradesToIncludeStress() {
        // A selection persisted after Readiness shipped but before Stress did:
        // carries the v2 marker and enables every kind that existed then. Stress
        // could not have been deselected (the case didn't exist yet), so it is
        // added once — the same one-time upgrade the unmarked-legacy case above
        // makes for Readiness, one format version later.
        let legacyV2 = "v2,heartRate,heartRateVariability,respiratoryRate,oxygenSaturation,activeEnergy,steps,readiness"
        let selection = BodyMetricDayViewSelection.storedValue(from: legacyV2)

        XCTAssertTrue(selection.includes(.stress))
        XCTAssertTrue(selection.includes(.readiness))
    }

    func testV2MarkedStoredValueWithCustomSubsetGainsStressWithoutTouchingTheRest() {
        // A deliberately customized v2 subset (readiness and most other kinds
        // off) — distinct from `preReadinessDefaultKinds`, so this exercises the
        // v2 marker path rather than the unmarked-legacy upgrade path above.
        let legacyV2 = "v2,heartRate,steps"
        let selection = BodyMetricDayViewSelection.storedValue(from: legacyV2)

        XCTAssertEqual(selection.enabledKinds, [.heartRate, .steps, .stress])
        XCTAssertFalse(selection.includes(.readiness))
    }

    func testV3MarkedStoredValueWithoutStressStaysAuthoritative() {
        // Once re-saved by the current build (v3), an explicit deselection of
        // Stress must stick — no further one-time upgrade applies.
        let deselected = BodyMetricDayViewSelection.defaultValue.setting(.stress, isEnabled: false)
        let decoded = BodyMetricDayViewSelection.storedValue(from: deselected.rawValue)

        XCTAssertEqual(decoded.enabledKinds, deselected.enabledKinds)
        XCTAssertFalse(decoded.includes(.stress))
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
