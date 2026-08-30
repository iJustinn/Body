//
//  WorkoutRecordLedgerTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutRecordLedgerTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func workout(
        id: UUID = UUID(),
        type: BodyWorkoutType = .running,
        start: Date? = nil,
        duration: TimeInterval = 1800,
        distance: Double? = nil,
        elevation: Double? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            type: type,
            startDate: start ?? baseDate,
            duration: duration,
            distanceMeters: distance,
            elevationAscendedMeters: elevation
        )
    }

    /// A complete ledger holding `workouts`, so cohort and baseline gates are out of the way.
    private func completeLedger(_ workouts: [WorkoutSummary]) -> WorkoutRecordLedger {
        var ledger = WorkoutRecordLedger()
        for workout in workouts {
            ledger.upsert(workout)
        }
        ledger.baselineComplete = true
        return ledger
    }

    /// Three filler contributions so a fourth workout clears `minimumCohortSize`.
    private func filler(
        type: BodyWorkoutType = .running,
        duration: TimeInterval = 600,
        distance: Double? = 5_000,
        elevation: Double? = 10,
        idOffset: Int = 900
    ) -> [WorkoutSummary] {
        (1...3).map {
            workout(
                id: uuid(idOffset + $0),
                type: type,
                start: baseDate.addingTimeInterval(TimeInterval($0) * 86_400),
                duration: duration,
                distance: distance,
                elevation: elevation
            )
        }
    }

    // MARK: - 1. Better value wins

    func testLongestDurationWins() {
        let winner = workout(id: uuid(1), duration: 7200, distance: 5_000)
        let ledger = completeLedger(filler() + [winner])
        XCTAssertTrue(ledger.records(for: winner).contains(.duration))
    }

    func testFasterPaceWinsForDistancePaceType() {
        // Pace is seconds per meter, so the slower run loses to the fillers' 5 km / 10 min.
        let slow = workout(id: uuid(1), duration: 3600, distance: 5_000)
        XCTAssertFalse(completeLedger(filler() + [slow]).records(for: slow).contains(.rate))

        let fast = workout(id: uuid(2), duration: 300, distance: 5_000)
        XCTAssertTrue(completeLedger(filler() + [fast]).records(for: fast).contains(.rate))
    }

    func testHigherSpeedWinsForCyclingAndFasterSwimPaceWins() {
        let fastRide = workout(id: uuid(1), type: .cycling, duration: 600, distance: 40_000)
        let rides = filler(type: .cycling, duration: 600, distance: 5_000, elevation: 10)
        XCTAssertTrue(completeLedger(rides + [fastRide]).records(for: fastRide).contains(.rate))

        let fastSwim = workout(id: uuid(2), type: .swimming, duration: 300, distance: 2_000)
        let swims = filler(type: .swimming, duration: 600, distance: 1_000, elevation: nil)
        XCTAssertTrue(completeLedger(swims + [fastSwim]).records(for: fastSwim).contains(.rate))
    }

    func testSubFloorDistanceContributesNoRateValue() {
        // 399 m is under the 400 m running floor: no rate value, so no rate record even
        // though the pace would be the fastest in the cohort.
        let short = workout(id: uuid(1), duration: 60, distance: 399)
        let ledger = completeLedger(filler() + [short])
        XCTAssertFalse(ledger.records(for: short).contains(.rate))

        // The swim floor is lower (100 m), so the same distance does qualify there.
        let swim = workout(id: uuid(2), type: .swimming, duration: 60, distance: 399)
        let swims = filler(type: .swimming, duration: 600, distance: 1_000, elevation: nil)
        XCTAssertTrue(completeLedger(swims + [swim]).records(for: swim).contains(.rate))
    }

    // MARK: - 2. Tie-break

    func testEqualValuesGoToEarlierWorkoutThenLowerUUID() {
        let early = workout(id: uuid(50), start: baseDate, duration: 7200, distance: 5_000)
        let late = workout(id: uuid(10), start: baseDate.addingTimeInterval(86_400), duration: 7200, distance: 5_000)
        let ledger = completeLedger(filler() + [late, early])
        XCTAssertTrue(ledger.records(for: early).contains(.duration))
        XCTAssertFalse(ledger.records(for: late).contains(.duration))

        let lowID = workout(id: uuid(10), start: baseDate, duration: 7200, distance: 5_000)
        let highID = workout(id: uuid(50), start: baseDate, duration: 7200, distance: 5_000)
        let tied = completeLedger(filler() + [highID, lowID])
        XCTAssertTrue(tied.records(for: lowID).contains(.duration))
        XCTAssertFalse(tied.records(for: highID).contains(.duration))
    }

    func testWinnerIsIndependentOfInsertionOrder() {
        let workouts = filler() + [
            workout(id: uuid(10), start: baseDate, duration: 7200, distance: 5_000),
            workout(id: uuid(50), start: baseDate, duration: 7200, distance: 5_000)
        ]
        let forward = completeLedger(workouts)
        let reversed = completeLedger(workouts.reversed())
        for workout in workouts {
            XCTAssertEqual(forward.records(for: workout), reversed.records(for: workout))
        }
    }

    // MARK: - 3. Cohort rule

    func testFewerThanFourContributorsShowNoRecord() {
        let best = workout(id: uuid(1), duration: 7200, distance: 5_000)
        let three = completeLedger(Array(filler().prefix(2)) + [best])
        XCTAssertTrue(three.records(for: best).isEmpty)

        let four = completeLedger(filler() + [best])
        XCTAssertTrue(four.records(for: best).contains(.duration))
    }

    func testFirstEverWorkoutHoldsNoRecord() {
        let only = workout(id: uuid(1), duration: 7200, distance: 5_000)
        XCTAssertTrue(completeLedger([only]).records(for: only).isEmpty)
    }

    // MARK: - 4. Isolation and catalog

    func testRecordsAreIsolatedPerWorkoutType() {
        let longWalk = workout(id: uuid(1), type: .walking, duration: 7200, distance: 5_000)
        // A far longer run must not deny the walk its walking record.
        let longRun = workout(id: uuid(2), type: .running, duration: 20_000, distance: 5_000)
        let ledger = completeLedger(
            filler(type: .walking) + filler(type: .running, idOffset: 800) + [longWalk, longRun]
        )
        XCTAssertTrue(ledger.records(for: longWalk).contains(.duration))
        XCTAssertTrue(ledger.records(for: longRun).contains(.duration))
    }

    func testMetricCatalogPerType() {
        XCTAssertEqual(
            WorkoutRecordMetric.metrics(for: .running),
            [.duration, .distance, .rate, .elevation]
        )
        XCTAssertEqual(
            WorkoutRecordMetric.metrics(for: .cycling),
            [.duration, .distance, .rate, .elevation]
        )
        // Swimming has a pace but no vertical.
        XCTAssertEqual(WorkoutRecordMetric.metrics(for: .swimming), [.duration, .distance, .rate])
        // Snow sports promote distance and climb, but have no pace tile.
        for type in [BodyWorkoutType.snowSports, .crossCountrySkiing, .downhillSkiing, .snowboarding] {
            XCTAssertEqual(
                WorkoutRecordMetric.metrics(for: type),
                [.duration, .distance, .elevation],
                "\(type.rawValue)"
            )
        }
        // A type with no pace and no promoted distance tracks duration alone.
        XCTAssertEqual(WorkoutRecordMetric.metrics(for: .strengthTraining), [.duration])
        XCTAssertEqual(WorkoutRecordMetric.metrics(for: .yoga), [.duration])
    }

    func testDetailKindAndDirectionPerPaceStyle() {
        XCTAssertEqual(WorkoutRecordMetric.rate.detailKind(for: .running), .pace)
        XCTAssertEqual(WorkoutRecordMetric.rate.detailKind(for: .cycling), .speed)
        XCTAssertEqual(WorkoutRecordMetric.rate.detailKind(for: .swimming), .swimPace)
        XCTAssertNil(WorkoutRecordMetric.rate.detailKind(for: .yoga))
        XCTAssertNil(WorkoutRecordMetric.duration.detailKind(for: .running))
        XCTAssertTrue(WorkoutRecordMetric.rate.isLowerBetter(for: .running))
        XCTAssertTrue(WorkoutRecordMetric.rate.isLowerBetter(for: .swimming))
        XCTAssertFalse(WorkoutRecordMetric.rate.isLowerBetter(for: .cycling))
        XCTAssertFalse(WorkoutRecordMetric.duration.isLowerBetter(for: .running))
    }

    func testSnowSportsRecordDistanceAndElevation() {
        // Shorter than the fillers, so only the distance and ascent records land — snow
        // sports carry no rate metric at all.
        let best = workout(id: uuid(1), type: .downhillSkiing, duration: 300, distance: 30_000, elevation: 900)
        let ledger = completeLedger(
            filler(type: .downhillSkiing, duration: 600, distance: 5_000, elevation: 100) + [best]
        )
        XCTAssertEqual(ledger.records(for: best), [.distance, .elevation])
    }

    // MARK: - 5. Upsert idempotency and repair

    func testUpsertIsIdempotent() {
        let best = workout(id: uuid(1), duration: 7200, distance: 5_000)
        var ledger = completeLedger(filler() + [best])
        let before = ledger.records(for: best)
        ledger.upsert(best)
        ledger.upsert(best)
        XCTAssertEqual(ledger.contributions.count, 4)
        XCTAssertEqual(ledger.records(for: best), before)
    }

    func testReUpsertWithLateArrivingDistanceMovesTheRecord() {
        let leader = workout(id: uuid(1), duration: 600, distance: 9_000)
        // Distance has not resolved yet, so this workout contributes no distance value.
        let pending = workout(id: uuid(2), duration: 600, distance: nil)
        var ledger = completeLedger(filler() + [leader, pending])
        XCTAssertTrue(ledger.records(for: leader).contains(.distance))

        ledger.upsert(workout(id: uuid(2), duration: 600, distance: 30_000))
        XCTAssertFalse(ledger.records(for: leader).contains(.distance))
    }

    /// The batch `upsert(_:)` used by the baseline backfill chunk must produce the exact
    /// same index as folding the same workouts in one at a time.
    func testBatchUpsertMatchesSequentialUpsert() {
        let workouts = filler() + [
            workout(id: uuid(1), duration: 7200, distance: 5_000, elevation: 800),
            workout(id: uuid(2), duration: 5400, distance: 9_000, elevation: 200)
        ]

        var sequential = WorkoutRecordLedger()
        for workout in workouts {
            sequential.upsert(workout)
        }
        sequential.baselineComplete = true

        var batched = WorkoutRecordLedger()
        batched.upsert(workouts)
        batched.baselineComplete = true

        XCTAssertEqual(batched.contributions, sequential.contributions)
        for workout in workouts {
            XCTAssertEqual(batched.records(for: workout), sequential.records(for: workout))
            XCTAssertEqual(batched.recordStandings(for: workout), sequential.recordStandings(for: workout))
        }
    }

    // MARK: - 6. Removal

    func testRemoveTransfersRecordToRunnerUpAndDropsCohortBelowThreshold() {
        let champion = workout(id: uuid(1), duration: 7200, distance: 5_000)
        let runnerUp = workout(id: uuid(2), duration: 5400, distance: 5_000)
        var ledger = completeLedger(filler() + [champion, runnerUp])
        XCTAssertTrue(ledger.records(for: champion).contains(.duration))

        ledger.remove(ids: [champion.id])
        XCTAssertTrue(ledger.records(for: runnerUp).contains(.duration))

        // Four contributors minus two leaves three: below the cohort floor, nothing shows.
        ledger.remove(ids: [uuid(901)])
        XCTAssertTrue(ledger.records(for: runnerUp).isEmpty)
    }

    // MARK: - 7. Baseline gate

    func testNoRecordsUntilBaselineComplete() {
        var ledger = WorkoutRecordLedger()
        let best = workout(id: uuid(1), duration: 7200, distance: 5_000)
        for workout in filler() + [best] {
            ledger.upsert(workout)
        }
        XCTAssertTrue(ledger.records(for: best).isEmpty)
        ledger.baselineComplete = true
        XCTAssertFalse(ledger.records(for: best).isEmpty)
    }

    // MARK: - 8. Codable

    func testRoundTripPreservesRecordsAndState() throws {
        let best = workout(id: uuid(1), duration: 7200, distance: 5_000, elevation: 800)
        var original = completeLedger(filler() + [best])
        original.scannedThrough = baseDate

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutRecordLedger.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, WorkoutRecordLedger.currentSchemaVersion)
        XCTAssertEqual(decoded.scannedThrough, baseDate)
        XCTAssertTrue(decoded.baselineComplete)
        XCTAssertEqual(decoded.contributions, original.contributions)
        // The derived index survives decoding, so a hydrated ledger answers reads.
        XCTAssertEqual(decoded.records(for: best), original.records(for: best))
    }

    func testEncodingIsByteStableAcrossEncodes() throws {
        let ledger = completeLedger(filler() + [workout(id: uuid(1), duration: 7200, distance: 5_000)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(ledger)
        let second = try encoder.encode(ledger)
        XCTAssertEqual(first, second)
    }

    // MARK: - 9. Standings (current vs former)

    /// A workout after the three fillers, so it sits at position 3 and clears
    /// `minimumFormerPredecessors` the moment it takes a record.
    private func contender(_ n: Int, days: Int, duration: TimeInterval) -> WorkoutSummary {
        workout(
            id: uuid(n),
            start: baseDate.addingTimeInterval(TimeInterval(days) * 86_400),
            duration: duration,
            distance: 5_000
        )
    }

    func testBeatenRecordHolderBecomesFormerAndTheNewOneCurrent() {
        let old = contender(1, days: 10, duration: 7200)
        let new = contender(2, days: 20, duration: 9000)
        let ledger = completeLedger(filler() + [old, new])

        XCTAssertEqual(ledger.recordStandings(for: old)[.duration], .former)
        XCTAssertEqual(ledger.recordStandings(for: new)[.duration], .current)
        // `records(for:)` stays current-only, so the share cards can't boast a lost PR.
        XCTAssertFalse(ledger.records(for: old).contains(.duration))
        XCTAssertTrue(ledger.records(for: new).contains(.duration))
    }

    func testFirstEverWorkoutIsNeverFormer() {
        // The fillers all start after `baseDate`, so this one leads the chronology and
        // has no predecessors to have beaten.
        let first = workout(id: uuid(1), duration: 7200, distance: 5_000)
        let later = contender(2, days: 20, duration: 9000)
        let ledger = completeLedger(filler() + [first, later])

        XCTAssertNil(ledger.recordStandings(for: first)[.duration])
        XCTAssertEqual(ledger.recordStandings(for: later)[.duration], .current)
    }

    func testWorkoutThatNeverLedGetsNoStanding() {
        let leader = contender(1, days: 10, duration: 9000)
        // Later, but slower than the record standing at its own moment.
        let alsoRan = contender(2, days: 20, duration: 3600)
        let ledger = completeLedger(filler() + [leader, alsoRan])

        XCTAssertTrue(ledger.recordStandings(for: alsoRan).isEmpty)
        XCTAssertEqual(ledger.recordStandings(for: leader)[.duration], .current)
    }

    func testEqualLaterWorkoutNeverHeldTheRecordSoIsNotFormer() {
        let earlier = contender(1, days: 10, duration: 7200)
        let equalLater = contender(2, days: 20, duration: 7200)
        let ledger = completeLedger(filler() + [earlier, equalLater])

        // The tie falls to the earlier workout, so the later one never led.
        XCTAssertEqual(ledger.recordStandings(for: earlier)[.duration], .current)
        XCTAssertNil(ledger.recordStandings(for: equalLater)[.duration])
    }

    func testRemovingTheCurrentHolderPromotesTheFormerHolderBackToCurrent() {
        let old = contender(1, days: 10, duration: 7200)
        let new = contender(2, days: 20, duration: 9000)
        var ledger = completeLedger(filler() + [old, new])
        XCTAssertEqual(ledger.recordStandings(for: old)[.duration], .former)

        ledger.remove(ids: [new.id])
        // Promoted, and not left in both buckets at once.
        XCTAssertEqual(ledger.recordStandings(for: old)[.duration], .current)
        XCTAssertTrue(ledger.records(for: old).contains(.duration))
    }

    func testStandingsAreEmptyUntilBaselineComplete() {
        var ledger = WorkoutRecordLedger()
        let old = contender(1, days: 10, duration: 7200)
        let new = contender(2, days: 20, duration: 9000)
        for workout in filler() + [old, new] {
            ledger.upsert(workout)
        }
        XCTAssertTrue(ledger.recordStandings(for: old).isEmpty)
        XCTAssertTrue(ledger.recordStandings(for: new).isEmpty)

        ledger.baselineComplete = true
        XCTAssertEqual(ledger.recordStandings(for: old)[.duration], .former)
        XCTAssertEqual(ledger.recordStandings(for: new)[.duration], .current)
    }

    /// Sparse early history earns no faded trophy: with fewer than
    /// `minimumFormerPredecessors` workouts before it, leading briefly was not a record.
    func testEarlyLeaderWithTooFewPredecessorsIsNotFormer() {
        let second = workout(
            id: uuid(1),
            start: baseDate.addingTimeInterval(86_400 * 2 - 1),
            duration: 3600,
            distance: 5_000
        )
        let latest = contender(2, days: 20, duration: 9000)
        // `filler()` runs at 600 s, so `second` led from day 2 until `latest` — but only
        // one workout preceded it.
        let ledger = completeLedger(filler() + [second, latest])

        XCTAssertNil(ledger.recordStandings(for: second)[.duration])
        XCTAssertEqual(ledger.recordStandings(for: latest)[.duration], .current)
    }
}
