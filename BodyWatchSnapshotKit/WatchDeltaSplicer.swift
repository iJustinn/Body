//
//  WatchDeltaSplicer.swift
//  Body
//
//  Splices the watch's short on-device HealthKit delta re-query onto the
//  phone-seeded historical trend/sleep-history context (`WatchComputeSeed`),
//  so the watch recomputes from a series that is "the phone's history, plus a
//  fresh few days" rather than re-deriving the whole window itself (the watch
//  only retains ~a week of HealthKit history anyway).
//

import Foundation

/// Tri-state fetch result mirroring the iOS engine's `QueryOutcome` semantics:
/// a plain `nil`/optional isn't enough here because "no data in the window"
/// (`.success([])`) and "the query itself failed" (`.failure`) must be told
/// apart — a failure must preserve the seed untouched, while a genuine
/// empty result must still clear stale seed points in the delta window.
enum WatchFetchOutcome<T> {
    case success(T)
    case failure

    /// True when the query ran and its (possibly empty) result is
    /// authoritative — the readiness watermark requires EVERY eligible input
    /// query to report this before the recomputed score may be published.
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

enum WatchDeltaSplicer {
    /// Start of the delta re-fetch window: `dataThrough`'s calendar day minus
    /// 2 CALENDAR days (not a fixed 48h) — a DST-transition day is 23/25h, and
    /// calendar-day arithmetic keeps the window "the last 2 full days plus
    /// today" regardless. The 2-day overlap absorbs a late-syncing sample that
    /// landed after the phone's last refresh but is dated to a day the seed
    /// already covers.
    static func deltaStart(dataThrough: Date, calendar: Calendar = .bodyGregorian) -> Date {
        let day = calendar.startOfDay(for: dataThrough)
        return calendar.date(byAdding: .day, value: -2, to: day) ?? day
    }

    /// Splices a delta fetch onto a seeded trend series: seed points strictly
    /// before `windowStart` are kept untouched; the `[windowStart, …)` slice
    /// is replaced wholesale by the delta's points in that same range (a delta
    /// point outside the window — e.g. an engine quirk returning extra history
    /// — is ignored, never appended past the boundary it doesn't own).
    /// `.failure` returns `seedSeries` completely unchanged: a failed query
    /// must never blank data the seed already had. `.success([])` still
    /// clears the window, since an empty result IS the fresh truth.
    static func splice(
        seedSeries: HealthTrendSeries,
        delta: WatchFetchOutcome<HealthTrendSeries>,
        from windowStart: Date,
        calendar: Calendar = .bodyGregorian
    ) -> HealthTrendSeries {
        guard case .success(let deltaSeries) = delta else {
            return seedSeries
        }

        let outsideWindow = seedSeries.points.filter { $0.date < windowStart }
        let insideDelta = deltaSeries.points.filter { $0.date >= windowStart }
        return HealthTrendSeries(points: outsideWindow + insideDelta)
    }

    /// Same failure/empty/out-of-window semantics as `splice`, but for
    /// `SleepHistorySnapshot` — keyed by the night's wake day (`SleepDaySummary.date`)
    /// rather than a `HealthTrendSeries` point date, since a night isn't a
    /// single-value series point.
    static func spliceSleepHistory(
        seed: SleepHistorySnapshot,
        deltaNights: WatchFetchOutcome<[SleepDaySummary]>,
        from windowStart: Date,
        calendar: Calendar = .bodyGregorian
    ) -> SleepHistorySnapshot {
        guard case .success(let nights) = deltaNights else {
            return seed
        }

        let windowStartDay = calendar.startOfDay(for: windowStart)
        let outsideWindow = seed.days.filter { calendar.startOfDay(for: $0.date) < windowStartDay }
        let insideDelta = nights.filter { calendar.startOfDay(for: $0.date) >= windowStartDay }
        return SleepHistorySnapshot(days: outsideWindow + insideDelta)
    }
}
