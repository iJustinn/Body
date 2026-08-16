//
//  ReadinessCommentGeneratorTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Covers the plain helpers behind the Apple Intelligence readiness comment —
/// the prompt builder, the signature, and the cache. The generator itself needs
/// an on-device model (iOS 26 + Apple Intelligence), so nothing here touches
/// `ReadinessCommentGenerator` or FoundationModels.
final class ReadinessCommentGeneratorTests: XCTestCase {
    private let fixedDay = Date(timeIntervalSince1970: 1_700_000_000)
    private let englishLocale = Locale(identifier: "en_US")

    private func readiness(
        score: Int? = 72,
        status: ReadinessStatus = .high,
        componentScores: [ReadinessComponentKind: Int] = [.autonomic: 68, .sleep: 80],
        drivers: [ReadinessDriver] = [
            ReadinessDriver(kind: .hrvBelowBaseline, message: "HRV sits below your baseline.", impact: -0.4),
            ReadinessDriver(kind: .sleepFragmented, message: "Sleep was broken up last night.", impact: -0.2)
        ],
        drainMorningScore: Int? = nil,
        drainPoints: Int? = nil
    ) -> ReadinessSummary {
        let components = componentScores
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { kind, value in
                ReadinessComponent(
                    kind: kind,
                    score: value,
                    weight: 0.3,
                    message: "Component message for \(kind.rawValue)."
                )
            }

        return ReadinessSummary(
            score: score,
            status: status,
            confidence: .high,
            components: components,
            drivers: drivers,
            activityDrainMorningScore: drainMorningScore,
            activityDrainPoints: drainPoints
        )
    }

    // MARK: - Prompt builder

    func testPromptCarriesStatusAndDriversButNoNumbers() {
        let summary = readiness()
        let prompt = ReadinessCommentPromptBuilder.prompt(for: summary)

        XCTAssertTrue(prompt.contains(summary.status.title))
        // The authored line is the reference the model rewords — its meaning, cause
        // and advice are already right for this band/driver/drain, so the model is
        // never left guessing.
        XCTAssertTrue(prompt.contains("Reference comment: \(summary.heroExplanation)"))
        XCTAssertTrue(prompt.contains("Reword the reference comment now."))
        XCTAssertTrue(
            ReadinessCommentPromptBuilder.instructions(locale: englishLocale)
                .contains("reword the reference, not to write something new")
        )
        // The prompt is a decided brief. Drivers are the "Below usual" list the
        // instructions require the model to name — a device once skipped HRV and
        // blamed "morning movement" instead.
        XCTAssertTrue(prompt.contains("Below usual (most important first; name each one):"))
        for driver in summary.drivers {
            XCTAssertTrue(prompt.contains(driver.message), driver.message)
        }
        XCTAssertTrue(prompt.contains("Training verdict: yes."))
        XCTAssertTrue(prompt.contains("Advice: Train as planned"))
        XCTAssertTrue(
            ReadinessCommentPromptBuilder.instructions(locale: englishLocale)
                .contains("Never tell someone whose verdict is \"yes\" to rest")
        )

        // Whatever the prompt carries gets quoted back — a device once echoed
        // "Signum HRV below baseline, impact 0.02" in Latin, another recited its
        // component scores. The comment is readiness-only and the score is already on
        // the hero, so no number, kind name, weight, or component reaches the model.
        XCTAssertFalse(prompt.contains("72"))
        XCTAssertFalse(prompt.contains("hrvBelowBaseline"))
        XCTAssertFalse(prompt.contains("weight"))
        XCTAssertFalse(prompt.contains("impact"))
        for component in summary.components {
            XCTAssertFalse(prompt.contains(component.message), component.message)
        }
        XCTAssertNil(prompt.rangeOfCharacter(from: .decimalDigits), prompt)
    }

    func testPromptSaysNothingStandsOutForTypicalSignals() {
        let typical = readiness(drivers: [
            ReadinessDriver(kind: .mostlyTypical, message: "Readiness signals are mostly typical.", impact: 0)
        ])
        let prompt = ReadinessCommentPromptBuilder.prompt(for: typical)

        XCTAssertTrue(prompt.contains("Below usual: none."))
        XCTAssertFalse(prompt.contains("name each one"))
    }

    func testPromptNeverNamesInternalAreas() {
        // Only vitals flagged on a High day — the exact case a device once answered
        // with "Take it easy today", then padded with "your sleep, autonomic, and
        // training are all good". Area names mean nothing to the reader, so the
        // brief carries only the flagged signal and the verdict.
        let summary = readiness(
            componentScores: [.autonomic: 80, .sleep: 84, .vitals: 60],
            drivers: [ReadinessDriver(kind: .respiratoryRateAboveBaseline, message: "Respiratory rate is above baseline.", impact: -0.2)]
        )
        let prompt = ReadinessCommentPromptBuilder.prompt(for: summary)

        XCTAssertTrue(prompt.contains("Below usual (most important first; name each one): Respiratory rate is above baseline."))
        XCTAssertTrue(prompt.contains("Training verdict: yes."))
        XCTAssertFalse(prompt.contains("Looking good"))
        XCTAssertFalse(prompt.lowercased().contains("autonomic"))
        XCTAssertFalse(prompt.lowercased().contains("training are"))
    }

    func testTrainingVerdictFollowsTheBandAndWorkoutDrain() {
        XCTAssertTrue(ReadinessCommentPromptBuilder.trainingVerdict(for: .prime, meaningfulDrain: false).trains)
        XCTAssertTrue(ReadinessCommentPromptBuilder.trainingVerdict(for: .high, meaningfulDrain: false).trains)
        XCTAssertTrue(ReadinessCommentPromptBuilder.trainingVerdict(for: .moderate, meaningfulDrain: false).trains)
        XCTAssertFalse(ReadinessCommentPromptBuilder.trainingVerdict(for: .low, meaningfulDrain: false).trains)
        XCTAssertFalse(ReadinessCommentPromptBuilder.trainingVerdict(for: .poor, meaningfulDrain: false).trains)
        // A real same-day workout drain turns moderate into "you've done your work".
        XCTAssertFalse(ReadinessCommentPromptBuilder.trainingVerdict(for: .moderate, meaningfulDrain: true).trains)
        // High stays a training day even after a workout drain.
        XCTAssertTrue(ReadinessCommentPromptBuilder.trainingVerdict(for: .high, meaningfulDrain: true).trains)

        let drained = ReadinessCommentPromptBuilder.prompt(
            for: readiness(score: 64, status: .moderate, drainMorningScore: 80, drainPoints: 16)
        )
        XCTAssertTrue(drained.contains("Training verdict: no."))
    }

    func testPromptOmitsDrainSentenceWithoutADrain() {
        let prompt = ReadinessCommentPromptBuilder.prompt(for: readiness())

        XCTAssertFalse(prompt.contains("lowered readiness"))
    }

    func testPromptDescribesWorkoutDrainQualitatively() {
        let meaningful = ReadinessCommentPromptBuilder.prompt(
            for: readiness(score: 64, drainMorningScore: 80, drainPoints: 16)
        )
        XCTAssertTrue(meaningful.contains("noticeably lowered readiness"))
        XCTAssertTrue(meaningful.contains("training load, not poor recovery"))
        XCTAssertNil(meaningful.rangeOfCharacter(from: .decimalDigits), meaningful)

        let light = ReadinessCommentPromptBuilder.prompt(
            for: readiness(score: 70, drainMorningScore: 74, drainPoints: 4)
        )
        XCTAssertTrue(light.contains("slightly lowered readiness"))
        XCTAssertFalse(light.contains("noticeably"))
    }

    func testInstructionsBoundLengthAndNameTheReadersLanguage() {
        let english = ReadinessCommentPromptBuilder.instructions(locale: englishLocale)

        XCTAssertTrue(english.contains("One or two sentences"))
        XCTAssertTrue(english.contains("Write the comment in English"))

        let chinese = ReadinessCommentPromptBuilder.instructions(locale: Locale(identifier: "zh-Hans"))

        XCTAssertTrue(chinese.contains("One or two sentences"))
        XCTAssertTrue(chinese.lowercased().contains("chinese"))
        XCTAssertFalse(chinese.contains("Write the comment in English"))
    }

    func testInstructionsNeverNameLatinScriptOrAllowAppMentions() {
        // "en" + script "Latn" once resolved to "English (Latin)" and a device
        // dutifully wrote its comment in Latin. The script may only surface for
        // Chinese, where it distinguishes Simplified from Traditional.
        let scripted = ReadinessCommentPromptBuilder.instructions(
            locale: Locale(identifier: "en_Latn_US")
        )
        XCTAssertTrue(scripted.contains("Write the comment in English."))
        XCTAssertFalse(scripted.contains("Latin"))

        let english = ReadinessCommentPromptBuilder.instructions(locale: englishLocale)
        XCTAssertTrue(english.contains("Never mention the app, Apple Health"))
        XCTAssertTrue(english.contains("Never mention any number, score, percentage, or points"))
    }

    // MARK: - Signature

    private func signature(
        for summary: ReadinessSummary,
        day: Date? = nil,
        locale: Locale? = nil
    ) -> String {
        ReadinessCommentSignature.signature(
            for: summary,
            day: day ?? fixedDay,
            locale: locale ?? englishLocale
        )
    }

    func testSignatureIsStableForIdenticalInput() {
        XCTAssertEqual(signature(for: readiness()), signature(for: readiness()))
    }

    func testSignatureChangesWithScore() {
        XCTAssertNotEqual(signature(for: readiness()), signature(for: readiness(score: 73)))
    }

    func testSignatureChangesWithDriverSet() {
        let fewerDrivers = readiness(drivers: [
            ReadinessDriver(kind: .hrvBelowBaseline, message: "HRV sits below your baseline.", impact: -0.4)
        ])
        let differentImpact = readiness(drivers: [
            ReadinessDriver(kind: .hrvBelowBaseline, message: "HRV sits below your baseline.", impact: -0.4),
            ReadinessDriver(kind: .sleepFragmented, message: "Sleep was broken up last night.", impact: -0.9)
        ])

        XCTAssertNotEqual(signature(for: readiness()), signature(for: fewerDrivers))
        XCTAssertNotEqual(signature(for: readiness()), signature(for: differentImpact))
    }

    func testSignatureChangesWithComponentScores() {
        let shifted = readiness(componentScores: [.autonomic: 61, .sleep: 80])

        XCTAssertNotEqual(signature(for: readiness()), signature(for: shifted))
    }

    func testSignatureChangesWithWorkoutDrain() {
        let drained = readiness(score: 64, drainMorningScore: 80, drainPoints: 16)
        let deeper = readiness(score: 64, drainMorningScore: 80, drainPoints: 20)
        let differentMorning = readiness(score: 64, drainMorningScore: 84, drainPoints: 16)

        XCTAssertNotEqual(signature(for: readiness(score: 64)), signature(for: drained))
        XCTAssertNotEqual(signature(for: drained), signature(for: deeper))
        XCTAssertNotEqual(signature(for: drained), signature(for: differentMorning))
    }

    func testSignatureChangesWithDayRollover() {
        let tomorrow = fixedDay.addingTimeInterval(24 * 60 * 60)

        XCTAssertNotEqual(signature(for: readiness()), signature(for: readiness(), day: tomorrow))
    }

    func testSignatureChangesWithLocale() {
        XCTAssertNotEqual(
            signature(for: readiness()),
            signature(for: readiness(), locale: Locale(identifier: "zh-Hans"))
        )
    }

    // MARK: - Cache

    func testCacheRoundTripsAndClears() throws {
        // The cache hardcodes `UserDefaults.standard`, so preserve whatever the
        // running simulator already had under the key.
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: ReadinessCommentCache.defaultsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ReadinessCommentCache.defaultsKey)
            } else {
                defaults.removeObject(forKey: ReadinessCommentCache.defaultsKey)
            }
        }

        ReadinessCommentCache.clear()
        XCTAssertNil(ReadinessCommentCache.load())

        let record = ReadinessCommentCache.Record(
            signature: signature(for: readiness()),
            text: "You're holding up well today.",
            generatedAt: fixedDay
        )
        ReadinessCommentCache.save(record)

        let loaded = try XCTUnwrap(ReadinessCommentCache.load())
        XCTAssertEqual(loaded.signature, record.signature)
        XCTAssertEqual(loaded.text, record.text)
        XCTAssertEqual(loaded.generatedAt.timeIntervalSince1970, record.generatedAt.timeIntervalSince1970, accuracy: 0.001)

        ReadinessCommentCache.clear()
        XCTAssertNil(ReadinessCommentCache.load())
    }
}
