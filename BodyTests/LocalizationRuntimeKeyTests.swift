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
            "km",
            "mi",
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

    func testWorkoutDetailContextTileKeysResolveInBodyMetricsKitCatalog() throws {
        let catalog = try loadCatalog(at: "BodyMetricsKit/BodyMetricsKit.xcstrings")

        // Weather/METs/recovery tile titles. (Temperature is no longer a tile — it
        // moved to the hero line, where it renders as a bare number + unit.)
        let keys = [
            "Humidity",
            "Avg METs",
            "HR Recovery",
            // Comparison-badge stand-in shown on every comparable tile once the
            // 30-day window settles without a measured delta
            // (WorkoutMetricComparisonBuilder.placeholder). The badge itself is a
            // dotted key — "--%" has no Swift-identifier characters, so Xcode's
            // symbol generator rejects it as a key.
            "comparison.noDeltaBadge",
            "No 30-day comparison yet"
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testStrideLengthKeysResolveInBodyMetricsKitCatalog() throws {
        let catalog = try loadCatalog(at: "BodyMetricsKit/BodyMetricsKit.xcstrings")

        // Every user-visible string of the Stride Length card comes from
        // WorkoutMetricSeriesCharts.strideLength, resolved against this table.
        let keys = [
            "Stride Length",
            "Avg Stride Length",
            "Max Stride Length",
            "m/step",
            "ft/step",
            "Stride length, average %@ %@, maximum %@ %@"
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testBucketedSeriesKeysResolveInBodyMetricsKitCatalog() throws {
        let catalog = try loadCatalog(at: "BodyMetricsKit/BodyMetricsKit.xcstrings")

        // Titles, captions, units and accessibility sentences of every chart
        // WorkoutMetricSeriesCharts builds, resolved against this table.
        let keys = [
            "Pace",
            "Avg Pace",
            "Best Pace",
            "min/km",
            "min/mi",
            "Pace, average %@ %@, best %@ %@",
            "Speed",
            "Avg Speed",
            "Max Speed",
            "km/h",
            "mph",
            "Speed, average %@ %@, maximum %@ %@",
            "Step Cadence",
            "Avg Step Cadence",
            "Max Step Cadence",
            "spm",
            "Cadence, average %@ %@, maximum %@ %@",
            "Cycling Cadence",
            "Avg Cycling Cadence",
            "Max Cycling Cadence",
            "rpm",
            "Cycling cadence, average %@ %@, maximum %@ %@",
            "Ground Contact Time",
            "Avg Ground Contact",
            "Max Ground Contact",
            "ms",
            "Ground contact time, average %@ %@, maximum %@ %@",
            "Vertical Oscillation",
            "Avg Vertical Osc.",
            "Max Vertical Osc.",
            "cm",
            "in",
            "Vertical oscillation, average %@ %@, maximum %@ %@"
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testActivityRingLabelsResolveInLocalizableCatalog() throws {
        let catalog = try loadCatalog(at: "Body/Localizable.xcstrings")

        // The rings detail passes bare title/unit literals down to its rows and
        // hold-to-peek callout, which resolve them via
        // String(localized: String.LocalizationValue(...)) — so a rename on the
        // Swift side that misses the catalog ships English into zh-Hans.
        let keys = [
            "Move",
            "Exercise",
            "Stand",
            "kcal",
            "min",
            "hrs"
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

    func testRouteStyleKeysResolveInBodyMetricsKitCatalog() throws {
        let catalog = try loadCatalog(at: "BodyMetricsKit/BodyMetricsKit.xcstrings")

        // `BodyWorkoutRouteStyle`'s title/subtitle strings for the three Route Style
        // rows (Settings › Workouts), including the new 3D style.
        try assertKeysTranslated(
            ["Map", "Apple Maps", "Plain", "Route Only", "3D", "Elevation Ribbon"],
            in: catalog
        )

        // The Route Style row's value is composed at runtime as "Draw · <style>", so the
        // lead word is resolved out of the app catalog rather than this one.
        try assertKeysTranslated(
            ["routeStyle.drawSummary", "routeStyle.drawSubtitle", "routeStyle.drawUnavailable"],
            in: try loadCatalog(at: "Body/Localizable.xcstrings")
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
            "v3",
            "Background",
            "Your Photo",
            "Close",
            "Midnight",
            "Workout Color",
            "Daylight",
            "Map",
            "Save",
            "Save to Photos",
            // Centered/route-less preset-card metric titles: built via String(localized:)
            // in WorkoutShareMetricsBuilder.centeredMetrics/routelessMetrics, so they
            // resolve at runtime.
            "Distance",
            "Pace",
            "Speed",
            "Time",
            "Couldn't Load Photo",
            "Couldn't Load Map",
            "Couldn't Create Image",
            "Couldn't Save Image",
            "Body needs permission to add photos. Allow it in Settings › Body › Photos, then try again.",
            // Route Style rail icon, its Hide tile and Map-dimming hint, the dimension
            // tiles, and the explainer under a route that can't carry a ribbon.
            "Route Style",
            "Hide Route",
            "Hiding the route doesn't apply to the Map background.",
            "2D",
            "3D",
            "3D needs a route with elevation data.",
            // Icon visibility rail row (route-less workouts) and its tray tile names.
            "Icon",
            "Show Icon",
            "Hide Icon",
            // Photo adjust steps: the two chip-strip captions, the step chip labels, the
            // progression accessibility hint, and the VoiceOver reset actions.
            "Drag to move the photo. Pinch to zoom. Double-tap to reset.",
            "Drag to move. Pinch to resize. Double-tap to reset.",
            "Photo",
            "Layout",
            "Adjust the media, then choose Layout to move the workout info.",
            "Reset Photo",
            "Reset Layout",
            // Media import busy state, shown as a floating sync badge while a photo or
            // video import is in flight.
            "Importing media...",
            // Workout detail Share button's disabled-state VoiceOver hint while the
            // route fetch is in flight.
            "Loading workout data.",
            // Video background: tile, captions, adjust step, and error alerts.
            "Your Video",
            "Video",
            "Reset Video",
            "Couldn't Load Video",
            "Couldn't Create Video",
            "Couldn't Save Video",
            "Drag to move the video. Pinch to zoom. Double-tap to reset.",
            "Video Activity Share",
            "Use your own videos as the background of workout share cards.",
            // Font row label and the option names, built via String(localized:) in
            // WorkoutShareFontChoice.localizedName.
            "Font",
            "Rounded",
            "Standard",
            "Serif",
            "Monospaced",
            // Route colour row label, hint, and the option names from
            // WorkoutShareRouteColorChoice.localizedName.
            "Route",
            "Route Color",
            "Route color doesn't apply to the Map background.",
            "Body Blue",
            "White",
            "Black",
            "Orange",
            "Green",
            "Pink",
            // Aspect ratio rail icon, tray tile names, and the Pro feature entry
            // from WorkoutShareAspectRatio.localizedName / BodyProView.
            "Ratio",
            "Portrait 9:16",
            "Landscape 16:9",
            "Portrait 3:4",
            "Landscape 4:3",
            "Square",
            "Share Card Sizes",
            "Export workout share cards as 16:9, 3:4, 4:3, or square — or as a long image of the whole workout.",
            // Long Image tray tile, its metrics caption, and the disabled-background hint.
            "Long Image",
            "Pick the metrics for the long image.",
            "The long image uses a gradient background.",
            // Landscape arrangement rail icon, tray tile names, and the Map-dimming
            // hint from WorkoutShareLandscapeArrangement.localizedName.
            "Arrange",
            "Stacked",
            "Side by Side",
            "Layout doesn't apply to the Map background.",
            // Metrics rail icon, its Pro lock hint, the tray's caption and min-1 hint,
            // and the Pro feature entry from BodyProView.
            "Metrics",
            "Requires Body Pro",
            "Pick 1 to 5 metrics.",
            "At least one metric stays on the card.",
            "Share Card Metrics",
            "Choose which metrics your workout share card shows.",
            // Profile attribution rail icon, its tray tile names and disabled-tile
            // hint, and the missing-data caption shown while the tray is open.
            "Profile",
            "Show Avatar",
            "Show Nickname",
            "Add it in Settings › Profile first.",
            "Add a photo and name in Settings › Profile to show them on the card."
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testReadinessAIKeysResolveInLocalizableCatalog() throws {
        let catalog = try loadCatalog(at: "Body/Localizable.xcstrings")

        let keys = [
            // Hero accessibility label: folded into the parent label via
            // String(localized:) in BodyReadinessStarHero, so it resolves at runtime.
            "Apple Intelligence comment: %@",
            // Hero placeholder while Apple Intelligence writes.
            "Generating comment…",
            // Settings > AI section title and sheet copy. The section title is a
            // dotted key so a bare "AI" can't collide with another feature's string;
            // the catalog test can't tell a wholly missing key from an absent one,
            // so every AI string is listed here explicitly.
            "settings.section.ai",
            "Apple Intelligence",
            "Readiness Comment",
            "AI comment on today's score",
            "When on, Apple Intelligence writes a short comment about what's shaping today's readiness score — your heart rate, HRV, sleep, and training signals. Everything runs on your device; your health data never leaves it. When off or unavailable, Body shows its built-in explanation instead.",
            "Apple Intelligence readiness comments need a supported device with Apple Intelligence turned on in Settings. Body's built-in explanation is shown instead."
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testChartScrubCalloutRowTitlesResolveInLocalizableCatalog() throws {
        let catalog = try loadCatalog(at: "Body/Localizable.xcstrings")

        // The workout detail charts' hold-to-scrub callout labels its two rows with
        // the same dotted keys the health charts already use, so a bucket's average
        // and range read as "Avg"/"Range" (平均/范围) rather than falling back to the key.
        let keys = [
            "detail.avgPrefix",
            "chart.legendRange"
        ]

        try assertKeysTranslated(keys, in: catalog)
        XCTAssertEqual(try value(of: "detail.avgPrefix", language: "zh-Hans", in: catalog), "平均")
        XCTAssertEqual(try value(of: "chart.legendRange", language: "zh-Hans", in: catalog), "范围")
    }

    func testBucketedSeriesElevationAndHeartRateKeysResolveInBodyMetricsKitCatalog() throws {
        let catalog = try loadCatalog(at: "BodyMetricsKit/BodyMetricsKit.xcstrings")

        // The Elevation profile card is built in BodyMetricsKit, so its strings
        // resolve against that table, as do the heart-rate captions the detail
        // metrics reuse. (The "m"/"ft" units stay unlocalized, matching
        // `BodyValueFormat.elevationText`.)
        let keys = [
            "Elevation",
            "Ascent",
            "Max Elevation",
            "Elevation, ascent %@ %@, maximum %@ %@",
            "Heart Rate",
            "Avg Heart Rate",
            "Max Heart Rate"
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testMetricWarningKeysResolveInLocalizableCatalog() throws {
        let catalog = try loadCatalog(at: "Body/Localizable.xcstrings")

        let keys = [
            // Home card warning badge accessibility label and detail-page warning card titles.
            "Low Heart Rate",
            "High Heart Rate",
            "Low Blood Oxygen",
            "Your heart rate fell below %lld BPM starting at %@.",
            "Your heart rate rose above %lld BPM starting at %@.",
            "Your blood oxygen fell below %lld%% starting at %@.",
            // Chart axis and mark labels. The threshold rule is drawn
            // unlabelled — the sentence above the chart names the value.
            "Threshold",
            "Time",
            "Heart Rate",
            "Blood Oxygen",
            // Settings → Metrics → Warnings row and sheet.
            "Warnings",
            "Any reading below %lld bpm today",
            "Any reading above %lld bpm today, outside workouts",
            "Any reading below %lld%% today",
            "Warnings appear on the Home card and the metric's detail page.",
            // Threshold picker popover.
            "Use Default",
            "If you were working out, this warning will disappear once the workout is logged.",
            "Default: %@",
            "%lld bpm"
        ]

        try assertKeysTranslated(keys, in: catalog)
    }

    func testWorkoutRenameKeysResolveInLocalizableCatalog() throws {
        let catalog = try loadCatalog(at: "Body/Localizable.xcstrings")

        // The workout detail hero's title button opens the rename alert; its
        // Save/Cancel buttons reuse keys the catalog already carries.
        let keys = [
            "Rename Workout",
            "Save",
            "Cancel"
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

    /// One language's resolved string for `key`, so a test can assert the translation
    /// itself and not merely that the entry exists.
    private func value(of key: String, language: String, in catalog: [String: Any]) throws -> String {
        let entry = try XCTUnwrap(catalog[key] as? [String: Any], "missing catalog entry for \(key)")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "\(key) missing localizations")
        let localization = try XCTUnwrap(localizations[language] as? [String: Any], "\(key) missing \(language)")
        let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any], "\(key) missing \(language) stringUnit")
        return try XCTUnwrap(unit["value"] as? String, "\(key) \(language) missing value")
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
