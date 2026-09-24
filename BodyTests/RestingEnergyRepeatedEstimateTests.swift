//
//  RestingEnergyRepeatedEstimateTests.swift
//  BodyTests
//
//  A scale writes its whole-day resting energy estimate at every weigh-in, so
//  two weigh-ins in a day would sum to double. What the estimates add to the
//  day must count each source's once, at their average.
//

import XCTest
@testable import Body

final class RestingEnergyRepeatedEstimateTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    private let day = Calendar.bodyGregorian.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    private func sample(_ value: Double, hour: Double, source: String = "scale", duration: TimeInterval = 0, dayOffset: Double = 0) -> HealthKitFetchEngine.DailyEstimateSample {
        let start = day.addingTimeInterval((dayOffset * 24 + hour) * 3600)
        return .init(start: start, end: start.addingTimeInterval(duration), source: source, value: value)
    }

    private func estimates(_ samples: [HealthKitFetchEngine.DailyEstimateSample]) -> [Date: HealthKitFetchEngine.DayEstimates] {
        HealthKitFetchEngine.dailyEstimates(samples: samples, calendar: calendar)
    }

    func testTwoWeighInsInOneDayAverageInsteadOfSumming() {
        // Out of order on purpose: the callout lists the records by time.
        let days = estimates([sample(1_720, hour: 21), sample(1_700, hour: 8)])
        XCTAssertEqual(days[day]?.total, 1_710)
        XCTAssertEqual(days[day]?.records.map(\.value), [1_700, 1_720])
        XCTAssertEqual(days.count, 1)
    }

    /// The device case behind the fix: the scale logged its evening estimate
    /// twice, and HealthKit's own sum ignored the copy, so correcting that sum
    /// by all three records left the day at minus 5 kcal.
    func testAnExactDuplicateIsCountedOnce() {
        let days = estimates([sample(1_678, hour: 11.3), sample(1_692, hour: 20), sample(1_692, hour: 20)])
        XCTAssertEqual(days[day]?.total, 1_685)
        XCTAssertEqual(days[day]?.records.map(\.value), [1_678, 1_692])
    }

    func testASingleWeighInCountsInFullWithNoRecords() {
        let days = estimates([sample(1_700, hour: 8), sample(1_650, hour: 8, dayOffset: 1)])
        XCTAssertEqual(days[day], .init(total: 1_700))
        XCTAssertEqual(days.count, 2)
    }

    func testSourcesAreAveragedSeparately() {
        let days = estimates([sample(1_700, hour: 8), sample(1_800, hour: 9, source: "other")])
        XCTAssertEqual(days[day], .init(total: 3_500))
    }

    func testLargeSamplesLoggedOverHoursStayCumulative() {
        let days = estimates([sample(900, hour: 0, duration: 12 * 3600), sample(900, hour: 12, duration: 12 * 3600)])
        XCTAssertEqual(days[day], .init(total: 1_800))
    }
}
