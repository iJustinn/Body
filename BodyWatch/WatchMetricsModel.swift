//
//  WatchMetricsModel.swift
//  BodyWatch
//
//  Single source of truth on the watch: receives the iPhone's pushed snapshot
//  over WatchConnectivity, caches it for the complications, and runs the hybrid
//  live HR/HRV refresh when the pushed data is stale.
//

import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchMetricsModel: NSObject, ObservableObject {
    static let shared = WatchMetricsModel()

    @Published private(set) var snapshot: WatchMetricsSnapshot

    private let healthStore = WatchHealthStore()
    private var hasRequestedAuthorization = false

    private override init() {
        snapshot = WatchMetricsSnapshotStore.load() ?? .empty
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func onAppear() {
        if let stored = WatchMetricsSnapshotStore.load(), stored.generatedAt >= snapshot.generatedAt {
            snapshot = stored
        }
        Task { await refreshLiveMetricsIfStale() }
    }

    // MARK: - WatchConnectivity intake

    private func applyReceivedContext(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let received = WatchMetricsSnapshot.decoded(from: data),
              received.generatedAt > snapshot.generatedAt else { return }
        apply(merging(received))
    }

    /// Keep locally-measured metrics (live HR/HRV) when they're fresher than
    /// the vitals the phone snapshot was built from — a workout-only refresh
    /// re-sends old vitals and must not roll back a live reading.
    private func merging(_ received: WatchMetricsSnapshot) -> WatchMetricsSnapshot {
        let receivedVitalsDate = received.lastRefreshDate ?? .distantPast
        var merged = received
        merged.metrics = received.metrics.map { metric in
            guard let local = snapshot.metric(forKind: metric.kind),
                  let liveUpdatedAt = local.liveUpdatedAt,
                  liveUpdatedAt > receivedVitalsDate else { return metric }
            var kept = metric
            kept.displayValue = local.displayValue
            kept.unit = local.unit
            kept.rawValue = local.rawValue
            kept.fillFraction = local.fillFraction
            kept.liveUpdatedAt = local.liveUpdatedAt
            return kept
        }
        return merged
    }

    private func apply(_ newSnapshot: WatchMetricsSnapshot) {
        snapshot = newSnapshot
        WatchMetricsSnapshotStore.save(newSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Hybrid live refresh

    private var isStale: Bool {
        guard let last = snapshot.lastRefreshDate else { return true }
        return Date().timeIntervalSince(last) > WatchMetricsSnapshot.staleInterval
    }

    /// When the pushed snapshot is stale, refresh the watch-measurable metrics
    /// (HR, HRV) directly and recompute their fill against the carried range.
    func refreshLiveMetricsIfStale() async {
        guard isStale, !snapshot.metrics.isEmpty else { return }

        if !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            await healthStore.requestAuthorization()
        }

        async let heartRateReading = healthStore.latestHeartRate()
        async let hrvReading = healthStore.latestHRV()
        let (heartRate, hrv) = await (heartRateReading, hrvReading)
        guard heartRate != nil || hrv != nil else { return }

        var metrics = snapshot.metrics
        if let heartRate {
            metrics = updating(metrics, kind: WatchMetricKindKey.heartRate, value: heartRate, decimals: 0, unit: "bpm")
        }
        if let hrv {
            metrics = updating(metrics, kind: WatchMetricKindKey.heartRateVariability, value: hrv, decimals: 0, unit: "ms")
        }

        // Don't advance `generatedAt` on a local live refresh: a newer phone
        // snapshot (higher generatedAt) must still win so Readiness / Sleep /
        // Training Load aren't frozen behind a watch-only HR/HRV update.
        var updated = snapshot
        updated.metrics = metrics
        apply(updated)
    }

    private func updating(_ metrics: [WatchMetric], kind: String, value: Double, decimals: Int, unit: String) -> [WatchMetric] {
        guard let index = metrics.firstIndex(where: { $0.kind == kind }) else { return metrics }
        var result = metrics
        var metric = result[index]
        metric.displayValue = WatchValueFormat.number(value, decimals: decimals)
        metric.unit = unit
        metric.rawValue = value
        metric.fillFraction = WatchRingFill.fraction(of: value, min: metric.rangeMin, max: metric.rangeMax)
        metric.liveUpdatedAt = Date()
        result[index] = metric
        return result
    }
}

extension WatchMetricsModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        // Cold start: `receivedApplicationContext` is only populated once
        // activation completes, so adopt a context delivered while the app
        // wasn't running here rather than inline after `activate()`.
        Task { @MainActor in
            self.applyReceivedContext(WCSession.default.receivedApplicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyReceivedContext(applicationContext)
        }
    }
}
