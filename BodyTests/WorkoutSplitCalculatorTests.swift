//
//  WorkoutSplitCalculatorTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutSplitCalculatorTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let base = 1_700_000_000.0
    private let km = 1_000.0
    private let mile = 1_609.344

    private func sample(_ start: Double, _ end: Double, _ meters: Double) -> WorkoutDistanceSample {
        WorkoutDistanceSample(
            startDate: Date(timeIntervalSince1970: base + start),
            endDate: Date(timeIntervalSince1970: base + end),
            meters: meters
        )
    }

    private func date(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: base + offset)
    }

    /// 100 m every 30 s (5:00 / km) for `count` samples starting at offset 0.
    private func evenSamples(count: Int) -> [WorkoutDistanceSample] {
        (0..<count).map { sample(Double($0) * 30, Double($0 + 1) * 30, 100) }
    }

    private func split(
        _ index: Int,
        _ meters: Double,
        _ seconds: Double,
        partial: Bool = false,
        start: Double = 0
    ) -> WorkoutSplit {
        WorkoutSplit(
            index: index,
            distanceMeters: meters,
            durationSeconds: seconds,
            isPartial: partial,
            startDate: date(start),
            endDate: date(start + seconds)
        )
    }

    private func heartRateSample(_ offset: Double, _ bpm: Double) -> WorkoutHeartRateSample {
        WorkoutHeartRateSample(date: date(offset), beatsPerMinute: bpm)
    }

    // MARK: - Calculator

    func testEvenPaceProducesCompleteSplitsWithoutPartial() {
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 30),
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(900)
        )
        XCTAssertEqual(splits.count, 3)
        for split in splits {
            XCTAssertEqual(split.distanceMeters, 1000, accuracy: 0.0001)
            XCTAssertEqual(split.durationSeconds, 300, accuracy: 0.0001)
            XCTAssertFalse(split.isPartial)
        }
        XCTAssertEqual(splits.map(\.index), [1, 2, 3])
    }

    func testBoundaryCrossingInterpolatesDurationInsideSample() {
        // 800 m in the first 100 s, then 400 m over the next 200 s. The 1 km boundary
        // falls halfway through the second sample → split 1 lasts 200 s, not 300 s.
        let samples = [sample(0, 100, 800), sample(100, 300, 400)]
        let splits = WorkoutSplitCalculator.splits(
            samples: samples,
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(300)
        )
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].distanceMeters, 1000, accuracy: 0.0001)
        XCTAssertEqual(splits[0].durationSeconds, 200, accuracy: 0.0001)
        XCTAssertFalse(splits[0].isPartial)
        XCTAssertTrue(splits[1].isPartial)
        XCTAssertEqual(splits[1].distanceMeters, 200, accuracy: 0.0001)
        XCTAssertEqual(splits[1].durationSeconds, 100, accuracy: 0.0001)
    }

    func testPartialSplitEndsAtLastSampleEnd() {
        // 2.4 km of even samples → 2 complete km splits + a ~400 m partial ending at 720 s.
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 24),
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(720)
        )
        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[0].distanceMeters, 1000, accuracy: 0.0001)
        XCTAssertEqual(splits[1].distanceMeters, 1000, accuracy: 0.0001)
        XCTAssertTrue(splits[2].isPartial)
        XCTAssertEqual(splits[2].distanceMeters, 400, accuracy: 0.0001)
        XCTAssertEqual(splits[2].durationSeconds, 120, accuracy: 0.0001)
    }

    func testLessThanOneUnitProducesNoPresentation() {
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 6), // 600 m
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(180)
        )
        XCTAssertNil(WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .distancePace,
            distanceUnitPreference: .kilometers,
            locale: enUS
        ))
    }

    func testEmptyAndZeroMeterSamplesProduceNoSplits() {
        XCTAssertTrue(WorkoutSplitCalculator.splits(
            samples: [],
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(300)
        ).isEmpty)

        let zeroed = [sample(0, 30, 0), sample(30, 60, 0)]
        XCTAssertTrue(WorkoutSplitCalculator.splits(
            samples: zeroed,
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(60)
        ).isEmpty)
    }

    func testUnsortedInputIsHandled() {
        let splits = WorkoutSplitCalculator.splits(
            samples: Array(evenSamples(count: 20).reversed()),
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(600)
        )
        XCTAssertEqual(splits.count, 2)
        for split in splits {
            XCTAssertEqual(split.durationSeconds, 300, accuracy: 0.0001)
            XCTAssertFalse(split.isPartial)
        }
    }

    func testRemainderBelowTenMetersHasNoPartial() {
        // One full km, then a 5 m tail — below the 10 m partial threshold.
        let samples = evenSamples(count: 10) + [sample(300, 302, 5)]
        let splits = WorkoutSplitCalculator.splits(
            samples: samples,
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(302)
        )
        XCTAssertEqual(splits.count, 1)
        XCTAssertFalse(splits[0].isPartial)
    }

    func testMilesBoundaryCrossesAtMileLength() {
        // 2 km of even samples split by miles → boundary at 1609.344 m at ~482.8 s.
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 20),
            unitMeters: mile,
            workoutStart: date(0),
            workoutEnd: date(600)
        )
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].distanceMeters, mile, accuracy: 0.001)
        XCTAssertEqual(splits[0].durationSeconds, 482.8032, accuracy: 0.001)
        XCTAssertTrue(splits[1].isPartial)
    }

    func testGranularityGuardReturnsNoSplitsForCoarseSample() {
        // A single sample already covering a full unit is too coarse to split.
        let splits = WorkoutSplitCalculator.splits(
            samples: [sample(0, 300, 1200)],
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(300)
        )
        XCTAssertTrue(splits.isEmpty)
    }

    func testClippingTrimsPreStartMetersSoSplitOneIsNotInflated() {
        // The first sample starts 100 s before the workout and carries 400 m over 200 s;
        // only the in-window half (200 m) may count, so the km boundary lands exactly at
        // the workout end (300 s) rather than earlier.
        let samples = [
            sample(-100, 100, 400),
            sample(100, 200, 400),
            sample(200, 300, 400)
        ]
        let splits = WorkoutSplitCalculator.splits(
            samples: samples,
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(300)
        )
        XCTAssertEqual(splits.count, 1)
        XCTAssertFalse(splits[0].isPartial)
        XCTAssertEqual(splits[0].distanceMeters, 1000, accuracy: 0.0001)
        XCTAssertEqual(splits[0].durationSeconds, 300, accuracy: 0.0001)
    }

    func testRecordedSegmentsOverrideInterpolatedBoundaries() {
        // The watch recorded km segments ending at 290 s and 590 s, while the distance
        // samples put the interpolated 1 km boundary at 300 s (GPS-lag drift). The
        // recorded segments must win: they are the windows Apple Fitness shows.
        let segments = [
            WorkoutTimeSegment(startDate: date(0), endDate: date(290)),
            WorkoutTimeSegment(startDate: date(290), endDate: date(590))
        ]
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 20), // 2 km, interpolated boundary at 300 s
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(600),
            segments: segments
        )
        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[0].durationSeconds, 290, accuracy: 0.0001)
        XCTAssertEqual(splits[0].endDate, date(290))
        XCTAssertEqual(splits[1].durationSeconds, 300, accuracy: 0.0001)
        XCTAssertTrue(splits[2].isPartial) // ~33 m recorded in the 10 s past the last segment
        XCTAssertEqual(splits[2].distanceMeters, 33.3333, accuracy: 0.01)
    }

    func testRecordedSegmentsAddPartialTail() {
        // 2.4 km of samples with two recorded km segments → the ~400 m after the last
        // segment becomes the partial split, windowed from the segment end.
        let segments = [
            WorkoutTimeSegment(startDate: date(0), endDate: date(300)),
            WorkoutTimeSegment(startDate: date(300), endDate: date(600))
        ]
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 24),
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(720),
            segments: segments
        )
        XCTAssertEqual(splits.count, 3)
        XCTAssertTrue(splits[2].isPartial)
        XCTAssertEqual(splits[2].distanceMeters, 400, accuracy: 0.0001)
        XCTAssertEqual(splits[2].startDate, date(600))
        XCTAssertEqual(splits[2].endDate, date(720))
    }

    func testSegmentsSurviveEarlyRunDistanceUndercount() {
        // The distance samples undercount segment 1 (GPS still calibrating: 880 m
        // recorded across the first recorded km window) while later segments sum to
        // 1000 m. The median distance validates, so the recorded windows still win.
        let segments = [
            WorkoutTimeSegment(startDate: date(0), endDate: date(300)),
            WorkoutTimeSegment(startDate: date(300), endDate: date(600)),
            WorkoutTimeSegment(startDate: date(600), endDate: date(900))
        ]
        let samples = [
            sample(0, 150, 440), sample(150, 300, 440),
            sample(300, 450, 500), sample(450, 600, 500),
            sample(600, 750, 500), sample(750, 900, 500)
        ]
        let splits = WorkoutSplitCalculator.splits(
            samples: samples,
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(900),
            segments: segments
        )
        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[0].startDate, date(0))
        XCTAssertEqual(splits[0].endDate, date(300))
        XCTAssertFalse(splits.contains { $0.isPartial })
    }

    func testPauseSliversAndDuplicateSegmentsAreDropped() {
        // A 3 km run whose event list mixes the three real km windows with two
        // pause slivers (tiny recorded distance) and a duplicate of km 1 — the
        // extras must be dropped, leaving exactly three splits.
        let segments = [
            WorkoutTimeSegment(startDate: date(0), endDate: date(300)),
            WorkoutTimeSegment(startDate: date(5), endDate: date(295)),    // duplicate of km 1
            WorkoutTimeSegment(startDate: date(300), endDate: date(320)),  // pause sliver
            WorkoutTimeSegment(startDate: date(300), endDate: date(600)),
            WorkoutTimeSegment(startDate: date(600), endDate: date(615)),  // pause sliver
            WorkoutTimeSegment(startDate: date(600), endDate: date(900))
        ]
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 30),
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(900),
            segments: segments
        )
        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits.map(\.endDate), [date(300), date(600), date(900)])
        XCTAssertFalse(splits.contains { $0.isPartial })
    }

    func testSparseManualLapsFallBackToInterpolation() {
        // Two manual ~1 km laps inside a 3 km run don't account for the whole
        // distance, so interpolation is used instead of pretending 2 splits.
        let segments = [
            WorkoutTimeSegment(startDate: date(0), endDate: date(300)),
            WorkoutTimeSegment(startDate: date(300), endDate: date(600))
        ]
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 30), // 3 km
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(900),
            segments: segments
        )
        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[2].durationSeconds, 300, accuracy: 0.0001) // interpolated km 3
    }

    func testMismatchedUnitSegmentsFallBackToInterpolation() {
        // Mile-length recorded segments while viewing kilometers: distance within each
        // segment (~1609 m) diverges from 1000 m, so interpolation is used instead.
        let segments = [
            WorkoutTimeSegment(startDate: date(0), endDate: date(482.8))
        ]
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 20), // 2 km
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(600),
            segments: segments
        )
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].durationSeconds, 300, accuracy: 0.0001) // interpolated
    }

    func testSubUnitOnlyWorkoutSegmentBecomesPartialNotFullUnit() {
        // A 0.9 km workout whose single recorded segment spans the whole run. Its
        // distance (900 m) passes the 15% window check but the run never completed a
        // full km, so it must not be shown as a completed unit — the segment path
        // rejects it, and interpolation reports the true 900 m partial.
        let segments = [WorkoutTimeSegment(startDate: date(0), endDate: date(270))]
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 9), // 900 m
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(270),
            segments: segments
        )
        XCTAssertEqual(splits.count, 1)
        XCTAssertTrue(splits[0].isPartial)
        XCTAssertEqual(splits[0].distanceMeters, 900, accuracy: 0.0001)
    }

    func testSubUnitFinalSegmentReportedAsPartialTail() {
        // Two full km then a 0.9 km final lap. The trailing sub-unit segment is late in
        // the run (no undercount excuse), so it becomes a 900 m partial instead of a
        // fake third full km.
        let segments = [
            WorkoutTimeSegment(startDate: date(0), endDate: date(300)),
            WorkoutTimeSegment(startDate: date(300), endDate: date(600)),
            WorkoutTimeSegment(startDate: date(600), endDate: date(870))
        ]
        let splits = WorkoutSplitCalculator.splits(
            samples: evenSamples(count: 29), // 2.9 km
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(870),
            segments: segments
        )
        XCTAssertEqual(splits.count, 3)
        XCTAssertFalse(splits[0].isPartial)
        XCTAssertFalse(splits[1].isPartial)
        XCTAssertTrue(splits[2].isPartial)
        XCTAssertEqual(splits[2].distanceMeters, 900, accuracy: 0.0001)
        XCTAssertEqual(splits[2].startDate, date(600))
    }

    func testNearUnitTrailingSegmentIsNotPromotedToFullUnit() {
        // The 960 m near-unit case from review: a workout that stops just short of a
        // full km records a single ~960 m segment. It clears the 15% window check but
        // never completed the unit, so it must stay a 960 m partial, not a full km.
        let segments = [WorkoutTimeSegment(startDate: date(0), endDate: date(288))]
        let splits = WorkoutSplitCalculator.splits(
            samples: [sample(0, 288, 960)],
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(288),
            segments: segments
        )
        XCTAssertEqual(splits.count, 1)
        XCTAssertTrue(splits[0].isPartial)
        XCTAssertEqual(splits[0].distanceMeters, 960, accuracy: 0.5)
    }

    // MARK: - Presentation

    func testPresentationFlagsFastestAndPartialFraction() {
        let splits = [
            split(1, 1000, 300),           // 3.333 m/s
            split(2, 1000, 250),           // 4.0 m/s  (fastest)
            split(3, 1000, 10000),         // 0.1 m/s
            split(4, 400, 200, partial: true)
        ]
        let presentation = WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .distancePace,
            distanceUnitPreference: .kilometers,
            locale: enUS
        )
        let rows = try! XCTUnwrap(presentation).rows
        XCTAssertEqual(rows.count, 4)

        // Fastest highlight sits only on the single fastest complete split.
        XCTAssertEqual(rows.map(\.isFastest), [false, true, false, false])
        XCTAssertFalse(rows[3].isFastest) // partial is never fastest

        // Bars track pace: the slowest split fills the bar, the fastest is shortest.
        XCTAssertEqual(rows[2].barFraction, 1.0, accuracy: 0.0001) // slowest → full bar
        XCTAssertLessThan(rows[1].barFraction, rows[0].barFraction) // fastest shorter than row 1
        XCTAssertEqual(rows.map(\.barFraction).min(), rows[1].barFraction) // fastest is shortest

        // Pace text and index/partial text.
        XCTAssertEqual(rows[0].indexText, "1")
        XCTAssertEqual(rows[0].valueText, "5:00 /km")
        XCTAssertEqual(rows[1].valueText, "4:10 /km")
        XCTAssertTrue(rows[3].isPartial)
        XCTAssertEqual(rows[3].indexText, "0.4")

        // No heart-rate samples supplied → no per-split HR text.
        XCTAssertNil(rows[0].heartRateText)

        // Accessibility label carries the fastest suffix only on the fastest row.
        XCTAssertEqual(rows[0].accessibilityLabel, "Kilometer 1, 5:00 /km")
        XCTAssertEqual(rows[1].accessibilityLabel, "Kilometer 2, 4:10 /km, Fastest split")
    }

    func testPresentationComputesPerSplitAverageHeartRate() {
        // Two back-to-back km splits: [0,300] and [300,550]. HR samples are averaged
        // within each split's window. Split 2 is faster so the fastest highlight (and
        // its accessibility suffix) lands there, keeping split 1's label free of it.
        let splits = [
            split(1, 1000, 300, start: 0),
            split(2, 1000, 250, start: 300)
        ]
        // Time-weighted (trapezoidal) average of the piecewise-linear HR curve,
        // clamped to each split window:
        // split 1 [0,300]: 150→160 over [10,120] plus 160→166.43 over [120,300] ≈ 160
        // split 2 [300,550]: 166.43→170 over [300,400] plus 170→180 over [400,500] ≈ 172
        let heartRate = [
            heartRateSample(10, 150),
            heartRateSample(120, 160),
            heartRateSample(400, 170),
            heartRateSample(500, 180)
        ]
        let presentation = WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .distancePace,
            distanceUnitPreference: .kilometers,
            heartRateSamples: heartRate,
            locale: enUS
        )
        let rows = try! XCTUnwrap(presentation).rows
        XCTAssertEqual(rows[0].heartRateText, "160")
        XCTAssertEqual(rows[1].heartRateText, "172")
        XCTAssertEqual(rows[0].accessibilityLabel, "Kilometer 1, 5:00 /km, Average heart rate 160 BPM")
    }

    func testPerSplitHeartRateIsTimeWeightedNotSampleWeighted() {
        // 100 s at 120 bpm sampled densely (every 10 s), then 200 s at 180 bpm from
        // just two samples. A per-sample mean would sit near 120 (11 of 13 samples);
        // the time-weighted average must weight the long sparse stretch: ~160 bpm.
        let splits = [split(1, 1000, 300, start: 0)]
        var heartRate = stride(from: 0.0, through: 100.0, by: 10.0).map { heartRateSample($0, 120) }
        heartRate.append(heartRateSample(101, 180))
        heartRate.append(heartRateSample(300, 180))
        let presentation = WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .distancePace,
            distanceUnitPreference: .kilometers,
            heartRateSamples: heartRate,
            locale: enUS
        )
        let rows = try! XCTUnwrap(presentation).rows
        let bpm = try! XCTUnwrap(rows[0].heartRateText.flatMap(Double.init))
        XCTAssertEqual(bpm, 160, accuracy: 2)
    }

    func testPresentationComputesPerSplitStepCadence() {
        // Split 1 [0,300]: 850 steps over 5 min → 170 spm. A step sample straddling
        // the boundary contributes proportionally. Split 2 has no steps → no text.
        let splits = [
            split(1, 1000, 300, start: 0),
            split(2, 1000, 300, start: 300)
        ]
        let steps = [
            WorkoutStepSample(startDate: date(0), endDate: date(200), count: 550),
            WorkoutStepSample(startDate: date(200), endDate: date(400), count: 600)
        ]
        let presentation = WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .distancePace,
            distanceUnitPreference: .kilometers,
            stepSamples: steps,
            locale: enUS
        )
        let rows = try! XCTUnwrap(presentation).rows
        // Split 1: 550 + 600 * (100/200) = 850 → 850/5 min = 170 spm.
        XCTAssertEqual(rows[0].cadenceText, "170")
        // Split 2: 600 * (100/200) = 300 → 300/5 min = 60 spm.
        XCTAssertEqual(rows[1].cadenceText, "60")

        // No step samples → no cadence text.
        let noSteps = try! XCTUnwrap(WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .distancePace,
            distanceUnitPreference: .kilometers,
            locale: enUS
        ))
        XCTAssertNil(noSteps.rows[0].cadenceText)
    }

    func testPerSplitHeartRateFallsBackToNearestSampleForEmptyWindow() {
        // Split 2's window holds no HR sample, so it falls back to the nearest sample
        // (in split 1) instead of showing nothing — every segment with any workout HR
        // data gets a value.
        let splits = [
            split(1, 1000, 300, start: 0),   // [0,300]
            split(2, 1000, 300, start: 300)  // [300,600] — no sample inside
        ]
        let heartRate = [heartRateSample(150, 148)] // only in split 1
        let presentation = WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .distancePace,
            distanceUnitPreference: .kilometers,
            heartRateSamples: heartRate,
            locale: enUS
        )
        let rows = try! XCTUnwrap(presentation).rows
        XCTAssertEqual(rows[0].heartRateText, "148")
        XCTAssertEqual(rows[1].heartRateText, "148")
    }

    func testEndToEndSplitsCarryAverageHeartRateForEverySegment() {
        // 3 km at 100 m / 30 s, with HR sampled every 10 s across the whole run:
        // the calculator-derived windows must catch HR samples in every segment.
        let distance = evenSamples(count: 30) // 0…900 s, 3 km
        let hr = stride(from: 0.0, through: 900.0, by: 10.0)
            .map { heartRateSample($0, 150) }
        let splits = WorkoutSplitCalculator.splits(
            samples: distance,
            unitMeters: km,
            workoutStart: date(0),
            workoutEnd: date(900)
        )
        let presentation = WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .distancePace,
            distanceUnitPreference: .kilometers,
            heartRateSamples: hr,
            locale: enUS
        )
        let rows = try! XCTUnwrap(presentation).rows
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.heartRateText == "150" }, "every segment should carry avg HR")
    }

    func testPresentationUsesSpeedTextForSpeedStyle() {
        let splits = [split(1, 1000, 250), split(2, 1000, 300)]
        let presentation = WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .speed,
            distanceUnitPreference: .kilometers,
            locale: enUS
        )
        let rows = try! XCTUnwrap(presentation).rows
        let expected = BodyValueFormat.speedText(
            meters: 1000,
            seconds: 250,
            distanceUnitPreference: .kilometers,
            locale: enUS
        )
        XCTAssertEqual(rows[0].valueText, expected)
        XCTAssertTrue(rows[0].valueText.contains("km/h"))
    }

    func testPresentationReturnsNilForSwimPace() {
        let splits = [split(1, 1000, 300)]
        XCTAssertNil(WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .swimPace,
            distanceUnitPreference: .kilometers,
            locale: enUS
        ))
        XCTAssertNil(WorkoutSplitsPresentation(
            splits: splits,
            paceStyle: .none,
            distanceUnitPreference: .kilometers,
            locale: enUS
        ))
    }
}
