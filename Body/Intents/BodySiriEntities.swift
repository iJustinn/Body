//
//  BodySiriEntities.swift
//  Body
//
//  The entity Siri and Spotlight see for each metric Body has a cached value
//  for. Thin adapters over `BodySiriAnswerBuilder`: no HealthKit, no formatting
//  rules of their own beyond the dated prose Spotlight stores.
//

import AppIntents
import CoreSpotlight
import Foundation

// MARK: - Entity

struct BodyHealthMetricEntity: AppEntity, IndexedEntity, Sendable {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Health Metric")
    )

    static let defaultQuery = BodyHealthMetricEntityQuery()

    /// Stable across refreshes so Spotlight updates a row instead of adding one.
    var id: String
    var metric: BodySiriMetric

    @Property(title: "Value")
    var valueText: String?

    @Property(title: "Unit")
    var unit: String?

    @Property(title: "Measured")
    var asOf: Date?

    /// The day the value belongs to, spelled out so indexed prose cannot
    /// outlive the day it describes.
    @Property(title: "Date")
    var applicableDate: String

    init(
        metric: BodySiriMetric,
        valueText: String?,
        unit: String?,
        asOf: Date?,
        applicableDate: String
    ) {
        self.id = metric.rawValue
        self.metric = metric
        self.valueText = valueText
        self.unit = unit
        self.asOf = asOf
        self.applicableDate = applicableDate
    }

    /// "45 ms" or just "45" when the metric carries no unit.
    var readingText: String {
        guard let valueText, !valueText.isEmpty else { return "" }
        guard let unit, !unit.isEmpty else { return valueText }
        return "\(valueText) \(unit)"
    }

    var displayRepresentation: DisplayRepresentation {
        let reading = readingText
        let subtitle: String
        if let asOf {
            subtitle = String(
                localized: "\(reading), snapshot from \(Self.snapshotText(asOf))"
            )
        } else {
            subtitle = reading
        }
        return DisplayRepresentation(
            title: "\(metric.title)",
            subtitle: "\(subtitle)"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = metric.title
        set.contentDescription = String(
            localized: "Body \(Self.indexedName(for: metric)) on \(applicableDate): \(readingText)"
        )
        set.keywords = [metric.title, String(localized: "Body"), String(localized: "health")]
        return set
    }

    // MARK: Building

    /// Only metrics Body actually has a value for. Everything else is dropped so
    /// the delete-then-index pass removes stale rows.
    static func entities(from bundle: BodySiriSnapshotBundle) -> [BodyHealthMetricEntity] {
        BodySiriMetric.allCases.compactMap { metric in
            let answer = BodySiriAnswerBuilder.metric(metric, bundle: bundle)
            guard answer.hasValue else { return nil }
            return BodyHealthMetricEntity(
                metric: metric,
                valueText: answer.valueText,
                unit: answer.unit,
                asOf: answer.asOf,
                applicableDate: longDateText(answer.asOf ?? bundle.now)
            )
        }
    }

    /// Readiness is the live score, not a morning history value, and the
    /// indexed prose says so.
    private static func indexedName(for metric: BodySiriMetric) -> String {
        metric == .readiness ? String(localized: "live readiness") : metric.title
    }

    private static func longDateText(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .complete, time: .omitted)
        )
    }

    private static func snapshotText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Query

struct BodyHealthMetricEntityQuery: EntityQuery, EnumerableEntityQuery {

    func entities(for identifiers: [BodyHealthMetricEntity.ID]) async throws -> [BodyHealthMetricEntity] {
        let wanted = Set(identifiers)
        return await Self.currentEntities().filter { wanted.contains($0.id) }
    }

    func allEntities() async throws -> [BodyHealthMetricEntity] {
        await Self.currentEntities()
    }

    /// Detached so the snapshot files are never read on the main actor.
    private static func currentEntities() async -> [BodyHealthMetricEntity] {
        await Task.detached(priority: .utility) {
            BodyHealthMetricEntity.entities(from: .loadCurrent())
        }.value
    }
}

/// `IndexedEntityQuery` is iOS 27 only. On iOS 18 to 26 the coordinator's own
/// scheduling is the repair path.
@available(iOS 27, *)
extension BodyHealthMetricEntityQuery: IndexedEntityQuery {

    func reindexEntities(
        for identifiers: [BodyHealthMetricEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        try await BodySiriIndexCoordinator.shared.reindexNow()
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await BodySiriIndexCoordinator.shared.reindexNow()
    }
}
