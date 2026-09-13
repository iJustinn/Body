//
//  WatchDashboardView.swift
//  BodyWatch
//
//  The iOS Summary readiness hero (`WatchReadinessHeroView`) over a scrollable
//  list of metric cards, in the iOS dashboard's visual language. Readiness is
//  the hero only (no card). Tapping the hero or a card — or a metric
//  complication on the watch face — opens that metric's detail page in a
//  vertical-paging carousel.
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
    @State private var scrollState = WatchDashboardScrollState()
    @State private var heroState = WatchReadinessHeroState()
    /// The hero's resting top in screen coordinates, measured by the pin, so the
    /// page glow centers on the ring wherever the navigation bar puts the content.
    @State private var heroRestingTop: CGFloat = 0

    /// Name of the ScrollView's coordinate space, which the hero pin measures against.
    static let viewportCoordinateSpace = "watchDashboardViewport"
    /// Side padding of the content column; the hero draws at the width inside it.
    private static let horizontalPadding: CGFloat = 4
    /// Spacing between the hero and the cards, and between the cards.
    private static let gridSpacing: CGFloat = 8

    private var visibleMetrics: [WatchMetric] {
        model.snapshot.orderedMetrics.filter { model.isMetricVisible($0.kind) }
    }

    /// Readiness is drawn as the hero, never as a card.
    private var heroMetric: WatchMetric? {
        visibleMetrics.first { $0.kind == WatchMetricKindKey.readiness }
    }

    private var cardMetrics: [WatchMetric] {
        visibleMetrics.filter { $0.kind != WatchMetricKindKey.readiness }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { page in
                let heroWidth = max(0, page.size.width - 2 * Self.horizontalPadding)
                ZStack {
                    if heroMetric != nil {
                        WatchReadinessPageBackground(
                            heroState: heroState,
                            scrollState: scrollState,
                            circleCenterY: heroRestingTop + WatchReadinessHero.arcCenterY(width: heroWidth),
                            glowRadius: WatchReadinessHero.glowRadius(width: heroWidth)
                        )
                        .ignoresSafeArea()
                    }

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
                            VStack(spacing: Self.gridSpacing) {
                                if let heroMetric, heroWidth > 0 {
                                    // The pin (which reads scrollState) hands its progress to
                                    // the closure, so scrolling re-renders only that closure.
                                    WatchReadinessHeroScrollPin(
                                        scrollState: scrollState,
                                        width: heroWidth,
                                        heroRestingTop: $heroRestingTop
                                    ) { progress, pull in
                                        NavigationLink(value: heroMetric.kind) {
                                            WatchReadinessHeroView(
                                                score: heroMetric.score,
                                                width: heroWidth,
                                                progress: progress,
                                                pull: pull
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                ForEach(cardMetrics) { metric in
                                    NavigationLink(value: metric.kind) {
                                        WatchMetricCardView(metric: metric)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Self.horizontalPadding)
                        }
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, offset in
                        scrollState.offset = max(0, offset)
                        scrollState.pull = max(0, -offset)
                    }
                    // The hero pin measures its resting position in this space.
                    .coordinateSpace(name: Self.viewportCoordinateSpace)
                }
                .frame(width: page.size.width, height: page.size.height)
            }
            .environment(heroState)
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
