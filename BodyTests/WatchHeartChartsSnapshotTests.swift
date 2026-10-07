//
//  WatchHeartChartsSnapshotTests.swift
//  BodyTests
//
//  The `heartCharts` payload the watch's Heart Rate and HRV chart complications
//  draw: it survives phone/watch version skew (an older payload omits the key,
//  and a phone, which never sets it, publishes no key at all, so the push is
//  unchanged), round-trips through the snapshot's encoding, and the gallery
//  placeholder carries sample slots and a 12 hour Stress timeline that still
//  end on the sample cards' readings.
//

import XCTest
@testable import Body

final class WatchHeartChartsSnapshotTests: XCTestCase {
    private func moment(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: hour, minute: minute))!
    }

    private func chart(slots: [(minutes: Double, average: Double)]) -> WatchIntradayChart {
        let window = WatchIntradayWindow(start: moment(8, 30), end: moment(16, 45), plotEnd: moment(17, 0))
        return WatchIntradayChart(window: window, buckets: slots.map { slot in
            WatchIntradayBucket(
                start: window.start.addingTimeInterval(slot.minutes * 60),
                minimum: slot.average - 5,
                maximum: slot.average + 5,
                average: slot.average
            )
        })
    }

    // MARK: - Schema evolution

    func testSnapshotWithoutTheHeartChartsKeyStillDecodes() throws {
        // What an older watch cached, and what every phone publishes.
        let json = """
        {
          "generatedAt": "2026-06-04T07:00:00Z",
          "metrics": []
        }
        """

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: Data(json.utf8)))

        XCTAssertNil(decoded.heartCharts)
    }

    /// The phone never sets the field, so its push carries no key and stays
    /// the size it was.
    func testANilFieldWritesNoKey() throws {
        let snapshot = WatchMetricsSnapshot(generatedAt: moment(9), lastRefreshDate: moment(9), metrics: [])
        let data = try XCTUnwrap(snapshot.encoded())

        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("heartCharts"))
    }

    func testEncodeDecodeRoundTripsTheHeartCharts() throws {
        var original = WatchMetricsSnapshot(generatedAt: moment(9), lastRefreshDate: moment(9), metrics: [])
        original.heartCharts = [
            WatchMetricKindKey.heartRate: chart(slots: [(0, 64), (30, 61), (480, 62)]),
            WatchMetricKindKey.heartRateVariability: chart(slots: [(60, 51)])
        ]
        let data = try XCTUnwrap(original.encoded())

        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: data))

        XCTAssertEqual(decoded.heartCharts, original.heartCharts)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Gallery preview

    func testPlaceholderChartsEndOnTheSampleCardsReadings() throws {
        let placeholder = WatchMetricsSnapshot.placeholder
        for kind in [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability] {
            let chart = try XCTUnwrap(placeholder.heartCharts?[kind], kind)
            let latest = try XCTUnwrap(chart.buckets.max { $0.start < $1.start }, kind)
            XCTAssertEqual(latest.average, placeholder.metric(forKind: kind)?.rawValue, "\(kind) ends on its card's reading")
        }
        XCTAssertEqual(placeholder.heartCharts?.count, 2, "Heart Rate and HRV only")
    }

    func testPlaceholderSlotsSitOnTheirWindowsGridOnWholeSeconds() throws {
        let charts = try XCTUnwrap(WatchMetricsSnapshot.placeholder.heartCharts)
        for (kind, chart) in charts {
            XCTAssertEqual(chart.window.plotEnd.timeIntervalSince(chart.window.start), WatchIntradayWindow.length + WatchIntradayWindow.slotLength, kind)
            for date in [chart.window.start, chart.window.end, chart.window.plotEnd] {
                XCTAssertEqual(date.timeIntervalSinceReferenceDate.rounded(), date.timeIntervalSinceReferenceDate, kind)
            }
            for bucket in chart.buckets {
                let offset = bucket.start.timeIntervalSince(chart.window.start)
                XCTAssertGreaterThanOrEqual(offset, 0, kind)
                XCTAssertLessThan(bucket.start, chart.window.plotEnd, kind)
                XCTAssertEqual(offset.truncatingRemainder(dividingBy: WatchIntradayWindow.slotLength), 0, kind)
                XCTAssertLessThanOrEqual(bucket.minimum, bucket.average, kind)
                XCTAssertLessThanOrEqual(bucket.average, bucket.maximum, kind)
            }
        }
    }

    /// The Stress chart needs 12 hours of windows; the Stress ring and bands
    /// complications still read the same Relaxed 42 on the same instants, so
    /// their gallery and renders don't change.
    func testPlaceholderStressFillsTheChartAndStillEndsOnRelaxed42() throws {
        let timeline = try XCTUnwrap(WatchMetricsSnapshot.placeholder.stressTimeline)
        let a = WatchStressTimeline.activityMarker

        XCTAssertGreaterThanOrEqual(timeline.end.timeIntervalSince(timeline.start), WatchStressChartGeometry.windowLength)
        XCTAssertEqual(Array(timeline.slots.suffix(7)), [28, 31, 35, a, a, 40, 42])
        XCTAssertEqual(timeline.end, Date(timeIntervalSinceReferenceDate: 802_284_300))
        XCTAssertEqual(timeline.latestScoredWindow?.score, 42)
        // Its scores reach both ends of the 0 to 100 scale, so the chart
        // complication's gallery and render span the whole plot.
        let scores = timeline.slots.compactMap { $0 }.filter { $0 != a }
        XCTAssertEqual(scores.min(), 0)
        XCTAssertEqual(scores.max(), 100)
        XCTAssertEqual(timeline.latestBand?.label, String(localized: "Relaxed", table: "BodyWatchShared"))
        XCTAssertEqual(
            Set(timeline.context.map(\.kind)),
            [WatchStressContextBand.sleepKind, WatchStressContextBand.workoutKind]
        )
        for date in [timeline.start, timeline.end] + timeline.context.flatMap({ [$0.start, $0.end] }) {
            XCTAssertEqual(date.timeIntervalSinceReferenceDate.rounded(), date.timeIntervalSinceReferenceDate)
        }
    }
}
