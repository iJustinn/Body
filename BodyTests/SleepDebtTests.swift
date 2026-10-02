//
//  SleepDebtTests.swift
//  BodyTests
//

import HealthKit
import SwiftUI
import XCTest
@testable import Body

final class SleepDebtTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    private let goal: TimeInterval = 8 * 3_600

    // MARK: - Sums, clamping, recorded nights

    func testShortfallsAndSurplusesSumOverFourteenNights() throws {
        let today = try date(2026, 6, 20)
        var durations: [Int: TimeInterval] = [:]
        for daysAgo in 0..<7 { durations[daysAgo] = hours(7) }
        for daysAgo in 7..<14 { durations[daysAgo] = hours(8.5) }

        let model = model(today: today, durations: durations)

        XCTAssertEqual(try XCTUnwrap(model.debt), hours(3.5), accuracy: 0.001)
        XCTAssertEqual(model.latestNight?.recordedNightCount, 14)
    }

    func testTotalNeverDropsBelowZero() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(0..<14, hours(9)))

        XCTAssertEqual(model.debt, 0)
    }

    func testNightsWithoutUsableSleepAreSkipped() throws {
        let today = try date(2026, 6, 20)
        var durations = nights(0..<5, hours(7))
        durations[5] = 0
        durations[6] = .nan
        durations[7] = -hours(1)

        let fiveRecorded = model(today: today, durations: durations)
        XCTAssertEqual(try XCTUnwrap(fiveRecorded.debt), hours(5), accuracy: 0.001)
        XCTAssertEqual(fiveRecorded.latestNight?.recordedNightCount, 5)
        XCTAssertNil(fiveRecorded.night(on: daysAgo(6, from: today))?.actualDuration)

        durations[4] = nil
        let fourRecorded = model(today: today, durations: durations)
        XCTAssertNil(fourRecorded.debt)
        XCTAssertEqual(fourRecorded.latestNight?.recordedNightCount, 4)
    }

    func testRawDurationsAreSummedBeforeRounding() throws {
        let today = try date(2026, 6, 20)
        let sevenFiftyOneTen = hours(7) + 51 * 60 + 10
        let model = model(today: today, durations: nights(0..<14, sevenFiftyOneTen))

        // 14 × 8m50s is 2h03m40s; rounding each night up first would say 1h52m.
        XCTAssertEqual(try XCTUnwrap(model.debt), 7_420, accuracy: 0.001)
        XCTAssertEqual(model.latestNight?.actualDuration, sevenFiftyOneTen)
    }

    func testGoalSetsEveryNightsNeedUntilTheNeedIsLearned() throws {
        let today = try date(2026, 6, 20)
        let sevenHourGoal = model(today: today, durations: nights(0..<14, hours(7)), goal: hours(7))

        XCTAssertTrue(sevenHourGoal.nights.allSatisfy { $0.needDuration == self.hours(7) && !$0.isNeedLearned })
        XCTAssertEqual(sevenHourGoal.debt, 0)
    }

    // MARK: - Learned need

    /// Against an 8h goal, a night that learned 7h30m gets a 7h50m base need,
    /// one that learned 9h gets 8h20m, and one that learned nothing yet keeps
    /// the goal.
    func testEachNightMovesTheGoalAThirdOfTheWayTowardItsOwnLearnedNeed() throws {
        let today = try date(2026, 6, 20)
        var learnedNeeds = nights(0..<12, hours(7.5))
        learnedNeeds[12] = hours(9)
        let debtEntries = entries(
            today: today,
            durations: nights(0..<14, hours(7) + 40 * 60),
            ratios: [1: 1.5],
            hrvZScores: [1: -2],
            learnedNeeds: learnedNeeds
        )

        let learned = SleepDebtChartModel.make(entries: debtEntries, sleepGoal: hours(8))
        let columns = learned.chartNights

        XCTAssertEqual(learned.sleepGoal, hours(8))
        XCTAssertFalse(columns[0].isNeedLearned)
        XCTAssertEqual(columns[0].needDuration, hours(8))
        XCTAssertTrue(columns.dropFirst().allSatisfy(\.isNeedLearned))
        XCTAssertEqual(columns[1].needDuration, hours(8) + 20 * 60)
        XCTAssertTrue(columns.dropFirst(2).dropLast().allSatisfy { $0.needDuration == self.hours(7) + 50 * 60 })
        XCTAssertEqual(columns.last?.needDuration, hours(7) + 50 * 60 + 30 * 60 + 20 * 60)
        // 20 and 40 minutes short on the two oldest nights, 10 on each of the
        // next 11, and 60 tonight.
        XCTAssertEqual(try XCTUnwrap(learned.debt), (20 + 40 + 11 * 10 + 60) * 60, accuracy: 0.001)
    }

    func testBaseNeedMovesTheGoalAThirdOfTheWayInFiveMinuteSteps() {
        XCTAssertEqual(SleepDebtChartModel.baseNeed(learnedNeed: hours(9), sleepGoal: hours(7)), hours(7) + 40 * 60)
        XCTAssertEqual(SleepDebtChartModel.baseNeed(learnedNeed: hours(7), sleepGoal: hours(9)), hours(8) + 20 * 60)
        // A third of 50 minutes is 16m40s, stepped to 15; a third of 55 is 18m20s, stepped to 20.
        XCTAssertEqual(SleepDebtChartModel.baseNeed(learnedNeed: hours(8) + 20 * 60, sleepGoal: hours(7.5)), hours(7) + 45 * 60)
        XCTAssertEqual(SleepDebtChartModel.baseNeed(learnedNeed: hours(8) + 25 * 60, sleepGoal: hours(7.5)), hours(7) + 50 * 60)
    }

    /// 28 nights 8 minutes apart from 6 hours: the 75th percentile falls between
    /// the 21st and 22nd (8h40m and 8h48m), and the 5 minute step lands on 8h40m.
    func testLearnedNeedIsTheSeventyFifthPercentileInFiveMinuteSteps() {
        let durations = (0..<28).map { hours(6) + Double($0) * 8 * 60 }

        XCTAssertEqual(SleepDebtChartModel.learnedNeed(durations: durations), hours(8) + 40 * 60)
        XCTAssertEqual(SleepDebtChartModel.learnedNeed(durations: durations.reversed()), hours(8) + 40 * 60)
        XCTAssertNil(SleepDebtChartModel.learnedNeed(durations: Array(durations.dropLast())))
    }

    func testLearnedNeedStaysBetweenSixAndTenHours() {
        XCTAssertEqual(SleepDebtChartModel.learnedNeed(durations: Array(repeating: hours(5), count: 28)), hours(6))
        XCTAssertEqual(SleepDebtChartModel.learnedNeed(durations: Array(repeating: hours(11), count: 28)), hours(10))
    }

    /// Each day learns its need from the recorded nights of the 56 days ending
    /// on it: for today a night 56 days ago is out and one 55 days ago is in,
    /// while yesterday still counts the one 56 days before today.
    func testEachDayLearnsItsNeedFromTheFiftySixDaysEndingOnIt() throws {
        let now = try date(2026, 6, 20, 9)
        var history = (1...27).map { night(on: daysAgo($0, from: now), hours(7)) }
        history.append(night(on: daysAgo(40, from: now), 0))
        history.append(night(on: daysAgo(56, from: now), hours(9)))

        func learnedNeed(daysAgo count: Int, _ history: [SleepDaySummary]) -> TimeInterval? {
            let entries = SleepDebtChartModel.entries(
                sleepHistory: SleepHistorySnapshot(days: history),
                currentDaySummary: nil,
                trainingLoad: .empty,
                today: now,
                calendar: calendar
            )
            return entries[entries.count - 1 - count].learnedNeed
        }

        XCTAssertNil(learnedNeed(daysAgo: 0, history))
        XCTAssertEqual(learnedNeed(daysAgo: 1, history), hours(7))
        history.append(night(on: daysAgo(55, from: now), hours(9)))
        XCTAssertEqual(learnedNeed(daysAgo: 0, history), hours(7))
    }

    /// Against a 7h30m goal, the 8 weeks ending yesterday hold 15 nights of
    /// 8h25m on top, so yesterday learns 8h25m and a 7h50m base need. Today's
    /// 8h20m night comes in as one of those leaves, so today learns 8h20m and
    /// 7h45m. Only today's night takes the lower need: every night the chart
    /// showed yesterday reads the same today, where one need for every night
    /// would move each point by 14 nights of 5 minutes.
    @MainActor
    func testEarlierNightsKeepTheirNeedAndDebtWhenTheLearnedNeedMoves() throws {
        let now = try date(2026, 6, 20, 9)
        let dayBefore = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        func duration(daysAgo: Int) -> TimeInterval {
            switch daysAgo {
            case 0: hours(8) + 20 * 60
            case 42...56: hours(8) + 25 * 60
            default: daysAgo.isMultiple(of: 2) ? hours(8) + 10 * 60 : hours(7)
            }
        }
        // Yesterday's page had no night for today yet.
        func model(today: Date, newestDaysAgo: Int) -> SleepDebtChartModel {
            let history = (newestDaysAgo...110).map { night(on: daysAgo($0, from: now), duration(daysAgo: $0)) }
            return BodySleepDebtChartCache().model(
                inputs: SleepDebtChartModel.inputs(
                    sleepHistory: SleepHistorySnapshot(days: history),
                    currentDaySummary: nil,
                    trainingLoad: .empty,
                    today: today,
                    calendar: calendar
                ),
                sleepGoal: hours(7.5)
            )
        }

        let yesterdaysPage = model(today: dayBefore, newestDaysAgo: 1)
        let todaysPage = model(today: now, newestDaysAgo: 0)

        XCTAssertEqual(todaysPage.nights.count, SleepDebtChartModel.selectableNightCount)
        XCTAssertEqual(Array(todaysPage.nights.dropLast()), Array(yesterdaysPage.nights.dropFirst()))
        XCTAssertEqual(try XCTUnwrap(yesterdaysPage.debt), hours(3.5), accuracy: 0.001)
        let yesterday = try XCTUnwrap(todaysPage.night(on: daysAgo(1, from: now)))
        XCTAssertEqual(yesterday.needDuration, hours(7) + 50 * 60)
        XCTAssertEqual(try XCTUnwrap(yesterday.debtAfterNight), hours(3.5), accuracy: 0.001)
        XCTAssertEqual(todaysPage.nights.last?.needDuration, hours(7) + 45 * 60)
        XCTAssertEqual(try XCTUnwrap(todaysPage.debt), hours(3.25), accuracy: 0.001)
    }

    // MARK: - Window and anchor

    func testChartColumnsAreTheFourteenDaysEndingToday() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(0..<14, hours(8)))

        XCTAssertEqual(model.nights.count, SleepDebtChartModel.selectableNightCount)
        XCTAssertEqual(model.nights.first?.day, daysAgo(29, from: today))
        XCTAssertEqual(model.chartNights.map(\.day), (0..<14).reversed().map { daysAgo($0, from: today) })
    }

    func testHeadlineWaitsForTodaysNight() throws {
        let today = try date(2026, 6, 20)
        let pending = model(today: today, durations: nights(1..<14, hours(7.75)))

        XCTAssertNil(pending.chartNights.last?.debtAfterNight)
        XCTAssertEqual(pending.latestNight?.day, daysAgo(1, from: today))
        XCTAssertEqual(try XCTUnwrap(pending.debt), hours(3.25), accuracy: 0.001)

        var withToday = nights(1..<14, hours(7.75))
        withToday[0] = hours(8)
        let arrived = model(today: today, durations: withToday)

        XCTAssertEqual(arrived.latestNight?.day, daysAgo(0, from: today))
        XCTAssertEqual(try XCTUnwrap(arrived.debt), hours(3.25), accuracy: 0.001)
    }

    /// The calendar window moves on at midnight even without new sleep: the
    /// only five recordings sit at the far end of the window, so after one
    /// more unrecorded day just four remain.
    func testWindowMovesOnAtMidnightWithoutNewSleep() throws {
        let dayD = try date(2026, 6, 20)
        let dayAfter = daysAgo(-1, from: dayD)
        let shortNights = [14, 13, 12, 11, 10]

        let atD = model(today: dayD, durations: Dictionary(uniqueKeysWithValues: shortNights.map { ($0, hours(7)) }))
        XCTAssertEqual(try XCTUnwrap(atD.debt), hours(5), accuracy: 0.001)

        let atNextDay = model(today: dayAfter, durations: Dictionary(uniqueKeysWithValues: shortNights.map { ($0 + 1, hours(7)) }))
        XCTAssertNil(atNextDay.debt)
        XCTAssertEqual(atNextDay.latestNight?.day, daysAgo(0, from: dayD))
        XCTAssertEqual(atNextDay.latestNight?.recordedNightCount, 4)
    }

    func testTwoDayGapKeepsAValueWhileCoverageLasts() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(2..<14, hours(7.5)))

        XCTAssertEqual(model.latestNight?.day, daysAgo(1, from: today))
        XCTAssertEqual(model.latestNight?.recordedNightCount, 12)
        XCTAssertEqual(try XCTUnwrap(model.debt), hours(6), accuracy: 0.001)
    }

    func testDebtExpiresAfterFourteenDaysWithoutSleep() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(15..<30, hours(6)))

        XCTAssertNil(model.debt)
        XCTAssertEqual(model.latestNight?.recordedNightCount, 0)
    }

    func testOldShortNightLeavingTheWindowLowersTheTotal() throws {
        let today = try date(2026, 6, 20)
        var durations = nights(0..<14, hours(8))
        durations[14] = hours(6)

        let model = model(today: today, durations: durations)
        let columns = model.chartNights

        XCTAssertEqual(try XCTUnwrap(columns[12].debtAfterNight), hours(2), accuracy: 0.001)
        XCTAssertEqual(columns[13].debtAfterNight, 0)
    }

    func testOldLongNightLeavingTheWindowRaisesTheTotal() throws {
        let today = try date(2026, 6, 20)
        var durations = nights(1..<14, hours(7.75))
        durations[0] = hours(8)
        durations[14] = hours(10)

        let model = model(today: today, durations: durations)
        let columns = model.chartNights

        XCTAssertEqual(try XCTUnwrap(columns[12].debtAfterNight), hours(1.25), accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(columns[13].debtAfterNight), hours(3.25), accuracy: 0.001)
    }

    func testTotalIsCappedAtSixHours() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(0..<14, hours(7)))

        XCTAssertEqual(model.debt, SleepDebtChartModel.maximumDebt)
        XCTAssertEqual(model.debt, hours(6))
    }

    func testRecordedNightCountsFollowTheWindow() throws {
        let today = try date(2026, 6, 20)
        let everyOtherNight = Dictionary(uniqueKeysWithValues: stride(from: 0, through: 12, by: 2).map { ($0, hours(7)) })

        let model = model(today: today, durations: everyOtherNight)
        let columns = model.chartNights

        XCTAssertEqual(columns[13].recordedNightCount, 7)
        XCTAssertEqual(columns[12].recordedNightCount, 6)
        XCTAssertEqual(columns[3].recordedNightCount, 2)
        XCTAssertNil(columns[3].debtAfterNight)
        XCTAssertEqual(self.model(today: today, durations: nights(0..<14, hours(8))).latestNight?.recordedNightCount, 14)
    }

    // MARK: - Selected nights

    func testNightOnFindsAnOlderNightWithItsOwnWindow() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(20..<34, hours(7.75)))
        let twentyDaysAgo = daysAgo(20, from: today)

        let night = try XCTUnwrap(model.night(on: twentyDaysAgo.addingTimeInterval(9 * 3_600)))
        XCTAssertEqual(night.day, twentyDaysAgo)
        XCTAssertEqual(night.actualDuration, hours(7.75))
        XCTAssertEqual(night.recordedNightCount, 14)
        XCTAssertEqual(try XCTUnwrap(night.debtAfterNight), hours(3.5), accuracy: 0.001)
        XCTAssertFalse(model.chartNights.contains { $0.day == twentyDaysAgo })
        XCTAssertNil(model.debt)
    }

    func testNightOnReportsAMissingNightWithItsDebt() throws {
        let today = try date(2026, 6, 20)
        var durations = nights(0..<20, hours(7.75))
        durations[3] = nil

        let model = model(today: today, durations: durations)
        // Its window runs from 3 to 16 days back, 13 of them recorded.
        let night = try XCTUnwrap(model.night(on: daysAgo(3, from: today)))

        XCTAssertNil(night.actualDuration)
        XCTAssertFalse(night.isRecorded)
        XCTAssertEqual(night.recordedNightCount, 13)
        XCTAssertEqual(try XCTUnwrap(night.debtAfterNight), hours(3.25), accuracy: 0.001)
    }

    func testNightOnIsNilOutsideThePickableDays() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(0..<14, hours(7)))

        XCTAssertNil(model.night(on: daysAgo(30, from: today)))
        XCTAssertNil(model.night(on: daysAgo(-1, from: today)))
        XCTAssertNil(SleepDebtChartModel.empty.night(on: today))
    }

    // MARK: - Training adjustment

    func testTrainingAdjustmentSteps() {
        let cases: [(ratio: Double?, minutes: Double)] = [
            (nil, 0), (.nan, 0), (.infinity, 0), (0.8, 0), (1.0, 0),
            (1.0625, 5), (1.25, 15), (1.3, 20), (1.375, 25), (1.5, 30), (2.5, 30)
        ]
        for testCase in cases {
            XCTAssertEqual(
                SleepDebtChartModel.trainingAdjustment(forTrainingLoadRatio: testCase.ratio),
                testCase.minutes * 60,
                "ratio \(String(describing: testCase.ratio))"
            )
        }
    }

    func testTrainingAdjustmentComesFromThePreviousDay() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(0..<14, hours(8)), ratios: [1: 1.5])

        let tonight = try XCTUnwrap(model.nights.last)
        XCTAssertEqual(tonight.trainingAdjustment, 30 * 60)
        XCTAssertEqual(tonight.needDuration, hours(8.5))
        XCTAssertEqual(model.nights.dropLast().last?.trainingAdjustment, 0)
        XCTAssertEqual(try XCTUnwrap(model.debt), 30 * 60, accuracy: 0.001)
    }

    func testFirstEntryLendsItsTrainingLoadToTheOldestWindow() throws {
        let today = try date(2026, 6, 20)
        let oldestWindow = nights(29..<43, hours(8))

        let withoutRatio = model(today: today, durations: oldestWindow)
        XCTAssertEqual(withoutRatio.nights.first?.debtAfterNight, 0)

        let withRatio = model(today: today, durations: oldestWindow, ratios: [43: 1.5])
        XCTAssertEqual(try XCTUnwrap(withRatio.nights.first?.debtAfterNight), 30 * 60, accuracy: 0.001)
    }

    // MARK: - HRV adjustment

    func testHRVAdjustmentSteps() {
        let cases: [(zScore: Double?, minutes: Double)] = [
            (nil, 0), (.nan, 0), (-.infinity, 0), (1, 0), (-0.5, 0), (-1, 0),
            (-1.1, 0), (-1.25, 5), (-1.5, 10), (-1.75, 15), (-2, 20), (-3.5, 20)
        ]
        for testCase in cases {
            XCTAssertEqual(
                SleepDebtChartModel.hrvAdjustment(forHRVZScore: testCase.zScore),
                testCase.minutes * 60,
                "z \(String(describing: testCase.zScore))"
            )
        }
    }

    func testLowHRVRaisesTheNextNightsNeedOnly() throws {
        let today = try date(2026, 6, 20)
        let model = model(today: today, durations: nights(0..<14, hours(8)), hrvZScores: [1: -2])

        let tonight = try XCTUnwrap(model.nights.last)
        XCTAssertEqual(tonight.hrvAdjustment, 20 * 60)
        XCTAssertEqual(tonight.needDuration, goal + 20 * 60)
        let lowNight = try XCTUnwrap(model.nights.dropLast().last)
        XCTAssertEqual(lowNight.hrvAdjustment, 0)
        XCTAssertEqual(lowNight.needDuration, goal)
        XCTAssertEqual(try XCTUnwrap(model.debt), 20 * 60, accuracy: 0.001)
    }

    func testTrainingAndHRVAdjustmentsAddUp() throws {
        let today = try date(2026, 6, 20)
        let model = model(
            today: today, durations: nights(0..<14, hours(8)), ratios: [1: 1.5], hrvZScores: [1: -1.5]
        )

        let tonight = try XCTUnwrap(model.nights.last)
        XCTAssertEqual(tonight.trainingAdjustment, 30 * 60)
        XCTAssertEqual(tonight.hrvAdjustment, 10 * 60)
        XCTAssertEqual(tonight.needDuration, goal + 40 * 60)
        XCTAssertEqual(try XCTUnwrap(model.debt), 40 * 60, accuracy: 0.001)
    }

    /// A flat 60 ms history leaves the spread at its 5 ms floor, so a 50 ms
    /// night sits exactly 2 spreads low.
    func testEntriesJudgeEachNightsHRVAgainstTheNightsBeforeIt() throws {
        let now = try date(2026, 6, 20, 9)
        var history = (2..<100).map { night(on: daysAgo($0, from: now), hours(8), hrv: 60) }
        history.append(night(on: daysAgo(1, from: now), hours(8), hrv: 50))
        history.append(night(on: daysAgo(0, from: now), hours(8)))

        let entries = SleepDebtChartModel.entries(
            sleepHistory: SleepHistorySnapshot(days: history),
            currentDaySummary: nil,
            trainingLoad: .empty,
            today: now,
            calendar: calendar
        )

        XCTAssertEqual(try XCTUnwrap(entries[entries.count - 2].hrvZScore), -2, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(entries[entries.count - 3].hrvZScore), 0, accuracy: 0.000_001)
        XCTAssertNil(entries.last?.hrvZScore)

        let model = SleepDebtChartModel.make(entries: entries, sleepGoal: goal)
        XCTAssertEqual(model.nights.last?.hrvAdjustment, 20 * 60)
        XCTAssertEqual(model.nights.dropLast().last?.hrvAdjustment, 0)
    }

    /// Against the 14 nights before it (median 60, MAD 5), a 45 ms night sits
    /// about 2 spreads low. Counted in its own baseline, it would pull the
    /// median to 55 and widen the spread, leaving it under 1 spread low.
    func testTheJudgedNightNeverCountsInItsOwnBaseline() throws {
        let now = try date(2026, 6, 20, 9)
        var history = (2..<16).map { night(on: daysAgo($0, from: now), hours(8), hrv: $0.isMultiple(of: 2) ? 55 : 65) }
        history.append(night(on: daysAgo(1, from: now), hours(8), hrv: 45))

        let entries = SleepDebtChartModel.entries(
            sleepHistory: SleepHistorySnapshot(days: history),
            currentDaySummary: nil,
            trainingLoad: .empty,
            today: now,
            calendar: calendar
        )

        let zScore = try XCTUnwrap(entries[entries.count - 2].hrvZScore)
        XCTAssertEqual(zScore, -15 / (1.4826 * 5), accuracy: 0.000_001)
        XCTAssertEqual(SleepDebtChartModel.make(entries: entries, sleepGoal: goal).nights.last?.hrvAdjustment, 20 * 60)
    }

    func testHRVWaitsForFourteenBaselineNights() throws {
        let now = try date(2026, 6, 20, 9)

        func yesterdaysZScore(baselineNightCount: Int) -> Double? {
            var history = (2..<(2 + baselineNightCount)).map { night(on: daysAgo($0, from: now), hours(8), hrv: 60) }
            history.append(night(on: daysAgo(1, from: now), hours(8), hrv: 50))
            let entries = SleepDebtChartModel.entries(
                sleepHistory: SleepHistorySnapshot(days: history),
                currentDaySummary: nil,
                trainingLoad: .empty,
                today: now,
                calendar: calendar
            )
            return entries[entries.count - 2].hrvZScore
        }

        XCTAssertNil(yesterdaysZScore(baselineNightCount: 13))
        XCTAssertEqual(try XCTUnwrap(yesterdaysZScore(baselineNightCount: 14)), -2, accuracy: 0.000_001)
    }

    /// The oldest entry lends its HRV to the night after it, so it is judged
    /// too, against a baseline reaching 56 nights before any entry.
    func testTheOldestEntryIsJudgedAgainstAWholeBaselineBeforeTheEntries() throws {
        let now = try date(2026, 6, 20, 9)
        let oldestDaysAgo = SleepDebtChartModel.entryDayCount - 1
        // Only the far end of that baseline has HRV.
        var history = ((oldestDaysAgo + 43)...(oldestDaysAgo + 56)).map {
            night(on: daysAgo($0, from: now), hours(8), hrv: 60)
        }
        history.append(night(on: daysAgo(oldestDaysAgo, from: now), hours(8), hrv: 50))

        let entries = SleepDebtChartModel.entries(
            sleepHistory: SleepHistorySnapshot(days: history),
            currentDaySummary: nil,
            trainingLoad: .empty,
            today: now,
            calendar: calendar
        )

        XCTAssertEqual(entries.first?.day, daysAgo(oldestDaysAgo, from: now))
        XCTAssertEqual(try XCTUnwrap(entries.first?.hrvZScore), -2, accuracy: 0.000_001)
    }

    func testMakeRejectsTheWrongEntryCount() throws {
        let today = try date(2026, 6, 20)
        let entries = entries(today: today, durations: nights(0..<14, hours(7)))

        XCTAssertEqual(SleepDebtChartModel.make(entries: Array(entries.dropFirst()), sleepGoal: goal), .empty)
    }

    // MARK: - Watch nights

    /// The watch charts the last 14 nights with the same 14 night debt: each
    /// night reads only its own window, the entry before it, and the history
    /// behind them, so a 14 night model must equal the picker model's last 14
    /// nights field for field, with learned needs, Training Load and sleep HRV
    /// all moving the needs.
    func testWatchNightsAreThePickerModelsLastFourteenNights() throws {
        let now = try date(2026, 6, 20, 9)
        let (history, trainingLoad) = watchParityHistory(now: now)
        let watchNightCount = SleepDebtChartModel.watchNightCount

        let card = SleepDebtChartModel.make(
            entries: SleepDebtChartModel.entries(
                sleepHistory: history, currentDaySummary: nil, trainingLoad: trainingLoad, today: now, calendar: calendar
            ),
            sleepGoal: goal
        )
        let watch = SleepDebtChartModel.make(
            entries: SleepDebtChartModel.entries(
                sleepHistory: history,
                currentDaySummary: nil,
                trainingLoad: trainingLoad,
                nightCount: watchNightCount,
                today: now,
                calendar: calendar
            ),
            sleepGoal: goal,
            nightCount: watchNightCount
        )

        XCTAssertEqual(watchNightCount, 14)
        XCTAssertEqual(watch.nights.count, watchNightCount)
        XCTAssertEqual(watch.nights, Array(card.nights.suffix(watchNightCount)))
        XCTAssertEqual(watch.debt, card.debt)
        XCTAssertEqual(watch.nights.last?.day, daysAgo(0, from: now))

        // The comparison covers every input: each compared night learned its
        // need, the windows behind them carry training and HRV additions, and
        // no debt sits at a clamp that could hide a different sum.
        let windows = card.nights.suffix(watchNightCount + SleepDebtChartModel.windowNightCount - 1)
        XCTAssertTrue(watch.nights.allSatisfy(\.isNeedLearned))
        XCTAssertTrue(windows.contains { $0.trainingAdjustment > 0 })
        XCTAssertTrue(windows.contains { $0.hrvAdjustment > 0 })
        XCTAssertTrue(watch.nights.allSatisfy { night in
            night.debtAfterNight.map { $0 > 0 && $0 < SleepDebtChartModel.maximumDebt } ?? false
        })
    }

    /// The watch's compute seed keeps `historyDayCount` nights, so that is
    /// exactly how far back `inputs` reads: 85 days back is read and 86 is
    /// not for the watch's 14 nights (101 and 102 for the picker's 30).
    func testHistoryDayCountIsHowFarInputsReads() throws {
        let now = try date(2026, 6, 20, 9)
        XCTAssertEqual(SleepDebtChartModel.historyDayCount(nightCount: SleepDebtChartModel.watchNightCount), 86)
        XCTAssertEqual(SleepDebtChartModel.historyDayCount(nightCount: SleepDebtChartModel.selectableNightCount), 102)

        for nightCount in [SleepDebtChartModel.watchNightCount, SleepDebtChartModel.selectableNightCount] {
            let oldestRead = SleepDebtChartModel.historyDayCount(nightCount: nightCount) - 1
            let history = SleepHistorySnapshot(days: [
                night(on: daysAgo(oldestRead + 1, from: now), hours(7), hrv: 60),
                night(on: daysAgo(oldestRead, from: now), hours(7), hrv: 60)
            ])

            let inputs = SleepDebtChartModel.inputs(
                sleepHistory: history,
                currentDaySummary: nil,
                trainingLoad: .empty,
                nightCount: nightCount,
                today: now,
                calendar: calendar
            )

            XCTAssertEqual(inputs.nights.map(\.day), [daysAgo(oldestRead, from: now)], "\(nightCount) nights")
            XCTAssertEqual(inputs.days.count, nightCount + SleepDebtChartModel.windowNightCount, "\(nightCount) nights")
        }
    }

    /// The phone's call sites pass no night count, so they read and build
    /// exactly what they did before the parameter existed.
    func testDefaultNightCountIsThePickerWindow() throws {
        let now = try date(2026, 6, 20, 9)
        let (history, trainingLoad) = watchParityHistory(now: now)
        let pickerNightCount = SleepDebtChartModel.selectableNightCount

        XCTAssertEqual(
            SleepDebtChartModel.inputs(
                sleepHistory: history, currentDaySummary: nil, trainingLoad: trainingLoad, today: now, calendar: calendar
            ),
            SleepDebtChartModel.inputs(
                sleepHistory: history,
                currentDaySummary: nil,
                trainingLoad: trainingLoad,
                nightCount: pickerNightCount,
                today: now,
                calendar: calendar
            )
        )
        let defaultEntries = SleepDebtChartModel.entries(
            sleepHistory: history, currentDaySummary: nil, trainingLoad: trainingLoad, today: now, calendar: calendar
        )
        XCTAssertEqual(defaultEntries.count, SleepDebtChartModel.entryDayCount)
        XCTAssertEqual(
            defaultEntries,
            SleepDebtChartModel.entries(
                sleepHistory: history,
                currentDaySummary: nil,
                trainingLoad: trainingLoad,
                nightCount: pickerNightCount,
                today: now,
                calendar: calendar
            )
        )

        let model = SleepDebtChartModel.make(entries: defaultEntries, sleepGoal: goal)
        XCTAssertEqual(model.nights.count, pickerNightCount)
        XCTAssertEqual(model, SleepDebtChartModel.make(entries: defaultEntries, sleepGoal: goal, nightCount: pickerNightCount))
        // Entries sized for one night count are rejected by another.
        XCTAssertEqual(
            SleepDebtChartModel.make(entries: defaultEntries, sleepGoal: goal, nightCount: SleepDebtChartModel.watchNightCount),
            .empty
        )
    }

    // MARK: - Entries

    func testEntriesPreferHistoryAndUseTheLiveSummaryOnlyForToday() throws {
        let now = try date(2026, 6, 20, 9)
        let today = calendar.startOfDay(for: now)
        let yesterday = daysAgo(1, from: now)
        let history = SleepHistorySnapshot(days: [night(on: yesterday, hours(6))])

        let liveToday = summary(on: today, hours(7))
        let entries = SleepDebtChartModel.entries(
            sleepHistory: history, currentDaySummary: liveToday, trainingLoad: .empty, today: now, calendar: calendar
        )
        XCTAssertEqual(entries.count, SleepDebtChartModel.entryDayCount)
        XCTAssertEqual(entries.first?.day, daysAgo(43, from: now))
        XCTAssertEqual(entries.last?.day, today)
        XCTAssertEqual(entries.last?.duration, hours(7))
        XCTAssertEqual(entries[entries.count - 2].duration, hours(6))

        let historyWithToday = SleepHistorySnapshot(days: [night(on: yesterday, hours(6)), night(on: today, hours(5))])
        let historyFirst = SleepDebtChartModel.entries(
            sleepHistory: historyWithToday, currentDaySummary: liveToday, trainingLoad: .empty, today: now, calendar: calendar
        )
        XCTAssertEqual(historyFirst.last?.duration, hours(5))

        let staleLive = summary(on: yesterday, hours(9))
        let stale = SleepDebtChartModel.entries(
            sleepHistory: .empty, currentDaySummary: staleLive, trainingLoad: .empty, today: now, calendar: calendar
        )
        XCTAssertTrue(stale.allSatisfy { $0.duration == nil })
    }

    func testEntriesKeepTheFirstNightOfADuplicateDay() throws {
        let now = try date(2026, 6, 20, 9)
        let day = daysAgo(3, from: now)
        let history = SleepHistorySnapshot(days: [
            SleepDaySummary(date: day.addingTimeInterval(6 * 3_600), summary: summary(on: day, hours(5))),
            SleepDaySummary(date: day, summary: summary(on: day, hours(7)))
        ])

        let entries = SleepDebtChartModel.entries(
            sleepHistory: history, currentDaySummary: nil, trainingLoad: .empty, today: now, calendar: calendar
        )

        let entry = try XCTUnwrap(entries.first { $0.day == day })
        XCTAssertEqual(entry.duration, hours(7))
        XCTAssertEqual(entry.duration, history.summary(on: day, calendar: calendar)?.summary.duration)
    }

    func testEntriesKeepTheLatestTrainingLoadPointOfADay() throws {
        let now = try date(2026, 6, 20, 9)
        let day = daysAgo(2, from: now)
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: day.addingTimeInterval(20 * 3_600), value: 1.4),
            HealthTrendDataPoint(date: day.addingTimeInterval(8 * 3_600), value: 1.2),
            HealthTrendDataPoint(date: day.addingTimeInterval(22 * 3_600), value: .nan)
        ])

        let entries = SleepDebtChartModel.entries(
            sleepHistory: .empty, currentDaySummary: nil, trainingLoad: series, today: now, calendar: calendar
        )

        XCTAssertEqual(entries.first { $0.day == day }?.trainingLoadRatio, 1.4)
    }

    func testEntriesStepByCalendarDayAcrossDaylightSavingChanges() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        for (month, day) in [(3, 20), (11, 10)] {
            let now = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9)))
            let days = SleepHistorySnapshot.datePickerDates(
                endingAt: now, dayCount: SleepDebtChartModel.entryDayCount, calendar: newYork
            )
            let history = SleepHistorySnapshot(days: days.map { night(on: $0, hours(7)) })
            let series = HealthTrendSeries(points: days.map { HealthTrendDataPoint(date: $0.addingTimeInterval(18 * 3_600), value: 1.5) })

            let entries = SleepDebtChartModel.entries(
                sleepHistory: history, currentDaySummary: nil, trainingLoad: series, today: now, calendar: newYork
            )

            XCTAssertEqual(entries.map(\.day), days)
            for (earlier, later) in zip(entries, entries.dropFirst()) {
                XCTAssertEqual(newYork.dateComponents([.day], from: earlier.day, to: later.day).day, 1)
            }
            XCTAssertTrue(entries.allSatisfy { $0.duration == self.hours(7) }, "\(month)/\(day)")
            XCTAssertTrue(entries.dropLast().allSatisfy { $0.trainingLoadRatio == 1.5 }, "\(month)/\(day)")

            let model = SleepDebtChartModel.make(entries: entries, sleepGoal: goal)
            XCTAssertTrue(model.nights.allSatisfy { $0.trainingAdjustment == 30 * 60 }, "\(month)/\(day)")
        }
    }

    /// The live summary is judged in the calendar passed in, not the process
    /// time zone: 23 hours apart, the two instants share a day only there.
    func testEntriesJudgeTheLiveSummaryInTheGivenCalendar() throws {
        let processOffset = TimeZone.current.secondsFromGMT()
        let shift = processOffset - 6 * 3_600 >= -12 * 3_600 ? -6 * 3_600 : 6 * 3_600
        var other = Calendar(identifier: .gregorian)
        other.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: processOffset + shift))

        let dayStart = try XCTUnwrap(other.date(from: DateComponents(year: 2026, month: 6, day: 20)))
        let summaryDate = dayStart.addingTimeInterval(30 * 60)
        let now = dayStart.addingTimeInterval(23.5 * 3_600)
        XCTAssertTrue(other.isDate(summaryDate, inSameDayAs: now))
        XCTAssertFalse(Calendar.bodyGregorian.isDate(summaryDate, inSameDayAs: now))

        let live = SleepSummary(duration: hours(7), stageSnapshot: SleepStageSnapshot(date: summaryDate, segments: []))
        let entries = SleepDebtChartModel.entries(
            sleepHistory: .empty, currentDaySummary: live, trainingLoad: .empty, today: now, calendar: other
        )

        XCTAssertEqual(entries.last?.day, dayStart)
        XCTAssertEqual(entries.last?.duration, hours(7))
    }

    // MARK: - Inputs and cache

    /// The gathered inputs are the Sleep page cache's key: they must change with
    /// every value the model reads, and only with those.
    func testInputsChangeOnlyWithWhatTheModelReads() throws {
        let now = try date(2026, 6, 20, 9)
        let history = (1..<100).map { night(on: daysAgo($0, from: now), hours(7), hrv: 60) }
        let load = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: daysAgo(2, from: now).addingTimeInterval(18 * 3_600), value: 1.2)
        ])
        func inputs(
            _ days: [SleepDaySummary],
            live: SleepSummary? = nil,
            trainingLoad: HealthTrendSeries? = nil
        ) -> SleepDebtChartModel.Inputs {
            SleepDebtChartModel.inputs(
                sleepHistory: SleepHistorySnapshot(days: days),
                currentDaySummary: live,
                trainingLoad: trainingLoad ?? load,
                today: now,
                calendar: calendar
            )
        }
        let base = inputs(history)

        // Not read: another vital, and a night older than any baseline reaches.
        var otherVital = history
        let sixDaysAgo = daysAgo(6, from: now)
        otherVital[5] = SleepDaySummary(date: sixDaysAgo, summary: SleepSummary(
            duration: hours(7),
            stageSnapshot: SleepStageSnapshot(date: sixDaysAgo, segments: []),
            vitals: SleepVitalsSummary(heartRate: 48, heartRateVariability: 60)
        ))
        XCTAssertEqual(inputs(otherVital), base)
        XCTAssertEqual(inputs(history + [night(on: daysAgo(120, from: now), hours(3), hrv: 20)]), base)

        // Not read: today's Training Load ratio and today's sleep HRV, which
        // only set tomorrow's need, so a workout logged today or a revised
        // HRV for last night leaves the cache key as it was.
        var todayLoad = load
        todayLoad.points.append(HealthTrendDataPoint(date: now, value: 1.5))
        XCTAssertEqual(inputs(history, trainingLoad: todayLoad), base)
        let today = daysAgo(0, from: now)
        XCTAssertEqual(
            inputs(history + [night(on: today, hours(7), hrv: 30)]),
            inputs(history + [night(on: today, hours(7), hrv: 60)])
        )
        XCTAssertEqual(
            inputs(history, live: summary(on: today, hours(7), hrv: 30)),
            inputs(history, live: summary(on: today, hours(7), hrv: 60))
        )

        // Read: HRV deep in a baseline, a night's duration, a Training Load
        // ratio, and the live summary standing in for today.
        var lowHRV = history
        lowHRV[80] = night(on: daysAgo(81, from: now), hours(7), hrv: 40)
        XCTAssertNotEqual(inputs(lowHRV), base)
        var shortNight = history
        shortNight[0] = night(on: daysAgo(1, from: now), hours(5), hrv: 60)
        XCTAssertNotEqual(inputs(shortNight), base)
        XCTAssertNotEqual(inputs(history, trainingLoad: .empty), base)
        XCTAssertNotEqual(inputs(history, live: summary(on: daysAgo(0, from: now), hours(6))), base)
    }

    @MainActor
    func testCacheRebuildsWhenItsInputsOrTheGoalChange() throws {
        let now = try date(2026, 6, 20, 9)
        func inputs(sleeping duration: TimeInterval) -> SleepDebtChartModel.Inputs {
            SleepDebtChartModel.inputs(
                sleepHistory: SleepHistorySnapshot(days: (0..<14).map { night(on: daysAgo($0, from: now), duration) }),
                currentDaySummary: nil,
                trainingLoad: .empty,
                today: now,
                calendar: calendar
            )
        }
        let cache = BodySleepDebtChartCache()

        let first = cache.model(inputs: inputs(sleeping: hours(7.75)), sleepGoal: goal)
        XCTAssertEqual(first.debt, hours(3.5))
        XCTAssertEqual(cache.model(inputs: inputs(sleeping: hours(7.75)), sleepGoal: goal), first)
        XCTAssertEqual(cache.model(inputs: inputs(sleeping: hours(7.75)), sleepGoal: hours(7)).debt, 0)
        XCTAssertEqual(cache.model(inputs: inputs(sleeping: hours(8)), sleepGoal: goal).debt, 0)
    }

    // MARK: - Chart colors

    @MainActor
    func testChartColorsEachNightByItsDebtBand() {
        let low = Color(red: 0.20, green: 0.72, blue: 1.00)
        let radarPink = BodyRadarChartStyle.color(for: .minor)
        let radarRed = BodyRadarChartStyle.color(for: .major)
        func color(_ debt: TimeInterval) -> Color {
            BodySleepDebtChart.bandColor(for: debt, lowColor: low)
        }

        XCTAssertEqual(color(0), low)
        XCTAssertEqual(color(hours(2) - 1), low)
        XCTAssertEqual(color(hours(2)), radarPink)
        XCTAssertEqual(color(hours(4)), radarPink)
        XCTAssertEqual(color(hours(4) + 1), radarRed)
        XCTAssertEqual(color(hours(12)), radarRed)

        // The callout names the band over the same edges.
        XCTAssertEqual(BodySleepDebtChart.bandTitle(for: hours(2) - 1), "LOW DEBT")
        XCTAssertEqual(BodySleepDebtChart.bandTitle(for: hours(2)), "MODERATE DEBT")
        XCTAssertEqual(BodySleepDebtChart.bandTitle(for: hours(4)), "MODERATE DEBT")
        XCTAssertEqual(BodySleepDebtChart.bandTitle(for: hours(4) + 1), "HIGH DEBT")
    }

    // MARK: - Refresh

    /// The Sleep page's pull re-reads Training Load with sleep, efforts
    /// included, so a workout that synced or was re-rated since the last
    /// refresh reaches the need at once.
    @MainActor
    func testSleepPullRereadsChangedWorkoutsIntoTheNeed() async throws {
        let restoreLoadDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreLoadDefaults() }
        let now = Date()
        let fake = FakeHealthStore()
        let workoutType = HKObjectType.workoutType()
        let effortType = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .workoutEffortScore))
        let sampleTypes: [HKSampleType] = [
            try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)),
            effortType,
            workoutType
        ]
        for type in sampleTypes {
            fake.scriptSources(for: type, .sources([]))
            fake.scriptSamples(for: type, .samples([]))
        }
        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: [.sleep, .workouts]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [], engineHealthStore: fake
        )
        store.contextRefreshOverride = { _ in }
        func run(daysAgo count: Int, hours: Double) -> HKWorkout {
            let start = daysAgo(count, from: now).addingTimeInterval(7 * 3_600)
            return makeTestWorkout(activityType: .running, start: start, end: start.addingTimeInterval(hours * 3_600), metadata: nil)
        }
        func effort(_ score: Double) -> HKQuantitySample {
            HKQuantitySample(type: effortType, quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: score), start: now, end: now)
        }
        func todaysNeed() -> TimeInterval? {
            let entries = SleepDebtChartModel.entries(
                sleepHistory: store.healthTrends.sleepHistory,
                currentDaySummary: nil,
                trainingLoad: store.healthTrends.trainingLoad,
                today: now,
                calendar: calendar
            )
            return SleepDebtChartModel.make(entries: entries, sleepGoal: goal).nights.last?.needDuration
        }

        // Four months of an hour's run every other day settle the ratio, and
        // yesterday was a rest day, so today's need is the goal.
        let usual = stride(from: 120, through: 2, by: -2).map { run(daysAgo: $0, hours: 1) }
        fake.scriptSamples(for: workoutType, .samples(usual))
        await store.refreshHealthMetric(.sleep, date: now)
        XCTAssertEqual(todaysNeed(), goal)

        // A long run rated 5 then syncs for yesterday, and only the Sleep page
        // is pulled.
        let longRun = run(daysAgo: 1, hours: 3)
        let longRunEffort = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: longRun, activity: nil)
        fake.scriptSamples(for: effortType, matching: longRunEffort, .samples([effort(5)]))
        fake.scriptSamples(for: workoutType, .samples(usual + [longRun]))
        await store.refreshHealthMetric(.sleep, date: now)
        XCTAssertEqual(todaysNeed(), goal + SleepDebtChartModel.maximumTrainingAdjustment)

        // The same run is re-rated 2, keeping its UUID. Its cached 5 would stay
        // valid for a day, so only a fresh effort read lowers the need.
        fake.scriptSamples(for: effortType, matching: longRunEffort, .samples([effort(2)]))
        await store.refreshHealthMetric(.sleep, date: now)
        XCTAssertEqual(todaysNeed(), goal + 20 * 60)
    }

    // MARK: - Helpers

    private func hours(_ value: Double) -> TimeInterval {
        value * 3_600
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    /// Start of the day `count` days before `date`'s day (negative counts go forward).
    private func daysAgo(_ count: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: -count, to: calendar.startOfDay(for: date)) ?? date
    }

    private func nights(_ daysAgo: Range<Int>, _ duration: TimeInterval) -> [Int: TimeInterval] {
        Dictionary(uniqueKeysWithValues: daysAgo.map { ($0, duration) })
    }

    private func summary(on day: Date, _ duration: TimeInterval, hrv: Double? = nil) -> SleepSummary {
        SleepSummary(
            duration: duration,
            stageSnapshot: SleepStageSnapshot(date: day, segments: []),
            vitals: SleepVitalsSummary(heartRateVariability: hrv)
        )
    }

    private func night(on day: Date, _ duration: TimeInterval, hrv: Double? = nil) -> SleepDaySummary {
        SleepDaySummary(date: day, summary: summary(on: day, duration, hrv: hrv))
    }

    /// 110 nights ending today whose asleep time drifts around the goal (one
    /// 6 hour night 3 days back), with sleep HRV near 58 ms that drops 2 to 3
    /// spreads low on a few nights, and Training Load ratios from 0.85 to 1.65.
    /// Every night of a 30 night model learns its need, and the debts of the
    /// last 14 land between 0 and 6 hours.
    private func watchParityHistory(now: Date) -> (history: SleepHistorySnapshot, trainingLoad: HealthTrendSeries) {
        let nights = (0..<110).map { age -> SleepDaySummary in
            var asleep = 8.35 + 0.3 * sin(Double(age) / 3.5) + 0.25 * sin(Double(age) / 1.7)
            if age == 3 {
                asleep = 6
            }
            var hrv = 58 + 3 * sin(Double(age) / 3.1)
            if [2, 9, 16].contains(age) {
                hrv = 42
            } else if [5, 12].contains(age) {
                hrv = 49
            }
            return night(on: daysAgo(age, from: now), hours(asleep), hrv: hrv)
        }
        let trainingLoad = HealthTrendSeries(points: (0..<110).map { age in
            HealthTrendDataPoint(
                date: daysAgo(age, from: now).addingTimeInterval(18 * 3_600),
                value: 0.85 + 0.2 * Double(age % 5)
            )
        })
        return (SleepHistorySnapshot(days: nights), trainingLoad)
    }

    /// `entryDayCount` entries ending on `today`, keyed by days ago (0 is today).
    private func entries(
        today: Date,
        durations: [Int: TimeInterval],
        ratios: [Int: Double] = [:],
        hrvZScores: [Int: Double] = [:],
        learnedNeeds: [Int: TimeInterval] = [:]
    ) -> [SleepDebtChartModel.Entry] {
        let days = SleepHistorySnapshot.datePickerDates(
            endingAt: today, dayCount: SleepDebtChartModel.entryDayCount, calendar: calendar
        )
        return days.enumerated().map { index, day in
            let daysAgo = days.count - 1 - index
            return SleepDebtChartModel.Entry(
                day: day,
                duration: durations[daysAgo],
                trainingLoadRatio: ratios[daysAgo],
                hrvZScore: hrvZScores[daysAgo],
                learnedNeed: learnedNeeds[daysAgo]
            )
        }
    }

    private func model(
        today: Date,
        durations: [Int: TimeInterval],
        ratios: [Int: Double] = [:],
        hrvZScores: [Int: Double] = [:],
        goal: TimeInterval? = nil
    ) -> SleepDebtChartModel {
        SleepDebtChartModel.make(
            entries: entries(today: today, durations: durations, ratios: ratios, hrvZScores: hrvZScores),
            sleepGoal: goal ?? self.goal
        )
    }
}
