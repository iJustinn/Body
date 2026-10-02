//
//  BodyCompanionPublisherTests.swift
//  BodyTests
//
//  The watch publish's epoch gate (H7), the republish debounce, and the widget
//  save's independence from the watch send. The build runs off-actor, so a Clear
//  Cache can land between the main-actor capture and the hop back; the send
//  must lose that race rather than ship pre-clear metrics onto wiped state.
//

import XCTest
@testable import Body

@MainActor
final class BodyCompanionPublisherTests: XCTestCase {
    private static func makeSharedInput() -> BodyCompanionPublishInput.Shared {
        BodyCompanionPublishInput.Shared(
            trends: .empty,
            summary: .empty,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 60 * 60,
            showSleepScore: true
        )
    }

    private func makeInput(
        epoch: Int,
        homeHeroRaw: String = BodyStarMetric.readiness.rawValue,
        shared: BodyCompanionPublishInput.Shared? = nil,
        now: Date = Date(),
        lastRefreshDate: Date? = nil,
        permissionSelection: BodyHealthPermissionSelection = .defaultValue,
        metricPullDates: [String: Date] = [:],
        workoutColorPalette: BodyWorkoutColorPalette = .builtIn
    ) -> BodyCompanionPublishInput {
        BodyCompanionPublishInput(
            shared: shared ?? Self.makeSharedInput(),
            epoch: epoch,
            lastRefreshDate: lastRefreshDate,
            permissionSelection: permissionSelection,
            permissionRawValue: "",
            now: now,
            workoutCalendar: .bodyGregorian,
            monthSnapshots: [:],
            captureSequence: 1,
            // `nil` keeps the seed (and its time-zone map and zlib pass) out of
            // this test: the gate under test sits after the build either way.
            dataThrough: nil,
            readinessComputeDate: nil,
            trainingLoadComputeDate: nil,
            workoutMinutesDataAsOf: .distantPast,
            metricPullDates: metricPullDates,
            trainingLoadStartDay: nil,
            trainingLoadDailyLoads: nil,
            trainingLoadDataThrough: nil,
            expectedSourceIDsByKind: [:],
            followsSystemUnits: true,
            selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue,
            showsSubMinuteAwakeStages: false,
            showsLeadingTrailingAwakeStages: false,
            readinessHeroShowsLevel: true,
            showsSleepDebt: false,
            homeHeroRaw: homeHeroRaw,
            dayRingShowsCaption: false,
            workoutColorPalette: workoutColorPalette,
            healthDataSourceSelectionRaw: "",
            customHealthSourceGroupsRaw: nil,
            combinesByName: false
        )
    }

    func testCurrentEpochSendsTheBuiltSnapshot() async {
        let sent = expectation(description: "sent")
        let publisher = BodyCompanionPublisher(send: { _, _, _, _, _ in sent.fulfill() })

        publisher.publishWatchSnapshot(makeInput(epoch: 3), isEpochCurrent: { $0 == 3 })

        await fulfillment(of: [sent], timeout: 5)
    }

    func testHomeHeroChoiceRidesTheWatchSnapshot() async {
        // The watch draws the hero picked in the phone's Settings, and only the Day
        // Ring pays for the workout list.
        for (raw, carriesWorkouts) in [(BodyStarMetric.dayRing.rawValue, true), (BodyStarMetric.readiness.rawValue, false)] {
            let sent = expectation(description: "sent \(raw)")
            let publisher = BodyCompanionPublisher(send: { snapshot, _, _, _, _ in
                XCTAssertEqual(snapshot.homeHero, raw)
                XCTAssertEqual(snapshot.dayRingShowsCaption, false)
                XCTAssertEqual(snapshot.dayRingWorkouts != nil, carriesWorkouts)
                sent.fulfill()
            })

            publisher.publishWatchSnapshot(makeInput(epoch: 3, homeHeroRaw: raw), isEpochCurrent: { $0 == 3 })

            await fulfillment(of: [sent], timeout: 5)
        }
    }

    /// The Stress page's "Last 8 hours" is built from the captured LIVE
    /// trends (only they carry the intraday day samples), stamped with the
    /// Stress card's own watermark, and only while Heart is on. The workout
    /// colors ride along in their raw form, empty without Body Pro.
    func testStressTimelineAndWorkoutColorsRideTheWatchSnapshot() async throws {
        let calendar = Calendar.bodyGregorian
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let today = calendar.startOfDay(for: now)
        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = (1...20).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map {
                StressDaySummary(date: $0, averageScore: 30, scoredWindowCount: 40, quietHRMedian: 60)
            }
        }
        .sorted { $0.date < $1.date }
        // 02:00 to 10:00, two readings in every window.
        trends.heartRateDaySamples = HealthTrendSeries(points: (8..<40).flatMap { index -> [HealthTrendDataPoint] in
            let windowStart = today.addingTimeInterval(Double(index) * 900)
            return [
                HealthTrendDataPoint(date: windowStart.addingTimeInterval(60), value: 72),
                HealthTrendDataPoint(date: windowStart.addingTimeInterval(420), value: 72)
            ]
        })
        let shared = BodyCompanionPublishInput.Shared(
            trends: trends,
            summary: .empty,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 60 * 60,
            showSleepScore: true
        )
        let refreshed = now.addingTimeInterval(-900)
        let pulled = now.addingTimeInterval(-300)
        let expected = WatchStressTimelineBuilder.make(
            dashboard: HealthDashboardSnapshot(summary: .empty, trends: trends),
            workouts: [],
            now: now,
            calendar: calendar,
            computedAt: pulled
        )
        XCTAssertNotNil(expected)

        let cases: [(name: String, permission: BodyHealthPermissionSelection, palette: BodyWorkoutColorPalette, timeline: WatchStressTimeline?, overrides: String)] = [
            ("built-in colors", .defaultValue, .builtIn, expected, ""),
            ("Body Pro colors", .defaultValue, BodyWorkoutColorPalette(rawOverrides: "running:12AB34", isProUnlocked: true), expected, "running:12AB34"),
            ("lapsed Body Pro", .defaultValue, BodyWorkoutColorPalette(rawOverrides: "running:12AB34", isProUnlocked: false), expected, ""),
            ("Heart off", BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false), .builtIn, nil, "")
        ]
        for testCase in cases {
            let sent = expectation(description: testCase.name)
            let publisher = BodyCompanionPublisher(send: { snapshot, _, _, _, _ in
                XCTAssertEqual(snapshot.stressTimeline, testCase.timeline, testCase.name)
                XCTAssertEqual(snapshot.workoutColorOverrides, testCase.overrides, testCase.name)
                if testCase.timeline != nil {
                    XCTAssertEqual(
                        snapshot.metric(forKind: WatchMetricKindKey.stress)?.computedAt,
                        snapshot.stressTimeline?.computedAt,
                        "\(testCase.name): the card and its timeline share one watermark"
                    )
                }
                sent.fulfill()
            })

            publisher.publishWatchSnapshot(
                makeInput(
                    epoch: 3,
                    shared: shared,
                    now: now,
                    lastRefreshDate: refreshed,
                    permissionSelection: testCase.permission,
                    metricPullDates: [WatchMetricKindKey.stress: pulled],
                    workoutColorPalette: testCase.palette
                ),
                isEpochCurrent: { $0 == 3 }
            )

            await fulfillment(of: [sent], timeout: 5)
        }
    }

    func testStaleEpochNeverSends() async {
        let sent = expectation(description: "sent")
        sent.isInverted = true
        let publisher = BodyCompanionPublisher(send: { _, _, _, _, _ in sent.fulfill() })

        // A Clear Cache bumped the epoch while the build was on the persist
        // queue, so the captured epoch no longer matches.
        publisher.publishWatchSnapshot(makeInput(epoch: 3), isEpochCurrent: { $0 == 4 })

        await fulfillment(of: [sent], timeout: 2)
    }

    func testScheduleRepublishRunsOnlyTheLastRebuildOfABurst() async {
        // A held stepper fires one `onChange` per tick; each rebuild encodes both
        // snapshots and reloads the widget timelines, so all but the last has to
        // be cancelled inside the debounce window.
        let publisher = BodyCompanionPublisher(send: { _, _, _, _, _ in })
        let first = expectation(description: "first")
        first.isInverted = true
        let second = expectation(description: "second")

        publisher.scheduleRepublish { first.fulfill() }
        publisher.scheduleRepublish { second.fulfill() }

        await fulfillment(of: [first, second], timeout: 2)
    }

    func testWidgetSaveNeverReachesTheWatchSend() async {
        // `saveHealthWidgetSnapshot` is called on its own from several refresh
        // paths; it writes the App Group file and nothing else. A send from it
        // would ship an unsequenced snapshot the watch would merge out of order.
        let sent = expectation(description: "sent")
        sent.isInverted = true
        let publisher = BodyCompanionPublisher(send: { _, _, _, _, _ in sent.fulfill() })

        publisher.saveWidgetSnapshot(
            BodyCompanionPublishInput.Widget(
                shared: Self.makeSharedInput(),
                energyUnitPreference: .kilocalories,
                weightUnitPreference: .kilograms,
                primarySourceNames: [:]
            )
        )

        await fulfillment(of: [sent], timeout: 2)
    }
}
