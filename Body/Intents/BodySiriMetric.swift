//
//  BodySiriMetric.swift
//  Body
//
//  The metrics Siri can be asked about. Deliberately free of any AppIntents
//  import so the answer builder and its tests stay pure; the `AppEnum`
//  conformance is added as an extension beside the intents.
//

import Foundation

enum BodySiriMetric: String, CaseIterable, Sendable {
    case readiness
    case sleep
    case heartRateVariability
    case restingHeartRate
    case heartRate
    case respiratoryRate
    case oxygenSaturation
    case wristTemperature
    case steps
    case exerciseMinutes

    /// The widget metric backing this answer. The widget snapshot is the cache
    /// the numbers come from, so the mapping must stay total.
    var widgetMetric: HealthWidgetMetric {
        switch self {
        case .readiness: return .readiness
        case .sleep: return .sleep
        case .heartRateVariability: return .heartRateVariability
        case .restingHeartRate: return .restingHeartRate
        case .heartRate: return .heartRate
        case .respiratoryRate: return .respiratoryRate
        case .oxygenSaturation: return .oxygenSaturation
        case .wristTemperature: return .wristTemperature
        case .steps: return .steps
        case .exerciseMinutes: return .exerciseMinutes
        }
    }

    /// Reuses the widget metric's localized name so Siri, the widgets and the
    /// app all say the same thing.
    var title: String {
        widgetMetric.title
    }
}
