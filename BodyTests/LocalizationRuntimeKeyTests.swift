//
//  LocalizationRuntimeKeyTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class LocalizationRuntimeKeyTests: XCTestCase {
    func testSleepVitalTitlesResolveInLocalizableCatalog() throws {
        let catalog = try loadCatalog(at: "Body/Localizable.xcstrings")

        let keys = [
            "Heart Rate",
            "Pressure",
            "Respiratory",
            "Skin Temperature",
            "Blood Oxygen",
            "Sleep Duration",
            "Splits"
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testSplitKeysResolveInBodyMetricsKitCatalog() throws {
        let catalog = try loadCatalog(at: "BodyMetricsKit/BodyMetricsKit.xcstrings")

        let keys = [
            "KM",
            "MI",
            "Kilometer %@, %@",
            "Mile %@, %@",
            "Fastest split",
            "Slowest split",
            "Average heart rate %@ BPM",
            "Pace",
            "Speed",
            "Avg HR"
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testReadinessAwaitingSleepHeroResolvesInBodyMetricsKitCatalog() throws {
        let catalog = try loadCatalog(at: "BodyMetricsKit/BodyMetricsKit.xcstrings")

        try assertKeysTranslated(
            ["Today's sleep data isn't in yet. Get some rest and check back later for a more accurate result."],
            in: catalog
        )
    }

    private func assertKeysTranslated(_ keys: [String], in catalog: [String: Any]) throws {
        for key in keys {
            let entry = try XCTUnwrap(catalog[key] as? [String: Any], "missing catalog entry for \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "\(key) missing localizations")
            let zhHans = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any], "\(key) missing zh-Hans")
            let unit = try XCTUnwrap(zhHans["stringUnit"] as? [String: Any], "\(key) missing zh-Hans stringUnit")
            XCTAssertEqual(unit["state"] as? String, "translated", "\(key) zh-Hans not translated")
            let value = try XCTUnwrap(unit["value"] as? String, "\(key) zh-Hans missing value")
            XCTAssertFalse(value.isEmpty, "\(key) zh-Hans value is empty")
        }
    }

    private func loadCatalog(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent(relativePath))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], relativePath)
        return try XCTUnwrap(root["strings"] as? [String: Any], relativePath)
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
