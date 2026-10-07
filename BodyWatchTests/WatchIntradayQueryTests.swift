//
//  WatchIntradayQueryTests.swift
//  BodyWatchTests
//
//  Locks `WatchHealthStore.intradayQuery(forKind:)`, the pure table behind
//  the "Last 8 hours" reads: which quantity type, unit and phone permission
//  each charted kind reads, that Heart Rate and HRV read readings while the
//  two daily totals read sums, that only Active Energy converts to the
//  iPhone's energy unit, that Resting Energy has no row (the iPhone has no
//  Day View for it), and that the table and
//  `WatchIntradayChartStore.chartKinds` name exactly the same kinds.
//

import HealthKit
import XCTest
@testable import BodyWatch

final class WatchIntradayQueryTests: XCTestCase {
    func testHeartRateAndHRVReadReadingsBehindHeart() throws {
        let heartRate = try XCTUnwrap(WatchHealthStore.intradayQuery(forKind: WatchMetricKindKey.heartRate))
        XCTAssertEqual(heartRate.metricKind, .heartRate)
        XCTAssertEqual(heartRate.identifier, .heartRate)
        XCTAssertEqual(heartRate.unit, HKUnit.count().unitDivided(by: .minute()))
        XCTAssertEqual(heartRate.permission, .heart)
        XCTAssertEqual(heartRate.aggregation, .discrete)
        XCTAssertFalse(heartRate.isEnergy)

        let hrv = try XCTUnwrap(WatchHealthStore.intradayQuery(forKind: WatchMetricKindKey.heartRateVariability))
        XCTAssertEqual(hrv.metricKind, .heartRateVariability)
        XCTAssertEqual(hrv.identifier, .heartRateVariabilitySDNN)
        XCTAssertEqual(hrv.unit, .secondUnit(with: .milli))
        XCTAssertEqual(hrv.permission, .heart)
        XCTAssertEqual(hrv.aggregation, .discrete)
    }

    func testStepsReadSumsBehindSteps() throws {
        let steps = try XCTUnwrap(WatchHealthStore.intradayQuery(forKind: WatchMetricKindKey.steps))
        XCTAssertEqual(steps.metricKind, .steps)
        XCTAssertEqual(steps.identifier, .stepCount)
        XCTAssertEqual(steps.unit, .count())
        XCTAssertEqual(steps.permission, .steps)
        XCTAssertEqual(steps.aggregation, .cumulativeSum)
        XCTAssertFalse(steps.isEnergy)
    }

    func testActiveEnergyReadsKilocalorieSumsBehindEnergy() throws {
        let active = try XCTUnwrap(WatchHealthStore.intradayQuery(forKind: WatchMetricKindKey.activeEnergy))
        XCTAssertEqual(active.metricKind, .activeEnergy)
        XCTAssertEqual(active.identifier, .activeEnergyBurned)
        XCTAssertEqual(active.unit, .kilocalorie())
        XCTAssertEqual(active.permission, .energy)
        XCTAssertEqual(active.aggregation, .cumulativeSum)
        XCTAssertTrue(active.isEnergy)
    }

    /// No Day View on the iPhone, no Last 8 hours on the watch.
    func testRestingEnergyHasNoChart() {
        XCTAssertNil(WatchHealthStore.intradayQuery(forKind: WatchMetricKindKey.restingEnergy))
        XCTAssertFalse(WatchIntradayChartStore.chartKinds.contains(WatchMetricKindKey.restingEnergy))
    }

    /// The rows match the descriptor table the compute's week reads use, so a
    /// slot total and a daily total are built from the same type and unit.
    func testDailyTotalRowsMatchTheDescriptorTable() throws {
        for kind in [HealthMetricKind.steps, .activeEnergy] {
            let query = try XCTUnwrap(WatchHealthStore.intradayQuery(forKind: kind.rawValue))
            let descriptor = try XCTUnwrap(HealthMetricQueryDescriptor.descriptor(for: kind))
            XCTAssertEqual(query.identifier, descriptor.quantityType, kind.rawValue)
            XCTAssertEqual(query.unit, descriptor.unit, kind.rawValue)
            XCTAssertEqual(query.permission, descriptor.permission, kind.rawValue)
        }
    }

    func testTheTableAndTheChartKindsNameTheSameKinds() {
        for kind in WatchMetricKindKey.displayOrder {
            let charted = WatchIntradayChartStore.chartKinds.contains(kind)
            XCTAssertEqual(WatchHealthStore.intradayQuery(forKind: kind) != nil, charted, kind)
        }
        XCTAssertNil(WatchHealthStore.intradayQuery(forKind: WatchMetricKindKey.sleep))
        XCTAssertNil(WatchHealthStore.intradayQuery(forKind: WatchMetricKindKey.workoutMinutes))
        XCTAssertNil(WatchHealthStore.intradayQuery(forKind: "unknown"))
    }
}
