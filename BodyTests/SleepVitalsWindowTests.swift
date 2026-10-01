import XCTest
@testable import Body

/// A summary whose latest night's main session ended `seconds` before `now`.
func sleepNightSummary(endingAgo seconds: TimeInterval, now: Date = Date()) -> HealthSummarySnapshot {
    let end = now.addingTimeInterval(-seconds)
    let start = end.addingTimeInterval(-8 * 3_600)
    var summary = HealthSummarySnapshot.empty
    summary.sleep.stageSnapshot = SleepStageSnapshot(
        date: end,
        segments: [SleepStageSegment(stage: .core, startDate: start, endDate: end)],
        mainSessionInterval: DateInterval(start: start, end: end)
    )
    return summary
}

@MainActor
final class SleepVitalsWindowTests: XCTestCase {
    private let day: TimeInterval = 86_400

    private func makeStore(summary: HealthSummarySnapshot = .empty,
                           validation: [String: HealthDashboardSnapshotStore.Freshness]? = nil) -> HealthKitWorkoutStore {
        var metadata = HealthDashboardSnapshotStore.PersistenceMetadata()
        metadata.observedMetricValidation = validation
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [],
            initialHealthDashboardSnapshot: HealthDashboardSnapshot(summary: summary, trends: .empty, activityRingHistory: .empty),
            initialPersistenceMetadata: metadata,
            initialPermissionSelection: .init(enabledPermissions: [.heart, .sleep]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore(), workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        return store
    }

    private func publish(_ summary: HealthSummarySnapshot, to store: HealthKitWorkoutStore) async -> Bool {
        await store.updateHealthDashboardSnapshot(summary: summary, trends: .empty, activityRingHistory: .empty,
            recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false)
    }

    func testWindowAnchorsOnTheLaterOfNightEndAndChangeAndRejectsNegativeElapsed() {
        let end = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let limit = BodyHealthObservationPolicy.sleepVitalsWindow
        func open(_ nightEnd: Date?, _ changedAt: Date?, _ date: Date) -> Bool {
            HealthKitWorkoutStore.sleepVitalsWindowIsOpen(nightEnd: nightEnd, changedAt: changedAt, date: date, limit: limit)
        }
        XCTAssertFalse(open(nil, end, end), "no night is closed")
        XCTAssertTrue(open(end, nil, end))
        XCTAssertTrue(open(end, nil, end.addingTimeInterval(limit - 1)))
        XCTAssertFalse(open(end, nil, end.addingTimeInterval(limit)))
        XCTAssertFalse(open(end, nil, end.addingTimeInterval(-1)), "a negative elapsed is closed")
        let late = end.addingTimeInterval(10 * 3_600)
        XCTAssertTrue(open(end, late, late.addingTimeInterval(limit - 1)), "a late night anchors on its arrival")
        XCTAssertFalse(open(end, late, late.addingTimeInterval(limit)))
        XCTAssertFalse(open(end, end.addingTimeInterval(-3_600), end.addingTimeInterval(limit)),
                       "an earlier change never moves the anchor back")
    }

    func testDeferralLapsesWhenTheWindowOpensAtTheLimitOrOnRollback() {
        let limit = BodyHealthObservationPolicy.sleepDeferralLimit
        let closed = makeStore()
        let deferredAt = Date()
        XCTAssertNil(closed.latestNightEnd)
        XCTAssertFalse(closed.sleepVitalsWindowIsOpen(date: deferredAt))
        XCTAssertFalse(closed.sleepDeferralHasLapsed(deferredAt, date: deferredAt))
        XCTAssertFalse(closed.sleepDeferralHasLapsed(deferredAt, date: deferredAt.addingTimeInterval(limit - 1)))
        XCTAssertTrue(closed.sleepDeferralHasLapsed(deferredAt, date: deferredAt.addingTimeInterval(limit)))
        XCTAssertTrue(closed.sleepDeferralHasLapsed(deferredAt, date: deferredAt.addingTimeInterval(-1)),
                      "a clock moved back past the deferral lapses it")
        let old = makeStore(summary: sleepNightSummary(endingAgo: 3 * day))
        XCTAssertFalse(old.sleepVitalsWindowIsOpen())
        XCTAssertFalse(old.sleepDeferralHasLapsed(Date().addingTimeInterval(-3_600)))
        let morning = makeStore(summary: sleepNightSummary(endingAgo: 3_600))
        XCTAssertTrue(morning.sleepVitalsWindowIsOpen())
        XCTAssertTrue(morning.sleepDeferralHasLapsed(Date().addingTimeInterval(-3_600)), "the window opening makes it work")
    }

    func testNightEndFallsBackToTheWakeCycleEndForCachesWithoutAMainSession() {
        var legacy = sleepNightSummary(endingAgo: 3_600)
        let end = legacy.sleep.stageSnapshot.mainSessionInterval?.end
        legacy.sleep.stageSnapshot.mainSessionInterval = nil
        let store = makeStore(summary: legacy)
        XCTAssertEqual(store.latestNightEnd, end)
        XCTAssertTrue(store.sleepVitalsWindowIsOpen())
    }

    func testChangedAtMovesOnlyWhenTheMainSessionChanges() async throws {
        let first = sleepNightSummary(endingAgo: 3 * day)
        let store = makeStore(summary: first)
        XCTAssertNil(store.latestNightChangedAt, "a relaunch anchors on the night's end")
        XCTAssertFalse(store.sleepVitalsWindowIsOpen())
        var recomputed = first
        recomputed.sleep.stageSnapshot.timeZoneIdentifier = "UTC"
        let same = await publish(recomputed, to: store)
        XCTAssertTrue(same)
        XCTAssertEqual(store.healthSummary.sleep.stageSnapshot.mainSessionInterval, first.sleep.stageSnapshot.mainSessionInterval)
        XCTAssertNil(store.latestNightChangedAt)
        let lateNight = sleepNightSummary(endingAgo: 2 * day)
        let late = await publish(lateNight, to: store)
        XCTAssertTrue(late)
        let changedAt = try XCTUnwrap(store.latestNightChangedAt)
        XCTAssertTrue(store.sleepVitalsWindowIsOpen(), "a night that arrives late reopens the window")
        var again = lateNight
        again.sleep.stageSnapshot.timeZoneIdentifier = "UTC"
        let unchanged = await publish(again, to: store)
        XCTAssertTrue(unchanged)
        XCTAssertEqual(store.latestNightChangedAt, changedAt)
    }

    func testSleepValidationTrustsAPostNightStampOnlyWithScopeAndNonNegativeElapsed() {
        let now = Date()
        let signature = makeStore().currentDashboardCacheScope().signature
        let closedNight = sleepNightSummary(endingAgo: 12 * 3_600, now: now)
        func needsValidation(_ kind: HealthMetricKind = .sleep, stamp: Date?, scope: String? = nil,
                             summary: HealthSummarySnapshot) -> Bool {
            let store = makeStore(summary: summary, validation: stamp.map {
                [kind.rawValue: HealthDashboardSnapshotStore.Freshness(date: $0, contextSignature: scope ?? signature)]
            })
            XCTAssertEqual(store.currentDashboardCacheScope().signature, signature)
            return store.observedMetricNeedsValidation(kind, date: now)
        }
        XCTAssertFalse(needsValidation(stamp: now.addingTimeInterval(-8 * 3_600), summary: closedNight),
                       "read after the night with the window closed")
        XCTAssertTrue(needsValidation(stamp: now.addingTimeInterval(3_600), summary: closedNight), "future stamp")
        XCTAssertTrue(needsValidation(stamp: now.addingTimeInterval(-8 * 3_600), scope: "other", summary: closedNight),
                      "mismatched scope")
        XCTAssertTrue(needsValidation(stamp: nil, summary: closedNight), "missing stamp")
        XCTAssertTrue(needsValidation(stamp: now.addingTimeInterval(-14 * 3_600), summary: closedNight), "pre-night stamp")
        XCTAssertTrue(needsValidation(stamp: now.addingTimeInterval(-45 * 60),
                                      summary: sleepNightSummary(endingAgo: 3_600, now: now)), "window open")
        XCTAssertTrue(needsValidation(.heartRate, stamp: now.addingTimeInterval(-8 * 3_600), summary: closedNight),
                      "the rule is for sleep only")
        XCTAssertFalse(needsValidation(stamp: now.addingTimeInterval(-10 * 60), summary: closedNight), "fresh stamp")
    }
}
