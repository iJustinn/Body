//
//  MetricCardPreviewPhaseTests.swift
//  BodyTests
//
//  Covers the home card preview phase: a preview with nothing in it is only a
//  skeleton while a refresh is actually in flight. Someone who granted Body two
//  or three Health categories has nothing coming for the rest, and reading
//  emptiness as "pending" left those cards loading forever.
//

import SwiftUI
import XCTest
@testable import Body

@MainActor
final class MetricCardPreviewPhaseTests: XCTestCase {
    private typealias Phase = BodyHealthMetricCard.PreviewPhase

    private func vitalsModel(dotEntries: [BodyHealthMetricCard.Model.DotEntry]) -> BodyHealthMetricCard.Model {
        BodyHealthMetricCard.Model(
            kind: .vitals,
            title: "Vitals",
            value: dotEntries.isEmpty ? "--" : "Typical",
            unit: "",
            symbolName: "heart.badge.bolt",
            symbolColor: .blue,
            chartPreviewStyle: .dots,
            previewDotEntries: dotEntries
        )
    }

    private func cardioFitnessModel(
        value: String,
        levelPreviewEntry: BodyHealthMetricCard.Model.LevelEntry?
    ) -> BodyHealthMetricCard.Model {
        BodyHealthMetricCard.Model(
            kind: .cardioFitness,
            title: "Cardio Fitness",
            value: value,
            unit: "VO₂ max",
            symbolName: "arrow.up.heart.fill",
            symbolColor: .red,
            chartPreviewStyle: .levels,
            levelPreviewEntry: levelPreviewEntry
        )
    }

    func testAssessedVitalsStayInDataThroughARefresh() {
        let model = vitalsModel(dotEntries: [
            BodyHealthMetricCard.Model.DotEntry(position: 0.5, region: .typical)
        ])

        XCTAssertEqual(Phase.resolved(for: model, isRefreshing: false), .data)
        XCTAssertEqual(Phase.resolved(for: model, isRefreshing: true), .data)
    }

    func testEmptyVitalsAreOnlyPendingWhileARefreshRuns() {
        let model = vitalsModel(dotEntries: [])

        XCTAssertEqual(Phase.resolved(for: model, isRefreshing: true), .pending)
        XCTAssertEqual(Phase.resolved(for: model, isRefreshing: false), .unavailable)
    }

    func testClassifiedCardioFitnessStaysInDataThroughARefresh() {
        let model = cardioFitnessModel(
            value: "42.5",
            levelPreviewEntry: BodyHealthMetricCard.Model.LevelEntry(level: .aboveAverage, position: 0.5)
        )

        XCTAssertEqual(Phase.resolved(for: model, isRefreshing: false), .data)
        XCTAssertEqual(Phase.resolved(for: model, isRefreshing: true), .data)
    }

    /// A VO₂ max the norms can't place — no date of birth or biological sex, or
    /// an age outside the classifiable range — is documented behavior, not a
    /// pending fetch. The card keeps its number and drops the skeleton.
    func testUnclassifiableCardioFitnessReadingIsUnavailableAtRest() {
        let model = cardioFitnessModel(value: "42.5", levelPreviewEntry: nil)

        XCTAssertEqual(Phase.resolved(for: model, isRefreshing: false), .unavailable)
    }

    /// The line, bar and range previews plot what they were handed and have
    /// never drawn a skeleton for the gaps, so no amount of emptiness puts them
    /// in a waiting state.
    func testPlottedPreviewsNeverWait() {
        for style in [BodyHomeMetricCardPreview.Style.line, .bar, .range] {
            let model = BodyHealthMetricCard.Model(
                kind: .sleep,
                title: "Sleep",
                value: "--",
                unit: "",
                symbolName: "bed.double.fill",
                symbolColor: .blue,
                chartPreviewStyle: style
            )

            XCTAssertEqual(Phase.resolved(for: model, isRefreshing: false), .data)
            XCTAssertEqual(Phase.resolved(for: model, isRefreshing: true), .data)
        }
    }

    /// Vitals' "Typical"/"Below Average" and Stress's band word both render
    /// through `BodyMetricStatusValueText`, not the numeric-value text a kind
    /// like Heart Rate uses.
    func testStressVitalsAndBodyRadarUseWordValueButHeartRateDoesNot() {
        let stressModel = BodyHealthMetricCard.Model(
            kind: .stress,
            title: "Stress",
            value: "42",
            unit: "",
            symbolName: "brain.head.profile.fill",
            symbolColor: .pink
        )
        let vitalsModel = vitalsModel(dotEntries: [])
        let bodyRadarModel = BodyHealthMetricCard.Model(
            kind: .bodyRadar,
            title: "Body Radar",
            value: "No signs",
            unit: "All typical",
            symbolName: "person.and.background.dotted",
            symbolColor: .gray
        )
        let heartRateModel = BodyHealthMetricCard.Model(
            kind: .heartRate,
            title: "Heart Rate",
            value: "68",
            unit: "bpm",
            symbolName: "heart.fill",
            symbolColor: .red
        )

        XCTAssertTrue(stressModel.usesWordValue)
        XCTAssertTrue(vitalsModel.usesWordValue)
        XCTAssertTrue(bodyRadarModel.usesWordValue)
        XCTAssertFalse(heartRateModel.usesWordValue)
    }

    /// With the Sleep permission off the summary carries no Body Radar at all, so
    /// the card must read No Data with the pending/unavailable skeleton rather
    /// than a calibration that can never finish.
    func testBodyRadarWithoutSummaryReadsAsNoDataWithNoDotEntries() {
        XCTAssertEqual(
            BodyHomeView.bodyRadarCardValue(for: nil),
            String(localized: "bodyRadar.state.noData", defaultValue: "No Data")
        )
        XCTAssertTrue(BodyHomeView.bodyRadarDotEntries(for: nil).isEmpty)

        let model = BodyHealthMetricCard.Model(
            kind: .bodyRadar,
            title: "Body Radar",
            value: BodyHomeView.bodyRadarCardValue(for: nil),
            unit: "",
            symbolName: "person.and.background.dotted",
            symbolColor: .gray,
            chartPreviewStyle: .dots,
            previewDotEntries: BodyHomeView.bodyRadarDotEntries(for: nil)
        )

        XCTAssertEqual(
            BodyHealthMetricCard.PreviewPhase.resolved(for: model, isRefreshing: false),
            .unavailable
        )
        XCTAssertEqual(
            BodyHealthMetricCard.PreviewPhase.resolved(for: model, isRefreshing: true),
            .pending
        )
    }
}
