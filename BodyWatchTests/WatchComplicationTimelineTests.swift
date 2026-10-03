//
//  WatchComplicationTimelineTests.swift
//  BodyWatchTests
//
//  Locks `WatchComplicationTimeline.entries`: a `now` entry plus a local
//  midnight entry (H-10), the midnight entry re-sanitized so a sleep night
//  that belongs to the earlier day clears, an entry when the Stress
//  complication's reading ages out, an entry at every local half hour across
//  an intraday chart complication's window, and the fallback reload date.
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

    private func stressSnapshot(now: Date, latestWindowStart: Date) -> WatchMetricsSnapshot {
        var snapshot = WatchMetricsSnapshot(generatedAt: now, lastRefreshDate: now, metrics: [])
        snapshot.stressTimeline = WatchStressTimeline(
            start: latestWindowStart.addingTimeInterval(-WatchStressTimeline.slotLength),
            end: latestWindowStart.addingTimeInterval(5 * 60),
            slots: [36, 42],
            context: [],
            computedAt: now
        )
        return snapshot
    }

    /// The Stress reading blanks 12 hours after its window ends, without a
    /// reload: one more entry at that instant, in date order with midnight.
    func testAnEntryWhenTheStressReadingAgesOut() {
        let now = date(2026, 6, 4, 9)
        let built = WatchComplicationTimeline.entries(
            snapshot: stressSnapshot(now: now, latestWindowStart: date(2026, 6, 4, 8, 30)),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(built.entries.map(\.date), [now, date(2026, 6, 4, 20, 45), date(2026, 6, 5, 0)])
        XCTAssertEqual(built.entries[0].snapshot.stressTimeline?.latestReading(asOf: built.entries[0].date)?.score, 42)
        XCTAssertNil(built.entries[1].snapshot.stressTimeline?.latestReading(asOf: built.entries[1].date))

        let evening = date(2026, 6, 4, 20)
        let afterMidnight = WatchComplicationTimeline.entries(
            snapshot: stressSnapshot(now: evening, latestWindowStart: date(2026, 6, 4, 19, 30)),
            now: evening,
            calendar: calendar
        )
        XCTAssertEqual(afterMidnight.entries.map(\.date), [evening, date(2026, 6, 5, 0), date(2026, 6, 5, 7, 45)])
    }

    func testNoStressEntryOnceTheReadingHasAgedOut() {
        let now = date(2026, 6, 4, 22)
        let built = WatchComplicationTimeline.entries(
            snapshot: stressSnapshot(now: now, latestWindowStart: date(2026, 6, 4, 8, 30)),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(built.entries.map(\.date), [now, date(2026, 6, 5, 0)])
    }

    // MARK: - Sliding window

    /// An intraday chart complication ends its chart at the entry's date, so
    /// its timeline steps through every local half hour across the chart's
    /// window, then midnight, with the reload unchanged.
    func testASlidingWindowAddsAnEntryAtEachHalfHourAhead() {
        let now = date(2026, 6, 4, 9, 10)
        let snapshot = WatchMetricsSnapshot(generatedAt: now, lastRefreshDate: now, metrics: [])

        let built = WatchComplicationTimeline.entries(
            snapshot: snapshot,
            now: now,
            slidingWindow: WatchIntradayWindow.length,
            calendar: calendar
        )

        // 09:30 through 17:00: 17:30 is past 09:10 plus 8 hours.
        let halfHours = (0...15).map { date(2026, 6, 4, 9, 30).addingTimeInterval(Double($0) * WatchIntradayWindow.slotLength) }
        XCTAssertEqual(halfHours.last, date(2026, 6, 4, 17))
        XCTAssertEqual(built.entries.map(\.date), [now] + halfHours + [date(2026, 6, 5, 0)])
        XCTAssertEqual(built.reloadAfter, now.addingTimeInterval(WatchComplicationTimeline.refreshInterval))
    }

    /// A half hour that is also midnight gets one entry, and the Stress
    /// expiry still joins the list in date order.
    func testSlidingEntriesShareMidnightWithoutADuplicate() {
        let now = date(2026, 6, 4, 20, 10)
        let built = WatchComplicationTimeline.entries(
            snapshot: stressSnapshot(now: now, latestWindowStart: date(2026, 6, 4, 13, 50)),
            now: now,
            slidingWindow: WatchIntradayWindow.length,
            calendar: calendar
        )
        let dates = built.entries.map(\.date)

        // 20:30 through 04:00, midnight among them, plus the reading's expiry
        // at 02:05, 12 hours after its window ends.
        let halfHours = (0...15).map { date(2026, 6, 4, 20, 30).addingTimeInterval(Double($0) * WatchIntradayWindow.slotLength) }
        XCTAssertEqual(halfHours.last, date(2026, 6, 5, 4))
        XCTAssertEqual(dates, ([now] + halfHours + [date(2026, 6, 5, 2, 5)]).sorted())
        XCTAssertEqual(dates.filter { $0 == date(2026, 6, 5, 0) }.count, 1)
        XCTAssertTrue(zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 }, "Strictly increasing, no duplicate dates")
    }

    /// The other complications pass no window, so their entries are the ones
    /// they always had.
    func testWithoutASlidingWindowTheEntriesAreUnchanged() {
        let now = date(2026, 6, 4, 9)
        let snapshot = stressSnapshot(now: now, latestWindowStart: date(2026, 6, 4, 8, 30))

        let defaulted = WatchComplicationTimeline.entries(snapshot: snapshot, now: now, calendar: calendar)
        let explicit = WatchComplicationTimeline.entries(snapshot: snapshot, now: now, slidingWindow: nil, calendar: calendar)

        XCTAssertEqual(defaulted.entries.map(\.date), [now, date(2026, 6, 4, 20, 45), date(2026, 6, 5, 0)])
        XCTAssertEqual(explicit.entries.map(\.date), defaulted.entries.map(\.date))
        XCTAssertEqual(explicit.entries.map(\.snapshot), defaulted.entries.map(\.snapshot))
        XCTAssertEqual(explicit.reloadAfter, defaulted.reloadAfter)
    }
}
