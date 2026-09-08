import Foundation

/// Fetch/merge metadata only: not a new persisted cache or consumer result type.
enum HealthTrendReconciliationLeaf: CaseIterable, Hashable {
    case sleep, sleepSecondary, heartRate, heartRateVariability, respiratoryRate, oxygenSaturation, heartRateRangesSecondary, heartRateVariabilityRangesSecondary, oxygenSaturationRangesSecondary, restingHeartRate, restingHeartRateSecondary, bodyMass, bodyFatPercentage, bodyMassIndex, activeEnergy, activeEnergySecondary, restingEnergy, restingEnergySecondary, exerciseMinutes, exerciseMinutesSecondary, wristTemperature, timeInDaylight, steps, stepsSecondary, cardioFitness

    private struct Fields {
        var series: WritableKeyPath<HealthTrendSnapshot, HealthTrendSeries>?
        var range: WritableKeyPath<HealthTrendSnapshot, HealthTrendRangeSeries>?
        var sleep: WritableKeyPath<HealthTrendSnapshot, SleepHistorySnapshot>?
    }

    private var fields: Fields {
        switch self {
        case .sleep: return .init(series: \.sleep, sleep: \.sleepHistory)
        case .sleepSecondary: return .init(series: \.sleepSecondary, sleep: \.sleepHistorySecondary)
        case .heartRate: return .init(series: \.heartRate, range: \.heartRateRanges)
        case .heartRateVariability: return .init(series: \.heartRateVariability, range: \.heartRateVariabilityRanges)
        case .respiratoryRate: return .init(series: \.respiratoryRate, range: \.respiratoryRateRanges)
        case .oxygenSaturation: return .init(series: \.oxygenSaturation, range: \.oxygenSaturationRanges)
        case .heartRateRangesSecondary: return .init(range: \.heartRateRangesSecondary)
        case .heartRateVariabilityRangesSecondary: return .init(range: \.heartRateVariabilityRangesSecondary)
        case .oxygenSaturationRangesSecondary: return .init(range: \.oxygenSaturationRangesSecondary)
        case .restingHeartRate: return .init(series: \.restingHeartRate)
        case .restingHeartRateSecondary: return .init(series: \.restingHeartRateSecondary)
        case .bodyMass: return .init(series: \.bodyMass)
        case .bodyFatPercentage: return .init(series: \.bodyFatPercentage)
        case .bodyMassIndex: return .init(series: \.bodyMassIndex)
        case .activeEnergy: return .init(series: \.activeEnergy)
        case .activeEnergySecondary: return .init(series: \.activeEnergySecondary)
        case .restingEnergy: return .init(series: \.restingEnergy)
        case .restingEnergySecondary: return .init(series: \.restingEnergySecondary)
        case .exerciseMinutes: return .init(series: \.exerciseMinutes)
        case .exerciseMinutesSecondary: return .init(series: \.exerciseMinutesSecondary)
        case .wristTemperature: return .init(series: \.wristTemperature)
        case .timeInDaylight: return .init(series: \.timeInDaylight)
        case .steps: return .init(series: \.steps)
        case .stepsSecondary: return .init(series: \.stepsSecondary)
        case .cardioFitness: return .init(series: \.cardioFitness)
        }
    }

    func hasSameValue(in lhs: HealthTrendSnapshot, and rhs: HealthTrendSnapshot) -> Bool {
        let fields = fields
        if let path = fields.series, lhs[keyPath: path] != rhs[keyPath: path] { return false }
        if let path = fields.range, lhs[keyPath: path] != rhs[keyPath: path] { return false }
        if let path = fields.sleep, lhs[keyPath: path] != rhs[keyPath: path] { return false }
        return true
    }

    func copy(from fetched: HealthTrendSnapshot, to live: inout HealthTrendSnapshot, retainingFrom cutoff: Date?) {
        let fields = fields
        if let path = fields.series {
            let value = fetched[keyPath: path]
            live[keyPath: path] = cutoff.map { start in
                HealthTrendSeries(points: value.points.filter { $0.date >= start })
            } ?? value
        }
        if let path = fields.range {
            let value = fetched[keyPath: path]
            live[keyPath: path] = cutoff.map { start in
                HealthTrendRangeSeries(points: value.points.filter { $0.date >= start })
            } ?? value
        }
        if let path = fields.sleep {
            let value = fetched[keyPath: path]
            live[keyPath: path] = cutoff.map { start in
                SleepHistorySnapshot(days: value.days.filter { $0.date >= start })
            } ?? value
        }
    }
}

