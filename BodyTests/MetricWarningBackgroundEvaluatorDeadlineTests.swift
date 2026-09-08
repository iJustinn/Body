//
//  MetricWarningBackgroundEvaluatorDeadlineTests.swift
//  BodyTests
//
//  The background metric-warning evaluation runs inside a BGAppRefresh window
//  (~30 s wall clock). A HealthKit read that never resumes — a locked device,
//  a store that never answers — must not pin the task until the system kills
//  it: the deadline has to win and hand back `nil` (H-03).
//
//  `FakeHealthStore`'s unscripted reads are exactly that never-resuming read,
//  so this drives the real race rather than a source-text grep of it.
//

import XCTest
import HealthKit
@testable import Body

final class MetricWarningBackgroundEvaluatorDeadlineTests: XCTestCase {
    func testFetchWarningsGivesUpAtItsDeadlineWhenHealthKitNeverAnswers() async throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let evaluator = MetricWarningBackgroundEvaluator(
            defaults: defaults,
            calendar: .bodyGregorian,
            healthStore: FakeHealthStore(),
            isForegroundActive: { false }
        )

        let deadline: Duration = .milliseconds(300)
        let started = Date()
        let warnings = await evaluator.fetchWarnings(kinds: [.lowHeartRate], deadline: deadline)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertNil(warnings, "an unanswered HealthKit read must lose to the deadline")
        // Margin covers scheduling jitter on a loaded simulator while still
        // failing loudly if the deadline is not enforced at all (the real
        // fetch would otherwise hang forever).
        XCTAssertLessThan(elapsed, 5, "the evaluation must return at its deadline, not hang")
    }
}
