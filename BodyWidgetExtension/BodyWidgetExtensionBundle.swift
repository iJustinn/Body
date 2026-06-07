//
//  BodyWidgetExtensionBundle.swift
//  BodyWidgetExtension
//

import SwiftUI
import WidgetKit

@main
struct BodyWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        BodyHealthMetricWidget()          // small — metric trend preview
        BodyHealthTrendWidget()           // medium — trend
        BodySleepStagesWidget()           // medium — sleep stages
        BodyWorkoutTypeBreakdownWidget()  // medium + large — workout type
        BodyWorkoutCalendarWidget()       // large — workout calendar
    }
}
