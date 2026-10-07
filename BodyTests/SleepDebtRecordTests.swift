//
//  SleepDebtRecordTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Frozen Sleep Debt nights: the record context that decides when they are
/// re-judged, how they persist on `HealthTrendSnapshot`, and how
/// `recalculatingSleepDebt` applies, drops and mints them. A past night only
/// moves when the goal, a sleep or Training Load source, the Sleep or Workouts
/// permission, or the algorithm changes.
final class SleepDebtRecordTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    private let goal: TimeInterval = 8 * 3_600

    // MARK: - Record context signature

    private func signature(
        permissions: Set<BodyHealthPermission> = Set(BodyHealthPermission.allCases),
        sources: [HealthMetricKind: BodyHealthDataSourceOption] = [:],
        idealSleepDuration: TimeInterval = 8 * 3_600
    ) -> String {
        HealthKitWorkoutStore.sleepDebtRecordContextSignature(
            permissionSelection: BodyHealthPermissionSelection(enabledPermissions: permissions),
            healthDataSourceSelection: BodyHealthDataSourceSelection(selectedOptions: sources),
            combinesHealthDataSourcesByName: false,
            idealSleepDuration: idealSleepDuration,
            showsSubMinuteAwakeStages: false,
            showsLeadingTrailingAwakeStages: false
        )
    }

    func testSignatureChangesWithTheGoalMinutes() {
        XCTAssertNotEqual(signature(idealSleepDuration: 8 * 3_600), signature(idealSleepDuration: 7.5 * 3_600))
        // Signed in whole minutes, so a sub minute difference is the same goal.
        XCTAssertEqual(signature(idealSleepDuration: 8 * 3_600), signature(idealSleepDuration: 8 * 3_600 + 10))
    }

    func testSignatureChangesWithTheSleepWorkoutsAndHeartPermissions() {
        let all = Set(BodyHealthPermission.allCases)
        XCTAssertNotEqual(signature(), signature(permissions: all.subtracting([.sleep])))
        XCTAssertNotEqual(signature(), signature(permissions: all.subtracting([.workouts])))
        // The sleep HRV adjustment reads HRV under the Heart permission.
        XCTAssertNotEqual(signature(), signature(permissions: all.subtracting([.heart])))
    }

    func testSignatureChangesWithTheSleepAndHRVSources() {
        let watch = BodyHealthDataSourceOption(id: "source:watch", name: "Watch")
        XCTAssertNotEqual(signature(), signature(sources: [.sleep: watch]))
        // Sleep HRV is fetched through the HRV metric's source.
        XCTAssertNotEqual(signature(), signature(sources: [.heartRateVariability: watch]))
    }

    /// Training Load is signed like Readiness signs it. It has no source picker
    /// of its own (it is built from workouts), so its option always resolves to
    /// all sources and an override cannot move the signature; the cache scope
    /// still invalidates on it should it ever gain one.
    func testSignatureSignsTheTrainingLoadSource() {
        XCTAssertTrue(HealthKitWorkoutStore.sleepDebtInputMetricKinds.contains(.trainingLoad))
        let resolved = BodyHealthDataSourceSelection.defaultValue.option(for: .trainingLoad).id
        XCTAssertTrue(signature().contains("\(HealthMetricKind.trainingLoad.rawValue):\(resolved)"))
    }

    func testSignatureIsStableForInputsSleepDebtDoesNotRead() {
        let all = Set(BodyHealthPermission.allCases)
        let otherSource = BodyHealthDataSourceOption(id: "source:other", name: "Other")
        XCTAssertEqual(signature(), signature())
        XCTAssertEqual(signature(), signature(permissions: all.subtracting([.steps])))
        XCTAssertEqual(signature(), signature(permissions: all.subtracting([.bloodOxygen])))
        XCTAssertEqual(signature(), signature(sources: [.heartRate: otherSource]))
        XCTAssertEqual(signature(), signature(sources: [.steps: otherSource]))
    }

    func testSignatureCarriesTheAlgorithmVersion() {
        XCTAssertTrue(signature().hasSuffix(";sleepDebt[\(SleepDebtChartModel.algorithmVersion)]"))
    }

    // MARK: - Snapshot persistence

    private func record(on day: Date, need: TimeInterval = 8 * 3_600) throws -> SleepDebtRecord {
        try XCTUnwrap(SleepDebtRecord(
            night: SleepDebtNight(
                day: day,
                actualDuration: 7 * 3_600,
                needDuration: need,
                isNeedLearned: true,
                trainingAdjustment: 10 * 60,
                hrvAdjustment: 5 * 60,
                recordedNightCount: 14,
                debtAfterNight: 2 * 3_600
            ),
            capturedAt: day.addingTimeInterval(30 * 3_600)
        ))
    }

    func testSnapshotRoundTripsTheRecordsThroughJSON() throws {
        var trends = HealthTrendSnapshot.empty
        trends.recordedSleepDebt = [try record(on: daysAgo(2, from: try date(2026, 6, 20)))]
        trends.recordedSleepDebtContext = "context"

        let decoded = try JSONDecoder().decode(HealthTrendSnapshot.self, from: try JSONEncoder().encode(trends))

        XCTAssertEqual(decoded.recordedSleepDebt, trends.recordedSleepDebt)
        XCTAssertEqual(decoded.recordedSleepDebtContext, "context")
    }

    /// A snapshot persisted by a build before the records existed still decodes.
    func testSnapshotWithoutTheKeysDecodesToNoRecords() throws {
        var trends = HealthTrendSnapshot.empty
        trends.recordedSleepDebt = [try record(on: daysAgo(2, from: try date(2026, 6, 20)))]
        trends.recordedSleepDebtContext = "context"
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(trends)) as? [String: Any]
        )
        XCTAssertNotNil(object.removeValue(forKey: "recordedSleepDebt"))
        XCTAssertNotNil(object.removeValue(forKey: "recordedSleepDebtContext"))

        let decoded = try JSONDecoder().decode(
            HealthTrendSnapshot.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.recordedSleepDebt, [])
        XCTAssertEqual(decoded.recordedSleepDebtContext, "")
    }

    func testSleepPermissionOffClearsTheRecords() throws {
        var trends = HealthTrendSnapshot.empty
        trends.recordedSleepDebt = [try record(on: daysAgo(2, from: try date(2026, 6, 20)))]
        let all = Set(BodyHealthPermission.allCases)

        XCTAssertEqual(
            trends.filtered(by: BodyHealthPermissionSelection(enabledPermissions: all)).recordedSleepDebt,
            trends.recordedSleepDebt
        )
        XCTAssertEqual(
            trends.filtered(by: BodyHealthPermissionSelection(enabledPermissions: all.subtracting([.sleep]))).recordedSleepDebt,
            []
        )
    }

    func testReplacingTheSleepMetricCopiesTheRecords() throws {
        var refreshed = HealthTrendSnapshot.empty
        refreshed.recordedSleepDebt = [try record(on: daysAgo(2, from: try date(2026, 6, 20)))]
        refreshed.recordedSleepDebtContext = "refreshed"

        let replaced = HealthTrendSnapshot.empty.replacingMetric(.sleep, with: refreshed)
        let untouched = HealthTrendSnapshot.empty.replacingMetric(.heartRate, with: refreshed)

        XCTAssertEqual(replaced.recordedSleepDebt, refreshed.recordedSleepDebt)
        XCTAssertEqual(replaced.recordedSleepDebtContext, "refreshed")
        XCTAssertEqual(untouched.recordedSleepDebt, [])
        XCTAssertEqual(untouched.recordedSleepDebtContext, "")
    }

    // MARK: - recalculatingSleepDebt

    /// 110 nights ending today, drifting around the goal, with a Training Load
    /// series, so every charted night learns its need and carries a debt. The
    /// night `missingDaysAgo` has no sleep.
    private func snapshot(now: Date, missingDaysAgo: Int? = nil, shortenDaysAgo: Int? = nil) -> HealthDashboardSnapshot {
        let nights = (0..<110).compactMap { age -> SleepDaySummary? in
            guard age != missingDaysAgo else {
                return nil
            }
            var asleep = 7.6 + 0.4 * sin(Double(age) / 3.5) + 0.3 * sin(Double(age) / 1.7)
            if age == shortenDaysAgo {
                asleep -= 2
            }
            let day = daysAgo(age, from: now)
            return SleepDaySummary(
                date: day,
                summary: SleepSummary(
                    duration: asleep * 3_600,
                    stageSnapshot: SleepStageSnapshot(date: day, segments: []),
                    vitals: SleepVitalsSummary(heartRateVariability: 58 + 3 * sin(Double(age) / 3.1))
                )
            )
        }
        var trends = HealthTrendSnapshot.empty
        trends.sleepHistory = SleepHistorySnapshot(days: nights)
        trends.trainingLoad = HealthTrendSeries(points: (0..<110).map { age in
            HealthTrendDataPoint(
                date: daysAgo(age, from: now).addingTimeInterval(18 * 3_600),
                value: 0.85 + 0.2 * Double(age % 5)
            )
        })
        return HealthDashboardSnapshot(summary: .empty, trends: trends)
    }

    private func liveNights(_ snapshot: HealthDashboardSnapshot, now: Date, goal: TimeInterval) -> [SleepDebtNight] {
        SleepDebtChartModel.make(
            entries: SleepDebtChartModel.entries(
                sleepHistory: snapshot.trends.sleepHistory,
                currentDaySummary: snapshot.summary.sleep,
                trainingLoad: snapshot.trends.trainingLoad,
                today: now,
                calendar: calendar
            ),
            sleepGoal: goal,
            calendar: calendar
        ).nights
    }

    /// Freezing mints a record for every past night with sleep, exactly as it
    /// was shown, and leaves today and a night with no sleep live.
    func testFreezingRecordsEveryPastNightWithSleepAndLeavesTodayLive() throws {
        let now = try date(2026, 6, 20, 9)
        let today = calendar.startOfDay(for: now)
        let base = snapshot(now: now, missingDaysAgo: 4)
        let live = liveNights(base, now: now, goal: goal)
        XCTAssertGreaterThanOrEqual(live.count, 20)
        XCTAssertTrue(live.contains { ($0.debtAfterNight ?? 0) > 0 }, "the fixture must carry debts")

        let frozen = base.recalculatingSleepDebt(
            on: now, calendar: calendar, now: now, sleepGoal: goal, freezes: true, recordedSleepDebtContext: "A"
        )
        let records = frozen.trends.recordedSleepDebt

        let expected = live.filter { $0.day < today && $0.actualDuration != nil }
        XCTAssertEqual(records.map(\.day), expected.map(\.day))
        XCTAssertEqual(records.map { $0.night(on: $0.day) }, expected)
        XCTAssertFalse(records.contains { calendar.isDate($0.day, inSameDayAs: today) }, "today stays live")
        XCTAssertFalse(records.contains { $0.day == daysAgo(4, from: now) }, "a night with no sleep is never frozen")
        XCTAssertTrue(records.allSatisfy { $0.capturedAt == now })
        XCTAssertEqual(frozen.trends.recordedSleepDebtContext, "A")
    }

    /// Without `freezes` the pass applies the existing records and keeps them,
    /// but never mints one: a phase 1 history must not become permanent.
    func testWithoutFreezingRecordsAreKeptButNeverAdded() throws {
        let now = try date(2026, 6, 20, 9)
        let base = snapshot(now: now)

        let untouched = base.recalculatingSleepDebt(
            on: now, calendar: calendar, now: now, sleepGoal: goal, freezes: false, recordedSleepDebtContext: "A"
        )
        XCTAssertEqual(untouched.trends.recordedSleepDebt, [])
        XCTAssertEqual(untouched.trends.recordedSleepDebtContext, "A")

        var frozen = base.recalculatingSleepDebt(
            on: now, calendar: calendar, now: now, sleepGoal: goal, freezes: true, recordedSleepDebtContext: "A"
        )
        // Yesterday has not been frozen yet, as after a short refresh.
        let yesterday = daysAgo(1, from: now)
        frozen.trends.recordedSleepDebt.removeAll { $0.day == yesterday }
        let kept = frozen.trends.recordedSleepDebt
        // The history behind a frozen night changes later.
        frozen.trends.sleepHistory = snapshot(now: now, shortenDaysAgo: 3).trends.sleepHistory

        let applied = frozen.recalculatingSleepDebt(
            on: now, calendar: calendar, now: now.addingTimeInterval(3_600), sleepGoal: goal, freezes: false,
            recordedSleepDebtContext: "A"
        )

        XCTAssertEqual(applied.trends.recordedSleepDebt, kept)
        XCTAssertFalse(applied.trends.recordedSleepDebt.contains { $0.day == yesterday })
    }

    /// A stale context drops the records even when the pass may not freeze, so
    /// nights judged under the old goal never render next to the new one.
    func testWithoutFreezingAStaleContextStillDropsTheRecords() throws {
        let now = try date(2026, 6, 20, 9)
        let frozen = snapshot(now: now).recalculatingSleepDebt(
            on: now, calendar: calendar, now: now, sleepGoal: goal, freezes: true, recordedSleepDebtContext: "A"
        )
        XCTAssertFalse(frozen.trends.recordedSleepDebt.isEmpty)

        let dropped = frozen.recalculatingSleepDebt(
            on: now, calendar: calendar, now: now, sleepGoal: goal, freezes: false, recordedSleepDebtContext: "B"
        )

        XCTAssertEqual(dropped.trends.recordedSleepDebt, [])
        XCTAssertEqual(dropped.trends.recordedSleepDebtContext, "B")
    }

    /// Freezing again under the same context never rewrites a record, even
    /// when the history behind it moved.
    func testRefreezingNeverRewritesARecord() throws {
        let now = try date(2026, 6, 20, 9)
        var frozen = snapshot(now: now).recalculatingSleepDebt(
            on: now, calendar: calendar, now: now, sleepGoal: goal, freezes: true, recordedSleepDebtContext: "A"
        )
        let records = frozen.trends.recordedSleepDebt
        frozen.trends.sleepHistory = snapshot(now: now, shortenDaysAgo: 3).trends.sleepHistory

        let refrozen = frozen.recalculatingSleepDebt(
            on: now, calendar: calendar, now: now.addingTimeInterval(3_600), sleepGoal: goal, freezes: true,
            recordedSleepDebtContext: "A"
        )

        XCTAssertEqual(refrozen.trends.recordedSleepDebt, records)
    }

    /// A goal change is a new context: every night is dropped and refrozen
    /// under the new goal.
    func testANewContextDropsTheRecordsAndRefreezesThem() throws {
        let now = try date(2026, 6, 20, 9)
        let base = snapshot(now: now)
        let frozen = base.recalculatingSleepDebt(
            on: now, calendar: calendar, now: now, sleepGoal: goal, freezes: true, recordedSleepDebtContext: "A"
        )
        let later = now.addingTimeInterval(3_600)
        let newGoal: TimeInterval = 7 * 3_600

        let refrozen = frozen.recalculatingSleepDebt(
            on: now, calendar: calendar, now: later, sleepGoal: newGoal, freezes: true, recordedSleepDebtContext: "B"
        )

        let records = refrozen.trends.recordedSleepDebt
        XCTAssertEqual(refrozen.trends.recordedSleepDebtContext, "B")
        XCTAssertEqual(records.map(\.day), frozen.trends.recordedSleepDebt.map(\.day))
        XCTAssertTrue(records.allSatisfy { $0.capturedAt == later })
        XCTAssertEqual(
            records.map { $0.night(on: $0.day) },
            liveNights(base, now: now, goal: newGoal).filter { $0.day < calendar.startOfDay(for: now) && $0.actualDuration != nil }
        )
        XCTAssertNotEqual(records.map(\.needDuration), frozen.trends.recordedSleepDebt.map(\.needDuration))
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    /// Start of the day `count` days before `date`'s day.
    private func daysAgo(_ count: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: -count, to: calendar.startOfDay(for: date)) ?? date
    }
}
