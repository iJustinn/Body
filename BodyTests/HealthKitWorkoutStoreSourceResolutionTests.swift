//
//  HealthKitWorkoutStoreSourceResolutionTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

final class HealthKitWorkoutStoreSourceResolutionTests: XCTestCase {

    func testMergeIntradaySamplesDropsExpiredCacheAndReplacesRefetchWindow() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let expiredDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 23)))
        let keptDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 1)))
        // Refetch window opens at day 2; the incoming series is authoritative from there.
        let refetchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let incomingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 1)))

        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: expiredDate, value: 59),
                HealthTrendDataPoint(date: keptDate, value: 61)
            ]),
            incoming: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: incomingDate, value: 62)
            ]),
            windowStart: windowStart,
            refetchStart: refetchStart
        )

        XCTAssertEqual(merged.points.map(\.date), [keptDate, incomingDate])
        XCTAssertEqual(merged.points.map(\.value), [61, 62])
    }

    func testMergeIntradaySamplesReconcilesBackfilledSampleInsideOverlap() throws {
        // Regression for H1: a sample timestamped earlier than the newest cached
        // point arrives late (Watch batch sync / third-party backfill). Because
        // the refetch window covers its timestamp, the authoritative `incoming`
        // series carries both the backfilled point and the previously-cached one,
        // and the merge yields them in order with no duplication.
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let refetchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 6)))
        let cachedNewest = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 8)))
        let backfilledDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 7)))

        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: cachedNewest, value: 70)
            ]),
            // Refetch returns the whole overlap window: the late backfill plus the
            // already-cached point (HealthKit hands back everything it now holds).
            incoming: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: backfilledDate, value: 55),
                HealthTrendDataPoint(date: cachedNewest, value: 70)
            ]),
            windowStart: windowStart,
            refetchStart: refetchStart
        )

        XCTAssertEqual(merged.points.map(\.date), [backfilledDate, cachedNewest])
        XCTAssertEqual(merged.points.map(\.value), [55, 70])
    }

    // MARK: - M7: HealthKit query failure vs empty result

    func testResolvedTrendSeriesKeepsCacheWhenFetchFailed() throws {
        // A `nil` fetched value models a failed HealthKit query (device locked,
        // store unavailable, XPC drop) — the cached series must survive rather
        // than being blanked.
        let cached = HealthTrendSeries(points: [
            HealthTrendDataPoint(
                date: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 5))),
                value: 61
            )
        ])

        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: nil, cached: cached),
            cached
        )
    }

    func testResolvedTrendSeriesReplacesCacheOnSuccessEvenWhenEmpty() throws {
        // A non-nil fetched value replaces the cache — including a genuinely
        // empty successful result and the intentionally empty series produced
        // when a permission is toggled off (both are "authoritative empty",
        // distinct from a failed query's `nil`).
        let cached = HealthTrendSeries(points: [
            HealthTrendDataPoint(
                date: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 5))),
                value: 61
            )
        ])
        let fresh = HealthTrendSeries(points: [
            HealthTrendDataPoint(
                date: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 6))),
                value: 64
            )
        ])

        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: fresh, cached: cached),
            fresh
        )
        // Permission-off / authoritative-empty clears the cache.
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: .empty, cached: cached),
            .empty
        )
    }

    func testResolvedTrendSeriesAppliesToSleepHistorySnapshot() throws {
        // The same merge protects the sleep history that feeds readiness: a
        // failed sleep query keeps the cached nights; a successful empty result
        // clears them.
        let cached = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 5))),
                summary: SleepSummary(duration: 7 * 3_600)
            )
        ])

        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: SleepHistorySnapshot?.none, cached: cached),
            cached
        )
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: SleepHistorySnapshot.empty, cached: cached),
            .empty
        )
    }

    func testMergeIntradaySamplesRefetchStartNeverPrecedesWindowStart() throws {
        // When the cache's newest point sits within the overlap window of
        // windowStart, incrementalFetchStart clamps refetchStart to windowStart,
        // so the whole cached series is authoritative-replaced by the refetch.
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let cachedSampleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12)))
        let refetchStart = HealthKitFetchEngine.incrementalFetchStart(
            after: HealthTrendSeries(points: [HealthTrendDataPoint(date: cachedSampleDate, value: 61)]),
            windowStart: windowStart
        )
        XCTAssertEqual(refetchStart, windowStart)

        let incomingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12)))
        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: cachedSampleDate, value: 61)
            ]),
            incoming: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: incomingDate, value: 63)
            ]),
            windowStart: windowStart,
            refetchStart: refetchStart
        )

        // No point kept before refetchStart (== windowStart); refetch replaces all.
        XCTAssertEqual(merged.points.map(\.date), [incomingDate])
        XCTAssertEqual(merged.points.map(\.value), [63])
    }

    func testMergeIntradaySamplesEmptyIncomingDeletesOnlyInsideRefetchWindow() throws {
        // Empty incoming with a real refetch window means HealthKit now holds
        // nothing in [refetchStart, end] — the samples there were deleted, so
        // dropping them is correct. Points before refetchStart are untouched.
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let keptDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 1)))
        let refetchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        let deletedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 7)))

        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: keptDate, value: 61),
                HealthTrendDataPoint(date: deletedDate, value: 62)
            ]),
            incoming: .empty,
            windowStart: windowStart,
            refetchStart: refetchStart
        )

        XCTAssertEqual(merged.points.map(\.date), [keptDate])
        XCTAssertEqual(merged.points.map(\.value), [61])
    }

    /// A comparison source that resolved to No Comparison (Body Pro lapsed, or the
    /// primary source was changed to match the secondary and collapsed it) fetches an
    /// authoritative EMPTY, which has to clear the cached series. Anchoring the
    /// refetch boundary on the newest cached point instead leaves every point older
    /// than the 48h overlap on the chart, so the comparison line keeps drawing after
    /// it should have vanished. Both halves are asserted: the boundary that works and
    /// the boundary that silently strands the stale points.
    func testDisabledSecondaryClearsCacheOnlyWhenRefetchStartsAtWindowStart() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let staleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 9)))
        let recentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 9)))
        let cached = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: staleDate, value: 58),
            HealthTrendDataPoint(date: recentDate, value: 61)
        ])

        // What the store now does for a disabled comparison: the whole window is
        // authoritative, so the empty result wipes the series.
        let cleared = HealthKitFetchEngine.mergeIntradaySamples(
            existing: cached,
            incoming: .empty,
            windowStart: windowStart,
            refetchStart: windowStart
        )
        XCTAssertTrue(cleared.isEmpty)

        // The incremental boundary — correct for an ENABLED comparison, wrong for a
        // disabled one, because it preserves everything before the overlap.
        let incrementalStart = HealthKitFetchEngine.incrementalFetchStart(after: cached, windowStart: windowStart)
        let stranded = HealthKitFetchEngine.mergeIntradaySamples(
            existing: cached,
            incoming: .empty,
            windowStart: windowStart,
            refetchStart: incrementalStart
        )
        XCTAssertEqual(stranded.points.map(\.date), [staleDate])
    }

    /// Clearing the comparison cache is what makes the next detail-view visit pull a
    /// FULL window rather than incrementally topping up pre-lapse points: an empty
    /// cache has no anchor, so `incrementalFetchStart` falls back to `windowStart`.
    /// This is why the entitlement handler invalidates instead of eagerly refetching
    /// — the lazy path already does the right thing once the cache is genuinely
    /// empty, and a comparison kind is ~50k raw samples to fetch eagerly.
    func testClearedComparisonCacheRefetchesFullWindowOnNextVisit() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let preLapse = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 6)))
        let staleCache = HealthTrendSeries(points: [HealthTrendDataPoint(date: preLapse, value: 57)])

        // Left in place, the pre-lapse points anchor the refetch 48h back and every
        // older point is silently trusted forever.
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: staleCache, windowStart: windowStart),
            preLapse.addingTimeInterval(-HealthKitFetchEngine.incrementalOverlapWindow)
        )
        // Cleared, the next visit re-reads the whole window from HealthKit.
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: .empty, windowStart: windowStart),
            windowStart
        )
    }

    /// The secondary day-sample fetch is now incremental too, so it must land on the
    /// same 48h boundary the primary uses — a comparison cache and a primary cache
    /// with the same newest point refetch the same window.
    func testSecondaryIncrementalFetchStartMatchesPrimary() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let newest = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 6)))
        let series = HealthTrendSeries(points: [HealthTrendDataPoint(date: newest, value: 55)])

        let fetchStart = HealthKitFetchEngine.incrementalFetchStart(after: series, windowStart: windowStart)

        XCTAssertEqual(fetchStart, newest.addingTimeInterval(-HealthKitFetchEngine.incrementalOverlapWindow))
        // An empty comparison cache (first load, or just-cleared after a source
        // switch) still pulls the full window.
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: .empty, windowStart: windowStart),
            windowStart
        )
    }

    /// The Step-2 guard in `refreshHealthMetric` keys off `HealthTrendDaySampleSignatures`,
    /// so a secondary-source switch or a combine-flag flip mid-fetch has to register
    /// as a mismatch — otherwise a mixed-source merge gets published and persisted.
    func testDaySampleSignaturesDifferForSecondaryAndCombineChanges() {
        let base = HealthTrendDaySampleSignatures(
            primarySelectionSignature: "primary-a",
            secondarySelectionSignature: "secondary-a",
            permissionSignature: "perm-a",
            combinesHealthDataSourcesByName: false
        )

        XCTAssertNotEqual(base, HealthTrendDaySampleSignatures(
            primarySelectionSignature: "primary-a",
            secondarySelectionSignature: "secondary-b",
            permissionSignature: "perm-a",
            combinesHealthDataSourcesByName: false
        ))
        XCTAssertNotEqual(base, HealthTrendDaySampleSignatures(
            primarySelectionSignature: "primary-a",
            secondarySelectionSignature: "secondary-a",
            permissionSignature: "perm-a",
            combinesHealthDataSourcesByName: true
        ))
        XCTAssertEqual(base, HealthTrendDaySampleSignatures(
            primarySelectionSignature: "primary-a",
            secondarySelectionSignature: "secondary-a",
            permissionSignature: "perm-a",
            combinesHealthDataSourcesByName: false
        ))
    }

    func testEffortFetchCandidateIDsSkipCachedAndConfirmedWorkouts() {
        let cached = UUID()
        let confirmed = UUID()
        let fresh = UUID()

        let candidates = HealthKitFetchEngine.effortFetchCandidateIDs(
            workoutIDs: [cached, confirmed, fresh],
            cachedEffortIDs: [cached],
            confirmedNoEffortIDs: [confirmed]
        )

        XCTAssertEqual(candidates, [fresh])
    }

    func testConfirmableNoEffortWorkoutIDsRequireAgeAndNoFoundScore() {
        let now = Date()
        let oldUnrated = UUID()
        let recentUnrated = UUID()
        let oldRated = UUID()
        let queried: [(id: UUID, endDate: Date)] = [
            (oldUnrated, now.addingTimeInterval(-49 * 60 * 60)),
            (recentUnrated, now.addingTimeInterval(-2 * 60 * 60)),
            (oldRated, now.addingTimeInterval(-72 * 60 * 60))
        ]

        let confirmed = HealthKitFetchEngine.confirmableNoEffortWorkoutIDs(
            queried: queried,
            foundIDs: [oldRated],
            now: now
        )

        XCTAssertEqual(confirmed, [oldUnrated])
    }

    func testHeartRateReuseEligibilityRequiresMatchingFinishedCachedWorkout() {
        let now = Date()
        let duration: TimeInterval = 3_600
        let finishedStart = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let recentStart = now.addingTimeInterval(-2 * 60 * 60)

        func cachedSummary(id: UUID, startDate: Date, samples: [WorkoutHeartRateSample]) -> WorkoutSummary {
            WorkoutSummary(
                id: id,
                type: .running,
                startDate: startDate,
                duration: duration,
                heartRateSamples: samples
            )
        }

        // Samples covering the workout window edge-to-edge (complete payload) vs
        // a payload cached during a partial Watch sync that misses the opening
        // ramp (first sample 10 minutes in) — the latter must re-fetch.
        let coveringSamples = [
            WorkoutHeartRateSample(date: finishedStart, beatsPerMinute: 140),
            WorkoutHeartRateSample(date: finishedStart.addingTimeInterval(duration), beatsPerMinute: 150)
        ]
        let lateStartSamples = [
            WorkoutHeartRateSample(date: finishedStart.addingTimeInterval(600), beatsPerMinute: 160),
            WorkoutHeartRateSample(date: finishedStart.addingTimeInterval(duration), beatsPerMinute: 150)
        ]
        let eligible = UUID()
        let dateMismatch = UUID()
        let emptySamples = UUID()
        let missingRamp = UUID()
        let tooRecent = UUID()
        let uncached = UUID()

        let workouts: [(id: UUID, startDate: Date, duration: TimeInterval)] = [
            (eligible, finishedStart, duration),
            (dateMismatch, finishedStart, duration),
            (emptySamples, finishedStart, duration),
            (missingRamp, finishedStart, duration),
            (tooRecent, recentStart, duration),
            (uncached, finishedStart, duration)
        ]
        let cachedSummaries: [UUID: WorkoutSummary] = [
            eligible: cachedSummary(id: eligible, startDate: finishedStart, samples: coveringSamples),
            dateMismatch: cachedSummary(id: dateMismatch, startDate: finishedStart.addingTimeInterval(5), samples: coveringSamples),
            emptySamples: cachedSummary(id: emptySamples, startDate: finishedStart, samples: []),
            missingRamp: cachedSummary(id: missingRamp, startDate: finishedStart, samples: lateStartSamples),
            tooRecent: cachedSummary(id: tooRecent, startDate: recentStart, samples: coveringSamples)
        ]

        let eligibleIDs = HealthKitFetchEngine.heartRateReuseEligibleWorkoutIDs(
            workouts: workouts,
            cachedSummaries: cachedSummaries,
            now: now
        )

        XCTAssertEqual(eligibleIDs, [eligible])
    }

    func testDetailMetricReuseRequiresAgedWorkoutWithNonNilCachedField() {
        let now = Date()
        let duration: TimeInterval = 3_600
        let agedStart = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let recentStart = now.addingTimeInterval(-2 * 60 * 60)

        func cachedSummary(id: UUID, startDate: Date, cadence: Double?) -> WorkoutSummary {
            WorkoutSummary(
                id: id,
                type: .running,
                startDate: startDate,
                duration: duration,
                averageStepCadenceSPM: cadence
            )
        }

        let reusable = UUID()
        // Cached before the field existed (or genuinely value-less) — both
        // decode as nil and must be re-queried, never reused.
        let nilField = UUID()
        let dateMismatch = UUID()
        let tooRecent = UUID()
        let uncached = UUID()

        let workouts: [(id: UUID, startDate: Date, duration: TimeInterval)] = [
            (reusable, agedStart, duration),
            (nilField, agedStart, duration),
            (dateMismatch, agedStart, duration),
            (tooRecent, recentStart, duration),
            (uncached, agedStart, duration)
        ]
        let cachedSummaries: [UUID: WorkoutSummary] = [
            reusable: cachedSummary(id: reusable, startDate: agedStart, cadence: 168),
            nilField: cachedSummary(id: nilField, startDate: agedStart, cadence: nil),
            dateMismatch: cachedSummary(id: dateMismatch, startDate: agedStart.addingTimeInterval(5), cadence: 170),
            tooRecent: cachedSummary(id: tooRecent, startDate: recentStart, cadence: 172)
        ]

        let reusableValues = HealthKitFetchEngine.reusableWorkoutDetailMetricValues(
            workouts: workouts,
            cachedSummaries: cachedSummaries,
            now: now,
            cachedValue: \.averageStepCadenceSPM
        )

        XCTAssertEqual(reusableValues, [reusable: 168])
    }

    func testReusingHeartRateSummaryCopiesCachedHeartRateAndTakesFreshMetadata() throws {
        let calendar = Calendar.bodyGregorian
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8)))
        let end = start.addingTimeInterval(1_800)
        let workout = HKWorkout(activityType: .running, start: start, end: end)
        let cached = WorkoutSummary(
            id: workout.uuid,
            type: .cycling,
            startDate: start.addingTimeInterval(-60),
            duration: 999,
            averageHeartRateBeatsPerMinute: 142,
            heartRateSamples: [WorkoutHeartRateSample(date: start, beatsPerMinute: 140)],
            sourceName: "Cached Source"
        )

        let summary = BodyWorkoutFetch.summary(for: workout, reusingHeartRateFrom: cached, effortLevel: 7)

        XCTAssertEqual(summary.id, workout.uuid)
        XCTAssertEqual(summary.type, .running)
        XCTAssertEqual(summary.startDate, start)
        XCTAssertEqual(summary.duration, workout.duration)
        XCTAssertEqual(summary.averageHeartRateBeatsPerMinute, 142)
        XCTAssertEqual(summary.heartRateSamples, cached.heartRateSamples)
        XCTAssertEqual(summary.effortLevel, 7)
    }

    // MARK: - Auto-apply effort eligibility

    func testAutoApplyEligibleWorkoutsRespectsWindowAndExclusions() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hour: TimeInterval = 3600
        func workout(id: UUID = UUID(), endedHoursAgo: Double, effort: Double? = nil) -> WorkoutSummary {
            let start = now.addingTimeInterval(-(endedHoursAgo * hour) - hour)
            return WorkoutSummary(id: id, type: .running, startDate: start, duration: hour, effortLevel: effort)
        }
        let inWindow = workout(endedHoursAgo: 3)            // unrated, 3h old -> eligible
        let tooNew = workout(endedHoursAgo: 0.5)            // 30 min old -> excluded (< 1h)
        let tooOld = workout(endedHoursAgo: 60)             // 60h old -> excluded (> 48h)
        let rated = workout(endedHoursAgo: 3, effort: 6)    // already rated -> excluded
        let overriddenID = UUID(), appliedID = UUID(), skippedID = UUID()
        let overridden = workout(id: overriddenID, endedHoursAgo: 3)
        let applied = workout(id: appliedID, endedHoursAgo: 3)
        let skipped = workout(id: skippedID, endedHoursAgo: 3)

        let result = HealthKitWorkoutStore.autoApplyEligibleWorkouts(
            [tooOld, inWindow, tooNew, rated, overridden, applied, skipped],
            now: now,
            minAge: hour,
            maxAge: 48 * hour,
            overriddenIDs: [overriddenID],
            appliedIDs: [appliedID],
            skippedIDs: [skippedID]
        )
        XCTAssertEqual(result.map(\.id), [inWindow.id])
    }

    func testAutoApplyEligibleWorkoutsIncludesWindowBoundariesNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hour: TimeInterval = 3600
        func workout(endedHoursAgo: Double) -> WorkoutSummary {
            WorkoutSummary(
                type: .running,
                startDate: now.addingTimeInterval(-(endedHoursAgo * hour) - hour),
                duration: hour
            )
        }
        let exactlyOneHour = workout(endedHoursAgo: 1)   // age == minAge -> included (inclusive)
        let middle = workout(endedHoursAgo: 10)
        let exactly48Hours = workout(endedHoursAgo: 48)  // age == maxAge -> included (inclusive)

        let result = HealthKitWorkoutStore.autoApplyEligibleWorkouts(
            [exactly48Hours, exactlyOneHour, middle],
            now: now,
            minAge: hour,
            maxAge: 48 * hour,
            overriddenIDs: [],
            appliedIDs: [],
            skippedIDs: []
        )
        XCTAssertEqual(result.map(\.id), [exactlyOneHour.id, middle.id, exactly48Hours.id])
    }

    // MARK: - Auto-apply effort write loop

    private enum FakeWriteError: Error { case saveFailed }

    /// Scripts the injected write path so `runAutoApplyEffortLoop`'s branch handling can
    /// be exercised without a live HealthKit engine.
    @MainActor
    private final class FakeAutoApplyWriter {
        enum Behavior {
            case outcome(HealthKitFetchEngine.AutoApplyEffortOutcome)
            case failure
        }
        var script: [UUID: Behavior] = [:]
        var authorizedAfterFailure = true
        private(set) var writeCalls: [UUID] = []
        private(set) var authChecks = 0

        func makeWriter() -> HealthKitWorkoutStore.AutoApplyEffortWriter {
            HealthKitWorkoutStore.AutoApplyEffortWriter(
                write: { id, _ in
                    self.writeCalls.append(id)
                    switch self.script[id] {
                    case .outcome(let outcome): return outcome
                    case .failure: throw FakeWriteError.saveFailed
                    case .none: return .unresolved
                    }
                },
                isWriteAuthorized: {
                    self.authChecks += 1
                    return self.authorizedAfterFailure
                }
            )
        }
    }

    @MainActor
    func testAutoApplyLoopRecordsEachWriteOutcomeAndSkipsNilScores() async {
        let written = UUID(), rated = UUID(), unresolved = UUID(), noEstimate = UUID()
        let fake = FakeAutoApplyWriter()
        fake.script = [
            written: .outcome(.written),
            rated: .outcome(.alreadyRated),
            unresolved: .outcome(.unresolved)
        ]
        let candidates = [
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: written, score: 7),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: rated, score: 5),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: unresolved, score: 6),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: noEstimate, score: nil)
        ]

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: fake.makeWriter()
        )

        XCTAssertEqual(result.writtenScores, [written: 7])
        XCTAssertEqual(result.appliedIDs, [written])
        XCTAssertEqual(result.alreadyRatedIDs, [rated])
        XCTAssertFalse(result.writeAuthRevoked)
        // The nil-score candidate is skipped before any write is attempted.
        XCTAssertEqual(fake.writeCalls, [written, rated, unresolved])
    }

    @MainActor
    func testAutoApplyLoopCapCountsWritesSoNoHRSkipsDontStarveOlderWorkouts() async {
        // Newest candidates have no usable estimate (nil score); older ones do. Skips
        // must not consume the write budget, so both HR-eligible workouts still get
        // written under a cap of 2.
        let newestNoHR = UUID(), secondNoHR = UUID(), olderA = UUID(), olderB = UUID()
        let fake = FakeAutoApplyWriter()
        fake.script = [olderA: .outcome(.written), olderB: .outcome(.written)]
        let candidates = [
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: newestNoHR, score: nil),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: secondNoHR, score: nil),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: olderA, score: 8),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: olderB, score: 4)
        ]

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 2,
            writer: fake.makeWriter()
        )

        XCTAssertEqual(result.appliedIDs, [olderA, olderB])
        XCTAssertEqual(fake.writeCalls, [olderA, olderB])
    }

    @MainActor
    func testAutoApplyLoopStopsAtWriteCap() async {
        let first = UUID(), second = UUID(), third = UUID()
        let fake = FakeAutoApplyWriter()
        fake.script = [
            first: .outcome(.written),
            second: .outcome(.written),
            third: .outcome(.written)
        ]
        let candidates = [first, second, third].map {
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: $0, score: 5)
        }

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 2,
            writer: fake.makeWriter()
        )

        XCTAssertEqual(result.appliedIDs.count, 2)
        // The third candidate is never written: the cap check breaks before it.
        XCTAssertEqual(fake.writeCalls, [first, second])
        XCTAssertNil(result.writtenScores[third])
    }

    @MainActor
    func testAutoApplyLoopDisablesToggleWhenWriteAuthRevoked() async {
        let written = UUID(), failed = UUID(), afterFailure = UUID()
        let fake = FakeAutoApplyWriter()
        fake.authorizedAfterFailure = false // access revoked after opt-in
        fake.script = [
            written: .outcome(.written),
            failed: .failure,
            afterFailure: .outcome(.written)
        ]
        let candidates = [written, failed, afterFailure].map {
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: $0, score: 6)
        }

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: fake.makeWriter()
        )

        XCTAssertTrue(result.writeAuthRevoked)
        XCTAssertEqual(result.appliedIDs, [written])
        // The batch stops at the failure; the candidate after it is never attempted.
        XCTAssertEqual(fake.writeCalls, [written, failed])
        XCTAssertEqual(fake.authChecks, 1)
    }

    @MainActor
    func testAutoApplyLoopKeepsToggleOnForTransientWriteFailure() async {
        let written = UUID(), failed = UUID(), afterFailure = UUID()
        let fake = FakeAutoApplyWriter()
        fake.authorizedAfterFailure = true // still authorized -> transient error
        fake.script = [
            written: .outcome(.written),
            failed: .failure,
            afterFailure: .outcome(.written)
        ]
        let candidates = [written, failed, afterFailure].map {
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: $0, score: 6)
        }

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: fake.makeWriter()
        )

        XCTAssertFalse(result.writeAuthRevoked)
        XCTAssertEqual(result.appliedIDs, [written])
        XCTAssertEqual(fake.writeCalls, [written, failed])
        XCTAssertEqual(fake.authChecks, 1)
    }

    // MARK: - Sync-badge success signal

    @MainActor
    func testSyncBadgeSignalAdvancesOnlyForUserVisibleGenuineSuccess() {
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // A lazy month/ring load reaches success WITHOUT `isRefreshing`
        // (advancesSyncBadge defaults false) — it must not move the badge signal.
        store.markRefreshSucceeded(date: Date(), refreshedVitals: false, publishesWatch: false)
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // A user-visible refresh whose queries failed (cached values preserved)
        // is not a genuine fetch — still no advance.
        store.markRefreshSucceeded(
            date: Date(),
            refreshedVitals: true,
            publishesWatch: false,
            hadQueryFailure: true,
            advancesSyncBadge: true
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // A user-visible refresh that genuinely fetched advances the signal.
        store.markRefreshSucceeded(
            date: Date(),
            refreshedVitals: false,
            publishesWatch: false,
            hadQueryFailure: false,
            advancesSyncBadge: true
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 1)
    }

    @MainActor
    func testSyncBadgeSignalDoesNotAdvanceWhenNoQueryRan() {
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // A user-visible pull that dispatched no HealthKit query (a metric or
        // workout month whose permission is disabled, or a readiness recompute)
        // preserved the cached values and must not confirm "Health data updated"
        // — even with `advancesSyncBadge: true` and no query failure.
        store.markRefreshSucceeded(
            date: Date(),
            refreshedVitals: false,
            publishesWatch: false,
            hadQueryFailure: false,
            advancesSyncBadge: true,
            ranQueries: false
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // The same path that actually queried advances the signal.
        store.markRefreshSucceeded(
            date: Date(),
            refreshedVitals: false,
            publishesWatch: false,
            hadQueryFailure: false,
            advancesSyncBadge: true,
            ranQueries: true
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 1)
    }

    // MARK: - Permissions sheet access states

    @MainActor
    private func accessStateStore(
        ringHistory: ActivityRingHistorySnapshot,
        permissionSelection: BodyHealthPermissionSelection = .defaultValue
    ) -> HealthKitWorkoutStore {
        HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 1,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: HealthDashboardSnapshot(
                summary: .empty,
                trends: .empty,
                activityRingHistory: ringHistory
            ),
            initialPermissionSelection: permissionSelection
        )
    }

    private func ringDay(month: Int, day: Int) throws -> ActivityRingDaySummary {
        let date = try XCTUnwrap(
            Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: month, day: day))
        )
        return ActivityRingDaySummary(
            date: date,
            summary: ActivityRingSummary(
                move: ActivityRingMetric(value: 500, goal: 500),
                exercise: ActivityRingMetric(value: 30, goal: 30),
                stand: ActivityRingMetric(value: 12, goal: 12)
            )
        )
    }

    /// Regression: the backfill deliberately retains `loadedMonthKeys` for months
    /// that hold no days. A presence check built on "did filtering change
    /// anything" saw those keys disappear and reported data where there is none.
    /// Asking the snapshot's own `isEmpty` counts days, which is the real question.
    @MainActor
    func testCoveredButEmptyRingMonthsReportNoDataRatherThanData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(
            ringHistory: ActivityRingHistorySnapshot(
                days: [],
                loadedMonthKeys: [
                    ActivityRingMonthKey(month: 1, year: 2026),
                    ActivityRingMonthKey(month: 2, year: 2026)
                ]
            )
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)
        XCTAssertEqual(states[.activityRings], .noData)
    }

    @MainActor
    func testRingDaysReportHasData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(
            ringHistory: ActivityRingHistorySnapshot(
                days: [try ringDay(month: 1, day: 5)],
                loadedMonthKeys: [ActivityRingMonthKey(month: 1, year: 2026)]
            )
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)
        XCTAssertEqual(states[.activityRings], .hasData)
    }

    /// Regression: `BodyDashboardFetchSelection` is built from the Home-card
    /// layout, not from permissions, and a metric it excludes is never queried at
    /// all. Hiding a card must not be reported as Apple Health withholding data.
    @MainActor
    func testHiddenDashboardCardsReportNotUsedByDashboardRatherThanNoData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(ringHistory: .empty)
        let noCards = BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: []),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [])
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: noCards)
        XCTAssertEqual(states[.activityRings], .notUsedByDashboard)
        XCTAssertEqual(states[.heart], .notUsedByDashboard)
        XCTAssertEqual(states[.steps], .notUsedByDashboard)
    }

    /// A switch the user turned off must never be reported as missing data, even
    /// while the cache still holds values read before the opt out.
    @MainActor
    func testDisabledPermissionReportsOffEvenWithCachedData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(
            ringHistory: ActivityRingHistorySnapshot(days: [try ringDay(month: 1, day: 5)]),
            permissionSelection: BodyHealthPermissionSelection(
                enabledPermissions: Set(BodyHealthPermission.allCases).subtracting([.activityRings])
            )
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)
        XCTAssertEqual(states[.activityRings], .off)
    }

    /// Opening the Permissions sheet must be free: it reads published state only,
    /// so it can never kick off a HealthKit read or disturb refresh bookkeeping.
    @MainActor
    func testAccessStatesReadPublishedStateWithoutStartingWork() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(ringHistory: .empty)
        let refreshDateBefore = store.lastSuccessfulRefreshDate

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)

        XCTAssertEqual(states.count, BodyHealthPermission.allCases.count)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshDateBefore)
    }

    /// Regression: readiness is derived, deliberately survives every permission
    /// filter, and is counted by both `isEmpty`s — so one cached readiness score
    /// made every category read "Body has data" even when that category was
    /// empty. The presence probe must strip readiness before asking.
    @MainActor
    func testCachedReadinessAloneDoesNotMakeCategoriesReportData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        var summary = HealthSummarySnapshot.empty
        summary.readiness.score = 80
        var trends = HealthTrendSnapshot.empty
        trends.recordedReadiness = [
            RecordedReadinessEntry(date: Date(timeIntervalSince1970: 1_770_000_000), score: 80)
        ]

        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 1,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: HealthDashboardSnapshot(
                summary: summary,
                trends: trends,
                activityRingHistory: .empty
            )
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)
        XCTAssertEqual(states[.bloodOxygen], .noData)
        XCTAssertEqual(states[.activityRings], .noData)
        XCTAssertEqual(states[.heart], .noData)
        XCTAssertEqual(states[.sleep], .noData)
    }

    /// Stress-only layout, Heart on: sleep and HRV are fetched by the dashboard
    /// refresh itself (`.inputCapable`), and with Heart enabled the heart-gated
    /// Stress input loader also queries heart rate/steps/active energy — so all
    /// three report as used by the dashboard, not `.notUsedByDashboard`.
    @MainActor
    func testStressOnlyLayoutWithHeartOnMarksInputDependenciesDashboardUsed() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(ringHistory: .empty)
        let stressOnly = BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: [.stress]),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [])
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: stressOnly)

        XCTAssertNotEqual(states[.heart], .notUsedByDashboard)
        XCTAssertNotEqual(states[.steps], .notUsedByDashboard)
        XCTAssertNotEqual(states[.energy], .notUsedByDashboard)
    }

    /// Stress-only layout, Heart off: the Stress input loader is heart-gated
    /// (`startStressInputLoadIfNeeded`), so with Heart off it never queries
    /// steps/energy — they must report `.notUsedByDashboard`, not a false
    /// "no data". Sleep is unaffected: it's one of the engine's own
    /// `.inputCapable` leaves, refresh-fetched regardless of Heart.
    @MainActor
    func testStressOnlyLayoutWithHeartOffLeavesStepsAndEnergyNotDashboardUsed() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(
            ringHistory: .empty,
            permissionSelection: BodyHealthPermissionSelection(
                enabledPermissions: Set(BodyHealthPermission.allCases).subtracting([.heart])
            )
        )
        let stressOnly = BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: [.stress]),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [])
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: stressOnly)

        XCTAssertEqual(states[.steps], .notUsedByDashboard)
        XCTAssertEqual(states[.energy], .notUsedByDashboard)
        XCTAssertNotEqual(states[.sleep], .notUsedByDashboard)
    }

    /// Every row must resolve to something. A missing entry would render a row
    /// with no footer at all, which reads as a layout bug rather than a state.
    @MainActor
    func testEveryPermissionResolvesToAState() throws {
        let store = accessStateStore(ringHistory: .empty)
        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)

        for permission in BodyHealthPermission.allCases {
            XCTAssertNotNil(states[permission], "\(permission) has no access state")
        }
    }
}
