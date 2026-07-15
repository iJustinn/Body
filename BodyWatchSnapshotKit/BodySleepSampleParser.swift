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
                )
            )
        )
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
        let explicitSegments = samples.compactMap { sample -> SleepStageSegment? in
            guard let stage = sleepStage(for: sample, includeUnspecified: false) else {
                return nil
            }
            if !showsSubMinuteAwakeStages,
               stage == .awake,
               sample.endDate.timeIntervalSince(sample.startDate) < 60 {
                return nil
            }

            return SleepStageSegment(
                stage: stage,
                startDate: sample.startDate,
                endDate: sample.endDate
            )
        }
        let explicitIntervals = explicitSegments.map { segment in
            (start: segment.startDate, end: segment.endDate)
        }
        let unspecifiedSegments = samples.flatMap { sample -> [SleepStageSegment] in
            guard isUnspecifiedSleep(sample) else {
                return []
            }

            return uncoveredSleepIntervals(
                in: (start: sample.startDate, end: sample.endDate),
                coveredBy: explicitIntervals
            )
            .map { interval in
                SleepStageSegment(stage: .core, startDate: interval.start, endDate: interval.end)
            }
        }

        let sortedSegments = (explicitSegments + unspecifiedSegments)
            .sorted { $0.startDate < $1.startDate }
        guard showsLeadingTrailingAwakeStages else {
            return trimmingAwakeOutsideSleepWindow(sortedSegments)
        }
        return sortedSegments
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
