//
//  WorkoutBucketedSeriesTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutBucketedSeriesTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let base = 1_700_000_000.0

    // MARK: - Input builders

    private func native(_ index: Int, _ average: Double, _ minimum: Double? = nil, _ maximum: Double? = nil) -> WorkoutMetricSeriesData.NativeBucket {
        WorkoutMetricSeriesData.NativeBucket(
            index: index,
            average: average,
            minimum: minimum ?? average,
            maximum: maximum ?? average
        )
    }

    private func series(
        _ buckets: [WorkoutMetricSeriesData.NativeBucket],
        sessionAverage: Double? = nil,
        sessionMax: Double? = nil
    ) -> WorkoutMetricSeriesData.NativeSeries {
        WorkoutMetricSeriesData.NativeSeries(
            buckets: buckets,
            sessionAverage: sessionAverage,
            sessionMax: sessionMax
        )
    }

    private func data(
        bucketSeconds: TimeInterval = 60,
        duration: TimeInterval = 600,
        activeSeconds: [Int: Double] = [:],
        distance: [Int: Double] = [:],
        steps: [Int: Double] = [:],
        stride: WorkoutMetricSeriesData.NativeSeries? = nil,
        groundContact: WorkoutMetricSeriesData.NativeSeries? = nil,
        verticalOscillation: WorkoutMetricSeriesData.NativeSeries? = nil,
        cyclingCadence: WorkoutMetricSeriesData.NativeSeries? = nil
    ) -> WorkoutMetricSeriesData {
        WorkoutMetricSeriesData(
            bucketSeconds: bucketSeconds,
            startDate: Date(timeIntervalSince1970: base),
            endDate: Date(timeIntervalSince1970: base + duration),
            bucketActiveSeconds: activeSeconds,
            distanceMeters: distance,
            steps: steps,
            strideLengthMeters: stride,
            groundContactTimeMs: groundContact,
            verticalOscillationCm: verticalOscillation,
            cyclingCadenceRPM: cyclingCadence,
            hadReadFailure: false
        )
    }

    /// `count` buckets of the same distance / step count, for the stride fallback.
    private func evenSteps(_ count: Int, meters: Double, steps: Double) -> ([Int: Double], [Int: Double]) {
        var distance: [Int: Double] = [:]
        var stepCounts: [Int: Double] = [:]
        for index in 0..<count {
            distance[index] = meters
            stepCounts[index] = steps
        }
        return (distance, stepCounts)
    }

    private func stride(
        _ input: WorkoutMetricSeriesData,
        type: BodyWorkoutType = .running,
        unit: BodyValueFormat.DistanceUnitPreference = .kilometers
    ) -> WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.strideLength(
            data: input,
            type: type,
            distanceUnitPreference: unit,
            locale: enUS
        )
    }

    private func paceOrSpeed(
        _ input: WorkoutMetricSeriesData,
        type: BodyWorkoutType,
        unit: BodyValueFormat.DistanceUnitPreference = .kilometers
    ) -> WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.paceOrSpeed(
            data: input,
            type: type,
            distanceUnitPreference: unit,
            locale: enUS
        )
    }

    private func cadence(
        _ input: WorkoutMetricSeriesData,
        type: BodyWorkoutType,
        unit: BodyValueFormat.DistanceUnitPreference = .kilometers
    ) -> WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.cadence(
            data: input,
            type: type,
            distanceUnitPreference: unit,
            locale: enUS
        )
    }

    // MARK: - Stride: source selection

    func testNativeIsPreferredOverFallbackWhenThreeBucketsExist() throws {
        let fallback = evenSteps(8, meters: 50, steps: 100)
        let presentation = try XCTUnwrap(stride(data(
            distance: fallback.0,
            steps: fallback.1,
            stride: series([native(0, 1.0), native(1, 1.1), native(2, 1.2)])
        )))

        XCTAssertEqual(presentation.source, .native)
        XCTAssertEqual(presentation.bars.count, 3)
        // Bucket-derived mean of the native averages, not the 0.50 m fallback stride.
        XCTAssertEqual(presentation.averageText, "1.10")
    }

    func testFallbackIsUsedWhenNativeHasTooFewBuckets() throws {
        let fallback = evenSteps(5, meters: 50, steps: 100)
        let presentation = try XCTUnwrap(stride(data(
            distance: fallback.0,
            steps: fallback.1,
            stride: series([native(0, 1.0), native(1, 1.1)])
        )))

        XCTAssertEqual(presentation.source, .computed)
        XCTAssertEqual(presentation.bars.count, 5)
        XCTAssertEqual(presentation.averageText, "0.50")
    }

    func testReturnsNilWhenNeitherPathHasThreeUsableBuckets() {
        let fallback = evenSteps(2, meters: 50, steps: 100)
        XCTAssertNil(stride(data(
            distance: fallback.0,
            steps: fallback.1,
            stride: series([native(0, 1.0), native(1, 1.1)])
        )))
        XCTAssertNil(stride(.empty))
    }

    func testStrideIsNotBuiltForActivitiesWithoutStepCadence() {
        XCTAssertNil(stride(
            data(stride: series([native(0, 1.0), native(1, 1.1), native(2, 1.2)])),
            type: .cycling
        ))
    }

    // MARK: - Stride: statistics

    func testNativeSessionStatisticsAreUsedWhenPresent() throws {
        let presentation = try XCTUnwrap(stride(data(
            stride: series(
                [native(0, 1.0), native(1, 1.1), native(2, 1.2)],
                sessionAverage: 1.25,
                sessionMax: 1.6
            )
        )))

        XCTAssertEqual(presentation.averageText, "1.25")
        XCTAssertEqual(presentation.extremeText, "1.60")
    }

    func testNativeStatisticsFallBackToBucketsWhenSessionStatsMissing() throws {
        let presentation = try XCTUnwrap(stride(data(
            stride: series([native(0, 1.0), native(1, 1.1), native(2, 1.2)])
        )))

        XCTAssertEqual(presentation.averageText, "1.10")
        XCTAssertEqual(presentation.extremeText, "1.20")
    }

    func testComputedAverageIsTotalMetersOverTotalSteps() throws {
        let presentation = try XCTUnwrap(stride(data(
            distance: [0: 100, 1: 120, 2: 60],
            steps: [0: 100, 1: 100, 2: 100]
        )))

        XCTAssertEqual(presentation.source, .computed)
        // 280 m / 300 steps — not the mean of the three bucket strides.
        XCTAssertEqual(presentation.averageText, "0.93")
        XCTAssertEqual(presentation.extremeText, "1.20")
    }

    // MARK: - Stride: validation

    func testInvalidNativeBucketsAreDropped() throws {
        let presentation = try XCTUnwrap(stride(data(
            stride: series([
                native(0, 1.0),
                native(1, .nan),
                native(2, 1.1),
                native(3, 10.0),
                native(4, 0.05),
                native(5, 1.2)
            ])
        )))

        XCTAssertEqual(presentation.source, .native)
        XCTAssertEqual(presentation.bars.map(\.id), [0, 2, 5])
        XCTAssertEqual(presentation.averageText, "1.10")
    }

    func testInvalidFallbackBucketsAreDropped() throws {
        let presentation = try XCTUnwrap(stride(data(
            distance: [0: 100, 1: 4, 2: 100, 3: .nan, 4: 0, 5: 500, 6: 100],
            steps: [0: 100, 1: 5, 2: 100, 3: 100, 4: 100, 5: 100, 6: 100]
        )))

        XCTAssertEqual(presentation.bars.map(\.id), [0, 2, 6])
        XCTAssertEqual(presentation.averageText, "1.00")
    }

    func testNativeRangeIsClampedAroundTheBucketAverage() throws {
        let presentation = try XCTUnwrap(stride(data(
            stride: series(
                [native(0, 1.0, 0.05, 9.0), native(1, 1.0, 1.5, 0.5), native(2, 1.0)],
                sessionMax: 1.0
            )
        )))

        let first = try XCTUnwrap(presentation.bars.first)
        // 0.05 m clamps to 0.2 m and 9.0 m to 3.0 m; the axis then grows to fit the bar.
        XCTAssertEqual(presentation.axisTopValue, 3.3, accuracy: 0.0001)
        XCTAssertEqual(first.lowFraction, 0.2 / presentation.axisTopValue, accuracy: 0.0001)
        XCTAssertEqual(first.highFraction, 3.0 / presentation.axisTopValue, accuracy: 0.0001)
        // A range that brackets the average the wrong way collapses onto it.
        let second = presentation.bars[1]
        XCTAssertEqual(second.lowFraction, second.valueFraction, accuracy: 0.0001)
        XCTAssertEqual(second.highFraction, second.valueFraction, accuracy: 0.0001)
    }

    // MARK: - Geometry

    func testGapBucketsProduceNoBarAndDoNotShiftPositions() throws {
        let presentation = try XCTUnwrap(stride(data(
            bucketSeconds: 60,
            duration: 600,
            stride: series([native(0, 1.0), native(1, 1.0), native(5, 1.0)])
        )))

        XCTAssertEqual(presentation.bars.map(\.id), [0, 1, 5])
        let last = try XCTUnwrap(presentation.bars.last)
        XCTAssertEqual(last.xStart, 0.5, accuracy: 0.0001)
        XCTAssertEqual(last.xEnd, 0.6, accuracy: 0.0001)
    }

    func testFinalBucketIsClampedToTheEndOfTheTimeline() throws {
        let presentation = try XCTUnwrap(stride(data(
            bucketSeconds: 60,
            duration: 150,
            stride: series([native(0, 1.0), native(1, 1.0), native(2, 1.0)])
        )))

        let last = try XCTUnwrap(presentation.bars.last)
        XCTAssertEqual(last.xStart, 120.0 / 150.0, accuracy: 0.0001)
        XCTAssertEqual(last.xEnd, 1.0, accuracy: 0.0001)
    }

    func testComputedBarsHaveNoRange() throws {
        let fallback = evenSteps(3, meters: 100, steps: 100)
        let presentation = try XCTUnwrap(stride(data(distance: fallback.0, steps: fallback.1)))

        for bar in presentation.bars {
            XCTAssertEqual(bar.lowFraction, bar.valueFraction)
            XCTAssertEqual(bar.highFraction, bar.valueFraction)
        }
    }

    // MARK: - Axis

    func testAxisTopRoundsUpToFiveCentimeters() throws {
        let presentation = try XCTUnwrap(stride(data(
            stride: series([native(0, 1.0), native(1, 1.05), native(2, 1.13)])
        )))

        // 1.13 × 1.1 = 1.243 → next 0.05 step.
        XCTAssertEqual(presentation.axisTopValue, 1.25, accuracy: 0.0001)
    }

    func testAxisTopHasAMinimumOfHalfAUnit() throws {
        let presentation = try XCTUnwrap(stride(data(
            stride: series([native(0, 0.3), native(1, 0.35), native(2, 0.4)])
        )))

        XCTAssertEqual(presentation.axisTopValue, 0.5, accuracy: 0.0001)
    }

    func testYAxisLabelsAreFourTwoDecimalValuesBottomToTop() throws {
        let presentation = try XCTUnwrap(stride(data(
            stride: series([native(0, 1.0), native(1, 1.05), native(2, 1.13)])
        )))

        XCTAssertEqual(presentation.yAxisFractions.count, 4)
        XCTAssertEqual(presentation.yAxisLabels, ["0.00", "0.42", "0.83", "1.25"])
    }

    func testTimeMarksLabelStartMiddleAndEnd() throws {
        let presentation = try XCTUnwrap(stride(data(
            duration: 3_662,
            stride: series([native(0, 1.0), native(1, 1.0), native(2, 1.0)])
        )))

        XCTAssertEqual(presentation.timeMarks.map(\.fraction), [0, 0.5, 1])
        XCTAssertEqual(presentation.timeMarks.map(\.label), ["00:00:00", "00:30:31", "01:01:02"])
    }

    // MARK: - Stride units

    func testMetersPerStepIsTheDefaultUnit() throws {
        let presentation = try XCTUnwrap(stride(data(
            stride: series(
                [native(0, 1.0), native(1, 1.0), native(2, 1.0)],
                sessionAverage: 1.0,
                sessionMax: 1.0
            )
        )))

        XCTAssertEqual(presentation.title, "Stride Length")
        XCTAssertEqual(presentation.unitText, "m/step")
        XCTAssertEqual(presentation.averageText, "1.00")
        XCTAssertEqual(presentation.extremeText, "1.00")
    }

    func testMilesPreferenceConvertsToFeetPerStep() throws {
        let input = data(
            stride: series(
                [native(0, 1.0), native(1, 1.0), native(2, 1.0)],
                sessionAverage: 1.0,
                sessionMax: 1.0
            )
        )
        let presentation = try XCTUnwrap(stride(input, unit: .miles))

        XCTAssertEqual(presentation.unitText, "ft/step")
        XCTAssertEqual(presentation.averageText, "3.28")
        XCTAssertEqual(presentation.extremeText, "3.28")
        // 3.2808 ft × 1.1 = 3.609 → next 0.2 step.
        XCTAssertEqual(presentation.axisTopValue, 3.8, accuracy: 0.0001)
        XCTAssertEqual(
            presentation.accessibilitySummary,
            "Stride length, average 3.28 ft/step, maximum 3.28 ft/step"
        )
        // Validation happens in meters, so the same buckets survive either unit.
        XCTAssertEqual(presentation.bars.map(\.id), try XCTUnwrap(stride(input)).bars.map(\.id))
    }

    // MARK: - Pace

    private var paceInput: WorkoutMetricSeriesData {
        data(
            activeSeconds: [0: 60, 1: 60, 2: 54],
            distance: [0: 200, 1: 250, 2: 150]
        )
    }

    func testPaceUsesTheBestBucketAsItsExtreme() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(paceInput, type: .running))

        XCTAssertEqual(presentation.title, "Pace")
        XCTAssertEqual(presentation.averageCaption, "Avg Pace")
        XCTAssertEqual(presentation.extremeCaption, "Best Pace")
        XCTAssertEqual(presentation.unitText, "min/km")
        // 600 m in 174 s → 4:50 /km; the fastest bucket is 250 m in 60 s → 4:00 /km.
        XCTAssertEqual(presentation.averageText, "4:50")
        XCTAssertEqual(presentation.extremeText, "4:00")
        XCTAssertEqual(
            presentation.accessibilitySummary,
            "Pace, average 4:50 min/km, best 4:00 min/km"
        )
    }

    func testPaceAxisScalesToTheSlowestBucketAndLabelsAreClockText() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(paceInput, type: .running))

        // Slowest bucket is 6:00 /km → 6.0 × 1.1 = 6.6 → next 0.5 step.
        XCTAssertEqual(presentation.axisTopValue, 7.0, accuracy: 0.0001)
        XCTAssertEqual(presentation.yAxisLabels, ["0:00", "2:20", "4:40", "7:00"])
    }

    func testPaceAxisHasAMinimumOfThreeMinutesPerKilometer() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(
            data(
                activeSeconds: [0: 60, 1: 60, 2: 60],
                distance: [0: 400, 1: 400, 2: 400]
            ),
            type: .running
        ))

        // 2:30 /km × 1.1 = 2.75 → 3.0 is both the rounded step and the floor.
        XCTAssertEqual(presentation.axisTopValue, 3.0, accuracy: 0.0001)
    }

    func testPaceUsesEachBucketsActiveSecondsIncludingAPartialLastBucket() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(
            data(
                bucketSeconds: 60,
                duration: 192,
                activeSeconds: [0: 60, 1: 60, 2: 60, 3: 12],
                distance: [0: 200, 1: 200, 2: 200, 3: 40]
            ),
            type: .running
        ))

        XCTAssertEqual(presentation.bars.map(\.id), [0, 1, 2, 3])
        // 40 m in the final 12 s is the same 5:00 /km as a full bucket, not 25:00.
        let last = try XCTUnwrap(presentation.bars.last)
        XCTAssertEqual(last.valueFraction, presentation.bars[0].valueFraction, accuracy: 0.0001)
        XCTAssertEqual(presentation.averageText, "5:00")
    }

    func testPausedBucketsWithoutActiveSecondsProduceNoBar() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(
            data(
                activeSeconds: [0: 60, 1: 60, 3: 60],
                distance: [0: 200, 1: 200, 2: 200, 3: 200]
            ),
            type: .running
        ))

        XCTAssertEqual(presentation.bars.map(\.id), [0, 1, 3])
    }

    func testShortOrNearlyStationaryBucketsAreDropped() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(
            data(
                activeSeconds: [0: 60, 1: 5, 2: 60, 3: 60, 4: 60],
                distance: [0: 200, 1: 200, 2: 10, 3: 200, 4: 200]
            ),
            type: .running
        ))

        // Bucket 1 has under 10 s of active time; bucket 2 under 20 m of distance.
        XCTAssertEqual(presentation.bars.map(\.id), [0, 3, 4])
    }

    func testMilesPreferenceShowsMinutesPerMile() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(paceInput, type: .running, unit: .miles))

        XCTAssertEqual(presentation.unitText, "min/mi")
        // 4:50 /km → 7:47 /mi.
        XCTAssertEqual(presentation.averageText, "7:47")
        XCTAssertEqual(presentation.extremeText, "6:26")
        // Same buckets in either unit — validation is in seconds per meter.
        XCTAssertEqual(
            presentation.bars.map(\.id),
            try XCTUnwrap(paceOrSpeed(paceInput, type: .running)).bars.map(\.id)
        )
    }

    func testPaceIsNotBuiltForActivitiesWithoutDistancePace() {
        XCTAssertNil(paceOrSpeed(paceInput, type: .swimming))
        XCTAssertNil(paceOrSpeed(paceInput, type: .yoga))
    }

    // MARK: - Speed

    private var speedInput: WorkoutMetricSeriesData {
        data(
            activeSeconds: [0: 60, 1: 60, 2: 60],
            distance: [0: 300, 1: 400, 2: 200]
        )
    }

    func testCyclingUsesSpeedInKilometersPerHour() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(speedInput, type: .cycling))

        XCTAssertEqual(presentation.title, "Speed")
        XCTAssertEqual(presentation.averageCaption, "Avg Speed")
        XCTAssertEqual(presentation.extremeCaption, "Max Speed")
        XCTAssertEqual(presentation.unitText, "km/h")
        // 900 m in 180 s = 5 m/s = 18 km/h; the quickest bucket is 24 km/h.
        XCTAssertEqual(presentation.averageText, "18.0")
        XCTAssertEqual(presentation.extremeText, "24.0")
        XCTAssertEqual(presentation.axisTopValue, 30, accuracy: 0.0001)
        XCTAssertEqual(
            presentation.accessibilitySummary,
            "Speed, average 18.0 km/h, maximum 24.0 km/h"
        )
    }

    func testCyclingSpeedConvertsToMilesPerHour() throws {
        let presentation = try XCTUnwrap(paceOrSpeed(speedInput, type: .cycling, unit: .miles))

        XCTAssertEqual(presentation.unitText, "mph")
        XCTAssertEqual(presentation.averageText, "11.2")
        XCTAssertEqual(presentation.extremeText, "14.9")
        XCTAssertEqual(presentation.axisTopValue, 20, accuracy: 0.0001)
    }

    func testSpeedAxisFloorsDifferPerUnit() throws {
        let slow = data(
            activeSeconds: [0: 60, 1: 60, 2: 60],
            distance: [0: 60, 1: 60, 2: 60]
        )

        XCTAssertEqual(try XCTUnwrap(paceOrSpeed(slow, type: .cycling)).axisTopValue, 20, accuracy: 0.0001)
        XCTAssertEqual(
            try XCTUnwrap(paceOrSpeed(slow, type: .cycling, unit: .miles)).axisTopValue,
            15,
            accuracy: 0.0001
        )
    }

    // MARK: - Cadence

    func testFootCadenceIsStepsPerMinute() throws {
        let presentation = try XCTUnwrap(cadence(
            data(
                activeSeconds: [0: 60, 1: 60, 2: 60],
                steps: [0: 160, 1: 180, 2: 150]
            ),
            type: .running
        ))

        XCTAssertEqual(presentation.source, .computed)
        XCTAssertEqual(presentation.title, "Cadence")
        XCTAssertEqual(presentation.unitText, "spm")
        // 490 steps over 180 s → 163 spm; the busiest bucket is 180 spm.
        XCTAssertEqual(presentation.averageText, "163")
        XCTAssertEqual(presentation.extremeText, "180")
        XCTAssertEqual(presentation.axisTopValue, 200, accuracy: 0.0001)
        XCTAssertEqual(
            presentation.accessibilitySummary,
            "Cadence, average 163 spm, maximum 180 spm"
        )
    }

    func testFootCadenceDropsShortAndNearlyStillBuckets() throws {
        let presentation = try XCTUnwrap(cadence(
            data(
                activeSeconds: [0: 60, 1: 5, 2: 60, 3: 60, 4: 60, 5: 60],
                steps: [0: 60, 1: 60, 2: 4, 3: 60, 4: 500, 5: 50]
            ),
            type: .running
        ))

        // Bucket 1 is too short, bucket 2 has too few steps, bucket 4 is 500 spm.
        XCTAssertEqual(presentation.bars.map(\.id), [0, 3, 5])
        // 60 spm × 1.1 = 66 → the 100 spm floor wins.
        XCTAssertEqual(presentation.axisTopValue, 100, accuracy: 0.0001)
    }

    func testCyclingCadenceUsesTheNativeRevolutionsPerMinuteSeries() throws {
        let presentation = try XCTUnwrap(cadence(
            data(cyclingCadence: series(
                [native(0, 80), native(1, 90), native(2, 85)],
                sessionAverage: 85,
                sessionMax: 95
            )),
            type: .cycling
        ))

        XCTAssertEqual(presentation.source, .native)
        XCTAssertEqual(presentation.title, "Cadence")
        XCTAssertEqual(presentation.unitText, "rpm")
        XCTAssertEqual(presentation.averageText, "85")
        XCTAssertEqual(presentation.extremeText, "95")
        XCTAssertEqual(presentation.axisTopValue, 110, accuracy: 0.0001)
        XCTAssertEqual(
            presentation.accessibilitySummary,
            "Cycling cadence, average 85 rpm, maximum 95 rpm"
        )
    }

    func testCyclingCadenceIsNilWithoutANativeSeries() {
        XCTAssertNil(cadence(data(activeSeconds: [0: 60], steps: [0: 160]), type: .cycling))
    }

    // MARK: - Ground contact time

    private func groundContact(
        _ input: WorkoutMetricSeriesData,
        unit: BodyValueFormat.DistanceUnitPreference = .kilometers
    ) -> WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.groundContactTime(
            data: input,
            type: .running,
            distanceUnitPreference: unit,
            locale: enUS
        )
    }

    func testGroundContactTimeIsMillisecondsWithAThreeHundredFloor() throws {
        let presentation = try XCTUnwrap(groundContact(data(groundContact: series(
            [native(0, 240), native(1, 260), native(2, 250)],
            sessionAverage: 250,
            sessionMax: 300
        ))))

        XCTAssertEqual(presentation.title, "Ground Contact Time")
        XCTAssertEqual(presentation.averageCaption, "Avg Ground Contact")
        XCTAssertEqual(presentation.extremeCaption, "Max Ground Contact")
        XCTAssertEqual(presentation.unitText, "ms")
        XCTAssertEqual(presentation.averageText, "250")
        XCTAssertEqual(presentation.extremeText, "300")
        XCTAssertEqual(presentation.axisTopValue, 350, accuracy: 0.0001)
        XCTAssertEqual(
            presentation.accessibilitySummary,
            "Ground contact time, average 250 ms, maximum 300 ms"
        )
    }

    func testGroundContactTimeDropsImplausibleBuckets() throws {
        let presentation = try XCTUnwrap(groundContact(data(groundContact: series([
            native(0, 240),
            native(1, 50),
            native(2, 700),
            native(3, 260),
            native(4, 250)
        ]))))

        XCTAssertEqual(presentation.bars.map(\.id), [0, 3, 4])
        XCTAssertEqual(presentation.axisTopValue, 300, accuracy: 0.0001)
    }

    func testGroundContactTimeIsNilWithoutANativeSeries() {
        XCTAssertNil(groundContact(data()))
    }

    // MARK: - Vertical oscillation

    private func verticalOscillation(
        _ input: WorkoutMetricSeriesData,
        unit: BodyValueFormat.DistanceUnitPreference = .kilometers
    ) -> WorkoutBucketedSeriesPresentation? {
        WorkoutMetricSeriesCharts.verticalOscillation(
            data: input,
            type: .running,
            distanceUnitPreference: unit,
            locale: enUS
        )
    }

    func testVerticalOscillationIsCentimeters() throws {
        let presentation = try XCTUnwrap(verticalOscillation(data(verticalOscillation: series(
            [native(0, 8.0), native(1, 9.0), native(2, 10.0)],
            sessionMax: 10.0
        ))))

        XCTAssertEqual(presentation.title, "Vertical Oscillation")
        XCTAssertEqual(presentation.averageCaption, "Avg Vertical Osc.")
        XCTAssertEqual(presentation.extremeCaption, "Max Vertical Osc.")
        XCTAssertEqual(presentation.unitText, "cm")
        XCTAssertEqual(presentation.averageText, "9.0")
        XCTAssertEqual(presentation.extremeText, "10.0")
        XCTAssertEqual(presentation.axisTopValue, 11, accuracy: 0.0001)
        XCTAssertEqual(
            presentation.accessibilitySummary,
            "Vertical oscillation, average 9.0 cm, maximum 10.0 cm"
        )
    }

    func testVerticalOscillationConvertsToInches() throws {
        let input = data(verticalOscillation: series(
            [native(0, 8.0), native(1, 9.0), native(2, 10.0)],
            sessionMax: 10.0
        ))
        let presentation = try XCTUnwrap(verticalOscillation(input, unit: .miles))

        XCTAssertEqual(presentation.unitText, "in")
        XCTAssertEqual(presentation.averageText, "3.5")
        XCTAssertEqual(presentation.extremeText, "3.9")
        XCTAssertEqual(presentation.axisTopValue, 4.5, accuracy: 0.0001)
        // Centimeters are validated before conversion, so both units show the same bars.
        XCTAssertEqual(
            presentation.bars.map(\.id),
            try XCTUnwrap(verticalOscillation(input)).bars.map(\.id)
        )
    }

    func testVerticalOscillationDropsImplausibleBucketsAndFloorsItsAxis() throws {
        let presentation = try XCTUnwrap(verticalOscillation(data(verticalOscillation: series([
            native(0, 8.0),
            native(1, 1.0),
            native(2, 25.0),
            native(3, 8.5),
            native(4, 9.0)
        ]))))

        XCTAssertEqual(presentation.bars.map(\.id), [0, 3, 4])
        // 9.0 × 1.1 = 9.9 → the 10 cm floor wins.
        XCTAssertEqual(presentation.axisTopValue, 10, accuracy: 0.0001)
    }

    // MARK: - Duration formatting

    func testPaddedStopwatchDurationTextIsAlwaysHoursMinutesSeconds() {
        XCTAssertEqual(BodyValueFormat.paddedStopwatchDurationText(for: 0), "00:00:00")
        XCTAssertEqual(BodyValueFormat.paddedStopwatchDurationText(for: 1_831), "00:30:31")
        XCTAssertEqual(BodyValueFormat.paddedStopwatchDurationText(for: 3_662), "01:01:02")
        XCTAssertEqual(BodyValueFormat.paddedStopwatchDurationText(for: 36_000), "10:00:00")
        XCTAssertEqual(BodyValueFormat.paddedStopwatchDurationText(for: -5), "00:00:00")
    }
}
