//
//  WatchMetricDetailPager.swift
//  BodyWatch
//
//  The metric detail surface: a vertical-paging carousel of every visible
//  metric's detail page, in the dashboard's order. Swipe up/down or turn the
//  Digital Crown to move between metrics (the right-edge page dots track
//  position). Entered from a dashboard card or a complication tap, it opens
//  positioned on the chosen metric — the order doesn't change.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchMetricDetailPager: View {
    @EnvironmentObject private var model: WatchMetricsModel
    private let initialKind: String
    @State private var selection: String?

    init(initialKind: String) {
        self.initialKind = initialKind
    }

    /// Dashboard order, unchanged — plus the entry metric even if it's hidden (a
    /// complication can deep-link to a metric hidden from the dashboard).
    private var metrics: [WatchMetric] {
        model.snapshot.orderedMetrics.filter {
            model.isMetricVisible($0.kind) || $0.kind == initialKind
        }
    }

    var body: some View {
        // Page only when the deep-linked metric is actually in the snapshot. A
        // complication can point at a metric the phone has since dropped (its
        // health category was disabled, or nothing has synced yet) while other
        // metrics remain visible; entering the pager then would select a tag that
        // isn't among the pages and land on a blank/wrong page. Show the no-data
        // state instead.
        if metrics.contains(where: { $0.kind == initialKind }) {
            TabView(selection: $selection) {
                ForEach(metrics) { metric in
                    WatchMetricDetailView(metric: metric, generatedAt: model.snapshot.generatedAt)
                        .tag(metric.kind as String?)
                }
            }
            .tabViewStyle(.verticalPage)
            .onAppear {
                // Open positioned on the tapped metric while keeping the dashboard
                // order. `.verticalPage` ignores the *initial* selection (it lands on
                // the first page), so set it once the pager has appeared — without
                // animation, so it opens directly on the metric rather than scrolling.
                guard selection == nil else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { selection = initialKind }
            }
            .onChange(of: metrics.map(\.kind)) { _, kinds in
                // A phone push can drop the currently-selected metric out of
                // `metrics` mid-visit (its health category was disabled, or it
                // fell off the snapshot) while other metrics remain — TabView's
                // selection would then name a tag with no matching page and
                // render blank. `initialKind` is always present here (the guard
                // above), so fall back to it, without animation so the page swap
                // doesn't scroll past whatever's left.
                guard let selection, !kinds.contains(selection) else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { self.selection = initialKind }
            }
        } else {
            ContentUnavailableView(
                "No Data Yet",
                systemImage: "applewatch",
                description: Text("Open Body on your iPhone to sync your metrics.")
            )
        }
    }
}
