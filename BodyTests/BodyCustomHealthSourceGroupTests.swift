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
        members: [String]
    ) -> BodyCustomHealthSourceGroup {
        BodyCustomHealthSourceGroup(id: id, name: name, memberIdentityKeys: members)
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
}
