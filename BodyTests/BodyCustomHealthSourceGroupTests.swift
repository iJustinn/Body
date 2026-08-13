//
//  BodyCustomHealthSourceGroupTests.swift
//  BodyTests
//
//  Pins the persistence + signing contract of user-created custom sources.
//  Both halves are load-bearing beyond this one screen: the raw value is what
//  the compute seed ships to the watch (so the watch has to rebuild the exact
//  same buckets from it), and the canonical signature is what every cache
//  signature and the seed's `settingsSignature` fold in — a signature that
//  moves for a cosmetic reason drops the Day View sidecar and re-seeds the
//  watch for nothing, and one that DOESN'T move on a membership edit serves
//  data merged from the old member set.
//

import XCTest
@testable import Body

final class BodyCustomHealthSourceGroupTests: XCTestCase {
    private let watchKey = "bundle=com.example.watch|name=watch"
    private let phoneKey = "bundle=com.example.phone|name=phone"
    private let strapKey = "bundle=com.example.strap|name=strap"

    private func group(
        id: String,
        name: String = "Wrist",
        members: [String],
        iconSystemName: String? = nil
    ) -> BodyCustomHealthSourceGroup {
        BodyCustomHealthSourceGroup(id: id, name: name, memberIdentityKeys: members, iconSystemName: iconSystemName)
    }

    // MARK: - Init normalization

    func testInitTrimsTheNameAndSortsAndDedupesMembers() {
        let merged = group(id: "custom:A", name: "  Wrist  ", members: [watchKey, phoneKey, watchKey])

        XCTAssertEqual(merged.name, "Wrist")
        XCTAssertEqual(merged.memberIdentityKeys, [phoneKey, watchKey])
        // The option the pickers show carries the CURRENT name and the group id.
        XCTAssertEqual(merged.option.id, "custom:A")
        XCTAssertEqual(merged.option.name, "Wrist")
        XCTAssertTrue(merged.option.isCustomSource)
        // A custom id must never be mistaken for a bundle identifier by the icon
        // lookup (an unknown prefix used to leak the raw id as a bundle hint).
        XCTAssertNil(merged.option.iconBundleIdentifierHint)
    }

    // MARK: - Icon

    func testInitTrimsIconSystemNameAndBlankBecomesNil() {
        XCTAssertEqual(
            group(id: "custom:A", members: [watchKey, phoneKey], iconSystemName: "  applewatch  ").iconSystemName,
            "applewatch"
        )
        XCTAssertNil(group(id: "custom:A", members: [watchKey, phoneKey], iconSystemName: "").iconSystemName)
        XCTAssertNil(group(id: "custom:A", members: [watchKey, phoneKey], iconSystemName: "   ").iconSystemName)
    }

    // MARK: - Round trip

    func testRawValueRoundTripsThroughTheStore() {
        let groups = [
            group(id: "custom:A", name: "Wrist", members: [watchKey, phoneKey]),
            group(id: "custom:B", name: "Straps", members: [strapKey, phoneKey])
        ]

        let decoded = BodyCustomHealthSourceGroupStore.groups(
            from: BodyCustomHealthSourceGroupStore.rawValue(from: groups)
        )

        XCTAssertEqual(decoded, groups)
    }

    func testRawValueRoundTripsIconSystemName() {
        let groups = [
            group(id: "custom:A", name: "Wrist", members: [watchKey, phoneKey], iconSystemName: "applewatch"),
            group(id: "custom:B", name: "Straps", members: [strapKey, phoneKey])
        ]

        let decoded = BodyCustomHealthSourceGroupStore.groups(
            from: BodyCustomHealthSourceGroupStore.rawValue(from: groups)
        )

        XCTAssertEqual(decoded, groups)
        XCTAssertEqual(decoded.first?.iconSystemName, "applewatch")
        XCTAssertNil(decoded.last?.iconSystemName)
    }

    func testNilIconEncodesByteIdenticallyToThePreFeatureFormat() {
        // No `iconSystemName` key at all — the exact bytes the compute seed and
        // any persisted defaults entry shipped before this feature existed, so
        // a user who never sets an icon signs nothing new.
        let groups = [group(id: "custom:A", name: "Wrist", members: [watchKey, phoneKey])]
        let rawValue = BodyCustomHealthSourceGroupStore.rawValue(from: groups)
        let expected = #"[{"id":"custom:A","memberIdentityKeys":["\#(phoneKey)","\#(watchKey)"],"name":"Wrist"}]"#

        XCTAssertEqual(rawValue, expected)
        XCTAssertFalse(rawValue.contains("iconSystemName"))
    }

    func testDecodingPreFeatureJSONYieldsANilIcon() throws {
        // A raw value written by a build that predates the icon field.
        let raw = #"[{"id":"custom:A","memberIdentityKeys":["\#(watchKey)","\#(phoneKey)"],"name":"Wrist"}]"#
        let decoded = try XCTUnwrap(BodyCustomHealthSourceGroupStore.groups(from: raw).first)

        XCTAssertNil(decoded.iconSystemName)
    }

    func testDecodeNormalizesNamesAndMembersTheSameWayInitDoes() throws {
        // Hand-written raw (an older build, or a hand-edited defaults entry):
        // untrimmed name, unsorted + duplicated members.
        let raw = #"[{"id":"custom:A","memberIdentityKeys":["\#(watchKey)","\#(phoneKey)","\#(watchKey)"],"name":"  Wrist  "}]"#
        let decoded = try XCTUnwrap(BodyCustomHealthSourceGroupStore.groups(from: raw).first)

        XCTAssertEqual(decoded.name, "Wrist")
        XCTAssertEqual(decoded.memberIdentityKeys, [phoneKey, watchKey])
    }

    func testDecodeDropsNonCustomIDsAndSurvivesGarbage() {
        // Only `custom:` ids may become selectable options — a stray individual
        // or combined-name id would register a bucket that shadows the real one.
        let raw = #"[{"id":"source:\#(watchKey)","memberIdentityKeys":[],"name":"Watch"},{"id":"custom:A","memberIdentityKeys":["\#(watchKey)","\#(phoneKey)"],"name":"Wrist"}]"#
        let decoded = BodyCustomHealthSourceGroupStore.groups(from: raw)

        XCTAssertEqual(decoded.map(\.id), ["custom:A"])
        // Unreadable storage degrades to "no groups", never to a decode failure
        // that would take the whole settings load down with it.
        XCTAssertTrue(BodyCustomHealthSourceGroupStore.groups(from: "not json").isEmpty)
        XCTAssertTrue(BodyCustomHealthSourceGroupStore.groups(from: "").isEmpty)
        XCTAssertTrue(BodyCustomHealthSourceGroupStore.groups(from: "[]").isEmpty)
    }

    func testBothEncodeAndDecodeCapTheGroupCount() {
        let cap = BodyCustomHealthSourceGroupStore.maximumGroupCount
        let groups = (0..<(cap + 2)).map { index in
            group(id: "custom:\(index)", name: "Group \(index)", members: [watchKey, phoneKey])
        }

        let rawValue = BodyCustomHealthSourceGroupStore.rawValue(from: groups)
        let decoded = BodyCustomHealthSourceGroupStore.groups(from: rawValue)

        // The cap is enforced on the way out AND on the way in, so an
        // over-long value written by any path can't come back over-long.
        XCTAssertEqual(decoded.count, cap)
        XCTAssertEqual(decoded, Array(groups.prefix(cap)))
    }

    // MARK: - Canonical signature

    func testCanonicalSignatureIsStableUnderGroupAndMemberReordering() {
        let a = group(id: "custom:A", members: [watchKey, phoneKey])
        let b = group(id: "custom:B", members: [strapKey])
        let reorderedA = group(id: "custom:A", members: [phoneKey, watchKey])

        XCTAssertEqual(
            BodyCustomHealthSourceGroupStore.canonicalSignature(for: [a, b]),
            BodyCustomHealthSourceGroupStore.canonicalSignature(for: [b, reorderedA])
        )
    }

    func testCanonicalSignatureIgnoresRenamesButTracksMembershipEdits() {
        let base = group(id: "custom:A", name: "Wrist", members: [watchKey, phoneKey])
        let renamed = group(id: "custom:A", name: "Everything", members: [watchKey, phoneKey])
        let edited = group(id: "custom:A", name: "Wrist", members: [watchKey, phoneKey, strapKey])

        let baseSignature = BodyCustomHealthSourceGroupStore.canonicalSignature(for: [base])

        // A rename changes no query and no math, so it must not invalidate a
        // single cache or re-seed the watch.
        XCTAssertEqual(baseSignature, BodyCustomHealthSourceGroupStore.canonicalSignature(for: [renamed]))
        // A membership edit changes what every affected chart READS, so it must.
        XCTAssertNotEqual(baseSignature, BodyCustomHealthSourceGroupStore.canonicalSignature(for: [edited]))
        XCTAssertFalse(baseSignature.contains("Wrist"))
    }

    func testCanonicalSignatureIsEmptyWithoutGroups() {
        // The empty string is what keeps a user who never made a group signing
        // exactly the bytes they signed before this feature existed.
        XCTAssertEqual(BodyCustomHealthSourceGroupStore.canonicalSignature(for: []), "")
    }

    func testCanonicalSignatureIgnoresTheIcon() {
        // Icon is exactly as cosmetic as name: picking one must not invalidate
        // a single cache or re-seed the watch.
        let withIcon = group(id: "custom:A", members: [watchKey, phoneKey], iconSystemName: "applewatch")
        let withoutIcon = group(id: "custom:A", members: [watchKey, phoneKey])

        XCTAssertEqual(
            BodyCustomHealthSourceGroupStore.canonicalSignature(for: [withIcon]),
            BodyCustomHealthSourceGroupStore.canonicalSignature(for: [withoutIcon])
        )
    }

    // MARK: - Membership-update icon preservation
    //
    // `HealthKitWorkoutStore.updateCustomHealthSourceGroupMembers` rebuilds the
    // edited group through this exact initializer, forwarding the existing
    // `iconSystemName`. There is no existing pattern in BodyTests for driving
    // that store method directly: it funnels into `applyCustomHealthSourceGroups`,
    // which runs a live HealthKit refetch/authorization pipeline (not just a
    // save) unsuited to a unit test, and no other BodyTests file constructs
    // `HealthKitWorkoutStore` to exercise it. This model-level test instead
    // pins the rebuild contract the store method depends on: forwarding
    // `iconSystemName` through the initializer when membership changes must be
    // lossless, so a membership-edit save can never silently drop the icon.

    func testRebuildingAGroupThroughTheInitializerForwardsTheIcon() {
        let original = group(id: "custom:A", name: "Wrist", members: [watchKey, phoneKey], iconSystemName: "applewatch")

        let rebuiltWithNewMembers = BodyCustomHealthSourceGroup(
            id: original.id,
            name: original.name,
            memberIdentityKeys: [strapKey, phoneKey],
            iconSystemName: original.iconSystemName
        )

        XCTAssertEqual(rebuiltWithNewMembers.iconSystemName, "applewatch")
        XCTAssertEqual(rebuiltWithNewMembers.memberIdentityKeys, [phoneKey, strapKey])
    }
}
