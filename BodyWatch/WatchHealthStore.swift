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

    func latestHeartRate() async -> Double? {
        await latestQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    func latestHRV() async -> Double? {
        await latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            // Live readings only: an older sample is stale sensor data (watch
            // off-wrist, sensor off) and must not masquerade as current —
            // returning nil keeps the value the iPhone pushed.
            let windowStart = Date().addingTimeInterval(-4 * 60 * 60)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: windowStart, end: nil),
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
