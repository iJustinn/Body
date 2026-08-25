//
//  WorkoutRecordLedger.swift
//  Body
//

import Foundation

/// A metric a workout can hold an all-time, per-type personal record in.
///
/// Deliberately coarser than `WorkoutDetailMetric.Kind`: the three rate styles
/// (pace, speed, swim pace) collapse into a single `.rate` slot because a type has
/// exactly one of them, and a ledger keyed by the style would fragment the cohort
/// if a type's `paceStyle` ever changed.
enum WorkoutRecordMetric: String, Codable, CaseIterable {
    case duration
    case distance
    case rate
    case elevation
}

// Lets `[WorkoutRecordMetric: Double]` encode as a JSON object keyed by the raw
// values rather than the flat key/value array Swift uses for non-string keys —
// the stdlib supplies the implementation for string-raw enums.
extension WorkoutRecordMetric: CodingKeyRepresentable {}

extension WorkoutRecordMetric {
    /// The detail metric this record reads its scalar from, or nil for `.duration`
    /// (which has no detail tile — it lives in the hero header).
    func detailKind(for type: BodyWorkoutType) -> WorkoutDetailMetric.Kind? {
        switch self {
        case .duration:
            return nil
        case .distance:
            return .distance
        case .elevation:
            return .elevation
        case .rate:
            switch type.paceStyle {
            case .distancePace: return .pace
            case .speed: return .speed
            case .swimPace: return .swimPace
            case .none: return nil
            }
        }
    }

    /// Whether a smaller value is the better one. Pace and swim pace are seconds per
    /// meter, so faster reads lower; everything else is bigger-is-better.
    func isLowerBetter(for type: BodyWorkoutType) -> Bool {
        guard self == .rate else { return false }
        switch type.paceStyle {
        case .distancePace, .swimPace: return true
        case .speed, .none: return false
        }
    }

    /// The record catalog for a workout type.
    ///
    /// Every type tracks duration. Distance follows `promotesDistanceToHero` — the
    /// paced activities plus snow sports. Rate exists wherever `paceStyle` does.
    /// Elevation is enumerated explicitly rather than derived, because "climbs
    /// meaningfully" is not the same question as "has a pace tile".
    static func metrics(for type: BodyWorkoutType) -> [WorkoutRecordMetric] {
        var metrics: [WorkoutRecordMetric] = [.duration]
        if type.promotesDistanceToHero {
            metrics.append(.distance)
        }
        if type.paceStyle != .none {
            metrics.append(.rate)
        }
        if elevationEligibleTypes.contains(type) {
            metrics.append(.elevation)
        }
        return metrics
    }

    /// Types whose ascent is a record worth holding: the paced land activities and
    /// the snow sports. Swimming is excluded — it has a pace, but no vertical.
    static let elevationEligibleTypes: Set<BodyWorkoutType> = [
        // .distancePace
        .walking, .running, .hiking, .wheelchairWalkPace, .wheelchairRunPace,
        // .speed
        .cycling, .handCycling,
        // snow sports
        .snowSports, .crossCountrySkiing, .downhillSkiing, .snowboarding
    ]
}

/// How a workout relates to a metric's all-time record: it holds it now, or it held
/// it once and a later workout has since taken it.
enum WorkoutRecordStanding: Equatable {
    case current
    case former
}

/// One workout's comparable values, stored rather than its wins — winners are derived,
/// so a deletion or a late-arriving distance repairs the record instead of stranding it.
struct WorkoutRecordContribution: Codable, Equatable {
    let typeRaw: String
    let startDate: Date
    /// Only the metrics that produced a valid scalar; an absent key means "no value",
    /// never "zero".
    let values: [WorkoutRecordMetric: Double]

    init(workout: WorkoutSummary) {
        typeRaw = workout.type.rawValue
        startDate = workout.startDate
        var values: [WorkoutRecordMetric: Double] = [:]
        for metric in WorkoutRecordMetric.metrics(for: workout.type) {
            if let value = WorkoutRecordContribution.scalar(metric, for: workout) {
                values[metric] = value
            }
        }
        self.values = values
    }

    /// Reuses `WorkoutMetricComparisonBuilder.scalar` so records inherit its finite,
    /// positive-only guards and its distance floors (400 m, or 100 m for swim pace) —
    /// a 50 m pool length can't become an all-time pace record. Duration has no detail
    /// kind, so it gets the same finite/positive guard applied directly.
    private static func scalar(_ metric: WorkoutRecordMetric, for workout: WorkoutSummary) -> Double? {
        if metric == .duration {
            guard workout.duration.isFinite, workout.duration > 0 else { return nil }
            return workout.duration
        }
        guard let kind = metric.detailKind(for: workout.type) else { return nil }
        return WorkoutMetricComparisonBuilder.scalar(for: kind, from: workout)
    }
}

/// The all-time personal-record ledger: every workout's contribution, plus a derived
/// index of who currently holds each per-type record.
struct WorkoutRecordLedger: Codable {
    /// Bump when the stored shape changes; a mismatch on load discards and rescans.
    static let currentSchemaVersion = 1

    /// A record only becomes visible once the type has this many contributors for the
    /// metric — being "the best of two" is not an achievement.
    static let minimumCohortSize = 4

    /// A *former* record needs this many same-type contributions before it, mirroring
    /// the cohort rule: beating the two workouts that happen to precede you is not a
    /// record worth remembering, so early sparse history earns no faded trophies.
    static let minimumFormerPredecessors = 3

    private(set) var schemaVersion: Int
    private(set) var contributions: [UUID: WorkoutRecordContribution]
    /// How far back the baseline scan has reached, so a cancelled scan resumes.
    var scannedThrough: Date?
    /// Records stay hidden until the whole history has been folded in — a partial scan
    /// would crown the most recent workout in every metric.
    var baselineComplete: Bool

    /// Derived, never encoded: holder and cohort size per type per metric.
    private var index: [String: [WorkoutRecordMetric: Holder]] = [:]

    private struct Holder {
        var id: UUID
        var startDate: Date
        var value: Double
        var count: Int
        /// Workouts that held this record when they happened and have since been
        /// beaten. Never contains `id`.
        var formerIds: Set<UUID> = []
    }

    /// One contribution's comparable value for a single metric — the unit both the
    /// holder walk and the former-holder walk compare.
    private struct Entry {
        var id: UUID
        var startDate: Date
        var value: Double
    }

    init() {
        schemaVersion = Self.currentSchemaVersion
        contributions = [:]
        scannedThrough = nil
        baselineComplete = false
    }

    // MARK: - Mutation

    /// Recomputes and replaces this workout's contribution. Idempotent by construction,
    /// so re-upserting a workout whose distance arrived late repairs the record.
    mutating func upsert(_ workout: WorkoutSummary) {
        contributions[workout.id] = WorkoutRecordContribution(workout: workout)
        rebuildIndex()
    }

    /// Batch twin of `upsert(_:)` above: folds every workout's contribution in
    /// first and rebuilds the index once at the end, instead of once per
    /// workout. `rebuildIndex` traverses and sorts every accumulated
    /// contribution, so calling the single-workout upsert in a loop over N
    /// workouts costs O(N²); this costs O(N). Produces the identical index —
    /// `rebuildIndex` only ever reads the final `contributions`, never the
    /// order they arrived in.
    mutating func upsert(_ workouts: [WorkoutSummary]) {
        guard !workouts.isEmpty else { return }
        for workout in workouts {
            contributions[workout.id] = WorkoutRecordContribution(workout: workout)
        }
        rebuildIndex()
    }

    mutating func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            contributions.removeValue(forKey: id)
        }
        rebuildIndex()
    }

    // MARK: - Reads

    /// How this workout stands in each of its type's record metrics.
    ///
    /// A metric is absent unless the workout either holds the all-time record now
    /// (`.current`) or held it when it happened and has since been beaten (`.former`).
    /// Empty until `baselineComplete`, and empty for any metric whose same-type cohort
    /// is smaller than `minimumCohortSize`.
    func recordStandings(for workout: WorkoutSummary) -> [WorkoutRecordMetric: WorkoutRecordStanding] {
        guard baselineComplete else { return [:] }
        guard let holders = index[workout.type.rawValue] else { return [:] }
        var standings: [WorkoutRecordMetric: WorkoutRecordStanding] = [:]
        for metric in WorkoutRecordMetric.metrics(for: workout.type) {
            guard let holder = holders[metric], holder.count >= Self.minimumCohortSize else {
                continue
            }
            if holder.id == workout.id {
                standings[metric] = .current
            } else if holder.formerIds.contains(workout.id) {
                standings[metric] = .former
            }
        }
        return standings
    }

    /// The metrics this workout currently holds the all-time record in.
    ///
    /// Empty until `baselineComplete`, and empty for any metric whose same-type cohort
    /// is smaller than `minimumCohortSize`.
    func records(for workout: WorkoutSummary) -> Set<WorkoutRecordMetric> {
        Set(recordStandings(for: workout).compactMap { $0.value == .current ? $0.key : nil })
    }

    // MARK: - Index

    /// Rebuilt on every mutation and after decoding, so reads are O(1) and neither the
    /// winner nor the former-holder chain depends on the order contributions arrived in.
    ///
    /// Each metric's entries are walked in chronological order carrying a running best:
    /// that running maximum under the total order below IS the all-time holder, and
    /// every entry that displaces it was the record at the moment it happened — which
    /// is exactly the set of former holders, minus the one still standing.
    private mutating func rebuildIndex() {
        var grouped: [String: [WorkoutRecordMetric: [Entry]]] = [:]
        for (id, contribution) in contributions {
            guard BodyWorkoutType(rawValue: contribution.typeRaw) != nil else { continue }
            for (metric, value) in contribution.values {
                grouped[contribution.typeRaw, default: [:]][metric, default: []]
                    .append(Entry(id: id, startDate: contribution.startDate, value: value))
            }
        }

        var index: [String: [WorkoutRecordMetric: Holder]] = [:]
        for (typeRaw, metrics) in grouped {
            guard let type = BodyWorkoutType(rawValue: typeRaw) else { continue }
            for (metric, entries) in metrics {
                guard let first = entries.first else { continue }
                let lowerIsBetter = metric.isLowerBetter(for: type)
                // Same ordering the tie-break uses, so "earlier" here and "wins a tie"
                // there can never disagree.
                let ordered = entries.sorted(by: Self.precedes)

                var best = first
                var formerIds: Set<UUID> = []
                for (position, entry) in ordered.enumerated() {
                    if position == 0 {
                        best = entry
                        continue
                    }
                    guard Self.beats(entry, best, lowerIsBetter: lowerIsBetter) else { continue }
                    // `position` is how many same-type contributions for this metric
                    // precede it, so this is the cohort rule applied at its own moment.
                    if position >= Self.minimumFormerPredecessors {
                        formerIds.insert(entry.id)
                    }
                    best = entry
                }
                formerIds.remove(best.id)

                index[typeRaw, default: [:]][metric] = Holder(
                    id: best.id,
                    startDate: best.startDate,
                    value: best.value,
                    count: ordered.count,
                    formerIds: formerIds
                )
            }
        }
        self.index = index
    }

    /// Chronological order with the tie-break's own tail: earlier start date, then
    /// lower UUID string.
    private static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Strictly better wins; an exact tie falls to the earlier workout, then to the
    /// lower UUID string — a total order, so the holder is independent of insertion
    /// order and of where a resumed scan picked up.
    private static func beats(_ lhs: Entry, _ rhs: Entry, lowerIsBetter: Bool) -> Bool {
        if lhs.value != rhs.value {
            return lowerIsBetter ? lhs.value < rhs.value : lhs.value > rhs.value
        }
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case contributions
        case scannedThrough
        case baselineComplete
    }

    /// `contributions` persists as an array sorted by UUID string: a dictionary keyed by
    /// UUID encodes in hash order, which is not stable across launches and would defeat
    /// byte-comparison dedupe on write.
    private struct StoredContribution: Codable {
        let id: UUID
        let contribution: WorkoutRecordContribution

        enum CodingKeys: String, CodingKey {
            case id
            case typeRaw
            case startDate
            case values
        }

        init(id: UUID, contribution: WorkoutRecordContribution) {
            self.id = id
            self.contribution = contribution
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            contribution = try WorkoutRecordContribution(from: decoder)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try contribution.encode(to: encoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        scannedThrough = try container.decodeIfPresent(Date.self, forKey: .scannedThrough)
        baselineComplete = try container.decode(Bool.self, forKey: .baselineComplete)
        let stored = try container.decode([StoredContribution].self, forKey: .contributions)
        contributions = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.contribution) })
        rebuildIndex()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(scannedThrough, forKey: .scannedThrough)
        try container.encode(baselineComplete, forKey: .baselineComplete)
        let stored = contributions
            .map { StoredContribution(id: $0.key, contribution: $0.value) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        try container.encode(stored, forKey: .contributions)
    }
}
