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
    /// compile-time constant here. Titles kept in step with
    /// `HealthWidgetMetric.title`; the synonyms are other names people say.
    static let caseDisplayRepresentations: [BodySiriMetric: DisplayRepresentation] = [
        .readiness: DisplayRepresentation(title: "Readiness", synonyms: ["Readiness Score", "Recovery"]),
        .sleep: DisplayRepresentation(title: "Sleep", synonyms: ["Sleep Score"]),
        .heartRateVariability: DisplayRepresentation(title: "HRV", synonyms: ["Heart Rate Variability"]),
        .restingHeartRate: DisplayRepresentation(title: "Resting Heart Rate", synonyms: ["Resting HR"]),
        .heartRate: DisplayRepresentation(title: "Heart Rate", synonyms: ["Pulse"]),
        .respiratoryRate: DisplayRepresentation(title: "Respiratory Rate", synonyms: ["Breathing Rate"]),
        .oxygenSaturation: DisplayRepresentation(title: "Blood Oxygen", synonyms: ["Oxygen", "SpO2"]),
        .wristTemperature: DisplayRepresentation(title: "Skin Temperature", synonyms: ["Wrist Temperature", "Temperature"]),
        .steps: DisplayRepresentation(title: "Steps", synonyms: ["Step Count"]),
        .exerciseMinutes: DisplayRepresentation(title: "Exercise Minutes", synonyms: ["Exercise"])
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
        "Reads today's readiness score from Body's cached health data, and the start of day score when workouts lowered it.",
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

// MARK: - Status

struct GetBodyStatusIntent: AppIntent {

    static let title: LocalizedStringResource = "Get Body Status"

    static let description = IntentDescription(
        "Reads today's readiness, what is moving it and any health warnings from Body's cached data.",
        categoryName: "Health"
    )

    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<BodyHealthMetricEntity?> {
        let bundle = await loadSiriBundle()
        let answer = BodySiriAnswerBuilder.status(bundle: bundle)
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

    /// Siri only runs an action on one of these phrases (the app name may be
    /// "ohmybody" or its alternative "Body"); anything else goes to Siri's own
    /// model, which cannot see Body's data. Keep the wording people actually
    /// use, and keep `AppShortcuts.xcstrings` in step.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetBodyStatusIntent(),
            phrases: [
                "How's my status in \(.applicationName)",
                "How's my status look in \(.applicationName)",
                "How's my status look like in \(.applicationName)",
                "What's my status in \(.applicationName)",
                "Check my status in \(.applicationName)",
                "How am I doing in \(.applicationName)",
                "How am I doing today in \(.applicationName)",
                "How's my body today in \(.applicationName)",
                "Give me my summary in \(.applicationName)",
                "My daily summary in \(.applicationName)",
                "Check \(.applicationName)"
            ],
            shortTitle: "Status",
            systemImageName: "heart.text.clipboard"
        )
        AppShortcut(
            intent: GetReadinessIntent(),
            phrases: [
                "What's my readiness in \(.applicationName)",
                "How ready am I in \(.applicationName)",
                "What's my readiness score in \(.applicationName)",
                "How is my readiness in \(.applicationName)",
                "How is my readiness score in \(.applicationName)",
                "How's my readiness today in \(.applicationName)",
                "What's my readiness today in \(.applicationName)",
                "Give me my readiness score in \(.applicationName)",
                "Check my readiness in \(.applicationName)",
                "Show my readiness in \(.applicationName)",
                "What's my start of day readiness in \(.applicationName)",
                "How is the start of day readiness score in \(.applicationName)",
                "What was my morning readiness in \(.applicationName)",
                "Am I ready to train in \(.applicationName)"
            ],
            shortTitle: "Readiness",
            systemImageName: "bolt.heart"
        )
        AppShortcut(
            intent: GetHealthWarningsIntent(),
            phrases: [
                "Any health warnings in \(.applicationName)",
                "Any warnings today in \(.applicationName)",
                "Are there any warnings in \(.applicationName)",
                "Is there any warnings today in \(.applicationName)",
                "Do I have any warnings in \(.applicationName)",
                "Do I have any health warnings in \(.applicationName)",
                "What are my warnings in \(.applicationName)",
                "Show my health warnings in \(.applicationName)"
            ],
            shortTitle: "Health Warnings",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: GetRecentWorkoutsIntent(),
            phrases: [
                "My workouts this week in \(.applicationName)",
                "How many workouts this week in \(.applicationName)",
                "How many workouts did I do this week in \(.applicationName)",
                "Show my workouts this week in \(.applicationName)"
            ],
            shortTitle: "Workouts This Week",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: GetHealthMetricIntent(metric: .sleep),
            phrases: [
                "How did I sleep in \(.applicationName)",
                "How did I sleep last night in \(.applicationName)",
                "How was my sleep in \(.applicationName)",
                "What's my sleep score in \(.applicationName)"
            ],
            shortTitle: "Sleep",
            systemImageName: "bed.double"
        )
        AppShortcut(
            intent: GetHealthMetricIntent(),
            phrases: [
                "What's my \(\.$metric) in \(.applicationName)",
                "How's my \(\.$metric) in \(.applicationName)",
                "What's my \(\.$metric) today in \(.applicationName)",
                "Show my \(\.$metric) in \(.applicationName)"
            ],
            shortTitle: "Health Metric",
            systemImageName: "heart.text.square"
        )
    }
}
