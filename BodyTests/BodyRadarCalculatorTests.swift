//
//  BodyRadarCalculatorTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class BodyRadarCalculatorTests: XCTestCase {
    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 0, minute: 0)) ?? Date()
    }

    private func date(_ day: Date, hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func offsetDay(_ day: Date, _ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day) ?? day
    }

    /// A night with vitals only, which is how backfilled sleep history arrives.
    private func vitalsNight(
        on day: Date,
        heartRate: Double? = 55,
        respiratoryRate: Double? = 14,
        temperature: Double? = 36.0,
        heartRateVariability: Double? = 60,
        stages: SleepStageSnapshot = .empty
    ) -> SleepDaySummary {
        SleepDaySummary(
            date: day,
            summary: SleepSummary(
                duration: 8 * 3_600,
                stageSnapshot: stages,
                vitals: SleepVitalsSummary(
                    heartRate: heartRate,
                    heartRateVariability: heartRateVariability,
                    respiratoryRate: respiratoryRate,
                    oxygenSaturation: nil,
                    wristTemperatureCelsius: temperature
                )
            )
        )
    }

    /// Flat nights at the given day offsets before `scoringDay`.
    private func flatHistory(
        before scoringDay: Date,
        offsets: [Int],
        heartRate: Double? = 55,
        respiratoryRate: Double? = 14,
        temperature: Double? = 36.0,
        heartRateVariability: Double? = 60,
        stagesFor: ((Date) -> SleepStageSnapshot)? = nil
    ) -> [SleepDaySummary] {
        offsets.map { offset in
            let dayStart = offsetDay(scoringDay, -offset)
            return vitalsNight(
                on: dayStart,
                heartRate: heartRate,
                respiratoryRate: respiratoryRate,
                temperature: temperature,
                heartRateVariability: heartRateVariability,
                stages: stagesFor?(dayStart) ?? .empty
            )
        }
    }

    /// A single-session night ending at 07:00, with a known wake-cycle boundary.
    private func nightStages(on day: Date, asleepHours: Double = 8) -> SleepStageSnapshot {
        let end = date(day, hour: 7)
        return SleepStageSnapshot(
            date: day,
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: end.addingTimeInterval(-asleepHours * 3_600),
                    endDate: end
                )
            ]
        )
    }

    private func night(
        on scoringDay: Date,
        history: [SleepDaySummary],
        currentDaySleep: SleepSummary? = nil
    ) -> BodyRadarNight {
        BodyRadarCalculator.night(
            on: scoringDay,
            sleepHistory: SleepHistorySnapshot(days: history),
            currentDaySleep: currentDaySleep,
            today: scoringDay,
            calendar: calendar
        )
    }

    private func signal(_ kind: BodyRadarSignalKind, in night: BodyRadarNight) -> BodyRadarSignal? {
        night.signals.first { $0.kind == kind }
    }

    // MARK: - Scoring

    func testFourMovedSignalsScoreMajorSigns() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(
            vitalsNight(
                on: scoringDay,
                heartRate: 55 + 8,
                respiratoryRate: 14 + 1.5,
                temperature: 36.0 + 0.6,
                heartRateVariability: 60 - 15
            )
        )

        let tonight = night(on: scoringDay, history: history)

        XCTAssertEqual(tonight.state, .majorSigns)
        XCTAssertEqual(tonight.corroboration, .sameNight)
        XCTAssertEqual(tonight.flaggedSignals.count, 4)
        // temp 1.5 · (1.5 − 0.5) + rr 1.0 · (1.25 − 0.5)
        //   + hr 1.0 · (1.333 − 0.5) + hrv 1.0 · (1.5 − 0.5)
        XCTAssertEqual(tonight.evidence, 1.5 + 0.75 + (8.0 / 6.0 - 0.5) + 1.0, accuracy: 0.001)
        XCTAssertEqual(signal(.heartRateVariability, in: tonight)?.deviation ?? 0, -1.5, accuracy: 0.001)
    }

    func testOneSaturatedSignalCapsAtMinorSigns() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(2...21))
        // Beta 3: one family alerts only through persistence, so the previous
        // night carries persistence evidence (temperature +1.25 bands, 1.125).
        history.append(vitalsNight(on: offsetDay(scoringDay, -1), temperature: 36.5))
        // +3 typical bands of skin temperature, everything else flat.
        history.append(vitalsNight(on: scoringDay, temperature: 36.0 + 3 * 2 * 0.2))

        let tonight = night(on: scoringDay, history: history)

        XCTAssertEqual(tonight.state, .minorSigns)
        XCTAssertEqual(tonight.corroboration, .persistence)
        XCTAssertEqual(tonight.flaggedSignals.map(\.kind), [.wristTemperature])
        XCTAssertGreaterThanOrEqual(tonight.evidence, BodyRadarCalculator.Tuning.majorEvidence)
    }

    func testSmallHeartRateRiseAloneScoresNoSigns() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay, heartRate: 55 + 4))

        let tonight = night(on: scoringDay, history: history)

        XCTAssertEqual(tonight.state, .noSigns)
        XCTAssertTrue(tonight.flaggedSignals.isEmpty)
    }

    func testHealthyHeartRateVariabilityRiseScoresNoSigns() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay, heartRateVariability: 60 + 30))

        let tonight = night(on: scoringDay, history: history)

        XCTAssertEqual(tonight.state, .noSigns)
        XCTAssertEqual(tonight.evidence, 0, accuracy: 0.001)
        XCTAssertEqual(signal(.heartRateVariability, in: tonight)?.flagged, false)
    }

    func testMissingTemperatureAndRespiratorySensorsStillScore() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(
            before: scoringDay,
            offsets: Array(2...21),
            respiratoryRate: nil,
            temperature: nil
        )
        // Beta 3: heart rate and HRV are one family, so with no other sensor a
        // night alerts only when the previous night's evidence persists.
        history.append(
            vitalsNight(
                on: offsetDay(scoringDay, -1),
                heartRate: 55 + 8,
                respiratoryRate: nil,
                temperature: nil,
                heartRateVariability: 60 - 15
            )
        )
        history.append(
            vitalsNight(
                on: scoringDay,
                heartRate: 55 + 8,
                respiratoryRate: nil,
                temperature: nil,
                heartRateVariability: 60 - 15
            )
        )

        let tonight = night(on: scoringDay, history: history)

        XCTAssertEqual(tonight.signals.map(\.kind), [.sleepingHeartRate, .heartRateVariability])
        XCTAssertEqual(tonight.flaggedSignals.count, 2)
        // Two flagged signals, but the absolute evidence threshold is out of reach.
        XCTAssertEqual(tonight.state, .minorSigns)
        XCTAssertEqual(tonight.corroboration, .persistence)
    }

    // MARK: - Corroboration (Beta 3)

    /// Heart rate +3 bands and HRV -3 bands: 5.0 evidence, two flags, and only
    /// the autonomic family.
    private func extremeAutonomicNight(on day: Date) -> SleepDaySummary {
        vitalsNight(on: day, heartRate: 55 + 18, heartRateVariability: 60 - 30)
    }

    /// Heart rate +8 and HRV -15: raw evidence 1.833 from the autonomic family.
    private func elevatedAutonomicNight(on day: Date) -> SleepDaySummary {
        vitalsNight(on: day, heartRate: 55 + 8, heartRateVariability: 60 - 15)
    }

    func testLowerRespiratoryRateContributesAndFlagsWithItsSignedDeviation() throws {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        // 1.8 breaths below the median is -1.5 typical bands.
        history.append(vitalsNight(on: scoringDay, respiratoryRate: 14 - 1.8))

        let tonight = night(on: scoringDay, history: history)
        let respiration = try XCTUnwrap(signal(.respiratoryRate, in: tonight))

        XCTAssertEqual(respiration.deviation, -1.5, accuracy: 0.001)
        XCTAssertEqual(respiration.directionalDeviation, 1.5, accuracy: 0.001)
        XCTAssertTrue(respiration.flagged)
        XCTAssertEqual(BodyRadarCalculator.contribution(of: respiration), 1.0, accuracy: 0.001)
        XCTAssertEqual(tonight.evidence, 1.0, accuracy: 0.001)
        // HRV still counts only when it falls.
        XCTAssertEqual(
            BodyRadarSignal(kind: .heartRateVariability, deviation: 1, flagged: false).directionalDeviation,
            -1
        )
    }

    func testSingleFamilyExtremeNightIsHeldWithoutAQualifyingPreviousNight() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(extremeAutonomicNight(on: scoringDay))

        let tonight = night(on: scoringDay, history: history)

        XCTAssertEqual(tonight.state, .noSigns)
        XCTAssertEqual(tonight.corroboration, BodyRadarCorroboration.none)
        // Raw evidence and flags are kept for the callout.
        XCTAssertEqual(tonight.evidence, 5.0, accuracy: 0.001)
        XCTAssertEqual(tonight.flaggedSignals.map(\.kind), [.sleepingHeartRate, .heartRateVariability])
        XCTAssertNotNil(tonight.holdExplanation)
        XCTAssertEqual(tonight.unflaggedExplanation, tonight.holdExplanation)
    }

    func testSingleFamilyNightAfterAnElevatedPreviousNightAlertsThroughPersistence() {
        let scoringDay = day(2026, 9, 4)
        let yesterday = offsetDay(scoringDay, -1)
        var history = flatHistory(before: scoringDay, offsets: Array(2...21))
        history.append(elevatedAutonomicNight(on: yesterday))
        history.append(extremeAutonomicNight(on: scoringDay))

        // Yesterday is itself held (the night before it was flat), but its raw
        // evidence still supports tonight.
        let previous = night(on: yesterday, history: history)
        XCTAssertEqual(previous.state, .noSigns)
        XCTAssertEqual(previous.evidence, 8.0 / 6.0 - 0.5 + 1.0, accuracy: 0.001)

        let tonight = night(on: scoringDay, history: history)
        XCTAssertEqual(tonight.state, .majorSigns)
        XCTAssertEqual(tonight.corroboration, .persistence)
        XCTAssertNil(tonight.holdExplanation)
    }

    func testUnscoredOrAbsentPreviousNightBreaksPersistence() {
        let scoringDay = day(2026, 9, 4)
        let yesterday = offsetDay(scoringDay, -1)
        let flat = flatHistory(before: scoringDay, offsets: Array(2...21))
        let nap = SleepDaySummary(
            date: yesterday,
            summary: SleepSummary(
                duration: 3_600,
                stageSnapshot: nightStages(on: yesterday, asleepHours: 1),
                vitals: SleepVitalsSummary(
                    heartRate: 73,
                    heartRateVariability: 30,
                    respiratoryRate: 14,
                    oxygenSaturation: nil,
                    wristTemperatureCelsius: 36.0
                )
            )
        )
        let cases: [(name: String, history: [SleepDaySummary], previousState: BodyRadarState)] = [
            ("absent", flat, .missingSleep),
            ("nap only", flat + [nap], .missingSleep),
            ("insufficient", flat + [vitalsNight(
                on: yesterday, heartRate: 73, respiratoryRate: nil, temperature: nil, heartRateVariability: nil
            )], .insufficientData),
            // Thirteen baseline nights before yesterday: it calibrates, while
            // tonight, with yesterday in its baseline, has fourteen and scores.
            ("calibrating", flatHistory(before: scoringDay, offsets: Array(2...14))
                + [elevatedAutonomicNight(on: yesterday)], .calibrating)
        ]

        for testCase in cases {
            let history = testCase.history + [extremeAutonomicNight(on: scoringDay)]
            XCTAssertEqual(night(on: yesterday, history: history).state, testCase.previousState, testCase.name)

            let tonight = night(on: scoringDay, history: history)
            XCTAssertEqual(tonight.state, .noSigns, testCase.name)
            XCTAssertEqual(tonight.corroboration, BodyRadarCorroboration.none, testCase.name)
            XCTAssertEqual(tonight.evidence, 5.0, accuracy: 0.001, testCase.name)
        }
    }

    func testTwoFamiliesOnOneNightAlertWithoutAQualifyingPreviousNight() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        // Heart rate +1.333 bands (0.833) and temperature +0.75 bands (0.375).
        history.append(vitalsNight(on: scoringDay, heartRate: 55 + 8, temperature: 36.0 + 0.3))

        let previous = night(on: offsetDay(scoringDay, -1), history: history)
        XCTAssertEqual(previous.state, .noSigns)
        XCTAssertEqual(previous.evidence, 0, accuracy: 0.001)

        let tonight = night(on: scoringDay, history: history)
        XCTAssertEqual(tonight.state, .minorSigns)
        XCTAssertEqual(tonight.corroboration, .sameNight)
        XCTAssertEqual(tonight.evidence, 8.0 / 6.0 - 0.5 + 0.375, accuracy: 0.001)
    }

    func testCorroborationThresholdsPassAtEquality() {
        let scoringDay = day(2026, 9, 4)
        // 0.75 bands is exactly 0.25 past the dead zone, in either breathing direction.
        let atMinimum = [
            BodyRadarSignal(kind: .sleepingHeartRate, deviation: 0.75, flagged: false),
            BodyRadarSignal(kind: .heartRateVariability, deviation: 0.4, flagged: false),
            BodyRadarSignal(kind: .respiratoryRate, deviation: -0.75, flagged: false)
        ]
        let families = BodyRadarCalculator.familyContributions(of: atMinimum)
        XCTAssertEqual(families[.autonomic], 0.25)
        XCTAssertEqual(families[.respiratory], 0.25)
        XCTAssertNil(families[.thermal])
        XCTAssertEqual(BodyRadarCalculator.corroboration(signals: atMinimum, previousRawNight: nil), .sameNight)

        let justBelow = [
            BodyRadarSignal(kind: .sleepingHeartRate, deviation: 0.75, flagged: false),
            BodyRadarSignal(kind: .respiratoryRate, deviation: 0.74, flagged: false)
        ]
        XCTAssertEqual(
            BodyRadarCalculator.corroboration(signals: justBelow, previousRawNight: nil),
            BodyRadarCorroboration.none
        )

        let previousAtThreshold = BodyRadarNight(date: offsetDay(scoringDay, -1), state: .noSigns, evidence: 0.75)
        XCTAssertEqual(
            BodyRadarCalculator.corroboration(signals: justBelow, previousRawNight: previousAtThreshold),
            .persistence
        )
        let previousJustBelow = BodyRadarNight(date: offsetDay(scoringDay, -1), state: .noSigns, evidence: 0.7499)
        XCTAssertEqual(
            BodyRadarCalculator.corroboration(signals: justBelow, previousRawNight: previousJustBelow),
            BodyRadarCorroboration.none
        )
        // An unscored previous night never supports, whatever it carries.
        let unscored = BodyRadarNight(date: offsetDay(scoringDay, -1), state: .calibrating, evidence: 3)
        XCTAssertEqual(
            BodyRadarCalculator.corroboration(signals: justBelow, previousRawNight: unscored),
            BodyRadarCorroboration.none
        )
    }

    func testPreviousNightAtExactlyThePersistenceEvidenceEnablesTonight() {
        let scoringDay = day(2026, 9, 4)
        let yesterday = offsetDay(scoringDay, -1)
        var history = flatHistory(before: scoringDay, offsets: Array(2...21))
        // +7.5 bpm is 1.25 bands: exactly 0.75 evidence.
        history.append(vitalsNight(on: yesterday, heartRate: 55 + 7.5))
        history.append(extremeAutonomicNight(on: scoringDay))

        XCTAssertEqual(night(on: yesterday, history: history).evidence, BodyRadarCalculator.Tuning.persistenceEvidence)

        let tonight = night(on: scoringDay, history: history)
        XCTAssertEqual(tonight.state, .majorSigns)
        XCTAssertEqual(tonight.corroboration, .persistence)
    }

    /// Persistence is total raw evidence on the adjacent night, regardless of
    /// the signal or its direction: a low breathing night supports a high one.
    func testOppositeDirectionRespirationPersistsIntoTheNextNight() throws {
        let scoringDay = day(2026, 6, 27)
        let yesterday = offsetDay(scoringDay, -1)
        var history = flatHistory(before: scoringDay, offsets: Array(2...21))
        // Respiration -1.15 bands (0.65) plus a small HRV drop (0.11).
        history.append(vitalsNight(on: yesterday, respiratoryRate: 14 - 1.38, heartRateVariability: 60 - 6.1))
        // Respiration +2 bands (1.5) alone.
        history.append(vitalsNight(on: scoringDay, respiratoryRate: 14 + 2.4))

        let previous = night(on: yesterday, history: history)
        XCTAssertEqual(previous.evidence, 0.76, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(previous.evidence, BodyRadarCalculator.Tuning.persistenceEvidence)
        XCTAssertEqual(previous.state, .noSigns)
        XCTAssertEqual(previous.corroboration, BodyRadarCorroboration.none)
        XCTAssertNotNil(previous.holdExplanation)
        XCTAssertLessThan(try XCTUnwrap(signal(.respiratoryRate, in: previous)).deviation, 0)

        let tonight = night(on: scoringDay, history: history)
        XCTAssertEqual(tonight.state, .minorSigns)
        XCTAssertEqual(tonight.corroboration, .persistence)
        XCTAssertEqual(tonight.flaggedSignals.map(\.kind), [.respiratoryRate])
        XCTAssertGreaterThan(try XCTUnwrap(signal(.respiratoryRate, in: tonight)).deviation, 0)
    }

    func testPersistenceDoesNotChainThroughALowEvidenceNight() {
        let scoringDay = day(2026, 9, 4)
        let yesterday = offsetDay(scoringDay, -1)
        var history = flatHistory(before: scoringDay, offsets: Array(3...22))
        history.append(elevatedAutonomicNight(on: offsetDay(scoringDay, -2)))
        // +6 bpm is one band: 0.5 evidence, below the persistence threshold.
        history.append(vitalsNight(on: yesterday, heartRate: 55 + 6))
        history.append(extremeAutonomicNight(on: scoringDay))

        // Yesterday is supported by the night before it, but only its own raw
        // evidence counts for tonight.
        let previous = night(on: yesterday, history: history)
        XCTAssertEqual(previous.evidence, 0.5, accuracy: 0.001)
        XCTAssertEqual(previous.corroboration, .persistence)
        XCTAssertEqual(previous.state, .noSigns)

        let tonight = night(on: scoringDay, history: history)
        XCTAssertEqual(tonight.state, .noSigns)
        XCTAssertEqual(tonight.corroboration, BodyRadarCorroboration.none)
    }

    func testLateChangeToThePreviousNightLeavesTodaysFrozenVerdict() {
        let scoringDay = day(2026, 9, 4)
        let yesterday = offsetDay(scoringDay, -1)
        let flat = flatHistory(before: scoringDay, offsets: Array(2...21))
        let history = flat + [elevatedAutonomicNight(on: yesterday), extremeAutonomicNight(on: scoringDay)]
        let freezeTime = date(scoringDay, hour: 8)

        let first = summary(history: history, recorded: [], today: scoringDay,
                            now: freezeTime, wakeTime: date(scoringDay, hour: 7))
        XCTAssertEqual(first.summary.latest?.state, .majorSigns)
        XCTAssertEqual(first.summary.latest?.corroboration, .persistence)
        XCTAssertEqual(first.summary.latest?.capture, .freeze)
        XCTAssertEqual(first.summary.latest?.capturedAt, freezeTime)

        // A late sync corrects yesterday to an ordinary night. Recomputed from
        // the current cache, tonight would now be held.
        let corrected = flat + [vitalsNight(on: yesterday), extremeAutonomicNight(on: scoringDay)]
        XCTAssertEqual(night(on: scoringDay, history: corrected).state, .noSigns)

        let later = summary(history: corrected, recorded: first.recorded, today: scoringDay,
                            now: date(scoringDay, hour: 12), wakeTime: date(scoringDay, hour: 7))
        XCTAssertEqual(later.summary.latest, first.summary.latest)
        XCTAssertEqual(
            later.recorded.first { $0.date == scoringDay },
            first.recorded.first { $0.date == scoringDay }
        )
    }

    func testPersistenceLooksBackOneCalendarDayAcrossADaylightSavingChange() {
        // New York leaves daylight saving on Nov 1 2026 and enters it on Mar 8 2026.
        for scoringDay in [day(2026, 11, 2), day(2026, 3, 9)] {
            let yesterday = offsetDay(scoringDay, -1)
            var history = flatHistory(before: scoringDay, offsets: Array(2...21))
            history.append(elevatedAutonomicNight(on: yesterday))
            history.append(extremeAutonomicNight(on: scoringDay))

            let tonight = night(on: scoringDay, history: history)
            XCTAssertEqual(tonight.state, .majorSigns, "\(scoringDay)")
            XCTAssertEqual(tonight.corroboration, .persistence, "\(scoringDay)")
        }
    }

    func testTravelDayFilingTwoNightsKeepsTheFirstForPersistence() {
        let scoringDay = day(2026, 9, 4)
        let yesterday = offsetDay(scoringDay, -1)
        let flat = flatHistory(before: scoringDay, offsets: Array(2...21))

        // Both land on yesterday's key; the earlier one is kept.
        let secondFiling = date(yesterday, hour: 12)
        let ordinaryFirst = flat + [vitalsNight(on: yesterday), elevatedAutonomicNight(on: secondFiling),
                                    extremeAutonomicNight(on: scoringDay)]
        XCTAssertEqual(night(on: scoringDay, history: ordinaryFirst).corroboration, BodyRadarCorroboration.none)

        let elevatedFirst = flat + [elevatedAutonomicNight(on: yesterday), vitalsNight(on: secondFiling),
                                    extremeAutonomicNight(on: scoringDay)]
        XCTAssertEqual(night(on: scoringDay, history: elevatedFirst).corroboration, .persistence)
    }

    // MARK: - Gating

    func testThirteenBaselineNightsCalibrate() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...13))
        history.append(vitalsNight(on: scoringDay, temperature: 36.0 + 1.0))

        let tonight = night(on: scoringDay, history: history)

        XCTAssertEqual(tonight.state, .calibrating)
        XCTAssertTrue(tonight.signals.isEmpty)
    }

    func testFourteenBaselineNightsScore() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...14))
        history.append(vitalsNight(on: scoringDay, temperature: 36.0 + 1.0))

        let tonight = night(on: scoringDay, history: history)

        XCTAssertTrue(tonight.state.isScored)
        XCTAssertEqual(tonight.signals.count, 4)
    }

    func testSparseRecentNightsCalibrateDespiteALongBaseline() {
        let scoringDay = day(2026, 9, 4)
        // 20 older nights carry the baseline, but only five of the last fourteen
        // days hold a night, so with tonight that is six of the required seven.
        var history = flatHistory(before: scoringDay, offsets: Array(20...39))
        history.append(contentsOf: flatHistory(before: scoringDay, offsets: Array(1...5)))
        history.append(vitalsNight(on: scoringDay, temperature: 36.0 + 1.0))

        let tonight = night(on: scoringDay, history: history)

        XCTAssertEqual(tonight.state, .calibrating)
    }

    func testNapOnlyCurrentDayReadsAsMissingSleep() {
        let scoringDay = day(2026, 9, 4)
        let history = flatHistory(before: scoringDay, offsets: Array(1...20))
        let napEnd = date(scoringDay, hour: 14)
        let nap = SleepSummary(
            duration: 3_600,
            stageSnapshot: SleepStageSnapshot(
                date: scoringDay,
                segments: [
                    SleepStageSegment(
                        stage: .core,
                        startDate: napEnd.addingTimeInterval(-3_600),
                        endDate: napEnd
                    )
                ]
            ),
            vitals: SleepVitalsSummary(heartRate: 70, respiratoryRate: 16)
        )

        let tonight = night(on: scoringDay, history: history, currentDaySleep: nap)

        XCTAssertEqual(tonight.state, .missingSleep)
        XCTAssertTrue(tonight.signals.isEmpty)
    }

    func testLegacyInactivityCannotContributeEvidence() {
        let inactive = BodyRadarSignal(kind: .inactiveTime, deviation: 3, flagged: true)
        XCTAssertEqual(BodyRadarCalculator.contribution(of: inactive), 0)
        XCTAssertFalse(BodyRadarSignalKind.scoringKinds.contains(.inactiveTime))
    }

    // MARK: - Freezing

    func testOneCurrentSignalIsInsufficientDespiteCalibratedHistory() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay, respiratoryRate: nil, temperature: nil, heartRateVariability: nil))

        let result = night(on: scoringDay, history: history)
        XCTAssertEqual(result.state, .insufficientData)
        XCTAssertFalse(result.state.isScored)
        XCTAssertEqual(result.evidence, 0)
    }

    func testEachSignalNeedsRecentHistoryInsteadOfPooledCoverage() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(20...39))
        // HR and HRV each have only four recent observations, even though the
        // union has eight nights. Neither channel is ready to score.
        for offset in 1...8 {
            history.append(vitalsNight(
                on: offsetDay(scoringDay, -offset),
                heartRate: offset.isMultiple(of: 2) ? 55 : nil,
                respiratoryRate: nil,
                temperature: nil,
                heartRateVariability: offset.isMultiple(of: 2) ? nil : 60
            ))
        }
        history.append(vitalsNight(on: scoringDay))
        XCTAssertEqual(night(on: scoringDay, history: history).state, .calibrating)
    }

    func testTwoRecentChannelsCanScoreWithoutOtherSensors() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20), respiratoryRate: nil, temperature: nil)
        history.append(vitalsNight(on: scoringDay, respiratoryRate: nil, temperature: nil))
        let result = night(on: scoringDay, history: history)
        XCTAssertEqual(result.state, .noSigns)
        XCTAssertEqual(result.signals.map(\.kind), [.sleepingHeartRate, .heartRateVariability])
    }

    func testNonFiniteCurrentSignalsDoNotCreateReassuringVerdict() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay, respiratoryRate: .nan, temperature: .infinity, heartRateVariability: nil))
        XCTAssertEqual(night(on: scoringDay, history: history).state, .insufficientData)
    }

    func testCombinedMinorChangesAreNotDescribedAsAllTypical() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        // All four at 0.9 typical bands: evidence 1.8, no individual flags.
        history.append(vitalsNight(on: scoringDay, heartRate: 60.4, respiratoryRate: 15.08,
                                   temperature: 36.36, heartRateVariability: 51))
        let result = night(on: scoringDay, history: history)
        XCTAssertEqual(result.state, .minorSigns)
        XCTAssertTrue(result.flaggedSignals.isEmpty)
        XCTAssertNotEqual(result.unflaggedExplanation,
                          BodyRadarNight(date: scoringDay, state: .noSigns).unflaggedExplanation)
    }

    func testUnavailableCurrentNightDoesNotShowYesterdaysVerdict() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay, respiratoryRate: nil, temperature: nil, heartRateVariability: nil))
        let result = summary(history: history, recorded: [scoredNight(on: offsetDay(scoringDay, -1))],
                             today: scoringDay, now: date(scoringDay, hour: 12), wakeTime: nil)
        XCTAssertEqual(result.summary.latest?.date, scoringDay)
        XCTAssertEqual(result.summary.state, .insufficientData)
        XCTAssertEqual(result.summary.recentNights.last?.state, .insufficientData)
        XCTAssertFalse(result.recorded.contains { $0.date == scoringDay })
    }

    func testAllUnscoredStatesRemainRetryableAfterWake() {
        let scoringDay = day(2026, 9, 4)
        for state in BodyRadarState.allCases where !state.isScored {
            let first = BodyRadarCalculator.freezing(
                records: [], night: BodyRadarNight(date: scoringDay, state: state),
                now: date(scoringDay, hour: 12), wakeTime: nil, scoringDay: scoringDay, calendar: calendar
            )
            XCTAssertTrue(first.isEmpty)
            let retry = BodyRadarCalculator.freezing(
                records: first, night: scoredNight(on: scoringDay),
                now: date(scoringDay, hour: 13), wakeTime: nil, scoringDay: scoringDay, calendar: calendar
            )
            XCTAssertEqual(retry.count, 1)
            XCTAssertEqual(retry.first?.state, .minorSigns)
        }
    }

    func testLateVitalsFillAnInsufficientNightThenRemainFrozen() {
        let scoringDay = day(2026, 9, 4)
        let baseline = flatHistory(before: scoringDay, offsets: Array(1...20))
        let sparse = baseline + [vitalsNight(on: scoringDay, respiratoryRate: nil,
                                             temperature: nil, heartRateVariability: nil)]
        let initial = summary(history: sparse, recorded: [], today: scoringDay,
                              now: date(scoringDay, hour: 8), wakeTime: date(scoringDay, hour: 7))
        XCTAssertEqual(initial.summary.state, .insufficientData)

        // Temperature plus a breathing change, so Beta 3's same-night
        // corroboration lets the filled night alert.
        let hydrated = baseline + [vitalsNight(on: scoringDay, respiratoryRate: 15.08, temperature: 36.6)]
        let filled = summary(history: hydrated, recorded: initial.recorded, today: scoringDay,
                             now: date(scoringDay, hour: 9), wakeTime: date(scoringDay, hour: 7))
        XCTAssertEqual(filled.summary.state, .minorSigns)
        let later = summary(history: baseline + [vitalsNight(on: scoringDay)], recorded: filled.recorded,
                            today: scoringDay, now: date(scoringDay, hour: 12), wakeTime: date(scoringDay, hour: 7))
        XCTAssertEqual(later.summary.latest, filled.summary.latest)
    }

    /// Beta 3 counts a lower respiratory rate (it scored nothing under Beta 2);
    /// a higher HRV still counts nothing, and removing sensors never amplifies.
    func testBeta3CountsLowerRespirationKeepsOtherDirectionsAndDoesNotAmplifyMissingSensors() {
        let scoringDay = day(2026, 9, 4)
        let baseline = flatHistory(before: scoringDay, offsets: Array(1...20))
        let full = night(on: scoringDay, history: baseline + [vitalsNight(
            on: scoringDay, heartRate: 63, respiratoryRate: 15.5, temperature: 36.6, heartRateVariability: 45
        )])
        let reduced = night(on: scoringDay, history: baseline + [vitalsNight(
            on: scoringDay, heartRate: 63, respiratoryRate: nil, temperature: nil, heartRateVariability: 45
        )])
        XCTAssertLessThan(reduced.evidence, full.evidence)
        let lowerRespiration = night(on: scoringDay, history: baseline + [vitalsNight(
            on: scoringDay, respiratoryRate: 11, heartRateVariability: 90
        )])
        // Respiration at -2.5 bands contributes 2.0; the HRV rise adds nothing.
        XCTAssertEqual(lowerRespiration.evidence, 2.0, accuracy: 0.001)
        XCTAssertEqual(signal(.heartRateVariability, in: lowerRespiration)?.flagged, false)
        // One family with a flat previous night is held.
        XCTAssertEqual(lowerRespiration.state, .noSigns)
        XCTAssertEqual(lowerRespiration.corroboration, BodyRadarCorroboration.none)
    }

    func testColdCacheDiscardsLegacyRadarWithoutDiscardingSleep() throws {
        var snapshot = HealthSummarySnapshot.empty
        snapshot.sleep = SleepSummary(duration: 8 * 3_600)
        var legacy = scoredNight(on: day(2026, 9, 4))
        legacy.algorithmVersion = nil
        snapshot.bodyRadar = BodyRadarSummary(latest: legacy, recentNights: [legacy])
        let decoded = try JSONDecoder().decode(HealthSummarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertNil(decoded.bodyRadar)
        XCTAssertEqual(decoded.sleep.duration, snapshot.sleep.duration)
    }

    func testLegacyRecordsDecodeButAreRecomputedUnderBeta2() throws {
        let scoringDay = day(2026, 9, 4)
        let data = try JSONEncoder().encode(scoredNight(on: scoringDay))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "algorithmVersion")
        let legacy = try JSONDecoder().decode(BodyRadarNight.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.algorithmVersion)
        XCTAssertFalse(legacy.isCurrentAlgorithm)

        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay))
        let result = summary(history: history, recorded: [legacy], today: scoringDay,
                             now: date(scoringDay, hour: 12), wakeTime: nil)
        XCTAssertEqual(result.summary.state, .noSigns)
        XCTAssertTrue(result.recorded.allSatisfy(\.isCurrentAlgorithm))
    }

    func testLegacyUnscoredRecordCannotBlockLateVitals() {
        let scoringDay = day(2026, 9, 4)
        let result = BodyRadarCalculator.freezing(
            records: [BodyRadarNight(date: scoringDay, state: .calibrating)],
            night: scoredNight(on: scoringDay), now: date(scoringDay, hour: 12),
            wakeTime: nil, scoringDay: scoringDay, calendar: calendar
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.state, .minorSigns)
    }

    private func scoredNight(on day: Date, evidence: Double = 1.0) -> BodyRadarNight {
        BodyRadarNight(date: day, state: .minorSigns, evidence: evidence, signals: [])
    }

    func testFreezeIsSkippedBeforeTheWakeWindowOpens() {
        let scoringDay = day(2026, 9, 4)
        let wake = date(scoringDay, hour: 7)

        let records = BodyRadarCalculator.freezing(
            records: [],
            night: scoredNight(on: scoringDay),
            now: wake.addingTimeInterval(300),
            wakeTime: wake,
            scoringDay: scoringDay,
            calendar: calendar
        )

        XCTAssertTrue(records.isEmpty)
    }

    func testFreezeCapturesTheNightOnceTheWindowOpens() {
        let scoringDay = day(2026, 9, 4)
        let wake = date(scoringDay, hour: 7)

        let records = BodyRadarCalculator.freezing(
            records: [],
            night: scoredNight(on: scoringDay, evidence: 1.2),
            now: wake.addingTimeInterval(700),
            wakeTime: wake,
            scoringDay: scoringDay,
            calendar: calendar
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].date, scoringDay)
        XCTAssertEqual(records[0].evidence, 1.2, accuracy: 0.001)
    }

    func testFreezeFallsBackToTenLocalWithoutAWakeTime() {
        let scoringDay = day(2026, 9, 4)

        let early = BodyRadarCalculator.freezing(
            records: [],
            night: scoredNight(on: scoringDay),
            now: date(scoringDay, hour: 9, minute: 30),
            wakeTime: nil,
            scoringDay: scoringDay,
            calendar: calendar
        )
        let later = BodyRadarCalculator.freezing(
            records: [],
            night: scoredNight(on: scoringDay),
            now: date(scoringDay, hour: 10, minute: 5),
            wakeTime: nil,
            scoringDay: scoringDay,
            calendar: calendar
        )

        XCTAssertTrue(early.isEmpty)
        XCTAssertEqual(later.count, 1)
    }

    func testALaterRefreshKeepsTheFrozenNight() {
        let scoringDay = day(2026, 9, 4)
        let wake = date(scoringDay, hour: 7)
        let frozen = BodyRadarCalculator.freezing(
            records: [],
            night: scoredNight(on: scoringDay, evidence: 1.2),
            now: wake.addingTimeInterval(700),
            wakeTime: wake,
            scoringDay: scoringDay,
            calendar: calendar
        )

        let refreshed = BodyRadarCalculator.freezing(
            records: frozen,
            night: BodyRadarNight(date: scoringDay, state: .majorSigns, evidence: 4.0, signals: []),
            now: date(scoringDay, hour: 20),
            wakeTime: wake,
            scoringDay: scoringDay,
            calendar: calendar
        )

        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(refreshed[0].state, .minorSigns)
        XCTAssertEqual(refreshed[0].evidence, 1.2, accuracy: 0.001)
    }

    func testTheNextDayFreezesItsOwnNight() {
        let scoringDay = day(2026, 9, 4)
        let nextDay = offsetDay(scoringDay, 1)
        let wake = date(nextDay, hour: 7)

        let records = BodyRadarCalculator.freezing(
            records: [scoredNight(on: scoringDay)],
            night: BodyRadarNight(date: nextDay, state: .noSigns, evidence: 0.1, signals: []),
            now: wake.addingTimeInterval(700),
            wakeTime: wake,
            scoringDay: nextDay,
            calendar: calendar
        )

        XCTAssertEqual(records.map(\.date), [scoringDay, nextDay])
        XCTAssertEqual(records[1].state, .noSigns)
    }

    func testMissingSleepIsNeverFrozen() {
        let scoringDay = day(2026, 9, 4)
        let wake = date(scoringDay, hour: 7)

        let records = BodyRadarCalculator.freezing(
            records: [],
            night: BodyRadarNight(date: scoringDay, state: .missingSleep),
            now: wake.addingTimeInterval(700),
            wakeTime: wake,
            scoringDay: scoringDay,
            calendar: calendar
        )

        XCTAssertTrue(records.isEmpty)
    }

    func testRecordsAreSortedAndCappedAtSixtyNights() {
        let scoringDay = day(2026, 9, 4)
        let existing = (1...60).map { scoredNight(on: offsetDay(scoringDay, -$0)) }.shuffled()
        let wake = date(scoringDay, hour: 7)

        let records = BodyRadarCalculator.freezing(
            records: existing,
            night: scoredNight(on: scoringDay),
            now: wake.addingTimeInterval(700),
            wakeTime: wake,
            scoringDay: scoringDay,
            calendar: calendar
        )

        XCTAssertEqual(records.count, 60)
        XCTAssertEqual(records.last?.date, scoringDay)
        XCTAssertEqual(records.first?.date, offsetDay(scoringDay, -59))
        XCTAssertEqual(records.map(\.date), records.map(\.date).sorted())
    }

    // MARK: - Summary

    private func summary(
        history: [SleepDaySummary],
        recorded: [BodyRadarNight],
        today: Date,
        now: Date,
        wakeTime: Date?
    ) -> (summary: BodyRadarSummary, recorded: [BodyRadarNight]) {
        BodyRadarCalculator.summary(
            sleepHistory: SleepHistorySnapshot(days: history),
            currentDaySleep: nil,
            recorded: recorded,
            today: today,
            now: now,
            wakeTime: wakeTime,
            calendar: calendar
        )
    }

    func testSummaryShowsYesterdaysRecordBeforeTheFreezeMoment() {
        let scoringDay = day(2026, 9, 4)
        let yesterday = offsetDay(scoringDay, -1)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay, temperature: 36.0 + 0.6))

        let result = summary(
            history: history,
            recorded: [BodyRadarNight(date: yesterday, state: .noSigns, evidence: 0.2, signals: [])],
            today: scoringDay,
            now: date(scoringDay, hour: 6),
            wakeTime: date(scoringDay, hour: 7)
        )

        XCTAssertEqual(result.summary.latest?.date, yesterday)
        XCTAssertEqual(result.summary.state, .noSigns)
        // Today is not frozen yet; scored earlier nights are recorded for reuse.
        XCTAssertTrue(result.recorded.contains { $0.date == yesterday && $0.state == .noSigns })
    }

    func testSummaryFreezesTodayInsideTheWindow() {
        let scoringDay = day(2026, 9, 4)
        // Deep enough that every one of the thirteen preceding nights has its
        // own 14-night baseline and can be recomputed for the preview chart.
        var history = flatHistory(before: scoringDay, offsets: Array(1...40))
        // Temperature plus a breathing change: two families, so Beta 3 alerts.
        history.append(vitalsNight(on: scoringDay, respiratoryRate: 15.08, temperature: 36.0 + 0.6))

        let result = summary(
            history: history,
            recorded: [],
            today: scoringDay,
            now: date(scoringDay, hour: 8),
            wakeTime: date(scoringDay, hour: 7)
        )

        XCTAssertEqual(result.summary.latest?.date, scoringDay)
        XCTAssertEqual(result.summary.latest?.state, .minorSigns)
        // Today comes from the frozen record; the twenty days before it are
        // recomputed from the sleep cache, and the scored ones are recorded so
        // the next refresh reads them back instead of scoring them again.
        XCTAssertEqual(result.summary.recentNights.count, 21)
        XCTAssertEqual(result.summary.evidenceSeries().points.count, 21)
        XCTAssertEqual(result.recorded.count, 21)
        XCTAssertEqual(result.recorded.last?.date, scoringDay)
        XCTAssertEqual(result.recorded.map(\.date), result.summary.recentNights.map(\.date))

        // Feeding the records back yields the same summary with nothing new recorded.
        let replay = summary(
            history: history,
            recorded: result.recorded,
            today: scoringDay,
            now: date(scoringDay, hour: 9),
            wakeTime: date(scoringDay, hour: 7)
        )
        XCTAssertEqual(replay.recorded, result.recorded)
        XCTAssertEqual(replay.summary, result.summary)
    }

    func testSummaryWithoutAnyRecordFallsBackToACalibratingPlaceholder() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay))

        let result = summary(
            history: history,
            recorded: [],
            today: scoringDay,
            now: date(scoringDay, hour: 6),
            wakeTime: date(scoringDay, hour: 7)
        )

        XCTAssertEqual(result.summary.latest?.state, .calibrating)
        XCTAssertEqual(result.summary.latest?.date, scoringDay)
        XCTAssertFalse(result.recorded.contains { $0.state == .calibrating })
    }

    func testDroppedRecordsRefreezeTheDay() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay, temperature: 36.0 + 0.6))

        // A changed input context leaves the caller passing an empty array; the
        // day is then frozen again from the current inputs.
        let result = summary(
            history: history,
            recorded: [],
            today: scoringDay,
            now: date(scoringDay, hour: 12),
            wakeTime: date(scoringDay, hour: 7)
        )

        // Earlier scored nights are backfilled into the records alongside today.
        XCTAssertEqual(result.recorded.last?.date, scoringDay)
    }

    func testSummaryWithNoSleepAtAllReportsMissingSleep() {
        let scoringDay = day(2026, 9, 4)
        let history = flatHistory(before: scoringDay, offsets: Array(1...20))

        let result = summary(
            history: history,
            recorded: [],
            today: scoringDay,
            now: date(scoringDay, hour: 12),
            wakeTime: nil
        )

        XCTAssertEqual(result.summary.latest?.state, .missingSleep)
        XCTAssertFalse(result.recorded.contains { $0.date == scoringDay })
    }

    func testFreezeAndBackfillStampCaptureMetadata() {
        let scoringDay = day(2026, 9, 4)
        var history = flatHistory(before: scoringDay, offsets: Array(1...40))
        history.append(vitalsNight(on: scoringDay, respiratoryRate: 15.08, temperature: 36.0 + 0.6))
        let now = date(scoringDay, hour: 8)

        let result = summary(history: history, recorded: [], today: scoringDay,
                             now: now, wakeTime: date(scoringDay, hour: 7))

        let today = result.recorded.first { $0.date == scoringDay }
        XCTAssertEqual(today?.capture, .freeze)
        XCTAssertEqual(today?.capturedAt, now)
        let backfilled = result.recorded.filter { $0.date < scoringDay }
        XCTAssertEqual(backfilled.count, 20)
        XCTAssertTrue(backfilled.allSatisfy { $0.capture == .backfill && $0.capturedAt == now })
        XCTAssertTrue(result.recorded.allSatisfy { $0.corroboration != nil })

        // A live night carries no capture metadata.
        let live = night(on: scoringDay, history: history)
        XCTAssertNil(live.capture)
        XCTAssertNil(live.capturedAt)
    }

    // MARK: - Codable

    func testVersion2PayloadDecodesAndIsDroppedAndRecomputed() throws {
        let scoringDay = day(2026, 9, 4)
        // Exactly what a Beta 2 build wrote: no corroboration or capture keys.
        let json = """
        {"date": \(scoringDay.timeIntervalSinceReferenceDate), "state": "minorSigns", "evidence": 1.5,
         "signals": [{"kind": "wristTemperature", "deviation": 1.5, "flagged": true}], "algorithmVersion": 2}
        """
        let legacy = try JSONDecoder().decode(BodyRadarNight.self, from: Data(json.utf8))
        XCTAssertEqual(legacy.algorithmVersion, 2)
        XCTAssertFalse(legacy.isCurrentAlgorithm)
        XCTAssertNil(legacy.corroboration)
        XCTAssertNil(legacy.capturedAt)
        XCTAssertNil(legacy.capture)
        XCTAssertEqual(legacy.signals.first?.deviation, 1.5)

        let frozen = BodyRadarCalculator.freezing(
            records: [legacy], night: scoredNight(on: scoringDay), now: date(scoringDay, hour: 12),
            wakeTime: nil, scoringDay: scoringDay, calendar: calendar
        )
        XCTAssertEqual(frozen.count, 1)
        XCTAssertTrue(frozen[0].isCurrentAlgorithm)
        XCTAssertEqual(frozen[0].capture, .freeze)

        var history = flatHistory(before: scoringDay, offsets: Array(1...20))
        history.append(vitalsNight(on: scoringDay))
        let result = summary(history: history, recorded: [legacy], today: scoringDay,
                             now: date(scoringDay, hour: 12), wakeTime: nil)
        XCTAssertEqual(result.summary.state, .noSigns)
        XCTAssertEqual(result.summary.latest?.algorithmVersion, BodyRadarCalculator.algorithmVersion)
        XCTAssertFalse(result.recorded.contains { $0.algorithmVersion == 2 })
    }

    func testColdCacheDiscardsVersion2Radar() throws {
        var snapshot = HealthSummarySnapshot.empty
        snapshot.sleep = SleepSummary(duration: 8 * 3_600)
        var version2 = scoredNight(on: day(2026, 9, 4))
        version2.algorithmVersion = 2
        snapshot.bodyRadar = BodyRadarSummary(latest: version2, recentNights: [version2])
        let decoded = try JSONDecoder().decode(HealthSummarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertNil(decoded.bodyRadar)
        XCTAssertEqual(decoded.sleep.duration, snapshot.sleep.duration)
    }

    func testNightRoundTripsWithCorroborationAndCaptureMetadata() throws {
        let scoringDay = day(2026, 9, 4)
        var night = BodyRadarNight(
            date: scoringDay,
            state: .minorSigns,
            evidence: 1.5,
            signals: [BodyRadarSignal(kind: .respiratoryRate, deviation: -2.0, flagged: true)],
            corroboration: .persistence
        )
        night.capturedAt = date(scoringDay, hour: 8, minute: 10)
        night.capture = .freeze

        let decoded = try JSONDecoder().decode(BodyRadarNight.self, from: JSONEncoder().encode(night))

        XCTAssertEqual(decoded, night)
        XCTAssertEqual(decoded.corroboration, .persistence)
        XCTAssertEqual(decoded.capture, .freeze)
        XCTAssertEqual(decoded.capturedAt, night.capturedAt)
    }

    // MARK: - Codable

    func testSummaryRoundTripsThroughCodable() throws {
        let scoringDay = day(2026, 9, 4)
        let night = BodyRadarNight(
            date: scoringDay,
            state: .majorSigns,
            evidence: 3.25,
            signals: [
                BodyRadarSignal(kind: .wristTemperature, deviation: 1.5, flagged: true),
                BodyRadarSignal(kind: .heartRateVariability, deviation: -1.5, flagged: true)
            ]
        )
        let summary = BodyRadarSummary(latest: night, recentNights: [night])

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(BodyRadarSummary.self, from: data)

        XCTAssertEqual(decoded, summary)
        XCTAssertEqual(decoded.state, .majorSigns)
    }

    func testEmptySummaryCalibrates() {
        XCTAssertEqual(BodyRadarSummary.empty.state, .calibrating)
        XCTAssertTrue(BodyRadarSummary.empty.evidenceSeries().points.isEmpty)
    }
}
