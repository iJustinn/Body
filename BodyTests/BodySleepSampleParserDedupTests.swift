//
//  BodySleepSampleParserDedupTests.swift
//  BodyTests
//
//  Locks the cross-source arbitration in `BodySleepSampleParser`. When two or
//  more writers (Apple Watch + a ring/bed sensor) describe the same night,
//  every writer's samples used to be mapped 1:1 into the stage timeline, so the
//  hypnogram painted overlapping timelines on top of each other and the header
//  and legend totals doubled. Arbitration keeps the best-ranked writer whole
//  and lets lower-ranked writers contribute only the time nobody described.
//
//  Unit tests can't fabricate distinct `HKSource`s (no public initializer;
//  unsaved samples all report the running process), so the ranking/trimming is
//  exercised through the pure `dedupedExplicitSegments` with synthetic source
//  ids, and the `HKCategorySample` -> id adapter is covered separately.
//

import HealthKit
import XCTest
@testable import Body

final class BodySleepSampleParserDedupTests: XCTestCase {
    // MARK: Helpers

    private let night = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Minutes after the start of the synthetic night.
    private func at(_ minutes: Double) -> Date {
        night.addingTimeInterval(minutes * 60)
    }

    private func segment(_ stage: SleepStage, _ start: Double, _ end: Double) -> SleepStageSegment {
        SleepStageSegment(stage: stage, startDate: at(start), endDate: at(end))
    }

    private func sourced(
        _ sourceID: String,
        _ stage: SleepStage,
        _ start: Double,
        _ end: Double
    ) -> (segment: SleepStageSegment, sourceID: String) {
        (segment: segment(stage, start, end), sourceID: sourceID)
    }

    private func sleepType() throws -> HKCategoryType {
        try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
    }

    private func sample(
        _ value: HKCategoryValueSleepAnalysis,
        _ start: Double,
        _ end: Double,
        type: HKCategoryType
    ) -> HKCategorySample {
        HKCategorySample(type: type, value: value.rawValue, start: at(start), end: at(end))
    }

    // MARK: 1 — Two-source full overlap (the reported bug)

    func testFullyOverlappingSecondSourceIsDroppedEntirely() {
        // Watch: detailed 8h night. Ring: its own full timeline of the same night,
        // 5 minutes narrower, so the watch outranks it on asleep coverage.
        let watchSegments = [
            segment(.core, 0, 90),
            segment(.deep, 90, 150),
            segment(.core, 150, 240),
            segment(.rem, 240, 300),
            segment(.core, 300, 420),
            segment(.rem, 420, 480)
        ]
        let sourcedSegments = [
            sourced("watch", .core, 0, 90),
            sourced("ring", .core, 5, 240),
            sourced("watch", .deep, 90, 150),
            sourced("ring", .rem, 240, 300),
            sourced("watch", .core, 150, 240),
            sourced("ring", .core, 300, 475),
            sourced("watch", .rem, 240, 300),
            sourced("watch", .core, 300, 420),
            sourced("watch", .rem, 420, 480)
        ]

        let deduped = BodySleepSampleParser.dedupedExplicitSegments(sourcedSegments)

        XCTAssertEqual(deduped, watchSegments)

        let snapshot = SleepStageSnapshot(date: night, segments: deduped)
        // Header and legend agree, and both equal the real 8h night instead of
        // the ~15h the two stacked timelines used to sum to.
        XCTAssertEqual(snapshot.mergedAsleepDuration, 8 * 3_600, accuracy: 1)
        XCTAssertEqual(snapshot.asleepDuration, snapshot.mergedAsleepDuration, accuracy: 1)
        XCTAssertEqual(snapshot.duration(for: .core), 300 * 60, accuracy: 1)
        XCTAssertEqual(snapshot.duration(for: .deep), 60 * 60, accuracy: 1)
        XCTAssertEqual(snapshot.duration(for: .rem), 120 * 60, accuracy: 1)
    }

    // MARK: 2 — Partial overlap keeps the secondary's uncovered head

    func testPartiallyOverlappingSecondarySurvivesWhereItAddsCoverage() {
        // The ring caught 45 minutes of sleep before the watch started tracking.
        let sourcedSegments = [
            sourced("watch", .core, 0, 200),
            sourced("watch", .rem, 200, 260),
            sourced("watch", .core, 260, 480),
            sourced("ring", .core, -45, 120)
        ]

        let deduped = BodySleepSampleParser.dedupedExplicitSegments(sourcedSegments)

        XCTAssertEqual(deduped, [
            segment(.core, 0, 200),
            segment(.rem, 200, 260),
            segment(.core, 260, 480),
            // Trimmed to exactly the uncovered lead-in, stage preserved.
            segment(.core, -45, 0)
        ])
    }

    // MARK: 3 — Disjoint secondary-only nap survives regardless of rank

    func testDisjointSecondaryNapSurvivesWhole() {
        // Nap source ranked last (core-only, tiny coverage) — survives whole.
        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments([
            sourced("watch", .rem, 0, 60),
            sourced("watch", .core, 60, 480),
            sourced("ring", .core, 700, 760)
        ]), [
            segment(.rem, 0, 60),
            segment(.core, 60, 480),
            segment(.core, 700, 760)
        ])

        // Nap source ranked first (it reports deep, the night source doesn't) —
        // the far longer night still survives whole.
        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments([
            sourced("watch", .core, 0, 480),
            sourced("ring", .deep, 700, 760)
        ]), [
            segment(.deep, 700, 760),
            segment(.core, 0, 480)
        ])
    }

    // MARK: 4 — Clock-skew slivers are dropped, real remnants kept

    func testSubMinuteTrimmedFragmentIsDroppedButLongerRemnantIsKept() {
        let watch = [
            sourced("watch", .rem, 0, 60),
            sourced("watch", .core, 60, 480)
        ]

        // Ring's block protrudes 30s past the watch's timeline: pure clock skew.
        let sliver = (
            segment: SleepStageSegment(
                stage: .core,
                startDate: at(470),
                endDate: at(480).addingTimeInterval(30)
            ),
            sourceID: "ring"
        )
        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments(watch + [sliver]), [
            segment(.rem, 0, 60),
            segment(.core, 60, 480)
        ])

        // Two minutes past the watch's timeline is real extra sleep, so it stays.
        let remnant = (
            segment: SleepStageSegment(
                stage: .core,
                startDate: at(470),
                endDate: at(482)
            ),
            sourceID: "ring"
        )
        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments(watch + [remnant]), [
            segment(.rem, 0, 60),
            segment(.core, 60, 480),
            segment(.core, 480, 482)
        ])
    }

    // MARK: 5 — Single source is the identity

    func testSingleSourceSegmentsPassThroughUnchanged() {
        // Includes an out-of-order entry, a self-overlap and a 10s awake blip:
        // same-writer semantics must be untouched by arbitration.
        let sourcedSegments = [
            sourced("watch", .core, 60, 240),
            sourced("watch", .rem, 0, 60),
            sourced("watch", .core, 200, 300),
            (
                segment: SleepStageSegment(
                    stage: .awake,
                    startDate: at(300),
                    endDate: at(300).addingTimeInterval(10)
                ),
                sourceID: "watch"
            )
        ]

        XCTAssertEqual(
            BodySleepSampleParser.dedupedExplicitSegments(sourcedSegments),
            sourcedSegments.map(\.segment)
        )
        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments([]), [])
    }

    // MARK: 6 — Third source trims against the union of the first two

    func testThirdSourceIsTrimmedAgainstUnionOfHigherRankedSources() {
        let sourcedSegments = [
            sourced("aaa", .rem, 0, 60),
            sourced("aaa", .core, 60, 240),
            sourced("bbb", .rem, 300, 360),
            sourced("bbb", .core, 360, 480),
            sourced("ccc", .core, 0, 600)
        ]

        // aaa and bbb are both detailed (aaa has more asleep coverage); ccc is
        // core-only so it ranks last and keeps only the two gaps.
        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments(sourcedSegments), [
            segment(.rem, 0, 60),
            segment(.core, 60, 240),
            segment(.rem, 300, 360),
            segment(.core, 360, 480),
            segment(.core, 240, 300),
            segment(.core, 480, 600)
        ])
    }

    // MARK: 7 — Equal coverage breaks the tie on source id

    func testEqualCoverageTieBreaksOnLexicographicallySmallerSourceID() {
        let expected = [segment(.core, 0, 240)]

        XCTAssertEqual(
            BodySleepSampleParser.dedupedExplicitSegments([
                sourced("aaa", .core, 0, 240),
                sourced("bbb", .core, 0, 240)
            ]),
            expected
        )
        // Input order must not decide the winner.
        XCTAssertEqual(
            BodySleepSampleParser.dedupedExplicitSegments([
                sourced("bbb", .core, 0, 240),
                sourced("aaa", .core, 0, 240)
            ]),
            expected
        )
    }

    // MARK: 8 — A detailed writer outranks a longer coarse one

    func testDetailedSourceOutranksLongerCoreOnlySource() {
        // aaa is core-only but covers 10h and sorts first alphabetically; bbb
        // reports REM, so the detail tier must put bbb on top anyway.
        let sourcedSegments = [
            sourced("aaa", .core, 0, 600),
            sourced("bbb", .rem, 100, 160),
            sourced("bbb", .core, 160, 400)
        ]

        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments(sourcedSegments), [
            segment(.rem, 100, 160),
            segment(.core, 160, 400),
            segment(.core, 0, 100),
            segment(.core, 400, 600)
        ])
    }

    // MARK: 9 — Ranking uses union coverage, not the raw sum

    func testDuplicatedSamplesDoNotInflateSourceRank() {
        // aaa writes the same 4h block twice (raw sum 8h) but really covers 4h;
        // bbb's honest 5h must outrank it even though "aaa" < "bbb".
        let sourcedSegments = [
            sourced("aaa", .core, 0, 240),
            sourced("aaa", .core, 0, 240),
            sourced("bbb", .core, 0, 300)
        ]

        XCTAssertEqual(
            BodySleepSampleParser.dedupedExplicitSegments(sourcedSegments),
            [segment(.core, 0, 300)]
        )
    }

    // MARK: 10 — Output doesn't depend on the order sources appear in

    func testOutputIsIndependentOfInputInterleaving() {
        let aaa = [
            sourced("aaa", .core, 0, 120),
            sourced("aaa", .awake, 120, 150),
            sourced("aaa", .core, 150, 300)
        ]
        let bbb = [
            sourced("bbb", .core, 0, 120),
            sourced("bbb", .awake, 120, 150),
            sourced("bbb", .core, 150, 300)
        ]
        let ccc = [sourced("ccc", .core, 500, 560)]

        let expected = [
            segment(.core, 0, 120),
            segment(.awake, 120, 150),
            segment(.core, 150, 300),
            segment(.core, 500, 560)
        ]

        // Every interleaving that preserves each writer's own sample order must
        // produce the same timeline — the chart bridges depend on array order.
        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments(aaa + bbb + ccc), expected)
        XCTAssertEqual(BodySleepSampleParser.dedupedExplicitSegments(ccc + bbb + aaa), expected)
        XCTAssertEqual(
            BodySleepSampleParser.dedupedExplicitSegments([
                bbb[0], aaa[0], ccc[0], bbb[1], aaa[1], bbb[2], aaa[2]
            ]),
            expected
        )
    }

    // MARK: 11 — Overlapping aggregate samples union instead of double-painting

    func testOverlappingUnspecifiedSamplesProduceNonOverlappingCoreSegments() throws {
        let type = try sleepType()
        let segments = BodySleepSampleParser.sleepStageSegments(from: [
            sample(.asleepUnspecified, 0, 300, type: type),
            sample(.asleepUnspecified, 240, 480, type: type)
        ])

        XCTAssertEqual(segments, [
            segment(.core, 0, 300),
            segment(.core, 300, 480)
        ])

        let snapshot = SleepStageSnapshot(date: night, segments: segments)
        // The core lane is the union of the two aggregates (8h), not their sum.
        XCTAssertEqual(snapshot.duration(for: .core), 480 * 60, accuracy: 1)
        XCTAssertEqual(snapshot.asleepDuration, snapshot.mergedAsleepDuration, accuracy: 1)
    }

    // MARK: 12 — Source identity adapter

    func testSleepSourceIdentityKeyFormatsBundleAndFoldedName() throws {
        let type = try sleepType()
        let first = sample(.asleepCore, 0, 60, type: type)
        let second = sample(.asleepREM, 60, 120, type: type)

        // Canaries `sourceRevision` access on unsaved samples: both report the
        // running process, so both must key identically.
        let source = first.sourceRevision.source
        let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedName = (trimmedName.isEmpty ? "Unknown Source" : trimmedName)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let key = BodySleepSampleParser.sleepSourceIdentityKey(for: first)
        XCTAssertEqual(key, "bundle=\(source.bundleIdentifier)|name=\(expectedName)")
        XCTAssertEqual(key, BodySleepSampleParser.sleepSourceIdentityKey(for: second))
        XCTAssertTrue(key.hasPrefix("bundle="))
        XCTAssertTrue(key.contains("|name="))
        // Same identity model as the source picker's per-device key.
        XCTAssertEqual(
            key,
            BodyHealthDataSourceOption.individualSourceIdentityKey(
                bundleIdentifier: source.bundleIdentifier,
                name: source.name
            )
        )
    }

    // MARK: 13 — Single-source night is unchanged end to end

    func testSingleSourceNightSummaryIsUnchanged() throws {
        let type = try sleepType()
        let samples = [
            sample(.awake, 0, 15, type: type),
            sample(.asleepCore, 15, 120, type: type),
            sample(.asleepDeep, 120, 180, type: type),
            sample(.asleepCore, 180, 300, type: type),
            sample(.asleepREM, 300, 360, type: type),
            sample(.asleepCore, 360, 450, type: type),
            sample(.awake, 450, 480, type: type)
        ]

        let summary = try XCTUnwrap(BodySleepSampleParser.sleepSummary(from: samples, date: night))

        // Trend duration is the asleep union (00:15 -> 07:30).
        XCTAssertEqual(try XCTUnwrap(summary.duration), 435 * 60, accuracy: 1)
        XCTAssertEqual(summary.stageSnapshot.segments, [
            segment(.awake, 0, 15),
            segment(.core, 15, 120),
            segment(.deep, 120, 180),
            segment(.core, 180, 300),
            segment(.rem, 300, 360),
            segment(.core, 360, 450),
            segment(.awake, 450, 480)
        ])
        XCTAssertEqual(summary.stageSnapshot.asleepDuration, 435 * 60, accuracy: 1)
        XCTAssertEqual(
            summary.stageSnapshot.mergedAsleepDuration,
            summary.stageSnapshot.asleepDuration,
            accuracy: 1
        )
    }
}
