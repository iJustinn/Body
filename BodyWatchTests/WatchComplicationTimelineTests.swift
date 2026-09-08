//
//  WatchComplicationTimelineTests.swift
//  BodyWatchTests
//
//  Locks `WatchComplicationTimeline.entries`: a `now` entry plus a local
//  midnight entry (H-10), the midnight entry re-sanitized so a sleep night
//  that belongs to the earlier day clears, and the fallback reload date.
//

import XCTest
@testable import BodyWatch

final class WatchComplicationTimelineTests: XCTestCase {
    // Fixed identifier, but pinned to the system's own time zone: `sanitized`
    // (which the midnight entry re-runs) checks the sleep night against
    // `Calendar(identifier: .gregorian)` in the LOCAL default time zone, so the
    // calendar used here must match that, not an arbitrary named zone.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTwoEntriesNowAndNextMidnight() {
        let now = date(2026, 6, 4, 20)
        let midnight = date(2026, 6, 5, 0)
        let snapshot = WatchMetricsSnapshot(generatedAt: now, lastRefreshDate: now, metrics: [])

        let built = WatchComplicationTimeline.entries(snapshot: snapshot, now: now, calendar: calendar)

        XCTAssertEqual(built.entries.count, 2)
        XCTAssertEqual(built.entries[0].date, now)
        XCTAssertEqual(built.entries[1].date, midnight)
        XCTAssertEqual(built.reloadAfter, now.addingTimeInterval(WatchComplicationTimeline.refreshInterval))
    }

    func testMidnightEntryClearsAPriorDaysSleepWhileNowKeepsIt() {
        let now = date(2026, 6, 4, 20)
        let sleepNight = date(2026, 6, 4, 7) // tonight's session, on today
        let sleep = WatchMetric(
            kind: WatchMetricKindKey.sleep,
            title: "Sleep",
            displayValue: "7h 32m",
            unit: "",
            score: 85,
            fillFraction: 0.85,
            rawValue: 85
        )
        let snapshot = WatchMetricsSnapshot(
            generatedAt: now,
            lastRefreshDate: now,
            metrics: [sleep],
            sleepNight: sleepNight
        )

        let built = WatchComplicationTimeline.entries(snapshot: snapshot, now: now, calendar: calendar)

        let nowMetric = built.entries[0].snapshot.metric(forKind: WatchMetricKindKey.sleep)
        let midnightMetric = built.entries[1].snapshot.metric(forKind: WatchMetricKindKey.sleep)
        XCTAssertEqual(nowMetric?.displayValue, "7h 32m", "The now entry keeps today's sleep.")
        XCTAssertEqual(midnightMetric?.displayValue, "--", "The night belongs to the day that just ended, so the midnight entry clears it.")
    }
}
