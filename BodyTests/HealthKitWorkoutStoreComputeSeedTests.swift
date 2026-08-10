//
//  HealthKitWorkoutStoreComputeSeedTests.swift
//  BodyTests
//
//  Covers the phone→watch compute-seed assembly (Phase 3 of the on-watch
//  realtime compute plan): `HealthKitWorkoutStore.makeComputeSeed` and its
//  supporting pure statics (`computeSettingsSignature`,
//  `recentTimeZoneIdentifiersByDay`). These are pure/static specifically so
//  they're testable without a live store, engine, or HealthKit round trip —
//  `publishWatchSnapshot` itself just captures inputs and calls through to
//  them off-actor.
//

import XCTest
@testable import Body

final class HealthKitWorkoutStoreComputeSeedTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    // MARK: - Fixtures

    private func dailySeries(dayCount: Int, anchor: Date, baseline: Double) -> HealthTrendSeries {
        let anchorDay = calendar.startOfDay(for: anchor)
        var points: [HealthTrendDataPoint] = []
        for age in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { continue }
            points.append(HealthTrendDataPoint(date: day, value: baseline + Double(age % 5)))
        }
        return HealthTrendSeries(points: points)
    }

    /// `dayCount` days of trend history ending at `anchor` — deliberately more
    /// than `WatchComputeSeed.trendDayCount` (70) so trimming is exercised.
    private func trendsFixture(dayCount: Int, anchor: Date) -> HealthTrendSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.heartRate = dailySeries(dayCount: dayCount, anchor: anchor, baseline: 64)
        trends.heartRateVariability = dailySeries(dayCount: dayCount, anchor: anchor, baseline: 55)
        trends.restingHeartRate = dailySeries(dayCount: dayCount, anchor: anchor, baseline: 58)
        trends.wristTemperature = dailySeries(dayCount: dayCount, anchor: anchor, baseline: 36.3)
        // A series `watchComputeTrimmed` does NOT keep (Basics-style) — used to
        // assert the trim actually drops non-compute series, not just windows them.
        trends.steps = dailySeries(dayCount: dayCount, anchor: anchor, baseline: 8_000)
        return trends
    }

    private func settingsFixture(
        idealSleepDurationMinutes: Int = 480,
        showSleepScore: Bool = true,
        healthDataSourceSelectionRaw: String = "{}",
        customHealthSourceGroupsRaw: String? = nil
    ) -> WatchComputeSettings {
        WatchComputeSettings(
            idealSleepDurationMinutes: idealSleepDurationMinutes,
            followsSystemUnits: true,
            selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.celsius.rawValue,
            showSleepScore: showSleepScore,
            showsSubMinuteAwakeSleepStages: true,
            showsLeadingTrailingAwakeSleepStages: true,
            healthDataSourceSelectionRaw: healthDataSourceSelectionRaw,
            combinesHealthDataSourcesByName: false,
            customHealthSourceGroupsRaw: customHealthSourceGroupsRaw
        )
    }

    // MARK: - makeComputeSeed

    func testMakeComputeSeedTrimsTrendsToSeventyDaysEndingAtDataThrough() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8)))
        let trends = trendsFixture(dayCount: 100, anchor: anchor)

        let seed = HealthKitWorkoutStore.makeComputeSeed(
            summary: .placeholder,
            trends: trends,
            dataThrough: anchor,
            lastVitalsRefreshDate: anchor,
            trainingLoadStartDay: nil,
            trainingLoadDailyLoads: nil,
            trainingLoadDataThrough: nil,
            expectedSourceIDsByKind: nil,
            settings: settingsFixture(),
            publishedAt: anchor
        )

        XCTAssertEqual(seed.trends.heartRate.points.count, WatchComputeSeed.trendDayCount)
        // Non-compute series are dropped entirely, not merely windowed.
        XCTAssertTrue(seed.trends.steps.points.isEmpty)
        XCTAssertEqual(seed.dataThrough, anchor)
        XCTAssertEqual(seed.publishedAt, anchor)
        XCTAssertEqual(seed.lastVitalsRefreshDate, anchor)
    }

    func testMakeComputeSeedDerivesSeriesRangesFromTheUntrimmedTrends() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8)))
        var trends = trendsFixture(dayCount: 100, anchor: anchor)
        // A yearly extreme OLDER than the 70-day trim window — the case that
        // matters: the phone's own displayed range includes it, and the watch's
        // short delta can never rediscover it, so the seed has to carry it.
        let oldDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: anchor)))
        trends.heartRate = HealthTrendSeries(
            points: trends.heartRate.points.map { point in
                calendar.isDate(point.date, inSameDayAs: oldDay)
                    ? HealthTrendDataPoint(date: point.date, value: 191)
                    : point
            }
        )

        let seed = HealthKitWorkoutStore.makeComputeSeed(
            summary: .placeholder,
            trends: trends,
            dataThrough: anchor,
            lastVitalsRefreshDate: anchor,
            trainingLoadStartDay: nil,
            trainingLoadDailyLoads: nil,
            trainingLoadDataThrough: nil,
            expectedSourceIDsByKind: nil,
            settings: settingsFixture(),
            publishedAt: anchor
        )

        // Ranges come from the FULL trends — the same series the phone's own
        // snapshot draws its `rangeMin`/`rangeMax` from — not from the trimmed
        // slice the seed carries, which would silently drop the old extreme and
        // make the watch's ring fill and chart bounds diverge from the phone's.
        XCTAssertEqual(seed.seriesRanges, WatchMetricsSnapshotBuilder.seriesRanges(from: trends))
        XCTAssertEqual(seed.seriesRanges[WatchMetricKindKey.heartRate]?.max, 191)
        XCTAssertNotEqual(
            seed.seriesRanges,
            WatchMetricsSnapshotBuilder.seriesRanges(from: seed.trends)
        )
    }

    func testMakeComputeSeedCarriesTheTrainingLoadDailySeedUnchanged() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20)))
        let startDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -407, to: anchor))
        let loads = (0..<408).map { Double($0 % 7) }

        let seed = HealthKitWorkoutStore.makeComputeSeed(
            summary: .placeholder,
            trends: .empty,
            dataThrough: anchor,
            lastVitalsRefreshDate: anchor,
            trainingLoadStartDay: startDay,
            trainingLoadDailyLoads: loads,
            trainingLoadDataThrough: anchor,
            expectedSourceIDsByKind: nil,
            settings: settingsFixture(),
            publishedAt: anchor
        )

        XCTAssertEqual(seed.trainingLoadStartDay, startDay)
        XCTAssertEqual(seed.trainingLoadDailyLoads?.count, 408)
        XCTAssertEqual(seed.trainingLoadDailyLoads, loads)
    }

    // MARK: - dataThrough capture decision (C4)

    /// The REAL "settings-only republish carries `dataThrough` forward, a
    /// clean full refresh advances it" invariant lives in
    /// `HealthKitWorkoutStore.markRefreshSucceeded`'s capture, not in
    /// `makeComputeSeed` (a pure pass-through of whatever `dataThrough` it's
    /// given — asserting it round-trips a literal is a tautology). Pinning the
    /// extracted pure static directly: a settings-only republish's own
    /// `markRefreshSucceeded` call passes `refreshedVitals: false`, so the
    /// watermark must NOT advance; a clean full refresh
    /// (`refreshedVitals: true, hadQueryFailure: false`) must advance it; a
    /// refresh with a leaf query failure must also leave it unchanged even
    /// though vitals were nominally refreshed.
    func testNextLastVitalsRefreshDateCarriesForwardOnASettingsOnlyRepublishButAdvancesOnACleanFullRefresh() throws {
        let current = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8)))
        let later = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9)))

        // Settings-only republish: `refreshedVitals` is false, so the
        // watermark carries forward unchanged, no matter how much later `date` is.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextLastVitalsRefreshDate(
                current: current, date: later, refreshedVitals: false, hadQueryFailure: false
            ),
            current
        )

        // A clean full refresh advances it to the new date.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextLastVitalsRefreshDate(
                current: current, date: later, refreshedVitals: true, hadQueryFailure: false
            ),
            later
        )

        // A refresh that nominally refetched vitals but hit a leaf query
        // failure must NOT advance the watermark either — a partially-failed
        // refresh must never look like fresher data.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextLastVitalsRefreshDate(
                current: current, date: later, refreshedVitals: true, hadQueryFailure: true
            ),
            current
        )

        // Cold start (no prior watermark) + a settings-only call: still nil,
        // never fabricated from `date`.
        XCTAssertNil(
            HealthKitWorkoutStore.nextLastVitalsRefreshDate(
                current: nil, date: later, refreshedVitals: false, hadQueryFailure: false
            )
        )
    }

    // MARK: - Carried-data republish (settings-only)

    /// Mirrors what `publishWatchSnapshot` does for a settings-only republish:
    /// the SAME `dataThrough`/summary/trends/training-load inputs, but a fresh
    /// `settings` value and a later `publishedAt`. `makeComputeSeed` itself is a
    /// pure pass-through (asserting `dataThrough` round-trips the same literal
    /// passed to both calls below is NOT proof of the real invariant — that's
    /// `testNextLastVitalsRefreshDateCarriesForwardOnASettingsOnlyRepublishButAdvancesOnACleanFullRefresh`
    /// above); what THIS test actually pins is that changing `settings`/
    /// `publishedAt` alone never perturbs the data fields `makeComputeSeed`
    /// carries through unchanged.
    func testRebuildingForASettingsOnlyRepublishCarriesDataForwardButUpdatesSettings() throws {
        let fullRefreshAnchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8)))
        let republishTime = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9)))
        let trends = trendsFixture(dayCount: 80, anchor: fullRefreshAnchor)
        let startDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -407, to: fullRefreshAnchor))
        let loads = (0..<408).map { Double($0) }

        let fullRefreshSeed = HealthKitWorkoutStore.makeComputeSeed(
            summary: .placeholder,
            trends: trends,
            dataThrough: fullRefreshAnchor,
            lastVitalsRefreshDate: fullRefreshAnchor,
            trainingLoadStartDay: startDay,
            trainingLoadDailyLoads: loads,
            trainingLoadDataThrough: fullRefreshAnchor,
            expectedSourceIDsByKind: nil,
            settings: settingsFixture(idealSleepDurationMinutes: 480),
            publishedAt: fullRefreshAnchor
        )

        // A settings-only republish reuses the SAME summary/trends/dataThrough/
        // training-load inputs (the store's stored properties + cached seed
        // slot are untouched by a republish) but re-reads settings and stamps
        // a fresh `publishedAt`.
        let republishedSeed = HealthKitWorkoutStore.makeComputeSeed(
            summary: .placeholder,
            trends: trends,
            dataThrough: fullRefreshAnchor,
            lastVitalsRefreshDate: fullRefreshAnchor,
            trainingLoadStartDay: startDay,
            trainingLoadDailyLoads: loads,
            trainingLoadDataThrough: fullRefreshAnchor,
            expectedSourceIDsByKind: nil,
            settings: settingsFixture(idealSleepDurationMinutes: 540),
            publishedAt: republishTime
        )

        // Data payload + watermark: unchanged.
        XCTAssertEqual(republishedSeed.dataThrough, fullRefreshSeed.dataThrough)
        XCTAssertEqual(republishedSeed.trends, fullRefreshSeed.trends)
        XCTAssertEqual(republishedSeed.seriesRanges, fullRefreshSeed.seriesRanges)
        XCTAssertEqual(republishedSeed.trainingLoadStartDay, fullRefreshSeed.trainingLoadStartDay)
        XCTAssertEqual(republishedSeed.trainingLoadDailyLoads, fullRefreshSeed.trainingLoadDailyLoads)

        // Settings + transport bookkeeping: updated.
        XCTAssertEqual(republishedSeed.publishedAt, republishTime)
        XCTAssertNotEqual(republishedSeed.publishedAt, fullRefreshSeed.publishedAt)
        XCTAssertEqual(republishedSeed.settings.idealSleepDurationMinutes, 540)
        XCTAssertNotEqual(republishedSeed.settingsSignature, fullRefreshSeed.settingsSignature)
    }

    // MARK: - computeSettingsSignature

    func testSettingsSignatureIsStableForIdenticalInputs() {
        let a = HealthKitWorkoutStore.computeSettingsSignature(settingsFixture())
        let b = HealthKitWorkoutStore.computeSettingsSignature(settingsFixture())
        XCTAssertEqual(a, b)
    }

    func testSettingsSignatureChangesWhenAFlagChanges() {
        let base = HealthKitWorkoutStore.computeSettingsSignature(settingsFixture())
        let changedGoal = HealthKitWorkoutStore.computeSettingsSignature(settingsFixture(idealSleepDurationMinutes: 420))
        let changedShowScore = HealthKitWorkoutStore.computeSettingsSignature(settingsFixture(showSleepScore: false))
        // A REAL selection change (the signature signs the decoded CANONICAL
        // form, so unknown-garbage raw bytes that decode to the default
        // selection deliberately do NOT count as a change).
        let pinnedSelection = BodyHealthDataSourceSelection(
            defaultOption: .allSources,
            selectedOptions: [.heartRate: BodyHealthDataSourceOption(id: "com.example.tracker", name: "Tracker")]
        )
        let changedSource = HealthKitWorkoutStore.computeSettingsSignature(
            settingsFixture(healthDataSourceSelectionRaw: pinnedSelection.rawValue)
        )

        XCTAssertNotEqual(base, changedGoal)
        XCTAssertNotEqual(base, changedShowScore)
        XCTAssertNotEqual(base, changedSource)
    }

    func testSettingsSignatureIsStableAcrossSelectionEncodingKeyOrder() {
        // `JSONEncoder` dictionary key order can differ between phone
        // processes; the SAME logical selection must sign identically or a
        // relaunch republish masquerades as a settings change and strips the
        // watch's fresher local provenance. These two raws decode equal.
        let orderA = #"{"selectedOptions":{"heartRate":{"id":"x","name":"X"},"sleep":{"id":"y","name":"Y"}}}"#
        let orderB = #"{"selectedOptions":{"sleep":{"id":"y","name":"Y"},"heartRate":{"id":"x","name":"X"}}}"#

        XCTAssertEqual(
            HealthKitWorkoutStore.computeSettingsSignature(settingsFixture(healthDataSourceSelectionRaw: orderA)),
            HealthKitWorkoutStore.computeSettingsSignature(settingsFixture(healthDataSourceSelectionRaw: orderB))
        )
    }

    func testSettingsSignatureIgnoresTheTimeZoneMap() {
        var withMap = settingsFixture()
        withMap.recentTimeZoneIdentifiersByDay = ["2026-06-20": "America/New_York"]
        var withoutMap = settingsFixture()
        withoutMap.recentTimeZoneIdentifiersByDay = nil

        // The tz map is data (changes daily regardless of user intent), not a
        // compute-affecting setting, so it must not perturb the signature.
        XCTAssertEqual(
            HealthKitWorkoutStore.computeSettingsSignature(withMap),
            HealthKitWorkoutStore.computeSettingsSignature(withoutMap)
        )
    }

    // MARK: - computeSettingsSignature: custom source groups

    private func customGroupsRaw(name: String = "Wrist", members: [String]) -> String {
        BodyCustomHealthSourceGroupStore.rawValue(
            from: [
                BodyCustomHealthSourceGroup(
                    id: "custom:11111111-2222-3333-4444-555555555555",
                    name: name,
                    memberIdentityKeys: members
                )
            ]
        )
    }

    /// The upgrade guard: a user with no custom sources must sign EXACTLY the
    /// bytes they signed before the feature existed, or every watch on the
    /// planet discards its stored seed on the update. The pre-feature call shape
    /// (no `customHealthSourceGroupsRaw` argument at all) is spelled out here
    /// deliberately rather than reusing the fixture's default — that's the call
    /// the shipped build made.
    func testSettingsSignatureIsUnchangedWithoutCustomGroups() {
        let preFeatureSettings = WatchComputeSettings(
            idealSleepDurationMinutes: 480,
            followsSystemUnits: true,
            selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.celsius.rawValue,
            showSleepScore: true,
            showsSubMinuteAwakeSleepStages: true,
            showsLeadingTrailingAwakeSleepStages: true,
            healthDataSourceSelectionRaw: "{}",
            combinesHealthDataSourcesByName: false
        )
        let preFeature = HealthKitWorkoutStore.computeSettingsSignature(preFeatureSettings)

        // Nil (no groups / Pro lapsed), an empty raw, and an empty JSON array all
        // decode to "no groups" and must all sign the pre-feature bytes.
        XCTAssertEqual(preFeature, HealthKitWorkoutStore.computeSettingsSignature(settingsFixture()))
        XCTAssertEqual(
            preFeature,
            HealthKitWorkoutStore.computeSettingsSignature(settingsFixture(customHealthSourceGroupsRaw: ""))
        )
        XCTAssertEqual(
            preFeature,
            HealthKitWorkoutStore.computeSettingsSignature(settingsFixture(customHealthSourceGroupsRaw: "[]"))
        )
        XCTAssertFalse(preFeature.contains(";groups["))
    }

    func testSettingsSignatureTracksMembershipEditsButNotRenames() {
        let watchKey = "bundle=com.example.watch|name=watch"
        let phoneKey = "bundle=com.example.phone|name=phone"
        let strapKey = "bundle=com.example.strap|name=strap"

        let base = HealthKitWorkoutStore.computeSettingsSignature(
            settingsFixture(customHealthSourceGroupsRaw: customGroupsRaw(members: [watchKey, phoneKey]))
        )
        let renamed = HealthKitWorkoutStore.computeSettingsSignature(
            settingsFixture(customHealthSourceGroupsRaw: customGroupsRaw(name: "Everything", members: [watchKey, phoneKey]))
        )
        let edited = HealthKitWorkoutStore.computeSettingsSignature(
            settingsFixture(customHealthSourceGroupsRaw: customGroupsRaw(members: [watchKey, phoneKey, strapKey]))
        )

        XCTAssertTrue(base.contains(";groups["))
        // Creating the first group invalidates once (intentional); after that a
        // rename must not re-seed the watch, and a membership edit must.
        XCTAssertNotEqual(base, HealthKitWorkoutStore.computeSettingsSignature(settingsFixture()))
        XCTAssertEqual(base, renamed)
        XCTAssertNotEqual(base, edited)
        XCTAssertFalse(base.contains("Wrist"))
    }

    // MARK: - Body Pro gate on the seed

    /// The seed's own assembly (`publishWatchSnapshot`) can't run in a test host
    /// — it needs a live main-actor store, a HealthKit refresh to have produced
    /// a `dataThrough`, and the App Group container — so the gate is pinned
    /// through its two pure inputs: the neutralized selection it ships, and the
    /// signature that results once the groups raw is withheld. The gate
    /// EXPRESSION itself (`isProUnlocked ? … : selectionNeutralizingCustomSources(…)`
    /// plus the nil groups raw) is pinned in `ProjectConfigurationTests`.
    func testLockedEntitlementSeedInputsCollapseCustomSourcesToAllSources() {
        let custom = BodyHealthDataSourceOption(id: "custom:11111111-2222", name: "Wrist")
        let individual = BodyHealthDataSourceOption(id: "source:bundle=com.example.tracker|name=tracker", name: "Tracker")
        let selection = BodyHealthDataSourceSelection(
            defaultOption: custom,
            selectedOptions: [.heartRate: custom, .sleep: individual]
        )

        let neutralized = HealthKitWorkoutStore.selectionNeutralizingCustomSources(selection)

        // Default and per-kind custom picks both widen…
        XCTAssertEqual(neutralized.defaultOption, .allSources)
        XCTAssertEqual(neutralized.option(for: .heartRate), .allSources)
        // …while an ordinary per-kind override is left exactly as it was: the
        // gate withholds the custom sources, it doesn't reset source selection.
        XCTAssertEqual(neutralized.option(for: .sleep), individual)
        // The phone-side selection is untouched — a lapse never erases.
        XCTAssertEqual(selection.defaultOption, custom)

        // What the locked seed then signs: no `custom:` id anywhere in `src[…]`
        // and no `groups[…]` term at all (the raw ships nil).
        let lockedSignature = HealthKitWorkoutStore.computeSettingsSignature(
            settingsFixture(healthDataSourceSelectionRaw: neutralized.rawValue, customHealthSourceGroupsRaw: nil)
        )
        XCTAssertFalse(lockedSignature.contains("custom:"))
        XCTAssertFalse(lockedSignature.contains(";groups["))
        // …and it differs from the unlocked seed's signature, so the flip
        // actually re-seeds the watch instead of leaving it filtering.
        XCTAssertNotEqual(
            lockedSignature,
            HealthKitWorkoutStore.computeSettingsSignature(
                settingsFixture(
                    healthDataSourceSelectionRaw: selection.rawValue,
                    customHealthSourceGroupsRaw: customGroupsRaw(members: ["bundle=com.example.watch|name=watch"])
                )
            )
        )
    }

    // MARK: - recentTimeZoneIdentifiersByDay

    func testRecentTimeZoneIdentifiersByDayKeysISODayStringsFromTheLedger() throws {
        let suiteName = "BodyTests.ComputeSeedTZ.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ledger = BodyTimeZoneLedger(defaults: defaults, calendar: calendar)

        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 12)))
        let fiveDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: now))
        ledger.recordCurrentZone(now: fiveDaysAgo, zone: try XCTUnwrap(TimeZone(identifier: "America/New_York")))

        let map = HealthKitWorkoutStore.recentTimeZoneIdentifiersByDay(now: now, calendar: calendar, ledger: ledger)

        XCTAssertEqual(map["2026-06-20"], "America/New_York")
        XCTAssertEqual(map["2026-06-15"], "America/New_York")
        // Never `[Date: String]` — every key must be a plain ISO day string.
        XCTAssertTrue(map.keys.allSatisfy { $0.count == 10 && $0.contains("-") })
    }

    func testRecentTimeZoneIdentifiersByDayOmitsDaysBeforeTheFirstLedgerRecord() throws {
        let suiteName = "BodyTests.ComputeSeedTZ.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ledger = BodyTimeZoneLedger(defaults: defaults, calendar: calendar)

        // No records at all — every day is unknown, so the map is empty
        // (the watch falls back to `TimeZone.current.identifier` for these).
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20)))
        let map = HealthKitWorkoutStore.recentTimeZoneIdentifiersByDay(now: now, calendar: calendar, ledger: ledger)

        XCTAssertTrue(map.isEmpty)
    }
}
