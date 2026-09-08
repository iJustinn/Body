//
//  HealthMetricQueryDescriptor.swift
//  Body
//
//  The one table describing HOW a quantity-backed metric is queried: which
//  HealthKit type, in which unit, under which source-selection kind and
//  permission, through which value transform, and with which query shape for
//  the summary tile, the daily trend, and the intraday day chart.
//
//  The same tuple used to be spelled out independently in `fetchHealthSummary`,
//  `fetchHealthTrends`, `fetchHealthDashboardSnapshot`,
//  `HealthKitFetchEngine+Secondary`, `HealthKitFetchEngine+IntradaySamples` and
//  the watch's `WatchDeltaFetcher` — six places that could only disagree
//  silently (issues-fable-51 A4 / S-11). Every one of them now reads this table,
//  so a unit or source-kind change lands in one row.
//
//  Six kinds are deliberately NOT here, because they are not a single quantity
//  query: `.readiness` and `.stress` are derived, `.sleep` and `.vitals` are
//  category-sample sessionization, `.basics` only fans out to the three body
//  measurements below, and `.trainingLoad` is its own workout-derived system.
//  `HealthMetricDescriptorTests` pins that list exhaustively.
//

import Foundation
import HealthKit

struct HealthMetricQueryDescriptor: Sendable {
    /// The shape of the "current value" query behind a summary tile.
    enum SummaryQuery: Equatable {
        case latestSample
        case dailyCumulative
        case dailyAverage
    }

    /// The shape of the daily-series query behind a trend chart. The associated
    /// aggregation is also what the watch's delta re-query runs with, so a
    /// spliced watch point stays comparable with the phone's series.
    enum TrendQuery: Equatable {
        case daily(BodyDailyQuantityAggregation)
        case dailyCumulative
        case averageAndRange(BodyDailyQuantityAggregation)
    }

    /// The shape of the intraday (hourly / per-sample) query behind a day chart.
    enum DaySampleQuery: Equatable {
        case sampleSeries
        case hourlyCumulative
    }

    let kind: HealthMetricKind
    let quantityType: HKQuantityTypeIdentifier
    let unit: HKUnit
    /// The kind whose source selection this metric's queries are filtered by:
    /// itself, except the three body measurements, which share `.basics`.
    let sourceKind: HealthMetricKind
    /// `false` only for `.cardioFitness`, which is deliberately absent from
    /// `HealthMetricKind.sourceSelectableKinds`: its queries pass no source kind
    /// at all rather than resolving one.
    let isSourceSelectable: Bool
    let permission: BodyHealthPermission
    /// Identity, or `BodyHealthQuantityFetch.normalizedPercent` for the two
    /// percentage reads whose sources disagree about 0…1 versus 0…100.
    let valueTransform: @Sendable (Double) -> Double
    let summary: SummaryQuery
    let trend: TrendQuery
    /// The primary-source intraday shape, `nil` when the metric has no intraday
    /// fetch. Present for `.restingHeartRate` even though it has no day view
    /// (`HealthMetricKind.dayViewKinds` excludes it) — a preserved divergence.
    let intradayDaySamples: DaySampleQuery?
    /// The comparison-source intraday shape, `nil` when there is none. Absent
    /// for `.respiratoryRate`, which has an intraday fetch but no comparison
    /// day line — the second preserved divergence.
    let secondaryDaySamples: DaySampleQuery?
    /// Whether a comparison-source daily series is fetched for this kind.
    let secondaryTrend: Bool
    /// Whether a comparison-source daily RANGE series is fetched for this kind.
    let secondaryRangeTrend: Bool

    /// The daily aggregation the watch's delta re-query runs with, or `nil` for
    /// the cumulative kinds the watch does not re-query.
    var dailyAggregation: BodyDailyQuantityAggregation? {
        switch trend {
        case .daily(let aggregation), .averageAndRange(let aggregation):
            return aggregation
        case .dailyCumulative:
            return nil
        }
    }

    /// The source kind a query is filtered by, or `nil` for the kinds that are
    /// not source-selectable and must query every source.
    var querySourceKind: HealthMetricKind? {
        isSourceSelectable ? sourceKind : nil
    }

    private init(
        _ kind: HealthMetricKind,
        _ quantityType: HKQuantityTypeIdentifier,
        unit: HKUnit,
        sourceKind: HealthMetricKind? = nil,
        isSourceSelectable: Bool = true,
        permission: BodyHealthPermission,
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 },
        summary: SummaryQuery,
        trend: TrendQuery,
        intradayDaySamples: DaySampleQuery? = nil,
        secondaryDaySamples: DaySampleQuery? = nil,
        secondaryTrend: Bool = false,
        secondaryRangeTrend: Bool = false
    ) {
        self.kind = kind
        self.quantityType = quantityType
        self.unit = unit
        self.sourceKind = sourceKind ?? kind
        self.isSourceSelectable = isSourceSelectable
        self.permission = permission
        self.valueTransform = valueTransform
        self.summary = summary
        self.trend = trend
        self.intradayDaySamples = intradayDaySamples
        self.secondaryDaySamples = secondaryDaySamples
        self.secondaryTrend = secondaryTrend
        self.secondaryRangeTrend = secondaryRangeTrend
    }

    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    static let all: [HealthMetricKind: HealthMetricQueryDescriptor] = [
        .heartRate: HealthMetricQueryDescriptor(
            .heartRate, .heartRate,
            unit: beatsPerMinute,
            permission: .heart,
            summary: .latestSample,
            trend: .averageAndRange(.average),
            intradayDaySamples: .sampleSeries,
            secondaryDaySamples: .sampleSeries,
            secondaryRangeTrend: true
        ),
        .restingHeartRate: HealthMetricQueryDescriptor(
            .restingHeartRate, .restingHeartRate,
            unit: beatsPerMinute,
            permission: .heart,
            summary: .latestSample,
            trend: .daily(.average),
            intradayDaySamples: .sampleSeries,
            secondaryDaySamples: .sampleSeries,
            secondaryTrend: true
        ),
        .bodyMass: HealthMetricQueryDescriptor(
            .bodyMass, .bodyMass,
            unit: .gramUnit(with: .kilo),
            sourceKind: .basics,
            permission: .basics,
            summary: .latestSample,
            trend: .daily(.latest)
        ),
        .bodyFatPercentage: HealthMetricQueryDescriptor(
            .bodyFatPercentage, .bodyFatPercentage,
            unit: .percent(),
            sourceKind: .basics,
            permission: .basics,
            valueTransform: BodyHealthQuantityFetch.normalizedPercent,
            summary: .latestSample,
            trend: .daily(.latest)
        ),
        .heartRateVariability: HealthMetricQueryDescriptor(
            .heartRateVariability, .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            permission: .heart,
            summary: .latestSample,
            trend: .averageAndRange(.average),
            intradayDaySamples: .sampleSeries,
            secondaryDaySamples: .sampleSeries,
            secondaryRangeTrend: true
        ),
        .respiratoryRate: HealthMetricQueryDescriptor(
            .respiratoryRate, .respiratoryRate,
            unit: beatsPerMinute,
            permission: .respiratory,
            summary: .latestSample,
            trend: .averageAndRange(.average),
            intradayDaySamples: .sampleSeries
        ),
        .oxygenSaturation: HealthMetricQueryDescriptor(
            .oxygenSaturation, .oxygenSaturation,
            unit: .percent(),
            permission: .bloodOxygen,
            valueTransform: BodyHealthQuantityFetch.normalizedPercent,
            summary: .latestSample,
            trend: .averageAndRange(.average),
            intradayDaySamples: .sampleSeries,
            secondaryDaySamples: .sampleSeries,
            secondaryRangeTrend: true
        ),
        .bodyMassIndex: HealthMetricQueryDescriptor(
            .bodyMassIndex, .bodyMassIndex,
            unit: .count(),
            sourceKind: .basics,
            permission: .basics,
            summary: .latestSample,
            trend: .daily(.latest)
        ),
        .activeEnergy: HealthMetricQueryDescriptor(
            .activeEnergy, .activeEnergyBurned,
            unit: .kilocalorie(),
            permission: .energy,
            summary: .dailyCumulative,
            trend: .dailyCumulative,
            intradayDaySamples: .hourlyCumulative,
            secondaryDaySamples: .hourlyCumulative,
            secondaryTrend: true
        ),
        .restingEnergy: HealthMetricQueryDescriptor(
            .restingEnergy, .basalEnergyBurned,
            unit: .kilocalorie(),
            permission: .energy,
            summary: .dailyCumulative,
            trend: .dailyCumulative,
            secondaryTrend: true
        ),
        .exerciseMinutes: HealthMetricQueryDescriptor(
            .exerciseMinutes, .appleExerciseTime,
            unit: .minute(),
            permission: .exerciseMinutes,
            summary: .dailyCumulative,
            trend: .dailyCumulative,
            secondaryTrend: true
        ),
        .wristTemperature: HealthMetricQueryDescriptor(
            .wristTemperature, .appleSleepingWristTemperature,
            unit: .degreeCelsius(),
            permission: .wristTemperature,
            summary: .dailyAverage,
            trend: .daily(.average)
        ),
        .timeInDaylight: HealthMetricQueryDescriptor(
            .timeInDaylight, .timeInDaylight,
            unit: .minute(),
            permission: .timeInDaylight,
            summary: .dailyCumulative,
            trend: .dailyCumulative
        ),
        .steps: HealthMetricQueryDescriptor(
            .steps, .stepCount,
            unit: .count(),
            permission: .steps,
            summary: .dailyCumulative,
            trend: .dailyCumulative,
            intradayDaySamples: .hourlyCumulative,
            secondaryDaySamples: .hourlyCumulative,
            secondaryTrend: true
        ),
        // `latestSample`, not a daily summary: Apple Watch writes one VO₂max
        // estimate every few days at best, so the newest reading in the trend
        // window is the current value. Not source-selectable, so its queries
        // pass no source kind and `BodyHealthSourceResolver.sourceSampleTypes`
        // reports none for it.
        .cardioFitness: HealthMetricQueryDescriptor(
            .cardioFitness, .vo2Max,
            unit: HKUnit(from: "ml/kg*min"),
            isSourceSelectable: false,
            permission: .cardioFitness,
            summary: .latestSample,
            trend: .daily(.latest)
        )
    ]

    static func descriptor(for kind: HealthMetricKind) -> HealthMetricQueryDescriptor? {
        all[kind]
    }
}
