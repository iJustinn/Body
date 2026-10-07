//
//  BodyMetricWarningFetch.swift
//  Body
//
//  The HealthKit read behind one of today's threshold warnings, shared by the
//  iOS `HealthKitFetchEngine` (`fetchTodayMetricWarning`) and the watch's own
//  check (`WatchDeltaFetcher`), so both devices read a warning the same way:
//  the same window, source predicate, threshold filter, sort and value
//  transform. Detection is `MetricThresholdWarning.detect`, which each caller
//  runs with its own workout exclusions.
//

import Foundation
import HealthKit

enum BodyMetricWarningFetch {
    /// Today's readings for `kind`, midnight in `calendar` to `now`, under
    /// `sourcePredicate`: dated at each sample's end, ascending, after the
    /// kind's descriptor transform, non-finite values dropped.
    ///
    /// Heart rate is dense (thousands of samples a day), so HealthKit does the
    /// threshold filtering and only past-threshold readings come back. Blood
    /// oxygen is sparse AND stored either as a 0–1 fraction or as 0–100
    /// depending on the source, so a native-unit threshold predicate would
    /// silently miss whole sources: its whole day comes back normalized and
    /// `detect` compares in memory. Respiratory rate and wrist temperature are
    /// sparse too, so they take the same in-memory path. A heart rate sample
    /// holding several readings (a series the watch writes) compares by its
    /// `quantity`, which is their average.
    ///
    /// `.success([])` for a kind with no query descriptor: nothing to read.
    static func todaysReadings(
        for kind: MetricWarningKind,
        store: any BodyHealthQuerying,
        sourcePredicate: NSPredicate?,
        threshold: Double,
        now: Date,
        calendar: Calendar,
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<[HealthTrendDataPoint]> {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind.metric),
              let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.quantityType) else {
            return .success([])
        }

        let windowPredicate = BodyHealthSourceResolver.combinedPredicate(
            startDate: calendar.startOfDay(for: now),
            endDate: now,
            sourcePredicate: sourcePredicate
        )
        let thresholdPredicate: NSPredicate? = kind.metric == .heartRate
            ? HKQuery.predicateForQuantitySamples(
                with: kind.isAbove ? .greaterThan : .lessThan,
                quantity: HKQuantity(unit: descriptor.unit, doubleValue: threshold)
            )
            : nil
        let predicate: NSPredicate?
        switch (windowPredicate, thresholdPredicate) {
        case (let window?, let threshold?):
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window, threshold])
        case (let window?, nil):
            predicate = window
        case (nil, let threshold):
            predicate = threshold
        }

        switch await BodyHealthQuantityFetch.quantitySampleSeries(
            store: store,
            quantityType: quantityType,
            predicate: predicate,
            unit: descriptor.unit,
            valueTransform: descriptor.valueTransform,
            onFailure: onFailure
        ) {
        case .failure:
            return .failure
        case .success(let series):
            return .success(series.points)
        }
    }
}
