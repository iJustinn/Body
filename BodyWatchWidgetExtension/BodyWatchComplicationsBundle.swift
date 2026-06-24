//
//  BodyWatchComplicationsBundle.swift
//  BodyWatchWidgetExtension
//
//  One ring-style complication per metric (matches the existing iOS
//  BodyWidgetExtensionBundle's static-per-widget pattern). Each supports the
//  circular ring, the rectangular row, and the corner gauge.
//
//  Note: full magenta renders in the Smart Stack and full-color faces; in
//  tinted watch-face accessory slots the system recolors the ring to the face
//  tint — expected watchOS behavior.
//

import SwiftUI
import WidgetKit

@main
struct BodyWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
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
            displayName: "Readiness", description: "Your readiness ring."
        )
    }
}

struct SleepComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchSleep", metricKind: WatchMetricKindKey.sleep,
            displayName: "Sleep", description: "Your sleep score ring."
        )
    }
}

struct HeartRateComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchHeartRate", metricKind: WatchMetricKindKey.heartRate,
            displayName: "Heart Rate", description: "Your heart rate ring."
        )
    }
}

struct HRVComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchHRV", metricKind: WatchMetricKindKey.heartRateVariability,
            displayName: "HRV", description: "Your heart rate variability ring."
        )
    }
}

struct RestingHeartRateComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchRestingHeartRate", metricKind: WatchMetricKindKey.restingHeartRate,
            displayName: "Resting HR", description: "Your resting heart rate ring."
        )
    }
}

struct TrainingLoadComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchTrainingLoad", metricKind: WatchMetricKindKey.trainingLoad,
            displayName: "Training Load", description: "Your training load ring."
        )
    }
}

struct SkinTemperatureComplication: Widget {
    var body: some WidgetConfiguration {
        metricComplication(
            widgetKind: "BodyWatchSkinTemperature", metricKind: WatchMetricKindKey.wristTemperature,
            displayName: "Skin Temp", description: "Your skin temperature ring."
        )
    }
}
