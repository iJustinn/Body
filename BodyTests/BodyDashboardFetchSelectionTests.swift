//
//  BodyDashboardFetchSelectionTests.swift
//  BodyTests
//
//  `BodyDashboardFetchSelection` now distinguishes full-card fetches
//  (`fullPayloadKinds`) from Stress-input-only fetches (`metricKinds` minus
//  `fullPayloadKinds`), so a layout can fetch a kind's data without rendering
//  its card. `includes(_:)` keeps its old union semantics on purpose (nothing
//  regresses for existing callers); this file pins that equivalence
//  exhaustively, plus the new `includesFullPayload`/`isInputOnly` accessors
//  the fetch-gating and permission-sheet code depend on.
//

import XCTest
@testable import Body

final class BodyDashboardFetchSelectionTests: XCTestCase {

    // MARK: - Legacy union, reproduced inline (never imported from production)

    private static let basicsMetricKinds: Set<HealthMetricKind> = [
        .bodyMass,
        .bodyFatPercentage,
        .bodyMassIndex
    ]
    private static let readinessDependencyKinds: Set<HealthMetricKind> = [
        .sleep,
        .heartRateVariability,
        .restingHeartRate,
        .trainingLoad,
        .respiratoryRate,
        .oxygenSaturation,
        .wristTemperature
    ]
    private static let stressDependencyKinds: Set<HealthMetricKind> = [
        .heartRate,
        .heartRateVariability,
        .sleep,
        .steps,
        .activeEnergy
    ]
    private static let bodyRadarDependencyKinds: Set<HealthMetricKind> = [
        .sleep,
        .steps
    ]
    private static let vitalsMetricKinds: Set<HealthMetricKind> = [.sleep]

    /// The ten toggles the exhaustive sweep varies: the three expansion
    /// triggers (basics/readiness/vitals) + the two input-only derived cards
    /// (stress, Body Radar) + the five dependency cards they share, each
    /// independently present or absent as a Home card. 2^10 = 1024 combinations.
    private struct Toggles {
        var basics: Bool
        var readiness: Bool
        var vitals: Bool
        var stress: Bool
        var heartRate: Bool
        var heartRateVariability: Bool
        var sleep: Bool
        var steps: Bool
        var activeEnergy: Bool
        var bodyRadar: Bool

        init(bits: Int) {
            basics = bits & 0x1 != 0
            readiness = bits & 0x2 != 0
            vitals = bits & 0x4 != 0
            stress = bits & 0x8 != 0
            heartRate = bits & 0x10 != 0
            heartRateVariability = bits & 0x20 != 0
            sleep = bits & 0x40 != 0
            steps = bits & 0x80 != 0
            activeEnergy = bits & 0x100 != 0
            bodyRadar = bits & 0x200 != 0
        }

        var directKinds: Set<HealthMetricKind> {
            var kinds: Set<HealthMetricKind> = []
            if basics { kinds.insert(.basics) }
            if readiness { kinds.insert(.readiness) }
            if vitals { kinds.insert(.vitals) }
            if stress { kinds.insert(.stress) }
            if heartRate { kinds.insert(.heartRate) }
            if heartRateVariability { kinds.insert(.heartRateVariability) }
            if sleep { kinds.insert(.sleep) }
            if steps { kinds.insert(.steps) }
            if activeEnergy { kinds.insert(.activeEnergy) }
            if bodyRadar { kinds.insert(.bodyRadar) }
            return kinds
        }

        var selectedCards: Set<BodyHomeCardKind> {
            var cards: Set<BodyHomeCardKind> = []
            if basics { cards.insert(.basics) }
            if readiness { cards.insert(.readiness) }
            if vitals { cards.insert(.vitals) }
            if stress { cards.insert(.stress) }
            if heartRate { cards.insert(.heartRate) }
            if heartRateVariability { cards.insert(.heartRateVariability) }
            if sleep { cards.insert(.sleep) }
            if steps { cards.insert(.steps) }
            if activeEnergy { cards.insert(.activeEnergy) }
            if bodyRadar { cards.insert(.bodyRadar) }
            return cards
        }
    }

    /// Reproduces the OLD (pre-input-tier) `includes` semantics: a flat union
    /// with no full/input distinction. Stress used to expand into the full set
    /// of its dependencies exactly as basics/readiness/vitals do.
    private func legacyUnion(_ toggles: Toggles) -> Set<HealthMetricKind> {
        let direct = toggles.directKinds
        var union = direct

        if direct.contains(.basics) {
            union.formUnion(Self.basicsMetricKinds)
        }
        if direct.contains(.readiness) {
            union.formUnion(Self.readinessDependencyKinds)
        }
        if direct.contains(.vitals) {
            union.formUnion(Self.vitalsMetricKinds)
        }
        if direct.contains(.stress) {
            union.formUnion(Self.stressDependencyKinds)
        }
        if direct.contains(.bodyRadar) {
            union.formUnion(Self.bodyRadarDependencyKinds)
        }

        return union
    }

    private func selection(_ toggles: Toggles) -> BodyDashboardFetchSelection {
        BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: toggles.selectedCards),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [])
        )
    }

    // MARK: - Exhaustive equivalence

    /// All 1024 combinations of the ten toggles above. For each: `includes`
    /// must equal the legacy flat union for every `HealthMetricKind`, and the
    /// new full/input split must obey its invariants.
    func testIncludesMatchesLegacyUnionAcrossAllCombinations() throws {
        for bits in 0..<1_024 {
            let toggles = Toggles(bits: bits)
            let fetch = selection(toggles)
            let legacy = legacyUnion(toggles)

            for kind in HealthMetricKind.allCases {
                XCTAssertEqual(
                    fetch.includes(kind),
                    legacy.contains(kind),
                    "bits=\(bits) kind=\(kind) diverges from legacy union"
                )
            }

            // includesFullPayload(k) => includes(k)
            for kind in HealthMetricKind.allCases where fetch.includesFullPayload(kind) {
                XCTAssertTrue(fetch.includes(kind), "bits=\(bits) kind=\(kind)")
            }

            // isInputOnly(k) => includes(k) && !includesFullPayload(k)
            for kind in HealthMetricKind.allCases where fetch.isInputOnly(kind) {
                XCTAssertTrue(fetch.includes(kind), "bits=\(bits) kind=\(kind)")
                XCTAssertFalse(fetch.includesFullPayload(kind), "bits=\(bits) kind=\(kind)")
            }

            // The input-only set is a subset of the derived dependency kinds.
            let inputOnlyKinds = HealthMetricKind.allCases.filter(fetch.isInputOnly)
            XCTAssertTrue(
                Set(inputOnlyKinds).isSubset(
                    of: Self.stressDependencyKinds.union(Self.bodyRadarDependencyKinds)
                ),
                "bits=\(bits) input-only kinds \(inputOnlyKinds) escape the derived dependency sets"
            )

            // Neither derived card => no input-only kinds at all.
            if !toggles.stress, !toggles.bodyRadar {
                XCTAssertTrue(
                    inputOnlyKinds.isEmpty,
                    "bits=\(bits) input-only kinds without a derived card: \(inputOnlyKinds)"
                )
            }
        }
    }

    // MARK: - Targeted cases

    /// Stress alone renders no other card, so all five of its dependencies are
    /// fetched only as scoring inputs — none render a card payload.
    func testStressOnlyMarksAllFiveDependenciesInputOnly() throws {
        var toggles = Toggles(bits: 0)
        toggles.stress = true
        let fetch = selection(toggles)

        for kind in Self.stressDependencyKinds {
            XCTAssertTrue(fetch.isInputOnly(kind), "\(kind) should be input-only")
            XCTAssertFalse(fetch.includesFullPayload(kind), "\(kind) should not be full payload")
        }
        XCTAssertFalse(fetch.includes(.basics))
        XCTAssertFalse(fetch.includes(.readiness))
        XCTAssertFalse(fetch.includes(.vitals))
    }

    /// Rendering the Heart Rate card alongside Stress promotes heart rate to
    /// full payload; the other four dependencies stay input-only.
    func testStressWithHeartRateCardPromotesHeartRateToFullPayload() throws {
        var toggles = Toggles(bits: 0)
        toggles.stress = true
        toggles.heartRate = true
        let fetch = selection(toggles)

        XCTAssertTrue(fetch.includesFullPayload(.heartRate))
        XCTAssertFalse(fetch.isInputOnly(.heartRate))

        for kind in Self.stressDependencyKinds.subtracting([.heartRate]) {
            XCTAssertTrue(fetch.isInputOnly(kind), "\(kind) should remain input-only")
        }
    }

    /// Readiness's own expansion pulls sleep and HRV to full payload (they're
    /// readiness dependencies too); heart rate/steps/active energy — which
    /// readiness never reads — stay input-only.
    func testStressWithReadinessPromotesSleepAndHRVOnly() throws {
        var toggles = Toggles(bits: 0)
        toggles.stress = true
        toggles.readiness = true
        let fetch = selection(toggles)

        XCTAssertTrue(fetch.includesFullPayload(.sleep))
        XCTAssertTrue(fetch.includesFullPayload(.heartRateVariability))

        for kind: HealthMetricKind in [.heartRate, .steps, .activeEnergy] {
            XCTAssertTrue(fetch.isInputOnly(kind), "\(kind) should remain input-only")
        }
    }

    /// Vitals expands only into sleep, so it alone promotes sleep to full
    /// payload while the other four stress dependencies stay input-only.
    func testStressWithVitalsPromotesSleepOnly() throws {
        var toggles = Toggles(bits: 0)
        toggles.stress = true
        toggles.vitals = true
        let fetch = selection(toggles)

        XCTAssertTrue(fetch.includesFullPayload(.sleep))

        for kind in Self.stressDependencyKinds.subtracting([.sleep]) {
            XCTAssertTrue(fetch.isInputOnly(kind), "\(kind) should remain input-only")
        }
    }
}
