//
//  BodyWidgetExtensionBundle.swift
//  BodyWidgetExtension
//

import SwiftUI
import WidgetKit

@main
struct BodyWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        BodyWorkoutCalendarWidget()
        BodyWorkoutTypeBreakdownWidget()
        BodyHealthTrendWidget()
        BodySleepStagesWidget()
    }
}
