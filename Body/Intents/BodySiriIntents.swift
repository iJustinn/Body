//
//  BodySiriIntents.swift
//  Body
//
//  The actions Siri and Shortcuts can run. Each one reads Body's cached
//  snapshots through the answer builder, never HealthKit, and never on the
//  main actor.
//

import AppIntents
import Foundation

// MARK: - Metric enum

extension BodySiriMetric: AppEnum {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Health Metric")
    )

    /// Literal on purpose: App Intents metadata extraction requires a
    /// compile-time constant here. Kept in step with `HealthWidgetMetric.title`.
    static let caseDisplayRepresentations: [BodySiriMetric: DisplayRepresentation] = [
        .readiness: "Readiness",
        .sleep: "Sleep",
        .heartRateVariability: "HRV",
        .restingHeartRate: "Resting Heart Rate",
        .heartRate: "Heart Rate",
        .respiratoryRate: "Respiratory Rate",
        .oxygenSaturation: "Blood Oxygen",
        .wristTemperature: "Skin Temperature",
        .steps: "Steps",
        .exerciseMinutes: "Exercise Minutes"
    ]
}

// MARK: - Shared loading

/// Reads the snapshot bundle off the main actor. Intents can be performed from
/// a Siri request that cold launches Body, so this must stay cheap and pure.
private func loadSiriBundle() async -> BodySiriSnapshotBundle {
    await Task.detached(priority: .userInitiated) {
        BodySiriSnapshotBundle.loadCurrent()
    }.value
}

private func siriDialog(_ answer: BodySiriAnswer) -> IntentDialog {
    IntentDialog(full: "\(answer.spoken)", supporting: "\(answer.supporting)")
}

private func metricEntity(_ metric: BodySiriMetric, _ answer: BodySiriAnswer, now: Date) -> BodyHealthMetricEntity? {
    guard answer.hasValue else { return nil }
    return BodyHealthMetricEntity(
        metric: metric,
        valueText: answer.valueText,
        unit: answer.unit,
        status: answer.statusText,
        asOf: answer.asOf,
        applicableDate: (answer.asOf ?? now).formatted(
            Date.FormatStyle(date: .complete, time: .omitted)
        )
    )
}

// MARK: - Readiness

struct GetReadinessIntent: AppIntent {

    static let title: LocalizedStringResource = "Get Readiness"

    static let description = IntentDescription(
        "Reads today's readiness score from Body's cached health data.",
        categoryName: "Health"
    )

    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<BodyHealthMetricEntity?> {
        let bundle = await loadSiriBundle()
        let answer = BodySiriAnswerBuilder.readiness(bundle: bundle)
        return .result(
            value: metricEntity(.readiness, answer, now: bundle.now),
            dialog: siriDialog(answer)
        )
    }
}

// MARK: - Metric

struct GetHealthMetricIntent: AppIntent {

    static let title: LocalizedStringResource = "Get Health Metric"

    static let description = IntentDescription(
        "Reads one of Body's cached health metrics, like HRV, resting heart rate or sleep.",
        categoryName: "Health"
    )

    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Metric", requestValueDialog: "Which metric?")
    var metric: BodySiriMetric

    init() {}

    init(metric: BodySiriMetric) {
        self.metric = metric
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<BodyHealthMetricEntity?> {
        let bundle = await loadSiriBundle()
        let answer = BodySiriAnswerBuilder.metric(metric, bundle: bundle)
        return .result(
            value: metricEntity(metric, answer, now: bundle.now),
            dialog: siriDialog(answer)
        )
    }
}

// MARK: - Warnings

struct GetHealthWarningsIntent: AppIntent {

    static let title: LocalizedStringResource = "Get Health Warnings"

    static let description = IntentDescription(
        "Lists the health warnings in Body's cached data for today.",
        categoryName: "Health"
    )

    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[String]?> {
        let bundle = await loadSiriBundle()
        let answer = BodySiriAnswerBuilder.warnings(bundle: bundle)
        return .result(
            value: answer.hasValue ? answer.items : nil,
            dialog: siriDialog(answer)
        )
    }
}

// MARK: - Workouts

struct GetRecentWorkoutsIntent: AppIntent {

    static let title: LocalizedStringResource = "Get Workouts This Week"

    static let description = IntentDescription(
        "Counts the workouts Body has cached for this week.",
        categoryName: "Fitness"
    )

    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int?> {
        let bundle = await loadSiriBundle()
        let answer = BodySiriAnswerBuilder.recentWorkouts(bundle: bundle)
        return .result(
            value: answer.hasValue ? answer.count : nil,
            dialog: siriDialog(answer)
        )
    }
}

// MARK: - Shortcuts

struct BodyAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetReadinessIntent(),
            phrases: [
                "What's my readiness in \(.applicationName)",
                "How ready am I in \(.applicationName)",
                "What's my readiness score in \(.applicationName)",
                "How is my readiness in \(.applicationName)",
                "How is my readiness score in \(.applicationName)",
                "How's my readiness today in \(.applicationName)"
            ],
            shortTitle: "Readiness",
            systemImageName: "bolt.heart"
        )
        AppShortcut(
            intent: GetHealthWarningsIntent(),
            phrases: [
                "Any health warnings in \(.applicationName)"
            ],
            shortTitle: "Health Warnings",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: GetRecentWorkoutsIntent(),
            phrases: [
                "My workouts this week in \(.applicationName)"
            ],
            shortTitle: "Workouts This Week",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: GetHealthMetricIntent(metric: .sleep),
            phrases: [
                "How did I sleep in \(.applicationName)"
            ],
            shortTitle: "Sleep",
            systemImageName: "bed.double"
        )
        AppShortcut(
            intent: GetHealthMetricIntent(),
            phrases: [
                "What's my \(\.$metric) in \(.applicationName)"
            ],
            shortTitle: "Health Metric",
            systemImageName: "heart.text.square"
        )
    }
}
