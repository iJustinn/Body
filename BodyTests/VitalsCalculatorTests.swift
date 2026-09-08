//
//  VitalsCalculatorTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class VitalsCalculatorTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 17))!
    }

    // MARK: - Baselines

    func testBaselineMatchesReadinessRobustBaselineForTheSameSeries() throws {
        let history = sleepHistory(nightCount: 30, endingOn: today) { offset in
            SleepSummary(duration: nil, vitals: SleepVitalsSummary(heartRate: 52 + Double(offset % 5)))
        }

        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )

        let latest = try XCTUnwrap(snapshot.latestNight)
        let measurement = try XCTUnwrap(latest.measurements.first { $0.kind == .sleepingHeartRate })
        let expected = ReadinessScoreCalculator.robustBaseline(
            for: today,
            values: history.days.map {
                ReadinessScoreCalculator.DailyValue(
                    date: calendar.startOfDay(for: $0.date),
                    value: $0.summary.vitals.heartRate!
                )
            },
            floor: VitalsCalculator.Floor.heartRate,
            calendar: calendar
        )

        XCTAssertEqual(measurement.baseline, expected)
    }

    func testVitalIsSkippedUntilFourteenPriorNightsExist() throws {
        let shortHistory = sleepHistory(nightCount: 14, endingOn: today) { _ in
            SleepSummary(duration: nil, vitals: SleepVitalsSummary(heartRate: 55))
        }
        let shortSnapshot = VitalsCalculator.snapshot(
            sleepHistory: shortHistory,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(shortSnapshot.nights.isEmpty)

        let history = sleepHistory(nightCount: 15, endingOn: today) { _ in
            SleepSummary(duration: nil, vitals: SleepVitalsSummary(heartRate: 55))
        }
        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )

        let latest = try XCTUnwrap(snapshot.latestNight)
        XCTAssertEqual(latest.date, calendar.startOfDay(for: today))
        XCTAssertEqual(latest.measurements.map(\.kind), [.sleepingHeartRate])
    }

    func testNormalizedDeviationMatchesRegionBoundaries() {
        let baseline = ReadinessScoreCalculator.Baseline(median: 60, spread: 3, validDayCount: 20)

        // The typical band spans ±typicalBandMultiplier·spread; |deviation| = 1
        // is the band edge (still typical), beyond it is an outlier region.
        XCTAssertEqual(VitalsCalculator.normalizedDeviation(value: 66, baseline: baseline), 1.0)
        XCTAssertEqual(VitalsCalculator.normalizedDeviation(value: 54, baseline: baseline), -1.0)
        XCTAssertEqual(VitalsCalculator.normalizedDeviation(value: 63, baseline: baseline), 0.5)
        XCTAssertEqual(VitalsCalculator.normalizedDeviation(value: 90, baseline: baseline), VitalsCalculator.deviationCap)
        XCTAssertEqual(VitalsCalculator.normalizedDeviation(value: 20, baseline: baseline), -VitalsCalculator.deviationCap)
    }

    // MARK: - Classification

    func testValueInsideTheTypicalBandStaysTypical() throws {
        let measurement = try heartRateMeasurement(onLastNight: 55 + 1.9 * VitalsCalculator.Floor.heartRate)

        XCTAssertEqual(measurement.region, .typical)
        XCTAssertEqual(measurement.normalizedDeviation, 0.95, accuracy: 0.0001)
    }

    func testValueOutsideTheTypicalBandIsAnOutlier() throws {
        let history = constantHeartRateHistory(lastNightValue: 55 + 2.1 * VitalsCalculator.Floor.heartRate)
        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )

        let latest = try XCTUnwrap(snapshot.latestNight)
        let measurement = try XCTUnwrap(latest.measurements.first)
        XCTAssertEqual(measurement.region, .high)
        XCTAssertEqual(measurement.normalizedDeviation, 1.05, accuracy: 0.0001)
        XCTAssertEqual(latest.outlierCount, 1)
        XCTAssertEqual(latest.statusText, "1 Outlier")
    }

    func testDeviationIsClampedForExtremeValues() throws {
        let high = try heartRateMeasurement(onLastNight: 500)
        XCTAssertEqual(high.normalizedDeviation, VitalsCalculator.deviationCap)
        XCTAssertEqual(high.region, .high)

        let low = try heartRateMeasurement(onLastNight: 1)
        XCTAssertEqual(low.normalizedDeviation, -VitalsCalculator.deviationCap)
        XCTAssertEqual(low.region, .low)
    }

    // MARK: - Sleep Duration

    func testSleepDurationSpreadFloorsAndSkipsNightsWithoutDuration() throws {
        let history = sleepHistory(nightCount: 21, endingOn: today) { offset in
            SleepSummary(
                duration: offset == 20 ? nil : (7 + Double(offset % 3) * 0.01) * 3_600,
                vitals: SleepVitalsSummary(heartRate: 55)
            )
        }

        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )

        let yesterday = try XCTUnwrap(snapshot.nights.first { $0.date == calendar.startOfDay(for: date(daysBefore: 1)) })
        let duration = try XCTUnwrap(yesterday.measurements.first { $0.kind == .sleepDuration })
        XCTAssertEqual(duration.baseline.spread, VitalsCalculator.Floor.sleepDurationHours)

        let latest = try XCTUnwrap(snapshot.latestNight)
        XCTAssertEqual(latest.date, calendar.startOfDay(for: today))
        XCTAssertEqual(latest.measurements.map(\.kind), [.sleepingHeartRate])
    }

    // MARK: - Baseline Equivalence

    /// The snapshot windows each vital's baseline itself instead of handing the
    /// whole series to `robustBaseline` once per night. Every night, every
    /// vital, must still land on exactly the baseline the unwindowed call
    /// produces.
    func testSnapshotBaselinesMatchTheUnwindowedRobustBaseline() {
        for fixture in equivalenceFixtures() {
            let snapshot = VitalsCalculator.snapshot(
                sleepHistory: fixture.history,
                currentDaySleep: fixture.currentDaySleep,
                today: today,
                calendar: calendar
            )
            let reference = referenceNights(
                history: fixture.history,
                currentDaySleep: fixture.currentDaySleep
            )

            XCTAssertEqual(snapshot.nights.map(\.date), reference.map(\.date), fixture.name)

            for (night, expected) in zip(snapshot.nights, reference) {
                XCTAssertEqual(night.measurements.map(\.kind), expected.entries.map(\.kind), fixture.name)

                for (measurement, entry) in zip(night.measurements, expected.entries) {
                    XCTAssertEqual(measurement.value, entry.value, accuracy: 1e-9, fixture.name)
                    XCTAssertEqual(measurement.baseline.median, entry.baseline.median, accuracy: 1e-9, fixture.name)
                    XCTAssertEqual(measurement.baseline.spread, entry.baseline.spread, accuracy: 1e-9, fixture.name)
                    XCTAssertEqual(
                        measurement.baseline.validDayCount,
                        entry.baseline.validDayCount,
                        fixture.name
                    )
                }
            }
        }
    }

    /// Each night reads a fixed 56-day window, so a snapshot costs about the
    /// same per night however long the history is. A baseline that rescans the
    /// whole series per night grows with it, and four times the nights cost
    /// sixteen times as much.
    func testSnapshotCostGrowsWithHistoryLengthNotItsSquare() {
        let shortElapsed = snapshotDuration(nightCount: 100)
        let longElapsed = snapshotDuration(nightCount: 400)

        print("""
            [timing] vitals snapshot: \
            100 nights \(String(format: "%.1f", shortElapsed * 1_000)) ms, \
            400 nights \(String(format: "%.1f", longElapsed * 1_000)) ms
            """)

        XCTAssertLessThan(longElapsed, shortElapsed * 8)
        // Debug builds run several times slower than the shipping build; this
        // only has to catch a return to the quadratic walk, which took over a
        // second here.
        XCTAssertLessThan(longElapsed, 0.4)
    }

    private func snapshotDuration(nightCount: Int) -> TimeInterval {
        let history = sleepHistory(nightCount: nightCount, endingOn: today) { offset in
            fullSummary(offset: offset)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(snapshot.nights.count, nightCount - ReadinessScoreCalculator.minimumBaselineDayCount)
        return elapsed
    }

    // MARK: - Status Text

    func testSnapshotStatusTextTotalsOutliersAcrossNights() {
        let typicalNight = VitalsNightAssessment(
            date: date(daysBefore: 1),
            measurements: [measurement(kind: .sleepingHeartRate, region: .typical)]
        )
        let outlierNight = VitalsNightAssessment(
            date: today,
            measurements: [
                measurement(kind: .sleepingHeartRate, region: .high),
                measurement(kind: .bloodOxygen, region: .low),
                measurement(kind: .sleepDuration, region: .typical)
            ]
        )

        XCTAssertEqual(VitalsSnapshot.statusText(for: []), "Typical")
        XCTAssertEqual(VitalsSnapshot.statusText(for: [typicalNight]), "Typical")
        XCTAssertEqual(VitalsSnapshot.statusText(for: [typicalNight, outlierNight]), "2 Outliers")
    }

    // MARK: - Current Night

    func testCurrentNightAssessmentIsNilWhenTodaysSleepHasNotArrived() {
        // 20 calibrated nights, but the newest ended yesterday and nothing has
        // synced for today: the headline must fall back to a placeholder, not
        // replay yesterday's status.
        let history = sleepHistory(nightCount: 20, endingOn: date(daysBefore: 1)) { _ in
            SleepSummary(duration: nil, vitals: SleepVitalsSummary(heartRate: 55))
        }

        XCTAssertNil(VitalsCalculator.currentNightAssessment(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        ))
    }

    func testCurrentNightAssessmentMergesTodaysSleepAndMatchesTheFullSnapshot() throws {
        let history = sleepHistory(nightCount: 20, endingOn: date(daysBefore: 1)) { _ in
            SleepSummary(duration: nil, vitals: SleepVitalsSummary(heartRate: 55))
        }
        let currentDaySleep = SleepSummary(
            duration: nil,
            stageSnapshot: SleepStageSnapshot(date: today, segments: []),
            vitals: SleepVitalsSummary(heartRate: 62)
        )

        let latest = try XCTUnwrap(VitalsCalculator.currentNightAssessment(
            sleepHistory: history,
            currentDaySleep: currentDaySleep,
            today: today,
            calendar: calendar
        ))

        XCTAssertEqual(latest.date, calendar.startOfDay(for: today))
        XCTAssertEqual(latest.measurements.first?.value, 62)

        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: currentDaySleep,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(latest, snapshot.latestNight)
    }

    /// The cheap path only walks the nights the current night's baseline can
    /// read, so an extreme night 120 days back is invisible to both paths and
    /// the windowed result must still match the full snapshot.
    func testCurrentNightAssessmentSkipsNightsOutsideTheBaselineWindow() throws {
        let history = sleepHistory(nightCount: 365, endingOn: today) { offset in
            SleepSummary(
                duration: nil,
                vitals: SleepVitalsSummary(heartRate: offset == 244 ? 200 : 52 + Double(offset % 5))
            )
        }

        let latest = try XCTUnwrap(VitalsCalculator.currentNightAssessment(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        ))

        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(history.days[244].date, date(daysBefore: 120), "the extreme night must sit outside the 56-day window")
        XCTAssertEqual(latest, snapshot.latestNight)
    }

    // MARK: - Floors

    func testFloorsMatchTheReadinessMetricFloors() {
        XCTAssertEqual(VitalsCalculator.Floor.heartRate, 3.0)
        XCTAssertEqual(VitalsCalculator.Floor.respiratoryRate, 0.6)
        XCTAssertEqual(VitalsCalculator.Floor.oxygenSaturation, 1.0)
        XCTAssertEqual(VitalsCalculator.Floor.wristTemperature, 0.2)
        XCTAssertEqual(VitalsCalculator.Floor.sleepDurationHours, 0.5)
    }

    // MARK: - Reference Range

    func testNarrowReferenceRangeKeepsTheTypicalBandInTheMiddleThird() {
        let range = SleepVitalReferenceRange(typicalLowerBound: 36.4, typicalUpperBound: 37.2)

        XCTAssertEqual(range.markerPosition(for: 36.4), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(range.markerPosition(for: 37.2), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(range.markerPosition(for: 36.8), 0.5, accuracy: 0.0001)
    }

    // MARK: - Fixtures

    private func date(daysBefore offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: today)!
    }

    // MARK: - Coverage

    func testDenseYearOfNightsAssessesEverythingPastTheCalibrationWindow() {
        let history = sleepHistory(nightCount: 365, endingOn: today) { offset in
            SleepSummary(duration: nil, vitals: SleepVitalsSummary(heartRate: 52 + Double(offset % 5)))
        }

        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )

        // Night 15 is the first with 14 prior nights, so a dense year keeps
        // every night from there on: 365 - 14.
        XCTAssertEqual(snapshot.nights.count, 351)
        XCTAssertEqual(
            snapshot.nights.first?.date,
            calendar.date(byAdding: .day, value: -350, to: calendar.startOfDay(for: today))
        )
        XCTAssertEqual(snapshot.nights.last?.date, calendar.startOfDay(for: today))
    }

    func testSparseStretchIsDroppedByTheRollingBaselineGate() {
        // ~One logged night per week for 12 weeks, then 8 dense weeks: the
        // sparse nights never see 14 valid nights inside their trailing 56
        // days, so only the dense block (past its own calibration) assesses.
        let denseNightCount = 56
        let sparseNightCount = 12
        let days = (0..<sparseNightCount).map { index in
            -(denseNightCount + (sparseNightCount - index) * 7 - 7)
        } + Array(-(denseNightCount - 1)...0)
        let history = SleepHistorySnapshot(days: days.map { offset in
            SleepDaySummary(
                date: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))!,
                summary: SleepSummary(duration: nil, vitals: SleepVitalsSummary(heartRate: 55))
            )
        })

        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: history,
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )

        let denseBlockStart = calendar.date(
            byAdding: .day,
            value: -(denseNightCount - 1),
            to: calendar.startOfDay(for: today)
        )!
        XCTAssertFalse(snapshot.nights.isEmpty)
        XCTAssertTrue(snapshot.nights.allSatisfy { $0.date >= denseBlockStart })
    }

    // MARK: - Chart bucket geometry

    func testYearBucketsAnchorNewestAndEndOnToday() {
        let days = BodyVitalsOutlierTrendChart.dayGrid(for: .recentYear, calendar: calendar, date: today)
        let nights = (0..<365).map { offset in
            VitalsNightAssessment(
                date: calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today))!,
                measurements: []
            )
        }

        let buckets = BodyVitalsOutlierTrendChart.buckets(
            from: nights,
            days: days,
            selectedRange: .recentYear,
            calendar: calendar
        )

        // 365 days at 12-day pitch = 30 full buckets anchored on today; the
        // 5-day remainder at the oldest end is dropped.
        XCTAssertEqual(buckets.count, 30)
        XCTAssertEqual(buckets.first?.date, days[5])
        XCTAssertEqual(buckets.last?.endDate, calendar.startOfDay(for: today))
    }

    func testSixMonthBucketsAnchorNewestAndEndOnToday() {
        let days = BodyVitalsOutlierTrendChart.dayGrid(for: .recentSixMonths, calendar: calendar, date: today)
        let nights = (0..<183).map { offset in
            VitalsNightAssessment(
                date: calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today))!,
                measurements: []
            )
        }

        let buckets = BodyVitalsOutlierTrendChart.buckets(
            from: nights,
            days: days,
            selectedRange: .recentSixMonths,
            calendar: calendar
        )

        XCTAssertEqual(buckets.count, 30)
        XCTAssertEqual(buckets.first?.date, days[3])
        XCTAssertEqual(buckets.last?.endDate, calendar.startOfDay(for: today))
    }

    // MARK: - Equivalence Helpers

    private struct EquivalenceFixture {
        var name: String
        var history: SleepHistorySnapshot
        var currentDaySleep: SleepSummary?
    }

    private struct ReferenceNight {
        var date: Date
        var entries: [(kind: VitalKind, value: Double, baseline: ReadinessScoreCalculator.Baseline)]
    }

    /// A tiny deterministic generator so the fixtures are reproducible without
    /// depending on the platform's random number generator.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    private func equivalenceFixtures() -> [EquivalenceFixture] {
        var generator = SeededGenerator(state: 0x9E37_79B9_7F4A_7C15)

        let dense = sleepHistory(nightCount: 400, endingOn: today) { offset in
            fullSummary(offset: offset)
        }

        // Random gaps in the day grid plus randomly missing vitals, so the five
        // series stop lining up with one another and with the night grid.
        let raggedDays = (0..<400).compactMap { offset -> SleepDaySummary? in
            guard Int.random(in: 0..<10, using: &generator) > 1 else {
                return nil
            }
            let summary = SleepSummary(
                duration: Int.random(in: 0..<4, using: &generator) == 0
                    ? nil
                    : (6.5 + Double(offset % 7) * 0.2) * 3_600,
                vitals: SleepVitalsSummary(
                    heartRate: Int.random(in: 0..<5, using: &generator) == 0 ? nil : 52 + Double(offset % 9),
                    respiratoryRate: Int.random(in: 0..<3, using: &generator) == 0 ? nil : 14 + Double(offset % 4) * 0.3,
                    oxygenSaturation: Int.random(in: 0..<6, using: &generator) == 0 ? nil : 96 + Double(offset % 3),
                    wristTemperatureCelsius: Int.random(in: 0..<7, using: &generator) == 0
                        ? nil
                        : 33.5 + Double(offset % 5) * 0.1
                )
            )
            return SleepDaySummary(
                date: calendar.date(byAdding: .day, value: offset - 399, to: calendar.startOfDay(for: today))!,
                summary: summary
            )
        }

        // Two entries filed under the same night, which collapse to one day key
        // before any baseline sees them.
        let duplicatedDay = SleepDaySummary(
            date: calendar.date(byAdding: .hour, value: 9, to: calendar.startOfDay(for: date(daysBefore: 30)))!,
            summary: fullSummary(offset: 77)
        )

        let todaySummary = SleepSummary(
            duration: 7.25 * 3_600,
            stageSnapshot: SleepStageSnapshot(date: today, segments: []),
            vitals: SleepVitalsSummary(
                heartRate: 61,
                respiratoryRate: 15.4,
                oxygenSaturation: 97,
                wristTemperatureCelsius: 33.9
            )
        )

        let historyEndingYesterday = sleepHistory(nightCount: 400, endingOn: date(daysBefore: 1)) { offset in
            fullSummary(offset: offset)
        }

        return [
            EquivalenceFixture(name: "dense", history: dense, currentDaySleep: nil),
            EquivalenceFixture(name: "ragged", history: SleepHistorySnapshot(days: raggedDays), currentDaySleep: nil),
            EquivalenceFixture(
                name: "duplicate day key",
                history: SleepHistorySnapshot(days: dense.days + [duplicatedDay]),
                currentDaySleep: nil
            ),
            EquivalenceFixture(
                name: "current day sleep merged",
                history: historyEndingYesterday,
                currentDaySleep: todaySummary
            ),
            EquivalenceFixture(
                name: "current day sleep already in history",
                history: dense,
                currentDaySleep: todaySummary
            ),
            EquivalenceFixture(
                name: "short history",
                history: sleepHistory(nightCount: 13, endingOn: today) { offset in fullSummary(offset: offset) },
                currentDaySleep: nil
            )
        ]
    }

    /// The pre-optimization path: every night graded by handing `robustBaseline`
    /// the vital's entire daily series.
    private func referenceNights(
        history: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?
    ) -> [ReferenceNight] {
        let todayKey = calendar.startOfDay(for: today)
        var valuesByDayByKind: [VitalKind: [Date: Double]] = [:]

        for day in history.days {
            let dayKey = calendar.startOfDay(for: day.date)
            for kind in VitalKind.allCases {
                guard let value = value(of: kind, in: day.summary) else {
                    continue
                }
                valuesByDayByKind[kind, default: [:]][dayKey] = value
            }
        }

        if let todaySleep = currentDaySleep?.asOf(today, calendar: calendar) {
            for kind in VitalKind.allCases {
                guard valuesByDayByKind[kind]?[todayKey] == nil,
                      let value = value(of: kind, in: todaySleep) else {
                    continue
                }
                valuesByDayByKind[kind, default: [:]][todayKey] = value
            }
        }

        let dailyValuesByKind = valuesByDayByKind.mapValues { valuesByDay in
            valuesByDay.map { ReadinessScoreCalculator.DailyValue(date: $0.key, value: $0.value) }
        }
        let nightDates = Set(valuesByDayByKind.values.flatMap(\.keys)).sorted()

        return nightDates.compactMap { date in
            let entries = VitalKind.allCases.compactMap {
                kind -> (kind: VitalKind, value: Double, baseline: ReadinessScoreCalculator.Baseline)? in
                guard let value = valuesByDayByKind[kind]?[date],
                      let baseline = ReadinessScoreCalculator.robustBaseline(
                          for: date,
                          values: dailyValuesByKind[kind] ?? [],
                          floor: floor(for: kind),
                          calendar: calendar
                      ) else {
                    return nil
                }
                return (kind, value, baseline)
            }

            return entries.isEmpty ? nil : ReferenceNight(date: date, entries: entries)
        }
    }

    private func fullSummary(offset: Int) -> SleepSummary {
        SleepSummary(
            duration: (6.8 + Double(offset % 11) * 0.15) * 3_600,
            vitals: SleepVitalsSummary(
                heartRate: 52 + Double(offset % 9),
                respiratoryRate: 14 + Double(offset % 4) * 0.3,
                oxygenSaturation: 96 + Double(offset % 3),
                wristTemperatureCelsius: 33.5 + Double(offset % 5) * 0.1
            )
        )
    }

    private func value(of kind: VitalKind, in summary: SleepSummary) -> Double? {
        let value: Double?
        switch kind {
        case .sleepingHeartRate:
            value = summary.vitals.heartRate
        case .respiratoryRate:
            value = summary.vitals.respiratoryRate
        case .wristTemperature:
            value = summary.vitals.wristTemperatureCelsius
        case .bloodOxygen:
            value = summary.vitals.oxygenSaturation
        case .sleepDuration:
            value = summary.duration.flatMap { $0 > 0 ? $0 / 3_600 : nil }
        }

        guard let value, value.isFinite else {
            return nil
        }

        return value
    }

    private func floor(for kind: VitalKind) -> Double {
        switch kind {
        case .sleepingHeartRate:
            return VitalsCalculator.Floor.heartRate
        case .respiratoryRate:
            return VitalsCalculator.Floor.respiratoryRate
        case .wristTemperature:
            return VitalsCalculator.Floor.wristTemperature
        case .bloodOxygen:
            return VitalsCalculator.Floor.oxygenSaturation
        case .sleepDuration:
            return VitalsCalculator.Floor.sleepDurationHours
        }
    }

    private func sleepHistory(
        nightCount: Int,
        endingOn lastNight: Date,
        summary: (Int) -> SleepSummary
    ) -> SleepHistorySnapshot {
        SleepHistorySnapshot(days: (0..<nightCount).map { offset in
            SleepDaySummary(
                date: calendar.date(byAdding: .day, value: offset - (nightCount - 1), to: lastNight)!,
                summary: summary(offset)
            )
        })
    }

    /// 20 flat nights of 55 BPM — a zero-spread baseline that floors at
    /// `Floor.heartRate`, so a night's deviation is exactly predictable.
    private func constantHeartRateHistory(lastNightValue: Double) -> SleepHistorySnapshot {
        sleepHistory(nightCount: 21, endingOn: today) { offset in
            SleepSummary(
                duration: nil,
                vitals: SleepVitalsSummary(heartRate: offset == 20 ? lastNightValue : 55)
            )
        }
    }

    private func heartRateMeasurement(onLastNight value: Double) throws -> VitalMeasurement {
        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: constantHeartRateHistory(lastNightValue: value),
            currentDaySleep: nil,
            today: today,
            calendar: calendar
        )

        let latest = try XCTUnwrap(snapshot.latestNight)
        return try XCTUnwrap(latest.measurements.first)
    }

    private func measurement(kind: VitalKind, region: SleepVitalRegion) -> VitalMeasurement {
        VitalMeasurement(
            kind: kind,
            value: 0,
            baseline: ReadinessScoreCalculator.Baseline(median: 0, spread: 1, validDayCount: 20),
            normalizedDeviation: region == .typical ? 0 : 2,
            region: region,
            referenceRange: SleepVitalReferenceRange(typicalLowerBound: -2, typicalUpperBound: 2)
        )
    }
}
