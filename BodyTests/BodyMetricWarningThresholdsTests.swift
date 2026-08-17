//
//  BodyMetricWarningThresholdsTests.swift
//  BodyTests
//
//  Covers the stored custom limits for the metric threshold warnings: the
//  raw-value round trip, the defaults an untouched kind falls back to (zone 3's
//  lower bound for high heart rate) and the clamping into each picker range.
//

import XCTest
@testable import Body

final class BodyMetricWarningThresholdsTests: XCTestCase {
    // MARK: - Storage

    func testEmptyRawValueHasNoOverrides() {
        let thresholds = BodyMetricWarningThresholds.storedValue(from: "")

        XCTAssertTrue(thresholds.overrides.isEmpty)
        XCTAssertEqual(thresholds, .defaultValue)
        XCTAssertEqual(thresholds.rawValue, "")
        XCTAssertEqual(BodyMetricWarningThresholds.defaultRawValue, "")
    }

    func testOverridesRoundTripThroughTheRawValue() {
        let thresholds = BodyMetricWarningThresholds.defaultValue
            .setting(.highHeartRate, to: 130)
            .setting(.lowBloodOxygen, to: 88)

        XCTAssertEqual(thresholds.rawValue, #"{"highHeartRate":130,"lowBloodOxygen":88}"#)
        XCTAssertEqual(BodyMetricWarningThresholds.storedValue(from: thresholds.rawValue), thresholds)
    }

    func testUnknownKindsAndMalformedValuesFallBackToDefaults() {
        XCTAssertEqual(
            BodyMetricWarningThresholds.storedValue(from: #"{"lowBloodPressure":80}"#).overrides,
            [:]
        )
        XCTAssertEqual(BodyMetricWarningThresholds.storedValue(from: "not json"), .defaultValue)
    }

    func testClearingAnOverrideRestoresTheDefault() {
        let thresholds = BodyMetricWarningThresholds.defaultValue.setting(.lowHeartRate, to: 45)
        XCTAssertEqual(thresholds.override(for: .lowHeartRate), 45)
        XCTAssertEqual(thresholds.threshold(for: .lowHeartRate), 45)

        let cleared = thresholds.setting(.lowHeartRate, to: nil)
        XCTAssertNil(cleared.override(for: .lowHeartRate))
        XCTAssertEqual(cleared.threshold(for: .lowHeartRate), MetricWarningKind.lowHeartRate.defaultThreshold)
        XCTAssertEqual(cleared.rawValue, "")
    }

    // MARK: - Clamping

    func testOverridesAreClampedIntoTheKindRange() {
        let low = BodyMetricWarningThresholds.defaultValue.setting(.lowHeartRate, to: 5)
        XCTAssertEqual(low.override(for: .lowHeartRate), 30)

        let high = BodyMetricWarningThresholds.defaultValue.setting(.highHeartRate, to: 400)
        XCTAssertEqual(high.override(for: .highHeartRate), 200)

        let oxygen = BodyMetricWarningThresholds.defaultValue.setting(.lowBloodOxygen, to: 99)
        XCTAssertEqual(oxygen.override(for: .lowBloodOxygen), 95)
    }

    func testStoredOutOfRangeValuesAreClamped() {
        let thresholds = BodyMetricWarningThresholds.storedValue(from: #"{"highHeartRate":20}"#)
        XCTAssertEqual(thresholds.override(for: .highHeartRate), 100)
    }

    // MARK: - Zone 3 default

    func testZoneThreeLowerBoundIsSeventyPercentOfMaxHeartRate() {
        XCTAssertEqual(BodyMetricWarningThresholds.zoneThreeLowerBound(maxHeartRate: 190), 133)
        // 220 − 35 = 185 → 129.5, rounded up to a whole beat.
        XCTAssertEqual(BodyMetricWarningThresholds.zoneThreeLowerBound(maxHeartRate: 185), 130)
        XCTAssertEqual(WorkoutHeartRateZones.lowerBoundFractions[2], 0.70)
    }

    func testZoneThreeLowerBoundNeedsAUsableMaxHeartRate() {
        XCTAssertNil(BodyMetricWarningThresholds.zoneThreeLowerBound(maxHeartRate: nil))
        XCTAssertNil(BodyMetricWarningThresholds.zoneThreeLowerBound(maxHeartRate: 0))
        XCTAssertNil(BodyMetricWarningThresholds.zoneThreeLowerBound(maxHeartRate: .nan))
    }

    func testZoneThreeLowerBoundIsClampedIntoTheHighHeartRateRange() {
        // A very old athlete's 70 % lands under the picker's floor.
        XCTAssertEqual(BodyMetricWarningThresholds.zoneThreeLowerBound(maxHeartRate: 130), 100)
    }

    func testHighHeartRateDefaultsToZoneThreeAndFallsBackWithoutABirthDate() {
        let thresholds = BodyMetricWarningThresholds.defaultValue

        XCTAssertEqual(thresholds.threshold(for: .highHeartRate, maxHeartRate: 190), 133)
        XCTAssertEqual(thresholds.threshold(for: .highHeartRate, maxHeartRate: nil), 120)
        XCTAssertEqual(thresholds.threshold(for: .highHeartRate), 120)
    }

    func testOtherKindsIgnoreMaxHeartRate() {
        let thresholds = BodyMetricWarningThresholds.defaultValue

        XCTAssertEqual(thresholds.threshold(for: .lowHeartRate, maxHeartRate: 190), 40)
        XCTAssertEqual(thresholds.threshold(for: .lowBloodOxygen, maxHeartRate: 190), 90)
    }

    func testAnOverrideBeatsTheZoneThreeDefault() {
        let thresholds = BodyMetricWarningThresholds.defaultValue.setting(.highHeartRate, to: 145)

        XCTAssertEqual(thresholds.threshold(for: .highHeartRate, maxHeartRate: 190), 145)
    }
}
