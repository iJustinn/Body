//
//  WatchComputeAssemblyWindowTests.swift
//  BodyTests
//
//  `WatchComputeAssembly.windowDecision` is the gate the watch's compute runs
//  before it queries HealthKit at all: it refuses a seed whose delta window
//  would reach past the watch's own HealthKit retention (stale seed) or whose
//  `dataThrough` sits implausibly far in the future (phone clock ahead), and
//  otherwise hands back `WatchDeltaSplicer.deltaStart`.
//

import XCTest
@testable import Body

final class WatchComputeAssemblyWindowTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func makeSeed(dataThrough: Date) -> WatchComputeSeed {
        HealthKitWorkoutStore.makeComputeSeed(
            summary: .empty,
            trends: .empty,
            dataThrough: dataThrough,
            lastVitalsRefreshDate: dataThrough,
            trainingLoadStartDay: nil,
            trainingLoadDailyLoads: nil,
            trainingLoadDataThrough: nil,
            expectedSourceIDsByKind: nil,
            settings: WatchComputeSettings(
                idealSleepDurationMinutes: 480,
                followsSystemUnits: false,
                selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.celsius.rawValue,
                showSleepScore: true,
                showsSubMinuteAwakeSleepStages: true,
                showsLeadingTrailingAwakeSleepStages: true,
                healthDataSourceSelectionRaw: "",
                combinesHealthDataSourcesByName: false
            ),
            publishedAt: dataThrough
        )
    }

    /// The WHOLE window has to fit inside the retention, not just the seed's
    /// own age: `deltaStart` reaches two calendar days further back, and days
    /// the watch no longer holds would splice in as authoritative emptiness.
    func testASeedWhoseWindowReachesPastTheWatchRetentionIsRefused() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let dataThrough = now.addingTimeInterval(-WatchComputeSeed.maxComputeAge + 3_600)
        XCTAssertEqual(
            WatchComputeAssembly.windowDecision(seed: makeSeed(dataThrough: dataThrough), now: now, calendar: calendar),
            .tooOld
        )
    }

    func testASeedFromAClockFarAheadIsRefused() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let dataThrough = now.addingTimeInterval(WatchMetricsSnapshot.staleInterval + 60)
        XCTAssertEqual(
            WatchComputeAssembly.windowDecision(seed: makeSeed(dataThrough: dataThrough), now: now, calendar: calendar),
            .futureDataThrough
        )
    }

    func testAFreshSeedFetchesFromTheSplicerDeltaStart() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let dataThrough = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        XCTAssertEqual(
            WatchComputeAssembly.windowDecision(seed: makeSeed(dataThrough: dataThrough), now: now, calendar: calendar),
            .fetch(windowStart: WatchDeltaSplicer.deltaStart(dataThrough: dataThrough, calendar: calendar))
        )
    }
}
