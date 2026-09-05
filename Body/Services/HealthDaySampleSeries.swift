import Foundation

/// Write intent identifies a successfully reconciled live series, including an
/// empty one. Absence means unqueried or failed, never permission to erase disk.
/// This metadata stays at fetch/persistence boundaries, not in consumer payloads.
enum HealthDaySampleSeries: CaseIterable, Hashable, Sendable {
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

    var keyPath: WritableKeyPath<HealthTrendDaySampleSnapshot, HealthTrendSeries> {
        switch self {
        case .heartRateDaySamples: return \.heartRateDaySamples
        case .heartRateDaySamplesSecondary: return \.heartRateDaySamplesSecondary
        case .restingHeartRateDaySamples: return \.restingHeartRateDaySamples
        case .restingHeartRateDaySamplesSecondary: return \.restingHeartRateDaySamplesSecondary
        case .heartRateVariabilityDaySamples: return \.heartRateVariabilityDaySamples
        case .heartRateVariabilityDaySamplesSecondary: return \.heartRateVariabilityDaySamplesSecondary
        case .heartbeatRMSSDDaySamples: return \.heartbeatRMSSDDaySamples
        case .respiratoryRateDaySamples: return \.respiratoryRateDaySamples
        case .oxygenSaturationDaySamples: return \.oxygenSaturationDaySamples
        case .oxygenSaturationDaySamplesSecondary: return \.oxygenSaturationDaySamplesSecondary
        case .activeEnergyDaySamples: return \.activeEnergyDaySamples
        case .activeEnergyDaySamplesSecondary: return \.activeEnergyDaySamplesSecondary
        case .stepsDaySamples: return \.stepsDaySamples
        case .stepsDaySamplesSecondary: return \.stepsDaySamplesSecondary
        }
    }

    var trendKeyPath: WritableKeyPath<HealthTrendSnapshot, HealthTrendSeries> {
        switch self {
        case .heartRateDaySamples: return \.heartRateDaySamples
        case .heartRateDaySamplesSecondary: return \.heartRateDaySamplesSecondary
        case .restingHeartRateDaySamples: return \.restingHeartRateDaySamples
        case .restingHeartRateDaySamplesSecondary: return \.restingHeartRateDaySamplesSecondary
        case .heartRateVariabilityDaySamples: return \.heartRateVariabilityDaySamples
        case .heartRateVariabilityDaySamplesSecondary: return \.heartRateVariabilityDaySamplesSecondary
        case .heartbeatRMSSDDaySamples: return \.heartbeatRMSSDDaySamples
        case .respiratoryRateDaySamples: return \.respiratoryRateDaySamples
        case .oxygenSaturationDaySamples: return \.oxygenSaturationDaySamples
        case .oxygenSaturationDaySamplesSecondary: return \.oxygenSaturationDaySamplesSecondary
        case .activeEnergyDaySamples: return \.activeEnergyDaySamples
        case .activeEnergyDaySamplesSecondary: return \.activeEnergyDaySamplesSecondary
        case .stepsDaySamples: return \.stepsDaySamples
        case .stepsDaySamplesSecondary: return \.stepsDaySamplesSecondary
        }
    }

    var kind: HealthMetricKind {
        switch self {
        case .heartRateDaySamples: return .heartRate
        case .heartRateDaySamplesSecondary: return .heartRate
        case .restingHeartRateDaySamples: return .restingHeartRate
        case .restingHeartRateDaySamplesSecondary: return .restingHeartRate
        case .heartRateVariabilityDaySamples: return .heartRateVariability
        case .heartRateVariabilityDaySamplesSecondary: return .heartRateVariability
        case .heartbeatRMSSDDaySamples: return .heartRateVariability
        case .respiratoryRateDaySamples: return .respiratoryRate
        case .oxygenSaturationDaySamples: return .oxygenSaturation
        case .oxygenSaturationDaySamplesSecondary: return .oxygenSaturation
        case .activeEnergyDaySamples: return .activeEnergy
        case .activeEnergyDaySamplesSecondary: return .activeEnergy
        case .stepsDaySamples: return .steps
        case .stepsDaySamplesSecondary: return .steps
        }
    }

    var isSecondary: Bool {
        switch self {
        case .heartRateDaySamplesSecondary, .restingHeartRateDaySamplesSecondary, .heartRateVariabilityDaySamplesSecondary, .oxygenSaturationDaySamplesSecondary, .activeEnergyDaySamplesSecondary, .stepsDaySamplesSecondary: return true
        default: return false
        }
    }

    func hasCompatibleScope(_ old: HealthTrendDaySampleSnapshot, _ new: HealthTrendDaySampleSnapshot) -> Bool {
        guard old.schemaVersion == new.schemaVersion else { return false }
        let oldScopes = isSecondary ? old.secondaryMetricScopes : old.primaryMetricScopes
        let newScopes = isSecondary ? new.secondaryMetricScopes : new.primaryMetricScopes
        if oldScopes != nil || newScopes != nil {
            return oldScopes?[kind.rawValue] != nil && oldScopes?[kind.rawValue] == newScopes?[kind.rawValue]
        }
        // Payload-only legacy/test callers have no per-metric provenance.
        return old.permissionSignature == new.permissionSignature
            && old.combinesHealthDataSourcesByName == new.combinesHealthDataSourcesByName
            && (isSecondary ? old.secondarySelectionSignature == new.secondarySelectionSignature
                            : old.primarySelectionSignature == new.primarySelectionSignature)
    }
}
