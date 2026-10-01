//
//  BodyRadarChartTests.swift
//  BodyTests
//

import SwiftUI
import XCTest
@testable import Body

final class BodyRadarChartTests: XCTestCase {
    func testUnavailableNightStaysInMutedPlaceholderBand() {
        for state in BodyRadarState.allCases where !state.isScored {
            let night = BodyRadarNight(date: Date(timeIntervalSince1970: 0), state: state)
            let point = BodyRadarChartPoint(night: night)
            XCTAssertFalse(point.isScored)
            XCTAssertEqual(point.bandPosition(majorCeiling: 5), 0)
            XCTAssertEqual(night.region, .none)
            XCTAssertEqual(night.unflaggedExplanation, state.title)
        }
    }

    private func night(day: Int) -> BodyRadarNight {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = day
        let date = Calendar.bodyGregorian.date(from: components) ?? Date()
        return BodyRadarNight(date: date, state: .noSigns, evidence: 0.5)
    }

    private var points: [BodyRadarChartPoint] {
        (1...3).map { BodyRadarChartPoint(night: night(day: $0)) }
    }

    func testNearestPointPicksTheSlotTheScrubIsInside() {
        let points = points
        let slotStart = points[1].night.date

        for hour in [0.5, 12.0, 23.5] {
            let selected = slotStart.addingTimeInterval(hour * 60 * 60)
            XCTAssertEqual(
                BodyRadarChart.nearestPoint(to: selected, in: points)?.id,
                points[1].id,
                "A scrub \(hour)h into the second night's slot should select that night"
            )
        }
    }

    func testNearestPointSwitchesAtTheSlotBoundary() {
        let points = points
        let boundary = points[1].night.date

        XCTAssertEqual(
            BodyRadarChart.nearestPoint(to: boundary.addingTimeInterval(-60), in: points)?.id,
            points[0].id
        )
        XCTAssertEqual(
            BodyRadarChart.nearestPoint(to: boundary.addingTimeInterval(60), in: points)?.id,
            points[1].id
        )
    }

    func testNearestPointOnEmptyInputIsNil() {
        XCTAssertNil(BodyRadarChart.nearestPoint(to: Date(), in: []))
    }

    // MARK: - Held nights (Beta 3)

    /// Raw evidence past Minor from heart signals alone, held at No Signs.
    private var heldNightWithFlags: BodyRadarNight {
        BodyRadarNight(
            date: night(day: 4).date,
            state: .noSigns,
            evidence: 5.0,
            signals: [
                BodyRadarSignal(kind: .sleepingHeartRate, deviation: 3, flagged: true),
                BodyRadarSignal(kind: .respiratoryRate, deviation: 0.2, flagged: false),
                BodyRadarSignal(kind: .heartRateVariability, deviation: -3, flagged: true)
            ],
            corroboration: BodyRadarCorroboration.none
        )
    }

    func testHeldNightWithFlagsShowsTheHoldTextAndKeepsItsArrows() throws {
        let night = heldNightWithFlags
        let callout = BodyRadarCalloutModel(night: night)

        // The view draws the explanation above the rows.
        let explanation = try XCTUnwrap(callout.explanation)
        XCTAssertEqual(explanation, night.holdExplanation)
        XCTAssertEqual(callout.rows.map(\.kind), [.sleepingHeartRate, .heartRateVariability])
        XCTAssertEqual(callout.rows.map(\.arrowSymbolName), ["arrow.up", "arrow.down"])
    }

    /// The hold note is a full sentence. The floating callout must wrap it
    /// rather than grow wider than the phone (seen on device, Sep 23, 2026).
    func testHeldNightExplanationWrapsInsideTheCallout() throws {
        let source = try BodyTestSupport.sourceText(at: "Body/Views/Health/Charts/BodyRadarChart.swift")
        let start = try XCTUnwrap(source.range(of: "struct BodyRadarSelectionAnnotation: View")?.lowerBound)
        let block = source[start...]

        XCTAssertTrue(block.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(block.contains(".frame(maxWidth: BodyRadarChartStyle.calloutExplanationMaxWidth, alignment: .leading)"))
        XCTAssertGreaterThan(BodyRadarChartStyle.calloutExplanationMaxWidth, 0)
    }

    func testHeldNightWithoutFlagsShowsTheHoldTextAlone() {
        let night = BodyRadarNight(
            date: self.night(day: 4).date,
            state: .noSigns,
            evidence: 0.8,
            signals: [
                BodyRadarSignal(kind: .respiratoryRate, deviation: -0.95, flagged: false),
                BodyRadarSignal(kind: .wristTemperature, deviation: 0.9, flagged: false)
            ],
            corroboration: BodyRadarCorroboration.none
        )
        let callout = BodyRadarCalloutModel(night: night)

        XCTAssertNotNil(night.holdExplanation)
        XCTAssertEqual(callout.explanation, night.holdExplanation)
        XCTAssertTrue(callout.rows.isEmpty)
    }

    func testCalloutOutsideTheHoldKeepsItsBeta2Lines() {
        let quiet = BodyRadarCalloutModel(night: night(day: 1))
        XCTAssertNil(night(day: 1).holdExplanation)
        XCTAssertEqual(quiet.explanation, night(day: 1).unflaggedExplanation)
        XCTAssertTrue(quiet.rows.isEmpty)

        let alert = BodyRadarNight(
            date: night(day: 2).date,
            state: .minorSigns,
            evidence: 1.5,
            signals: [BodyRadarSignal(kind: .respiratoryRate, deviation: -2, flagged: true)],
            corroboration: .persistence
        )
        let alertCallout = BodyRadarCalloutModel(night: alert)
        XCTAssertNil(alertCallout.explanation)
        XCTAssertEqual(alertCallout.rows.map(\.arrowSymbolName), ["arrow.down"])

        let unscored = BodyRadarCalloutModel(night: BodyRadarNight(date: night(day: 3).date, state: .calibrating))
        XCTAssertNil(unscored.explanation)
        XCTAssertTrue(unscored.rows.isEmpty)
    }

    func testHeldNightDotSitsAtTheTopOfTheNoneBandInGray() {
        let night = heldNightWithFlags
        let point = BodyRadarChartPoint(night: night)
        let noneCeiling = 1 - BodyRadarChartStyle.signBandFraction * 2

        XCTAssertEqual(night.region, .none)
        XCTAssertEqual(point.bandPosition(majorCeiling: 5), 1)
        XCTAssertEqual(point.bandBounds.ceiling, noneCeiling, accuracy: 0.000_1)
        XCTAssertLessThan(point.plotValue(majorCeiling: 5), noneCeiling)
        XCTAssertEqual(BodyRadarChartStyle.color(for: night.region), .secondary)
    }
}
