//
//  BodyHealthSourceResolverTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Pins the shared source-selection resolution both platforms compile:
/// iOS resolves with `strictWhenMissing: false` (a discovered-and-gone source
/// widens to all sources — the phone's long-standing behavior), the watch with
/// `true` (it keeps its seeded values instead of silently reading every source,
/// which is what made the first on-watch compute disagree with the phone).
///
/// Exercised through `resolutionDecision`, the generic decision half of
/// `resolution(option:discovered:strictWhenMissing:)`, with plain `String`
/// stand-ins for the sources: `HKSource` has no public initializer and
/// `HKSource.default()` raises an Objective-C exception in a test host without
/// a HealthKit bundle identity (e.g. an unsigned `CODE_SIGNING_ALLOWED=NO`
/// simulator run), which would abort the whole test process. The un-tested
/// remainder of `resolution` is only the mechanical `.sources` → predicate
/// mapping over Apple API.
final class BodyHealthSourceResolverTests: XCTestCase {
    private let selectedOption = BodyHealthDataSourceOption(id: "com.example.tracker", name: "Tracker")

    private func decision(
        option: BodyHealthDataSourceOption,
        discovered: [String: [String]]?,
        strict: Bool
    ) -> BodyHealthSourceResolver.SourceResolutionDecision<String> {
        BodyHealthSourceResolver.resolutionDecision(
            option: option,
            discovered: discovered,
            strictWhenMissing: strict
        )
    }

    // MARK: - Sentinel selections

    func testAllSourcesAndNoComparisonNeverFilterInEitherMode() {
        for strict in [false, true] {
            XCTAssertEqual(
                decision(option: .allSources, discovered: nil, strict: strict),
                .allSources,
                "strict: \(strict)"
            )
            XCTAssertEqual(
                decision(option: .noComparison, discovered: [:], strict: strict),
                .allSources,
                "strict: \(strict)"
            )
        }
    }

    // MARK: - Discovery never succeeded

    func testMissingDiscoveryIsUnresolvedInBothModes() {
        for strict in [false, true] {
            XCTAssertEqual(
                decision(option: selectedOption, discovered: nil, strict: strict),
                .unresolved,
                "strict: \(strict)"
            )
        }
    }

    // MARK: - Discovered, but the selected source isn't there

    func testMissingIDWidensOnlyWhenNotStrict() {
        let discovered = ["com.example.other": ["Phone"]]

        XCTAssertEqual(
            decision(option: selectedOption, discovered: discovered, strict: false),
            .allSources
        )
        XCTAssertEqual(
            decision(option: selectedOption, discovered: discovered, strict: true),
            .unresolved
        )
    }

    func testEmptySourceBucketBehavesLikeAMissingID() {
        let discovered = [selectedOption.id: [String]()]

        XCTAssertEqual(
            decision(option: selectedOption, discovered: discovered, strict: false),
            .allSources
        )
        XCTAssertEqual(
            decision(option: selectedOption, discovered: discovered, strict: true),
            .unresolved
        )
    }

    // MARK: - Discovered and resolvable

    func testResolvedSelectionYieldsItsSourcesIdenticallyInBothModes() {
        let discovered = [selectedOption.id: ["Watch"]]

        for strict in [false, true] {
            XCTAssertEqual(
                decision(option: selectedOption, discovered: discovered, strict: strict),
                .sources(["Watch"]),
                "strict: \(strict)"
            )
        }
    }

    func testCombinedSelectionCarriesEverySourceInTheBucket() {
        // `resolution` ORs a multi-source bucket into one compound predicate —
        // the decision must hand it every member, in bucket order.
        let discovered = [selectedOption.id: ["Phone", "Watch"]]

        XCTAssertEqual(
            decision(option: selectedOption, discovered: discovered, strict: true),
            .sources(["Phone", "Watch"])
        )
    }

    // MARK: - User-created group buckets

    private let watchKey = "bundle=com.example.watch|name=watch"
    private let phoneKey = "bundle=com.example.phone|name=phone"
    private let strapKey = "bundle=com.example.strap|name=strap"

    private func customGroup(members: [String]) -> BodyCustomHealthSourceGroup {
        BodyCustomHealthSourceGroup(
            id: "custom:11111111-2222-3333-4444-555555555555",
            name: "Wrist",
            memberIdentityKeys: members
        )
    }

    func testCustomGroupBucketUnionsItsMembersAndDedupesBySourceIdentity() {
        let group = customGroup(members: [watchKey, phoneKey])
        // The phone bucket deliberately also carries "Watch": a source can be
        // reachable through more than one registered key (every source registers
        // both its plain and its disambiguated ID), and the union must not list
        // it twice — a duplicated member would OR the same predicate twice.
        let discovered: [String: [String]] = [
            "source:" + watchKey: ["Watch"],
            "source:" + phoneKey: ["Phone", "Watch"],
            "source:" + strapKey: ["Strap"]
        ]

        let registered = BodyHealthSourceResolver.registeringCustomGroupBuckets(
            discovered,
            customGroups: [group],
            identityKey: { $0 }
        )

        // Members are walked in sorted key order (phone before watch), so the
        // bucket is deterministic regardless of how the membership UI ordered them.
        XCTAssertEqual(registered[group.id], ["Phone", "Watch"])
        // A non-member's bucket is untouched, and the member buckets survive.
        XCTAssertEqual(registered["source:" + strapKey], ["Strap"])
        XCTAssertEqual(registered["source:" + watchKey], ["Watch"])

        // Registered buckets resolve identically under both modes — a custom
        // selection is no different from a combined-name one once its bucket exists.
        for strict in [false, true] {
            XCTAssertEqual(
                decision(option: group.option, discovered: registered, strict: strict),
                .sources(["Phone", "Watch"]),
                "strict: \(strict)"
            )
        }
    }

    func testCustomGroupWithNoDiscoveredMembersRegistersNothing() {
        let group = customGroup(members: [watchKey, phoneKey])
        let discovered: [String: [String]] = ["source:" + strapKey: ["Strap"]]

        let registered = BodyHealthSourceResolver.registeringCustomGroupBuckets(
            discovered,
            customGroups: [group],
            identityKey: { $0 }
        )

        // Absent, NOT an empty bucket: absence is the case `resolutionDecision`
        // already defines, so the group inherits the platform contract instead of
        // needing one of its own.
        XCTAssertNil(registered[group.id])
        XCTAssertEqual(registered, discovered)
        XCTAssertEqual(decision(option: group.option, discovered: registered, strict: false), .allSources)
        XCTAssertEqual(decision(option: group.option, discovered: registered, strict: true), .unresolved)
    }

    func testPartiallyVisibleCustomGroupResolvesToTheVisibleSubset() {
        // The watch commonly sees only some of the phone's sources; a group
        // resolves to what's actually here (combined-name's precedent) rather
        // than failing outright.
        let group = customGroup(members: [watchKey, phoneKey])
        let discovered: [String: [String]] = ["source:" + phoneKey: ["Phone"]]

        let registered = BodyHealthSourceResolver.registeringCustomGroupBuckets(
            discovered,
            customGroups: [group],
            identityKey: { $0 }
        )

        XCTAssertEqual(registered[group.id], ["Phone"])
        XCTAssertEqual(decision(option: group.option, discovered: registered, strict: true), .sources(["Phone"]))
    }

    // MARK: - Predicate assembly

    func testCombinedPredicateOnlyCompoundsWhatItWasGiven() {
        let sourcePredicate = NSPredicate(value: true)

        XCTAssertNil(BodyHealthSourceResolver.combinedPredicate())
        XCTAssertTrue(
            BodyHealthSourceResolver.combinedPredicate(sourcePredicate: sourcePredicate) === sourcePredicate
        )
        XCTAssertNotNil(BodyHealthSourceResolver.combinedPredicate(startDate: Date()))

        let combined = BodyHealthSourceResolver.combinedPredicate(
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 86_400),
            sourcePredicate: sourcePredicate
        ) as? NSCompoundPredicate
        XCTAssertEqual(combined?.compoundPredicateType, .and)
        XCTAssertEqual(combined?.subpredicates.count, 2)
    }
}
