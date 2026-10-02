//
//  HealthKitFetchEngine+HeartbeatSeries.swift
//  Body
//
//  RMSSD for the Stress metric and the HRV page's Recovery view. On iOS 27
//  Apple writes it as its own quantity (`heartRateVariabilityRMSSD`, the
//  "Recovery HRV" of Apple Watch Series 12 and Ultra 4), which is one ordinary
//  sample query. Older watches write none, so each `HKHeartbeatSeriesSample`
//  is streamed beat by beat and reduced through `StressRMSSD` (shared with the
//  calculator's tests, so the math has exactly one implementation) instead.
//  The scan itself lives in the shared `BodyHeartbeatRMSSDFetch`, which the
//  watch's Stress compute runs too. It is deliberately kept OFF the critical
//  refresh path: it is a fan-out of streaming queries and the refresh deadline
//  must never wait on it.
//

import Foundation
import HealthKit

extension HealthKitFetchEngine {
    /// Apple's Recovery HRV quantity, `nil` below iOS 27 where the type does
    /// not exist. Every Recovery HRV read goes through this so the fetches
    /// below stay one `#available` check, not five.
    nonisolated static var recoveryHRVIdentifier: HKQuantityTypeIdentifier? {
        BodyHeartbeatRMSSDFetch.recoveryHRVIdentifier
    }

    /// Every Recovery HRV sample in the window, under the HRV metric's primary
    /// source (or `sourceOption`, the comparison source). `nil` when the query
    /// failed so callers keep their cache; `.empty` below iOS 27 and for a
    /// watch that writes none.
    func fetchRecoveryHRVSamples(
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .bodyGregorian,
        sourceOption: BodyHealthDataSourceOption? = nil
    ) async -> HealthTrendSeries? {
        guard let identifier = Self.recoveryHRVIdentifier else { return .empty }
        return await fetchQuantitySampleSeries(
            for: identifier,
            unit: .secondUnit(with: .milli),
            calendar: calendar,
            sourceKind: .heartRateVariability,
            sourceOption: sourceOption,
            startDate: startDate,
            endDate: endDate
        )
    }

    /// Daily average plus min/max range of Recovery HRV over the trend window,
    /// the HRV page's Recovery year chart (the same bars-and-line chart as
    /// Overall). Both come out of one statistics collection. `.empty` below
    /// iOS 27, `nil` on a failed query.
    func fetchRecoveryHRVTrendPair(calendar: Calendar, maxDays: Int? = nil) async -> (HealthTrendSeries, HealthTrendRangeSeries)? {
        guard let identifier = Self.recoveryHRVIdentifier else { return (.empty, .empty) }
        return await fetchDailyQuantityAverageAndRangeSeries(
            for: identifier,
            unit: .secondUnit(with: .milli),
            calendar: calendar,
            sourceKind: .heartRateVariability,
            maxDays: maxDays
        )
    }

    /// The comparison source's daily Recovery HRV range. No comparison selected
    /// returns an intentional `.empty` that clears the cached series, like
    /// `fetchSecondaryRangeTrend`.
    func fetchSecondaryRecoveryHRVRangeTrend(calendar: Calendar) async -> HealthTrendRangeSeries? {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: .heartRateVariability)
        guard !secondaryOption.isNoComparison, let identifier = Self.recoveryHRVIdentifier else {
            return .empty
        }
        return await fetchDailyQuantityRangeSeries(
            for: identifier,
            unit: .secondUnit(with: .milli),
            calendar: calendar,
            sourceKind: .heartRateVariability,
            sourceOption: secondaryOption
        )
    }

    /// The primary source's Recovery HRV samples merged onto the cached Stress
    /// input series, for a per-metric HRV refresh (the pull on the HRV page).
    /// `nil` when the read FAILED, so the caller keeps the cache and reports
    /// the failure like every other day-sample leaf. A successful empty read
    /// returns `cached` untouched rather than an authoritative empty: it must
    /// never erase a beat-to-beat scan cached by an older watch, and a watch
    /// that writes no Recovery HRV is not a failure.
    func refreshedRecoveryHRVDaySamples(
        cached: HealthTrendSeries,
        calendar: Calendar,
        reconcilesRetainedWindow: Bool
    ) async -> HealthTrendSeries? {
        let interval = intradayDaySampleInterval(calendar: calendar)
        let fetchStart = reconcilesRetainedWindow
            ? interval.start
            : Self.incrementalFetchStart(after: cached, windowStart: interval.start)
        guard fetchStart < interval.end else { return cached }
        guard let incoming = await fetchRecoveryHRVSamples(startDate: fetchStart, endDate: interval.end, calendar: calendar) else {
            return nil
        }
        guard !incoming.isEmpty else { return cached }
        return Self.mergeIntradaySamples(
            existing: cached,
            incoming: incoming,
            windowStart: interval.start,
            refetchStart: fetchStart
        )
    }

    /// The comparison source's Recovery HRV samples in the window; `.empty`
    /// with no comparison selected so the cached series clears.
    func fetchSecondaryRecoveryHRVSamples(
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .bodyGregorian
    ) async -> HealthTrendSeries? {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: .heartRateVariability)
        guard !secondaryOption.isNoComparison else { return .empty }
        return await fetchRecoveryHRVSamples(
            startDate: startDate,
            endDate: endDate,
            calendar: calendar,
            sourceOption: secondaryOption
        )
    }

    /// The Stress metric's RMSSD series for the window: Apple's Recovery HRV
    /// samples when the watch writes any, otherwise one RMSSD point per readable
    /// heartbeat series, dated on the series' `endDate` so it lines up with the
    /// SDNN samples the calculator compares it against.
    ///
    /// Returns `nil` when the scan itself failed (device locked, store
    /// unavailable, XPC drop, unresolved source selection, cancellation, or the
    /// overall timeout) so the store keeps its cached RMSSD series instead of
    /// blanking it; a successful empty result — the simulator, or a user whose
    /// watch records no beat-to-beat data — returns `.empty` and lets Stress
    /// degrade to the SDNN path. Individual series that fail, time out, or
    /// carry too few clean intervals are dropped without failing the fetch.
    func fetchHeartbeatRMSSDSamples(startDate: Date, endDate: Date) async -> HealthTrendSeries? {
        // The RMSSD series is an HRV input, so it must be constrained to the
        // same source the HRV metric is pinned to — otherwise a pinned SDNN
        // source would be scored against another device's beat-to-beat data.
        if sourceSelectionUnresolved(for: .heartRateVariability) {
            return nil
        }

        // Apple's own RMSSD first: it is the number the user sees as Recovery
        // HRV, and one sample query replaces the 120-series scan. A failed
        // query or a watch that writes none falls through to the scan.
        if let recovery = await fetchRecoveryHRVSamples(startDate: startDate, endDate: endDate),
           !recovery.isEmpty {
            return recovery
        }

        let predicate = combinedPredicate(
            startDate: startDate,
            endDate: endDate,
            sourceKind: .heartRateVariability
        )

        // The scan itself (series list, beat streams, per-series and overall
        // deadlines) is shared with the watch's Stress compute; the phone runs
        // it under its own limits, every query it issues taking a pool permit.
        let series: HealthTrendSeries?
        switch await BodyHeartbeatRMSSDFetch.scan(
            store: healthStore,
            predicate: predicate,
            limits: .phone,
            admission: Self.heartbeatQueryAdmission,
            onFailure: { Self.logTrendQueryFailure($0, error: $1) }
        ) {
        case .success(let scanned):
            series = scanned
        case .failure:
            series = nil
        }

        if series == nil {
            Self.logTrendQueryFailure("heartbeatSeriesRMSSD", error: nil)
        }

        return series
    }

    /// Admits each query of the shared heartbeat scan the way
    /// `runCancellableQuery` admits one: a permit from the current task's pool,
    /// the background lease check, and the refresh profile's query depth, all
    /// handed back when the query ends. Read at call time, so the scan's tasks
    /// see the pool the caller bound (`withBackgroundQueryPool`).
    nonisolated static let heartbeatQueryAdmission: BodyHeartbeatRMSSDFetch.QueryAdmission = {
        let semaphore = HealthKitQueryPool.current.semaphore
        guard await semaphore.acquireForCurrentTask() else { return nil }
        guard BodyBackgroundLease.current?.isValid != false else {
            semaphore.release()
            return nil
        }
        BodyRefreshProfile.shared.enterQuery()
        return {
            BodyRefreshProfile.shared.exitQuery()
            semaphore.release()
        }
    }
}
