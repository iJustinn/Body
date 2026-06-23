//
//  WatchDashboardView.swift
//  BodyWatch
//
//  Scrollable list of metric cards, in the iOS dashboard's visual language.
//

import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject private var model: WatchMetricsModel
    @State private var isRefreshing = false

    private var visibleMetrics: [WatchMetric] {
        model.snapshot.orderedMetrics.filter { model.isMetricVisible($0.kind) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.snapshot.orderedMetrics.isEmpty {
                    ContentUnavailableView(
                        "No Data Yet",
                        systemImage: "applewatch",
                        description: Text("Open Body on your iPhone to sync your metrics.")
                    )
                    .padding(.top, 20)
                } else if visibleMetrics.isEmpty {
                    ContentUnavailableView(
                        "All Metrics Hidden",
                        systemImage: "eye.slash",
                        description: Text("Turn metrics back on in Settings.")
                    )
                    .padding(.top, 20)
                } else {
                    VStack(spacing: 8) {
                        ForEach(visibleMetrics) { metric in
                            WatchMetricCardView(metric: metric)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        Task {
                            await model.refresh()
                            isRefreshing = false
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .onAppear { model.onAppear() }
    }
}
