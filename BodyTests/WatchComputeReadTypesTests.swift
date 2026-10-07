//
//  WatchComputeReadTypesTests.swift
//  BodyTests
//
//  The watch's compute read set (`BodyHealthReadTypes.watchComputeReadObjectTypes`)
//  carries Stress's own inputs and the Steps, Active Energy and Resting Energy
//  cards' reads, each only under the permission the phone gates it with, and
//  stays inside the phone's request.
//

import XCTest
import HealthKit
@testable import Body

final class WatchComputeReadTypesTests: XCTestCase {
    func testHeartPermissionAddsTheRMSSDSources() throws {
        let heartOnly = BodyHealthReadTypes.watchComputeReadObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.heart])
        )
        XCTAssertTrue(heartOnly.contains(HKSeriesType.heartbeat()))
        if #available(iOS 27, *) {
            let rmssd = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateVariabilityRMSSD))
            XCTAssertTrue(heartOnly.contains(rmssd))
        }
        XCTAssertFalse(heartOnly.contains(try quantity(.stepCount)))
        XCTAssertFalse(heartOnly.contains(try quantity(.activeEnergyBurned)))

        var withoutHeart = BodyHealthPermissionSelection.defaultValue
        withoutHeart.enabledPermissions.remove(.heart)
        let hidden = BodyHealthReadTypes.watchComputeReadObjectTypes(for: withoutHeart)
        XCTAssertFalse(hidden.contains(HKSeriesType.heartbeat()))
        if #available(iOS 27, *) {
            let rmssd = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateVariabilityRMSSD))
            XCTAssertFalse(hidden.contains(rmssd))
        }
    }

    func testStepsAndEnergyPermissionsAddTheMovementMask() throws {
        let steps = BodyHealthReadTypes.watchComputeReadObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.steps])
        )
        XCTAssertEqual(steps, [try quantity(.stepCount)])

        let energy = BodyHealthReadTypes.watchComputeReadObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.energy])
        )
        XCTAssertEqual(
            energy,
            Set([try quantity(.activeEnergyBurned), try quantity(.basalEnergyBurned)]),
            "the watch reads active energy for the movement mask and its card, and resting energy for its card"
        )
    }

    func testComputeSetStaysInsideThePhoneRequest() {
        for selection in [
            BodyHealthPermissionSelection.defaultValue,
            BodyHealthPermissionSelection(enabledPermissions: [.heart, .steps, .energy])
        ] {
            let watch = BodyHealthReadTypes.watchComputeReadObjectTypes(for: selection)
            let phone = BodyHealthReadTypes.readObjectTypes(for: selection)
            XCTAssertTrue(watch.isSubset(of: phone), "\(watch.subtracting(phone))")
        }
    }

    private func quantity(_ identifier: HKQuantityTypeIdentifier) throws -> HKObjectType {
        try XCTUnwrap(HKObjectType.quantityType(forIdentifier: identifier))
    }
}
