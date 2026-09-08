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

    private func makeInput(epoch: Int) -> BodyCompanionPublishInput {
        BodyCompanionPublishInput(
            shared: Self.makeSharedInput(),
            epoch: epoch,
            lastRefreshDate: nil,
            permissionSelection: .defaultValue,
            permissionRawValue: "",
            now: Date(),
            workoutCalendar: .bodyGregorian,
            monthSnapshots: [:],
            captureSequence: 1,
            // `nil` keeps the seed (and its time-zone map and zlib pass) out of
            // this test: the gate under test sits after the build either way.
            dataThrough: nil,
            readinessComputeDate: nil,
            trainingLoadComputeDate: nil,
            workoutMinutesDataAsOf: .distantPast,
            metricPullDates: [:],
            trainingLoadStartDay: nil,
            trainingLoadDailyLoads: nil,
            trainingLoadDataThrough: nil,
            expectedSourceIDsByKind: [:],
            followsSystemUnits: true,
            selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue,
            showsSubMinuteAwakeStages: false,
            showsLeadingTrailingAwakeStages: false,
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
