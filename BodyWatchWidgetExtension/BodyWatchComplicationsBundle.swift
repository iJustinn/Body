//
//  BodyWatchComplicationsBundle.swift
//  BodyWatchWidgetExtension
//
//  One ring-style complication per metric (matches the existing iOS
//  BodyWidgetExtensionBundle's static-per-widget pattern), each supporting
//  the circular ring, the rectangular row, and the corner gauge, plus two
//  rectangular-only bar complications (weekly Exercise minutes, last night's
//  Sleep stages) that lead the list.
//
//  Note: full magenta renders in the Smart Stack and full-color faces; in
//  tinted watch-face accessory slots the system recolors the ring (or bars)
//  to the face tint — expected watchOS behavior.
//

import SwiftUI
import WidgetKit

@main
struct BodyWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        ExerciseWeekComplication()
        SleepStagesComplication()
        ReadinessComplication()
        SleepComplication()
        HeartRateComplication()
        HRVComplication()
        RestingHeartRateComplication()
        TrainingLoadComplication()
        SkinTemperatureComplication()
    }
}

private let complicationFamilies: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryCorner]

/// Shared configuration for the per-metric complications. WidgetKit needs a
/// distinct `Widget` type per kind; only these parameters differ.
private func metricComplication(
    widgetKind: String,
    metricKind: String,
    displayName: String,
    description: String
) -> some WidgetConfiguration {
    StaticConfiguration(kind: widgetKind, provider: WatchMetricProvider()) { entry in
        WatchComplicationView(metricKind: metricKind, entry: entry)
            // Tapping the complication opens this metric's detail page directly.
            .widgetURL(WatchMetricDeepLink.url(forKind: metricKind))
    }
    .configurationDisplayName(displayName)
    .description(description)
    .supportedFamilies(complicationFamilies)
}

struct ReadinessComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchReadiness", metricKind: WatchMetricKindKey.readiness,
            displayName: String(localized: "Readiness"), description: String(localized: "Your readiness ring.")
        )
    }
}

struct SleepComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchSleep", metricKind: WatchMetricKindKey.sleep,
            displayName: String(localized: "Sleep"), description: String(localized: "Your sleep score ring.")
        )
    }
}

struct HeartRateComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchHeartRate", metricKind: WatchMetricKindKey.heartRate,
            displayName: String(localized: "Heart Rate"), description: String(localized: "Your heart rate ring.")
        )
    }
}

struct HRVComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchHRV", metricKind: WatchMetricKindKey.heartRateVariability,
            displayName: String(localized: "HRV"), description: String(localized: "Your heart rate variability ring.")
        )
    }
}

struct RestingHeartRateComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchRestingHeartRate", metricKind: WatchMetricKindKey.restingHeartRate,
            displayName: String(localized: "Resting HR"), description: String(localized: "Your resting heart rate ring.")
        )
    }
}

struct TrainingLoadComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchTrainingLoad", metricKind: WatchMetricKindKey.trainingLoad,
            displayName: String(localized: "Training Load"), description: String(localized: "Your training load ring.")
        )
    }
}

struct SkinTemperatureComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchSkinTemperature", metricKind: WatchMetricKindKey.wristTemperature,
            displayName: String(localized: "Skin Temp"), description: String(localized: "Your skin temperature ring.")
        )
    }
}
