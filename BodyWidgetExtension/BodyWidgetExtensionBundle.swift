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
        BodyTrendCardWidget()             // large — Home's top trend, or a pinned one
        BodyExerciseWeekWidget()          // lock screen — weekly exercise minutes
        BodySleepStagesLockScreenWidget() // lock screen — sleep stages
    }
}
