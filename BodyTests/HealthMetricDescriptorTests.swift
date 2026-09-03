//
//  HealthMetricDescriptorTests.swift
//  BodyTests
//
//  A4 / S-11: `HealthMetricQueryDescriptor` is the single table the engine
//  orchestrators, the secondary and intraday dispatchers and the watch's delta
//  fetcher read their per-metric query wiring from. These tests pin that the
//  table stays exhaustive over `HealthMetricKind`, that it agrees with the
//  other per-kind tables it does NOT own (permissions, source sample types,
//  comparison-chart support, day-view support), and that each row's identifier,
//  unit and query shapes are what shipped, so a change to any of them is a
//  deliberate edit rather than a silent drift.
//

import HealthKit
import XCTest
@testable import Body

final class HealthMetricDescriptorTests: XCTestCase {
    /// The kinds that are deliberately NOT a single quantity query: two derived
    /// scores, two sleep-sessionization views, the body-measurement fan-out, and
    /// the workout-derived training load.
    private let bespokeKinds: Set<HealthMetricKind> = [
        .readiness,
        .stress,
        .sleep,
        .basics,
        .trainingLoad,
        .vitals
    ]

    private var descriptors: [HealthMetricQueryDescriptor] {
        Array(HealthMetricQueryDescriptor.all.values)
    }

    // MARK: - Coverage

    func testEveryMetricKindIsEitherADescriptorKindOrExplicitlyBespoke() {
        for kind in HealthMetricKind.allCases {
            let hasDescriptor = HealthMetricQueryDescriptor.descriptor(for: kind) != nil
            let isBespoke = bespokeKinds.contains(kind)
            XCTAssertNotEqual(
                hasDescriptor,
                isBespoke,
                "\(kind.rawValue) must be exactly one of a descriptor kind or a bespoke kind"
            )
        }
        XCTAssertEqual(HealthMetricQueryDescriptor.all.count, 15)
    }

    func testEveryRowIsKeyedByItsOwnKind() {
        for (kind, descriptor) in HealthMetricQueryDescriptor.all {
            XCTAssertEqual(descriptor.kind, kind)
        }
    }

    // MARK: - Agreement with the tables the descriptor does not own

    /// `HealthKitFetchEngine.healthPermission(forMetric:)` stays the canonical
    /// kind → permission map (it also answers for the bespoke kinds). The
    /// descriptor carries its own copy for the query leaves, so the two must
    /// agree row for row.
    func testDescriptorPermissionsMatchTheEnginePermissionMap() {
        for (kind, descriptor) in HealthMetricQueryDescriptor.all {
            XCTAssertEqual(
                descriptor.permission,
                HealthKitFetchEngine.healthPermission(forMetric: kind),
                kind.rawValue
            )
        }
    }

    func testSourceSelectableRowsResolveToASourceSelectableKind() {
        for descriptor in descriptors where descriptor.isSourceSelectable {
            XCTAssertTrue(
                HealthMetricKind.sourceSelectableKinds.contains(descriptor.sourceKind),
                descriptor.kind.rawValue
            )
        }
        // Cardio fitness is the only row that is not source-selectable, and it
        // is correspondingly absent from the selectable list.
        XCTAssertEqual(descriptors.filter { !$0.isSourceSelectable }.map(\.kind), [.cardioFitness])
        XCTAssertFalse(HealthMetricKind.sourceSelectableKinds.contains(.cardioFitness))
    }

    /// Source discovery must fan over the same quantity type the reads query, or
    /// a persisted selection would key differently from what it filters.
    /// `sourceSampleTypes(for:)` forwards to the descriptor for single-type kinds,
    /// so the expectation here is a hand-written list of identifiers rather than
    /// the descriptor's own row, which keeps the check from being circular.
    func testQuantityTypeIsDiscoveredForItsSourceKind() {
        let expectedDiscovery: [HealthMetricKind: Set<String>] = [
            .heartRate: [HKQuantityTypeIdentifier.heartRate.rawValue],
            .restingHeartRate: [HKQuantityTypeIdentifier.restingHeartRate.rawValue],
            .heartRateVariability: [HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue],
            .respiratoryRate: [HKQuantityTypeIdentifier.respiratoryRate.rawValue],
            .oxygenSaturation: [HKQuantityTypeIdentifier.oxygenSaturation.rawValue],
            .activeEnergy: [HKQuantityTypeIdentifier.activeEnergyBurned.rawValue],
            .restingEnergy: [HKQuantityTypeIdentifier.basalEnergyBurned.rawValue],
            .exerciseMinutes: [HKQuantityTypeIdentifier.appleExerciseTime.rawValue],
            .wristTemperature: [HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue],
            .timeInDaylight: [HKQuantityTypeIdentifier.timeInDaylight.rawValue],
            .steps: [HKQuantityTypeIdentifier.stepCount.rawValue],
            .basics: [
                HKQuantityTypeIdentifier.bodyMass.rawValue,
                HKQuantityTypeIdentifier.bodyFatPercentage.rawValue,
                HKQuantityTypeIdentifier.bodyMassIndex.rawValue
            ],
            .sleep: [HKCategoryTypeIdentifier.sleepAnalysis.rawValue]
        ]
        XCTAssertEqual(Set(expectedDiscovery.keys), Set(HealthMetricKind.sourceSelectableKinds))
        for (kind, identifiers) in expectedDiscovery {
            let discovered = Set(BodyHealthSourceResolver.sourceSampleTypes(for: kind).map(\.identifier))
            XCTAssertEqual(discovered, identifiers, kind.rawValue)
        }
        // Every descriptor row queries a type that discovery fans over for its
        // source kind; cardio fitness is not source-selectable and discovers none.
        for descriptor in descriptors {
            let discovered = Set(BodyHealthSourceResolver.sourceSampleTypes(for: descriptor.sourceKind).map(\.identifier))
            if descriptor.kind == .cardioFitness {
                XCTAssertTrue(discovered.isEmpty)
            } else {
                XCTAssertTrue(discovered.contains(descriptor.quantityType.rawValue), descriptor.kind.rawValue)
            }
        }
        // A kind that is only a member of `.basics` has no source list of its own.
        for kind in [HealthMetricKind.bodyMass, .bodyFatPercentage, .bodyMassIndex, .readiness, .stress, .vitals, .trainingLoad] {
            XCTAssertTrue(BodyHealthSourceResolver.sourceSampleTypes(for: kind).isEmpty, kind.rawValue)
        }
    }

    /// The comparison-source leaves must be fetched for exactly the kinds whose
    /// detail page can draw a comparison chart of that shape.
    func testSecondaryFlagsMatchSupportedComparisonCharts() {
        for (kind, descriptor) in HealthMetricQueryDescriptor.all {
            let charts = kind.supportedComparisonCharts
            XCTAssertEqual(
                descriptor.secondaryTrend,
                charts.contains(.line) || charts.contains(.bar),
                "secondaryTrend for \(kind.rawValue)"
            )
            XCTAssertEqual(
                descriptor.secondaryRangeTrend,
                charts.contains(.range),
                "secondaryRangeTrend for \(kind.rawValue)"
            )
            XCTAssertEqual(
                descriptor.secondaryDaySamples != nil,
                charts.contains(.dayLine),
                "secondaryDaySamples for \(kind.rawValue)"
            )
        }
        XCTAssertEqual(descriptors.filter(\.secondaryTrend).count, 5)
        XCTAssertEqual(descriptors.filter(\.secondaryRangeTrend).count, 3)
        XCTAssertEqual(descriptors.filter { $0.secondaryDaySamples != nil }.count, 6)
    }

    /// Every descriptor kind with a day view must have an intraday fetch.
    /// Readiness and stress are in `dayViewKinds` but are bespoke, and resting
    /// heart rate is the reverse: it has the fetch but no day view, a divergence
    /// that predates the descriptor and is preserved deliberately.
    func testIntradayFetchExistsForEveryDescriptorKindWithADayView() {
        for kind in HealthMetricKind.dayViewKinds {
            guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind) else {
                XCTAssertTrue(bespokeKinds.contains(kind), kind.rawValue)
                continue
            }
            XCTAssertNotNil(descriptor.intradayDaySamples, kind.rawValue)
        }
        XCTAssertEqual(descriptors.filter { $0.intradayDaySamples != nil }.count, 7)
        XCTAssertNotNil(HealthMetricQueryDescriptor.descriptor(for: .restingHeartRate)?.intradayDaySamples)
        XCTAssertFalse(HealthMetricKind.dayViewKinds.contains(.restingHeartRate))
        // Respiratory rate is the other preserved divergence: an intraday fetch
        // with no comparison-source counterpart.
        XCTAssertNotNil(HealthMetricQueryDescriptor.descriptor(for: .respiratoryRate)?.intradayDaySamples)
        XCTAssertNil(HealthMetricQueryDescriptor.descriptor(for: .respiratoryRate)?.secondaryDaySamples)
    }

    // MARK: - The pinned table

    /// The identifier, unit and query shapes that shipped. Any change here is a
    /// change to what HealthKit is asked for on both the phone and the watch.
    func testDescriptorTableMatchesTheShippedWiring() {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute()).unitString
        let expected: [HealthMetricKind: (
            identifier: HKQuantityTypeIdentifier,
            unit: String,
            sourceKind: HealthMetricKind,
            summary: HealthMetricQueryDescriptor.SummaryQuery,
            trend: HealthMetricQueryDescriptor.TrendQuery,
            intraday: HealthMetricQueryDescriptor.DaySampleQuery?,
            normalizesPercent: Bool
        )] = [
            .heartRate: (.heartRate, beatsPerMinute, .heartRate, .latestSample, .averageAndRange(.average), .sampleSeries, false),
            .restingHeartRate: (.restingHeartRate, beatsPerMinute, .restingHeartRate, .latestSample, .daily(.average), .sampleSeries, false),
            .bodyMass: (.bodyMass, HKUnit.gramUnit(with: .kilo).unitString, .basics, .latestSample, .daily(.latest), nil, false),
            .bodyFatPercentage: (.bodyFatPercentage, HKUnit.percent().unitString, .basics, .latestSample, .daily(.latest), nil, true),
            .heartRateVariability: (.heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli).unitString, .heartRateVariability, .latestSample, .averageAndRange(.average), .sampleSeries, false),
            .respiratoryRate: (.respiratoryRate, beatsPerMinute, .respiratoryRate, .latestSample, .averageAndRange(.average), .sampleSeries, false),
            .oxygenSaturation: (.oxygenSaturation, HKUnit.percent().unitString, .oxygenSaturation, .latestSample, .averageAndRange(.average), .sampleSeries, true),
            .bodyMassIndex: (.bodyMassIndex, HKUnit.count().unitString, .basics, .latestSample, .daily(.latest), nil, false),
            .activeEnergy: (.activeEnergyBurned, HKUnit.kilocalorie().unitString, .activeEnergy, .dailyCumulative, .dailyCumulative, .hourlyCumulative, false),
            .restingEnergy: (.basalEnergyBurned, HKUnit.kilocalorie().unitString, .restingEnergy, .dailyCumulative, .dailyCumulative, nil, false),
            .exerciseMinutes: (.appleExerciseTime, HKUnit.minute().unitString, .exerciseMinutes, .dailyCumulative, .dailyCumulative, nil, false),
            .wristTemperature: (.appleSleepingWristTemperature, HKUnit.degreeCelsius().unitString, .wristTemperature, .dailyAverage, .daily(.average), nil, false),
            .timeInDaylight: (.timeInDaylight, HKUnit.minute().unitString, .timeInDaylight, .dailyCumulative, .dailyCumulative, nil, false),
            .steps: (.stepCount, HKUnit.count().unitString, .steps, .dailyCumulative, .dailyCumulative, .hourlyCumulative, false),
            .cardioFitness: (.vo2Max, HKUnit(from: "ml/kg*min").unitString, .cardioFitness, .latestSample, .daily(.latest), nil, false)
        ]

        XCTAssertEqual(Set(expected.keys), Set(HealthMetricQueryDescriptor.all.keys))
        for (kind, row) in expected {
            guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind) else {
                XCTFail("missing descriptor for \(kind.rawValue)")
                continue
            }
            XCTAssertEqual(descriptor.quantityType, row.identifier, kind.rawValue)
            XCTAssertEqual(descriptor.unit.unitString, row.unit, kind.rawValue)
            XCTAssertEqual(descriptor.sourceKind, row.sourceKind, kind.rawValue)
            XCTAssertEqual(descriptor.summary, row.summary, kind.rawValue)
            XCTAssertEqual(descriptor.trend, row.trend, kind.rawValue)
            XCTAssertEqual(descriptor.intradayDaySamples, row.intraday, kind.rawValue)
            // 0.97 is what a fractional source writes for 97%; only the two
            // percentage reads scale it.
            XCTAssertEqual(descriptor.valueTransform(0.97), row.normalizesPercent ? 97 : 0.97, accuracy: 0.0001, kind.rawValue)
        }
    }

    /// The comparison-source day-sample shape always matches the primary one, so
    /// the two series on a day chart are bucketed the same way.
    func testSecondaryDaySampleShapeMatchesThePrimaryShape() {
        for descriptor in descriptors {
            guard let secondary = descriptor.secondaryDaySamples else { continue }
            XCTAssertEqual(secondary, descriptor.intradayDaySamples, descriptor.kind.rawValue)
        }
    }

    /// The watch's delta re-query reads `dailyAggregation`; it must be present
    /// for every kind the watch re-queries and absent for the cumulative kinds.
    func testDailyAggregationIsPresentForEveryNonCumulativeRow() {
        for descriptor in descriptors {
            switch descriptor.trend {
            case .dailyCumulative:
                XCTAssertNil(descriptor.dailyAggregation, descriptor.kind.rawValue)
            case .daily(let aggregation), .averageAndRange(let aggregation):
                XCTAssertEqual(descriptor.dailyAggregation, aggregation, descriptor.kind.rawValue)
            }
        }
    }

    func testQuerySourceKindIsOmittedOnlyForTheNonSelectableRow() {
        for descriptor in descriptors {
            if descriptor.isSourceSelectable {
                XCTAssertEqual(descriptor.querySourceKind, descriptor.sourceKind, descriptor.kind.rawValue)
            } else {
                XCTAssertNil(descriptor.querySourceKind, descriptor.kind.rawValue)
            }
        }
    }
}
