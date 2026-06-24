//
//  WatchComplicationsProvider.swift
//  BodyWatchWidgetExtension
//
//  Reads the on-watch cached snapshot. Real updates arrive via
//  `WidgetCenter.reloadAllTimelines()` when the iPhone pushes or the watch app
//  freshens live metrics; the timeline policy is just a slow fallback.
//

import WidgetKit

struct WatchMetricEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchMetricsSnapshot
}

struct WatchMetricProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchMetricEntry {
        WatchMetricEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchMetricEntry) -> Void) {
        // Gallery previews fall back to sample data; a configured complication
        // keeps the honest empty state.
        let stored = WatchMetricsSnapshotStore.load()
        let snapshot = stored ?? (context.isPreview ? .placeholder : .empty)
        completion(WatchMetricEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchMetricEntry>) -> Void) {
        let snapshot = WatchMetricsSnapshotStore.load() ?? .empty
        let entry = WatchMetricEntry(date: Date(), snapshot: snapshot)
        let next = Date().addingTimeInterval(WatchMetricsSnapshot.staleInterval)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
