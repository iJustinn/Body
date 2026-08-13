//
//  BodyHealthSourceIconTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class BodyHealthSourceIconTests: XCTestCase {
    private let fallback = "heart.text.square"

    // MARK: - Positive matches

    func testOuraMatchesByNameAndBundle() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Oura", bundleIdentifier: "com.ouraring.oura", fallback: fallback),
            "circle"
        )
    }

    func testWhoopMatchesScreenlessBandIcon() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "WHOOP", bundleIdentifier: "com.whoop.iphone", fallback: fallback),
            "applewatch.side.right"
        )
    }

    func testGarminConnectMatchesByBundleAfterRebrand() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Connect", bundleIdentifier: "com.garmin.connect.mobile", fallback: fallback),
            "watch.analog"
        )
    }

    func testAppleWatchMatchesByName() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Justin's Apple Watch", bundleIdentifier: nil, fallback: fallback),
            "applewatch"
        )
    }

    func testIWatchMatchesAppleWatchByName() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Justin's iWatch", bundleIdentifier: nil, fallback: fallback),
            "applewatch"
        )
    }

    func testIPadMatchesIPadIconBeforeIPhoneBundleRule() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Justin's iPad", bundleIdentifier: "com.apple.health.XXX", fallback: fallback),
            "ipad"
        )
    }

    func testIPhoneMatchesByNameAndHealthBundle() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Justin's iPhone", bundleIdentifier: "com.apple.health.XXX", fallback: fallback),
            "iphone.gen3"
        )
    }

    func testWithingsMatchesScaleIcon() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Withings", bundleIdentifier: "com.withings.wiScaleNG", fallback: fallback),
            "scalemass"
        )
    }

    func testDexcomMatchesSensorIcon() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Dexcom G7", bundleIdentifier: "com.dexcom.g7", fallback: fallback),
            "sensor"
        )
    }

    // MARK: - Negative / edge cases

    func testConnectWithUnrelatedBundleFallsBack() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Connect", bundleIdentifier: "com.example.app", fallback: fallback),
            fallback
        )
    }

    func testPolarityDoesNotFalsePositiveOnPolar() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Polarity", bundleIdentifier: nil, fallback: fallback),
            fallback
        )
    }

    func testIWatchXAliasViaCombinedIdMatchesAppleWatch() {
        let combinedID = BodyHealthDataSourceOption.combinedSourceID(for: "iWatchX")
        let option = BodyHealthDataSourceOption(id: combinedID, name: "iWatchX")

        XCTAssertNil(option.iconBundleIdentifierHint)
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: option.name, bundleIdentifier: option.iconBundleIdentifierHint, fallback: fallback),
            "applewatch"
        )
    }

    func testDiacriticNameFoldsBeforeMatching() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Öura", bundleIdentifier: nil, fallback: fallback),
            "circle"
        )
    }

    func testCombinedSourceIDHasNoBundleHintButNameStillMatches() {
        let option = BodyHealthDataSourceOption(id: "combined-name:oura", name: "Oura")

        XCTAssertNil(option.iconBundleIdentifierHint)
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: option.name, bundleIdentifier: option.iconBundleIdentifierHint, fallback: fallback),
            "circle"
        )
    }

    func testDisambiguatedIDParsesBundleWithoutLeakingEncodedName() {
        let id = BodyHealthDataSourceOption.individualSourceID(
            bundleIdentifier: "com.garmin.connect.mobile",
            name: "Connect",
            disambiguatesBundleIdentifier: true
        )
        let option = BodyHealthDataSourceOption(id: id, name: "Connect")

        XCTAssertEqual(option.iconBundleIdentifierHint, "com.garmin.connect.mobile")
    }

    func testPlainIndividualIDIsUsedAsBundleIdentifierAsIs() {
        let id = BodyHealthDataSourceOption.individualSourceID(
            bundleIdentifier: "com.dexcom.g7",
            name: "Dexcom G7",
            disambiguatesBundleIdentifier: false
        )
        let option = BodyHealthDataSourceOption(id: id, name: "Dexcom G7")

        XCTAssertEqual(option.iconBundleIdentifierHint, "com.dexcom.g7")
    }

    func testAppleWatchRulePrecedesIPhoneRule() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Apple Watch", bundleIdentifier: "com.apple.health.XXX", fallback: fallback),
            "applewatch"
        )
    }

    func testAllSourcesSentinelHasNoBundleHint() {
        XCTAssertNil(BodyHealthDataSourceOption.allSources.iconBundleIdentifierHint)
        XCTAssertNil(BodyHealthDataSourceOption.noComparison.iconBundleIdentifierHint)
    }

    func testUnknownSourceFallsBack() {
        XCTAssertEqual(
            BodyHealthSourceIcon.systemImageName(name: "Random Health App", bundleIdentifier: "com.example.random", fallback: fallback),
            fallback
        )
    }

    // MARK: - Custom source icon picker vocabulary

    func testSelectableSymbolNamesHasNoDuplicates() {
        let names = BodyHealthSourceIcon.selectableSymbolNames

        XCTAssertEqual(names.count, Set(names).count)
    }

    func testSelectableSymbolNamesStartsWithTheDefault() {
        XCTAssertEqual(BodyHealthSourceIcon.selectableSymbolNames.first, BodyHealthSourceIcon.customSourceDefaultSymbolName)
    }
}
