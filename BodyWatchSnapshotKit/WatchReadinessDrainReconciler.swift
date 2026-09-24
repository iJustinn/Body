//
//  WatchReadinessDrainReconciler.swift
//  BodyWatchSnapshotKit
//
//  Keeps the same-day activity drain on the watch's displayed readiness honest
//  while the phone and the watch disagree about which workouts exist.
//
//  The merge (`WatchComputeMerge`) picks a WINNER per metric by freshness alone,
//  and for readiness that is not enough: HealthKit replicates a workout between
//  the devices minutes to hours after it is saved, so a phone refresh stamped
//  AFTER the watch's compute can still predate the workout the watch just
//  drained, and a watch compute can likewise predate a workout only the phone
//  has seen. Taking the winner wholesale would drop that workout's drain until
//  replication catches up, which is exactly the "readiness only moves after a
//  phone sync" failure.
//
//  So each publisher states which workouts it drained (`WatchMetric.drain`),
//  the watch keeps the latest report from each side
//  (`WatchMetric.drainReports`), and the displayed score is the winner's
//  UNDRAINED score minus the union of both reports' contributions, through the
//  same `ActivityReadinessImpact.drainedScore` a full recompute uses. Who wins
//  is never changed here, and neither are the winner's provenance stamps.
//

import Foundation

enum WatchReadinessDrainReconciler {
    // MARK: - Report intake

    /// `reports` with the phone's slot replaced by an incoming push's report.
    /// nil (an older phone build, or Workouts not readable there) is stored as
    /// nil: unknown, never "no workouts".
    static func receivingPhoneReport(
        _ report: WatchReadinessDrainReport?,
        into reports: WatchReadinessDrainReports?
    ) -> WatchReadinessDrainReports {
        var next = reports ?? WatchReadinessDrainReports()
        next.phone = report
        next.watchRemovedIDs = prunedRemovedIDs(next)
        return next
    }

    /// `reports` with the watch's slot replaced by a fresh compute's report.
    ///
    /// A workout the watch reported before and no longer finds was DELETED: the
    /// watch's report comes straight from a successful HealthKit query, and
    /// leaving a wake cycle is handled by the cycle filter instead. The id is
    /// remembered so the phone's report, which keeps listing the workout until
    /// the deletion replicates (indefinitely, with the phone offline), can't
    /// resurrect its drain. The phone gets no such list: a workout missing from
    /// a phone report can just as well be a month snapshot that had not loaded.
    static func receivingWatchReport(
        _ report: WatchReadinessDrainReport?,
        into reports: WatchReadinessDrainReports?
    ) -> WatchReadinessDrainReports {
        var next = reports ?? WatchReadinessDrainReports()
        if let report {
            let kept = Set(report.contributions.map(\.id))
            let dropped = (next.watch?.contributions ?? []).map(\.id).filter { !kept.contains($0) }
            next.watchRemovedIDs = (next.watchRemovedIDs ?? []) + dropped
        }
        next.watch = report
        next.watchRemovedIDs = prunedRemovedIDs(next)
        return next
    }

    /// A removal only matters while the phone still lists the workout.
    private static func prunedRemovedIDs(_ reports: WatchReadinessDrainReports) -> [String]? {
        let phoneIDs = Set((reports.phone?.contributions ?? []).map(\.id))
        let pruned = Array(Set(reports.watchRemovedIDs ?? []).intersection(phoneIDs)).sorted()
        return pruned.isEmpty ? nil : pruned
    }

    // MARK: - Reconciliation

    /// The contributions that count for a winner holding `own`, given the other
    /// side's latest report.
    ///
    /// The drain window is the LATER of the two wake cycle starts, never a
    /// calendar day: an evening workout keeps draining past midnight until
    /// someone reports a new wake cycle, and a new cycle expires the old drain
    /// even on the same day (`ReadinessComputeSupport.wakeCycleStart`, which
    /// also bounds a cycle to 24 hours). For a workout both sides know, the
    /// winner's points stand, so a re-rated effort follows the fresher side.
    static func effectiveContributions(
        own: WatchReadinessDrainReport,
        other: WatchReadinessDrainReport?,
        watchRemovedIDs: [String]?
    ) -> [WatchReadinessDrainReport.Contribution] {
        let cycleStart = max(own.cycleStart, other?.cycleStart ?? own.cycleStart)
        let removed = Set(watchRemovedIDs ?? [])
        var seen = Set<String>()
        return (own.contributions + (other?.contributions ?? [])).filter { contribution in
            contribution.start >= cycleStart
                && !removed.contains(contribution.id)
                && seen.insert(contribution.id).inserted
        }
    }

    /// `winner` carrying `reports`, with its score re-derived from the union of
    /// both reports.
    ///
    /// Left exactly as the merge produced it when there is nothing to reconcile
    /// against: a metric that isn't readiness, a BLANK winner (a blank readiness
    /// is an authoritative clear, and a drain report must never resurrect a
    /// score behind it), or a winner with no report of its own (an older
    /// payload, or Workouts not readable: unknown, so today's behavior stands).
    static func reconciled(
        _ winner: WatchMetric,
        reports: WatchReadinessDrainReports,
        winnerIsWatchComputed: Bool
    ) -> WatchMetric {
        guard winner.kind == WatchMetricKindKey.readiness else { return winner }
        var metric = winner
        // Nothing reported by either side yet is stored as nil, so a payload
        // from before these fields merges exactly as it used to.
        metric.drainReports = reports == WatchReadinessDrainReports() ? nil : reports
        guard winner.hasValue, let own = winner.drain else { return metric }

        let contributions = effectiveContributions(
            own: own,
            other: winnerIsWatchComputed ? reports.phone : reports.watch,
            watchRemovedIDs: reports.watchRemovedIDs
        )
        let drained = ActivityReadinessImpact.drainedScore(
            undrained: own.undrainedScore,
            contributionPoints: contributions.reduce(0) { $0 + $1.points }
        )
        let score = drained?.score ?? own.undrainedScore
        // Always re-derived from the winner's OWN report rather than from what
        // is on screen, so a previously reconciled metric that is kept again
        // settles back once the other side's report drops a workout.
        guard score != metric.score || (drained != nil) != (metric.weeklyCurrentValue != nil) else {
            return metric
        }

        let display = WatchMetricsSnapshotBuilder.readinessMetric(score: score, isDrained: drained != nil)
        metric.displayValue = display.displayValue
        metric.unit = display.unit
        metric.score = display.score
        metric.fillFraction = display.fillFraction
        metric.rawValue = display.rawValue
        metric.levelMin = display.levelMin
        metric.levelMax = display.levelMax
        metric.tint = display.tint
        metric.statusBand = display.statusBand
        metric.weeklyCurrentValue = display.weeklyCurrentValue
        return metric
    }
}
