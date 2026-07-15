//
//  BodySleepSessionizer.swift
//  BodyWatchSnapshotKit
//
//  Groups raw HealthKit sleep samples into contiguous sleep sessions so a night
//  that begins before midnight is attributed to the calendar day it *ended*
//  (the "wake day") rather than being split across two days by per-sample
//  `startOfDay(endDate)` bucketing. Shared by Body + BodyWatch so iOS and the
//  watch attribute sleep the same way.
//

import Foundation
import HealthKit

enum BodySleepSessionizer {
    /// Maximum gap between the latest end seen so far and the next sample's
    /// start for them to belong to the same session. Sleep that resumes within
    /// two hours is treated as one continuous night; a longer break starts a new
    /// session (a separate nap or the next night).
    static let maximumSessionGap: TimeInterval = 2 * 60 * 60

    /// One contiguous sleep episode: the timeline samples that fall within it,
    /// its overall span, and its merged asleep duration.
    struct SleepSession {
        var samples: [HKCategorySample]
        /// Earliest sample start in the session.
        var start: Date
        /// Latest sample end in the session (the running `maxEndSoFar`).
        var end: Date
        /// Merged asleep duration (overlaps unioned), reusing the shared parser.
        var asleepDuration: TimeInterval

        /// The session span, used to bound its nocturnal-vitals window. `nil`
        /// for a zero-length span (degenerate all-instantaneous samples).
        var interval: DateInterval? {
            guard end > start else {
                return nil
            }
            return DateInterval(start: start, end: end)
        }
    }

    /// Splits samples into sessions: a session extends while the next sample
    /// begins within `maximumSessionGap` of the latest end seen so far, so
    /// overlapping (multi-source) and briefly-interrupted samples stay in one
    /// night. Samples are sorted ascending by start first.
    static func sessions(from samples: [HKCategorySample]) -> [SleepSession] {
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }

        var sessions: [SleepSession] = []
        var currentSamples: [HKCategorySample] = []
        var currentStart = Date.distantPast
        var currentEnd = Date.distantPast

        for sample in sortedSamples {
            guard !currentSamples.isEmpty else {
                currentSamples = [sample]
                currentStart = sample.startDate
                currentEnd = sample.endDate
                continue
            }

            if sample.startDate.timeIntervalSince(currentEnd) <= maximumSessionGap {
                currentSamples.append(sample)
                currentEnd = max(currentEnd, sample.endDate)
            } else {
                sessions.append(makeSession(currentSamples, start: currentStart, end: currentEnd))
                currentSamples = [sample]
                currentStart = sample.startDate
                currentEnd = sample.endDate
            }
        }

        if !currentSamples.isEmpty {
            sessions.append(makeSession(currentSamples, start: currentStart, end: currentEnd))
        }

        return sessions
    }

    /// Sessions grouped by the calendar day their sleep ends
    /// (`startOfDay(session.end)`) — the wake day the whole night is attributed
    /// to, so a night that begins before midnight lands entirely on the morning
    /// it ended instead of being split across two calendar days.
    static func sessionsByWakeDay(
        from samples: [HKCategorySample],
        calendar: Calendar
    ) -> [Date: [SleepSession]] {
        Dictionary(grouping: sessions(from: samples)) { session in
            calendar.startOfDay(for: session.end)
        }
    }

    /// The session with the longest merged asleep duration — the main night —
    /// used to bound the nocturnal-vitals window so an afternoon nap on the same
    /// wake day can't stretch it across the whole day. Ties resolve to the later
    /// session.
    static func mainSession(in sessions: [SleepSession]) -> SleepSession? {
        sessions.max { lhs, rhs in
            if lhs.asleepDuration == rhs.asleepDuration {
                return lhs.end < rhs.end
            }
            return lhs.asleepDuration < rhs.asleepDuration
        }
    }

    private static func makeSession(
        _ samples: [HKCategorySample],
        start: Date,
        end: Date
    ) -> SleepSession {
        SleepSession(
            samples: samples,
            start: start,
            end: end,
            asleepDuration: BodySleepSampleParser.sleepDuration(from: samples)
        )
    }
}
