//
//  WatchDashboardView.swift
//  BodyWatch
//
//  Scrollable list of metric cards, in the iOS dashboard's visual language.
//  Tapping a card — or a metric complication on the watch face — opens that
//  metric's detail page in a vertical-paging carousel.
//

import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject private var model: WatchMetricsModel
    @State private var path: [String] = []
    /// Bumped on every complication deep-link, folded into the detail pager's
    /// `.id`. Re-tapping the complication for the metric already on screen sets
    /// `path` to its current value — a no-op that wouldn't rebuild the pager — so
    /// without this token a repeat tap would leave the user on whatever metric
    /// they'd swiped to instead of the tapped one.
    @State private var deepLinkToken = 0
    @State private var isRefreshing = false

    private var visibleMetrics: [WatchMetric] {
        model.snapshot.orderedMetrics.filter { model.isMetricVisible($0.kind) }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                            NavigationLink(value: metric.kind) {
                                WatchMetricCardView(metric: metric)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .navigationTitle("Body")
            .navigationDestination(for: String.self) { kind in
                // Key the pager on the metric *and* the deep-link token, so opening
                // a different metric — or re-tapping the same metric's complication
                // while its pager is already open — makes a fresh pager that
                // re-positions onto it (vs. reusing one stuck on the page the user
                // last swiped to).
                WatchMetricDetailPager(initialKind: kind)
                    .id("\(kind)#\(deepLinkToken)")
            }
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
        .onOpenURL { url in
            // A metric complication deep-links straight to its detail page. Bump
            // the token first so re-tapping the metric already on screen still
            // rebuilds the pager onto it (setting `path` to its current value is a
            // no-op on its own).
            if let kind = WatchMetricDeepLink.kind(from: url) {
                deepLinkToken += 1
                path = [kind]
            }
        }
    }
}
