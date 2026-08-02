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
            // Vitals breakdown row titles: SleepVitalDisplayRow.title is built from
            // VitalKind.displayName (already resolved against BodyMetricsKit) and
            // re-localized at runtime in BodyHealthMetricDetailView, so the resolved
            // English text must also exist as a key here.
            "Respiratory Rate",
            "Skin Temperature",
            "Blood Oxygen",
            "Sleep Duration",
            "Splits",
            // Vitals home-card title and detail navigation title: both built via
            // String(localized: String.LocalizationValue(...)) from a plain "Vitals"
            // literal (BodyHealthMetricCard, BodyHealthMetricDetailView).
            "Vitals",
            // Vitals empty-state copy (BodyHealthMetricDetailView): distinct literals for "no data
            // for last night" vs. "no data for the selected day", each resolved at
            // runtime, so both need their own catalog entry.
            "No vitals for last night",
            "No vitals for this day"
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

    func testAboutVitalsBodyResolvesInBodyMetricsKitCatalog() throws {
        let catalog = try loadCatalog(at: "BodyMetricsKit/BodyMetricsKit.xcstrings")

        // HealthSummarySnapshot's "About Vitals" explainer is a long literal resolved
        // against the BodyMetricsKit catalog at runtime; a one-character drift between
        // the Swift literal and this key would silently ship English to zh-Hans users.
        try assertKeysTranslated(
            ["Vitals reviews overnight measurements of sleeping heart rate, respiratory rate, skin temperature, blood oxygen, and sleep duration. Each one is compared against your personal typical range, learned from about eight weeks of your own sleep data. Outliers can follow illness, alcohol, travel, or hard training, and they are not a diagnosis. It takes about two weeks of sleep data to calibrate.\nVitals follows the data sources you select for Sleep and for each individual vital, so choosing a single source may limit how many nights have data and how far back the charts reach."],
            in: catalog
        )
    }

    func testWorkoutShareKeysResolveInLocalizableCatalog() throws {
        let catalog = try loadCatalog(at: "Body/Localizable.xcstrings")

        let keys = [
            "Share",
            "Share Workout",
            "Beta v2",
            "Background",
            "Your Photo",
            "Close",
            "Midnight",
            "Workout Color",
            "Map",
            "Save",
            "Save to Photos",
            // Centered preset-card metric titles: built via String(localized:) in
            // WorkoutShareMetricsBuilder.centeredMetrics, so they resolve at runtime.
            "Distance",
            "Pace",
            "Speed",
            "Time",
            "Couldn't Load Photo",
            "Couldn't Load Map",
            "Couldn't Create Image",
            "Couldn't Save Image",
            "Body needs permission to add photos. Allow it in Settings › Body › Photos, then try again."
        ]

        try assertKeysTranslated(keys, in: catalog)
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
