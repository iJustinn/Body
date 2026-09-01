//
//  WorkoutShareSummaryCardTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
@testable import Body

final class WorkoutShareSummaryCardTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    private func workout(
        day: Int,
        type: BodyWorkoutType,
        duration: TimeInterval,
        energy: Double? = nil,
        distance: Double? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            type: type,
            startDate: Calendar.bodyGregorian.date(
                from: DateComponents(year: 2_025, month: 3, day: day, hour: 9)
            ) ?? Date(),
            duration: duration,
            activeEnergyKilocalories: energy,
            distanceMeters: distance
        )
    }

    private func snapshot(_ workouts: [WorkoutSummary]) -> WorkoutMonthSnapshot {
        WorkoutMonthSnapshot.make(
            month: 3,
            year: 2_025,
            workouts: workouts,
            calendar: .bodyGregorian,
            generatedAt: Date(timeIntervalSince1970: 1_740_000_000)
        )
    }

    /// Outdoor runs and rides: every optional metric has data.
    private var richMonth: WorkoutMonthSnapshot {
        snapshot([
            workout(day: 2, type: .running, duration: 2_400, energy: 310, distance: 5_200),
            workout(day: 5, type: .cycling, duration: 4_200, energy: 520, distance: 18_000),
            workout(day: 9, type: .running, duration: 3_000, energy: 380, distance: 6_400)
        ])
    }

    /// Strength only: energy and duration, never a distance.
    private var indoorMonth: WorkoutMonthSnapshot {
        snapshot([
            workout(day: 3, type: .strengthTraining, duration: 3_600, energy: 410),
            workout(day: 7, type: .yoga, duration: 2_700, energy: 120)
        ])
    }

    private var emptyMonth: WorkoutMonthSnapshot {
        snapshot([])
    }

    private func metrics(_ snapshot: WorkoutMonthSnapshot) -> [WorkoutShareSummaryMetricOption] {
        WorkoutShareSummaryMetricsBuilder.availableMetrics(
            snapshot: snapshot,
            distanceUnitPreference: .kilometers,
            energyUnitPreference: .kilocalories,
            locale: enUS
        )
    }

    private func geometry(
        _ ratio: WorkoutShareAspectRatio,
        metricCount: Int = WorkoutShareMetricSelection.defaultCount,
        barRowCount: Int = WorkoutShareSummaryBarCount.defaultCount
    ) -> WorkoutShareSummaryCardGeometry {
        WorkoutShareSummaryCardGeometry(
            aspectRatio: ratio,
            metricCount: metricCount,
            barRowCount: barRowCount
        )
    }

    // MARK: - Metric pool

    func testRichMonthOffersEveryMetricInCardOrder() {
        XCTAssertEqual(
            metrics(richMonth).map(\.id),
            [
                WorkoutShareSummaryMetricsBuilder.workoutsID,
                WorkoutShareSummaryMetricsBuilder.activeDaysID,
                WorkoutShareSummaryMetricsBuilder.durationID,
                WorkoutShareSummaryMetricsBuilder.activeEnergyID,
                WorkoutShareSummaryMetricsBuilder.distanceID,
                WorkoutShareSummaryMetricsBuilder.longestID,
                WorkoutShareSummaryMetricsBuilder.topActivityID
            ]
        )
    }

    func testIndoorMonthDropsDistance() {
        let ids = metrics(indoorMonth).map(\.id)
        XCTAssertFalse(ids.contains(WorkoutShareSummaryMetricsBuilder.distanceID))
        XCTAssertTrue(ids.contains(WorkoutShareSummaryMetricsBuilder.activeEnergyID))
        XCTAssertTrue(ids.contains(WorkoutShareSummaryMetricsBuilder.longestID))
        XCTAssertTrue(ids.contains(WorkoutShareSummaryMetricsBuilder.topActivityID))
    }

    /// A month with nothing in it still offers the three always-on metrics.
    func testEmptyMonthKeepsTheThreeAlwaysOnMetrics() {
        let options = metrics(emptyMonth)
        XCTAssertEqual(
            options.map(\.id),
            [
                WorkoutShareSummaryMetricsBuilder.workoutsID,
                WorkoutShareSummaryMetricsBuilder.activeDaysID,
                WorkoutShareSummaryMetricsBuilder.durationID
            ]
        )
        XCTAssertEqual(options.map(\.value), ["0", "0", "0m"])
    }

    func testDefaultsAreAlwaysInTheRichPool() {
        let ids = Set(metrics(richMonth).map(\.id))
        for id in WorkoutShareSummaryMetricsBuilder.defaultIDs {
            XCTAssertTrue(ids.contains(id), "default \(id) missing from the pool")
        }
    }

    // MARK: - Selection

    func testResolvedSummaryCapsAtThreeAndKeepsPoolOrder() {
        let available = metrics(richMonth)
        let resolved = WorkoutShareMetricSelection.resolvedSummary(
            stored: [
                WorkoutShareSummaryMetricsBuilder.topActivityID,
                WorkoutShareSummaryMetricsBuilder.distanceID,
                WorkoutShareSummaryMetricsBuilder.workoutsID,
                WorkoutShareSummaryMetricsBuilder.longestID,
                WorkoutShareSummaryMetricsBuilder.activeDaysID,
                WorkoutShareSummaryMetricsBuilder.durationID
            ],
            available: available,
            defaults: WorkoutShareSummaryMetricsBuilder.defaultIDs
        )
        XCTAssertEqual(resolved.count, WorkoutShareMetricSelection.summaryMaximumCount)
        XCTAssertEqual(
            resolved,
            [
                WorkoutShareSummaryMetricsBuilder.workoutsID,
                WorkoutShareSummaryMetricsBuilder.activeDaysID,
                WorkoutShareSummaryMetricsBuilder.durationID
            ]
        )
    }

    func testResolvedSummaryFallsBackToDefaultsOnAStalePick() {
        XCTAssertEqual(
            WorkoutShareMetricSelection.resolvedSummary(
                stored: ["somethingElse", WorkoutShareSummaryMetricsBuilder.distanceID],
                available: metrics(indoorMonth),
                defaults: WorkoutShareSummaryMetricsBuilder.defaultIDs
            ),
            WorkoutShareSummaryMetricsBuilder.defaultIDs
        )
    }

    func testResolvedSummaryOnAnEmptyMonthKeepsBothDefaults() {
        XCTAssertEqual(
            WorkoutShareMetricSelection.resolvedSummary(
                stored: nil,
                available: metrics(emptyMonth),
                defaults: WorkoutShareSummaryMetricsBuilder.defaultIDs
            ),
            [WorkoutShareSummaryMetricsBuilder.workoutsID, WorkoutShareSummaryMetricsBuilder.activeDaysID]
        )
        XCTAssertEqual(WorkoutShareSummaryMetricsBuilder.defaultIDs, [WorkoutShareSummaryMetricsBuilder.workoutsID, WorkoutShareSummaryMetricsBuilder.activeDaysID])
    }

    func testStoredSummaryRoundTripsAndRejectsJunk() {
        let ids = [WorkoutShareSummaryMetricsBuilder.workoutsID, WorkoutShareSummaryMetricsBuilder.distanceID]
        XCTAssertEqual(WorkoutShareMetricSelection.storedSummary(json: WorkoutShareMetricSelection.storingSummary(ids)), ids)
        XCTAssertNil(WorkoutShareMetricSelection.storedSummary(json: ""))
        // An empty list is a real pick ("no totals"), not an absence.
        XCTAssertEqual(WorkoutShareMetricSelection.storedSummary(json: "[]"), [])
        XCTAssertNil(WorkoutShareMetricSelection.storedSummary(json: "not json"))
    }

    func testTogglingSummaryHasNoFloorAndHoldsTheCeiling() {
        let available = metrics(richMonth)
        let single = [WorkoutShareSummaryMetricsBuilder.workoutsID]
        // The last chip turns off too: a month card may carry no totals.
        XCTAssertEqual(
            WorkoutShareMetricSelection.togglingSummary(
                WorkoutShareSummaryMetricsBuilder.workoutsID,
                in: single,
                available: available
            ),
            []
        )
        // …and that "none" round-trips through storage as a pick of its own.
        let none = WorkoutShareMetricSelection.storingSummary([])
        XCTAssertEqual(WorkoutShareMetricSelection.storedSummary(json: none), [])
        XCTAssertEqual(
            WorkoutShareMetricSelection.resolvedSummary(
                stored: [],
                available: available,
                defaults: WorkoutShareSummaryMetricsBuilder.defaultIDs
            ),
            []
        )
        XCTAssertNil(WorkoutShareMetricSelection.storedSummary(json: ""))
        XCTAssertEqual(WorkoutShareSummaryCardGeometry(aspectRatio: .portrait9x16, metricCount: 0).metricsRect.height, 0)

        let five = Array(available.map(\.id).prefix(WorkoutShareMetricSelection.summaryMaximumCount))
        XCTAssertEqual(
            WorkoutShareMetricSelection.togglingSummary(
                WorkoutShareSummaryMetricsBuilder.topActivityID,
                in: five,
                available: available
            ),
            five
        )

        XCTAssertEqual(
            WorkoutShareMetricSelection.togglingSummary(
                WorkoutShareSummaryMetricsBuilder.distanceID,
                in: [WorkoutShareSummaryMetricsBuilder.durationID, WorkoutShareSummaryMetricsBuilder.workoutsID],
                available: available
            ),
            [
                WorkoutShareSummaryMetricsBuilder.workoutsID,
                WorkoutShareSummaryMetricsBuilder.durationID,
                WorkoutShareSummaryMetricsBuilder.distanceID
            ]
        )
    }

    func testSummaryShareHasNoLongImage() {
        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedOutputStyle(.longImage, isProUnlocked: true, supportsLongImage: false),
            .card
        )
        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedOutputStyle(.longImage, isProUnlocked: true),
            .longImage
        )
    }

    // MARK: - Snapshot and summary

    func testTotalDistanceSumsEveryDay() {
        XCTAssertEqual(richMonth.totalDistanceMeters, 29_600, accuracy: 0.001)
        XCTAssertEqual(indoorMonth.totalDistanceMeters, 0, accuracy: 0.001)
    }

    /// Same duration, same display priority — only the raw value decides, so the tint
    /// and "Top Activity" can't move between runs.
    func testBreakdownTieBreakIsDeterministic() {
        let tied = snapshot([
            workout(day: 4, type: .functionalStrengthTraining, duration: 1_800),
            workout(day: 6, type: .coreTraining, duration: 1_800)
        ])
        XCTAssertEqual(tied.workoutTypeBreakdown.map(\.type), [.coreTraining, .functionalStrengthTraining])
    }

    func testEmptyMonthSummaryUsesTheNeutralTint() {
        let summary = WorkoutShareMonthSummary(snapshot: emptyMonth, initialChartStyle: .calendar)
        XCTAssertEqual(summary.tintType, .other)

        let synthetic = summary.syntheticWorkout
        XCTAssertEqual(synthetic.type, .other)
        XCTAssertEqual(synthetic.duration, 0)
        let components = Calendar.bodyGregorian.dateComponents([.year, .month, .day], from: synthetic.startDate)
        XCTAssertEqual(components.year, 2_025)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 1)
    }

    func testRichMonthSummaryTakesTheLeadingActivitysTint() {
        let summary = WorkoutShareMonthSummary(snapshot: richMonth, initialChartStyle: .bar)
        XCTAssertEqual(summary.tintType, .running)
        XCTAssertEqual(summary.syntheticWorkout.type, .running)
    }

    // MARK: - Geometry

    func testChartRegionClearsTheBrandingZoneOnEveryRatio() {
        for ratio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
            for count in 1...WorkoutShareMetricSelection.summaryMaximumCount {
                let layout = geometry(ratio, metricCount: count)
                XCTAssertLessThanOrEqual(
                    layout.chartRect.maxY,
                    layout.size.height - WorkoutShareCardGeometry.brandingZoneHeight,
                    "\(ratio.rawValue) with \(count) metrics enters the branding zone"
                )
                XCTAssertGreaterThan(layout.chartRect.height, 0, "\(ratio.rawValue) with \(count) metrics has no chart")
                XCTAssertLessThanOrEqual(layout.metricsRect.maxY, layout.chartRect.maxY)
            }
        }
    }

    func testChartFrameFitsItsRegionOnEveryRatioAndStyle() {
        for ratio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
            let layout = geometry(ratio)
            for style in WorkoutSummaryChartStyle.allCases {
                let frame = layout.chartFrame(for: style)
                XCTAssertGreaterThan(frame.width, 0, "\(ratio.rawValue) \(style.rawValue)")
                XCTAssertLessThanOrEqual(frame.width, layout.chartRect.width, "\(ratio.rawValue) \(style.rawValue)")
                XCTAssertLessThanOrEqual(frame.height, layout.chartRect.height, "\(ratio.rawValue) \(style.rawValue)")
            }
        }
    }

    /// The default pick is the five rows the breakdown has always drawn here, at full
    /// size on every supported ratio.
    func testBarRowLimitDefaultsToFiveFullSizeRowsOnEveryRatio() {
        for ratio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
            let layout = geometry(ratio)
            XCTAssertEqual(layout.barRowLimit, 5, ratio.rawValue)
            XCTAssertEqual(layout.barContentScale, 1, ratio.rawValue)
            XCTAssertEqual(layout.chartFrame(for: .bar).height, layout.barContentHeight, accuracy: 0.5, ratio.rawValue)
        }
    }

    /// A pick the region can't hold at full size shrinks the whole chart instead of
    /// dropping the bars the user asked for.
    func testTallBarPicksShrinkInsteadOfLosingBars() {
        for ratio in WorkoutShareSummaryCardGeometry.supportedAspectRatios {
            let layout = geometry(ratio, barRowCount: 12)
            XCTAssertEqual(layout.barRowLimit, 12, ratio.rawValue)
            XCTAssertLessThan(layout.barContentScale, 1, "\(ratio.rawValue) should have had to shrink")
            XCTAssertGreaterThan(layout.barContentScale, 0, ratio.rawValue)
            // Scaled, the chart lands exactly inside its region — and that is the frame
            // the card positions, so the bars can't reach the branding.
            XCTAssertEqual(
                layout.barContentHeight * layout.barContentScale,
                layout.chartFrame(for: .bar).height,
                accuracy: 0.5,
                ratio.rawValue
            )
            XCTAssertLessThanOrEqual(layout.chartFrame(for: .bar).height, layout.chartRect.height, ratio.rawValue)
        }

        // The metric rows come out of the same region, so a five-metric 3:4 card leaves
        // the chart less room — and shrinks the same pick further.
        let lean = geometry(.portrait3x4, metricCount: 1, barRowCount: 8)
        let crowded = geometry(.portrait3x4, metricCount: 5, barRowCount: 8)
        XCTAssertLessThan(crowded.barContentScale, lean.barContentScale)
    }

    /// The month card's header runs smaller than the workout card's blocks: same
    /// shape, less type, and the height it gives up goes to the chart rather than to
    /// empty air.
    func testMonthTotalsAreSetSmallerThanTheWorkoutCardsBlocks() {
        for ratio in [WorkoutShareAspectRatio.portrait9x16, .portrait3x4] {
            let layout = geometry(ratio)
            let shared = layout.metricBlockStyle
            XCTAssertLessThan(layout.metricValueSize, shared.valueSize, ratio.rawValue)
            XCTAssertLessThan(layout.metricLabelSize, shared.labelSize, ratio.rawValue)
            XCTAssertLessThan(layout.metricRowHeight, shared.rowHeight, ratio.rawValue)
            XCTAssertLessThan(layout.metricRowGap, shared.rowGap, ratio.rawValue)
            // One row of totals, so the slot is exactly one scaled block tall.
            XCTAssertEqual(layout.metricsRect.height, layout.metricRowHeight, accuracy: 0.5, ratio.rawValue)
            // What the header doesn't take, the chart does.
            XCTAssertEqual(
                layout.chartRect.minY,
                layout.metricsRect.maxY + 14,
                accuracy: 0.5,
                ratio.rawValue
            )
        }
    }

    /// The stored number is a preference: a month with fewer activities clamps it for
    /// this card without the pick being rewritten, and a missing value (`@AppStorage`
    /// hands back a zero) reads as the default.
    func testResolvedBarCountClampsToTheMonthsActivities() {
        XCTAssertEqual(WorkoutShareSummaryBarCount.defaultCount, 5)
        XCTAssertEqual(WorkoutShareSummaryBarCount.resolved(stored: 0, availableTypeCount: 9), 5)
        XCTAssertEqual(WorkoutShareSummaryBarCount.resolved(stored: -3, availableTypeCount: 9), 5)
        XCTAssertEqual(WorkoutShareSummaryBarCount.resolved(stored: 12, availableTypeCount: 12), 12)
        XCTAssertEqual(WorkoutShareSummaryBarCount.resolved(stored: 1, availableTypeCount: 9), 1)
        // Clamped down, never below one — and an empty month still gets a row for the
        // chart's own "no workouts yet" state.
        XCTAssertEqual(WorkoutShareSummaryBarCount.resolved(stored: 12, availableTypeCount: 3), 3)
        XCTAssertEqual(WorkoutShareSummaryBarCount.resolved(stored: 5, availableTypeCount: 0), 1)
    }

    /// The tray offers one tile per activity the month has, and no tiles at all when
    /// there is nothing to choose between.
    func testBarCountOptionsCoverTheMonthsActivities() {
        XCTAssertEqual(WorkoutShareSummaryBarCount.options(availableTypeCount: 4), [1, 2, 3, 4])
        XCTAssertEqual(WorkoutShareSummaryBarCount.options(availableTypeCount: 1), [])
        XCTAssertEqual(WorkoutShareSummaryBarCount.options(availableTypeCount: 0), [])
        // The pool the tray actually reads: one tile per activity in the month.
        XCTAssertEqual(
            WorkoutShareSummaryBarCount.options(availableTypeCount: richMonth.workoutTypeBreakdown.count).count,
            richMonth.workoutTypeBreakdown.count
        )
    }

    /// The square is the chart alone; the portraits stack title and metrics above it.
    /// Landscape is not a summary shape at all.
    func testSquareIsChartOnlyAndLandscapeIsNotOffered() {
        let square = geometry(.square, metricCount: 5)
        XCTAssertEqual(square.arrangement, .chartOnly)
        XCTAssertEqual(square.titleRect, .zero)
        XCTAssertEqual(square.metricsRect, .zero)
        XCTAssertEqual(square.chartRect.minY, 20)
        XCTAssertEqual(square.chartRect.width, 320)
        for ratio in [WorkoutShareAspectRatio.portrait9x16, .portrait3x4] {
            XCTAssertEqual(geometry(ratio).arrangement, .stacked, ratio.rawValue)
            XCTAssertGreaterThan(geometry(ratio).titleRect.height, 0, ratio.rawValue)
        }
        XCTAssertEqual(WorkoutShareSummaryCardGeometry.supportedAspectRatios, [.portrait9x16, .portrait3x4, .square])
        XCTAssertFalse(WorkoutShareSummaryCardGeometry.supportedAspectRatios.contains { $0.isLandscape })
        // A landscape pick remembered from a workout share resolves to 9:16 for the summary.
        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedAspectRatio(.landscape16x9, isProUnlocked: true, supportsLandscape: false),
            .portrait9x16
        )
        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedAspectRatio(.square, isProUnlocked: true, supportsLandscape: false),
            .square
        )
    }

    /// Hiding the weekday letters hands their 28 pt back to the grid's cells.
    func testHidingWeekdaysShortensTheCalendarFrame() {
        let shown = geometry(.portrait9x16).chartFrame(for: .calendar)
        let hidden = WorkoutShareSummaryCardGeometry(aspectRatio: .portrait9x16, showsWeekdayHeader: false)
            .chartFrame(for: .calendar)
        XCTAssertEqual(hidden.height, shown.height - 28, accuracy: 0.01)
        XCTAssertEqual(hidden.width, shown.width, accuracy: 0.01)
        XCTAssertEqual(WorkoutShareWeekdayVisibility.stored(rawValue: nil), .shown)
        XCTAssertEqual(WorkoutShareWeekdayVisibility.stored(rawValue: "hidden"), .hidden)
    }

    func testMetricBlocksCompactWhenTheyHaveTo() {
        XCTAssertEqual(geometry(.portrait9x16).metricBlockStyle, .regular)
        XCTAssertEqual(geometry(.portrait9x16, metricCount: 4).metricBlockStyle, .compact)
        XCTAssertEqual(geometry(.portrait3x4, metricCount: 5).metricBlockStyle, .compact)
    }
}
