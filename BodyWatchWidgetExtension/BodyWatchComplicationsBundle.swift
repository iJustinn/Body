//
//  BodyWatchComplicationsBundle.swift
//  BodyWatchWidgetExtension
//
//  One ring-style complication per metric (matches the existing iOS
//  BodyWidgetExtensionBundle's static-per-widget pattern), each supporting
//  the circular ring, the rectangular row, and the corner gauge, plus the bar
//  and intraday chart complications. The picker lists Sleep Stages first,
//  then the week bar charts (Weekly Workout Time, then this week's daily
//  Steps, Active Energy and Resting Energy), then the intraday charts
//  (Stress, Heart Rate, HRV), then the rest in the watch's card order. Steps,
//  Active Energy and Resting Energy are also rings in circular slots, so they
//  lead that list too, and gauges in corner slots like the rest. Readiness
//  draws the home hero's segmented bands instead of the single ring
//  (`ReadinessComplicationView`), and a second circular Readiness
//  complication draws the single ring. Stress has its own
//  circular, rectangular and corner complication (`StressComplication`), which
//  shows the latest reading rather than the card's daily average, and a second
//  circular one draws that reading on Stress's bands.
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
        SleepStagesComplication()
        ExerciseWeekComplication()
        StepsWeekComplication()
        ActiveEnergyWeekComplication()
        RestingEnergyWeekComplication()
        StressChartComplication()
        HeartRateChartComplication()
        HRVChartComplication()
        ReadinessComplication()
        ReadinessRingComplication()
        SleepComplication()
        TrainingLoadComplication()
        StressComplication()
        StressBandsComplication()
        HeartRateComplication()
        HRVComplication()
        RestingHeartRateComplication()
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
        Group {
            if metricKind == WatchMetricKindKey.readiness {
                ReadinessComplicationView(entry: entry)
            } else {
                WatchComplicationView(metricKind: metricKind, entry: entry)
            }
        }
        // Tapping the complication opens this metric's detail page directly,
        // except Readiness, which opens the home page where its hero lives.
        .widgetURL(
            metricKind == WatchMetricKindKey.readiness
                ? WatchMetricDeepLink.homeURL
                : WatchMetricDeepLink.url(forKind: metricKind)
        )
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

/// Readiness in the single ring the other metrics draw (`WatchComplicationView`),
/// circular only. A tap opens the home page, like the bands complication.
struct ReadinessRingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchReadinessRing", provider: WatchMetricProvider()) { entry in
            WatchComplicationView(metricKind: WatchMetricKindKey.readiness, entry: entry)
                .widgetURL(WatchMetricDeepLink.homeURL)
        }
        .configurationDisplayName(String(localized: "Readiness"))
        .description(String(localized: "Your readiness score ring."))
        .supportedFamilies([.accessoryCircular])
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
