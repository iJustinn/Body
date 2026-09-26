//
//  RecoveryHRVTests.swift
//  BodyTests
//
//  Apple's Recovery HRV (`heartRateVariabilityRMSSD`, iOS 27) as the Stress
//  RMSSD input and the HRV page's Recovery view: the three trend fields it
//  adds, their scoping, and the wiring that feeds them.
//

import HealthKit
import XCTest
@testable import Body

final class RecoveryHRVTests: XCTestCase {
    private let day = Calendar.bodyGregorian.startOfDay(for: Date())

    override func setUpWithError() throws {
        try BodyTestSupport.requireProjectRoot()
    }

    private func series(_ value: Double) -> HealthTrendSeries {
        HealthTrendSeries(points: [.init(date: day, value: value)])
    }

    private func ranges(_ low: Double, _ high: Double) -> HealthTrendRangeSeries {
        HealthTrendRangeSeries(points: [.init(date: day, lowValue: low, highValue: high)])
    }

    private func trends() -> HealthTrendSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = series(50)
        trends.heartRateVariabilityDaySamples = series(51)
        trends.recoveryHRV = series(40)
        trends.recoveryHRVRanges = ranges(30, 50)
        trends.recoveryHRVRangesSecondary = ranges(31, 51)
        trends.heartbeatRMSSDDaySamples = series(38)
        trends.recoveryHRVDaySamplesSecondary = series(39)
        return trends
    }

    // MARK: - Snapshot fields

    func testTrendSnapshotRoundTripsRecoveryHRVAndDecodesLegacyPayloadEmpty() throws {
        let original = trends()
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(HealthTrendSnapshot.self, from: data), original)

        // A cache written before these fields existed decodes with them empty
        // and every other series intact.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["recoveryHRV", "recoveryHRVRanges", "recoveryHRVRangesSecondary", "recoveryHRVDaySamplesSecondary"] {
            XCTAssertNotNil(json.removeValue(forKey: key), key)
        }
        let legacy = try JSONDecoder().decode(HealthTrendSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.recoveryHRV.isEmpty)
        XCTAssertTrue(legacy.recoveryHRVRanges.isEmpty)
        XCTAssertTrue(legacy.recoveryHRVRangesSecondary.isEmpty)
        XCTAssertTrue(legacy.recoveryHRVDaySamplesSecondary.isEmpty)
        XCTAssertEqual(legacy.heartRateVariability, series(50))
        XCTAssertEqual(legacy.heartbeatRMSSDDaySamples, series(38))
    }

    func testDaySampleSidecarCarriesTheComparisonRecoverySamples() throws {
        let sidecar = HealthTrendDaySampleSnapshot(trends: trends())
        XCTAssertEqual(sidecar.recoveryHRVDaySamplesSecondary, series(39))
        let data = try JSONEncoder().encode(sidecar)
        XCTAssertEqual(try JSONDecoder().decode(HealthTrendDaySampleSnapshot.self, from: data), sidecar)

        var onlyRecovery = HealthTrendDaySampleSnapshot(trends: .empty)
        XCTAssertTrue(onlyRecovery.isEmpty)
        onlyRecovery.recoveryHRVDaySamplesSecondary = series(39)
        XCTAssertFalse(onlyRecovery.isEmpty)
        XCTAssertTrue(onlyRecovery.strippingSecondaryDaySamples().recoveryHRVDaySamplesSecondary.isEmpty)
    }

    func testDaySampleSeriesEnumRoutesTheComparisonRecoverySamplesToHRV() {
        let series = HealthDaySampleSeries.recoveryHRVDaySamplesSecondary
        XCTAssertEqual(series.kind, .heartRateVariability)
        XCTAssertTrue(series.isSecondary)
        XCTAssertEqual(series.trendKeyPath, \HealthTrendSnapshot.recoveryHRVDaySamplesSecondary)
        XCTAssertEqual(series.keyPath, \HealthTrendDaySampleSnapshot.recoveryHRVDaySamplesSecondary)
        // The primary Recovery samples stay the Stress input series.
        XCTAssertEqual(HealthDaySampleSeries.heartbeatRMSSDDaySamples.kind, .heartRateVariability)
        XCTAssertFalse(HealthDaySampleSeries.heartbeatRMSSDDaySamples.isSecondary)
    }

    // MARK: - Scoping

    func testHeartPermissionOffClearsEveryRecoveryHRVSeries() {
        var selection = BodyHealthPermissionSelection.defaultValue
        selection.enabledPermissions.remove(.heart)
        let filtered = trends().filtered(by: selection)
        XCTAssertTrue(filtered.recoveryHRV.isEmpty)
        XCTAssertTrue(filtered.recoveryHRVRanges.isEmpty)
        XCTAssertTrue(filtered.recoveryHRVRangesSecondary.isEmpty)
        XCTAssertTrue(filtered.heartbeatRMSSDDaySamples.isEmpty)
        XCTAssertTrue(filtered.recoveryHRVDaySamplesSecondary.isEmpty)

        // Heart on keeps them.
        let kept = trends().filtered(by: .defaultValue)
        XCTAssertEqual(kept.recoveryHRV, series(40))
        XCTAssertEqual(kept.recoveryHRVDaySamplesSecondary, series(39))
    }

    func testClearingSecondarySeriesDropsOnlyTheComparisonRecoverySeries() {
        let cleared = trends().clearingSecondarySeries()
        XCTAssertTrue(cleared.recoveryHRVRangesSecondary.isEmpty)
        XCTAssertTrue(cleared.recoveryHRVDaySamplesSecondary.isEmpty)
        XCTAssertEqual(cleared.recoveryHRV, series(40))
        XCTAssertEqual(cleared.recoveryHRVRanges, ranges(30, 50))
        XCTAssertEqual(cleared.heartbeatRMSSDDaySamples, series(38))
    }

    func testStrippingDaySamplesKeepsTheRecoveryTrends() {
        let stripped = trends().strippingDaySamples()
        XCTAssertTrue(stripped.heartbeatRMSSDDaySamples.isEmpty)
        XCTAssertTrue(stripped.recoveryHRVDaySamplesSecondary.isEmpty)
        XCTAssertEqual(stripped.recoveryHRV, series(40))
        XCTAssertEqual(stripped.recoveryHRVRangesSecondary, ranges(31, 51))

        // A primary source switch on HRV drops its own samples, not the comparison's.
        let primaryStripped = trends().strippingPrimaryDaySamples(for: .heartRateVariability)
        XCTAssertTrue(primaryStripped.heartbeatRMSSDDaySamples.isEmpty)
        XCTAssertEqual(primaryStripped.recoveryHRVDaySamplesSecondary, series(39))
    }

    func testComparisonSourceScopeMismatchClearsTheComparisonRecoverySamples() {
        let sidecar = HealthTrendDaySampleSnapshot(trends: trends())
        let hrv = HealthMetricKind.heartRateVariability.rawValue
        let scoped = sidecar.scopedByMetricSignatures(
            capturedPrimary: [hrv: "A"], capturedSecondary: [hrv: "B"],
            currentPrimary: [hrv: "A"], currentSecondary: [hrv: "C"]
        )
        XCTAssertTrue(scoped.recoveryHRVDaySamplesSecondary.isEmpty)
        XCTAssertTrue(scoped.heartRateVariabilityDaySamplesSecondary.isEmpty)
        XCTAssertEqual(scoped.heartbeatRMSSDDaySamples, series(38))

        let unchanged = sidecar.scopedByMetricSignatures(
            capturedPrimary: [hrv: "A"], capturedSecondary: [hrv: "B"],
            currentPrimary: [hrv: "A"], currentSecondary: [hrv: "B"]
        )
        XCTAssertEqual(unchanged.recoveryHRVDaySamplesSecondary, series(39))
    }

    func testPerMetricHRVRefreshPublishesEveryRecoverySeriesIncludingThePrimarySamples() {
        // `fetchHealthDashboardSnapshot(for:)` builds its trends from `.empty`
        // and, for HRV, merges the primary Recovery samples onto the cached
        // Stress input series, so the merge must publish all of them.
        var refreshed = HealthTrendSnapshot.empty
        refreshed.heartRateVariability = series(52)
        refreshed.recoveryHRV = series(42)
        refreshed.recoveryHRVRanges = ranges(32, 52)
        refreshed.recoveryHRVRangesSecondary = ranges(33, 53)
        refreshed.heartbeatRMSSDDaySamples = series(45)
        refreshed.recoveryHRVDaySamplesSecondary = series(44)
        let next = trends().replacingMetric(.heartRateVariability, with: refreshed)
        XCTAssertEqual(next.recoveryHRV, series(42))
        XCTAssertEqual(next.recoveryHRVRanges, ranges(32, 52))
        XCTAssertEqual(next.recoveryHRVRangesSecondary, ranges(33, 53))
        XCTAssertEqual(next.recoveryHRVDaySamplesSecondary, series(44))
        XCTAssertEqual(next.heartbeatRMSSDDaySamples, series(45), "new primary Recovery samples must survive the merge")
    }

    func testReconciliationLeavesCopyTheRecoveryTrends() {
        var live = HealthTrendSnapshot.empty
        let fetched = trends()
        HealthTrendReconciliationLeaf.recoveryHRV.copy(from: fetched, to: &live, retainingFrom: nil)
        HealthTrendReconciliationLeaf.recoveryHRVRangesSecondary.copy(from: fetched, to: &live, retainingFrom: nil)
        XCTAssertEqual(live.recoveryHRV, series(40))
        XCTAssertEqual(live.recoveryHRVRanges, ranges(30, 50))
        XCTAssertEqual(live.recoveryHRVRangesSecondary, ranges(31, 51))
        XCTAssertTrue(live.heartRateVariability.isEmpty)
        XCTAssertTrue(HealthTrendReconciliationLeaf.recoveryHRV.hasSameValue(in: live, and: fetched))
        XCTAssertFalse(HealthTrendReconciliationLeaf.heartRateVariability.hasSameValue(in: live, and: fetched))
    }

    // MARK: - Read set and wiring

    func testRecoveryHRVReadTypeRidesTheHeartPermission() throws {
        guard #available(iOS 27, *) else {
            throw XCTSkip("Recovery HRV exists from iOS 27")
        }
        let rmssd = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateVariabilityRMSSD))
        XCTAssertTrue(BodyHealthReadTypes.readObjectTypes(for: .defaultValue).contains(rmssd))
        var selection = BodyHealthPermissionSelection.defaultValue
        selection.enabledPermissions.remove(.heart)
        XCTAssertFalse(BodyHealthReadTypes.readObjectTypes(for: selection).contains(rmssd))
        XCTAssertEqual(HealthKitFetchEngine.recoveryHRVIdentifier, .heartRateVariabilityRMSSD)
    }

    func testStressPrefersAppleRecoveryHRVBeforeTheHeartbeatScan() throws {
        let heartbeat = try BodyTestSupport.sourceText(at: "Body/Services/HealthKitFetchEngine+HeartbeatSeries.swift")
        let fetch = try XCTUnwrap(heartbeat.range(of: "func fetchHeartbeatRMSSDSamples(startDate: Date, endDate: Date)"))
        let recovery = try XCTUnwrap(heartbeat.range(of: "fetchRecoveryHRVSamples(startDate: startDate, endDate: endDate)", range: fetch.upperBound..<heartbeat.endIndex))
        let scan = try XCTUnwrap(heartbeat.range(of: "fetchHeartbeatSeriesSamples(predicate: predicate)", range: fetch.upperBound..<heartbeat.endIndex))
        XCTAssertLessThan(recovery.lowerBound, scan.lowerBound)
        XCTAssertTrue(heartbeat.contains("!recovery.isEmpty {"), "an empty Apple series must fall through to the scan")

        let policy = try BodyTestSupport.sourceText(at: "Body/Services/BodyHealthObservationPolicy.swift")
        XCTAssertTrue(policy.contains("quantity(.heartRateVariabilityRMSSD, [.heartRateVariability, .stress])"))
    }

    func testFullRefreshCarriesForwardAndFetchesTheRecoverySeries() throws {
        let engine = try BodyTestSupport.sourceText(at: "Body/Services/HealthKitFetchEngine.swift")
        XCTAssertTrue(engine.contains("let cachedRecoveryHRVDaySamplesSecondary = cachedTrends.recoveryHRVDaySamplesSecondary"))
        XCTAssertTrue(engine.contains("recoveryHRVDaySamplesSecondary: cachedRecoveryHRVDaySamplesSecondary,"))
        XCTAssertTrue(engine.contains("recoveryHRV: merged(fetchedRecoveryHRVPair?.0, cached: cachedTrends.recoveryHRV, from: heartRateVariabilityMergeStart, leaf: .recoveryHRV),"))
        XCTAssertTrue(engine.contains("recoveryHRVRanges: mergedRange(fetchedRecoveryHRVPair?.1, cached: cachedTrends.recoveryHRVRanges, from: heartRateVariabilityMergeStart, leaf: .recoveryHRV),"))
        XCTAssertTrue(engine.contains("recoveryHRVRangesSecondary: resolved(await recoveryHRVRangesSecondary, cached: cachedTrends.recoveryHRVRangesSecondary, leaf: .recoveryHRVRangesSecondary),"))
        XCTAssertTrue(engine.contains("trends.recoveryHRVRanges = resolvedTrend(fetchedRecoveryHRVPair?.1, cached: existing.trends.recoveryHRVRanges)"))
        // A pull on the HRV page also brings in the primary Recovery samples
        // (the hero value and Day View), through the non-blanking merge.
        XCTAssertTrue(engine.contains("trends.heartbeatRMSSDDaySamples = resolvedDaySamples(await recoveryHRVDaySamples, cached: existing.trends.heartbeatRMSSDDaySamples, series: .heartbeatRMSSDDaySamples)"))
        let heartbeat = try BodyTestSupport.sourceText(at: "Body/Services/HealthKitFetchEngine+HeartbeatSeries.swift")
        // A failed read propagates as nil (the refresh reports it); a successful
        // empty read keeps the cache instead of publishing an authoritative empty.
        XCTAssertTrue(heartbeat.contains("    ) async -> HealthTrendSeries? {\n        let interval = intradayDaySampleInterval(calendar: calendar)"))
        XCTAssertTrue(heartbeat.contains("calendar: calendar) else {\n            return nil\n        }\n        guard !incoming.isEmpty else { return cached }"))
        // The Recovery view is the same bars-and-line chart as Overall, so the
        // home view hands it a range series and a range comparison, never a line.
        let home = try BodyTestSupport.sourceText(at: "Body/Views/BodyHomeView.swift")
        XCTAssertTrue(home.contains("rangeSeries: trends.recoveryHRVRanges,"))
        XCTAssertTrue(home.contains("sourceRangeComparisonTrend: comparison,"))
        XCTAssertFalse(home.contains("series: trends.recoveryHRVSecondary"))

        let store = try BodyTestSupport.sourceText(at: "Body/Services/HealthKitWorkoutStore.swift")
        XCTAssertTrue(store.contains("successfulSeries.insert(.recoveryHRVDaySamplesSecondary)"))
        XCTAssertTrue(store.contains("if let recoveryPrimarySamples, !recoveryPrimarySamples.isEmpty {"),
                      "the HRV page must not blank a beat-to-beat series with an empty Apple read")
    }

    func testHRVPageOffersTheRecoveryViewOnlyWithReadings() throws {
        let detail = try BodyTestSupport.sourceText(at: "Body/Views/Health/BodyHealthMetricDetailView.swift")
        XCTAssertTrue(detail.contains("model.kind == .heartRateVariability && !workoutStore.healthTrends.recoveryHRV.isEmpty"))
        // The live series and the morph key follow the model, not the stored pick.
        XCTAssertTrue(detail.contains("model.kind == .heartRateVariability && model.trendVariant == BodyHRVDisplayKind.recovery.rawValue"))
        XCTAssertTrue(detail.contains("if recoveryHRVAvailable {\n                ToolbarItem(placement: .topBarTrailing) {\n                    hrvDisplayKindMenu"))
        // The system popup menu with an inline picker, not a sheet or a segmented control.
        XCTAssertTrue(detail.contains("Picker(String(localized: \"HRV View\"), selection: $hrvDetailDisplayKindRawValue) {"))
        XCTAssertTrue(detail.contains(".pickerStyle(.inline)"))
        XCTAssertFalse(detail.contains("pickerStyle(.segmented)"))
        XCTAssertFalse(detail.contains("BodyHRVDisplayKindSheet"))
        // Both range chart call sites carry the variant, so the switch morphs.
        XCTAssertEqual(detail.occurrenceCount(of: "variant: rangeChartVariant,"), 2)
        let chart = try BodyTestSupport.sourceText(at: "Body/Views/Health/Charts/HeartRateRangeChart.swift")
        XCTAssertTrue(chart.contains(".animation(reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0), value: morphKey)"))
        XCTAssertTrue(chart.contains(".onChange(of: morphKey) {"))
        XCTAssertTrue(detail.contains("if recoveryHRVAvailable {\n                aboutRecoveryHRVCard"))
        XCTAssertTrue(detail.contains("? workoutStore.healthTrends.heartbeatRMSSDDaySamples"))
        XCTAssertTrue(detail.contains("? workoutStore.healthTrends.recoveryHRVDaySamplesSecondary"))
        XCTAssertTrue(detail.contains("fallbackValue: showsRecoveryHRV ? nil : sleepSummary?.vitals.heartRateVariability"))

        let home = try BodyTestSupport.sourceText(at: "Body/Views/BodyHomeView.swift")
        XCTAssertTrue(home.contains("if hrvDetailDisplayKindRawValue == BodyHRVDisplayKind.recovery.rawValue, !trends.recoveryHRV.isEmpty {"))
        XCTAssertTrue(home.contains("trendVariant: BodyHRVDisplayKind.recovery.rawValue"))
        XCTAssertEqual(BodyHRVDisplayKind.defaultValue, .overall)
        XCTAssertEqual(BodyAppearancePreference.hrvDetailDisplayKindKey, "hrvDetailDisplayKind")
    }

    func testForegroundRefreshMayPresentTheSheetForANeverRequestedType() throws {
        let store = try BodyTestSupport.sourceText(at: "Body/Services/HealthKitWorkoutStore.swift")
        XCTAssertTrue(store.contains("let allowPrompt = intent == .userInitiated || BodyAppRuntime.isForegroundActive"))
        XCTAssertTrue(store.contains("guard try await requestHealthKitAuthorization(allowPrompt: allowPrompt) else {"))
        // The passive entry points keep prompting off: they can run with no scene.
        XCTAssertEqual(store.occurrenceCount(of: "requestHealthKitAuthorization(allowPrompt: false)"), 4)
    }

    func testRecoveryHRVStringsResolveInBothLanguages() throws {
        let catalog = try JSONSerialization.jsonObject(
            with: Data(contentsOf: BodyTestSupport.projectRoot.appendingPathComponent("Body/Localizable.xcstrings"))
        ) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        for key in ["HRV View", "Overall HRV", "Recovery HRV", "About Recovery HRV"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            XCTAssertNotNil(localizations["en"], key)
            XCTAssertNotNil(localizations["zh-Hans"], key)
        }
        let about = strings.keys.first { $0.hasPrefix("Recovery HRV looks at the difference between each heartbeat and the next") }
        let aboutEntry = try XCTUnwrap(strings[try XCTUnwrap(about)] as? [String: Any])
        let localizations = try XCTUnwrap(aboutEntry["localizations"] as? [String: Any])
        XCTAssertNotNil(localizations["zh-Hans"])
        XCTAssertFalse(try XCTUnwrap(about).contains("Series 12"))
    }
}
