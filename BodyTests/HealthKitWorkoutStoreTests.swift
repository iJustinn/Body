//
//  HealthKitWorkoutStoreTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

// MARK: - Shared test support (used by split HealthKitWorkoutStore*Tests files)

/// The store reads both first-load defaults from standard defaults at init;
/// park them so a previous run on this host cannot mask the fresh-install
/// state, and restore them from the returned closure.
func preserveInitialHealthLoadDefaults() -> () -> Void {
    let preservedRefreshDate = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
    let preservedCompletion = HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted()
    HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
    HealthDashboardSnapshotStore.clearInitialHealthDataLoadCompleted()
    return {
        if let preservedRefreshDate {
            HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(preservedRefreshDate)
        }
        if preservedCompletion {
            HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()
        } else {
            HealthDashboardSnapshotStore.clearInitialHealthDataLoadCompleted()
        }
    }
}

@MainActor
func emptyHealthDataStore() -> HealthKitWorkoutStore {
    HealthKitWorkoutStore(
        initialSnapshot: WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        ),
        initialHealthDashboardSnapshot: .empty
    )
}

/// Ring chunks only apply while Activity Rings is on in Body's own
/// selection, so a store used to drive them must say so explicitly rather
/// than inherit whatever this host has stored.
@MainActor
func activityRingsEnabledStore() -> HealthKitWorkoutStore {
    HealthKitWorkoutStore(
        initialSnapshot: WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        ),
        initialHealthDashboardSnapshot: .empty,
        initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: [.activityRings])
    )
}

func activityRingChunk(
    days: [Date],
    loadedMonthKeys: [ActivityRingMonthKey]
) -> ActivityRingHistorySnapshot {
    let summary = ActivityRingSummary(
        move: ActivityRingMetric(value: 500, goal: 500),
        exercise: ActivityRingMetric(value: 30, goal: 30),
        stand: ActivityRingMetric(value: 12, goal: 12)
    )
    return ActivityRingHistorySnapshot(
        days: days.map { ActivityRingDaySummary(date: $0, summary: summary) },
        loadedMonthKeys: loadedMonthKeys
    )
}

/// One chunk shaped the way the newest-first backfill walk hands them over:
/// only that chunk's days, plus the checkpoint to resume from. A `nil`
/// checkpoint is the chunk that reached history start.
func activityRingBackfillChunk(
    days: [Date],
    loadedMonthKeys: [ActivityRingMonthKey],
    nextChunkEndDate: Date?
) -> ActivityRingHistoryFetchResult {
    ActivityRingHistoryFetchResult(
        history: activityRingChunk(days: days, loadedMonthKeys: loadedMonthKeys),
        hadQueryFailure: false,
        reachedHistoryStart: nextChunkEndDate == nil,
        nextChunkEndDate: nextChunkEndDate
    )
}

/// The backfill checkpoint lives in standard defaults; park it so a previous
/// run on this host can't mask a fresh walk, and restore it afterwards.
func preserveActivityRingBackfillState() -> () -> Void {
    let preserved = HealthDashboardSnapshotStore.loadActivityRingBackfillState()
    HealthDashboardSnapshotStore.clearActivityRingBackfillState()
    return {
        HealthDashboardSnapshotStore.saveActivityRingBackfillState(preserved)
    }
}

func cachedHealthDashboardSnapshot() throws -> HealthDashboardSnapshot {
    let calendar = Calendar.bodyGregorian
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
    let sleepStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 1)))
    let sleepEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 8)))
    let summary = HealthSummarySnapshot(
        activityRings: ActivityRingSummary(
            move: ActivityRingMetric(value: 450, goal: 600),
            exercise: ActivityRingMetric(value: 45, goal: 30),
            stand: ActivityRingMetric(value: 9, goal: 12)
        ),
        sleep: SleepSummary(
            duration: 7 * 60 * 60,
            stageSnapshot: SleepStageSnapshot(
                date: day,
                segments: [
                    SleepStageSegment(stage: .core, startDate: sleepStart, endDate: sleepEnd)
                ]
            ),
            vitals: SleepVitalsSummary(
                heartRate: 58,
                heartRateVariability: 62,
                respiratoryRate: 14,
                oxygenSaturation: 97,
                wristTemperatureCelsius: 36.4
            )
        ),
        restingHeartRate: HealthMetricSummary(value: 61),
        bodyMass: HealthMetricSummary(value: 69.25),
        bodyFatPercentage: HealthMetricSummary(value: 13.2),
        heartRateVariability: HealthMetricSummary(value: 42),
        respiratoryRate: HealthMetricSummary(value: 14),
        oxygenSaturation: HealthMetricSummary(value: 98),
        bodyMassIndex: HealthMetricSummary(value: 22.1),
        activeEnergy: HealthMetricSummary(value: 530),
        restingEnergy: HealthMetricSummary(value: 1_720)
    )
    let trends = HealthTrendSnapshot(
        sleep: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 7)]),
        restingHeartRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 61)]),
        bodyMass: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 69.25)]),
        bodyFatPercentage: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 13.2)]),
        heartRateVariability: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 42)]),
        respiratoryRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 14)]),
        oxygenSaturation: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 98)]),
        bodyMassIndex: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 22.1)]),
        activeEnergy: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 530)]),
        restingEnergy: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 1_720)])
    )

    let activityRingHistory = ActivityRingHistorySnapshot(days: [
        ActivityRingDaySummary(date: day, summary: summary.activityRings)
    ])

    return HealthDashboardSnapshot(
        summary: summary,
        trends: trends,
        activityRingHistory: activityRingHistory
    )
}

final class HealthKitWorkoutStoreTests: XCTestCase {

    func testHealthPermissionSelectionLimitsHealthKitReadTypes() throws {
        let readTypes = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.steps, .wristTemperature])
        )

        XCTAssertTrue(readTypes.contains(try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))))
        XCTAssertTrue(readTypes.contains(try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature))))
        XCTAssertFalse(readTypes.contains(HKObjectType.workoutType()))
        XCTAssertFalse(readTypes.contains(HKObjectType.activitySummaryType()))
        XCTAssertFalse(readTypes.contains(try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .restingHeartRate))))
        XCTAssertFalse(readTypes.contains(try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))))
    }

    func testWorkoutMetricsPermissionGatesDetailReadTypes() throws {
        let vo2Max = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .vo2Max))
        let runningPower = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningPower))
        let cyclingPower = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .cyclingPower))
        let cyclingCadence = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .cyclingCadence))
        let swimStrokes = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount))
        let strideLength = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningStrideLength))
        let groundContact = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningGroundContactTime))
        let verticalOscillation = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation))
        let distance = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning))

        // Workouts + Workout Metrics: detail metrics requested; distance (core) also present.
        let both = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workouts, .workoutMetrics])
        )
        XCTAssertTrue(both.contains(vo2Max))
        XCTAssertTrue(both.contains(runningPower))
        XCTAssertTrue(both.contains(cyclingPower))
        XCTAssertTrue(both.contains(cyclingCadence))
        XCTAssertTrue(both.contains(swimStrokes))
        XCTAssertTrue(both.contains(strideLength))
        XCTAssertTrue(both.contains(groundContact))
        XCTAssertTrue(both.contains(verticalOscillation))
        XCTAssertTrue(both.contains(distance))
        XCTAssertTrue(both.contains(HKObjectType.workoutType()))

        // Workouts alone: distance + workout type stay; the detail metrics drop.
        let workoutsOnly = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workouts])
        )
        XCTAssertTrue(workoutsOnly.contains(distance))
        XCTAssertTrue(workoutsOnly.contains(HKObjectType.workoutType()))
        XCTAssertFalse(workoutsOnly.contains(vo2Max))
        XCTAssertFalse(workoutsOnly.contains(runningPower))
        XCTAssertFalse(workoutsOnly.contains(cyclingPower))
        XCTAssertFalse(workoutsOnly.contains(swimStrokes))
        XCTAssertFalse(workoutsOnly.contains(strideLength))
        XCTAssertFalse(workoutsOnly.contains(groundContact))
        XCTAssertFalse(workoutsOnly.contains(verticalOscillation))

        // Workout Metrics without Workouts: nothing requested (AND-gate).
        let metricsOnly = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workoutMetrics])
        )
        XCTAssertFalse(metricsOnly.contains(vo2Max))
        XCTAssertFalse(metricsOnly.contains(distance))
    }

    /// Heart-rate recovery feeds a workout-detail tile but is heart data, so it
    /// rides the Heart toggle rather than Workouts/Workout Metrics.
    func testHeartPermissionGatesHeartRateRecoveryReadType() throws {
        let recovery = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute))

        XCTAssertTrue(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.heart])
        ).contains(recovery))

        XCTAssertFalse(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workouts, .workoutMetrics])
        ).contains(recovery))
    }

    func testDateOfBirthPermissionGatesCharacteristicReadType() throws {
        let dateOfBirth = try XCTUnwrap(HKObjectType.characteristicType(forIdentifier: .dateOfBirth))

        let both = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.heart, .dateOfBirth])
        )
        XCTAssertTrue(both.contains(dateOfBirth))

        // Heart alone (no Date of Birth) and Date of Birth alone (no Heart): not requested.
        let heartOnly = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.heart])
        )
        XCTAssertFalse(heartOnly.contains(dateOfBirth))

        let dateOfBirthOnly = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.dateOfBirth])
        )
        XCTAssertFalse(dateOfBirthOnly.contains(dateOfBirth))
    }

    /// Pins the sync badge's "can this refresh dispatch any query" oracle:
    /// dependent-only selections (child toggles without their parents) yield an
    /// EMPTY read set, so `ranQueries` must be false and the badge must not
    /// confirm "Health data updated" for such a refresh.
    func testDependentOnlyPermissionSelectionsYieldNoReadTypes() {
        XCTAssertTrue(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.dateOfBirth, .workoutMetrics])
        ).isEmpty)
        XCTAssertTrue(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [])
        ).isEmpty)
        XCTAssertFalse(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workouts, .workoutMetrics])
        ).isEmpty)
    }

    @MainActor
    func testNeedsInitialHealthDataLoadReflectsCacheAndRefreshState() throws {
        // The store reads the persisted refresh timestamp and the first-load
        // completion flag from standard defaults at init; park both so a
        // previous run on this host cannot mask the fresh-install state.
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        )

        let emptyStore = HealthKitWorkoutStore(
            initialSnapshot: initialSnapshot,
            initialHealthDashboardSnapshot: .empty
        )
        XCTAssertTrue(emptyStore.needsInitialHealthDataLoad)

        let cachedStore = HealthKitWorkoutStore(
            initialSnapshot: initialSnapshot,
            initialHealthDashboardSnapshot: try cachedHealthDashboardSnapshot()
        )
        XCTAssertFalse(cachedStore.needsInitialHealthDataLoad)
    }

    @MainActor
    func testPartialRefreshClearsNeedsInitialHealthDataLoadWithoutArmingFreshnessTTL() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }

        let store = emptyHealthDataStore()
        XCTAssertTrue(store.needsInitialHealthDataLoad)

        // Denied read permissions make some leaves fail on every refresh; the
        // completed full refresh still counts as the first load.
        store.markRefreshSucceeded(date: Date(), refreshedVitals: true, hadQueryFailure: true)
        XCTAssertTrue(store.hasCompletedInitialHealthDataLoad)
        XCTAssertFalse(store.needsInitialHealthDataLoad)
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertFalse(store.hasHealthDataToShow)
    }

    @MainActor
    func testNonVitalsRefreshLeavesInitialHealthDataLoadPending() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }

        let store = emptyHealthDataStore()
        store.markRefreshSucceeded(date: Date(), refreshedVitals: false)
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)
        XCTAssertTrue(store.needsInitialHealthDataLoad)
    }

    @MainActor
    func testPassiveLoadsStayIdleUntilFirstHealthDataLoad() async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 5,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: .empty
        )
        XCTAssertTrue(store.needsInitialHealthDataLoad)

        let didLoad = await store.loadMonthIfNeeded(month: 4, year: 2026)
        XCTAssertFalse(didLoad)
        XCTAssertFalse(store.hasLoadedSnapshot(month: 4, year: 2026))

        await store.loadRecentWorkoutMonthsIfNeeded()
        XCTAssertTrue(store.loadingMonthKeys.isEmpty)

        await store.loadPreviousActivityRingMonthIfNeeded()
        XCTAssertTrue(store.activityRingHistory.isEmpty)
        XCTAssertTrue(store.loadingActivityRingMonthKeys.isEmpty)
    }

    /// A lazy-load-style success (`refreshedVitals: false` — month paging, older
    /// ring history, single-metric or workout-only refreshes) must not arm the
    /// dashboard-freshness TTL, in memory or in the persisted timestamp;
    /// otherwise paging history keeps the TTL fresh and warm resumes skip the
    /// vitals refresh indefinitely. Only a vitals-refreshing success arms it.
    @MainActor
    func testMarkRefreshSucceededOnlyArmsFreshnessTTLWhenVitalsRefreshed() throws {
        let preservedRefreshDate = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        defer {
            HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
            if let preservedRefreshDate {
                HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(preservedRefreshDate)
            }
        }

        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 5,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: .empty
        )
        XCTAssertNil(store.lastSuccessfulRefreshDate)

        let lazyLoadDate = Date(timeIntervalSince1970: 1_700_000_000)
        store.markRefreshSucceeded(date: lazyLoadDate, refreshedVitals: false, publishesWatch: false)
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertNil(HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate())

        let vitalsRefreshDate = Date(timeIntervalSince1970: 1_700_000_100)
        store.markRefreshSucceeded(date: vitalsRefreshDate, refreshedVitals: true, publishesWatch: false)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, vitalsRefreshDate)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate(), vitalsRefreshDate)
    }

    func testHealthKitWorkoutTypeMappingPreservesSpecificActivities() {
        let mappings: [(HKWorkoutActivityType, BodyWorkoutType)] = [
            (.running, .running),
            (.walking, .walking),
            (.traditionalStrengthTraining, .strengthTraining),
            (.functionalStrengthTraining, .functionalStrengthTraining),
            (.pickleball, .pickleball),
            (.pilates, .pilates),
            (.elliptical, .elliptical),
            (.rowing, .rowing),
            (.soccer, .soccer),
            (.tennis, .tennis),
            (.cooldown, .cooldown),
            (.swimBikeRun, .swimBikeRun),
            (.underwaterDiving, .underwaterDiving)
        ]

        for (activityType, bodyType) in mappings {
            XCTAssertEqual(HealthKitWorkoutStore.workoutType(for: activityType), bodyType)
        }
    }

    func testUnknownHealthKitWorkoutTypeFallsBackToOther() throws {
        let unknownActivityType = try XCTUnwrap(HKWorkoutActivityType(rawValue: 81))
        XCTAssertEqual(HealthKitWorkoutStore.workoutType(for: unknownActivityType), .other)
    }

    func testIntradayFetchStartBacksUpByOverlapWindow() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        // Newest cached point is well inside the window; backing up 48h stays
        // inside the window, so the overlap anchor wins.
        let cachedSampleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 7)))
        // Newest cached point is close to the window start; backing up 48h would
        // fall before it, so the fetch clamps to windowStart.
        let nearStartSampleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 7)))

        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: .empty, windowStart: windowStart),
            windowStart
        )
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(
                after: HealthTrendSeries(points: [HealthTrendDataPoint(date: cachedSampleDate, value: 61)]),
                windowStart: windowStart
            ),
            cachedSampleDate.addingTimeInterval(-HealthKitFetchEngine.incrementalOverlapWindow)
        )
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(
                after: HealthTrendSeries(points: [HealthTrendDataPoint(date: nearStartSampleDate, value: 61)]),
                windowStart: windowStart
            ),
            windowStart
        )
    }

    func testAverageVitalValuesPartitionsSamplesPerNightInterval() throws {
        let calendar = Calendar.bodyGregorian
        let night1Start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 1)))
        let night1End = night1Start.addingTimeInterval(7 * 60 * 60)
        let night2Start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 0, minute: 30)))
        let night2End = night2Start.addingTimeInterval(7 * 60 * 60)
        let night3Start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 2)))
        let night3End = night3Start.addingTimeInterval(6 * 60 * 60)

        func instant(_ date: Date, _ value: Double) -> SleepVitalWindowSample {
            SleepVitalWindowSample(startDate: date, endDate: date, value: value)
        }

        let samples = [
            // Instantaneous sample at the exact night start counts.
            instant(night1Start, 60),
            instant(night1Start.addingTimeInterval(3_600), 64),
            // Spans the night-2 boundary: overlaps night 2 only.
            SleepVitalWindowSample(
                startDate: night2Start.addingTimeInterval(-1_800),
                endDate: night2Start.addingTimeInterval(1_800),
                value: 50
            ),
            instant(night2Start.addingTimeInterval(60), 54),
            // Instantaneous sample at the exact night end is excluded ([start, end)).
            instant(night2End, 99)
        ].sorted { $0.startDate < $1.startDate }

        let averages = BodySleepFetch.averageVitalValues(
            samples: samples,
            intervals: [
                DateInterval(start: night1Start, end: night1End),
                DateInterval(start: night2Start, end: night2End),
                DateInterval(start: night3Start, end: night3End)
            ]
        )

        XCTAssertEqual(averages.count, 3)
        XCTAssertEqual(try XCTUnwrap(averages[0]), 62, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(averages[1]), 52, accuracy: 0.0001)
        XCTAssertNil(averages[2])
    }

    func testAverageVitalValuesReturnsNilsWhenNoSamples() {
        let now = Date()

        let averages = BodySleepFetch.averageVitalValues(
            samples: [],
            intervals: [DateInterval(start: now, end: now.addingTimeInterval(3_600))]
        )

        XCTAssertEqual(averages, [nil])
    }

    @MainActor
    func testWidgetReloadCoalescerCollapsesBurstsIntoOneReload() async {
        var reloadCount = 0
        let coalescer = BodyWidgetReloadCoalescer(debounceNanoseconds: 5_000_000) {
            reloadCount += 1
        }

        coalescer.requestReload()
        coalescer.requestReload()
        coalescer.requestReload()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(reloadCount, 1)

        coalescer.requestReload()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(reloadCount, 2)
    }

    @MainActor
    func testWidgetReloadCoalescerServesReloadRequestedDuringReload() async {
        var reloadCount = 0
        var coalescer: BodyWidgetReloadCoalescer?
        coalescer = BodyWidgetReloadCoalescer(debounceNanoseconds: 5_000_000) {
            reloadCount += 1
            if reloadCount == 1 {
                coalescer?.requestReload()
            }
        }

        coalescer?.requestReload()
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(reloadCount, 2)
    }

    func testPartitionHeartRateSamplesMatchesPerWorkoutWindowFiltering() {
        let base = Date(timeIntervalSinceReferenceDate: 790_000_000)
        let samples = (0..<500).map { offset in
            WorkoutHeartRateSample(
                date: base.addingTimeInterval(Double(offset) * 90),
                beatsPerMinute: 80 + Double(offset % 40)
            )
        }
        let windows: [(id: UUID, startDate: Date, endDate: Date)] = [
            // Starts exactly on a sample date.
            (UUID(), base, base.addingTimeInterval(1_800)),
            // Overlaps the first window.
            (UUID(), base.addingTimeInterval(900), base.addingTimeInterval(2_700)),
            // Zero-length window matches nothing.
            (UUID(), base.addingTimeInterval(10_000), base.addingTimeInterval(10_000)),
            (UUID(), base.addingTimeInterval(20_000), base.addingTimeInterval(26_000)),
            // Extends past the last sample.
            (UUID(), base.addingTimeInterval(44_910), base.addingTimeInterval(60_000))
        ]

        let partitioned = HealthKitFetchEngine.partitionHeartRateSamples(samples, forWorkoutWindows: windows)

        XCTAssertEqual(partitioned.count, windows.count)
        for window in windows {
            let expected = samples.filter { $0.date >= window.startDate && $0.date < window.endDate }
            XCTAssertEqual(partitioned[window.id]?.map(\.date), expected.map(\.date))
            XCTAssertEqual(partitioned[window.id]?.map(\.beatsPerMinute), expected.map(\.beatsPerMinute))
        }
    }

    @MainActor
    func testFreshnessTTLGateUnchangedByBadgeSignalChange() {
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)
        )
        XCTAssertNil(store.lastSuccessfulRefreshDate)

        // Vitals refresh with a leaf failure must NOT arm the freshness TTL.
        store.markRefreshSucceeded(date: Date(), refreshedVitals: true, publishesWatch: false, hadQueryFailure: true, advancesSyncBadge: true)
        XCTAssertNil(store.lastSuccessfulRefreshDate)

        // Clean vitals refresh arms it.
        let date = Date()
        store.markRefreshSucceeded(date: date, refreshedVitals: true, publishesWatch: false, hadQueryFailure: false, advancesSyncBadge: true)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, date)
    }
}
