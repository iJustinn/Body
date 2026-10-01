//
//  BodyRadarReplayTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class BodyRadarReplayTests: XCTestCase {
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
    private func flatHistory(before scoringDay: Date, offsets: [Int]) -> [SleepDaySummary] {
        offsets.map { vitalsNight(on: offsetDay(scoringDay, -$0)) }
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

    private func replay(
        history: [SleepDaySummary],
        today: Date,
        rules: BodyRadarRules = .beta3,
        recorded: [BodyRadarNight] = [],
        calendar: Calendar? = nil
    ) -> BodyRadarReplayExport {
        BodyRadarCalculator.replay(
            sleepHistory: SleepHistorySnapshot(days: history),
            currentDaySleep: nil,
            recorded: recorded,
            today: today,
            rules: rules,
            calendar: calendar ?? self.calendar
        )
    }

    private func row(on day: Date, in export: BodyRadarReplayExport) throws -> BodyRadarReplayNight {
        try XCTUnwrap(export.recomputed.first { $0.dayEpoch == Int(day.timeIntervalSince1970) })
    }

    private func signal(_ kind: BodyRadarSignalKind, in row: BodyRadarReplayNight) throws -> BodyRadarReplaySignal {
        try XCTUnwrap(row.signals.first { $0.kind == kind })
    }

    private func jsonText(_ export: BodyRadarReplayExport) throws -> String {
        let data = try BodyRadarReplayExport.makeEncoder().encode(export)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Nine weeks of varied nights with elevated, held, missing, nap and
    /// sparse days mixed in, ending on `today`.
    private func mixedHistory(endingOn today: Date) -> [SleepDaySummary] {
        var history: [SleepDaySummary] = []
        for offset in 3...62 where ![5, 17, 18].contains(offset) {
            history.append(
                vitalsNight(
                    on: offsetDay(today, -offset),
                    heartRate: 55 + Double(offset % 3) - 1,
                    respiratoryRate: offset > 40 ? nil : 14 + Double(offset % 2) * 0.2,
                    temperature: 36.0 + Double(offset % 4) * 0.05,
                    heartRateVariability: 60 + Double(offset % 5) * 4 - 8
                )
            )
        }
        // A nap on an otherwise missing day.
        let napDay = offsetDay(today, -5)
        history.append(
            SleepDaySummary(
                date: napDay,
                summary: SleepSummary(
                    duration: 3_600,
                    stageSnapshot: nightStages(on: napDay, asleepHours: 1),
                    vitals: SleepVitalsSummary(
                        heartRate: 70,
                        heartRateVariability: 30,
                        respiratoryRate: 14,
                        oxygenSaturation: nil,
                        wristTemperatureCelsius: 36.0
                    )
                )
            )
        )
        // Elevated two nights running, then a held single-family night.
        history.append(vitalsNight(on: offsetDay(today, -2), heartRate: 64, heartRateVariability: 45))
        history.append(vitalsNight(on: offsetDay(today, -1), heartRate: 73, heartRateVariability: 30))
        history.append(
            vitalsNight(
                on: today,
                heartRate: 55,
                respiratoryRate: 14 - 1.8,
                temperature: 36.3,
                stages: nightStages(on: today)
            )
        )
        return history
    }

    // MARK: - Schema

    func testExportRoundTripsThroughTheFileContract() throws {
        let today = day(2026, 9, 4)
        let recorded = [
            BodyRadarNight(date: offsetDay(today, -1), state: .minorSigns, evidence: 1.2)
        ]
        let export = replay(history: mixedHistory(endingOn: today), today: today, recorded: recorded)
        XCTAssertEqual(export.schemaVersion, BodyRadarReplayExport.schemaVersion)
        XCTAssertEqual(BodyRadarReplayExport.schemaVersion, 1)

        let data = try BodyRadarReplayExport.makeEncoder().encode(export)
        let decoded = try decoder().decode(BodyRadarReplayExport.self, from: data)
        let reencoded = try BodyRadarReplayExport.makeEncoder().encode(decoded)

        XCTAssertEqual(reencoded, data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.recomputed.map(\.day), export.recomputed.map(\.day))
        XCTAssertEqual(decoded.recomputed.map(\.state), export.recomputed.map(\.state))
        XCTAssertEqual(decoded.recorded, recorded)
        // A staged night carries its sleep interval and wake boundary.
        let tonight = try row(on: today, in: decoded)
        XCTAssertTrue(tonight.hasStages)
        XCTAssertEqual(tonight.sleepStart, date(today, hour: 7).addingTimeInterval(-8 * 3_600))
        XCTAssertEqual(tonight.sleepEnd, date(today, hour: 7))
        XCTAssertEqual(tonight.wakeCycleEnd, date(today, hour: 7))
        XCTAssertEqual(tonight.sleepDuration, 8 * 3_600)
        XCTAssertEqual(tonight.signals.map(\.kind), BodyRadarSignalKind.scoringKinds)
    }

    func testUnknownFieldsEncodeAsLiteralNull() throws {
        let today = day(2026, 9, 4)
        var history = flatHistory(before: today, offsets: Array(1...20))
        history.append(vitalsNight(on: today))
        let export = replay(history: history, today: today)

        let text = try jsonText(export)
        for key in ["sampleCounts", "queryCompletion", "sourceIdentity", "historicalTimeZone"] {
            XCTAssertEqual(
                text.components(separatedBy: "\"\(key)\" : null").count - 1,
                export.recomputed.count,
                key
            )
        }
        // Meta fields the calculator cannot know stay in the file as null.
        for key in ["appVersion", "build", "recordContextSignature", "configuredSourceSelection"] {
            XCTAssertTrue(text.contains("\"\(key)\" : null"), key)
        }
        // A scored signal writes its null reasons, an unscored night its null evidence.
        XCTAssertTrue(text.contains("\"exclusionReason\" : null"))
        XCTAssertTrue(text.contains("\"valueReason\" : null"))
        XCTAssertTrue(text.contains("\"rawEvidence\" : null"))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let nights = try XCTUnwrap(object["recomputed"] as? [[String: Any]])
        for night in nights {
            XCTAssertTrue(night["sampleCounts"] is NSNull)
            XCTAssertTrue(night["sourceIdentity"] is NSNull)
        }
    }

    func testNonFiniteCurrentValueIsExportedAsNullWithAReason() throws {
        let today = day(2026, 9, 4)
        var history = flatHistory(before: today, offsets: Array(1...20))
        history.append(vitalsNight(on: today, heartRate: .nan, temperature: .infinity))
        let export = replay(history: history, today: today)

        let tonight = try row(on: today, in: export)
        for kind in [BodyRadarSignalKind.sleepingHeartRate, .wristTemperature] {
            let replayed = try signal(kind, in: tonight)
            XCTAssertNil(replayed.value, kind.rawValue)
            XCTAssertEqual(replayed.valueReason, "nonFinite", kind.rawValue)
            XCTAssertEqual(replayed.exclusionReason, "nonFinite", kind.rawValue)
            XCTAssertNil(replayed.contribution, kind.rawValue)
        }
        // The finite signals are still scored, as production scores them.
        XCTAssertNil(try signal(.respiratoryRate, in: tonight).exclusionReason)
        XCTAssertEqual(try signal(.respiratoryRate, in: tonight).value, 14)
        let production = BodyRadarCalculator.night(
            on: today,
            sleepHistory: SleepHistorySnapshot(days: history),
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(tonight.state, production.state)
        XCTAssertEqual(production.signals.map(\.kind), [.respiratoryRate, .heartRateVariability])

        // Even a non-finite number that reaches a row never reaches the encoder.
        var poisoned = export
        poisoned.recomputed[0].rawEvidence = .nan
        poisoned.recomputed[0].signals[0].value = .infinity
        XCTAssertNoThrow(try BodyRadarReplayExport.makeEncoder().encode(poisoned))
        let text = try jsonText(export)
        XCTAssertTrue(text.contains("\"valueReason\" : \"nonFinite\""))
    }

    func testMissingValueAndAbsentBaselineReportTheirReasons() throws {
        let today = day(2026, 9, 4)
        var history = flatHistory(before: today, offsets: Array(1...20))
        // Temperature only for the last ten nights: a baseline too short to use.
        history = history.map { night in
            var night = night
            if night.date < offsetDay(today, -10) {
                night.summary.vitals.wristTemperatureCelsius = nil
            }
            return night
        }
        history.append(vitalsNight(on: today, respiratoryRate: nil))
        let tonight = try row(on: today, in: replay(history: history, today: today))

        let respiration = try signal(.respiratoryRate, in: tonight)
        XCTAssertEqual(respiration.valueReason, "absent")
        XCTAssertEqual(respiration.exclusionReason, "noCurrentValue")
        XCTAssertEqual(respiration.baselineCount, 20)

        let temperature = try signal(.wristTemperature, in: tonight)
        XCTAssertEqual(temperature.exclusionReason, "noBaseline")
        XCTAssertEqual(temperature.baselineCount, 10)
        XCTAssertNil(temperature.baselineMedian)
        XCTAssertNil(temperature.rawSpread)
        XCTAssertEqual(temperature.recentCount, 11)
    }

    // MARK: - Parity

    func testBeta3RecomputedMatchesProductionForEveryDay() throws {
        let today = day(2026, 9, 4)
        let history = mixedHistory(endingOn: today)
        let export = replay(history: history, today: today)

        let expectedDays = Set(
            history
                .filter { $0.summary.duration ?? 0 >= 3 * 3_600 }
                .map { calendar.startOfDay(for: $0.date) }
        ).union([today])
        XCTAssertEqual(Set(export.recomputed.map { Date(timeIntervalSince1970: TimeInterval($0.dayEpoch)) }), expectedDays)
        XCTAssertEqual(export.recomputed.map(\.dayEpoch), export.recomputed.map(\.dayEpoch).sorted())

        var statesSeen: Set<BodyRadarState> = []
        var floorBindings: Set<Bool> = []
        for replayed in export.recomputed {
            let day = Date(timeIntervalSince1970: TimeInterval(replayed.dayEpoch))
            let production = BodyRadarCalculator.night(
                on: day,
                sleepHistory: SleepHistorySnapshot(days: history),
                currentDaySleep: nil,
                today: today,
                calendar: calendar
            )
            XCTAssertEqual(replayed.rulesVersion, 3)
            XCTAssertEqual(replayed.state, production.state, replayed.day)
            XCTAssertEqual(replayed.corroboration, production.corroboration, replayed.day)
            statesSeen.insert(replayed.state)
            guard production.state.isScored else {
                XCTAssertEqual(replayed.rawState, production.state, replayed.day)
                XCTAssertNil(replayed.rawEvidence, replayed.day)
                continue
            }
            XCTAssertEqual(try XCTUnwrap(replayed.rawEvidence), production.evidence, replayed.day)
            XCTAssertEqual(replayed.flaggedCount, production.flaggedSignals.count, replayed.day)

            let scored = replayed.signals.filter { $0.exclusionReason == nil }
            XCTAssertEqual(scored.map(\.kind), production.signals.map(\.kind), replayed.day)
            for (replayedSignal, productionSignal) in zip(scored, production.signals) {
                XCTAssertEqual(replayedSignal.deviation, productionSignal.deviation, replayed.day)
                XCTAssertEqual(replayedSignal.flagged, productionSignal.flagged, replayed.day)
                XCTAssertEqual(
                    replayedSignal.contribution,
                    BodyRadarCalculator.contribution(of: productionSignal),
                    replayed.day
                )
                // The window the replay reports is the one production read.
                let rawSpread = try XCTUnwrap(replayedSignal.rawSpread)
                let spread = try XCTUnwrap(replayedSignal.baselineSpread)
                XCTAssertEqual(max(rawSpread, replayedSignal.floor), spread, accuracy: 1e-12, replayed.day)
                XCTAssertEqual(replayedSignal.floorBound, rawSpread < replayedSignal.floor)
                XCTAssertGreaterThanOrEqual(replayedSignal.baselineCount, 14)
                XCTAssertGreaterThanOrEqual(replayedSignal.recentCount, 7)
                floorBindings.insert(rawSpread < replayedSignal.floor)
            }
        }
        // The fixture exercises the gate and both sides of the floor.
        XCTAssertTrue(statesSeen.isSuperset(of: [.calibrating, .noSigns, .minorSigns, .majorSigns]))
        XCTAssertEqual(floorBindings, [true, false])
        // Only nights are rows: the nap day and the days without sleep are not.
        XCTAssertNil(export.recomputed.first { $0.dayEpoch == Int(offsetDay(today, -5).timeIntervalSince1970) })
        XCTAssertNil(export.recomputed.first { $0.dayEpoch == Int(offsetDay(today, -17).timeIntervalSince1970) })
    }

    func testTodayWithoutANightIsReportedWithoutItsReadings() throws {
        let today = day(2026, 9, 4)
        var history = flatHistory(before: today, offsets: Array(1...20))
        // A one hour nap is the only sleep filed under today.
        history.append(
            SleepDaySummary(
                date: today,
                summary: SleepSummary(
                    duration: 3_600,
                    stageSnapshot: nightStages(on: today, asleepHours: 1),
                    vitals: SleepVitalsSummary(
                        heartRate: 70,
                        heartRateVariability: 30,
                        respiratoryRate: 14,
                        oxygenSaturation: nil,
                        wristTemperatureCelsius: 36.0
                    )
                )
            )
        )
        let export = replay(history: history, today: today)

        let tonight = try row(on: today, in: export)
        XCTAssertEqual(tonight.state, .missingSleep)
        XCTAssertNil(tonight.rawEvidence)
        XCTAssertTrue(tonight.hasStages)
        XCTAssertEqual(tonight.signals.count, BodyRadarSignalKind.scoringKinds.count)
        XCTAssertTrue(tonight.signals.allSatisfy { $0.value == nil && $0.valueReason == "notNight" })
        XCTAssertTrue(tonight.signals.allSatisfy { $0.exclusionReason == "notNight" })
    }

    func testBeta2RulesIgnoreALowerRespiratoryRate() throws {
        let today = day(2026, 9, 4)
        var history = flatHistory(before: today, offsets: Array(1...20))
        // Respiration -1.5 bands (1.0 under Beta 3) and temperature +0.75 bands (0.375).
        history.append(vitalsNight(on: today, respiratoryRate: 14 - 1.8, temperature: 36.3))

        let beta2 = try row(on: today, in: replay(history: history, today: today, rules: .beta2))
        XCTAssertEqual(beta2.rulesVersion, 2)
        XCTAssertEqual(beta2.state, .noSigns)
        XCTAssertEqual(beta2.rawState, .noSigns)
        XCTAssertNil(beta2.corroboration)
        XCTAssertEqual(try XCTUnwrap(beta2.rawEvidence), 0.375, accuracy: 0.001)
        let beta2Respiration = try signal(.respiratoryRate, in: beta2)
        XCTAssertEqual(try XCTUnwrap(beta2Respiration.directionalDeviation), -1.5, accuracy: 0.001)
        XCTAssertEqual(beta2Respiration.contribution, 0)
        XCTAssertEqual(beta2Respiration.flagged, false)

        let beta3 = try row(on: today, in: replay(history: history, today: today, rules: .beta3))
        XCTAssertEqual(beta3.state, .minorSigns)
        XCTAssertEqual(beta3.corroboration, .sameNight)
        XCTAssertEqual(try XCTUnwrap(beta3.rawEvidence), 1.375, accuracy: 0.001)
        let beta3Respiration = try signal(.respiratoryRate, in: beta3)
        XCTAssertEqual(try XCTUnwrap(beta3Respiration.directionalDeviation), 1.5, accuracy: 0.001)
        XCTAssertEqual(beta3Respiration.flagged, true)
        // The signed deviation is the same input under both rules.
        XCTAssertEqual(beta2Respiration.deviation, beta3Respiration.deviation)
    }

    func testBeta2RulesReportASingleFamilyMajorNight() throws {
        let today = day(2026, 9, 4)
        var history = flatHistory(before: today, offsets: Array(1...20))
        // Heart rate +3 bands and HRV -3 bands: 5.0 evidence from one family.
        history.append(vitalsNight(on: today, heartRate: 55 + 18, heartRateVariability: 60 - 30))

        let beta2 = try row(on: today, in: replay(history: history, today: today, rules: .beta2))
        XCTAssertEqual(beta2.state, .majorSigns)
        XCTAssertEqual(beta2.rawState, .majorSigns)
        XCTAssertEqual(beta2.flaggedCount, 2)
        XCTAssertEqual(try XCTUnwrap(beta2.rawEvidence), 5.0, accuracy: 0.001)

        let beta3 = try row(on: today, in: replay(history: history, today: today, rules: .beta3))
        XCTAssertEqual(beta3.rawState, .majorSigns)
        XCTAssertEqual(beta3.state, .noSigns)
        XCTAssertEqual(beta3.corroboration, BodyRadarCorroboration.none)
        XCTAssertEqual(try XCTUnwrap(beta3.rawEvidence), 5.0, accuracy: 0.001)
    }

    /// The Jun 26/27 fixture: Beta 2 reads the low breathing night as quiet,
    /// Beta 3 counts it and lets it support the high breathing night after it.
    func testBeta2AndBeta3DisagreeOnOppositeDirectionRespiration() throws {
        let today = day(2026, 6, 27)
        let yesterday = offsetDay(today, -1)
        var history = flatHistory(before: today, offsets: Array(2...21))
        history.append(vitalsNight(on: yesterday, respiratoryRate: 14 - 1.38, heartRateVariability: 60 - 6.1))
        history.append(vitalsNight(on: today, respiratoryRate: 14 + 2.4))

        let beta2 = replay(history: history, today: today, rules: .beta2)
        XCTAssertEqual(try XCTUnwrap(try row(on: yesterday, in: beta2).rawEvidence), 0.11, accuracy: 0.001)
        XCTAssertEqual(try row(on: yesterday, in: beta2).state, .noSigns)
        XCTAssertEqual(try row(on: today, in: beta2).state, .minorSigns)
        XCTAssertNil(try row(on: today, in: beta2).corroboration)

        let beta3 = replay(history: history, today: today, rules: .beta3)
        XCTAssertEqual(try XCTUnwrap(try row(on: yesterday, in: beta3).rawEvidence), 0.76, accuracy: 0.001)
        XCTAssertEqual(try row(on: yesterday, in: beta3).state, .noSigns)
        XCTAssertEqual(try row(on: today, in: beta3).state, .minorSigns)
        XCTAssertEqual(try row(on: today, in: beta3).corroboration, .persistence)
    }

    // MARK: - Recorded and meta

    func testRecordedNightsPassThroughWithoutMerging() throws {
        let today = day(2026, 9, 4)
        var history = flatHistory(before: today, offsets: Array(1...20))
        history.append(vitalsNight(on: today))

        var frozen = BodyRadarNight(date: today, state: .majorSigns, evidence: 4, corroboration: .sameNight)
        frozen.capturedAt = date(today, hour: 7, minute: 10)
        frozen.capture = .freeze
        var legacy = BodyRadarNight(date: offsetDay(today, -1), state: .minorSigns, evidence: 1)
        legacy.algorithmVersion = 2
        let recorded = [legacy, frozen]

        let export = replay(history: history, today: today, recorded: recorded)
        XCTAssertEqual(export.recorded, recorded)
        // The recomputed row keeps its own verdict, whatever was recorded.
        XCTAssertEqual(try row(on: today, in: export).state, .noSigns)

        let decoded = try decoder().decode(
            BodyRadarReplayExport.self,
            from: BodyRadarReplayExport.makeEncoder().encode(export)
        )
        XCTAssertEqual(decoded.recorded, recorded)
    }

    func testMetaReportsTheAlgorithmCalendarAndTimeZone() throws {
        let today = day(2026, 9, 4)
        let export = replay(history: flatHistory(before: today, offsets: Array(1...20)), today: today)

        XCTAssertEqual(export.meta.algorithmVersion, 3)
        XCTAssertEqual(export.meta.algorithmVersion, BodyRadarCalculator.algorithmVersion)
        XCTAssertEqual(export.meta.calendarIdentifier, "gregorian")
        XCTAssertEqual(export.meta.timeZoneIdentifier, "America/New_York")
        XCTAssertNil(export.meta.configuredSourceSelection)
        XCTAssertFalse(export.meta.notes.isEmpty)
        XCTAssertTrue(export.recomputed.allSatisfy { $0.rulesVersion == 3 })
        XCTAssertTrue(
            replay(history: flatHistory(before: today, offsets: Array(1...20)), today: today, rules: .beta2)
                .recomputed.allSatisfy { $0.rulesVersion == 2 }
        )
    }

    func testDayIsFormattedInTheExportCalendarTimeZone() throws {
        let today = day(2026, 9, 4)
        let export = replay(history: flatHistory(before: today, offsets: Array(1...20)), today: today)
        let tonight = try row(on: today, in: export)
        XCTAssertEqual(tonight.day, "2026-09-04")
        XCTAssertEqual(tonight.dayEpoch, 1_788_494_400) // 2026-09-04T04:00:00Z
        XCTAssertEqual(export.recomputed.first?.day, "2026-08-15")

        // East of UTC, the wake day's midnight falls on the previous UTC date.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        let tokyoDay = tokyo.date(from: DateComponents(year: 2026, month: 9, day: 4)) ?? Date()
        let tokyoHistory = (1...20).map { offset in
            vitalsNight(on: tokyo.date(byAdding: .day, value: -offset, to: tokyoDay) ?? tokyoDay)
        }
        let tokyoExport = replay(history: tokyoHistory, today: tokyoDay, calendar: tokyo)
        XCTAssertEqual(tokyoExport.meta.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(tokyoExport.recomputed.last?.day, "2026-09-04")
        XCTAssertEqual(tokyoExport.recomputed.last?.dayEpoch, Int(tokyoDay.timeIntervalSince1970))
    }
}
