//
//  MetricWarningNotificationContent.swift
//  Body
//
//  A threshold warning notification's title and body, shared by the iPhone's
//  background evaluator (`MetricWarningBackgroundEvaluator`) and the watch's
//  own notifier, so a warning reads the same whichever device alerts. In the
//  kit the two apps share rather than BodyMetricsKit, which the widgets also
//  compile and which has no use for this copy. The keys are the iPhone
//  catalog's, and the watch catalog carries the same keys.
//

import Foundation

enum MetricWarningNotificationContent {
    static func title(for kind: MetricWarningKind) -> String {
        switch kind {
        case .lowHeartRate:
            return String(localized: "Low Heart Rate Warning")
        case .highHeartRate:
            return String(localized: "High Heart Rate Warning")
        case .lowBloodOxygen:
            return String(localized: "Low Blood Oxygen Warning")
        case .highRespiratoryRate:
            return String(localized: "High Respiratory Rate Warning")
        case .highWristTemperature:
            return String(localized: "High Skin Temperature Warning")
        }
    }

    /// The episode's extreme reading against its threshold. A skin temperature
    /// reads in `temperatureUnitPreference`; the other kinds have one unit.
    static func body(
        for event: MetricWarningEvent,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference
    ) -> String {
        let threshold = Int(event.threshold.rounded())
        let value = Int(event.extremeValue.rounded())

        switch event.kind {
        case .lowHeartRate:
            return String(localized: "A periodic check found a heart rate of \(value) bpm today, below your \(threshold) bpm limit.")
        case .highHeartRate:
            return String(localized: "A periodic check found a heart rate of \(value) bpm today, above your \(threshold) bpm limit.")
        case .lowBloodOxygen:
            return String(localized: "A periodic check found a blood oxygen level of \(value)% today, below your \(threshold)% limit.")
        case .highRespiratoryRate:
            return String(localized: "A periodic check found a respiratory rate of \(value) br/min today, above your \(threshold) br/min limit.")
        case .highWristTemperature:
            let reading = BodyMetricWarningTemperatureText.text(celsius: event.extremeValue, temperatureUnitPreference: temperatureUnitPreference)
            let limit = BodyMetricWarningTemperatureText.text(celsius: event.threshold, temperatureUnitPreference: temperatureUnitPreference)
            return String(localized: "A periodic check found a skin temperature of \(reading) today, above your \(limit) limit.")
        }
    }
}
