//
//  WatchHealthStore.swift
//  BodyWatch
//
//  Hybrid live path: reads the watch's own latest HR / HRV samples directly
//  from HealthKit so the watch can freshen those metrics when the iPhone's
//  pushed snapshot is stale. The heavy scores (Readiness, Sleep, Training Load)
//  are never recomputed here — they come from the iPhone.
//

import Foundation
import HealthKit

actor WatchHealthStore {
    private let store = HKHealthStore()

    /// Authorizes only the live HR/HRV reads — the only HealthKit the watch
    /// reads. Readiness, Sleep, and Training Load come from the iPhone snapshot.
    func requestLiveAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var read: Set<HKObjectType> = []
        [HKQuantityTypeIdentifier.heartRate, .heartRateVariabilitySDNN]
            .compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { read.insert($0) }
        guard !read.isEmpty else { return }
        try? await store.requestAuthorization(toShare: [], read: read)
    }

    func latestHeartRate() async -> (value: Double, measuredAt: Date)? {
        await latestQuantity(
            .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            freshnessLimit: WatchMetricKindKey.liveFreshnessLimit(forKind: WatchMetricKindKey.heartRate)
        )
    }

    func latestHRV() async -> (value: Double, measuredAt: Date)? {
        await latestQuantity(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            freshnessLimit: WatchMetricKindKey.liveFreshnessLimit(forKind: WatchMetricKindKey.heartRateVariability)
        )
    }

    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        freshnessLimit: TimeInterval
    ) async -> (value: Double, measuredAt: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            // Live readings only: a sample older than this kind's freshness limit
            // is stale sensor data (watch off-wrist, sensor off) and must not
            // masquerade as current — returning nil keeps the value the iPhone
            // pushed. The window is per-kind (HR ages fast, HRV slowly) so the
            // accepted sample matches what `WatchMetricsModel.isStale` considers
            // fresh and can't wedge the live-read loop.
            let windowStart = Date().addingTimeInterval(-freshnessLimit)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: windowStart, end: nil),
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate))
            }
            store.execute(query)
        }
    }
}
