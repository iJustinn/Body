import XCTest
import SwiftUI
@testable import Body

final class DayRingTimelineTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func sleep(_ stage: SleepStage, _ start: Date, _ end: Date) -> SleepStageSegment {
        SleepStageSegment(stage: stage, startDate: start, endDate: end)
    }

    private func workout(
        _ type: BodyWorkoutType,
        _ start: Date,
        _ end: Date?,
        duration: TimeInterval? = nil,
        id: UUID = UUID()
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            type: type,
            startDate: start,
            duration: duration ?? end.map { $0.timeIntervalSince(start) } ?? 0,
            endDate: end
        )
    }

    private func make(
        now: Date,
        sleep: [SleepStageSegment] = [],
        workouts: [WorkoutSummary] = []
    ) -> DayRingTimeline {
        DayRingTimeline.make(now: now, calendar: calendar, sleepSegments: sleep, workouts: workouts)
    }

    // MARK: - Sleep

    func testSleepDrawsAsOneBarFromStartToEndClippedAtMidnight() {
        let segments = [
            sleep(.core, date(2026, 9, 19, 23), date(2026, 9, 20, 2)),
            // An aggregate sample over the same stretch must not double count.
            sleep(.deep, date(2026, 9, 20, 1), date(2026, 9, 20, 2)),
            sleep(.awake, date(2026, 9, 20, 2), date(2026, 9, 20, 3)),
            sleep(.rem, date(2026, 9, 20, 3), date(2026, 9, 20, 6)),
            // A nap is not part of the night's bar.
            sleep(.core, date(2026, 9, 20, 14), date(2026, 9, 20, 15))
        ]
        let main = DateInterval(start: date(2026, 9, 19, 23), end: date(2026, 9, 20, 6))
        let withMain = DayRingTimeline.make(
            now: date(2026, 9, 20, 12), calendar: calendar, sleepSegments: segments, mainSleepInterval: main, workouts: []
        )
        // A snapshot saved before it recorded its main session finds the same night.
        let withoutMain = make(now: date(2026, 9, 20, 12), sleep: segments)

        XCTAssertEqual(withMain.spans, withoutMain.spans)
        XCTAssertEqual(withMain.spans.map(\.activity), [.sleep])
        XCTAssertEqual(withMain.spans[0].start, 0)
        XCTAssertEqual(withMain.spans[0].end, 6.0 / 24, accuracy: 1e-9)
        // The spoken total is still asleep time only: awake break out, nap in.
        XCTAssertEqual(withMain.sleepDuration, 6 * 3600, accuracy: 1e-6)
    }

    func testDayPartsCoverTheClock() {
        XCTAssertEqual((0..<24).map { DayRingDayPart(hour: $0) }, [
            .night, .night, .night, .night, .night,
            .morning, .morning, .morning, .morning, .morning, .morning,
            .noon, .noon, .noon,
            .afternoon, .afternoon, .afternoon, .afternoon,
            .night, .night, .night, .night, .night, .night
        ])
    }

    // MARK: - DST

    func testTicksMarkerAndPercentShareOneElapsedTimeAxisOnDSTDays() throws {
        // Spring forward: 2026-03-08 has 23 hours and no 02:00.
        let spring = make(now: date(2026, 3, 8, 12))
        XCTAssertEqual(spring.hourTicks.count, 23)
        XCTAssertFalse(spring.hourTicks.contains { $0.hour == 2 })
        let springNoon = try XCTUnwrap(spring.hourTicks.first { $0.hour == 12 })
        XCTAssertEqual(springNoon.fraction, spring.nowFraction, accuracy: 1e-9)
        XCTAssertEqual(spring.nowFraction, 11.0 / 23, accuracy: 1e-9)
        XCTAssertEqual(spring.percentPassed, 47)

        // Fall back: 2026-11-01 has 25 hours and 01:00 twice.
        let fall = make(now: date(2026, 11, 1, 12))
        XCTAssertEqual(fall.hourTicks.count, 25)
        XCTAssertEqual(fall.hourTicks.filter { $0.hour == 1 }.count, 2)
        let fallNoon = try XCTUnwrap(fall.hourTicks.first { $0.hour == 12 })
        XCTAssertEqual(fallNoon.fraction, fall.nowFraction, accuracy: 1e-9)
        XCTAssertEqual(fall.nowFraction, 13.0 / 25, accuracy: 1e-9)
    }

    func testOrdinaryDayHasTwentyFourEvenTicksAndBoundedFractions() {
        let timeline = make(now: date(2026, 9, 20, 18, 30))
        XCTAssertEqual(timeline.hourTicks.map(\.hour), Array(0..<24))
        XCTAssertEqual(timeline.hourTicks[6].fraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(timeline.percentPassed, 77)
        XCTAssertEqual(timeline.fraction(of: date(2026, 9, 19, 5)), 0)
        XCTAssertEqual(timeline.fraction(of: date(2026, 9, 22, 5)), 1)
    }

    // MARK: - Workouts

    func testOvernightWorkoutAcrossAMonthBoundaryIsClippedIntoToday() {
        let timeline = make(
            now: date(2026, 10, 1, 9),
            workouts: [workout(.running, date(2026, 9, 30, 23, 50), date(2026, 10, 1, 0, 20))]
        )

        XCTAssertEqual(timeline.workoutCount, 1)
        XCTAssertEqual(timeline.spans.count, 1)
        XCTAssertEqual(timeline.spans[0].start, 0)
        XCTAssertEqual(timeline.spans[0].end, 20.0 / (24 * 60), accuracy: 1e-9)
    }

    func testDayBoundsAreHalfOpenAndDuplicatesCountOnce() {
        let id = UUID()
        let timeline = make(
            now: date(2026, 9, 20, 9),
            workouts: [
                // Ends exactly at today's midnight: yesterday's, not today's.
                workout(.walking, date(2026, 9, 19, 23), date(2026, 9, 20, 0)),
                // Starts exactly at tomorrow's midnight.
                workout(.walking, date(2026, 9, 21, 0), date(2026, 9, 21, 1)),
                workout(.cycling, date(2026, 9, 20, 7), date(2026, 9, 20, 8), id: id),
                workout(.cycling, date(2026, 9, 20, 7), date(2026, 9, 20, 8), id: id)
            ]
        )

        XCTAssertEqual(timeline.workoutCount, 1)
        XCTAssertEqual(timeline.spans.map(\.activity), [.workout(.cycling)])
    }

    func testWorkoutWithoutAnEndDateFallsBackToItsDuration() {
        let timeline = make(
            now: date(2026, 9, 20, 9),
            workouts: [workout(.running, date(2026, 9, 20, 6), nil, duration: 3600)]
        )
        XCTAssertEqual(timeline.spans[0].end, 7.0 / 24, accuracy: 1e-9)
    }

    // MARK: - Overlap

    func testOverlapsSplitByPrecedenceWhateverTheInputOrder() {
        let sleepSegments = [sleep(.core, date(2026, 9, 20, 0), date(2026, 9, 20, 7))]
        let workouts = [
            workout(.walking, date(2026, 9, 20, 6), date(2026, 9, 20, 8)),
            workout(.running, date(2026, 9, 20, 7, 30), date(2026, 9, 20, 9))
        ]
        let forward = make(now: date(2026, 9, 20, 12), sleep: sleepSegments, workouts: workouts)
        let reversed = make(now: date(2026, 9, 20, 12), sleep: sleepSegments.reversed(), workouts: workouts.reversed())

        XCTAssertEqual(forward, reversed)
        // A workout beats sleep, and the later start beats the earlier one.
        XCTAssertEqual(forward.spans.map(\.activity), [.sleep, .workout(.walking), .workout(.running)])
        XCTAssertEqual(forward.spans[0].end, 6.0 / 24, accuracy: 1e-9)
        XCTAssertEqual(forward.spans[1].end, 7.5 / 24, accuracy: 1e-9)
        XCTAssertEqual(forward.spans[2].end, 9.0 / 24, accuracy: 1e-9)
        // Totals come from the data, not from what is left visible.
        XCTAssertEqual(forward.sleepDuration, 7 * 3600, accuracy: 1e-6)
        XCTAssertEqual(forward.workoutCount, 2)
    }

    func testIdenticalWorkoutIntervalsResolveTheSameWayInEitherOrder() {
        let first = workout(.walking, date(2026, 9, 20, 6), date(2026, 9, 20, 7), id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = workout(.running, date(2026, 9, 20, 6), date(2026, 9, 20, 7), id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

        let forward = make(now: date(2026, 9, 20, 12), workouts: [first, second])
        let reversed = make(now: date(2026, 9, 20, 12), workouts: [second, first])

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.spans.map(\.activity), [.workout(.running)])
        XCTAssertEqual(forward.workoutCount, 2)
    }

    // MARK: - Drawing

    func testShortEventsDrawAsABoundedGlyphAndNeighboursKeepAHairline() {
        let trackLength = BodyDayRingGeometry.track(width: 361).layout.trackLength
        let minimum = Double(BodyDayRingGeometry.minimumSegmentLength / trackLength)
        func range(_ span: DayRingTimeline.Span, _ previous: DayRingTimeline.Span? = nil, _ next: DayRingTimeline.Span? = nil) -> ClosedRange<Double> {
            BodyDayRingGeometry.drawnRange(for: span, previous: previous, next: next, trackLength: trackLength)
        }

        // Five minutes draws as the minimum bar, which is long enough to hold its icon.
        let short = DayRingTimeline.Span(start: 0.5, end: 0.5 + 5.0 / 1440, activity: .workout(.running))
        XCTAssertEqual(range(short).upperBound - range(short).lowerBound, minimum, accuracy: 1e-9)
        XCTAssertGreaterThan(
            BodyDayRingGeometry.minimumSegmentLength,
            BodyDayRingGeometry.outerBarWidth * BodyDayRingGeometry.iconMinimumLengthRatio
        )

        // Two events ten minutes apart never meet.
        let later = DayRingTimeline.Span(start: short.end + 10.0 / 1440, end: short.end + 15.0 / 1440, activity: .workout(.walking))
        XCTAssertLessThan(range(short, nil, later).upperBound, range(later, short).lowerBound)

        // Even two minutes apart the glyphs stop at the halfway point instead of merging.
        let close = DayRingTimeline.Span(start: short.end + 2.0 / 1440, end: short.end + 4.0 / 1440, activity: .workout(.walking))
        XCTAssertLessThan(range(short, nil, close).upperBound, range(close, short).lowerBound)

        // Glyphs at either midnight stay on the dial.
        let first = DayRingTimeline.Span(start: 0, end: 1.0 / 1440, activity: .sleep)
        let last = DayRingTimeline.Span(start: 1 - 1.0 / 1440, end: 1, activity: .sleep)
        XCTAssertEqual(range(first).lowerBound, 0, accuracy: 1e-9)
        XCTAssertEqual(range(last).upperBound, 1, accuracy: 1e-9)

        // Touching spans are split by a hairline; a long span keeps its true extent otherwise.
        let sleepSpan = DayRingTimeline.Span(start: 0.1, end: 0.3, activity: .sleep)
        let run = DayRingTimeline.Span(start: 0.3, end: 0.4, activity: .workout(.running))
        XCTAssertEqual(range(sleepSpan, nil, run).lowerBound, 0.1)
        XCTAssertEqual(range(run, sleepSpan).upperBound, 0.4)
        XCTAssertLessThan(range(sleepSpan, nil, run).upperBound, range(run, sleepSpan).lowerBound)
    }

    func testTheBarsKeepTheReadinessRingsFootprintAndRoundedTipsStayInsideTrueTimes() {
        // One merged bar, about 1.1 times the Readiness Ring's, on the track's centerline.
        XCTAssertEqual(BodyDayRingGeometry.outerBarWidth, BodyDayRingGeometry.innerBarWidth)
        XCTAssertEqual(BodyDayRingGeometry.outerBarWidth, BodyReadinessArcGeometry.arcBarWidth * 1.1, accuracy: 1e-9)
        XCTAssertEqual(BodyDayRingGeometry.outerLaneOffset, BodyDayRingGeometry.innerLaneOffset)

        for width: CGFloat in [288, 361, 398] {
            // A span ending at 0.5 ends at the top of the ring: filled just left of
            // center, empty just right of it, rounded tip included.
            let track = BodyDayRingGeometry.track(width: width)
            let segment = track.segmentPath(range: 0.25...0.5)
            let top = track.point(fraction: 0.5, offset: BodyDayRingGeometry.outerLaneOffset)
            let inside = CGPoint(x: top.x - 14, y: top.y)
            let outside = CGPoint(x: top.x + 1, y: top.y)
            XCTAssertTrue(segment.contains(inside))
            XCTAssertFalse(segment.contains(outside))
        }
    }

    func testTheRingFlattensIntoTheReadinessRingsPinnedBar() {
        let width: CGFloat = 361
        let flat = BodyDayRingGeometry.track(progress: 1, width: width)
        // Flat: every point of a lane shares one height, the outer lane above the inner.
        let outerYs = [0.0, 0.3, 0.7, 1.0].map { flat.point(fraction: $0, offset: BodyDayRingGeometry.outerLaneOffset).y }
        XCTAssertEqual(outerYs.max()! - outerYs.min()!, 0, accuracy: 0.01)
        XCTAssertEqual(flat.scale, BodyReadinessArcGeometry.flatBarWidth / BodyReadinessArcGeometry.arcBarWidth, accuracy: 1e-9)
        // The pin holds the cards off the lower bar's bottom edge, and the flat pair with
        // its round caps stays inside the hero's width.
        let innerY = flat.point(fraction: 0, offset: BodyDayRingGeometry.innerLaneOffset).y
        XCTAssertEqual(BodyDayRingGeometry.flatBarBottom, innerY + BodyDayRingGeometry.innerBarWidth * flat.scale / 2, accuracy: 1e-6)
        XCTAssertGreaterThan(BodyDayRingGeometry.flatBarBottom, BodyReadinessArcGeometry.flatY + BodyReadinessArcGeometry.flatBarWidth / 2)
        XCTAssertGreaterThanOrEqual(flat.point(fraction: 0, offset: 0).x - BodyDayRingGeometry.outerBarWidth * flat.scale / 2, 0)
        XCTAssertLessThanOrEqual(flat.point(fraction: 1, offset: 0).x + BodyDayRingGeometry.outerBarWidth * flat.scale / 2, width)
        // The canvas reaches below the hero far enough for the dial's overrun and round
        // tip even pulled fully open, when the ends ride furthest down the sides.
        for width: CGFloat in [288, 361, 408, 440] {
            let arc = BodyDayRingGeometry.track(width: width, stretch: BodyReadinessArcGeometry.maxPullStretch)
            let end = arc.point(fraction: 1 + BodyDayRingGeometry.dialOverrun, offset: 0)
            XCTAssertLessThan(
                end.y + BodyDayRingGeometry.outerBarWidth / 2 + 1,
                BodyReadinessArcGeometry.heroHeight(width: width) + BodyDayRingGeometry.canvasOverhang
            )
        }
        // Flat, the day moves in from the track's ends so both midnight ticks sit inside
        // the bar's round tips rather than on its very edge.
        XCTAssertEqual(flat.axisInset, BodyDayRingGeometry.dialOverrun, accuracy: 1e-12)
        XCTAssertGreaterThan(flat.point(fraction: 0, offset: 0).x, flat.layout.point(atDistance: 0).x + 4)
        XCTAssertLessThan(flat.point(fraction: 1, offset: 0).x, flat.layout.point(atDistance: flat.layout.trackLength).x - 4)
        XCTAssertEqual(BodyDayRingGeometry.track(width: width).axisInset, 0)
        // Midnight to midnight still runs left to right.
        XCTAssertLessThan(flat.point(fraction: 0, offset: 0).x, flat.point(fraction: 1, offset: 0).x)
    }

    func testThePullStretchOpensTheTrackAndTheSqueezeFattensTheBars() {
        XCTAssertGreaterThan(
            BodyDayRingGeometry.track(width: 361, stretch: 1).layout.trackLength,
            BodyDayRingGeometry.track(width: 361).layout.trackLength
        )
        XCTAssertLessThan(BodyDayRingGeometry.barScale(stretch: 1), 1)
        XCTAssertGreaterThan(BodyDayRingGeometry.barScale(stretch: -0.6), 1)
        XCTAssertGreaterThan(BodyDayRingGeometry.lengthScale(stretch: 1), 1)
        XCTAssertLessThan(BodyDayRingGeometry.lengthScale(stretch: -0.6), 1)
        XCTAssertEqual(BodyDayRingGeometry.clampedStretch(-5), -BodyReadinessArcGeometry.maxSqueeze)
    }

    @MainActor
    func testTheHeroRendersAtPhoneWidths() {
        for width: CGFloat in [288, 361] {
            let hero = BodyDayRingHero(
                sleepSegments: [sleep(.core, date(2026, 9, 20, 0), date(2026, 9, 20, 7))],
                workouts: [workout(.running, date(2026, 9, 20, 18), date(2026, 9, 20, 18, 5))],
                width: width,
                previewDate: date(2026, 9, 20, 18, 30)
            )
            let renderer = ImageRenderer(content: hero)
            renderer.scale = 2
            let image = renderer.uiImage
            XCTAssertEqual(image?.size.width ?? 0, width, accuracy: 1)
            XCTAssertEqual(image?.size.height ?? 0, BodyReadinessArcGeometry.heroHeight(width: width), accuracy: 1)
        }
    }
}
