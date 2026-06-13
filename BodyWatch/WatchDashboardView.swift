//
//  WatchDashboardView.swift
//  BodyWatch
//
//  Scrollable list of metric cards, in the iOS dashboard's visual language.
//

import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject private var model: WatchMetricsModel

    private var orderedMetrics: [WatchMetric] {
        WatchMetricKindKey.displayOrder.compactMap { model.snapshot.metric(forKind: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if orderedMetrics.isEmpty {
                    ContentUnavailableView(
                        "No Data Yet",
                        systemImage: "applewatch",
                        description: Text("Open Body on your iPhone to sync your metrics.")
                    )
                    .padding(.top, 20)
                } else {
                    VStack(spacing: 8) {
                        ForEach(orderedMetrics) { metric in
                            WatchMetricCardView(metric: metric)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .navigationTitle("Body")
        }
        .onAppear { model.onAppear() }
    }
}
