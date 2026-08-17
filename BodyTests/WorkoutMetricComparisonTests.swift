//
//  WorkoutMetricComparisonTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutMetricComparisonTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    private func workout(
        id: UUID = UUID(),
        type: BodyWorkoutType = .running,
        start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        duration: TimeInterval = 1800,
        distance: Double? = nil,
        activeEnergy: Double? = nil,
        avgHR: Double? = nil,
        elevation: Double? = nil,
        humidity: Double? = nil,
        averageMETs: Double? = nil,
        heartRateRecovery: Double? = nil,
        hrSamples: [WorkoutHeartRateSample] = []
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            type: type,
            startDate: start,
            duration: duration,
            activeEnergyKilocalories: activeEnergy,
            distanceMeters: distance,
            averageHeartRateBeatsPerMinute: avgHR,
            heartRateSamples: hrSamples,
            elevationAscendedMeters: elevation,
            weatherHumidityPercent: humidity,
            averageMETs: averageMETs,
            heartRateRecoveryBPM: heartRateRecovery
        )
    }

    private func hrSamples(_ values: [Double]) -> [WorkoutHeartRateSample] {
        values.enumerated().map {
            WorkoutHeartRateSample(
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double($0.offset)),
                beatsPerMinute: $0.element
            )
        }
    }

    private func comparison(
        _ kind: WorkoutDetailMetric.Kind,
        current: WorkoutSummary,
        priors: [WorkoutSummary],
        isComplete: Bool = true,
        locale: Locale? = nil
    ) -> WorkoutMetricComparison? {
        WorkoutMetricComparisonBuilder.comparison(
            for: kind,
            current: current,
            priors: priors,
            isComplete: isComplete,
            locale: locale ?? enUS
        )
    }

    // MARK: - Simple-mean metrics

    func testHigherThanBaselineShowsUpArrowAndSpokenLabel() {
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        let result = comparison(.activeEnergy, current: current, priors: priors)
        XCTAssertEqual(result?.badgeText, "↑50%")
        XCTAssertEqual(result?.accessibilityLabel, "50 percent higher than 30-day average")
    }

    func testLowerThanBaselineShowsDownArrow() {
        let current = workout(activeEnergy: 150)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertEqual(comparison(.activeEnergy, current: current, priors: priors)?.badgeText, "↓25%")
    }

    func testRoundsToZeroShowsApproximately() {
        let current = workout(activeEnergy: 200)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertEqual(comparison(.activeEnergy, current: current, priors: priors)?.badgeText, "≈0%")
    }

    // MARK: - Session-context metrics

    func testAverageMETsComparesAgainstTheThirtyDayAverage() {
        let current = workout(averageMETs: 9)
        let priors = [workout(averageMETs: 6), workout(averageMETs: 6), workout(averageMETs: 6)]
        XCTAssertEqual(comparison(.averageMETs, current: current, priors: priors)?.badgeText, "↑50%")
        // Below the 3-prior floor there is no badge, same as every other metric.
        XCTAssertNil(comparison(.averageMETs, current: current, priors: Array(priors.prefix(2))))
    }

    func testHumidityComparesAgainstTheThirtyDayAverage() {
        let current = workout(humidity: 90)
        let priors = [workout(humidity: 60), workout(humidity: 60), workout(humidity: 60)]
        XCTAssertEqual(comparison(.humidity, current: current, priors: priors)?.badgeText, "↑50%")
        XCTAssertNil(comparison(.humidity, current: current, priors: Array(priors.prefix(2))))
    }

    /// Zero humidity is a real reading (unlike a zero distance, which means
    /// "not recorded"), so it stays comparable.
    func testZeroHumidityIsStillComparable() {
        XCTAssertEqual(
            WorkoutMetricComparisonBuilder.scalar(for: .humidity, from: workout(humidity: 0)),
            0
        )
        let current = workout(humidity: 0)
        let priors = [workout(humidity: 60), workout(humidity: 60), workout(humidity: 60)]
        XCTAssertEqual(comparison(.humidity, current: current, priors: priors)?.badgeText, "↓100%")
    }

    func testHeartRateRecoveryComparesAgainstTheThirtyDayAverage() {
        let current = workout(heartRateRecovery: 45)
        let priors = [
            workout(heartRateRecovery: 30),
            workout(heartRateRecovery: 30),
            workout(heartRateRecovery: 30)
        ]
        XCTAssertEqual(comparison(.heartRateRecovery, current: current, priors: priors)?.badgeText, "↑50%")
        XCTAssertNil(comparison(.heartRateRecovery, current: current, priors: Array(priors.prefix(2))))
    }

    func testSessionContextMetricsGetTheCalculatingStandIn() {
        let current = workout(humidity: 0, averageMETs: 8.4, heartRateRecovery: 32)
        for kind in [WorkoutDetailMetric.Kind.humidity, .averageMETs, .heartRateRecovery] {
            XCTAssertEqual(
                WorkoutMetricComparisonBuilder.placeholder(
                    for: kind,
                    availability: .calculating,
                    current: current,
                    locale: enUS
                )?.badgeText,
                "0%",
                "\(kind) must show the stand-in while the history loads"
            )
        }
    }

    // MARK: - Sparse vs loading

    func testNoBadgeWhenCompleteButBelowSampleFloor() {
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200)] // only 2
        XCTAssertNil(comparison(.activeEnergy, current: current, priors: priors, isComplete: true))
    }

    func testNoCaptionWhileStillLoading() {
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertNil(comparison(.activeEnergy, current: current, priors: priors, isComplete: false))
    }

    func testNoCaptionWhileLoadingEvenWithEnoughPriors() {
        // A spanned month is still loading (isComplete == false) but already-loaded
        // months / the launch-seeded snapshot supply 3+ priors. The partial average
        // must stay hidden, not show an inaccurate caption.
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertNil(comparison(.activeEnergy, current: current, priors: priors, isComplete: false))
    }

    func testAbsentCurrentMetricProducesNoCaption() {
        let current = workout(elevation: nil)
        let priors = [workout(elevation: 100), workout(elevation: 100), workout(elevation: 100)]
        XCTAssertNil(comparison(.elevation, current: current, priors: priors))
    }

    // MARK: - Avg HR display fallback (samples when the stored average is absent)

    func testCurrentAvgHRFallsBackToSamplesLikeTheTile() {
        // Stored average is nil but the samples average to 180 — the tile shows 180,
        // so the comparison must use 180 too (baseline 120 → +50%), not read the metric
        // as absent and suppress the badge.
        let current = workout(avgHR: nil, hrSamples: hrSamples([180, 180]))
        let priors = [workout(avgHR: 120), workout(avgHR: 120), workout(avgHR: 120)]
        XCTAssertEqual(comparison(.avgHeartRate, current: current, priors: priors)?.badgeText, "↑50%")
    }

    func testSamplesOnlyPriorCountsTowardBaselineAndSampleFloor() {
        // Two priors carry a stored average; the third has only samples. All three are
        // displayed heart rate, so all three must count — reaching the sample floor and
        // shaping the baseline (100). Reading the stored field alone would leave 2
        // qualifying priors, dropping below the floor and showing no badge at all.
        let current = workout(avgHR: 150)
        let priors = [
            workout(avgHR: 100),
            workout(avgHR: 100),
            workout(avgHR: nil, hrSamples: hrSamples([100, 100]))
        ]
        XCTAssertEqual(comparison(.avgHeartRate, current: current, priors: priors)?.badgeText, "↑50%")
    }

    // MARK: - Rate metrics (aggregate ratio of totals)

    func testSpeedUsesAggregateRatioNotMeanOrDistanceWeighted() {
        // Aggregate = 21000m / 4100s = 5.122 m/s → current 5.0 m/s → -2%.
        // A naive mean of speeds would be 6.667 m/s (-25%); a distance-weighted
        // mean would be 5.238 m/s (-5%). Only the aggregate ratio yields "↓ 2%".
        let priors = [
            workout(type: .cycling, duration: 2000, distance: 10000),
            workout(type: .cycling, duration: 2000, distance: 10000),
            workout(type: .cycling, duration: 100, distance: 1000)
        ]
        let current = workout(type: .cycling, duration: 2000, distance: 10000) // 5.0 m/s
        XCTAssertEqual(comparison(.speed, current: current, priors: priors)?.badgeText, "↓2%")
    }

    func testPaceFasterShowsDownArrow() {
        // Baseline 0.36 s/m; current 0.30 s/m (faster) → lower number → down arrow.
        let priors = [
            workout(duration: 360, distance: 1000),
            workout(duration: 360, distance: 1000),
            workout(duration: 360, distance: 1000)
        ]
        let current = workout(duration: 300, distance: 1000)
        XCTAssertEqual(comparison(.pace, current: current, priors: priors)?.badgeText, "↓17%")
    }

    func testSubFloorPriorExcludedFromRateBaseline() {
        // 3 valid runs → 0.30 s/m; current 0.36 s/m → +20%. If the 100m sub-floor
        // prior were included the baseline would shift and give +16%.
        let priors = [
            workout(duration: 300, distance: 1000),
            workout(duration: 300, distance: 1000),
            workout(duration: 300, distance: 1000),
            workout(duration: 60, distance: 100) // below 400m land floor
        ]
        let current = workout(duration: 360, distance: 1000)
        XCTAssertEqual(comparison(.pace, current: current, priors: priors)?.badgeText, "↑20%")
    }

    func testSubFloorAndZeroPriorsDoNotCountTowardSampleFloor() {
        // Only 2 qualifying runs; a sub-floor and a zero-distance prior must not
        // lift the eligible count to the minimum of 3.
        let priors = [
            workout(duration: 300, distance: 1000),
            workout(duration: 300, distance: 1000),
            workout(duration: 60, distance: 100),  // sub-floor
            workout(duration: 300, distance: 0)     // zero distance
        ]
        let current = workout(duration: 360, distance: 1000)
        XCTAssertNil(comparison(.pace, current: current, priors: priors, isComplete: true))
    }

    func testSwimUsesSmallerFloorThanLandRate() {
        // 150m swims clear the 100m swim floor (they'd fail the 400m land floor).
        // Baseline 1.333 s/m; current 1.467 s/m → +10%.
        let priors = [
            workout(type: .swimming, duration: 200, distance: 150),
            workout(type: .swimming, duration: 200, distance: 150),
            workout(type: .swimming, duration: 200, distance: 150)
        ]
        let current = workout(type: .swimming, duration: 220, distance: 150)
        XCTAssertEqual(comparison(.swimPace, current: current, priors: priors)?.badgeText, "↑10%")
    }

    // MARK: - Hardening

    func testHugeDeltaClampsWithoutCrashing() {
        // A near-zero baseline would overflow the percentage; it must clamp to 999
        // rather than trap in Int(...).
        let current = workout(avgHR: 150)
        let priors = [workout(avgHR: 0.000001), workout(avgHR: 0.000001), workout(avgHR: 0.000001)]
        XCTAssertEqual(comparison(.avgHeartRate, current: current, priors: priors)?.badgeText, "↑999%")
    }

    func testPercentDigitsAreLocalized() {
        let current = workout(activeEnergy: 150)
        let priors = [workout(activeEnergy: 100), workout(activeEnergy: 100), workout(activeEnergy: 100)]
        let arabic = Locale(identifier: "ar")
        let result = comparison(.activeEnergy, current: current, priors: priors, locale: arabic)
        let localizedFifty = BodyValueFormat.numberText(50, decimals: 0, locale: arabic)
        XCTAssertEqual(result?.badgeText, "↑\(localizedFifty)%")
    }

    // MARK: - Store completeness (loaded state, not snapshot membership)

    @MainActor
    func testComparisonContextTreatsSeededButUnloadedMonthAsIncomplete() {
        let type = BodyWorkoutType.running
        let priors = [
            workout(type: type, start: date(2026, 5, 5), distance: 5000),
            workout(type: type, start: date(2026, 5, 10), distance: 5000),
            workout(type: type, start: date(2026, 5, 15), distance: 5000)
        ]
        let snapshot = WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: priors, calendar: .bodyGregorian)
        let store = HealthKitWorkoutStore(initialSnapshot: snapshot, initialPermissionSelection: .defaultValue)

        let current = workout(type: type, start: date(2026, 5, 31), distance: 5000)
        let context = store.comparisonContext(for: current)

        // The month is seeded into `monthSnapshots` but never entered `loadedMonthKeys`.
        XCTAssertFalse(store.hasLoadedSnapshot(month: 5, year: 2026))
        XCTAssertFalse(context.isComplete)
        // Filtering still surfaces the same-type priors from the seeded snapshot.
        XCTAssertEqual(context.priorWorkouts.count, 3)
        XCTAssertTrue(context.priorWorkouts.allSatisfy { $0.type == type })
    }

    // MARK: - Card state and "0%" stand-ins

    private func availability(
        current: WorkoutSummary,
        priors: [WorkoutSummary],
        kinds: [WorkoutDetailMetric.Kind] = [.activeEnergy],
        isComplete: Bool,
        isSettled: Bool
    ) -> WorkoutMetricComparisonAvailability? {
        let hasComparison = kinds.contains { kind in
            comparison(kind, current: current, priors: priors, isComplete: isComplete) != nil
        }
        return WorkoutMetricComparisonBuilder.availability(
            for: kinds,
            current: current,
            hasComparison: hasComparison,
            isComplete: isComplete,
            isSettled: isSettled
        )
    }

    func testStillLoadingReadsAsCalculating() {
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertEqual(availability(current: current, priors: priors, isComplete: false, isSettled: false), .calculating)
    }

    func testIncompleteButSettledReadsAsInsufficientHistory() {
        // The months can't load at all (permission off, Health unavailable, a failed
        // fetch), so `isComplete` never turns true. Without the settled signal the card
        // would sit on "Calculating…" forever.
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertEqual(
            availability(current: current, priors: priors, isComplete: false, isSettled: true),
            .insufficientHistory
        )
    }

    func testCompleteButBelowSampleFloorReadsAsInsufficientHistory() {
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertEqual(
            availability(current: current, priors: priors, isComplete: true, isSettled: true),
            .insufficientHistory
        )
    }

    func testMeasuredMetricReadsAsReady() {
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertEqual(availability(current: current, priors: priors, isComplete: true, isSettled: true), .ready)
    }

    func testWorkoutWithNothingComparableGetsNoLegend() {
        // Every tile would read "No Data", so the card keeps its clean look: no legend
        // and (below) no stand-ins either. The session-context kinds are comparable
        // now, so they have to be absent here too for the card to stay legend-free.
        let current = workout(activeEnergy: nil, elevation: nil)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        XCTAssertNil(
            availability(
                current: current,
                priors: priors,
                kinds: [.activeEnergy, .elevation, .humidity, .averageMETs, .heartRateRecovery],
                isComplete: true,
                isSettled: true
            )
        )
    }

    func testPlaceholderIsALocalizedZeroPercentOnlyForComparableMetrics() {
        let current = workout(activeEnergy: 300, elevation: nil)

        let energy = WorkoutMetricComparisonBuilder.placeholder(
            for: .activeEnergy,
            availability: .calculating,
            current: current,
            locale: enUS
        )
        XCTAssertEqual(energy?.badgeText, "0%")
        XCTAssertEqual(energy?.accessibilityLabel, "Calculating the 30-day comparison")

        // A metric this workout has no value for never sprouts a badge.
        XCTAssertNil(
            WorkoutMetricComparisonBuilder.placeholder(
                for: .elevation,
                availability: .calculating,
                current: current,
                locale: enUS
            )
        )

        // Feature off — previews and the share card stay badge-free.
        XCTAssertNil(
            WorkoutMetricComparisonBuilder.placeholder(
                for: .activeEnergy,
                availability: nil,
                current: current,
                locale: enUS
            )
        )
    }

    /// The stand-in only makes sense while a measurement is still coming. Once
    /// loading has settled there is nothing to roll into, and a "0%" would be a
    /// synthetic number presented as a result — under `.ready` the legend reads
    /// "vs 30-day avg" so it looks measured, and under `.insufficientHistory`
    /// there is no comparison at all.
    func testPlaceholderIsWithheldOnceLoadingHasSettled() {
        for availability in [WorkoutMetricComparisonAvailability.ready, .insufficientHistory] {
            XCTAssertNil(
                WorkoutMetricComparisonBuilder.placeholder(
                    for: .activeEnergy,
                    availability: availability,
                    current: workout(activeEnergy: 300),
                    locale: enUS
                ),
                "\(availability) must not show a stand-in"
            )
        }
    }

    func testPlaceholderDigitsAreLocalizedLikeTheRealBadge() {
        let arabic = Locale(identifier: "ar")
        let placeholder = WorkoutMetricComparisonBuilder.placeholder(
            for: .activeEnergy,
            availability: .calculating,
            current: workout(activeEnergy: 300),
            locale: arabic
        )
        XCTAssertEqual(placeholder?.badgeText, "\(BodyValueFormat.numberText(0, decimals: 0, locale: arabic))%")
        XCTAssertEqual(placeholder?.accessibilityLabel, "Calculating the 30-day comparison")
    }

    // MARK: - Presentation wiring

    private func presentation(
        current: WorkoutSummary,
        priors: [WorkoutSummary]?,
        isComplete: Bool = true,
        isSettled: Bool = true
    ) -> WorkoutDetailPresentation {
        WorkoutDetailPresentation(
            workout: current,
            locale: enUS,
            comparisonWorkouts: priors,
            comparisonDataComplete: isComplete,
            comparisonLoadSettled: isSettled
        )
    }

    func testPresentationCarriesTheCardStateAndStandIns() {
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200)]
        let loading = presentation(current: current, priors: priors, isComplete: false, isSettled: false)

        XCTAssertEqual(loading.comparisonAvailability, .calculating)
        XCTAssertEqual(loading.detailMetrics.first { $0.kind == .activeEnergy }?.comparison?.badgeText, "0%")
    }

    func testTheBadgeIsPresentBeforeAndAfterTheHistoryLands() {
        // The digits can only roll when the badge exists on both sides of the change —
        // a badge that appears from nothing pops instead.
        let current = workout(activeEnergy: 300)
        let priors = [workout(activeEnergy: 200), workout(activeEnergy: 200), workout(activeEnergy: 200)]
        let loading = presentation(current: current, priors: priors, isComplete: false, isSettled: false)
        let loaded = presentation(current: current, priors: priors, isComplete: true, isSettled: true)

        let loadingKinds = loading.detailMetrics.filter { $0.comparison != nil }.map(\.kind)
        let loadedKinds = loaded.detailMetrics.filter { $0.comparison != nil }.map(\.kind)
        XCTAssertFalse(loadedKinds.isEmpty)
        XCTAssertEqual(loadingKinds, loadedKinds)
        XCTAssertEqual(loaded.comparisonAvailability, .ready)
        XCTAssertEqual(loaded.detailMetrics.first { $0.kind == .activeEnergy }?.comparison?.badgeText, "↑50%")
    }

    func testFeatureOffLeavesEveryMetricBadgeFree() {
        let current = workout(activeEnergy: 300)
        let off = presentation(current: current, priors: nil)

        XCTAssertNil(off.comparisonAvailability)
        XCTAssertTrue(off.detailMetrics.allSatisfy { $0.comparison == nil })
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.bodyGregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
