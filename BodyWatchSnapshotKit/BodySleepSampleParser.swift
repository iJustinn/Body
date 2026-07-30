//
//  BodySleepSampleParser.swift
//  BodyWatchSnapshotKit
//
//  Single source of truth for turning raw HealthKit sleep samples into the
//  `SleepSummary` / `SleepStageSnapshot` the shared scorers consume, so sleep
//  parsing has one implementation that can't drift. The iOS
//  `HealthKitFetchEngine` / `HealthKitWorkoutStore` static helpers forward here.
//

import Foundation
import HealthKit

enum BodySleepSampleParser {
    /// A `SleepSummary` for one night's samples: merged asleep duration plus the
    /// staged snapshot. Returns `nil` when there's no asleep time.
    static func sleepSummary(
        from samples: [HKCategorySample],
        date: Date,
        showsSubMinuteAwakeStages: Bool = true,
        showsLeadingTrailingAwakeStages: Bool = true
    ) -> SleepSummary? {
        let duration = sleepDuration(from: samples)
        guard duration > 0 else {
            return nil
        }

        return SleepSummary(
            duration: duration,
            stageSnapshot: SleepStageSnapshot(
                date: date,
                segments: sleepStageSegments(
                    from: samples,
                    showsSubMinuteAwakeStages: showsSubMinuteAwakeStages,
                    showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages
                ),
                timeZoneIdentifier: timeZoneIdentifier(from: samples),
                mainSessionInterval: BodySleepSessionizer.mainSession(
                    in: BodySleepSessionizer.sessions(from: samples)
                )?.interval
            )
        )
    }

    /// The zone the night was recorded in (`HKMetadataKeyTimeZone`). A wake-day
    /// snapshot flattens every session of the day (naps included), so the zone
    /// comes from the main session only — a nap in another zone, even one whose
    /// single sample outlasts the main night's individual stage samples, must
    /// not label the night. Within the main session, per-zone asleep durations
    /// are aggregated so a detailed night split into short stage samples still
    /// outweighs any stray sample. `nil` when no main-session asleep sample
    /// carries the metadata.
    static func timeZoneIdentifier(from samples: [HKCategorySample]) -> String? {
        guard let mainSession = BodySleepSessionizer.mainSession(
            in: BodySleepSessionizer.sessions(from: samples)
        ) else {
            return nil
        }

        var durationByZone: [String: TimeInterval] = [:]
        for sample in mainSession.samples where isAsleep(sample) {
            guard let identifier = sample.metadata?[HKMetadataKeyTimeZone] as? String else {
                continue
            }
            durationByZone[identifier, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
        }

        return durationByZone.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }?.key
    }

    /// A sample belongs on the sleep timeline if it's an asleep stage or an
    /// explicit awake stage (not `.inBed` / unknown).
    static func isSleepTimelineSample(_ sample: HKCategorySample) -> Bool {
        isAsleep(sample) || sleepStage(for: sample, includeUnspecified: false) == .awake
    }

    static func sleepStageSegments(
        from samples: [HKCategorySample],
        showsSubMinuteAwakeStages: Bool = true,
        showsLeadingTrailingAwakeStages: Bool = true
    ) -> [SleepStageSegment] {
        let sourcedExplicitSegments = samples.compactMap { sample -> (segment: SleepStageSegment, sourceID: String)? in
            guard let stage = sleepStage(for: sample, includeUnspecified: false) else {
                return nil
            }
            if !showsSubMinuteAwakeStages,
               stage == .awake,
               sample.endDate.timeIntervalSince(sample.startDate) < 60 {
                return nil
            }

            return (
                segment: SleepStageSegment(
                    stage: stage,
                    startDate: sample.startDate,
                    endDate: sample.endDate
                ),
                sourceID: sleepSourceIdentityKey(for: sample)
            )
        }
        // Coverage for the aggregate fill stays the *raw* pre-arbitration
        // windows: a fragment dropped as a cross-source sliver is still time its
        // writer accounted for, so an overlapping `.asleepUnspecified` sample
        // must not read that window as uncovered and repaint it as `.core`.
        let explicitIntervals = sourcedExplicitSegments.map { sourced in
            (start: sourced.segment.startDate, end: sourced.segment.endDate)
        }
        let explicitSegments = dedupedExplicitSegments(sourcedExplicitSegments)

        // Aggregate samples are filled sequentially so two writers' overlapping
        // aggregates union into one core lane instead of double-painting it.
        var unspecifiedCoverage = explicitIntervals
        var unspecifiedSegments: [SleepStageSegment] = []
        let unspecifiedSamples = samples
            .filter(isUnspecifiedSleep)
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.endDate > rhs.endDate
            }
        for sample in unspecifiedSamples {
            let intervals = uncoveredSleepIntervals(
                in: (start: sample.startDate, end: sample.endDate),
                coveredBy: unspecifiedCoverage
            )
            for interval in intervals {
                unspecifiedSegments.append(
                    SleepStageSegment(stage: .core, startDate: interval.start, endDate: interval.end)
                )
                unspecifiedCoverage.append(interval)
            }
        }

        let sortedSegments = (explicitSegments + unspecifiedSegments)
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                if lhs.endDate != rhs.endDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.stage.chartPosition < rhs.stage.chartPosition
            }
        guard showsLeadingTrailingAwakeStages else {
            return trimmingAwakeOutsideSleepWindow(sortedSegments)
        }
        return sortedSegments
    }

    /// Identity of the writer behind a sample — bundle identifier plus folded
    /// name, matching `BodyHealthDataSourceOption.individualSourceIdentityKey` so
    /// arbitration buckets samples the same way the source picker does (bundle
    /// id alone collides: every third-party writer that syncs through Health
    /// shares `com.apple.health.<UUID>`-style ids per device).
    static func sleepSourceIdentityKey(for sample: HKCategorySample) -> String {
        let source = sample.sourceRevision.source
        let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Unknown Source" : trimmedName
        let nameKey = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return "bundle=\(source.bundleIdentifier)|name=\(nameKey)"
    }

    /// Resolves overlapping explicit-stage timelines from multiple writers into
    /// one timeline: the best-ranked source passes through whole, each lower
    /// ranked source contributes only the time no higher-ranked source already
    /// described. With fewer than two sources this is the identity, so
    /// single-source nights behave exactly as before.
    static func dedupedExplicitSegments(
        _ sourced: [(segment: SleepStageSegment, sourceID: String)]
    ) -> [SleepStageSegment] {
        var segmentsBySource: [String: [SleepStageSegment]] = [:]
        var sourceIDs: [String] = []
        for entry in sourced {
            if segmentsBySource[entry.sourceID] == nil {
                sourceIDs.append(entry.sourceID)
            }
            segmentsBySource[entry.sourceID, default: []].append(entry.segment)
        }

        guard sourceIDs.count > 1 else {
            return sourced.map(\.segment)
        }

        // Rank: stage-detailed writers first, then by union-merged asleep
        // coverage (union so duplicated samples earn no rank, asleep-only so
        // in-bed awake padding can't inflate it), then by id for determinism.
        var detailBySource: [String: Bool] = [:]
        var coverageBySource: [String: TimeInterval] = [:]
        for (sourceID, segments) in segmentsBySource {
            detailBySource[sourceID] = segments.contains { $0.stage == .rem || $0.stage == .deep }
            coverageBySource[sourceID] = mergedSleepDuration(
                intervals: segments
                    .filter { SleepStage.sleepStages.contains($0.stage) }
                    .map { (start: $0.startDate, end: $0.endDate) }
            )
        }
        let rankedSourceIDs = sourceIDs.sorted { lhs, rhs in
            if detailBySource[lhs] != detailBySource[rhs] {
                return detailBySource[lhs] == true
            }
            let lhsCoverage = coverageBySource[lhs] ?? 0
            let rhsCoverage = coverageBySource[rhs] ?? 0
            if lhsCoverage != rhsCoverage {
                return lhsCoverage > rhsCoverage
            }
            return lhs < rhs
        }

        var coverage: [(start: Date, end: Date)] = []
        var deduped: [SleepStageSegment] = []
        for sourceID in rankedSourceIDs {
            let segments = segmentsBySource[sourceID] ?? []
            for segment in segments {
                let uncoveredIntervals = uncoveredSleepIntervals(
                    in: (start: segment.startDate, end: segment.endDate),
                    coveredBy: coverage
                )
                let wasTrimmed = uncoveredIntervals.count != 1
                    || uncoveredIntervals[0].start != segment.startDate
                    || uncoveredIntervals[0].end != segment.endDate
                for interval in uncoveredIntervals {
                    // Clock skew between devices leaves sub-minute slivers at
                    // every boundary; only trimmed remnants are dropped, a
                    // segment that survived whole always stays.
                    if wasTrimmed,
                       interval.end.timeIntervalSince(interval.start) < minimumCrossSourceFragment {
                        continue
                    }
                    deduped.append(
                        SleepStageSegment(stage: segment.stage, startDate: interval.start, endDate: interval.end)
                    )
                }
            }
            // Coverage grows per source, not per segment, so a writer's own
            // overlapping samples never trim each other, and it includes the
            // writer's awake time: within its window a kept source is
            // authoritative for being awake too.
            coverage.append(contentsOf: segments.map { (start: $0.startDate, end: $0.endDate) })
        }
        return deduped
    }

    /// Drops `.awake` segments that fall entirely outside the asleep window
    /// (leading time in bed before sleep onset, trailing time awake before
    /// getting up), clamping any awake that straddles a boundary so it can't
    /// extend the timeline past real sleep. Interior awake (mid-night wake) is
    /// preserved. Defined by the sleep window rather than array edges so it stays
    /// correct when multi-source samples overlap. Returns `[]` when there's no
    /// asleep stage to anchor.
    static func trimmingAwakeOutsideSleepWindow(_ segments: [SleepStageSegment]) -> [SleepStageSegment] {
        let asleepSegments = segments.filter { SleepStage.sleepStages.contains($0.stage) }
        guard let windowStart = asleepSegments.map(\.startDate).min(),
              let windowEnd = asleepSegments.map(\.endDate).max() else {
            return []
        }

        return segments.compactMap { segment in
            guard segment.stage == .awake else {
                return segment
            }
            guard segment.endDate > windowStart, segment.startDate < windowEnd else {
                return nil
            }

            let clampedStart = max(segment.startDate, windowStart)
            let clampedEnd = min(segment.endDate, windowEnd)
            guard clampedEnd > clampedStart else {
                return nil
            }

            return SleepStageSegment(stage: .awake, startDate: clampedStart, endDate: clampedEnd)
        }
    }

    /// Total asleep time with overlapping/aggregate samples merged into their
    /// union, so multi-source or `asleep` aggregate samples don't double-count.
    static func sleepDuration(from samples: [HKCategorySample]) -> TimeInterval {
        mergedSleepDuration(
            intervals: samples
                .filter(isAsleep)
                .map { ($0.startDate, $0.endDate) }
        )
    }

    static func mergedSleepDuration(intervals: [(start: Date, end: Date)]) -> TimeInterval {
        let sortedIntervals = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        guard var current = sortedIntervals.first else {
            return 0
        }

        var duration: TimeInterval = 0

        for interval in sortedIntervals.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                duration += current.end.timeIntervalSince(current.start)
                current = interval
            }
        }

        duration += current.end.timeIntervalSince(current.start)
        return duration
    }

    /// Shortest remnant kept when one source's segment is trimmed against a
    /// better-ranked source's timeline.
    private static let minimumCrossSourceFragment: TimeInterval = 60

    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        default:
            return false
        }
    }

    private static func isUnspecifiedSleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleep, .asleepUnspecified:
            return true
        default:
            return false
        }
    }

    private static func uncoveredSleepIntervals(
        in interval: (start: Date, end: Date),
        coveredBy coverageIntervals: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        guard interval.end > interval.start else {
            return []
        }

        var uncoveredIntervals = [interval]
        let sortedCoverageIntervals = coverageIntervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        for coverageInterval in sortedCoverageIntervals {
            uncoveredIntervals = uncoveredIntervals.flatMap { uncoveredInterval in
                guard coverageInterval.start < uncoveredInterval.end,
                      coverageInterval.end > uncoveredInterval.start else {
                    return [uncoveredInterval]
                }

                var nextIntervals: [(start: Date, end: Date)] = []
                if coverageInterval.start > uncoveredInterval.start {
                    nextIntervals.append((
                        start: uncoveredInterval.start,
                        end: min(coverageInterval.start, uncoveredInterval.end)
                    ))
                }
                if coverageInterval.end < uncoveredInterval.end {
                    nextIntervals.append((
                        start: max(coverageInterval.end, uncoveredInterval.start),
                        end: uncoveredInterval.end
                    ))
                }
                return nextIntervals.filter { $0.end > $0.start }
            }

            if uncoveredIntervals.isEmpty {
                return []
            }
        }

        return uncoveredIntervals
    }

    private static func sleepStage(for sample: HKCategorySample, includeUnspecified: Bool) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .awake:
            return .awake
        case .asleepREM:
            return .rem
        case .asleepCore:
            return .core
        case .asleepDeep:
            return .deep
        case .asleep, .asleepUnspecified:
            return includeUnspecified ? .core : nil
        default:
            return nil
        }
    }
}
