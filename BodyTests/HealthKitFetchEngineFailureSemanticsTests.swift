//
//  HealthKitFetchEngineFailureSemanticsTests.swift
//  BodyTests
//
//  Failure-vs-empty semantics for the HealthKit fetch engine (H2/H3/H4/H12,
//  M15): a query FAILURE keeps the cached value, while a genuine absence
//  (confirmed-empty, permission-off, selection-off) clears it. Covers the pure
//  resolvers that back those decisions; the actor's HK query paths are
//  exercised by the manual/simulator flows in the plan.
//

import XCTest
@testable import Body

final class HealthKitFetchEngineFailureSemanticsTests: XCTestCase {
    private typealias Outcome = HealthKitFetchEngine.QueryOutcome<HealthMetricSummary>

    // MARK: - QueryOutcome resolver truth table (H2)

    func testResolvedSummaryValueReplacesCacheOnSuccessValue() {
        let fresh = HealthMetricSummary(value: 60)
        let cached = HealthMetricSummary(value: 50)
        let resolved = HealthKitFetchEngine.resolvedSummaryValue(fetched: Outcome.success(fresh), cached: cached)
        XCTAssertEqual(resolved, fresh)
    }

    func testResolvedSummaryValueClearsOnConfirmedAbsent() {
        // `.success(nil)` covers confirmed-empty, permission-off, and
        // selection-off — all of which must clear the tile, not keep the cache.
        let cached = HealthMetricSummary(value: 50)
        let resolved = HealthKitFetchEngine.resolvedSummaryValue(fetched: Outcome.success(nil), cached: cached)
        XCTAssertNil(resolved)
    }

    func testResolvedSummaryValueKeepsCacheOnFailure() {
        let cached = HealthMetricSummary(value: 50)
        let resolved = HealthKitFetchEngine.resolvedSummaryValue(fetched: Outcome.failure, cached: cached)
        XCTAssertEqual(resolved, cached)
    }

    func testResolvedSummaryValueFailureWithoutCacheIsEmpty() {
        // Signature mismatch → the store passes no cached value → a failure
        // resolves to empty rather than stale other-source data.
        let resolved = HealthKitFetchEngine.resolvedSummaryValue(fetched: Outcome.failure, cached: nil)
        XCTAssertNil(resolved)
    }

    func testQueryOutcomeIsFailure() {
        XCTAssertTrue(Outcome.failure.isFailure)
        XCTAssertFalse(Outcome.success(nil).isFailure)
        XCTAssertFalse(Outcome.success(HealthMetricSummary(value: 1)).isFailure)
    }

    func testQueryOutcomeSuccessValue() {
        XCTAssertNil(Outcome.failure.successValue)
        XCTAssertNil(Outcome.success(nil).successValue)
        XCTAssertEqual(Outcome.success(HealthMetricSummary(value: 7)).successValue, HealthMetricSummary(value: 7))
    }

    func testQueryOutcomeValueOrFallsBackForFailureAndAbsent() {
        typealias Samples = HealthKitFetchEngine.QueryOutcome<[Int]>
        XCTAssertEqual(Samples.failure.valueOr([]), [])
        XCTAssertEqual(Samples.success(nil).valueOr([]), [])
        XCTAssertEqual(Samples.success([1, 2]).valueOr([]), [1, 2])
    }

    // MARK: - Low heart rate event resolver

    func testResolvedLowHeartRateEventClearsOnConfirmedAbsent() {
        // The threshold-filtered query came back empty today → the badge must
        // clear rather than keep yesterday's episode.
        typealias LowOutcome = HealthKitFetchEngine.QueryOutcome<LowHeartRateEvent>
        let cached = LowHeartRateEvent(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_300),
            minimumBPM: 38,
            sampleCount: 3
        )
        XCTAssertNil(
            HealthKitFetchEngine.resolvedSummaryValue(fetched: LowOutcome.success(nil), cached: cached)
        )
    }

    func testResolvedLowHeartRateEventKeepsCacheOnFailureAndReplacesOnSuccess() {
        typealias LowOutcome = HealthKitFetchEngine.QueryOutcome<LowHeartRateEvent>
        let cached = LowHeartRateEvent(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_300),
            minimumBPM: 38,
            sampleCount: 3
        )
        let fresh = LowHeartRateEvent(
            startDate: Date(timeIntervalSince1970: 1_700_086_400),
            endDate: Date(timeIntervalSince1970: 1_700_086_700),
            minimumBPM: 35,
            sampleCount: 2
        )
        // Failure (including cancellation, which resumes `.failure`) retains.
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSummaryValue(fetched: LowOutcome.failure, cached: cached),
            cached
        )
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSummaryValue(fetched: LowOutcome.success(fresh), cached: cached),
            fresh
        )
    }

    // MARK: - Effort failure fallback (H12)

    func testEffortFallbackUsesFetchedWhenPresent() {
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedWorkoutEffortLevel(fetchedEffort: 8, workoutFailed: true, cachedEffort: 3),
            8
        )
    }

    func testEffortFallbackReusesCachedOnFailure() {
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedWorkoutEffortLevel(fetchedEffort: nil, workoutFailed: true, cachedEffort: 4),
            4
        )
    }

    func testEffortFallbackFailedWithNoPriorKeepsDefault() {
        // Failed with no prior score → nil level AND the unresolved flag set, so
        // the workout is EXCLUDED from training load rather than counted as the
        // fabricated default 5 (H12). See `testTrainingLoadExcludesUnresolvedEffort`.
        XCTAssertNil(
            HealthKitFetchEngine.resolvedWorkoutEffortLevel(fetchedEffort: nil, workoutFailed: true, cachedEffort: nil)
        )
        XCTAssertTrue(
            HealthKitFetchEngine.resolvedWorkoutEffortUnresolved(fetchedEffort: nil, workoutFailed: true, cachedEffort: nil)
        )
    }

    func testEffortConfirmedNoEffortDoesNotResurrectCache() {
        // The query succeeded and found no score (not a failure) → nil so the
        // default rating applies; a stale cached score must NOT resurrect.
        XCTAssertNil(
            HealthKitFetchEngine.resolvedWorkoutEffortLevel(fetchedEffort: nil, workoutFailed: false, cachedEffort: 4)
        )
    }

    func testEffortUnresolvedOnlyWhenFailedAndUncached() {
        // Unresolved is a strict subset of "nil level": ONLY a failed query with
        // no cached fallback. A cached fallback, a fetched score, or a genuine
        // no-score (query succeeded) are all resolved.
        XCTAssertTrue(
            HealthKitFetchEngine.resolvedWorkoutEffortUnresolved(fetchedEffort: nil, workoutFailed: true, cachedEffort: nil)
        )
        XCTAssertFalse(
            HealthKitFetchEngine.resolvedWorkoutEffortUnresolved(fetchedEffort: nil, workoutFailed: true, cachedEffort: 4)
        )
        XCTAssertFalse(
            HealthKitFetchEngine.resolvedWorkoutEffortUnresolved(fetchedEffort: 8, workoutFailed: true, cachedEffort: nil)
        )
        XCTAssertFalse(
            HealthKitFetchEngine.resolvedWorkoutEffortUnresolved(fetchedEffort: nil, workoutFailed: false, cachedEffort: nil)
        )
    }

    // MARK: - Workout detail metric failure fallback (H12)

    func testDetailMetricFailedReusesCached() {
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedWorkoutDetailMetric(fetched: nil, failed: true, cached: 42),
            42
        )
    }

    func testDetailMetricFailedWithNoCacheIsNil() {
        XCTAssertNil(
            HealthKitFetchEngine.resolvedWorkoutDetailMetric(fetched: nil, failed: true, cached: nil)
        )
    }

    func testDetailMetricSuccessUsesFetchedValue() {
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedWorkoutDetailMetric(fetched: 7, failed: false, cached: 42),
            7
        )
    }

    func testDetailMetricSuccessConfirmedAbsentClearsEvenWithCache() {
        // The query SUCCEEDED and found no value → nil clears the field even
        // though a cached value exists; a stale cached value must NOT
        // resurrect (this is the reuse-branch regression the H12 fix covers).
        XCTAssertNil(
            HealthKitFetchEngine.resolvedWorkoutDetailMetric(fetched: nil, failed: false, cached: 42)
        )
    }

    // MARK: - Sleep-vital per-night resolver (H2b)

    func testResolvedSleepVitalKeepsCachedOnFailure() {
        // A per-vital query failure merges that night's vital from the cached
        // night (matched by wake day one level up), never blanks it.
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSleepVital(.failure, at: 0, cached: 58),
            58
        )
    }

    func testResolvedSleepVitalUsesFetchedNightValue() {
        // A successful fetch replaces the cache per night, including a genuine nil
        // (no samples that night) which clears.
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSleepVital(.success([61, 62, 63]), at: 1, cached: 58),
            62
        )
        XCTAssertNil(
            HealthKitFetchEngine.resolvedSleepVital(.success([61, nil, 63]), at: 1, cached: 58)
        )
    }

    func testResolvedSleepVitalOutOfRangeIndexIsNil() {
        // A success whose array doesn't cover the index (shouldn't happen given
        // aligned intervals) resolves to nil rather than trapping.
        XCTAssertNil(
            HealthKitFetchEngine.resolvedSleepVital(.success([61]), at: 3, cached: 58)
        )
        XCTAssertNil(
            HealthKitFetchEngine.resolvedSleepVital(.success(nil), at: 0, cached: 58)
        )
    }

    // MARK: - Intraday day-sample window (M15)

    func testIntradayDaySampleIntervalIsShorterThanTrendWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)

        let intraday = HealthKitFetchEngine.intradayDaySampleInterval(calendar: calendar, anchor: anchor)
        let trend = HealthKitFetchEngine.recentHealthTrendInterval(calendar: calendar, anchor: anchor)

        XCTAssertEqual(intraday.end, anchor)
        // The intraday raw-sample window is far smaller than the 365-day daily
        // trend window it used to reuse.
        XCTAssertGreaterThan(intraday.start, trend.start)
        // …but still reaches the recent-month picker window (30 days back).
        let thirtyDaysBack = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: anchor))!
        XCTAssertLessThanOrEqual(intraday.start, thirtyDaysBack)
    }

    // MARK: - Source-option discovery resolver truth table (H4)

    func testResolvedSourceOptionKeepsStoredOptionWhenDiscoveryUnresolved() {
        // nil discoveredNonemptyIDs = discovery never succeeded this process. The
        // stored option is kept unchanged for BOTH fallback roles so leaf queries
        // skip with failure semantics via `sourceSelectionUnresolved` (H4) rather
        // than clearing the cached series.
        let stored = BodyHealthDataSourceOption(id: "com.garmin.connect", name: "Garmin")
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSourceOption(stored, discoveredNonemptyIDs: nil, absentFallback: .allSources),
            stored
        )
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSourceOption(stored, discoveredNonemptyIDs: nil, absentFallback: .noComparison),
            stored
        )
    }

    func testResolvedSourceOptionFallsBackWhenDiscoveredButAbsent() {
        // Discovery succeeded (non-nil set) but the stored source is not among the
        // non-empty buckets → confirmed gone → the fallback for the role.
        let stored = BodyHealthDataSourceOption(id: "com.garmin.connect", name: "Garmin")
        let discovered: Set<String> = ["com.apple.Health", "com.ouraring.oura"]
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSourceOption(stored, discoveredNonemptyIDs: discovered, absentFallback: .allSources),
            .allSources
        )
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSourceOption(stored, discoveredNonemptyIDs: discovered, absentFallback: .noComparison),
            .noComparison
        )
    }

    func testResolvedSourceOptionKeepsStoredOptionWhenDiscoveredAndPresent() {
        let stored = BodyHealthDataSourceOption(id: "com.garmin.connect", name: "Garmin")
        let discovered: Set<String> = ["com.garmin.connect", "com.apple.Health"]
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSourceOption(stored, discoveredNonemptyIDs: discovered, absentFallback: .allSources),
            stored
        )
    }

    func testResolvedSourceOptionIsTotalForSentinelOptions() {
        // The instance resolvers short-circuit `.allSources` / `.noComparison`
        // before ever reaching the helper, but the helper itself is total: a
        // sentinel option is kept when unresolved or discovered, and falls back
        // only when a discovered set omits its id.
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSourceOption(.allSources, discoveredNonemptyIDs: nil, absentFallback: .noComparison),
            .allSources
        )
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSourceOption(.allSources, discoveredNonemptyIDs: ["all"], absentFallback: .noComparison),
            .allSources
        )
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedSourceOption(.allSources, discoveredNonemptyIDs: ["com.apple.Health"], absentFallback: .noComparison),
            .noComparison
        )
    }

    // MARK: - Actor identity comparison with unresolved discovery (H4)

    func testSecondaryAllSourcesSurvivesUnresolvedPrimaryDiscovery() async throws {
        // A fresh engine has `healthSourcesByKind == [:]`, so discovery is
        // unresolved for every kind. With the fix the stored SPECIFIC primary is
        // KEPT (not collapsed to All Sources), so a stored `.allSources` secondary
        // no longer shares the primary's id and stays `.allSources` — before the
        // fix the unresolved primary collapsed to `.allSources`, making the ids
        // equal so the identity comparison at ~651 returned `.noComparison`.
        try XCTSkipUnless(
            UserDefaults(suiteName: WorkoutSnapshotStore.appGroupIdentifier) != nil,
            "App Group suite unavailable in this test host"
        )
        let wasUnlocked = BodyProEntitlement.isUnlocked
        BodyProEntitlement.setUnlocked(true)
        defer { BodyProEntitlement.setUnlocked(wasUnlocked) }

        let kind = HealthMetricKind.restingHeartRate
        let primary = BodyHealthDataSourceOption(id: "com.garmin.connect", name: "Garmin")
        let engine = HealthKitFetchEngine(
            permission: .defaultValue,
            healthDataSourceSelection: BodyHealthDataSourceSelection(selectedOptions: [kind: primary]),
            secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection(selectedOptions: [kind: .allSources]),
            combinesHealthDataSourcesByName: false
        )

        let resolvedSecondary = await engine.selectedSecondaryHealthDataSourceOption(for: kind)
        XCTAssertEqual(resolvedSecondary, .allSources)

        let primaryUnresolved = await engine.sourceSelectionUnresolved(for: kind)
        XCTAssertTrue(primaryUnresolved)
    }
}
