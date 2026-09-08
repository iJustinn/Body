//
//  WatchComplicationsProvider.swift
//  BodyWatchWidgetExtension
//
//  Reads the on-watch cached snapshot. Real updates arrive via
//  `WidgetCenter.reloadAllTimelines()` when the iPhone pushes or the watch app
//  freshens live metrics; the timeline carries a midnight entry (H-10) so a
//  night-ending Sleep card and the weekly bars advance without a launch, and
//  its fallback reload policy is just a slow backstop.
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
        // keeps the honest empty state. `sanitized` re-gates a cached snapshot's
        // Sleep metric at display time so a night that outlived midnight isn't
        // shown as today's.
        let now = Date()
        let stored = WatchMetricsSnapshotStore.load()?.sanitized(asOf: now)
        let snapshot = stored ?? (context.isPreview ? .placeholder : .empty)
        completion(WatchMetricEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchMetricEntry>) -> Void) {
        let now = Date()
        let snapshot = WatchMetricsSnapshotStore.load() ?? .empty
        let built = WatchComplicationTimeline.entries(snapshot: snapshot, now: now)
        let entries = built.entries.map { WatchMetricEntry(date: $0.date, snapshot: $0.snapshot) }
        completion(Timeline(entries: entries, policy: .after(built.reloadAfter)))
    }
}
