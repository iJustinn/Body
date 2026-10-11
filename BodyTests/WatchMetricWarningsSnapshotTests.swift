//
//  WatchMetricWarningsSnapshotTests.swift
//  BodyTests
//
//  The metric warnings payload on the watch snapshot (`metricWarnings`,
//  `heroShowsWarnings`): it survives phone/watch version skew (an older
//  payload omits both keys, and nil fields write none), round-trips through
//  the snapshot's encoding, is dropped after midnight by `sanitized(asOf:)`,
//  follows phone pushes and survives watch computes with no merge rule of its
//  own, and its kinds land on the cards whose keys the watch uses.
//

import XCTest
@testable import Body

final class WatchMetricWarningsSnapshotTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// 15:00 on 2026-10-04 in the test's time zone, whole seconds so the
    /// fixtures survive the ISO 8601 round trip.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 15))!
    }

    private func warning(_ kind: MetricWarningKind, hour: Int, dayOffset: Int = 0, isFolded: Bool = false, foldChangedAt: Date? = nil) -> WatchMetricWarning {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: now)!
        let start = calendar.date(bySettingHour: hour, minute: 12, second: 0, of: day)!
        let dayText = String(
            format: "%04d-%02d-%02d",
            calendar.component(.year, from: start),
            calendar.component(.month, from: start),
            calendar.component(.day, from: start)
        )
        return WatchMetricWarning(
            kind: kind.rawValue,
            startDate: start,
            threshold: kind.defaultThreshold,
            foldKey: "\(kind.rawValue)@\(dayText)",
            isFolded: isFolded,
            foldChangedAt: foldChangedAt
        )
    }

    private func snapshot(
        warnings: [WatchMetricWarning]? = nil,
        heroShowsWarnings: Bool? = nil,
        generatedAt: Date? = nil
    ) -> WatchMetricsSnapshot {
        var snapshot = WatchMetricsSnapshot(
            generatedAt: generatedAt ?? now,
            lastRefreshDate: generatedAt ?? now,
            metrics: [],
            source: "phone",
            publisherEpoch: "epoch-A",
            revision: 7
        )
        snapshot.metricWarnings = warnings
        snapshot.heroShowsWarnings = heroShowsWarnings
        return snapshot
    }

    // MARK: - Schema evolution

    func testEncodeDecodeRoundTripsTheWarningsAndTheHeroFlag() throws {
        let original = snapshot(
            warnings: [
                warning(.lowHeartRate, hour: 3, isFolded: true, foldChangedAt: now.addingTimeInterval(-60)),
                warning(.highWristTemperature, hour: 6)
            ],
            heroShowsWarnings: false
        )
        let data = try XCTUnwrap(original.encoded())

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: data))

        XCTAssertEqual(decoded.metricWarnings, original.metricWarnings)
        XCTAssertEqual(decoded.heroShowsWarnings, false)
        XCTAssertEqual(decoded, original)
    }

    /// A phone with no warnings today (or an older phone) adds nothing to
    /// the push.
    func testNilFieldsWriteNoKey() throws {
        let data = try XCTUnwrap(snapshot().encoded())
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("metricWarnings"))
        XCTAssertFalse(json.contains("heroShowsWarnings"))
    }

    func testAPayloadWithoutTheFieldsDecodesThemAsNil() throws {
        let json = """
        {
          "generatedAt": "2026-10-04T07:00:00Z",
          "metrics": []
        }
        """

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: Data(json.utf8)))

        XCTAssertNil(decoded.metricWarnings)
        XCTAssertNil(decoded.heroShowsWarnings)
    }

    // MARK: - Midnight

    func testSanitizeDropsYesterdaysWarningAndKeepsTodays() {
        let todays = warning(.highHeartRate, hour: 9)
        let yesterdays = warning(.lowHeartRate, hour: 23, dayOffset: -1)

        let sanitized = snapshot(warnings: [yesterdays, todays], heroShowsWarnings: true).sanitized(asOf: now)

        XCTAssertEqual(sanitized.metricWarnings, [todays])
        XCTAssertEqual(sanitized.heroShowsWarnings, true, "the phone's switch is not a day's data")
    }

    func testSanitizeClearsTheFieldWhenNoWarningRemains() {
        let yesterdays = snapshot(warnings: [warning(.highWristTemperature, hour: 6, dayOffset: -1)])
        XCTAssertNil(yesterdays.sanitized(asOf: now).metricWarnings)

        // Nil is the one "no warnings", so an empty list normalizes to it.
        XCTAssertNil(snapshot(warnings: []).sanitized(asOf: now).metricWarnings)
    }

    func testSanitizeReturnsTheSnapshotUnchangedWhenEveryWarningIsTodays() {
        let original = snapshot(warnings: [warning(.lowHeartRate, hour: 0), warning(.highHeartRate, hour: 14)], heroShowsWarnings: true)

        XCTAssertEqual(original.sanitized(asOf: now), original)
        XCTAssertEqual(snapshot().sanitized(asOf: now), snapshot())
    }

    // MARK: - Merge

    /// The warnings and the hero flag are the phone's display payload: every
    /// push brings its own, including nil from an older phone or a day with
    /// no warnings, and the merge has no rule that could keep the old ones.
    func testAPushBringsItsOwnWarningsAndFlag() {
        let current = snapshot(warnings: [warning(.highHeartRate, hour: 9)], heroShowsWarnings: true)
        let push = snapshot(
            warnings: [warning(.highHeartRate, hour: 9, isFolded: true, foldChangedAt: now)],
            heroShowsWarnings: false,
            generatedAt: now.addingTimeInterval(60)
        )

        let merged = WatchComputeMerge.merging(push, over: current)
        XCTAssertEqual(merged.metricWarnings, push.metricWarnings)
        XCTAssertEqual(merged.heroShowsWarnings, false)

        let olderPhone = snapshot(generatedAt: now.addingTimeInterval(120))
        let mergedOlder = WatchComputeMerge.merging(olderPhone, over: current)
        XCTAssertNil(mergedOlder.metricWarnings)
        XCTAssertNil(mergedOlder.heroShowsWarnings)
    }

    /// A watch compute never touches them: the merge starts from the current
    /// snapshot, so whatever the computed snapshot carries is ignored.
    func testAWatchComputeKeepsTheCurrentWarningsAndFlag() {
        let current = snapshot(warnings: [warning(.lowHeartRate, hour: 4)], heroShowsWarnings: false)
        var computed = snapshot(generatedAt: now.addingTimeInterval(60))
        computed.source = "watch"
        let result = WatchComputeResult(
            snapshot: computed,
            dataAsOf: [WatchMetricKindKey.heartRate: now.addingTimeInterval(60)],
            coverage: now.addingTimeInterval(60),
            generation: 3
        )

        let merged = WatchComputeMerge.mergingComputed(result, into: current)

        XCTAssertEqual(merged.metricWarnings, current.metricWarnings)
        XCTAssertEqual(merged.heroShowsWarnings, false)
    }

    // MARK: - Card keys

    /// The phone matches a warning to a watch card by its metric's raw value,
    /// and the watch draws it on the card with that `WatchMetricKindKey`. A
    /// mismatch would publish nothing while every fixture test still passed.
    func testCardedWarningKindsMatchTheirWatchCardKeys() {
        XCTAssertEqual(MetricWarningKind.lowHeartRate.metric.rawValue, WatchMetricKindKey.heartRate)
        XCTAssertEqual(MetricWarningKind.highHeartRate.metric.rawValue, WatchMetricKindKey.heartRate)
        XCTAssertEqual(MetricWarningKind.lowBloodOxygen.metric.rawValue, WatchMetricKindKey.oxygenSaturation)
        XCTAssertEqual(MetricWarningKind.highWristTemperature.metric.rawValue, WatchMetricKindKey.wristTemperature)
    }
}
