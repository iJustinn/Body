import Foundation

/// Invalidates queued publications without making the main actor wait for IO.
/// Writes already admitted retain FIFO order on the shared persistence queue.
final class HealthDashboardPublicationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true

    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        valid = false
    }
}

/// Provenance, not freshness: a matching key permits stale-on-failure reuse;
/// only a successful query may advance the existing freshness watermarks.
/// Encoded in the dashboard's existing atomic summary-context field.
struct HealthDashboardCacheScope: Codable, Equatable {
    struct Source: Codable, Equatable {
        var request: String
        var members: [String]?
    }

    var version = 1
    var primary: [String: Source]
    var secondary: [String: Source]
    var aggregation: String
    var sleepGoal: TimeInterval
    var computeVersion = 1

    static func key(_ parts: [String]) -> String {
        // Arrays are ordered; sortedKeys also makes nested scope encoding stable.
        String(decoding: try! JSONEncoder().encode(parts), as: UTF8.self)
    }

    var signature: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(self), as: UTF8.self)
    }

    init?(signature: String?) {
        guard let signature, let data = signature.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data),
              decoded.version == 1 else { return nil }
        self = decoded
    }

    init(
        primary: [String: Source], secondary: [String: Source],
        aggregation: String, sleepGoal: TimeInterval
    ) {
        self.primary = primary
        self.secondary = secondary
        self.aggregation = aggregation
        self.sleepGoal = sleepGoal
    }

    /// Per-kind raw identity. Hourly cumulative samples are calendar buckets;
    /// instantaneous samples retain their identity when the timezone changes.
    func rawSignatures(secondary comparison: Bool = false) -> [String: String] {
        (comparison ? secondary : primary).mapValues { source in
            Self.key([source.request, source.members.map { Self.key($0) } ?? "unresolved"])
        }.map { kind, value in
            (kind, [HealthMetricKind.steps.rawValue, HealthMetricKind.activeEnergy.rawValue].contains(kind)
                ? Self.key([value, aggregation]) : value)
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    static let leafKinds = Array(HealthMetricQueryDescriptor.all.keys) + [.sleep, .trainingLoad]
    static let sleepVitalKinds: Set<HealthMetricKind> = [
        .heartRate, .heartRateVariability, .respiratoryRate, .oxygenSaturation, .wristTemperature
    ]

    /// Clears incompatible *recomputable* fields. Frozen observations stay on
    /// disk with their original context; source changes retire their context so
    /// the existing calculators apply their established reset policy. A zone
    /// change never retires a frozen-observation context.
    func scoping(_ snapshot: HealthDashboardSnapshot, from old: Self?) -> HealthDashboardSnapshot {
        var next = snapshot
        var changed = Set<HealthMetricKind>()
        var sourceChanged = Set<HealthMetricKind>()
        for kind in Self.leafKinds {
            let raw = kind.rawValue
            let sameSource = old?.primary[raw] == primary[raw] && old?.primary[raw] != nil
            if !sameSource || old?.aggregation != aggregation {
                changed.insert(kind)
                if old?.primary[raw] != nil, !sameSource { sourceChanged.insert(kind) }
                next.summary = next.summary.replacingMetric(kind, with: .empty)
                next.trends = next.trends.replacingMetric(kind, with: .empty)
            }
            // replacingMetric also replaces comparisons. Restore only the
            // comparison whose own provenance still matches.
            let comparisonMatches = old?.secondary[raw] == secondary[raw]
                && old?.secondary[raw] != nil && old?.aggregation == aggregation
            Self.copyComparison(kind, from: comparisonMatches ? snapshot.trends : .empty, to: &next.trends)
        }

        // Sleep carries readings queried through five OTHER source selections.
        // Invalidating HRV must not retain A's nocturnal HRV inside B's sleep
        // history, nor discard the still-valid sleep duration and stages.
        let changedVitals = Self.sleepVitalKinds.filter {
            old?.primary[$0.rawValue] != primary[$0.rawValue] || old == nil
        }
        if !changedVitals.isEmpty {
            Self.stripVitals(&next.summary.sleep.vitals, kinds: changedVitals)
            next.trends.sleepHistory = SleepHistorySnapshot(days: next.trends.sleepHistory.days.map { day in
                var day = day
                Self.stripVitals(&day.summary.vitals, kinds: changedVitals)
                return day
            })
            changed.insert(.sleep)
        }

        // Raw samples are scoped independently of daily series, preserving
        // compatible intraday data during aggregate-only invalidation.
        let raw = HealthTrendDaySampleSnapshot(trends: snapshot.trends)
            .scopedByMetricSignatures(
                capturedPrimary: old?.rawSignatures(), capturedSecondary: old?.rawSignatures(secondary: true),
                currentPrimary: rawSignatures(), currentSecondary: rawSignatures(secondary: true)
            )
        next.trends = next.trends.strippingDaySamples().mergingMissingDaySamples(from: raw)

        if !changed.isDisjoint(with: HealthKitWorkoutStore.readinessInputMetricKinds)
            || old?.sleepGoal != sleepGoal || old?.computeVersion != computeVersion {
            next.summary.readiness = .unavailable
            next.trends.readiness = .empty
        }
        if !changed.isDisjoint(with: HealthKitWorkoutStore.stressInputMetricKinds) {
            next.summary.stress = nil
            next.summary.stressCurrentScore = nil
            next.trends.stress = .empty
            next.trends.stressRanges = .empty
        }
        if !changed.isDisjoint(with: HealthKitWorkoutStore.bodyRadarSignedSourceKinds) {
            next.summary.bodyRadar = nil
        }
        if !sourceChanged.isDisjoint(with: HealthKitWorkoutStore.readinessInputMetricKinds) {
            next.trends.recordedReadinessContext = "invalidated source context"
        }
        if !sourceChanged.isDisjoint(with: HealthKitWorkoutStore.stressInputMetricKinds) {
            next.trends.recordedStressContext = "invalidated source context"
        }
        if !sourceChanged.isDisjoint(with: HealthKitWorkoutStore.bodyRadarSignedSourceKinds) {
            next.trends.recordedBodyRadarContext = "invalidated source context"
        }
        return next
    }

    private static func stripVitals(_ vitals: inout SleepVitalsSummary, kinds: Set<HealthMetricKind>) {
        if kinds.contains(.heartRate) { vitals.heartRate = nil }
        if kinds.contains(.heartRateVariability) { vitals.heartRateVariability = nil }
        if kinds.contains(.respiratoryRate) { vitals.respiratoryRate = nil }
        if kinds.contains(.oxygenSaturation) { vitals.oxygenSaturation = nil }
        if kinds.contains(.wristTemperature) { vitals.wristTemperatureCelsius = nil }
    }

    private static func copyComparison(_ kind: HealthMetricKind, from source: HealthTrendSnapshot, to target: inout HealthTrendSnapshot) {
        switch kind {
        case .sleep:
            target.sleepSecondary = source.sleepSecondary
            target.sleepHistorySecondary = source.sleepHistorySecondary
        case .heartRate: target.heartRateRangesSecondary = source.heartRateRangesSecondary
        case .heartRateVariability: target.heartRateVariabilityRangesSecondary = source.heartRateVariabilityRangesSecondary
        case .restingHeartRate: target.restingHeartRateSecondary = source.restingHeartRateSecondary
        case .oxygenSaturation: target.oxygenSaturationRangesSecondary = source.oxygenSaturationRangesSecondary
        case .activeEnergy: target.activeEnergySecondary = source.activeEnergySecondary
        case .restingEnergy: target.restingEnergySecondary = source.restingEnergySecondary
        case .exerciseMinutes: target.exerciseMinutesSecondary = source.exerciseMinutesSecondary
        case .steps: target.stepsSecondary = source.stepsSecondary
        default: break
        }
    }
}
