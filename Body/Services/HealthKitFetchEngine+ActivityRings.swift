//
//  HealthKitFetchEngine+ActivityRings.swift
//  Body
//

import Foundation
import HealthKit

/// Outcome of scanning for ring data older than the already-probed months.
/// `failed` (error) is distinct from `noOlderData` so a transient HealthKit
/// failure never gets recorded as the permanent start of history.
enum ActivityRingOlderHistoryProbe {
    case found(ActivityRingHistorySnapshot)
    case noOlderData
    case failed
}

/// Result of a dashboard ring-history / backfill fetch: the resolved snapshot
/// plus whether the underlying activity-summary query FAILED (as opposed to
/// genuinely returning no days). The store ORs `hadQueryFailure` with the
/// summary/trend bits before advancing the freshness TTL, so a transient ring
/// failure withholds the TTL and the next resume retries. A permission-off or
/// selection-off result is a genuine empty (`hadQueryFailure: false`).
struct ActivityRingHistoryFetchResult {
    let history: ActivityRingHistorySnapshot
    let hadQueryFailure: Bool
    /// HealthKit refused the read outright (Activity access revoked). The store
    /// drops its ENTIRE cached ring history on this — not just the requested
    /// window — so stale backfilled/paged months can't outlive the permission.
    var authorizationDenied = false
    /// The chunked backfill walked all the way back to
    /// `activityRingBackfillStartDate`, so the history is genuinely complete.
    /// A partial walk (cancelled, deadline blown, or a chunk that failed)
    /// leaves this false, and completion state stays the store's business.
    var reachedHistoryStart = false
    /// Where a resumption of the backfill should pick up: the EXCLUSIVE end of
    /// the span still missing, so the next run fetches days strictly older than
    /// it. `nil` when nothing is pending.
    var nextChunkEndDate: Date?

    static let empty = ActivityRingHistoryFetchResult(history: .empty, hadQueryFailure: false)
    static let denied = ActivityRingHistoryFetchResult(history: .empty, hadQueryFailure: false, authorizationDenied: true)
}

/// Handed each backfill chunk the moment it lands, before the walk queries the
/// next one. `history` carries ONLY that chunk's days (the store merges), and
/// `nextChunkEndDate` is the checkpoint to persist so a quit mid-walk resumes
/// there. Returning `false` stops the walk — the store says so when a Clear
/// Cache invalidated the epoch the walk was started under.
typealias ActivityRingBackfillChunkHandler = @Sendable (ActivityRingHistoryFetchResult) async -> Bool

/// Outcome of one activity-summary read, already mapped off HealthKit's own
/// objects so the value can cross a task boundary. `stopped` (the read blew its
/// wall-clock deadline, or the surrounding refresh was cancelled) is kept apart
/// from `failed` at the call site only for clarity: both mean the days did not
/// arrive.
private enum ActivityRingDayQueryOutcome {
    case days([ActivityRingDaySummary])
    case denied
    case failed
    case stopped
}

// Activity Rings summary (one day) and history (range of days, plus the
// per-month-key overload that pages back through older months). The shared
// `activityRingHistoryInterval` and `activityRingSummary` helpers live on
// the main engine file and the sample-parsers extension respectively.
extension HealthKitFetchEngine {
    func fetchActivityRingSummary(calendar: Calendar, date: Date = Date()) async -> QueryOutcome<ActivityRingSummary> {
        guard permissionSelection.includes(.activityRings) else {
            return .success(nil)
        }

        let dateComponents = Self.activityDateComponents(for: date, calendar: calendar)

        let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)

        do {
            guard let summary = try await descriptor.result(for: healthStore).first else {
                return .success(nil)
            }

            return .success(Self.activityRingSummary(from: summary))
        } catch {
            Self.logTrendQueryFailure("activityRings", error: error)
            // A denied ring read is a confirmed absence, not a query failure.
            return Self.isAuthorizationDenial(error) ? .success(nil) : .failure
        }
    }

    func fetchActivityRingHistory(calendar: Calendar, date: Date = Date()) async -> ActivityRingHistoryFetchResult {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        let interval = activityRingHistoryInterval(calendar: calendar, date: date)
        let loadedMonthKeys = Self.recentActivityRingMonthKeys(
            count: HealthKitWorkoutStore.recentChartMonthCount,
            from: date,
            calendar: calendar
        )
        return await fetchActivityRingHistory(
            start: interval.start,
            end: interval.end,
            loadedMonthKeys: loadedMonthKeys,
            calendar: calendar
        )
    }

    func fetchDashboardActivityRingHistory(
        calendar: Calendar,
        selection: BodyDashboardFetchSelection,
        date: Date = Date()
    ) async -> ActivityRingHistoryFetchResult {
        guard selection.includesActivityRings else {
            return .empty
        }

        return await fetchActivityRingHistory(calendar: calendar, date: date)
    }

    func fetchDashboardActivityRingBackfillHistory(
        calendar: Calendar,
        selection: BodyDashboardFetchSelection,
        date: Date = Date(),
        resumeFrom: Date? = nil,
        onChunk: ActivityRingBackfillChunkHandler
    ) async -> ActivityRingHistoryFetchResult {
        guard selection.includesActivityRings else {
            return .empty
        }

        return await fetchActivityRingBackfillHistory(
            calendar: calendar,
            date: date,
            resumeFrom: resumeFrom,
            onChunk: onChunk
        )
    }

    /// One-time first-load scan: every ring day from `activityRingBackfillStartDate`
    /// (at most ten years back) through today, walked NEWEST FIRST in
    /// `activityRingBackfillChunkMonthCount`-month chunks so the most useful
    /// months land first and each read carries its own deadline. Loaded month
    /// keys span the earliest month with data through the current month, so
    /// the whole stretch persists as loaded (gap months render as empty
    /// grids) and older-month pagination never refetches it. A FRESH walk that
    /// finds no ring data at all falls back to the recent dashboard window; a
    /// resumed one claims only what it scanned (see
    /// `activityRingBackfillLoadedMonthKeys`).
    ///
    /// Each landed chunk goes to `onChunk` before the next one is queried, so
    /// the calendar fills in as the walk runs and the caller can write the
    /// chunk — and its resume checkpoint — to disk right away. The accumulated
    /// return value repeats what those chunks already carried; it is what
    /// reports the terminal state, and what falls back to the recent window
    /// when the whole covered span turned out to hold no ring data at all.
    ///
    /// The walk stops at the first chunk that fails, blows its deadline, is
    /// cancelled, or that `onChunk` refuses, and returns what already landed
    /// together with `nextChunkEndDate` so a resumption can continue instead of
    /// restarting. This used to be ONE ten-year
    /// `HKActivitySummaryQueryDescriptor` await with no timeout: when HealthKit
    /// never called back (typical when only a couple of types are authorized)
    /// the dashboard refresh's task group could not close, nothing was
    /// persisted, and the loading overlay stayed up forever.
    ///
    /// `date` is TODAY — it anchors the ten-year span and must NOT become the
    /// checkpoint on a resumption — and `resumeFrom` is the EXCLUSIVE
    /// checkpoint a previous walk handed back. See
    /// `activityRingBackfillWalkEnd` for that conversion.
    func fetchActivityRingBackfillHistory(
        calendar: Calendar,
        date: Date = Date(),
        resumeFrom: Date? = nil,
        onChunk: ActivityRingBackfillChunkHandler
    ) async -> ActivityRingHistoryFetchResult {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        guard
            let end = Self.activityRingBackfillWalkEnd(date: date, resumeFrom: resumeFrom, calendar: calendar),
            let historyStart = Self.activityRingBackfillStartDate(date: date, calendar: calendar),
            historyStart <= end
        else {
            return .empty
        }

        var days: [ActivityRingDaySummary] = []
        // `chunkEnd` is the newest day still to fetch; `pendingEnd` trails it by
        // one day on the exclusive side, so it is exactly the `nextChunkEndDate`
        // to hand back whenever the walk stops early.
        var chunkEnd = end
        var pendingEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        var landedChunk = false
        // Oldest chunk start this walk actually READ (chunks go newest first,
        // so the last one assigned is the oldest). It bounds what an empty
        // result may claim as loaded.
        var oldestScannedStart: Date?
        var hadQueryFailure = false
        var reachedHistoryStart = false

        walk: while true {
            // A cancelled refresh keeps the chunks that already landed rather
            // than throwing the whole walk away.
            if Task.isCancelled {
                hadQueryFailure = true
                break walk
            }

            let chunkStart = Self.activityRingBackfillChunkStart(
                endingAt: chunkEnd,
                notBefore: historyStart,
                calendar: calendar
            )

            let chunkDays: [ActivityRingDaySummary]
            switch await runActivityRingDayQuery(
                start: Self.activityDateComponents(for: chunkStart, calendar: calendar),
                end: Self.activityDateComponents(for: chunkEnd, calendar: calendar),
                calendar: calendar,
                context: "activityRingBackfill"
            ) {
            case .denied:
                // A denied ring read genuinely has no days, so it must not
                // withhold the freshness TTL. `.denied` carries no loaded month
                // keys either, so the backfill stays unstamped and reruns once
                // access is granted — including the chunks that already landed.
                return .denied
            case .failed, .stopped:
                // A partial walk must never advance the freshness TTL, so an
                // interrupted chunk fails the result the same way an errored
                // one does; `nextChunkEndDate` is what tells the caller how far
                // it got.
                hadQueryFailure = true
                break walk
            case .days(let fetched):
                // `HKActivitySummaryQuery` is predicated on date components and
                // can hand back a boundary day just outside the window this
                // chunk asked for. Such a day would widen the month span the
                // chunk claims below into a NEIGHBOURING chunk's month — and
                // `replacingLoadedMonths` REPLACES every month a result claims,
                // so the neighbour's days for that month would be deleted the
                // moment either chunk lands. Clamping here bounds both the
                // per-chunk claim and the accumulated `days` by construction.
                chunkDays = Self.activityRingDays(
                    fetched,
                    from: chunkStart,
                    through: chunkEnd,
                    calendar: calendar
                )
            }

            days.append(contentsOf: chunkDays)
            landedChunk = true
            oldestScannedStart = chunkStart

            if chunkStart > historyStart {
                pendingEnd = chunkStart
            } else {
                reachedHistoryStart = true
            }

            // Hand the chunk over the moment it lands, checkpoint included, so
            // the months show up one chunk at a time and a kill mid-walk keeps
            // what already arrived. A caller that says no — its cache epoch was
            // wiped — stops the walk instead of being fed more chunks.
            guard await onChunk(ActivityRingHistoryFetchResult(
                history: ActivityRingHistorySnapshot(
                    days: chunkDays,
                    // Strictly the months THIS chunk's window covers: a chunk
                    // that claimed a newer month would replace the days an
                    // earlier chunk already published for it. Both ends stay
                    // month aligned, so no month is claimed part-fetched. The
                    // months this chunk read but found empty below its oldest
                    // day are left for the finished walk's result to mark.
                    loadedMonthKeys: chunkDays.first.map {
                        Self.activityRingMonthKeySpan(from: $0.date, to: chunkEnd, calendar: calendar)
                    } ?? []
                ),
                hadQueryFailure: false,
                reachedHistoryStart: reachedHistoryStart,
                nextChunkEndDate: reachedHistoryStart ? nil : pendingEnd
            )) else {
                hadQueryFailure = true
                break walk
            }

            guard !reachedHistoryStart else {
                break walk
            }

            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: chunkStart) else {
                break walk
            }
            chunkEnd = previousDay
        }

        let nextChunkEndDate = reachedHistoryStart ? nil : pendingEnd
        guard landedChunk else {
            // Not one chunk landed, so nothing may be recorded as loaded.
            return ActivityRingHistoryFetchResult(
                history: .empty,
                hadQueryFailure: hadQueryFailure,
                nextChunkEndDate: nextChunkEndDate
            )
        }

        let sortedDays = days.sorted { $0.date < $1.date }
        let loadedMonthKeys = Self.activityRingBackfillLoadedMonthKeys(
            earliestDayWithData: sortedDays.first?.date,
            oldestScannedStart: oldestScannedStart,
            walkEnd: end,
            resumeFrom: resumeFrom,
            date: date,
            calendar: calendar
        )

        return ActivityRingHistoryFetchResult(
            history: ActivityRingHistorySnapshot(days: sortedDays, loadedMonthKeys: loadedMonthKeys),
            hadQueryFailure: hadQueryFailure,
            reachedHistoryStart: reachedHistoryStart,
            nextChunkEndDate: nextChunkEndDate
        )
    }

    func fetchActivityRingHistory(
        monthKey: ActivityRingMonthKey,
        calendar: Calendar
    ) async -> ActivityRingHistorySnapshot {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        guard
            let start = monthKey.startDate(calendar: calendar),
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: start),
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonthStart)
        else {
            return ActivityRingHistorySnapshot(days: [], loadedMonthKeys: [monthKey])
        }

        // Older-month pagination doesn't feed the freshness TTL, so it consumes
        // just the resolved snapshot and drops the failure bit.
        return await fetchActivityRingHistory(
            start: start,
            end: end,
            loadedMonthKeys: [monthKey],
            calendar: calendar
        ).history
    }

    private func fetchActivityRingHistory(
        start: Date,
        end: Date,
        loadedMonthKeys: [ActivityRingMonthKey],
        calendar: Calendar
    ) async -> ActivityRingHistoryFetchResult {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        switch await runActivityRingDayQuery(
            start: Self.activityDateComponents(for: start, calendar: calendar),
            end: Self.activityDateComponents(for: end, calendar: calendar),
            calendar: calendar,
            context: "activityRingHistory"
        ) {
        case .days(let days):
            return ActivityRingHistoryFetchResult(
                history: ActivityRingHistorySnapshot(days: days, loadedMonthKeys: loadedMonthKeys)
                    .filteringDaysToLoadedMonths(calendar: calendar),
                hadQueryFailure: false
            )
        case .denied:
            // A denied ring read is a genuine empty range, not a failure. The
            // store wipes every cached ring month on `.denied` — HealthKit is
            // the source of truth, and access revoked after a backfill must
            // not leave older months on screen.
            return .denied
        case .failed, .stopped:
            return ActivityRingHistoryFetchResult(history: .empty, hadQueryFailure: true)
        }
    }

    /// One `HKActivitySummaryQuery` for the inclusive day range, raced against a
    /// wall-clock deadline. Losing the race cancels the query task, and
    /// `runCancellableQuery` answers that by calling `healthStore.stop` and
    /// resuming with `.stopped`, so a HealthKit that never calls back can no
    /// longer wedge the caller: an `HKActivitySummaryQueryDescriptor` await has
    /// no timeout and no way to be stopped, which is what left the dashboard
    /// refresh (and its "Loading Health Data" overlay) hanging forever.
    ///
    /// Query and deadline are unstructured tasks rather than task-group children
    /// because `runCancellableQuery` takes a non-Sendable `makeQuery` closure:
    /// a `Task` inherits this actor's isolation, so the closure never crosses an
    /// isolation boundary, while a group child would run nonisolated. The cost
    /// is that cancellation has to be forwarded by hand, which the cancellation
    /// handler below does.
    private func runActivityRingDayQuery(
        start: DateComponents,
        end: DateComponents,
        calendar: Calendar,
        context: String
    ) async -> ActivityRingDayQueryOutcome {
        let queryTask = Task { () -> ActivityRingDayQueryOutcome in
            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: start, end: end)
            // Every caller of this query is off the refresh path — the ten-year
            // backfill, the recent-window read that resumes it, older-month
            // pagination, and the era probe — and the backfill in particular
            // "can run for minutes or hang outright". So it always spends the
            // background budget, never a permit the visible leaves need. (The
            // refresh's own ring read, `fetchActivityRingSummary`, goes through
            // `HKActivitySummaryQueryDescriptor` and never lands here.)
            return await withBackgroundQueryPool {
                await self.runCancellableQuery(cancelledValue: ActivityRingDayQueryOutcome.stopped) { resume in
                    HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                        guard let summaries else {
                            Self.logTrendQueryFailure(context, error: error)
                            // Unlike sample queries, a denied ring read reports an
                            // authorization error instead of coming back empty.
                            resume(error.map { Self.isAuthorizationDenial($0) ? .denied : .failed } ?? .failed)
                            return
                        }

                        resume(.days(Self.activityRingDays(from: summaries, calendar: calendar)))
                    }
                }
            }
        }
        let deadlineTask = Task {
            try? await ContinuousClock().sleep(for: Self.activityRingQueryTimeout)
            queryTask.cancel()
        }

        let outcome = await withTaskCancellationHandler {
            await queryTask.value
        } onCancel: {
            queryTask.cancel()
        }
        deadlineTask.cancel()

        if case .stopped = outcome {
            Self.logTrendQueryFailure(context, error: nil)
        }

        return outcome
    }

    /// One wide scan for the most recent month with ring data strictly older
    /// than `monthKey`, back to the Apple Watch era (rings cannot predate the
    /// platform). Used when consecutive previous months come back empty so a
    /// long no-watch gap is crossed in a single query, and a true history
    /// start is detected exactly instead of guessed from an empty streak.
    func probeOlderActivityRingHistory(
        before monthKey: ActivityRingMonthKey,
        calendar: Calendar
    ) async -> ActivityRingOlderHistoryProbe {
        guard permissionSelection.includes(.activityRings) else {
            // A Body-side toggle off is a settled answer, not a transient read failure:
            // there is no older history to page while rings are excluded, and the store
            // resets `hasMoreActivityRingHistory` on every refresh, so re-enabling the
            // toggle restores pagination.
            return .noOlderData
        }

        guard
            let eraStart = calendar.date(from: DateComponents(year: 2014, month: 9, day: 1)),
            let monthStart = monthKey.startDate(calendar: calendar),
            let end = calendar.date(byAdding: .day, value: -1, to: monthStart),
            eraStart <= end
        else {
            return .noOlderData
        }

        // The same stop-capable, deadlined read the rest of the ring fetches use.
        // The probe is reachable from older-month pagination, so an unbounded
        // await here would wedge the task that pages history exactly the way the
        // ten-year backfill used to wedge the dashboard refresh.
        switch await runActivityRingDayQuery(
            start: Self.activityDateComponents(for: eraStart, calendar: calendar),
            end: Self.activityDateComponents(for: end, calendar: calendar),
            calendar: calendar,
            context: "activityRingOlderHistoryProbe"
        ) {
        case .days(let days):
            guard let latestDay = days.max(by: { $0.date < $1.date }) else {
                return .noOlderData
            }

            let foundKey = ActivityRingMonthKey(date: latestDay.date, calendar: calendar)
            let foundMonthDays = days.filter {
                ActivityRingMonthKey(date: $0.date, calendar: calendar) == foundKey
            }
            return .found(ActivityRingHistorySnapshot(days: foundMonthDays, loadedMonthKeys: [foundKey]))
        case .denied, .failed, .stopped:
            // Unchanged: every unsuccessful read is `failed`, never `noOlderData`,
            // so a transient failure is never recorded as the start of history.
            return .failed
        }
    }

    static let activityRingBackfillYearCount = 10

    /// How much of the backfill one chunk covers. Chunking bounds the WORK per
    /// read; `activityRingQueryTimeout` is what bounds the wall clock, since a
    /// HealthKit that never calls back hangs a small query just as happily as a
    /// ten-year one.
    static let activityRingBackfillChunkMonthCount = 12

    /// Wall-clock ceiling for a single activity-summary read. Blowing it stops
    /// the query and keeps whatever already landed, so the caller's task group
    /// can always close.
    static let activityRingQueryTimeout: Duration = .seconds(20)

    /// Start of the backfill chunk ending on `chunkEnd`:
    /// `activityRingBackfillChunkMonthCount` months back, snapped to a month
    /// start and clamped to `historyStart`. Month alignment is what lets a
    /// landed chunk mark whole months as loaded; a mid-month boundary would
    /// strand the earlier days of that month as permanently empty.
    nonisolated static func activityRingBackfillChunkStart(
        endingAt chunkEnd: Date,
        notBefore historyStart: Date,
        calendar: Calendar
    ) -> Date {
        guard
            let shifted = calendar.date(byAdding: .month, value: -activityRingBackfillChunkMonthCount, to: chunkEnd),
            let monthStart = calendar.dateInterval(of: .month, for: shifted)?.start,
            monthStart > historyStart
        else {
            return historyStart
        }

        return monthStart
    }

    /// Maps activity summaries to day summaries, oldest first, dropping any
    /// whose components don't resolve to a date.
    nonisolated static func activityRingDays(
        from summaries: [HKActivitySummary],
        calendar: Calendar
    ) -> [ActivityRingDaySummary] {
        summaries.compactMap { summary -> ActivityRingDaySummary? in
            let components = summary.dateComponents(for: calendar)
            guard let date = calendar.date(from: components) else {
                return nil
            }

            return ActivityRingDaySummary(
                date: calendar.startOfDay(for: date),
                summary: Self.activityRingSummary(from: summary)
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// Days whose own day falls inside the CLOSED `[from, through]` window,
    /// order preserved. Both bounds and each day are compared at day
    /// granularity, because a chunk window is expressed in whole days.
    nonisolated static func activityRingDays(
        _ days: [ActivityRingDaySummary],
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [ActivityRingDaySummary] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return days.filter { day in
            let dayStart = calendar.startOfDay(for: day.date)
            return dayStart >= startDay && dayStart <= endDay
        }
    }

    /// The INCLUSIVE newest day a backfill walk fetches.
    ///
    /// `resumeFrom` is the EXCLUSIVE checkpoint a previous walk handed back
    /// (`nextChunkEndDate` = the month-aligned `chunkStart` of the chunk that
    /// just landed), so the checkpoint's own day is ALREADY covered and a
    /// resumption has to start one day older. Feeding the checkpoint straight
    /// back in as an inclusive end instead makes the resumed walk re-claim the
    /// checkpoint's whole month while supplying only its first day — and
    /// `replacingLoadedMonths` REPLACES every month an incoming chunk claims,
    /// so the rest of that month would be deleted from the cache.
    ///
    /// The checkpoint a walk that landed NOTHING hands back is `end + 1 day`,
    /// so the same conversion correctly resumes at today rather than skipping a
    /// day. `date` (today) also caps the result, so a checkpoint left by a
    /// clock change can't push the walk into the future.
    nonisolated static func activityRingBackfillWalkEnd(
        date: Date,
        resumeFrom: Date?,
        calendar: Calendar = .bodyGregorian
    ) -> Date? {
        let today = calendar.startOfDay(for: date)
        guard let resumeFrom else {
            return today
        }

        guard let dayBeforeCheckpoint = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: resumeFrom)
        ) else {
            return nil
        }
        return min(dayBeforeCheckpoint, today)
    }

    /// Month keys the FINISHED walk's accumulated result claims as loaded.
    ///
    /// `replacingLoadedMonths` REPLACES every month a result claims, so this
    /// must never name a month the walk did not actually cover:
    /// - days landed → the span from the oldest day to the walk's own `walkEnd`
    ///   (never past it). Chunks are month aligned (see
    ///   `activityRingBackfillChunkStart`), so the oldest day's month is always
    ///   covered in full and no month is marked loaded part-fetched.
    /// - no days, RESUMED walk → only the interval it actually scanned. Such a
    ///   walk legitimately found nothing in OLDER history; claiming the recent
    ///   window here would replace — and so delete — the recent ring days an
    ///   earlier run had already saved.
    /// - no days, FRESH walk → the recent dashboard window, so an account with
    ///   no ring data anywhere renders empty grids instead of nothing. A fresh
    ///   walk always starts at today, so that window is inside what it scanned.
    nonisolated static func activityRingBackfillLoadedMonthKeys(
        earliestDayWithData: Date?,
        oldestScannedStart: Date?,
        walkEnd: Date,
        resumeFrom: Date?,
        date: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [ActivityRingMonthKey] {
        if let earliestDayWithData {
            return activityRingMonthKeySpan(from: earliestDayWithData, to: walkEnd, calendar: calendar)
        }

        // A resumed walk NEVER falls through to the recent window below, even
        // with no scanned start to report. The walk currently early-returns
        // before it can ask for keys without having landed a chunk, so this is
        // belt and braces — but the recent window is the one answer that can
        // name months newer than `walkEnd`, and gating it on anything other
        // than "this walk started at today" is what produced this bug three
        // times already. Claim nothing rather than claim what we did not read.
        if resumeFrom != nil {
            guard let oldestScannedStart else {
                return []
            }
            return activityRingMonthKeySpan(from: oldestScannedStart, to: walkEnd, calendar: calendar)
        }

        return recentActivityRingMonthKeys(
            count: HealthKitWorkoutStore.recentChartMonthCount,
            from: date,
            calendar: calendar
        )
    }

    /// First day of the first-load backfill window: the month start ten
    /// years before `date`, clamped to the Apple Watch era (rings cannot
    /// predate the platform).
    static func activityRingBackfillStartDate(
        date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> Date? {
        guard
            let eraStart = calendar.date(from: DateComponents(year: 2014, month: 9, day: 1)),
            let yearsBack = calendar.date(byAdding: .year, value: -activityRingBackfillYearCount, to: date),
            let windowStart = calendar.dateInterval(of: .month, for: yearsBack)?.start
        else {
            return nil
        }

        return max(eraStart, windowStart)
    }

    /// Every month key from `start`'s month through `end`'s month, inclusive
    /// on both ends (unlike `activityRingMonthKeys(after:before:)`).
    static func activityRingMonthKeySpan(
        from start: Date,
        to end: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [ActivityRingMonthKey] {
        guard
            let startMonth = calendar.dateInterval(of: .month, for: start)?.start,
            let endMonth = calendar.dateInterval(of: .month, for: end)?.start,
            startMonth <= endMonth
        else {
            return []
        }

        var keys = [ActivityRingMonthKey(date: startMonth, calendar: calendar)]
        var cursor = startMonth
        while let next = calendar.date(byAdding: .month, value: 1, to: cursor), next <= endMonth {
            keys.append(ActivityRingMonthKey(date: next, calendar: calendar))
            cursor = next
        }

        return keys
    }

    static func recentActivityRingMonthKeys(
        count: Int,
        from date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> [ActivityRingMonthKey] {
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: date)?.start else {
            return [ActivityRingMonthKey(date: date, calendar: calendar)]
        }

        return (0..<max(count, 1)).compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else {
                return nil
            }

            return ActivityRingMonthKey(date: monthDate, calendar: calendar)
        }
        .sorted { lhs, rhs in
            if lhs.year == rhs.year {
                return lhs.month < rhs.month
            }
            return lhs.year < rhs.year
        }
    }
}
