//
//  HealthWidgetSnapshotBuilderTrendCardTests.swift
//  BodyTests
//
//  The large Trends widget renders cards the app writes into the widget snapshot
//  (`HealthWidgetSnapshotBuilder.trendCards`). They must read exactly as Home's
//  Trends cards do, and carry Home's Trends order for the widget's Top Trend.
//

import XCTest
@testable import Body

@MainActor
final class HealthWidgetSnapshotBuilderTrendCardTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    /// Readiness rises (a lower month, then five higher ones) and Stress holds
    /// flat, over the 180 days ending yesterday. Relative to today because Home's
    /// cache computes against `Date()`.
    private func trends() throws -> HealthTrendSnapshot {
        let today = calendar.startOfDay(for: Date())
        func points(_ value: (Int) -> Double) throws -> [HealthTrendDataPoint] {
            try (-180...(-1)).map { offset in
                let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: today))
                return HealthTrendDataPoint(date: date, value: value(offset))
            }
        }

        var trends = HealthTrendSnapshot.empty
        trends.readiness = HealthTrendSeries(points: try points { $0 < -150 ? 50 : 66 })
        trends.stress = HealthTrendSeries(points: try points { _ in 20 })
        return trends
    }

    private func trendCards(_ trends: HealthTrendSnapshot) -> [HealthWidgetTrendCard] {
        HealthWidgetSnapshotBuilder.trendCards(
            trends: trends,
            temperatureUnitPreference: .defaultValue,
            energyUnitPreference: .defaultValue,
            weightUnitPreference: .defaultValue
        )
    }

    func testMeaningfulCardReadsExactlyAsHomeShowsIt() throws {
        let trends = try trends()
        let card = try XCTUnwrap(trendCards(trends).first { $0.metric == "readiness" })
        // Home's collapsed list: meaningful windows only, through Home's own cache.
        let home = try XCTUnwrap(BodyHomeTrendCardFactory.cards(
            trends: trends,
            selection: BodyHomeTrendCardSelection(selectedCards: [.readiness]),
            temperatureUnitPreference: .defaultValue,
            energyUnitPreference: .defaultValue,
            weightUnitPreference: .defaultValue,
            includesStable: false,
            cache: BodyHomeTrendComputationCache()
        ).first).presentation

        XCTAssertTrue(card.isMeaningful)
        XCTAssertEqual(card.title, "Readiness")
        XCTAssertEqual(card.chartStyle, .line)
        XCTAssertTrue(card.messageText.hasPrefix("On average, your readiness score increased over the last"))
        XCTAssertEqual(card.messageText, home.messageText)
        XCTAssertEqual(card.baselineAverageText, home.baselineAverageText)
        XCTAssertEqual(card.recentAverageText, home.recentAverageText)
        XCTAssertEqual(card.baselinePeriodText, home.baselinePeriodText)
        XCTAssertEqual(card.recentPeriodText, home.recentPeriodText)
        XCTAssertEqual(card.baselineAverage, home.baselineAverage, accuracy: 0.000_001)
        XCTAssertEqual(card.recentAverage, home.recentAverage, accuracy: 0.000_001)
        XCTAssertEqual(card.values, home.displayCalendarPoints.map(\.value))
        XCTAssertEqual(card.baselineEndIndex, home.displayBaselineEndIndex)
        XCTAssertLessThanOrEqual(card.values.count, BodyHomeTrendCardPresentation.maximumDisplayPointCount)
        XCTAssertTrue(card.recentAverageText.hasSuffix("%"))
    }

    func testSteadyMetricStillGetsACardForPinning() throws {
        let trends = try trends()
        let card = try XCTUnwrap(trendCards(trends).first { $0.metric == "stress" })

        XCTAssertFalse(card.isMeaningful)
        XCTAssertTrue(card.messageText.contains("stayed about the same"))
        // Home's collapsed list leaves a steady trend out.
        XCTAssertTrue(BodyHomeTrendCardFactory.cards(
            trends: trends,
            selection: BodyHomeTrendCardSelection(selectedCards: [.stress]),
            temperatureUnitPreference: .defaultValue,
            energyUnitPreference: .defaultValue,
            weightUnitPreference: .defaultValue,
            includesStable: false,
            cache: BodyHomeTrendComputationCache()
        ).isEmpty)
    }

    func testOnlyKindsWithDataGetCardsInHomeOrder() throws {
        XCTAssertEqual(trendCards(try trends()).map(\.metric), ["readiness", "stress"])
        XCTAssertEqual(trendCards(.empty), [])
    }

    func testSnapshotCarriesHomeTrendsOrder() throws {
        func make(order: [BodyHomeTrendCardKind]?) throws -> HealthWidgetSnapshot {
            let trends = try trends()
            if let order {
                return HealthWidgetSnapshotBuilder.make(
                    trends: trends,
                    summary: .empty,
                    temperatureUnitPreference: .defaultValue,
                    energyUnitPreference: .defaultValue,
                    weightUnitPreference: .defaultValue,
                    idealSleepDuration: BodySleepDurationGoal.defaultDuration,
                    showSleepScore: true,
                    primarySourceName: { _ in nil },
                    trendCardOrder: order
                )
            }
            return HealthWidgetSnapshotBuilder.make(
                trends: trends,
                summary: .empty,
                temperatureUnitPreference: .defaultValue,
                energyUnitPreference: .defaultValue,
                weightUnitPreference: .defaultValue,
                idealSleepDuration: BodySleepDurationGoal.defaultDuration,
                showSleepScore: true,
                primarySourceName: { _ in nil }
            )
        }

        let selected = try make(order: [.stress, .steps])
        XCTAssertEqual(selected.trendCardOrder, ["stress", "steps"])
        // Cards are written for every kind with data, selected on Home or not.
        XCTAssertEqual(selected.trendCards?.map(\.metric), ["readiness", "stress"])

        XCTAssertEqual(try make(order: nil).trendCardOrder, BodyHomeTrendCardKind.defaultOrder.map(\.rawValue))
    }
}
