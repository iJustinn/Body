//
//  HealthWidgetSnapshotMigrationTests.swift
//  BodyTests
//
//  Verifies that HealthWidgetMetricTrend still decodes snapshots written by the
//  previous widget build, whose schema stored `week`/`month` as
//  `{ primary, secondary }` range trends and had no `displayValues`. Without the
//  tolerant decoder, an existing on-disk cache fails to decode and the widget
//  blanks out until the app rewrites it.
//

import XCTest
@testable import Body

final class HealthWidgetSnapshotMigrationTests: XCTestCase {
    // Mirrors the previous (pre-redesign) on-disk schema so the test can write
    // legacy bytes with the same encoder the old app used.
    private struct LegacyTrendSeries: Encodable {
        var points: [HealthWidgetPoint]
        var averageText: String?
    }

    private struct LegacyRangeTrend: Encodable {
        var primary: LegacyTrendSeries
        var secondary: LegacyTrendSeries?
    }

    private struct LegacyMetricTrend: Encodable {
        var metric: HealthWidgetMetric
        var primarySourceName: String?
        var secondarySourceName: String?
        var week: LegacyRangeTrend
        var month: LegacyRangeTrend
    }

    func testDecodesLegacyMetricTrendShape() throws {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let legacy = LegacyMetricTrend(
            metric: .heartRate,
            primarySourceName: "Apple Watch",
            secondarySourceName: "iPhone",
            week: LegacyRangeTrend(
                primary: LegacyTrendSeries(
                    points: [
                        HealthWidgetPoint(date: base, value: 60),
                        HealthWidgetPoint(date: base.addingTimeInterval(day), value: 64)
                    ],
                    averageText: "62 BPM"
                ),
                secondary: LegacyTrendSeries(
                    points: [HealthWidgetPoint(date: base, value: 70)],
                    averageText: "70 BPM"
                )
            ),
            month: LegacyRangeTrend(
                primary: LegacyTrendSeries(
                    points: [HealthWidgetPoint(date: base, value: 61)],
                    averageText: "61 BPM"
                ),
                secondary: nil
            )
        )

        // Same default encoder/decoder configuration the snapshot store uses.
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(HealthWidgetMetricTrend.self, from: data)

        XCTAssertEqual(decoded.metric, .heartRate)
        XCTAssertEqual(decoded.primarySourceName, "Apple Watch")
        // week/month are recovered from the legacy `primary` series.
        XCTAssertEqual(decoded.week.points.compactMap(\.value), [60, 64])
        XCTAssertEqual(decoded.week.averageText, "62 BPM")
        XCTAssertEqual(decoded.month.points.compactMap(\.value), [61])
        XCTAssertEqual(decoded.month.averageText, "61 BPM")
        // Legacy caches predate `latestText`, so it stays nil even though the value
        // is still recoverable from the points. The trend footer relies on this by
        // hiding the "Latest" label (instead of showing "Latest --") until the app
        // refreshes and rewrites the cache.
        XCTAssertNil(decoded.week.latestText)
        XCTAssertEqual(decoded.week.latest, 64)
        // displayValues did not exist in the legacy schema → defaults to empty.
        XCTAssertEqual(decoded.displayValues, [])
    }

    func testRoundTripsCurrentMetricTrend() throws {
        let trend = HealthWidgetMetricTrend(
            metric: .bodyMass,
            primarySourceName: "Withings",
            week: HealthWidgetTrendSeries(
                points: [HealthWidgetPoint(date: Date(timeIntervalSinceReferenceDate: 700_000_000), value: 70)],
                averageText: "70 kg",
                latestText: "70 kg"
            ),
            month: .empty,
            displayValues: [HealthWidgetDisplayValue(value: "70.0", unit: "kg")]
        )

        let data = try JSONEncoder().encode(trend)
        let decoded = try JSONDecoder().decode(HealthWidgetMetricTrend.self, from: data)

        XCTAssertEqual(decoded, trend)
    }
}
