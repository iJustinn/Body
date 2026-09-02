//
//  HealthTrend.swift
//  Body
//

import Foundation

/// The atomic readiness inputs that were present when a score was computed.
/// Coverage is compared as a set so a frozen morning record can be replaced by a
/// later, strictly richer one when a single input (e.g. HRV) syncs late — the
/// component kinds (`.autonomic`/`.sleep`/`.vitals`) stay identical in that case,
/// so they cannot detect the change (H11). Derived from the snapshot fields that
/// feed `ReadinessScoreCalculator`.
struct ReadinessCoverage: OptionSet, Hashable, Codable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let hrv = ReadinessCoverage(rawValue: 1 << 0)
    static let restingHeartRate = ReadinessCoverage(rawValue: 1 << 1)
    static let sleepDuration = ReadinessCoverage(rawValue: 1 << 2)
    static let sleepContinuity = ReadinessCoverage(rawValue: 1 << 3)
    static let trainingLoad = ReadinessCoverage(rawValue: 1 << 4)
    static let respiratoryRate = ReadinessCoverage(rawValue: 1 << 5)
    static let oxygenSaturation = ReadinessCoverage(rawValue: 1 << 6)
    static let wristTemperature = ReadinessCoverage(rawValue: 1 << 7)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A frozen daily readiness record: the morning score (captured ~10 min after
/// wake) that the history charts display. Immune to later intra-day changes.
struct RecordedReadinessEntry: Codable, Equatable {
    var date: Date   // calendar.startOfDay of the recorded day
    var score: Int
    var includedSleep: Bool? = nil   // nil = legacy record (pre-flag), unknown
    var coverage: ReadinessCoverage? = nil   // nil = legacy record (pre-coverage)
}

struct HealthTrendSnapshot: Codable, Equatable {
    var sleep: HealthTrendSeries
    var sleepSecondary: HealthTrendSeries
    var readiness: HealthTrendSeries
    var heartRate: HealthTrendSeries
    var heartRateRanges: HealthTrendRangeSeries
    var heartRateRangesSecondary: HealthTrendRangeSeries
    var restingHeartRate: HealthTrendSeries
    var restingHeartRateSecondary: HealthTrendSeries
    var bodyMass: HealthTrendSeries
    var bodyFatPercentage: HealthTrendSeries
    var heartRateVariability: HealthTrendSeries
    var heartRateVariabilityRanges: HealthTrendRangeSeries
    var heartRateVariabilityRangesSecondary: HealthTrendRangeSeries
    var respiratoryRate: HealthTrendSeries
    var respiratoryRateRanges: HealthTrendRangeSeries
    var oxygenSaturation: HealthTrendSeries
    var oxygenSaturationRanges: HealthTrendRangeSeries
    var oxygenSaturationRangesSecondary: HealthTrendRangeSeries
    var bodyMassIndex: HealthTrendSeries
    var activeEnergy: HealthTrendSeries
    var activeEnergySecondary: HealthTrendSeries
    var restingEnergy: HealthTrendSeries
    var restingEnergySecondary: HealthTrendSeries
    var exerciseMinutes: HealthTrendSeries
    var exerciseMinutesSecondary: HealthTrendSeries
    var trainingLoad: HealthTrendSeries
    var wristTemperature: HealthTrendSeries
    var timeInDaylight: HealthTrendSeries
    var steps: HealthTrendSeries
    var stepsSecondary: HealthTrendSeries
    var cardioFitness: HealthTrendSeries
    var stress: HealthTrendSeries
    /// Daily intraday min/max envelope of the day's scored 15-minute windows,
    /// derived from `recordedStressDays` — see `recalculatingStress`. Renders
    /// as the range band behind the average-score line in the detail chart.
    var stressRanges: HealthTrendRangeSeries
    var sleepHistory: SleepHistorySnapshot
    var sleepHistorySecondary: SleepHistorySnapshot
    var heartRateDaySamples: HealthTrendSeries
    var heartRateDaySamplesSecondary: HealthTrendSeries
    var restingHeartRateDaySamples: HealthTrendSeries
    var restingHeartRateDaySamplesSecondary: HealthTrendSeries
    var heartRateVariabilityDaySamples: HealthTrendSeries
    var heartRateVariabilityDaySamplesSecondary: HealthTrendSeries
    /// RMSSD computed from `HKHeartbeatSeriesSample` beat-to-beat intervals, one
    /// point per series. Fetched under the HRV metric's source selection, so it
    /// rides the same day-sample scope stamps as the SDNN series. No comparison
    /// counterpart: the metric is never a secondary-source chart.
    var heartbeatRMSSDDaySamples: HealthTrendSeries
    var respiratoryRateDaySamples: HealthTrendSeries
    var oxygenSaturationDaySamples: HealthTrendSeries
    var oxygenSaturationDaySamplesSecondary: HealthTrendSeries
    var activeEnergyDaySamples: HealthTrendSeries
    var activeEnergyDaySamplesSecondary: HealthTrendSeries
    var stepsDaySamples: HealthTrendSeries
    var stepsDaySamplesSecondary: HealthTrendSeries
    /// Per-day stress rollups, each carrying the day's quiet-HR and RMSSD
    /// medians so the baselines outlive the ~32-day day-sample cache. Persisted
    /// in the MAIN snapshot (day samples are stripped from it on save), which is
    /// why the baseline aggregates live here rather than in the sidecar.
    var recordedStressDays: [StressDaySummary]
    /// Signature of the Stress input context (enabled stress permissions and the
    /// primary source per stress input kind) under which `recordedStressDays`
    /// was captured. Its own field rather than the readiness one: the two
    /// metrics read different inputs, so a change to one must not drop the
    /// other's records (see `recalculatingStress`).
    var recordedStressContext: String
    /// Exclusive end (start-of-day) of the range the progressive Stress history
    /// backfill has already walked. `nil` means it has never run, so the walk
    /// starts at its horizon. Cleared alongside `recordedStressDays` when the
    /// record context changes, so a permission or source switch rescans.
    var stressBackfillScannedThrough: Date?
    /// True once the backfill has walked from its horizon up to the live
    /// computed window, which the per-refresh recompute keeps current from then
    /// on. Stops the scan from restarting on every launch.
    var stressBackfillComplete: Bool
    /// Per-day frozen "morning" readiness records (captured ~10 min after wake).
    /// The charts read these; later intra-day drain never touches them. Carried
    /// forward across refreshes (see HealthKitFetchEngine.fetchHealthTrends).
    var recordedReadiness: [RecordedReadinessEntry]
    /// Signature of the readiness input context (enabled readiness permissions,
    /// the primary source per readiness input kind, and source grouping) under
    /// which `recordedReadiness` was captured. When the live context no longer
    /// matches, the records are dropped so a recompute under the new inputs is
    /// authoritative (see `recalculatingReadiness`). Persisted with the records,
    /// so a context change is still detected after a failed refresh or relaunch.
    var recordedReadinessContext: String

    static let empty = HealthTrendSnapshot(
        sleep: .empty,
        sleepSecondary: .empty,
        readiness: .empty,
        heartRate: .empty,
        heartRateRanges: .empty,
        heartRateRangesSecondary: .empty,
        restingHeartRate: .empty,
        restingHeartRateSecondary: .empty,
        bodyMass: .empty,
        bodyFatPercentage: .empty,
        heartRateVariability: .empty,
        heartRateVariabilityRanges: .empty,
        heartRateVariabilityRangesSecondary: .empty,
        respiratoryRate: .empty,
        respiratoryRateRanges: .empty,
        oxygenSaturation: .empty,
        oxygenSaturationRanges: .empty,
        oxygenSaturationRangesSecondary: .empty,
        bodyMassIndex: .empty,
        activeEnergy: .empty,
        activeEnergySecondary: .empty,
        restingEnergy: .empty,
        restingEnergySecondary: .empty,
        exerciseMinutes: .empty,
        exerciseMinutesSecondary: .empty,
        trainingLoad: .empty,
        wristTemperature: .empty,
        timeInDaylight: .empty,
        steps: .empty,
        stepsSecondary: .empty,
        cardioFitness: .empty,
        stress: .empty,
        stressRanges: .empty,
        sleepHistory: .empty,
        sleepHistorySecondary: .empty,
        heartRateDaySamples: .empty,
        heartRateDaySamplesSecondary: .empty,
        restingHeartRateDaySamples: .empty,
        restingHeartRateDaySamplesSecondary: .empty,
        heartRateVariabilityDaySamples: .empty,
        heartRateVariabilityDaySamplesSecondary: .empty,
        heartbeatRMSSDDaySamples: .empty,
        respiratoryRateDaySamples: .empty,
        oxygenSaturationDaySamples: .empty,
        oxygenSaturationDaySamplesSecondary: .empty,
        activeEnergyDaySamples: .empty,
        activeEnergyDaySamplesSecondary: .empty,
        stepsDaySamples: .empty,
        stepsDaySamplesSecondary: .empty,
        recordedStressDays: [],
        recordedStressContext: "",
        stressBackfillScannedThrough: nil,
        stressBackfillComplete: false,
        recordedReadiness: [],
        recordedReadinessContext: ""
    )

    var isEmpty: Bool {
        sleep.isEmpty &&
            sleepSecondary.isEmpty &&
            readiness.isEmpty &&
            heartRate.isEmpty &&
            heartRateRanges.isEmpty &&
            heartRateRangesSecondary.isEmpty &&
            restingHeartRate.isEmpty &&
            restingHeartRateSecondary.isEmpty &&
            bodyMass.isEmpty &&
            bodyFatPercentage.isEmpty &&
            heartRateVariability.isEmpty &&
            heartRateVariabilityRanges.isEmpty &&
            heartRateVariabilityRangesSecondary.isEmpty &&
            respiratoryRate.isEmpty &&
            respiratoryRateRanges.isEmpty &&
            oxygenSaturation.isEmpty &&
            oxygenSaturationRanges.isEmpty &&
            oxygenSaturationRangesSecondary.isEmpty &&
            bodyMassIndex.isEmpty &&
            activeEnergy.isEmpty &&
            activeEnergySecondary.isEmpty &&
            restingEnergy.isEmpty &&
            restingEnergySecondary.isEmpty &&
            exerciseMinutes.isEmpty &&
            exerciseMinutesSecondary.isEmpty &&
            trainingLoad.isEmpty &&
            wristTemperature.isEmpty &&
            timeInDaylight.isEmpty &&
            steps.isEmpty &&
            stepsSecondary.isEmpty &&
            cardioFitness.isEmpty &&
            stress.isEmpty &&
            stressRanges.isEmpty &&
            sleepHistory.isEmpty &&
            sleepHistorySecondary.isEmpty &&
            heartRateDaySamples.isEmpty &&
            heartRateDaySamplesSecondary.isEmpty &&
            restingHeartRateDaySamples.isEmpty &&
            restingHeartRateDaySamplesSecondary.isEmpty &&
            heartRateVariabilityDaySamples.isEmpty &&
            heartRateVariabilityDaySamplesSecondary.isEmpty &&
            heartbeatRMSSDDaySamples.isEmpty &&
            respiratoryRateDaySamples.isEmpty &&
            oxygenSaturationDaySamples.isEmpty &&
            oxygenSaturationDaySamplesSecondary.isEmpty &&
            activeEnergyDaySamples.isEmpty &&
            activeEnergyDaySamplesSecondary.isEmpty &&
            stepsDaySamples.isEmpty &&
            stepsDaySamplesSecondary.isEmpty &&
            recordedStressDays.isEmpty &&
            recordedReadiness.isEmpty
    }

    init(
        sleep: HealthTrendSeries,
        sleepSecondary: HealthTrendSeries = .empty,
        readiness: HealthTrendSeries = .empty,
        heartRate: HealthTrendSeries = .empty,
        heartRateRanges: HealthTrendRangeSeries = .empty,
        heartRateRangesSecondary: HealthTrendRangeSeries = .empty,
        restingHeartRate: HealthTrendSeries,
        restingHeartRateSecondary: HealthTrendSeries = .empty,
        bodyMass: HealthTrendSeries,
        bodyFatPercentage: HealthTrendSeries,
        heartRateVariability: HealthTrendSeries,
        heartRateVariabilityRanges: HealthTrendRangeSeries = .empty,
        heartRateVariabilityRangesSecondary: HealthTrendRangeSeries = .empty,
        respiratoryRate: HealthTrendSeries,
        respiratoryRateRanges: HealthTrendRangeSeries = .empty,
        oxygenSaturation: HealthTrendSeries,
        oxygenSaturationRanges: HealthTrendRangeSeries = .empty,
        oxygenSaturationRangesSecondary: HealthTrendRangeSeries = .empty,
        bodyMassIndex: HealthTrendSeries,
        activeEnergy: HealthTrendSeries,
        activeEnergySecondary: HealthTrendSeries = .empty,
        restingEnergy: HealthTrendSeries,
        restingEnergySecondary: HealthTrendSeries = .empty,
        exerciseMinutes: HealthTrendSeries = .empty,
        exerciseMinutesSecondary: HealthTrendSeries = .empty,
        trainingLoad: HealthTrendSeries = .empty,
        wristTemperature: HealthTrendSeries = .empty,
        timeInDaylight: HealthTrendSeries = .empty,
        steps: HealthTrendSeries = .empty,
        stepsSecondary: HealthTrendSeries = .empty,
        cardioFitness: HealthTrendSeries = .empty,
        stress: HealthTrendSeries = .empty,
        stressRanges: HealthTrendRangeSeries = .empty,
        sleepHistory: SleepHistorySnapshot = .empty,
        sleepHistorySecondary: SleepHistorySnapshot = .empty,
        heartRateDaySamples: HealthTrendSeries = .empty,
        heartRateDaySamplesSecondary: HealthTrendSeries = .empty,
        restingHeartRateDaySamples: HealthTrendSeries = .empty,
        restingHeartRateDaySamplesSecondary: HealthTrendSeries = .empty,
        heartRateVariabilityDaySamples: HealthTrendSeries = .empty,
        heartRateVariabilityDaySamplesSecondary: HealthTrendSeries = .empty,
        heartbeatRMSSDDaySamples: HealthTrendSeries = .empty,
        respiratoryRateDaySamples: HealthTrendSeries = .empty,
        oxygenSaturationDaySamples: HealthTrendSeries = .empty,
        oxygenSaturationDaySamplesSecondary: HealthTrendSeries = .empty,
        activeEnergyDaySamples: HealthTrendSeries = .empty,
        activeEnergyDaySamplesSecondary: HealthTrendSeries = .empty,
        stepsDaySamples: HealthTrendSeries = .empty,
        stepsDaySamplesSecondary: HealthTrendSeries = .empty,
        recordedStressDays: [StressDaySummary] = [],
        recordedStressContext: String = "",
        stressBackfillScannedThrough: Date? = nil,
        stressBackfillComplete: Bool = false,
        recordedReadiness: [RecordedReadinessEntry] = [],
        recordedReadinessContext: String = ""
    ) {
        self.sleep = sleep
        self.sleepSecondary = sleepSecondary
        self.readiness = readiness
        self.heartRate = heartRate
        self.heartRateRanges = heartRateRanges
        self.heartRateRangesSecondary = heartRateRangesSecondary
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateSecondary = restingHeartRateSecondary
        self.bodyMass = bodyMass
        self.bodyFatPercentage = bodyFatPercentage
        self.heartRateVariability = heartRateVariability
        self.heartRateVariabilityRanges = heartRateVariabilityRanges
        self.heartRateVariabilityRangesSecondary = heartRateVariabilityRangesSecondary
        self.respiratoryRate = respiratoryRate
        self.respiratoryRateRanges = respiratoryRateRanges
        self.oxygenSaturation = oxygenSaturation
        self.oxygenSaturationRanges = oxygenSaturationRanges
        self.oxygenSaturationRangesSecondary = oxygenSaturationRangesSecondary
        self.bodyMassIndex = bodyMassIndex
        self.activeEnergy = activeEnergy
        self.activeEnergySecondary = activeEnergySecondary
        self.restingEnergy = restingEnergy
        self.restingEnergySecondary = restingEnergySecondary
        self.exerciseMinutes = exerciseMinutes
        self.exerciseMinutesSecondary = exerciseMinutesSecondary
        self.trainingLoad = trainingLoad
        self.wristTemperature = wristTemperature
        self.timeInDaylight = timeInDaylight
        self.steps = steps
        self.stepsSecondary = stepsSecondary
        self.cardioFitness = cardioFitness
        self.stress = stress
        self.stressRanges = stressRanges
        self.sleepHistory = sleepHistory
        self.sleepHistorySecondary = sleepHistorySecondary
        self.heartRateDaySamples = heartRateDaySamples
        self.heartRateDaySamplesSecondary = heartRateDaySamplesSecondary
        self.restingHeartRateDaySamples = restingHeartRateDaySamples
        self.restingHeartRateDaySamplesSecondary = restingHeartRateDaySamplesSecondary
        self.heartRateVariabilityDaySamples = heartRateVariabilityDaySamples
        self.heartRateVariabilityDaySamplesSecondary = heartRateVariabilityDaySamplesSecondary
        self.heartbeatRMSSDDaySamples = heartbeatRMSSDDaySamples
        self.respiratoryRateDaySamples = respiratoryRateDaySamples
        self.oxygenSaturationDaySamples = oxygenSaturationDaySamples
        self.oxygenSaturationDaySamplesSecondary = oxygenSaturationDaySamplesSecondary
        self.activeEnergyDaySamples = activeEnergyDaySamples
        self.activeEnergyDaySamplesSecondary = activeEnergyDaySamplesSecondary
        self.stepsDaySamples = stepsDaySamples
        self.stepsDaySamplesSecondary = stepsDaySamplesSecondary
        self.recordedStressDays = recordedStressDays
        self.recordedStressContext = recordedStressContext
        self.stressBackfillScannedThrough = stressBackfillScannedThrough
        self.stressBackfillComplete = stressBackfillComplete
        self.recordedReadiness = recordedReadiness
        self.recordedReadinessContext = recordedReadinessContext
    }

    private enum CodingKeys: String, CodingKey {
        case sleep
        case sleepSecondary
        case readiness
        case heartRate
        case heartRateRanges
        case heartRateRangesSecondary
        case restingHeartRate
        case restingHeartRateSecondary
        case bodyMass
        case bodyFatPercentage
        case heartRateVariability
        case heartRateVariabilityRanges
        case heartRateVariabilityRangesSecondary
        case respiratoryRate
        case respiratoryRateRanges
        case oxygenSaturation
        case oxygenSaturationRanges
        case oxygenSaturationRangesSecondary
        case bodyMassIndex
        case activeEnergy
        case activeEnergySecondary
        case restingEnergy
        case restingEnergySecondary
        case exerciseMinutes
        case exerciseMinutesSecondary
        case trainingLoad
        case wristTemperature
        case timeInDaylight
        case steps
        case stepsSecondary
        case cardioFitness
        case stress
        case stressRanges
        case sleepHistory
        case sleepHistorySecondary
        case heartRateDaySamples
        case heartRateDaySamplesSecondary
        case restingHeartRateDaySamples
        case restingHeartRateDaySamplesSecondary
        case heartRateVariabilityDaySamples
        case heartRateVariabilityDaySamplesSecondary
        case heartbeatRMSSDDaySamples
        case respiratoryRateDaySamples
        case oxygenSaturationDaySamples
        case oxygenSaturationDaySamplesSecondary
        case activeEnergyDaySamples
        case activeEnergyDaySamplesSecondary
        case stepsDaySamples
        case stepsDaySamplesSecondary
        case recordedStressDays
        case recordedStressContext
        case stressBackfillScannedThrough
        case stressBackfillComplete
        case recordedReadiness
        case recordedReadinessContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sleep = try container.decode(HealthTrendSeries.self, forKey: .sleep)
        sleepSecondary = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .sleepSecondary) ?? .empty
        readiness = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .readiness) ?? .empty
        heartRate = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .heartRate) ?? .empty
        heartRateRanges = try container.decodeIfPresent(HealthTrendRangeSeries.self, forKey: .heartRateRanges) ?? .empty
        heartRateRangesSecondary = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .heartRateRangesSecondary
        ) ?? .empty
        restingHeartRate = try container.decode(HealthTrendSeries.self, forKey: .restingHeartRate)
        restingHeartRateSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingHeartRateSecondary
        ) ?? .empty
        bodyMass = try container.decode(HealthTrendSeries.self, forKey: .bodyMass)
        bodyFatPercentage = try container.decode(HealthTrendSeries.self, forKey: .bodyFatPercentage)
        heartRateVariability = try container.decode(HealthTrendSeries.self, forKey: .heartRateVariability)
        heartRateVariabilityRanges = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .heartRateVariabilityRanges
        ) ?? .empty
        heartRateVariabilityRangesSecondary = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .heartRateVariabilityRangesSecondary
        ) ?? .empty
        respiratoryRate = try container.decode(HealthTrendSeries.self, forKey: .respiratoryRate)
        respiratoryRateRanges = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .respiratoryRateRanges
        ) ?? .empty
        oxygenSaturation = try container.decode(HealthTrendSeries.self, forKey: .oxygenSaturation)
        oxygenSaturationRanges = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .oxygenSaturationRanges
        ) ?? .empty
        oxygenSaturationRangesSecondary = try container.decodeIfPresent(
            HealthTrendRangeSeries.self,
            forKey: .oxygenSaturationRangesSecondary
        ) ?? .empty
        bodyMassIndex = try container.decode(HealthTrendSeries.self, forKey: .bodyMassIndex)
        activeEnergy = try container.decode(HealthTrendSeries.self, forKey: .activeEnergy)
        activeEnergySecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .activeEnergySecondary
        ) ?? .empty
        restingEnergy = try container.decode(HealthTrendSeries.self, forKey: .restingEnergy)
        restingEnergySecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingEnergySecondary
        ) ?? .empty
        exerciseMinutes = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .exerciseMinutes) ?? .empty
        exerciseMinutesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .exerciseMinutesSecondary
        ) ?? .empty
        trainingLoad = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .trainingLoad) ?? .empty
        wristTemperature = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .wristTemperature) ?? .empty
        timeInDaylight = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .timeInDaylight) ?? .empty
        steps = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .steps) ?? .empty
        stepsSecondary = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .stepsSecondary) ?? .empty
        cardioFitness = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .cardioFitness) ?? .empty
        stress = try container.decodeIfPresent(HealthTrendSeries.self, forKey: .stress) ?? .empty
        stressRanges = try container.decodeIfPresent(HealthTrendRangeSeries.self, forKey: .stressRanges) ?? .empty
        sleepHistory = try container.decodeIfPresent(SleepHistorySnapshot.self, forKey: .sleepHistory) ?? .empty
        sleepHistorySecondary = try container.decodeIfPresent(
            SleepHistorySnapshot.self,
            forKey: .sleepHistorySecondary
        ) ?? .empty
        heartRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateDaySamples
        ) ?? .empty
        heartRateDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateDaySamplesSecondary
        ) ?? .empty
        restingHeartRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingHeartRateDaySamples
        ) ?? .empty
        restingHeartRateDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .restingHeartRateDaySamplesSecondary
        ) ?? .empty
        heartRateVariabilityDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateVariabilityDaySamples
        ) ?? .empty
        heartRateVariabilityDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartRateVariabilityDaySamplesSecondary
        ) ?? .empty
        heartbeatRMSSDDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .heartbeatRMSSDDaySamples
        ) ?? .empty
        respiratoryRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .respiratoryRateDaySamples
        ) ?? .empty
        oxygenSaturationDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .oxygenSaturationDaySamples
        ) ?? .empty
        oxygenSaturationDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .oxygenSaturationDaySamplesSecondary
        ) ?? .empty
        activeEnergyDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .activeEnergyDaySamples
        ) ?? .empty
        activeEnergyDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .activeEnergyDaySamplesSecondary
        ) ?? .empty
        stepsDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .stepsDaySamples
        ) ?? .empty
        stepsDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self,
            forKey: .stepsDaySamplesSecondary
        ) ?? .empty
        recordedStressDays = try container.decodeIfPresent(
            [StressDaySummary].self,
            forKey: .recordedStressDays
        ) ?? []
        recordedStressContext = try container.decodeIfPresent(
            String.self,
            forKey: .recordedStressContext
        ) ?? ""
        stressBackfillScannedThrough = try container.decodeIfPresent(
            Date.self,
            forKey: .stressBackfillScannedThrough
        )
        stressBackfillComplete = try container.decodeIfPresent(
            Bool.self,
            forKey: .stressBackfillComplete
        ) ?? false
        recordedReadiness = try container.decodeIfPresent(
            [RecordedReadinessEntry].self,
            forKey: .recordedReadiness
        ) ?? []
        recordedReadinessContext = try container.decodeIfPresent(
            String.self,
            forKey: .recordedReadinessContext
        ) ?? ""
    }

    func series(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .readiness:
            return readiness
        case .stress:
            return stress
        case .sleep:
            return sleep
        case .basics:
            return .empty
        case .heartRate:
            return heartRate
        case .restingHeartRate:
            return restingHeartRate
        case .bodyMass:
            return bodyMass
        case .bodyFatPercentage:
            return bodyFatPercentage
        case .heartRateVariability:
            return heartRateVariability
        case .respiratoryRate:
            return respiratoryRate
        case .oxygenSaturation:
            return oxygenSaturation
        case .bodyMassIndex:
            return bodyMassIndex
        case .activeEnergy:
            return activeEnergy
        case .restingEnergy:
            return restingEnergy
        case .exerciseMinutes:
            return exerciseMinutes
        case .trainingLoad:
            return trainingLoad
        case .wristTemperature:
            return wristTemperature
        case .timeInDaylight:
            return timeInDaylight
        case .steps:
            return steps
        case .cardioFitness:
            return cardioFitness
        case .vitals:
            return .empty
        }
    }

    func secondarySeries(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .sleep:
            return sleepSecondary
        case .restingHeartRate:
            return restingHeartRateSecondary
        case .activeEnergy:
            return activeEnergySecondary
        case .restingEnergy:
            return restingEnergySecondary
        case .exerciseMinutes:
            return exerciseMinutesSecondary
        case .steps:
            return stepsSecondary
        case .basics,
             .readiness,
             .heartRate,
             .bodyMass,
             .bodyFatPercentage,
             .heartRateVariability,
             .respiratoryRate,
             .oxygenSaturation,
             .bodyMassIndex,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .vitals,
             .cardioFitness,
             .stress:
            return .empty
        }
    }

    func rangeSeries(for kind: HealthMetricKind) -> HealthTrendRangeSeries {
        switch kind {
        case .heartRate:
            return heartRateRanges
        case .heartRateVariability:
            return heartRateVariabilityRanges
        case .respiratoryRate:
            return respiratoryRateRanges
        case .oxygenSaturation:
            return oxygenSaturationRanges
        case .stress:
            return stressRanges
        case .sleep,
             .readiness,
             .basics,
             .restingHeartRate,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .steps,
             .vitals,
             .cardioFitness:
            return .empty
        }
    }

    func secondaryRangeSeries(for kind: HealthMetricKind) -> HealthTrendRangeSeries {
        switch kind {
        case .heartRate:
            return heartRateRangesSecondary
        case .heartRateVariability:
            return heartRateVariabilityRangesSecondary
        case .oxygenSaturation:
            return oxygenSaturationRangesSecondary
        case .sleep,
             .readiness,
             .basics,
             .restingHeartRate,
             .bodyMass,
             .bodyFatPercentage,
             .respiratoryRate,
             .bodyMassIndex,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .steps,
             .vitals,
             .cardioFitness,
             .stress:
            return .empty
        }
    }

    func daySeries(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .heartRate:
            return heartRateDaySamples
        case .restingHeartRate:
            return restingHeartRateDaySamples
        case .heartRateVariability:
            return heartRateVariabilityDaySamples
        case .respiratoryRate:
            return respiratoryRateDaySamples
        case .oxygenSaturation:
            return oxygenSaturationDaySamples
        case .activeEnergy:
            return activeEnergyDaySamples
        case .steps:
            return stepsDaySamples
        case .sleep,
             .readiness,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .vitals,
             .cardioFitness,
             .stress:
            return .empty
        }
    }

    func secondaryDaySeries(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .heartRate:
            return heartRateDaySamplesSecondary
        case .restingHeartRate:
            return restingHeartRateDaySamplesSecondary
        case .heartRateVariability:
            return heartRateVariabilityDaySamplesSecondary
        case .oxygenSaturation:
            return oxygenSaturationDaySamplesSecondary
        case .activeEnergy:
            return activeEnergyDaySamplesSecondary
        case .steps:
            return stepsDaySamplesSecondary
        case .sleep,
             .readiness,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .respiratoryRate,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .vitals,
             .cardioFitness,
             .stress:
            return .empty
        }
    }

    func replacingMetric(_ kind: HealthMetricKind, with refreshed: HealthTrendSnapshot) -> HealthTrendSnapshot {
        var next = self

        switch kind {
        case .readiness:
            next.readiness = refreshed.readiness
        case .stress:
            next.stress = refreshed.stress
            next.stressRanges = refreshed.stressRanges
            next.recordedStressDays = refreshed.recordedStressDays
            next.recordedStressContext = refreshed.recordedStressContext
        case .sleep:
            next.sleep = refreshed.sleep
            next.sleepSecondary = refreshed.sleepSecondary
            next.sleepHistory = refreshed.sleepHistory
            next.sleepHistorySecondary = refreshed.sleepHistorySecondary
        case .basics:
            next.bodyMass = refreshed.bodyMass
            next.bodyFatPercentage = refreshed.bodyFatPercentage
            next.bodyMassIndex = refreshed.bodyMassIndex
        case .heartRate:
            next.heartRate = refreshed.heartRate
            next.heartRateRanges = refreshed.heartRateRanges
            next.heartRateRangesSecondary = refreshed.heartRateRangesSecondary
            next.heartRateDaySamples = refreshed.heartRateDaySamples
            next.heartRateDaySamplesSecondary = refreshed.heartRateDaySamplesSecondary
        case .restingHeartRate:
            next.restingHeartRate = refreshed.restingHeartRate
            next.restingHeartRateSecondary = refreshed.restingHeartRateSecondary
            next.restingHeartRateDaySamples = refreshed.restingHeartRateDaySamples
            next.restingHeartRateDaySamplesSecondary = refreshed.restingHeartRateDaySamplesSecondary
        case .bodyMass:
            next.bodyMass = refreshed.bodyMass
        case .bodyFatPercentage:
            next.bodyFatPercentage = refreshed.bodyFatPercentage
        case .heartRateVariability:
            next.heartRateVariability = refreshed.heartRateVariability
            next.heartRateVariabilityRanges = refreshed.heartRateVariabilityRanges
            next.heartRateVariabilityRangesSecondary = refreshed.heartRateVariabilityRangesSecondary
            next.heartRateVariabilityDaySamples = refreshed.heartRateVariabilityDaySamples
            next.heartRateVariabilityDaySamplesSecondary = refreshed.heartRateVariabilityDaySamplesSecondary
        case .respiratoryRate:
            next.respiratoryRate = refreshed.respiratoryRate
            next.respiratoryRateRanges = refreshed.respiratoryRateRanges
            next.respiratoryRateDaySamples = refreshed.respiratoryRateDaySamples
        case .oxygenSaturation:
            next.oxygenSaturation = refreshed.oxygenSaturation
            next.oxygenSaturationRanges = refreshed.oxygenSaturationRanges
            next.oxygenSaturationRangesSecondary = refreshed.oxygenSaturationRangesSecondary
            next.oxygenSaturationDaySamples = refreshed.oxygenSaturationDaySamples
            next.oxygenSaturationDaySamplesSecondary = refreshed.oxygenSaturationDaySamplesSecondary
        case .bodyMassIndex:
            next.bodyMassIndex = refreshed.bodyMassIndex
        case .activeEnergy:
            next.activeEnergy = refreshed.activeEnergy
            next.activeEnergySecondary = refreshed.activeEnergySecondary
            next.activeEnergyDaySamples = refreshed.activeEnergyDaySamples
            next.activeEnergyDaySamplesSecondary = refreshed.activeEnergyDaySamplesSecondary
        case .restingEnergy:
            next.restingEnergy = refreshed.restingEnergy
            next.restingEnergySecondary = refreshed.restingEnergySecondary
        case .exerciseMinutes:
            next.exerciseMinutes = refreshed.exerciseMinutes
            next.exerciseMinutesSecondary = refreshed.exerciseMinutesSecondary
        case .trainingLoad:
            next.trainingLoad = refreshed.trainingLoad
        case .wristTemperature:
            next.wristTemperature = refreshed.wristTemperature
        case .timeInDaylight:
            next.timeInDaylight = refreshed.timeInDaylight
        case .steps:
            next.steps = refreshed.steps
            next.stepsSecondary = refreshed.stepsSecondary
            next.stepsDaySamples = refreshed.stepsDaySamples
            next.stepsDaySamplesSecondary = refreshed.stepsDaySamplesSecondary
        case .vitals:
            next.sleep = refreshed.sleep
            next.sleepSecondary = refreshed.sleepSecondary
            next.sleepHistory = refreshed.sleepHistory
            next.sleepHistorySecondary = refreshed.sleepHistorySecondary
        case .cardioFitness:
            next.cardioFitness = refreshed.cardioFitness
        }

        return next
    }

    var readinessSourceSeries: [HealthTrendSeries] {
        [
            heartRateVariability,
            restingHeartRate,
            sleep,
            trainingLoad,
            respiratoryRate,
            oxygenSaturation,
            wristTemperature
        ]
    }

    func filtered(by selection: BodyHealthPermissionSelection) -> HealthTrendSnapshot {
        var filtered = self

        // Strips a per-night vitals field from every cached sleep-history day
        // so a disabled permission can't keep driving readiness via the
        // overnight series in `ReadinessScoreCalculator` (mirrors the same
        // fields being nil'd on `HealthSummarySnapshot.filtered`'s current-day
        // sleep summary).
        func strippingSleepVitals(
            _ history: SleepHistorySnapshot,
            _ mutate: (inout SleepVitalsSummary) -> Void
        ) -> SleepHistorySnapshot {
            SleepHistorySnapshot(days: history.days.map { day in
                var day = day
                mutate(&day.summary.vitals)
                return day
            })
        }

        if !selection.includes(.sleep) {
            filtered.sleep = .empty
            filtered.sleepSecondary = .empty
            filtered.sleepHistory = .empty
            filtered.sleepHistorySecondary = .empty
        }
        if !selection.includes(.heart) {
            filtered.heartRate = .empty
            filtered.heartRateRanges = .empty
            filtered.heartRateRangesSecondary = .empty
            filtered.restingHeartRate = .empty
            filtered.restingHeartRateSecondary = .empty
            filtered.heartRateVariability = .empty
            filtered.heartRateVariabilityRanges = .empty
            filtered.heartRateVariabilityRangesSecondary = .empty
            filtered.heartRateDaySamples = .empty
            filtered.heartRateDaySamplesSecondary = .empty
            filtered.restingHeartRateDaySamples = .empty
            filtered.restingHeartRateDaySamplesSecondary = .empty
            filtered.heartRateVariabilityDaySamples = .empty
            filtered.heartRateVariabilityDaySamplesSecondary = .empty
            // Stress is heart-derived end to end (quiet HR + HRV), so the
            // recorded days go too — otherwise the baselines they carry would
            // survive the permission being turned off.
            filtered.heartbeatRMSSDDaySamples = .empty
            filtered.stress = .empty
            filtered.stressRanges = .empty
            filtered.recordedStressDays = []
            // The backfill's marker describes the records just dropped above —
            // leaving it set (especially `stressBackfillComplete`) would permanently
            // block the walk from rescanning once Heart is re-enabled, because the
            // context signature it resumes under is unchanged (mirrors the same
            // reset in `HealthDashboardSnapshot.recalculatingStress`).
            filtered.stressBackfillScannedThrough = nil
            filtered.stressBackfillComplete = false
            filtered.sleepHistory = strippingSleepVitals(filtered.sleepHistory) {
                $0.heartRate = nil
                $0.heartRateVariability = nil
            }
            filtered.sleepHistorySecondary = strippingSleepVitals(filtered.sleepHistorySecondary) {
                $0.heartRate = nil
                $0.heartRateVariability = nil
            }
        }
        if !selection.includes(.basics) {
            filtered.bodyMass = .empty
            filtered.bodyFatPercentage = .empty
            filtered.bodyMassIndex = .empty
        }
        if !selection.includes(.bloodOxygen) {
            filtered.oxygenSaturation = .empty
            filtered.oxygenSaturationRanges = .empty
            filtered.oxygenSaturationRangesSecondary = .empty
            filtered.oxygenSaturationDaySamples = .empty
            filtered.oxygenSaturationDaySamplesSecondary = .empty
            filtered.sleepHistory = strippingSleepVitals(filtered.sleepHistory) {
                $0.oxygenSaturation = nil
            }
            filtered.sleepHistorySecondary = strippingSleepVitals(filtered.sleepHistorySecondary) {
                $0.oxygenSaturation = nil
            }
        }
        if !selection.includes(.respiratory) {
            filtered.respiratoryRate = .empty
            filtered.respiratoryRateRanges = .empty
            filtered.respiratoryRateDaySamples = .empty
            filtered.sleepHistory = strippingSleepVitals(filtered.sleepHistory) {
                $0.respiratoryRate = nil
            }
            filtered.sleepHistorySecondary = strippingSleepVitals(filtered.sleepHistorySecondary) {
                $0.respiratoryRate = nil
            }
        }
        if !selection.includes(.energy) {
            filtered.activeEnergy = .empty
            filtered.activeEnergySecondary = .empty
            filtered.activeEnergyDaySamples = .empty
            filtered.activeEnergyDaySamplesSecondary = .empty
            filtered.restingEnergy = .empty
            filtered.restingEnergySecondary = .empty
        }
        if !selection.includes(.exerciseMinutes) {
            filtered.exerciseMinutes = .empty
            filtered.exerciseMinutesSecondary = .empty
        }
        if !selection.includes(.workouts) {
            filtered.trainingLoad = .empty
        }
        if !selection.includes(.wristTemperature) {
            filtered.wristTemperature = .empty
            filtered.sleepHistory = strippingSleepVitals(filtered.sleepHistory) {
                $0.wristTemperatureCelsius = nil
            }
            filtered.sleepHistorySecondary = strippingSleepVitals(filtered.sleepHistorySecondary) {
                $0.wristTemperatureCelsius = nil
            }
        }
        if !selection.includes(.timeInDaylight) {
            filtered.timeInDaylight = .empty
        }
        if !selection.includes(.steps) {
            filtered.steps = .empty
            filtered.stepsSecondary = .empty
            filtered.stepsDaySamples = .empty
            filtered.stepsDaySamplesSecondary = .empty
        }
        if !selection.includes(.cardioFitness) {
            filtered.cardioFitness = .empty
        }

        return filtered
    }

    func clearingSecondarySeries() -> HealthTrendSnapshot {
        var cleared = self
        cleared.sleepSecondary = .empty
        cleared.sleepHistorySecondary = .empty
        cleared.heartRateRangesSecondary = .empty
        cleared.heartRateDaySamplesSecondary = .empty
        cleared.restingHeartRateSecondary = .empty
        cleared.restingHeartRateDaySamplesSecondary = .empty
        cleared.heartRateVariabilityRangesSecondary = .empty
        cleared.heartRateVariabilityDaySamplesSecondary = .empty
        cleared.oxygenSaturationRangesSecondary = .empty
        cleared.oxygenSaturationDaySamplesSecondary = .empty
        cleared.activeEnergySecondary = .empty
        cleared.activeEnergyDaySamplesSecondary = .empty
        cleared.restingEnergySecondary = .empty
        cleared.exerciseMinutesSecondary = .empty
        cleared.stepsSecondary = .empty
        cleared.stepsDaySamplesSecondary = .empty
        return cleared
    }

    /// The lazily loaded intraday sample series are by far the largest part of
    /// the persisted snapshot (tens of thousands of raw points once a metric
    /// detail view has been opened). `HealthDashboardSnapshotStore` persists
    /// them in a sidecar file so the launch-critical main decode stays small;
    /// the sidecar is decoded off the main actor after the first frame.
    func strippingDaySamples() -> HealthTrendSnapshot {
        var stripped = self
        stripped.heartRateDaySamples = .empty
        stripped.heartRateDaySamplesSecondary = .empty
        stripped.restingHeartRateDaySamples = .empty
        stripped.restingHeartRateDaySamplesSecondary = .empty
        stripped.heartRateVariabilityDaySamples = .empty
        stripped.heartRateVariabilityDaySamplesSecondary = .empty
        stripped.heartbeatRMSSDDaySamples = .empty
        stripped.respiratoryRateDaySamples = .empty
        stripped.oxygenSaturationDaySamples = .empty
        stripped.oxygenSaturationDaySamplesSecondary = .empty
        stripped.activeEnergyDaySamples = .empty
        stripped.activeEnergyDaySamplesSecondary = .empty
        stripped.stepsDaySamples = .empty
        stripped.stepsDaySamplesSecondary = .empty
        return stripped
    }

    /// Strips only the PRIMARY intraday day-sample series for a single metric
    /// kind. The per-kind source setter uses this so switching one metric's
    /// source invalidates just that chart's cached other-source points (H6a)
    /// without blanking every other metric detail chart. Kinds without intraday
    /// day samples are no-ops.
    func strippingPrimaryDaySamples(for kind: HealthMetricKind) -> HealthTrendSnapshot {
        var stripped = self
        switch kind {
        case .heartRate:
            stripped.heartRateDaySamples = .empty
        case .restingHeartRate:
            stripped.restingHeartRateDaySamples = .empty
        case .heartRateVariability:
            stripped.heartRateVariabilityDaySamples = .empty
            // The RMSSD series is fetched under this metric's source selection,
            // so a source change invalidates it along with the SDNN samples.
            stripped.heartbeatRMSSDDaySamples = .empty
        case .respiratoryRate:
            stripped.respiratoryRateDaySamples = .empty
        case .oxygenSaturation:
            stripped.oxygenSaturationDaySamples = .empty
        case .activeEnergy:
            stripped.activeEnergyDaySamples = .empty
        case .steps:
            stripped.stepsDaySamples = .empty
        case .sleep,
             .readiness,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .vitals,
             .cardioFitness,
             .stress:
            break
        }
        return stripped
    }

    /// Fills only the `*DaySamples` fields that are still empty, so a sidecar
    /// decoded after launch never overwrites samples a refresh or detail-view
    /// lazy load has already fetched in this session.
    func mergingMissingDaySamples(from daySamples: HealthTrendDaySampleSnapshot) -> HealthTrendSnapshot {
        var merged = self
        if merged.heartRateDaySamples.isEmpty {
            merged.heartRateDaySamples = daySamples.heartRateDaySamples
        }
        if merged.heartRateDaySamplesSecondary.isEmpty {
            merged.heartRateDaySamplesSecondary = daySamples.heartRateDaySamplesSecondary
        }
        if merged.restingHeartRateDaySamples.isEmpty {
            merged.restingHeartRateDaySamples = daySamples.restingHeartRateDaySamples
        }
        if merged.restingHeartRateDaySamplesSecondary.isEmpty {
            merged.restingHeartRateDaySamplesSecondary = daySamples.restingHeartRateDaySamplesSecondary
        }
        if merged.heartRateVariabilityDaySamples.isEmpty {
            merged.heartRateVariabilityDaySamples = daySamples.heartRateVariabilityDaySamples
        }
        if merged.heartRateVariabilityDaySamplesSecondary.isEmpty {
            merged.heartRateVariabilityDaySamplesSecondary = daySamples.heartRateVariabilityDaySamplesSecondary
        }
        if merged.heartbeatRMSSDDaySamples.isEmpty {
            merged.heartbeatRMSSDDaySamples = daySamples.heartbeatRMSSDDaySamples
        }
        if merged.respiratoryRateDaySamples.isEmpty {
            merged.respiratoryRateDaySamples = daySamples.respiratoryRateDaySamples
        }
        if merged.oxygenSaturationDaySamples.isEmpty {
            merged.oxygenSaturationDaySamples = daySamples.oxygenSaturationDaySamples
        }
        if merged.oxygenSaturationDaySamplesSecondary.isEmpty {
            merged.oxygenSaturationDaySamplesSecondary = daySamples.oxygenSaturationDaySamplesSecondary
        }
        if merged.activeEnergyDaySamples.isEmpty {
            merged.activeEnergyDaySamples = daySamples.activeEnergyDaySamples
        }
        if merged.activeEnergyDaySamplesSecondary.isEmpty {
            merged.activeEnergyDaySamplesSecondary = daySamples.activeEnergyDaySamplesSecondary
        }
        if merged.stepsDaySamples.isEmpty {
            merged.stepsDaySamples = daySamples.stepsDaySamples
        }
        if merged.stepsDaySamplesSecondary.isEmpty {
            merged.stepsDaySamplesSecondary = daySamples.stepsDaySamplesSecondary
        }
        return merged
    }
}

/// The source + permission selection a day-sample sidecar was captured under.
/// Stamped onto the sidecar so `hydratePersistedDaySamplesIfNeeded` can reject
/// a sidecar written under a now-different selection instead of merging stale
/// other-source intraday points (H6).
struct HealthTrendDaySampleSignatures: Equatable {
    var primarySelectionSignature: String
    var secondarySelectionSignature: String
    var permissionSignature: String
    /// The combine-sources-by-name flag the samples were captured under. A flip
    /// changes how per-source values are merged, so hydration must reject a
    /// sidecar stamped under the other setting even when the source signatures
    /// still match (H6b).
    var combinesHealthDataSourcesByName: Bool
}

/// Sidecar payload holding the lazily loaded intraday sample series, persisted
/// separately from `HealthDashboardSnapshot` so cold launch decodes only the
/// small summary + daily-trend payload on the main thread.
struct HealthTrendDaySampleSnapshot: Codable, Equatable {
    /// Current sidecar schema. A `nil` `schemaVersion` marks a legacy sidecar
    /// written before the source/permission stamps existed. Bumped 1→2 when the
    /// combine-sources flag joined the stamps (H6b); a v1 sidecar predates it and
    /// is dropped one-time on hydration (`scopedForHydration` accepts v2 only).
    static let currentSchemaVersion = 2

    var heartRateDaySamples: HealthTrendSeries
    var heartRateDaySamplesSecondary: HealthTrendSeries
    var restingHeartRateDaySamples: HealthTrendSeries
    var restingHeartRateDaySamplesSecondary: HealthTrendSeries
    var heartRateVariabilityDaySamples: HealthTrendSeries
    var heartRateVariabilityDaySamplesSecondary: HealthTrendSeries
    var heartbeatRMSSDDaySamples: HealthTrendSeries
    var respiratoryRateDaySamples: HealthTrendSeries
    var oxygenSaturationDaySamples: HealthTrendSeries
    var oxygenSaturationDaySamplesSecondary: HealthTrendSeries
    var activeEnergyDaySamples: HealthTrendSeries
    var activeEnergyDaySamplesSecondary: HealthTrendSeries
    var stepsDaySamples: HealthTrendSeries
    var stepsDaySamplesSecondary: HealthTrendSeries
    /// `nil` on a legacy (pre-scoping) sidecar; set to `currentSchemaVersion`
    /// once the source/permission stamps below are recorded.
    var schemaVersion: Int?
    /// Selection signatures the samples were captured under. `nil` on a legacy
    /// sidecar. `permissionSignature` records the capture-time permission set;
    /// hydration enforces removals by live-filtering against the *current*
    /// permission selection, so a permission toggle never invalidates
    /// source-matched data.
    var primarySelectionSignature: String?
    var secondarySelectionSignature: String?
    var permissionSignature: String?
    /// The combine-sources-by-name flag the samples were captured under. `nil` on
    /// a legacy/v1 sidecar (which fails closed on hydration anyway).
    var combinesHealthDataSourcesByName: Bool?

    init(trends: HealthTrendSnapshot, signatures: HealthTrendDaySampleSignatures? = nil) {
        heartRateDaySamples = trends.heartRateDaySamples
        heartRateDaySamplesSecondary = trends.heartRateDaySamplesSecondary
        restingHeartRateDaySamples = trends.restingHeartRateDaySamples
        restingHeartRateDaySamplesSecondary = trends.restingHeartRateDaySamplesSecondary
        heartRateVariabilityDaySamples = trends.heartRateVariabilityDaySamples
        heartRateVariabilityDaySamplesSecondary = trends.heartRateVariabilityDaySamplesSecondary
        heartbeatRMSSDDaySamples = trends.heartbeatRMSSDDaySamples
        respiratoryRateDaySamples = trends.respiratoryRateDaySamples
        oxygenSaturationDaySamples = trends.oxygenSaturationDaySamples
        oxygenSaturationDaySamplesSecondary = trends.oxygenSaturationDaySamplesSecondary
        activeEnergyDaySamples = trends.activeEnergyDaySamples
        activeEnergyDaySamplesSecondary = trends.activeEnergyDaySamplesSecondary
        stepsDaySamples = trends.stepsDaySamples
        stepsDaySamplesSecondary = trends.stepsDaySamplesSecondary
        schemaVersion = signatures == nil ? nil : Self.currentSchemaVersion
        primarySelectionSignature = signatures?.primarySelectionSignature
        secondarySelectionSignature = signatures?.secondarySelectionSignature
        permissionSignature = signatures?.permissionSignature
        combinesHealthDataSourcesByName = signatures?.combinesHealthDataSourcesByName
    }

    private enum CodingKeys: String, CodingKey {
        case heartRateDaySamples
        case heartRateDaySamplesSecondary
        case restingHeartRateDaySamples
        case restingHeartRateDaySamplesSecondary
        case heartRateVariabilityDaySamples
        case heartRateVariabilityDaySamplesSecondary
        case heartbeatRMSSDDaySamples
        case respiratoryRateDaySamples
        case oxygenSaturationDaySamples
        case oxygenSaturationDaySamplesSecondary
        case activeEnergyDaySamples
        case activeEnergyDaySamplesSecondary
        case stepsDaySamples
        case stepsDaySamplesSecondary
        case schemaVersion
        case primarySelectionSignature
        case secondarySelectionSignature
        case permissionSignature
        case combinesHealthDataSourcesByName
    }

    // Every field decodes with `decodeIfPresent` + a default so a legacy sidecar
    // (13 series fields, no stamps) — or a partially written one — still loads
    // instead of failing the whole sidecar decode (L10).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heartRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .heartRateDaySamples
        ) ?? .empty
        heartRateDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .heartRateDaySamplesSecondary
        ) ?? .empty
        restingHeartRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .restingHeartRateDaySamples
        ) ?? .empty
        restingHeartRateDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .restingHeartRateDaySamplesSecondary
        ) ?? .empty
        heartRateVariabilityDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .heartRateVariabilityDaySamples
        ) ?? .empty
        heartRateVariabilityDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .heartRateVariabilityDaySamplesSecondary
        ) ?? .empty
        heartbeatRMSSDDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .heartbeatRMSSDDaySamples
        ) ?? .empty
        respiratoryRateDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .respiratoryRateDaySamples
        ) ?? .empty
        oxygenSaturationDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .oxygenSaturationDaySamples
        ) ?? .empty
        oxygenSaturationDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .oxygenSaturationDaySamplesSecondary
        ) ?? .empty
        activeEnergyDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .activeEnergyDaySamples
        ) ?? .empty
        activeEnergyDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .activeEnergyDaySamplesSecondary
        ) ?? .empty
        stepsDaySamples = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .stepsDaySamples
        ) ?? .empty
        stepsDaySamplesSecondary = try container.decodeIfPresent(
            HealthTrendSeries.self, forKey: .stepsDaySamplesSecondary
        ) ?? .empty
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        primarySelectionSignature = try container.decodeIfPresent(
            String.self, forKey: .primarySelectionSignature
        )
        secondarySelectionSignature = try container.decodeIfPresent(
            String.self, forKey: .secondarySelectionSignature
        )
        permissionSignature = try container.decodeIfPresent(String.self, forKey: .permissionSignature)
        combinesHealthDataSourcesByName = try container.decodeIfPresent(
            Bool.self, forKey: .combinesHealthDataSourcesByName
        )
    }

    var isEmpty: Bool {
        heartRateDaySamples.isEmpty &&
            heartRateDaySamplesSecondary.isEmpty &&
            restingHeartRateDaySamples.isEmpty &&
            restingHeartRateDaySamplesSecondary.isEmpty &&
            heartRateVariabilityDaySamples.isEmpty &&
            heartRateVariabilityDaySamplesSecondary.isEmpty &&
            heartbeatRMSSDDaySamples.isEmpty &&
            respiratoryRateDaySamples.isEmpty &&
            oxygenSaturationDaySamples.isEmpty &&
            oxygenSaturationDaySamplesSecondary.isEmpty &&
            activeEnergyDaySamples.isEmpty &&
            activeEnergyDaySamplesSecondary.isEmpty &&
            stepsDaySamples.isEmpty &&
            stepsDaySamplesSecondary.isEmpty
    }

    /// Drops every comparison-source series, keeping the primary ones. Used to
    /// re-point the session's memoized sidecar load after the app deliberately
    /// invalidates the comparison caches, so a later hydration can still restore
    /// the primary scope without resurrecting what was just cleared.
    func strippingSecondaryDaySamples() -> HealthTrendDaySampleSnapshot {
        var stripped = self
        stripped.heartRateDaySamplesSecondary = .empty
        stripped.restingHeartRateDaySamplesSecondary = .empty
        stripped.heartRateVariabilityDaySamplesSecondary = .empty
        stripped.oxygenSaturationDaySamplesSecondary = .empty
        stripped.activeEnergyDaySamplesSecondary = .empty
        stripped.stepsDaySamplesSecondary = .empty
        return stripped
    }

    /// Returns a copy safe to merge into the live trends during sidecar
    /// hydration: intraday series whose source scope no longer matches the
    /// current selection are dropped per-scope, and series whose permission is
    /// currently off are stripped (mirrors `HealthTrendSnapshot.filtered(by:)`).
    ///
    /// Only a current-schema (v2) sidecar carries the full source + combine
    /// stamps, so acceptance gates on `schemaVersion == currentSchemaVersion`
    /// EXACTLY: a legacy (`nil`), v1, or unknown-future sidecar fails closed for
    /// BOTH scopes and is dropped one-time (the next stamped save re-writes it as
    /// v2, self-healing). A scope matches only when its selection signature AND
    /// the combine-sources flag both match (H6b).
    ///
    /// `comparisonDisabledKinds` is a LIVE gate, like `permission` and unlike the
    /// captured signatures: it carries the kinds whose comparison the *current*
    /// selection resolves away. Body Pro lapsing, or a primary source changed to
    /// match the secondary, leaves the stored secondary selection — and therefore
    /// `secondarySelectionSignature` — untouched, so scope matching alone would
    /// happily restore those samples and undo the invalidation the entitlement or
    /// source change just performed.
    func scopedForHydration(
        currentPrimarySignature: String,
        currentSecondarySignature: String,
        currentCombinesByName: Bool,
        permission: BodyHealthPermissionSelection,
        comparisonDisabledKinds: Set<HealthMetricKind>
    ) -> HealthTrendDaySampleSnapshot {
        var scoped = self

        let isCurrentSchema = schemaVersion == Self.currentSchemaVersion
        let combineMatches = combinesHealthDataSourcesByName == currentCombinesByName
        let primaryScopeMatches = isCurrentSchema
            && combineMatches
            && primarySelectionSignature == currentPrimarySignature
        let secondaryScopeMatches = isCurrentSchema
            && combineMatches
            && secondarySelectionSignature == currentSecondarySignature

        if !primaryScopeMatches {
            scoped.heartRateDaySamples = .empty
            scoped.restingHeartRateDaySamples = .empty
            scoped.heartRateVariabilityDaySamples = .empty
            scoped.heartbeatRMSSDDaySamples = .empty
            scoped.respiratoryRateDaySamples = .empty
            scoped.oxygenSaturationDaySamples = .empty
            scoped.activeEnergyDaySamples = .empty
            scoped.stepsDaySamples = .empty
        }
        if !secondaryScopeMatches {
            scoped.heartRateDaySamplesSecondary = .empty
            scoped.restingHeartRateDaySamplesSecondary = .empty
            scoped.heartRateVariabilityDaySamplesSecondary = .empty
            scoped.oxygenSaturationDaySamplesSecondary = .empty
            scoped.activeEnergyDaySamplesSecondary = .empty
            scoped.stepsDaySamplesSecondary = .empty
        }

        if !permission.includes(.heart) {
            scoped.heartRateDaySamples = .empty
            scoped.heartRateDaySamplesSecondary = .empty
            scoped.restingHeartRateDaySamples = .empty
            scoped.restingHeartRateDaySamplesSecondary = .empty
            scoped.heartRateVariabilityDaySamples = .empty
            scoped.heartRateVariabilityDaySamplesSecondary = .empty
            scoped.heartbeatRMSSDDaySamples = .empty
        }
        if !permission.includes(.respiratory) {
            scoped.respiratoryRateDaySamples = .empty
        }
        if !permission.includes(.bloodOxygen) {
            scoped.oxygenSaturationDaySamples = .empty
            scoped.oxygenSaturationDaySamplesSecondary = .empty
        }
        if !permission.includes(.energy) {
            scoped.activeEnergyDaySamples = .empty
            scoped.activeEnergyDaySamplesSecondary = .empty
        }
        if !permission.includes(.steps) {
            scoped.stepsDaySamples = .empty
            scoped.stepsDaySamplesSecondary = .empty
        }

        if comparisonDisabledKinds.contains(.heartRate) {
            scoped.heartRateDaySamplesSecondary = .empty
        }
        if comparisonDisabledKinds.contains(.restingHeartRate) {
            scoped.restingHeartRateDaySamplesSecondary = .empty
        }
        if comparisonDisabledKinds.contains(.heartRateVariability) {
            scoped.heartRateVariabilityDaySamplesSecondary = .empty
        }
        if comparisonDisabledKinds.contains(.oxygenSaturation) {
            scoped.oxygenSaturationDaySamplesSecondary = .empty
        }
        if comparisonDisabledKinds.contains(.activeEnergy) {
            scoped.activeEnergyDaySamplesSecondary = .empty
        }
        if comparisonDisabledKinds.contains(.steps) {
            scoped.stepsDaySamplesSecondary = .empty
        }

        return scoped
    }
}

struct BasicsTrendSummary: Equatable {
    var weight: HealthTrendSeries
    var bodyFat: HealthTrendSeries
    var bodyMassIndex: HealthTrendSeries

    var isEmpty: Bool {
        weight.isEmpty && bodyFat.isEmpty && bodyMassIndex.isEmpty
    }

    static let empty = BasicsTrendSummary(weight: .empty, bodyFat: .empty, bodyMassIndex: .empty)

    var weightHalfSpread: Double? {
        halfSpread(for: weight)
    }

    var bodyFatHalfSpread: Double? {
        halfSpread(for: bodyFat)
    }

    var bodyMassIndexHalfSpread: Double? {
        halfSpread(for: bodyMassIndex)
    }

    var weightAverage: Double? {
        weight.averageValue
    }

    var bodyFatAverage: Double? {
        bodyFat.averageValue
    }

    private func halfSpread(for series: HealthTrendSeries) -> Double? {
        let values = series.points.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return nil
        }

        return (maximum - minimum) / 2
    }

    func limited(to range: BodyHealthTrendRange, calendar: Calendar = .bodyGregorian, date: Date = Date()) -> BasicsTrendSummary {
        BasicsTrendSummary(
            weight: weight.limited(to: range, calendar: calendar, date: date),
            bodyFat: bodyFat.limited(to: range, calendar: calendar, date: date),
            bodyMassIndex: bodyMassIndex.limited(to: range, calendar: calendar, date: date)
        )
    }

    func nearestDate(to date: Date) -> Date? {
        let dates = weight.points.map(\.date) + bodyFat.points.map(\.date) + bodyMassIndex.points.map(\.date)
        return dates.min { first, second in
            abs(first.timeIntervalSince(date)) < abs(second.timeIntervalSince(date))
        }
    }

    func selectionDate(for selectedDate: Date?) -> Date? {
        guard let selectedDate else {
            return nil
        }

        return nearestDate(to: selectedDate)
    }
}

private func bodyTrendAggregationBuckets<Point>(
    from points: [Point],
    aggregationDayCount: Int
) -> [ArraySlice<Point>] {
    guard aggregationDayCount > 0, !points.isEmpty else {
        return []
    }

    // Points run oldest → newest ending at today. Anchor bucketing from the
    // newest day backwards so a leftover partial bucket falls on the oldest
    // end, not the newest — otherwise today's reading gets silently dropped.
    var ranges: [Range<Int>] = []
    var endIndex = points.count
    while endIndex > 0 {
        let startIndex = max(endIndex - aggregationDayCount, 0)
        ranges.append(startIndex..<endIndex)
        endIndex = startIndex
    }
    ranges.reverse()

    if let firstRange = ranges.first,
       firstRange.count < aggregationDayCount,
       ranges.count > 1 {
        ranges.removeFirst()
    }

    return ranges.map { points[$0] }
}

struct HealthTrendRangeSeries: Codable, Equatable {
    var points: [HealthTrendRangeDataPoint]

    var isEmpty: Bool {
        points.isEmpty
    }

    var averageValue: Double? {
        let finiteValues = points.compactMap(\.averageValue).filter(\.isFinite)
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }

    var valueRange: ClosedRange<Double>? {
        let lows = points.map(\.lowValue).filter(\.isFinite)
        let highs = points.map(\.highValue).filter(\.isFinite)
        guard let low = lows.min(), let high = highs.max() else {
            return nil
        }

        return min(low, high)...max(low, high)
    }

    static let empty = HealthTrendRangeSeries(points: [])

    func limited(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> HealthTrendRangeSeries {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        return HealthTrendRangeSeries(
            points: points.filter { point in
                point.date >= startDate && point.date < endDate
            }
        )
    }

    func calendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendRangeCalendarPoint] {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let pointsByDay = Dictionary(grouping: points.filter { point in
            point.date >= startDate && point.date < endDate
        }) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<range.dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            let point = pointsByDay[day]?
                .sorted { $0.date < $1.date }
                .last
            return HealthTrendRangeCalendarPoint(
                date: day,
                lowValue: point?.lowValue.isFinite == true ? point?.lowValue : nil,
                highValue: point?.highValue.isFinite == true ? point?.highValue : nil,
                averageValue: point?.averageValue?.isFinite == true ? point?.averageValue : nil
            )
        }
    }

    func chartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendRangeCalendarPoint] {
        aggregatedChartCalendarPoints(
            to: range,
            aggregationDayCount: range.chartAggregationDayCount,
            calendar: calendar,
            date: date
        )
    }

    func sourceComparisonChartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendRangeCalendarPoint] {
        aggregatedChartCalendarPoints(
            to: range,
            aggregationDayCount: range.sourceComparisonChartAggregationDayCount,
            calendar: calendar,
            date: date
        )
    }

    private func aggregatedChartCalendarPoints(
        to range: BodyHealthTrendRange,
        aggregationDayCount: Int,
        calendar: Calendar,
        date: Date
    ) -> [HealthTrendRangeCalendarPoint] {
        let dailyPoints = calendarPoints(to: range, calendar: calendar, date: date)
        guard aggregationDayCount > 1 else {
            return dailyPoints
        }

        return bodyTrendAggregationBuckets(
            from: dailyPoints,
            aggregationDayCount: aggregationDayCount
        ).compactMap { bucket in
            guard let bucketStartDate = bucket.first?.date,
                  let bucketEndDate = bucket.last?.date else {
                return nil
            }

            let lows = bucket.compactMap(\.lowValue).filter(\.isFinite)
            let highs = bucket.compactMap(\.highValue).filter(\.isFinite)
            let averages = bucket.compactMap(\.averageValue).filter(\.isFinite)
            let averageValue = averages.isEmpty ? nil : averages.reduce(0, +) / Double(averages.count)
            return HealthTrendRangeCalendarPoint(
                date: bucketEndDate,
                lowValue: lows.min(),
                highValue: highs.max(),
                averageValue: averageValue,
                startDate: bucketStartDate,
                endDate: bucketEndDate
            )
        }
    }
}

struct HealthTrendRangeDataPoint: Codable, Equatable, Identifiable {
    var date: Date
    var lowValue: Double
    var highValue: Double
    var averageValue: Double?

    var id: Date {
        date
    }
}

struct HealthTrendRangeCalendarPoint: Equatable, Identifiable {
    var date: Date
    var lowValue: Double?
    var highValue: Double?
    var averageValue: Double?
    var startDate: Date
    var endDate: Date

    init(
        date: Date,
        lowValue: Double?,
        highValue: Double?,
        averageValue: Double?,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.date = date
        self.lowValue = lowValue
        self.highValue = highValue
        self.averageValue = averageValue
        self.startDate = startDate ?? date
        self.endDate = endDate ?? date
    }

    var id: Date {
        date
    }

    var hasValue: Bool {
        lowValue != nil && highValue != nil
    }

    var representsDateRange: Bool {
        startDate != endDate
    }
}

struct HealthTrendSeries: Codable, Equatable {
    var points: [HealthTrendDataPoint]

    var isEmpty: Bool {
        points.isEmpty
    }

    var averageValue: Double? {
        let finiteValues = points.map(\.value).filter(\.isFinite)
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }

    static let empty = HealthTrendSeries(points: [])

    func mapValues(_ transform: (Double) -> Double) -> HealthTrendSeries {
        HealthTrendSeries(
            points: points.map {
                HealthTrendDataPoint(date: $0.date, value: transform($0.value))
            }
        )
    }

    func limited(to range: BodyHealthTrendRange, calendar: Calendar = .bodyGregorian, date: Date = Date()) -> HealthTrendSeries {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        return HealthTrendSeries(
            points: points.filter { point in
                point.date >= startDate && point.date < endDate
            }
        )
    }

    func calendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let pointsByDay = Dictionary(grouping: points.filter { point in
            point.date >= startDate && point.date < endDate
        }) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<range.dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            let value = pointsByDay[day]?
                .sorted { $0.date < $1.date }
                .last?
                .value
            return HealthTrendCalendarPoint(
                date: day,
                value: value?.isFinite == true ? value : nil
            )
        }
    }

    func chartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        aggregatedChartCalendarPoints(
            to: range,
            aggregationDayCount: range.chartAggregationDayCount,
            calendar: calendar,
            date: date
        )
    }

    func sourceComparisonChartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        aggregatedChartCalendarPoints(
            to: range,
            aggregationDayCount: range.sourceComparisonChartAggregationDayCount,
            calendar: calendar,
            date: date
        )
    }

    private func aggregatedChartCalendarPoints(
        to range: BodyHealthTrendRange,
        aggregationDayCount: Int,
        calendar: Calendar,
        date: Date
    ) -> [HealthTrendCalendarPoint] {
        let dailyPoints = calendarPoints(to: range, calendar: calendar, date: date)
        guard aggregationDayCount > 1 else {
            return dailyPoints
        }

        return bodyTrendAggregationBuckets(
            from: dailyPoints,
            aggregationDayCount: aggregationDayCount
        ).compactMap { bucket in
            guard let bucketStartDate = bucket.first?.date,
                  let bucketEndDate = bucket.last?.date else {
                return nil
            }

            let finiteValues = bucket.compactMap(\.value).filter(\.isFinite)
            let averageValue = finiteValues.isEmpty
                ? nil
                : finiteValues.reduce(0, +) / Double(finiteValues.count)
            return HealthTrendCalendarPoint(
                date: bucketEndDate,
                value: averageValue,
                startDate: bucketStartDate,
                endDate: bucketEndDate
            )
        }
    }

    func lineChartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date(),
        maximumPointCount: Int? = nil
    ) -> [HealthTrendCalendarPoint] {
        let chartPoints = chartCalendarPoints(to: range, calendar: calendar, date: date)
        let effectiveMaximumPointCount = maximumPointCount ?? range.lineChartMaximumPointCount
        guard let effectiveMaximumPointCount else {
            return chartPoints
        }

        return chartPoints.compressedStableLineChartPoints(maximumCount: effectiveMaximumPointCount)
    }

    /// Line chart points for a metric whose readings are sparse and irregular —
    /// Cardio Fitness records one VO₂ max estimate per qualifying outdoor
    /// workout, so a month often holds two.
    ///
    /// The dense path above averages each bucket and stamps the average at the
    /// bucket's END date. That is right for a metric with a reading every day,
    /// but with readings weeks apart it moves a point up to `aggregationDayCount
    /// - 1` days from when it was actually measured (11 days on the year range)
    /// and reports an average of readings that were never averaged. This keeps
    /// each reading on its own day at its own value, and only compresses when
    /// the real readings outnumber the range's visual cap — so the chart is a
    /// plot of measurements rather than of buckets.
    ///
    /// Past the range's visual cap the series is thinned by DROPPING readings
    /// rather than by averaging them, so every plotted point stays a reading
    /// HealthKit actually recorded — see `evenlySampledLineChartPoints`.
    func sparseLineChartCalendarPoints(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date(),
        maximumPointCount: Int? = nil
    ) -> [HealthTrendCalendarPoint] {
        let readings = calendarPoints(to: range, calendar: calendar, date: date)
            .filter(\.hasValue)
        let effectiveMaximumPointCount = maximumPointCount ?? range.lineChartMaximumPointCount
        guard let effectiveMaximumPointCount, readings.count > effectiveMaximumPointCount else {
            return readings
        }

        return readings.evenlySampledLineChartPoints(maximumCount: effectiveMaximumPointCount)
    }

    func chartSeries(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> HealthTrendSeries {
        HealthTrendSeries(
            points: chartCalendarPoints(to: range, calendar: calendar, date: date).compactMap { point in
                guard let value = point.value, value.isFinite else {
                    return nil
                }

                return HealthTrendDataPoint(date: point.date, value: value)
            }
        )
    }

    func lineChartSeries(
        to range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date(),
        maximumPointCount: Int? = nil
    ) -> HealthTrendSeries {
        HealthTrendSeries(
            points: lineChartCalendarPoints(
                to: range,
                calendar: calendar,
                date: date,
                maximumPointCount: maximumPointCount
            ).compactMap { point in
                guard let value = point.value, value.isFinite else {
                    return nil
                }

                return HealthTrendDataPoint(date: point.date, value: value)
            }
        )
    }

    func nearestPoint(to date: Date) -> HealthTrendDataPoint? {
        points.min { first, second in
            abs(first.date.timeIntervalSince(date)) < abs(second.date.timeIntervalSince(date))
        }
    }

    func selectionPoint(for selectedDate: Date?) -> HealthTrendDataPoint? {
        guard let selectedDate else {
            return nil
        }

        return nearestPoint(to: selectedDate)
    }

    func point(on date: Date) -> HealthTrendDataPoint? {
        points.first { $0.date == date }
    }

    /// Latest finite point value on or before `date`, no older than `maxAgeDays`.
    /// Unlike `point(on:)` (exact-Date equality), this tolerates sparse daily series —
    /// e.g. "the resting HR in effect on the day of an old workout".
    func latestValue(
        onOrBefore date: Date,
        maxAgeDays: Int,
        calendar: Calendar = .bodyGregorian
    ) -> Double? {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date
        guard let earliest = calendar.date(byAdding: .day, value: -maxAgeDays, to: calendar.startOfDay(for: date)) else {
            return nil
        }

        let eligible = points.filter {
            $0.date < dayEnd && $0.date >= earliest && $0.value.isFinite
        }
        return eligible.max(by: { $0.date < $1.date })?.value
    }

    /// Overlay frozen morning records onto the series, replacing each recorded
    /// day's point value in place (keyed by start-of-day) so `point(on:)` and the
    /// chart's last-point-per-day grouping agree. Override-only: a recorded day
    /// with no computed point is left out — so when readiness becomes uncomputable
    /// (e.g. inputs filtered out), a stale frozen value can't leak back in as a
    /// phantom point. Days without a record keep their computed point unchanged.
    func applyingRecordedOverrides(
        _ records: [RecordedReadinessEntry],
        calendar: Calendar = .bodyGregorian
    ) -> HealthTrendSeries {
        guard !records.isEmpty else {
            return self
        }

        var valuesByDay: [Date: Double] = [:]
        for record in records {
            valuesByDay[calendar.startOfDay(for: record.date)] = Double(record.score)
        }

        return HealthTrendSeries(points: points.map { point in
            guard let frozen = valuesByDay[calendar.startOfDay(for: point.date)] else {
                return point
            }
            return HealthTrendDataPoint(date: point.date, value: frozen)
        })
    }

    func points(on date: Date, calendar: Calendar = .bodyGregorian) -> HealthTrendSeries {
        let dayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)

        return HealthTrendSeries(
            points: points
                .filter { point in
                    point.date >= dayStart && point.date < nextDayStart
                }
                .sorted { $0.date < $1.date }
        )
    }

    func hourlyAverageBuckets(on date: Date, calendar: Calendar = .bodyGregorian) -> [HealthTrendHourlyBucket] {
        let dayPoints = points(on: date, calendar: calendar).points.filter { $0.value.isFinite }
        let pointsByHour = Dictionary(grouping: dayPoints) { point in
            calendar.dateInterval(of: .hour, for: point.date)?.start ?? point.date
        }

        return pointsByHour.compactMap { hourStart, samples -> HealthTrendHourlyBucket? in
            let sortedSamples = samples.sorted { $0.date < $1.date }
            guard !sortedSamples.isEmpty else {
                return nil
            }

            let averageValue = sortedSamples.reduce(0) { $0 + $1.value } / Double(sortedSamples.count)
            return HealthTrendHourlyBucket(
                hourStart: hourStart,
                averageValue: averageValue,
                samples: sortedSamples
            )
        }
        .sorted { $0.hourStart < $1.hourStart }
    }
}

struct HealthTrendDataPoint: Codable, Equatable, Identifiable {
    var date: Date
    var value: Double

    var id: Date {
        date
    }
}



struct HealthTrendCalendarPoint: Equatable, Identifiable {
    var date: Date
    var value: Double?
    var startDate: Date
    var endDate: Date

    init(date: Date, value: Double?, startDate: Date? = nil, endDate: Date? = nil) {
        self.date = date
        self.value = value
        self.startDate = startDate ?? date
        self.endDate = endDate ?? date
    }

    var id: Date {
        date
    }

    var hasValue: Bool {
        value != nil
    }

    var representsDateRange: Bool {
        startDate != endDate
    }
}

private struct HealthTrendStableLineBucket {
    var points: [HealthTrendCalendarPoint]

    var averageValue: Double? {
        let finiteValues = points.compactMap(\.value).filter(\.isFinite)
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }

    func merged(with other: HealthTrendStableLineBucket) -> HealthTrendStableLineBucket {
        HealthTrendStableLineBucket(points: points + other.points)
    }

    var calendarPoint: HealthTrendCalendarPoint? {
        guard let firstPoint = points.first, let lastPoint = points.last else {
            return nil
        }

        return HealthTrendCalendarPoint(
            date: lastPoint.date,
            value: averageValue,
            startDate: firstPoint.startDate,
            endDate: lastPoint.endDate
        )
    }
}

private struct HealthTrendStableLineMergeCandidate {
    let index: Int
    let valueDelta: Double
    let combinedPointCount: Int

    func isBetter(than other: HealthTrendStableLineMergeCandidate) -> Bool {
        guard valueDelta == other.valueDelta else {
            return valueDelta < other.valueDelta
        }

        guard combinedPointCount == other.combinedPointCount else {
            return combinedPointCount < other.combinedPointCount
        }

        return index < other.index
    }
}

private extension Array where Element == HealthTrendCalendarPoint {
    /// Thins the series to `maximumCount` points by DROPPING readings, never by
    /// combining them: every returned point is an original sample at its own
    /// date and value.
    ///
    /// `compressedStableLineChartPoints` is the wrong tool for a sparse metric —
    /// it merges adjacent buckets and emits their average stamped at the later
    /// date, so a scrub would report a VO₂ max that was never measured on a day
    /// it was never measured. That is the same distortion the sparse path exists
    /// to avoid, just reached by a different route.
    ///
    /// The first and last readings are always kept so the visible span still
    /// runs edge to edge; the rest are picked at an even stride. `count >
    /// maximumCount` makes the stride strictly greater than 1, so no index is
    /// selected twice.
    func evenlySampledLineChartPoints(maximumCount: Int) -> [HealthTrendCalendarPoint] {
        guard maximumCount > 0 else {
            return []
        }
        guard count > maximumCount else {
            return self
        }
        guard maximumCount > 1 else {
            // A single slot shows the newest reading rather than the oldest.
            return [self[count - 1]]
        }

        let stride = Double(count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { position in
            self[Swift.min(Int((Double(position) * stride).rounded()), count - 1)]
        }
    }

    func compressedStableLineChartPoints(maximumCount: Int) -> [HealthTrendCalendarPoint] {
        guard maximumCount > 0 else {
            return []
        }

        let finitePoints = filter { point in
            point.value?.isFinite == true
        }
        guard finitePoints.count > maximumCount else {
            return finitePoints
        }

        var buckets = finitePoints.map { point in
            HealthTrendStableLineBucket(points: [point])
        }

        while buckets.count > maximumCount {
            var bestCandidate: HealthTrendStableLineMergeCandidate?

            for index in buckets.indices.dropLast() {
                let candidate = mergeCandidate(at: index, in: buckets)
                if bestCandidate.map({ candidate.isBetter(than: $0) }) ?? true {
                    bestCandidate = candidate
                }
            }

            guard let bestCandidate else {
                break
            }

            buckets[bestCandidate.index] = buckets[bestCandidate.index].merged(with: buckets[bestCandidate.index + 1])
            buckets.remove(at: bestCandidate.index + 1)
        }

        return buckets.compactMap(\.calendarPoint)
    }

    private func mergeCandidate(
        at index: Int,
        in buckets: [HealthTrendStableLineBucket]
    ) -> HealthTrendStableLineMergeCandidate {
        let firstBucket = buckets[index]
        let secondBucket = buckets[index + 1]
        let valueDelta: Double
        if let firstAverage = firstBucket.averageValue,
           let secondAverage = secondBucket.averageValue {
            valueDelta = abs(firstAverage - secondAverage)
        } else {
            valueDelta = .greatestFiniteMagnitude
        }

        return HealthTrendStableLineMergeCandidate(
            index: index,
            valueDelta: valueDelta,
            combinedPointCount: firstBucket.points.count + secondBucket.points.count
        )
    }
}

struct HealthTrendHourlyBucket: Equatable, Identifiable {
    var hourStart: Date
    var averageValue: Double
    var samples: [HealthTrendDataPoint]

    static let sampleWindowDuration: TimeInterval = 10 * 60

    var id: Date {
        hourStart
    }

    var plotDate: Date {
        hourStart.addingTimeInterval(30 * 60)
    }

    func sampleWindows(duration: TimeInterval = sampleWindowDuration) -> [HealthTrendHourlySampleWindow] {
        let hourEnd = hourStart.addingTimeInterval(60 * 60)
        let windowDuration = min(max(duration, 0), 60 * 60)
        guard windowDuration > 0 else {
            return []
        }

        let sortedSamples = samples
            .filter { sample in
                sample.value.isFinite && sample.date >= hourStart && sample.date < hourEnd
            }
            .sorted { $0.date < $1.date }
        let samplesByWindowStart = Dictionary(grouping: sortedSamples) { sample in
            let offset = sample.date.timeIntervalSince(hourStart)
            let windowIndex = floor(offset / windowDuration)
            return hourStart.addingTimeInterval(windowIndex * windowDuration)
        }

        return samplesByWindowStart.keys.sorted().compactMap { startDate in
            guard let samples = samplesByWindowStart[startDate], !samples.isEmpty else {
                return nil
            }

            let endDate = min(startDate.addingTimeInterval(windowDuration), hourEnd)
            let averageValue = samples.reduce(0) { $0 + $1.value } / Double(samples.count)
            return HealthTrendHourlySampleWindow(
                startDate: startDate,
                endDate: endDate,
                averageValue: averageValue,
                samples: samples
            )
        }
    }
}

struct HealthTrendHourlySampleWindow: Equatable, Identifiable {
    var startDate: Date
    var endDate: Date
    var averageValue: Double
    var samples: [HealthTrendDataPoint]

    var id: Date {
        startDate
    }
}
