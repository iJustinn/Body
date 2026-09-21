import Foundation

/// One local clock day laid along the Day Ring. Every position (hour ticks, activity
/// spans, the now marker and the percentage) comes from `fraction(of:)`, elapsed time
/// over the day's real length, so they still agree on a 23 or 25 hour DST day.
struct DayRingTimeline: Equatable {
    enum Activity: Equatable {
        case sleep
        case workout(BodyWorkoutType)
    }

    /// A stretch of the outer ring owned by one activity, as fractions of the day.
    struct Span: Equatable {
        let start: Double
        let end: Double
        let activity: Activity
    }

    /// A real local hour instant. A skipped DST hour has none, a repeated one has two.
    struct HourTick: Equatable {
        let hour: Int
        let fraction: Double
    }

    /// Local midnight to the next local midnight, half open.
    let day: DateInterval
    /// Non overlapping and sorted. Where activities overlap a workout beats sleep,
    /// and among workouts the later start wins.
    let spans: [Span]
    let hourTicks: [HourTick]
    let nowFraction: Double
    /// Asleep time inside the day, from the merged asleep segments, so awake breaks inside
    /// the one sleep bar are not counted. Not read from `spans`.
    let sleepDuration: TimeInterval
    /// Unique workouts touching the day. Not read from `spans`.
    let workoutCount: Int

    var percentPassed: Int {
        Int((nowFraction * 100).rounded(.down))
    }

    func fraction(of date: Date) -> Double {
        Self.fraction(of: date, in: day)
    }

    static func fraction(of date: Date, in day: DateInterval) -> Double {
        guard day.duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(day.start) / day.duration, 0), 1)
    }

    /// What the ring needs of a workout, so the watch can lay out the ones the phone
    /// publishes without a full `WorkoutSummary`.
    struct Workout: Equatable {
        let id: UUID
        let start: Date
        let end: Date
        let type: BodyWorkoutType
    }

    static func make(
        now: Date,
        calendar: Calendar,
        sleepSegments: [SleepStageSegment],
        mainSleepInterval: DateInterval? = nil,
        workouts: [WorkoutSummary]
    ) -> DayRingTimeline {
        make(
            now: now,
            calendar: calendar,
            sleepSegments: sleepSegments,
            mainSleepInterval: mainSleepInterval,
            ringWorkouts: workouts.map { Workout(id: $0.id, start: $0.startDate, end: $0.effectiveEndDate, type: $0.type) }
        )
    }

    static func make(
        now: Date,
        calendar: Calendar,
        sleepSegments: [SleepStageSegment],
        mainSleepInterval: DateInterval? = nil,
        ringWorkouts workouts: [Workout]
    ) -> DayRingTimeline {
        let day = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)

        let asleep = mergedAsleepIntervals(sleepSegments, in: day)
        // The ring draws the night as one bar, start to end, awake breaks included.
        let sleepBar = (mainSleepInterval ?? longestSleepSession(sleepSegments))
            .flatMap { clip(start: $0.start, end: $0.end, to: day) }

        var seenWorkouts = Set<UUID>()
        let dayWorkouts = workouts
            .filter { $0.start < day.end && $0.end > day.start && seenWorkouts.insert($0.id).inserted }
            .sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }

        return DayRingTimeline(
            day: day,
            spans: renderSpans(sleep: sleepBar.map { [$0] } ?? [], workouts: dayWorkouts, in: day),
            hourTicks: makeHourTicks(in: day, calendar: calendar),
            nowFraction: fraction(of: now, in: day),
            sleepDuration: asleep.reduce(0) { $0 + $1.duration },
            workoutCount: dayWorkouts.count
        )
    }

    /// Asleep stages only, each clipped to the day before merging, so awake breaks and
    /// unrecorded gaps inside a session stay empty and overlapping samples count once.
    private static func mergedAsleepIntervals(_ segments: [SleepStageSegment], in day: DateInterval) -> [DateInterval] {
        let clipped = segments
            .filter { SleepStage.sleepStages.contains($0.stage) }
            .compactMap { clip(start: $0.startDate, end: $0.endDate, to: day) }
            .sorted { $0.start < $1.start }

        var merged: [DateInterval] = []
        for interval in clipped {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// Stand in for a snapshot saved before it recorded its main session: the longest run
    /// of asleep segments with no break over two hours, the sessionizer's own rule.
    private static func longestSleepSession(_ segments: [SleepStageSegment]) -> DateInterval? {
        let asleep = segments
            .filter { SleepStage.sleepStages.contains($0.stage) && $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }

        var sessions: [DateInterval] = []
        for segment in asleep {
            if let last = sessions.last, segment.startDate.timeIntervalSince(last.end) <= 2 * 3600 {
                sessions[sessions.count - 1] = DateInterval(start: last.start, end: max(last.end, segment.endDate))
            } else {
                sessions.append(DateInterval(start: segment.startDate, end: segment.endDate))
            }
        }
        return sessions.max { $0.duration < $1.duration }
    }

    private static func clip(start: Date, end: Date, to day: DateInterval) -> DateInterval? {
        let clippedStart = max(start, day.start)
        let clippedEnd = min(end, day.end)
        return clippedEnd > clippedStart ? DateInterval(start: clippedStart, end: clippedEnd) : nil
    }

    /// `workouts` arrive sorted by (start, id), so the last one covering a stretch is
    /// its owner whatever order the caller had them in.
    private static func renderSpans(sleep: [DateInterval], workouts: [Workout], in day: DateInterval) -> [Span] {
        let workoutIntervals = workouts.compactMap { workout in
            clip(start: workout.start, end: workout.end, to: day).map { (interval: $0, type: workout.type) }
        }
        let boundaries = Set(sleep.flatMap { [$0.start, $0.end] } + workoutIntervals.flatMap { [$0.interval.start, $0.interval.end] })
            .sorted()

        var result: [Span] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let covers: (DateInterval) -> Bool = { $0.start <= start && $0.end >= end }
            let activity: Activity
            if let workout = workoutIntervals.last(where: { covers($0.interval) }) {
                activity = .workout(workout.type)
            } else if sleep.contains(where: covers) {
                activity = .sleep
            } else {
                continue
            }

            let startFraction = fraction(of: start, in: day)
            let endFraction = fraction(of: end, in: day)
            if let last = result.last, last.activity == activity, last.end == startFraction {
                result[result.count - 1] = Span(start: last.start, end: endFraction, activity: activity)
            } else {
                result.append(Span(start: startFraction, end: endFraction, activity: activity))
            }
        }
        return result
    }

    private static func makeHourTicks(in day: DateInterval, calendar: Calendar) -> [HourTick] {
        var ticks = [HourTick(hour: calendar.component(.hour, from: day.start), fraction: 0)]
        var cursor = day.start
        // Real instants an hour apart, so a DST day simply yields 23 or 25 of them.
        while let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next < day.end {
            ticks.append(HourTick(hour: calendar.component(.hour, from: next), fraction: fraction(of: next, in: day)))
            cursor = next
        }
        return ticks
    }
}

/// The part of the day the Day Ring's page glow is colored for.
enum DayRingDayPart: Equatable {
    case morning
    case noon
    case afternoon
    case night

    init(hour: Int) {
        switch hour {
        case 5..<11:
            self = .morning
        case 11..<14:
            self = .noon
        case 14..<18:
            self = .afternoon
        default:
            self = .night
        }
    }
}
