//
//  DetailRenderCacheTests.swift
//  BodyTests
//
//  Covers the metric detail page's render caches: the per-range trend point
//  cache, the cached workout index behind `allCachedWorkouts` / `workouts(on:)`,
//  and the floating callout channel's owner token.
//

import SwiftUI
import XCTest
@testable import Body

@MainActor
final class DetailRenderCacheTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    /// Fixed anchor so bucket dates never depend on the wall clock.
    private let anchorDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Range points cache

    private func dailySeries(dayCount: Int = 120, mutatedIndex: Int? = nil) -> HealthTrendSeries {
        let dayStart = calendar.startOfDay(for: anchorDate)
        let points = (0..<dayCount).compactMap { dayOffset -> HealthTrendDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: dayStart) else {
                return nil
            }
            let value = Double(dayOffset % 17) + (dayOffset == mutatedIndex ? 500 : 0)
            return HealthTrendDataPoint(date: date, value: value)
        }
        return HealthTrendSeries(points: points)
    }

    /// Storage identity of one range's points, so a cache hit (the stored array
    /// handed back) is distinguishable from a recompute that happens to be equal.
    private func storageIdentity(
        of pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]]
    ) -> UnsafeRawPointer? {
        pointsByRange[.recentMonth]?.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    func testRangePointsCacheReturnsTheSameBufferForAnIdenticalSeries() {
        let cache = BodyTrendRangePointsCache()
        let series = dailySeries()

        let first = cache.points(for: series, style: .line, date: anchorDate, slot: .primary)
        let second = cache.points(for: series, style: .line, date: anchorDate, slot: .primary)

        XCTAssertNotNil(storageIdentity(of: first))
        XCTAssertEqual(storageIdentity(of: first), storageIdentity(of: second))
    }

    func testRangePointsCacheMissesWhenAMiddlePointChanges() {
        let cache = BodyTrendRangePointsCache()
        let series = dailySeries()
        // Inside the month window, so the compared range actually changes.
        let mutated = dailySeries(mutatedIndex: 10)

        let first = cache.points(for: series, style: .line, date: anchorDate, slot: .primary)
        let second = cache.points(for: mutated, style: .line, date: anchorDate, slot: .primary)

        // A same-count/first/last key would have called this a hit.
        XCTAssertNotEqual(storageIdentity(of: first), storageIdentity(of: second))
        XCTAssertNotEqual(first[.recentMonth], second[.recentMonth])
    }

    func testRangePointsCacheKeepsOneEntryPerSlot() {
        let cache = BodyTrendRangePointsCache()
        let weight = dailySeries()
        let bodyFat = dailySeries(mutatedIndex: 3)

        let firstWeight = cache.points(for: weight, style: .basicsLine, date: anchorDate, slot: .weight)
        _ = cache.points(for: bodyFat, style: .basicsLine, date: anchorDate, slot: .bodyFat)
        let secondWeight = cache.points(for: weight, style: .basicsLine, date: anchorDate, slot: .weight)

        XCTAssertEqual(storageIdentity(of: firstWeight), storageIdentity(of: secondWeight))
    }

    func testRangePointsCacheMissesWhenTheStyleChanges() {
        let cache = BodyTrendRangePointsCache()
        let series = dailySeries()

        let line = cache.points(for: series, style: .line, date: anchorDate, slot: .primary)
        let bars = cache.points(for: series, style: .bars, date: anchorDate, slot: .primary)

        XCTAssertNotEqual(storageIdentity(of: line), storageIdentity(of: bars))
    }

    // MARK: - Cached workout index

    private func workout(
        id: UUID = UUID(),
        day: Int,
        hour: Int = 8,
        duration: TimeInterval,
        endDate: Date? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            type: .running,
            startDate: calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour)) ?? anchorDate,
            duration: duration,
            sourceName: "Tests",
            endDate: endDate
        )
    }

    private func snapshots(
        _ workouts: [WorkoutSummary]
    ) -> [BodyWorkoutMonthKey: WorkoutMonthSnapshot] {
        [
            BodyWorkoutMonthKey(month: 5, year: 2026): WorkoutMonthSnapshot.make(
                month: 5,
                year: 2026,
                workouts: workouts,
                calendar: .bodyGregorian
            )
        ]
    }

    private func dayInterval(day: Int) throws -> DateInterval {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: day)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        return DateInterval(start: start, end: end)
    }

    func testWorkoutIndexDeduplicatesByIDAndSortsByStart() {
        let sharedID = UUID()
        let early = workout(id: sharedID, day: 6, hour: 7, duration: 600)
        let duplicate = workout(id: sharedID, day: 6, hour: 7, duration: 600)
        let later = workout(day: 6, hour: 18, duration: 600)
        let index = BodyCachedWorkoutIndex()

        // The same workout can sit in two cached month snapshots (a month
        // boundary refresh rewrites both), so the flatten must de-duplicate.
        let all = index.allWorkouts(
            in: [
                BodyWorkoutMonthKey(month: 5, year: 2026): WorkoutMonthSnapshot.make(
                    month: 5,
                    year: 2026,
                    workouts: [later, early],
                    calendar: .bodyGregorian
                ),
                BodyWorkoutMonthKey(month: 4, year: 2026): WorkoutMonthSnapshot.make(
                    month: 5,
                    year: 2026,
                    workouts: [duplicate],
                    calendar: .bodyGregorian
                )
            ],
            generation: 1
        )

        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.map(\.startDate), [early.startDate, later.startDate])
    }

    func testWorkoutIndexServesStaleResultsUntilTheGenerationBumps() {
        let index = BodyCachedWorkoutIndex()
        let first = workout(day: 6, duration: 600)
        let second = workout(day: 7, duration: 600)

        _ = index.allWorkouts(in: snapshots([first]), generation: 1)
        let sameGeneration = index.allWorkouts(in: snapshots([first, second]), generation: 1)
        let bumped = index.allWorkouts(in: snapshots([first, second]), generation: 2)

        XCTAssertEqual(sameGeneration.count, 1)
        XCTAssertEqual(bumped.count, 2)
    }

    func testWorkoutIndexDropsDaySlicesWhenTheGenerationBumps() throws {
        let index = BodyCachedWorkoutIndex()
        let day = try dayInterval(day: 6)
        let existing = workout(day: 6, duration: 600)
        let added = workout(day: 6, hour: 19, duration: 600)

        _ = index.workouts(on: day, in: snapshots([existing]), generation: 1)
        let refreshed = index.workouts(on: day, in: snapshots([existing, added]), generation: 2)

        XCTAssertEqual(refreshed.count, 2)
    }

    func testWorkoutIndexIncludesAPausedWorkoutThatEndsInsideTheDay() throws {
        // Started at 23:30 the night before and paused for hours: `startDate +
        // duration` lands before midnight, but the recorded end is inside the
        // day, so the day context and the warning exclusions must both see it.
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 23, minute: 30)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 1)))
        let paused = WorkoutSummary(
            type: .running,
            startDate: start,
            duration: 600,
            sourceName: "Tests",
            endDate: end
        )
        let index = BodyCachedWorkoutIndex()
        let day = try dayInterval(day: 6)

        let slice = index.workouts(on: day, in: snapshots([paused]), generation: 1)

        XCTAssertEqual(slice.map(\.id), [paused.id])
        XCTAssertLessThan(paused.startDate.addingTimeInterval(paused.duration), day.start)
    }

    // MARK: - Floating callout owner token

    private func callout(x: CGFloat) -> BodyChartFloatingCallout {
        BodyChartFloatingCallout(anchor: CGPoint(x: x, y: 0), content: AnyView(EmptyView()))
    }

    func testASecondOwnersNilPublishDoesNotClearTheFirstOwnersCallout() {
        let state = BodyChartFloatingCalloutState()
        let hero = UUID()
        let warningCard = UUID()

        state.publish(callout(x: 10), owner: hero)
        // A warning card appearing mid-scrub publishes nil on appear.
        state.publish(nil, owner: warningCard)

        XCTAssertNotNil(state.callout)
        XCTAssertEqual(state.callout?.anchor.x, 10)
    }

    func testASecondOwnersDisappearDoesNotClearTheFirstOwnersCallout() {
        let state = BodyChartFloatingCalloutState()
        let hero = UUID()

        state.publish(callout(x: 10), owner: hero)
        state.clear(owner: UUID())

        XCTAssertNotNil(state.callout)
    }

    func testTheOwnerCanClearItsOwnCallout() {
        let state = BodyChartFloatingCalloutState()
        let hero = UUID()

        state.publish(callout(x: 10), owner: hero)
        state.clear(owner: hero)

        XCTAssertNil(state.callout)
    }

    func testTheLatestPublisherTakesOverTheSlot() {
        let state = BodyChartFloatingCalloutState()
        let first = UUID()
        let second = UUID()

        state.publish(callout(x: 10), owner: first)
        state.publish(callout(x: 40), owner: second)
        state.clear(owner: first)

        XCTAssertEqual(state.callout?.anchor.x, 40)
    }

    func testAnUnownedCalloutStaysClearableByAnyReporter() {
        // The direct `state.callout =` writers (the workout charts, the rings
        // detail) never take the token, so the reporters must still be able to
        // clear what they left behind.
        let state = BodyChartFloatingCalloutState()
        state.callout = callout(x: 10)

        state.clear(owner: UUID())

        XCTAssertNil(state.callout)
    }
}
