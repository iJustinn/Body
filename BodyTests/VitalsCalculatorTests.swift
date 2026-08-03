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
