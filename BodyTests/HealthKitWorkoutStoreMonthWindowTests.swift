//
//  HealthKitWorkoutStoreMonthWindowTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

final class HealthKitWorkoutStoreMonthWindowTests: XCTestCase {

    @MainActor
    func testWorkoutStoreKeepsRecentChartWindowToThreeMonths() {
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        )
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [initialSnapshot])

        XCTAssertEqual(HealthKitWorkoutStore.recentChartMonthCount, 3)
        XCTAssertEqual(store.snapshot(month: 5, year: 2026), initialSnapshot)

        let unloadedSnapshot = store.snapshot(month: 4, year: 2026)
        XCTAssertEqual(unloadedSnapshot.month, 4)
        XCTAssertEqual(unloadedSnapshot.year, 2026)
        XCTAssertEqual(unloadedSnapshot.workoutCount, 0)
        XCTAssertFalse(store.hasLoadedSnapshot(month: 4, year: 2026))
    }

    @MainActor
    func testWorkoutStoreRepairsCachedBoundaryTruncatedActivityRingHistory() throws {
        let calendar = Calendar.bodyGregorian
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)
        let january1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let february1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let march2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)))
        let march3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3)))
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let corruptedHistory = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: january1, summary: summary),
                ActivityRingDaySummary(date: february1, summary: summary),
                ActivityRingDaySummary(date: march2, summary: summary),
                ActivityRingDaySummary(date: march3, summary: summary)
            ],
            loadedMonthKeys: [januaryKey, februaryKey, marchKey]
        )
        let dashboardSnapshot = HealthDashboardSnapshot(
            summary: .empty,
            trends: .empty,
            activityRingHistory: corruptedHistory
        )
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 4,
            year: 2026,
            workouts: [],
            calendar: calendar
        )

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [initialSnapshot],
            initialHealthDashboardSnapshot: dashboardSnapshot,
            date: currentDate
        )

        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [march2, march3])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [marchKey])
    }

    func testActivityRingHistoryRemovesLoadedMonthsOlderThanEarliestDataKeepingGapMonths() throws {
        let calendar = Calendar.bodyGregorian
        let january5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)))
        let march8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let history = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: january5, summary: summary),
                ActivityRingDaySummary(date: march8, summary: summary)
            ],
            loadedMonthKeys: [
                ActivityRingMonthKey(month: 11, year: 2025),
                ActivityRingMonthKey(month: 12, year: 2025),
                ActivityRingMonthKey(month: 1, year: 2026),
                ActivityRingMonthKey(month: 2, year: 2026),
                ActivityRingMonthKey(month: 3, year: 2026)
            ]
        )

        let repaired = history.removingLoadedMonthsOlderThanEarliestData(date: currentDate, calendar: calendar)

        XCTAssertEqual(repaired.days, history.days)
        XCTAssertEqual(repaired.loadedMonthKeys, [
            ActivityRingMonthKey(month: 1, year: 2026),
            ActivityRingMonthKey(month: 2, year: 2026),
            ActivityRingMonthKey(month: 3, year: 2026)
        ])
    }

    func testActivityRingHistoryRemovingOlderLoadedMonthsKeepsRecentWindowWhenNoData() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let history = ActivityRingHistorySnapshot(
            days: [],
            loadedMonthKeys: [
                ActivityRingMonthKey(month: 1, year: 2026),
                ActivityRingMonthKey(month: 4, year: 2026),
                ActivityRingMonthKey(month: 6, year: 2026)
            ]
        )

        let repaired = history.removingLoadedMonthsOlderThanEarliestData(
            date: currentDate,
            calendar: calendar,
            keepingRecentMonthCount: 3
        )

        XCTAssertEqual(repaired.loadedMonthKeys, [
            ActivityRingMonthKey(month: 4, year: 2026),
            ActivityRingMonthKey(month: 6, year: 2026)
        ])
    }

    func testPreviousActivityRingMonthCandidatesWalksBackFromEarliestKnownKey() throws {
        let calendar = Calendar.bodyGregorian

        let candidates = HealthKitWorkoutStore.previousActivityRingMonthCandidates(
            loadedKeys: [
                ActivityRingMonthKey(month: 5, year: 2026),
                ActivityRingMonthKey(month: 4, year: 2026)
            ],
            exhaustedKeys: [ActivityRingMonthKey(month: 3, year: 2026)],
            limit: 3,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [
            ActivityRingMonthKey(month: 2, year: 2026),
            ActivityRingMonthKey(month: 1, year: 2026),
            ActivityRingMonthKey(month: 12, year: 2025)
        ])
    }

    func testPreviousActivityRingMonthCandidatesSeedsFromDateWhenNothingIsKnown() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))

        let candidates = HealthKitWorkoutStore.previousActivityRingMonthCandidates(
            loadedKeys: [],
            exhaustedKeys: [],
            limit: 2,
            date: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [
            ActivityRingMonthKey(month: 5, year: 2026),
            ActivityRingMonthKey(month: 4, year: 2026)
        ])
    }

    func testActivityRingMonthKeysBetweenReturnsExclusiveRangeOldestFirst() {
        let calendar = Calendar.bodyGregorian

        let keys = HealthKitWorkoutStore.activityRingMonthKeys(
            after: ActivityRingMonthKey(month: 11, year: 2025),
            before: ActivityRingMonthKey(month: 3, year: 2026),
            calendar: calendar
        )

        XCTAssertEqual(keys, [
            ActivityRingMonthKey(month: 12, year: 2025),
            ActivityRingMonthKey(month: 1, year: 2026),
            ActivityRingMonthKey(month: 2, year: 2026)
        ])
    }

    func testActivityRingMonthKeysBetweenAdjacentOrInvertedMonthsIsEmpty() {
        let calendar = Calendar.bodyGregorian

        XCTAssertTrue(HealthKitWorkoutStore.activityRingMonthKeys(
            after: ActivityRingMonthKey(month: 4, year: 2026),
            before: ActivityRingMonthKey(month: 5, year: 2026),
            calendar: calendar
        ).isEmpty)

        XCTAssertTrue(HealthKitWorkoutStore.activityRingMonthKeys(
            after: ActivityRingMonthKey(month: 5, year: 2026),
            before: ActivityRingMonthKey(month: 1, year: 2026),
            calendar: calendar
        ).isEmpty)
    }

    func testActivityRingBackfillStartDateSpansTenYearsAndClampsToWatchEra() throws {
        let calendar = Calendar.bodyGregorian

        let recentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: recentDate, calendar: calendar),
            calendar.date(from: DateComponents(year: 2016, month: 6, day: 1))
        )

        let earlyDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2020, month: 1, day: 15)))
        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: earlyDate, calendar: calendar),
            calendar.date(from: DateComponents(year: 2014, month: 9, day: 1))
        )
    }

    /// A backfill walk may never claim a month newer than its own `walkEnd`.
    ///
    /// This one property is what all three shipped instances of this bug
    /// violated: a chunk claiming months out to the walk end instead of its own
    /// window, a resume re-claiming the checkpoint month, and an empty resumed
    /// walk claiming the RECENT months it never scanned. Each was a hand
    /// computed month set that reached past what was actually read, and because
    /// `replacingLoadedMonths` REPLACES every claimed month, each one deleted
    /// days that were already on disk.
    ///
    /// Asserted over every branch of the key computation rather than over one
    /// scenario, so a fourth instance fails here instead of being found by a
    /// user missing days from their calendar.
    func testBackfillNeverClaimsMonthsNewerThanTheWalkItPerformed() throws {
        let calendar = Calendar.bodyGregorian
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23)))
        let resumeFrom = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let scannedStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 5, day: 1)))
        let dayWithData = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 9)))

        let freshEnd = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(
                date: today, resumeFrom: nil, calendar: calendar
            )
        )
        let resumedEnd = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(
                date: today, resumeFrom: resumeFrom, calendar: calendar
            )
        )

        let cases: [(name: String, earliest: Date?, scanned: Date?, resume: Date?, walkEnd: Date)] = [
            ("fresh walk with data", dayWithData, scannedStart, nil, freshEnd),
            ("fresh walk with no data anywhere", nil, scannedStart, nil, freshEnd),
            ("fresh walk that landed nothing", nil, nil, nil, freshEnd),
            ("resumed walk with data", dayWithData, scannedStart, resumeFrom, resumedEnd),
            ("resumed walk that found no days", nil, scannedStart, resumeFrom, resumedEnd),
            ("resumed walk that landed nothing", nil, nil, resumeFrom, resumedEnd)
        ]

        for scenario in cases {
            let keys = HealthKitFetchEngine.activityRingBackfillLoadedMonthKeys(
                earliestDayWithData: scenario.earliest,
                oldestScannedStart: scenario.scanned,
                walkEnd: scenario.walkEnd,
                resumeFrom: scenario.resume,
                date: today,
                calendar: calendar
            )
            let endKey = ActivityRingMonthKey(date: scenario.walkEnd, calendar: calendar)
            let overreaching = keys.filter { ($0.year, $0.month) > (endKey.year, endKey.month) }
            XCTAssertTrue(
                overreaching.isEmpty,
                "\(scenario.name): claims \(overreaching.map { "\($0.year)-\($0.month)" }) newer than its walk end \(endKey.year)-\(endKey.month), so applying it would delete days it never read"
            )
        }
    }

    /// Walks the real backfill chunk boundaries and asserts no month is ever
    /// claimed by two chunks, and that together they cover the whole span.
    ///
    /// This is the invariant that makes a whole class of silent data loss
    /// unreachable. A landed chunk marks whole months as loaded, and
    /// `replacingLoadedMonths` REPLACES the days of every month an incoming
    /// chunk claims — so if two chunks ever shared a month, the older one
    /// would wipe days the newer one had already published, producing a
    /// plausible-looking calendar that is quietly missing data. An earlier cut
    /// of the chunk walk did exactly that. Month alignment is the only thing
    /// keeping the windows disjoint, so pin it here rather than trusting it.
    func testActivityRingBackfillChunksNeverShareAMonth() throws {
        let calendar = Calendar.bodyGregorian
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23)))
        let historyStart = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: end, calendar: calendar)
        )

        var monthsByChunk: [Set<ActivityRingMonthKey>] = []
        var chunkEnd = end
        // Bounded well above the ten year span so a non-terminating walk fails
        // here instead of hanging the suite.
        for _ in 0..<240 {
            let chunkStart = HealthKitFetchEngine.activityRingBackfillChunkStart(
                endingAt: chunkEnd,
                notBefore: historyStart,
                calendar: calendar
            )
            monthsByChunk.append(
                Set(HealthKitFetchEngine.activityRingMonthKeySpan(from: chunkStart, to: chunkEnd, calendar: calendar))
            )

            guard chunkStart > historyStart else {
                break
            }
            chunkEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: chunkStart))
        }

        XCTAssertGreaterThan(monthsByChunk.count, 1, "The ten year span must take more than one chunk")

        var seen: Set<ActivityRingMonthKey> = []
        for (index, months) in monthsByChunk.enumerated() {
            let overlap = seen.intersection(months)
            XCTAssertTrue(
                overlap.isEmpty,
                "Chunk \(index) re-claims month(s) \(overlap.sorted { ($0.year, $0.month) < ($1.year, $1.month) }) already loaded by an earlier chunk, so applying it would wipe days that chunk published"
            )
            seen.formUnion(months)
        }

        // Disjoint is only half the contract: the chunks must also leave no gap.
        XCTAssertEqual(
            seen,
            Set(HealthKitFetchEngine.activityRingMonthKeySpan(from: historyStart, to: end, calendar: calendar)),
            "The chunk walk must cover every month from the history start through today"
        )
    }

    func testActivityRingDaysClampDropsBoundaryDaysOutsideTheChunkWindow() throws {
        let calendar = Calendar.bodyGregorian
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        // A month aligned chunk, exactly what `activityRingBackfillChunkStart`
        // produces: February 1 through April 30.
        let chunkStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let chunkEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        let dayBefore = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)))
        let dayAfter = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let inWindow = try [
            DateComponents(year: 2026, month: 2, day: 1),
            DateComponents(year: 2026, month: 3, day: 14),
            DateComponents(year: 2026, month: 4, day: 30)
        ].map { try XCTUnwrap(calendar.date(from: $0)) }

        let fetched = ([dayBefore] + inWindow + [dayAfter]).map {
            ActivityRingDaySummary(date: $0, summary: summary)
        }
        let clamped = HealthKitFetchEngine.activityRingDays(
            fetched,
            from: chunkStart,
            through: chunkEnd,
            calendar: calendar
        )

        XCTAssertEqual(
            clamped.map(\.date),
            inWindow,
            "A components-predicated ring query can return boundary days outside the requested window; they must not enter the chunk"
        )

        // The claimed month span is derived from the oldest day, so an unclamped
        // boundary day is what lets a chunk claim a neighbouring chunk's month —
        // and `replacingLoadedMonths` REPLACES those months rather than merging.
        let clampedMonths = try HealthKitFetchEngine.activityRingMonthKeySpan(
            from: XCTUnwrap(clamped.first).date,
            to: chunkEnd,
            calendar: calendar
        )
        XCTAssertEqual(
            Set(clampedMonths),
            Set(HealthKitFetchEngine.activityRingMonthKeySpan(from: chunkStart, to: chunkEnd, calendar: calendar)),
            "The clamped chunk must claim exactly the months its own window covers"
        )
        XCTAssertFalse(
            clampedMonths.contains(ActivityRingMonthKey(month: 1, year: 2026)),
            "A January boundary day must not make a February chunk claim — and so wipe — January"
        )

        let unclampedMonths = HealthKitFetchEngine.activityRingMonthKeySpan(
            from: dayBefore,
            to: chunkEnd,
            calendar: calendar
        )
        XCTAssertTrue(
            unclampedMonths.contains(ActivityRingMonthKey(month: 1, year: 2026)),
            "Guard that the unclamped span really would have reached the neighbouring month"
        )
    }

    func testActivityRingDaysClampLeavesDaysAlreadyInsideTheWindowUnchanged() throws {
        let calendar = Calendar.bodyGregorian
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let chunkStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let chunkEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        // A mid-day timestamp still belongs to its day: the window is compared
        // at day granularity, not instant granularity.
        let days = try [
            DateComponents(year: 2026, month: 2, day: 1, hour: 23, minute: 59),
            DateComponents(year: 2026, month: 3, day: 14),
            DateComponents(year: 2026, month: 4, day: 30, hour: 13)
        ].map { ActivityRingDaySummary(date: try XCTUnwrap(calendar.date(from: $0)), summary: summary) }

        XCTAssertEqual(
            HealthKitFetchEngine.activityRingDays(
                days,
                from: chunkStart,
                through: chunkEnd,
                calendar: calendar
            ),
            days,
            "Clamping must be a no-op when every fetched day already falls inside the requested window"
        )
    }

    func testActivityRingMonthKeySpanIsInclusiveOnBothEnds() throws {
        let calendar = Calendar.bodyGregorian
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 11, day: 20)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 3)))

        XCTAssertEqual(
            HealthKitFetchEngine.activityRingMonthKeySpan(from: start, to: end, calendar: calendar),
            [
                ActivityRingMonthKey(month: 11, year: 2024),
                ActivityRingMonthKey(month: 12, year: 2024),
                ActivityRingMonthKey(month: 1, year: 2025),
                ActivityRingMonthKey(month: 2, year: 2025)
            ]
        )

        XCTAssertEqual(
            HealthKitFetchEngine.activityRingMonthKeySpan(from: end, to: end, calendar: calendar),
            [ActivityRingMonthKey(month: 2, year: 2025)]
        )

        XCTAssertTrue(HealthKitFetchEngine.activityRingMonthKeySpan(from: end, to: start, calendar: calendar).isEmpty)
    }

    func testActivityRingBackfillCompletesOnlyWhenTheWalkReachesHistoryStart() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let checkpoint = Date(timeIntervalSince1970: 1_700_000_000)

        // A partial chunk that carried days is NOT a finished ten-year history:
        // it keeps the walk pending, at the checkpoint it got to.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .pending(resumeFrom: nil),
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: checkpoint,
                foundDays: true,
                now: now
            ),
            .pending(resumeFrom: checkpoint)
        )

        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .pending(resumeFrom: checkpoint),
                authorizationDenied: false,
                reachedHistoryStart: true,
                nextChunkEndDate: nil,
                foundDays: true,
                now: now
            ),
            .completed
        )

        // A failed walk reports no new checkpoint; the old one stands so the
        // retry doesn't start over at today.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .pending(resumeFrom: checkpoint),
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: false,
                now: now
            ),
            .pending(resumeFrom: checkpoint)
        )

        // A finished backfill's recent-window reads don't un-finish it.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .completed,
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: true,
                now: now
            ),
            .completed
        )
    }

    func testDeniedActivityRingReadSuppressesBackfillUntilAReadFindsDaysAgain() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let checkpoint = Date(timeIntervalSince1970: 1_700_000_000)

        // Denial parks the heavy scan instead of clearing the marker, which used
        // to re-issue the whole ten-year query on every single refresh.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .pending(resumeFrom: checkpoint),
                authorizationDenied: true,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: false,
                now: now
            ),
            .suppressed(lastProbe: now)
        )

        // A cheap probe that still finds nothing leaves it parked…
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .suppressed(lastProbe: now),
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: false,
                now: now
            ),
            .suppressed(lastProbe: now)
        )

        // …and one that comes back with days re-arms it.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .suppressed(lastProbe: now),
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: true,
                now: now
            ),
            .pending(resumeFrom: nil)
        )
    }

    /// Ring history now arrives in chunks AFTER the refresh has finished, so the
    /// chunks have to accumulate: a later, older chunk merges underneath the
    /// months already on screen instead of replacing them.
    @MainActor
    func testActivityRingHistoryChunksAccumulateThroughTheApplyFunnel() throws {
        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let january7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 7)))
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)

        XCTAssertTrue(
            store.applyActivityRingHistoryChunk(
                activityRingChunk(days: [march5], loadedMonthKeys: [marchKey]),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [marchKey])
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 1)

        // The newest-first walk hands back the older span second.
        XCTAssertTrue(
            store.applyActivityRingHistoryChunk(
                activityRingChunk(days: [january7], loadedMonthKeys: [januaryKey, februaryKey]),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [january7, march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [januaryKey, februaryKey, marchKey])
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 3)
    }

    @MainActor
    func testActivityRingHistoryChunkFromBeforeAClearCacheIsDropped() async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)
        let chunk = activityRingChunk(days: [march5], loadedMonthKeys: [marchKey])

        XCTAssertTrue(store.applyActivityRingHistoryChunk(chunk, capturedEpoch: 0))

        // The walk was requested under the pre-wipe epoch, so its next chunk
        // must not resurrect the history the wipe just dropped.
        await store.clearLocalCache()
        XCTAssertFalse(store.applyActivityRingHistoryChunk(chunk, capturedEpoch: 0))
        XCTAssertTrue(store.activityRingHistory.days.isEmpty)
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 0)
    }

    /// The ten-year walk runs for minutes, so every chunk has to be on screen
    /// AND on disk the moment it lands — not accumulated and applied once at the
    /// end, which is what made the calendar appear in a single step.
    @MainActor
    func testActivityRingBackfillChunksLandAndCheckpointAsTheyArrive() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = emptyHealthDataStore()
        let january20 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 20)))
        let february10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let februaryStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let marchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)

        // Chunk one: the newest month is on screen and checkpointed while the
        // rest of the walk is still querying.
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [march5],
                    loadedMonthKeys: [marchKey],
                    nextChunkEndDate: marchStart
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [marchKey])
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: marchStart)
        )

        // Chunk two merges underneath it and moves the checkpoint back with it.
        // It claims only the months its own window covered, so the merge cannot
        // replace the month chunk one already published.
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [february10],
                    loadedMonthKeys: [februaryKey],
                    nextChunkEndDate: februaryStart
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [february10, march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [februaryKey, marchKey])
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: februaryStart)
        )

        // The chunk that reached history start carries no checkpoint of its own:
        // whether the walk `completed` is the terminal state's call, so this
        // must not rewrite the resume point to something bogus.
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [january20],
                    loadedMonthKeys: [januaryKey],
                    nextChunkEndDate: nil
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [january20, february10, march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [januaryKey, februaryKey, marchKey])
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 3)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: februaryStart)
        )
    }

    /// A walk killed part way through (quit, cancellation) keeps what landed and
    /// resumes at that chunk's boundary. Applying only at the end threw every
    /// landed month away and restarted the whole scan at today.
    @MainActor
    func testInterruptedActivityRingBackfillKeepsLandedChunksAndResumesFromTheirBoundary() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = emptyHealthDataStore()
        let february10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let februaryStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let marchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)

        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [march5],
                    loadedMonthKeys: [marchKey],
                    nextChunkEndDate: marchStart
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [february10],
                    loadedMonthKeys: [februaryKey],
                    nextChunkEndDate: februaryStart
                ),
                capturedEpoch: 0
            )
        )

        // …and the walk dies here, with older chunks still unqueried.
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [february10, march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [februaryKey, marchKey])
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: februaryStart)
        )
        XCTAssertNotEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: nil)
        )
    }

    /// The refusal that stops the walk: once a Clear Cache has bumped the epoch,
    /// the chunk is dropped and the checkpoint stays at the wiped state rather
    /// than being pushed back to a resume point for history that no longer
    /// exists.
    @MainActor
    func testActivityRingBackfillChunkFromBeforeAClearCacheStopsTheWalk() async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = emptyHealthDataStore()
        let february10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let februaryStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let marchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)

        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [march5],
                    loadedMonthKeys: [marchKey],
                    nextChunkEndDate: marchStart
                ),
                capturedEpoch: 0
            )
        )

        await store.clearLocalCache()

        XCTAssertFalse(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [february10],
                    loadedMonthKeys: [februaryKey],
                    nextChunkEndDate: februaryStart
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertTrue(store.activityRingHistory.days.isEmpty)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: nil)
        )
    }

    /// A backfill checkpoint is EXCLUSIVE, so the resumed walk starts one day
    /// older and never re-claims the checkpoint's month. `replacingLoadedMonths`
    /// REPLACES every month an incoming chunk claims, so a resumed chunk that
    /// claimed August while carrying only August 1 would delete August 2 to 31
    /// from the cache.
    @MainActor
    func testResumedBackfillWalkStartsOlderThanTheCheckpointAndKeepsItsMonth() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let augustKey = ActivityRingMonthKey(month: 8, year: 2025)
        let julyKey = ActivityRingMonthKey(month: 7, year: 2025)
        let augustDays = try (1...31).map { day in
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 8, day: day)))
        }
        // What the engine hands back for a chunk covering August: month aligned,
        // checkpointed at its own `chunkStart`.
        let checkpoint = try XCTUnwrap(augustDays.first)

        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: augustDays,
                    loadedMonthKeys: [augustKey],
                    nextChunkEndDate: checkpoint
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.count, 31)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: checkpoint)
        )

        // The resumption converts that exclusive checkpoint to July 31…
        let resumedWalkEnd = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(
                date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 9, day: 15))),
                resumeFrom: checkpoint,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            resumedWalkEnd,
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 31)))
        )

        // …so the chunk it produces claims July, not August, and August survives.
        let july20 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 20)))
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [july20],
                    loadedMonthKeys: [julyKey],
                    nextChunkEndDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 1)))
                ),
                capturedEpoch: 0
            )
        )

        let survivingAugustDays = store.activityRingHistory.days
            .filter { ActivityRingMonthKey(date: $0.date, calendar: calendar) == augustKey }
        XCTAssertEqual(survivingAugustDays.map(\.date), augustDays)
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [julyKey, augustKey])
    }

    /// A resumed walk that scans OLDER history and correctly finds nothing
    /// there must claim only the stretch it scanned. The recent-window fallback
    /// is for an account with no ring data anywhere; firing it here would claim
    /// months this walk never looked at, and `replacingLoadedMonths` REPLACES
    /// every claimed month — deleting the recent days the interrupted first run
    /// had already saved.
    @MainActor
    func testResumedBackfillFindingNoDaysKeepsTheRecentMonthsAlreadySaved() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let now = Date()
        // What the interrupted first run saved: the newest chunk, checkpointed
        // at its own month-aligned start.
        let recentDay = calendar.startOfDay(for: now)
        let recentKey = ActivityRingMonthKey(date: recentDay, calendar: calendar)
        let checkpoint = try XCTUnwrap(calendar.dateInterval(of: .month, for: recentDay)?.start)

        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [recentDay],
                    loadedMonthKeys: [recentKey],
                    nextChunkEndDate: checkpoint
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [recentDay])

        // The resumed walk reads older history and lands chunks that hold no
        // ring days at all.
        let walkEnd = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(date: now, resumeFrom: checkpoint, calendar: calendar)
        )
        let historyStart = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: now, calendar: calendar)
        )
        let scannedStart = HealthKitFetchEngine.activityRingBackfillChunkStart(
            endingAt: walkEnd,
            notBefore: historyStart,
            calendar: calendar
        )
        let emptyWalkKeys = HealthKitFetchEngine.activityRingBackfillLoadedMonthKeys(
            earliestDayWithData: nil,
            oldestScannedStart: scannedStart,
            walkEnd: walkEnd,
            resumeFrom: checkpoint,
            date: now,
            calendar: calendar
        )

        // The recent-window fallback — what this used to resolve to — always
        // names the current month, so landing it would have replaced the month
        // holding `recentDay` with nothing.
        XCTAssertTrue(
            HealthKitFetchEngine.recentActivityRingMonthKeys(
                count: HealthKitWorkoutStore.recentChartMonthCount,
                from: now,
                calendar: calendar
            ).contains(recentKey)
        )
        XCTAssertFalse(emptyWalkKeys.contains(recentKey))
        XCTAssertTrue(
            store.applyActivityRingHistoryChunk(
                ActivityRingHistorySnapshot(days: [], loadedMonthKeys: emptyWalkKeys),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [recentDay])
        XCTAssertTrue(store.activityRingHistory.loadedMonthKeys.contains(recentKey))
    }

    /// The same terminal decision on a FRESH walk still claims the recent
    /// window, so an account with no ring data anywhere renders empty grids.
    func testFreshBackfillFindingNoDaysStillClaimsTheRecentWindow() throws {
        let calendar = Calendar.bodyGregorian
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let historyStart = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: now, calendar: calendar)
        )

        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillLoadedMonthKeys(
                earliestDayWithData: nil,
                oldestScannedStart: HealthKitFetchEngine.activityRingBackfillChunkStart(
                    endingAt: now,
                    notBefore: historyStart,
                    calendar: calendar
                ),
                walkEnd: now,
                resumeFrom: nil,
                date: now,
                calendar: calendar
            ),
            HealthKitFetchEngine.recentActivityRingMonthKeys(
                count: HealthKitWorkoutStore.recentChartMonthCount,
                from: now,
                calendar: calendar
            )
        )
    }

    func testBackfillWalkEndResumesAtTodayWhenNoChunkEverLanded() throws {
        let calendar = Calendar.bodyGregorian
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))

        // A fresh walk starts at today.
        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(date: today, resumeFrom: nil, calendar: calendar),
            today
        )

        // A walk that landed nothing checkpoints at `end + 1 day`, so the same
        // exclusive conversion resumes at today rather than skipping a day.
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(date: today, resumeFrom: tomorrow, calendar: calendar),
            today
        )
    }

    /// Switching Activity Rings off purges the cached history and the backfill
    /// progress, but the walk can already have a chunk in flight — cancellation
    /// cannot catch that one, so it is refused at the point of application.
    @MainActor
    func testActivityRingChunkIsRefusedAfterRingsAreSwitchedOff() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [WorkoutMonthSnapshot.make(
                month: 5,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            )],
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: [.steps])
        )
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let march1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))

        XCTAssertFalse(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [march5],
                    loadedMonthKeys: [ActivityRingMonthKey(month: 3, year: 2026)],
                    nextChunkEndDate: march1
                ),
                capturedEpoch: 0
            )
        )

        XCTAssertTrue(store.activityRingHistory.days.isEmpty)
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 0)
        // And the refused chunk must not push the reset progress back to a
        // checkpoint the user has opted out of.
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: nil)
        )
    }

    @MainActor
    func testWorkoutStoreInitStripsStaleLoadedMonthsOlderThanEarliestData() throws {
        let calendar = Calendar.bodyGregorian
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)
        let march2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)))
        let march3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3)))
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let pollutedHistory = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: march2, summary: summary),
                ActivityRingDaySummary(date: march3, summary: summary)
            ],
            loadedMonthKeys: [
                ActivityRingMonthKey(month: 1, year: 2024),
                ActivityRingMonthKey(month: 2, year: 2024),
                marchKey
            ]
        )
        let dashboardSnapshot = HealthDashboardSnapshot(
            summary: .empty,
            trends: .empty,
            activityRingHistory: pollutedHistory
        )
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 4,
            year: 2026,
            workouts: [],
            calendar: calendar
        )

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [initialSnapshot],
            initialHealthDashboardSnapshot: dashboardSnapshot,
            date: currentDate
        )

        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [march2, march3])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [marchKey])
    }

    func testEvictableMonthKeysDropOldestUnprotectedBeyondCap() {
        let keys = (1...6).map { BodyWorkoutMonthKey(month: $0, year: 2026) }

        let evicted = HealthKitWorkoutStore.evictableMonthKeys(
            loadOrder: keys,
            maximumCount: 4,
            protectedKeys: [keys[0]]
        )

        XCTAssertEqual(evicted, [keys[1], keys[2]])
        XCTAssertTrue(
            HealthKitWorkoutStore.evictableMonthKeys(
                loadOrder: keys,
                maximumCount: 6,
                protectedKeys: []
            ).isEmpty
        )
    }

    /// Pull-to-refresh drops the displayed months plus the unconfirmable trailing
    /// window, and keeps the aged rest of the training-load window.
    func testScopedEffortClearCoversDisplayedMonthsAndTheTrailingWindow() {
        let calendar = Calendar.bodyGregorian
        let now = calendar.date(from: DateComponents(year: 2025, month: 6, day: 20, hour: 12))!
        let displayedMonth = UUID()
        let recent = UUID()
        let aged = UUID()

        func range(_ start: Date) -> WorkoutEffortDateRange {
            WorkoutEffortDateRange(startDate: start, endDate: start.addingTimeInterval(3_600))
        }

        let cleared = HealthKitFetchEngine.effortIDsClearedByScopedRefresh(
            dates: [
                displayedMonth: range(calendar.date(from: DateComponents(year: 2025, month: 5, day: 2))!),
                recent: range(now.addingTimeInterval(-3 * 60 * 60)),
                aged: range(calendar.date(from: DateComponents(year: 2025, month: 1, day: 9))!)
            ],
            // Deliberately omits the current month, so `recent` can only be
            // cleared by the trailing-window clause.
            monthKeys: [BodyWorkoutMonthKey(month: 5, year: 2025)],
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(cleared, [displayedMonth, recent])
    }

    func testAutoApplyWindowMonthKeysSpansPriorMonthNearBoundary() throws {
        let calendar = Calendar.bodyGregorian

        // Mid-month: the 48h window stays inside the current month -> current month only.
        let midMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyWindowMonthKeys(now: midMonth, maxAge: 48 * 3600, calendar: calendar),
            [BodyWorkoutMonthKey(month: 7, year: 2026)]
        )

        // Early in the month: now - 48h falls in the prior month -> both months.
        let earlyMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 9)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyWindowMonthKeys(now: earlyMonth, maxAge: 48 * 3600, calendar: calendar),
            [BodyWorkoutMonthKey(month: 7, year: 2026), BodyWorkoutMonthKey(month: 6, year: 2026)]
        )

        // Across a year boundary: January 1 reaches back into the prior December.
        let newYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 6)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyWindowMonthKeys(now: newYear, maxAge: 48 * 3600, calendar: calendar),
            [BodyWorkoutMonthKey(month: 1, year: 2026), BodyWorkoutMonthKey(month: 12, year: 2025)]
        )
    }

    func testAutoApplyComparisonMonthKeysSpanTheComparisonReach() throws {
        let calendar = Calendar.bodyGregorian

        // Mid-month (Jul 24): the span [now - 33d, now] reaches back to Jun 21, so the
        // oldest candidate's 30-day comparison window touches only June and July.
        let midMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 12)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: midMonth, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar),
            [BodyWorkoutMonthKey(month: 6, year: 2026), BodyWorkoutMonthKey(month: 7, year: 2026)]
        )

        // Early in the month (Jul 2): the span reaches back to May 30, spanning three
        // months — a candidate near the start of July can compare against May.
        let earlyMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 9)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: earlyMonth, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar),
            [
                BodyWorkoutMonthKey(month: 5, year: 2026),
                BodyWorkoutMonthKey(month: 6, year: 2026),
                BodyWorkoutMonthKey(month: 7, year: 2026)
            ]
        )

        // Month boundary (Aug 1): the span reaches back to Jun 29, so June, July, and
        // August are all touched.
        let boundary = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 6)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: boundary, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar),
            [
                BodyWorkoutMonthKey(month: 6, year: 2026),
                BodyWorkoutMonthKey(month: 7, year: 2026),
                BodyWorkoutMonthKey(month: 8, year: 2026)
            ]
        )

        // The duration allowance matters near the cutoff: at Aug 2 01:00, a two-hour
        // workout ending Jul 31 01:00 (age 48h, still eligible) STARTED Jul 30 23:00,
        // so its comparison window opens Jun 30 23:00 — June must be in the span even
        // though `now - (48h + 30d)` alone (Jul 1 01:00) would miss it.
        let nearCutoff = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 1)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: nearCutoff, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar),
            [
                BodyWorkoutMonthKey(month: 6, year: 2026),
                BodyWorkoutMonthKey(month: 7, year: 2026),
                BodyWorkoutMonthKey(month: 8, year: 2026)
            ]
        )

        // The 30-day portion is calendar days, so a fall DST transition (Nov 1 2026 in
        // New York adds an hour) can't shave the span short: at Dec 3 23:30 the earliest
        // candidate start is Nov 30 23:30, and 30 calendar days before that is
        // Oct 31 23:30 — October must be included, where a fixed 30 * 24h subtraction
        // would land at Nov 1 00:30 and drop it.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let acrossFallDST = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 23, minute: 30)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: acrossFallDST, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: newYork),
            [
                BodyWorkoutMonthKey(month: 10, year: 2026),
                BodyWorkoutMonthKey(month: 11, year: 2026),
                BodyWorkoutMonthKey(month: 12, year: 2026)
            ]
        )
    }

    func testAutoApplyComparisonMonthKeysAlwaysConsecutiveTwoOrThreeEndingAtNow() throws {
        let calendar = Calendar.bodyGregorian

        // Sweep a variety of dates across a year (mid-month and near both edges, plus a
        // year boundary): the count is always 2 or 3, the keys are consecutive months,
        // and the last key is always `now`'s own month.
        let samples: [DateComponents] = [
            DateComponents(year: 2026, month: 1, day: 1, hour: 3),
            DateComponents(year: 2026, month: 1, day: 15, hour: 10),
            DateComponents(year: 2026, month: 2, day: 2, hour: 8),
            DateComponents(year: 2026, month: 2, day: 28, hour: 20),
            DateComponents(year: 2026, month: 3, day: 1, hour: 1),
            DateComponents(year: 2026, month: 4, day: 30, hour: 23),
            DateComponents(year: 2026, month: 5, day: 3, hour: 6),
            DateComponents(year: 2026, month: 6, day: 20, hour: 14),
            DateComponents(year: 2026, month: 7, day: 24, hour: 12),
            DateComponents(year: 2026, month: 8, day: 1, hour: 0),
            DateComponents(year: 2026, month: 9, day: 15, hour: 11),
            DateComponents(year: 2026, month: 10, day: 31, hour: 22),
            DateComponents(year: 2026, month: 11, day: 2, hour: 5),
            DateComponents(year: 2026, month: 12, day: 31, hour: 18)
        ]

        for components in samples {
            let now = try XCTUnwrap(calendar.date(from: components))
            let keys = HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: now, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar)

            XCTAssertTrue((2...3).contains(keys.count), "unexpected count \(keys.count) for \(components)")

            // Consecutive months, oldest first, each one month after the previous.
            for (previous, current) in zip(keys, keys.dropFirst()) {
                let previousStart = try XCTUnwrap(calendar.date(from: DateComponents(year: previous.year, month: previous.month)))
                let expectedNext = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: previousStart))
                XCTAssertEqual(BodyWorkoutMonthKey(date: expectedNext, calendar: calendar), current, "non-consecutive keys for \(components)")
            }

            // Ends at `now`'s month.
            XCTAssertEqual(keys.last, BodyWorkoutMonthKey(date: now, calendar: calendar), "last key isn't now's month for \(components)")
        }
    }

    // MARK: - Weekly workout minutes (watch complication bars)

    private func weeklyWorkout(month: Int, day: Int, minutes: Double) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: month, day: day, hour: 8)) ?? Date(),
            duration: minutes * 60
        )
    }

    private func weeklyWorkoutMonthSnapshots(
        may: [WorkoutSummary],
        june: [WorkoutSummary]
    ) -> [BodyWorkoutMonthKey: WorkoutMonthSnapshot] {
        [
            BodyWorkoutMonthKey(month: 5, year: 2026): .make(month: 5, year: 2026, workouts: may, calendar: .bodyGregorian),
            BodyWorkoutMonthKey(month: 6, year: 2026): .make(month: 6, year: 2026, workouts: june, calendar: .bodyGregorian)
        ]
    }

    @MainActor
    func testWeeklyWorkoutMinutesSumsDurationsPerDayWithExplicitRestDayZeros() {
        // Window: May 28 … Jun 3, so it spans a month boundary the way a real
        // rolling week does for most of the month.
        let now = Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 21)) ?? Date()
        let snapshots = weeklyWorkoutMonthSnapshots(
            may: [
                // Outside the window: a workout on the day before it starts must
                // not leak into the first bar.
                weeklyWorkout(month: 5, day: 27, minutes: 90),
                // Two workouts on one day sum into that day's bar.
                weeklyWorkout(month: 5, day: 28, minutes: 30),
                weeklyWorkout(month: 5, day: 28, minutes: 45),
                weeklyWorkout(month: 5, day: 30, minutes: 60)
            ],
            june: [
                weeklyWorkout(month: 6, day: 2, minutes: 20),
                weeklyWorkout(month: 6, day: 3, minutes: 15)
            ]
        )

        let weekly = HealthKitWorkoutStore.weeklyWorkoutMinutes(from: snapshots, now: now)

        // Dense: a rest day is an explicit 0, never nil — a nil would make the
        // pushed metric blank, and the watch merge would refuse the week.
        XCTAssertEqual(weekly, [75, 0, 60, 0, 0, 20, 15])
    }

    @MainActor
    func testWeeklyWorkoutMinutesIsNilOnlyWhenNeitherSourceHasASpannedMonth() {
        let now = Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 21)) ?? Date()
        let juneOnly: [BodyWorkoutMonthKey: WorkoutMonthSnapshot] = [
            BodyWorkoutMonthKey(month: 6, year: 2026): .make(
                month: 6,
                year: 2026,
                workouts: [weeklyWorkout(month: 6, day: 2, minutes: 20)],
                calendar: .bodyGregorian
            )
        ]

        // May is in neither source, so its four days are unknown rather than
        // empty: publishing them as zeros would show a falsely empty week.
        XCTAssertNil(HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, now: now))

        // The launch / passive-refresh shape: only the current month is in
        // memory, and the previous month comes from the persisted App Group
        // snapshot the caller hands in. The week must build from the pair,
        // because an omitted metric DELETES the watch's bars on a phone push.
        let persistedMay: [BodyWorkoutMonthKey: WorkoutMonthSnapshot] = [
            BodyWorkoutMonthKey(month: 5, year: 2026): .make(
                month: 5,
                year: 2026,
                workouts: [weeklyWorkout(month: 5, day: 30, minutes: 60)],
                calendar: .bodyGregorian
            )
        ]
        XCTAssertEqual(
            HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, fallback: persistedMay, now: now),
            [0, 0, 60, 0, 0, 20, 0]
        )

        // A fallback that doesn't cover the missing month changes nothing.
        let persistedApril: [BodyWorkoutMonthKey: WorkoutMonthSnapshot] = [
            BodyWorkoutMonthKey(month: 4, year: 2026): .make(
                month: 4,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            )
        ]
        XCTAssertNil(
            HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, fallback: persistedApril, now: now)
        )

        // In-memory wins where both sources carry the month: the persisted file
        // lags a refresh that already updated memory, so Jun 2 keeps its 20.
        var withStaleJune = persistedMay
        withStaleJune[BodyWorkoutMonthKey(month: 6, year: 2026)] = .make(
            month: 6,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, fallback: withStaleJune, now: now),
            [0, 0, 60, 0, 0, 20, 0]
        )

        // Once the window sits entirely inside a loaded month, the week builds
        // with no fallback at all.
        let midMonth = Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 21)) ?? Date()
        XCTAssertEqual(
            HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, now: midMonth),
            [20, 0, 0, 0, 0, 0, 0]
        )
    }
}
