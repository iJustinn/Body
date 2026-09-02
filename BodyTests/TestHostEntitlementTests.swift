//
//  TestHostEntitlementTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Pins the test host's own capabilities. Several suites read and write the App Group
/// container; when the host loses that entitlement they would silently degrade into skips
/// and stop covering anything. This test turns that environment loss into one loud failure
/// instead.
final class TestHostEntitlementTests: XCTestCase {
    /// An unsigned host (built with `CODE_SIGNING_ALLOWED=NO`) has no
    /// `_CodeSignature` directory in its bundle; a signed simulator build
    /// always does. There is no public iOS API to read the host's own
    /// entitlements directly, so this on-disk check stands in for that.
    private var hostIsUnsigned: Bool {
        let codeSignatureURL = Bundle.main.bundleURL.appendingPathComponent("_CodeSignature")
        return !FileManager.default.fileExists(atPath: codeSignatureURL.path)
    }

    func testHostHasAppGroupEntitlement() throws {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WorkoutSnapshotStore.appGroupIdentifier
        )

        if container == nil && hostIsUnsigned {
            throw XCTSkip("Unsigned test host (CODE_SIGNING_ALLOWED=NO); App Group entitlement is stripped by design")
        }

        XCTAssertNotNil(
            container,
            """
            The test host has no App Group container for \(WorkoutSnapshotStore.appGroupIdentifier), \
            and the host bundle is signed, so this is not the expected unsigned \
            CODE_SIGNING_ALLOWED=NO run. The App Group suites would silently degrade into skips \
            and stop covering anything, so fix the entitlement instead of ignoring this failure.
            """
        )
    }
}
