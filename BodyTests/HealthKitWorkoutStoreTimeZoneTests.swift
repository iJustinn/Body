//
//  HealthKitWorkoutStoreTimeZoneTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

final class HealthKitWorkoutStoreTimeZoneTests: XCTestCase {

    func testMergedSleepDurationDoesNotDoubleCountOverlaps() throws {
        let calendar = Calendar.bodyGregorian
        let firstStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 1)))
        let firstEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 5)))
        let secondStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 3)))
        let secondEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 7)))
        let thirdStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 8)))
        let thirdEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 9, minute: 30)))

        let duration = HealthKitWorkoutStore.mergedSleepDuration(
            intervals: [
                (start: secondStart, end: secondEnd),
                (start: firstStart, end: firstEnd),
                (start: thirdStart, end: thirdEnd)
            ]
        )

        XCTAssertEqual(duration, 27_000)
    }

    func testSleepDurationTextDoesNotRoundDownPartialMinutes() {
        let sevenHoursTwentyMinutesOneSecond: TimeInterval = (7 * 3_600) + (20 * 60) + 1

        XCTAssertEqual(
            BodyValueFormat.sleepDurationText(for: sevenHoursTwentyMinutesOneSecond),
            "7h 21m"
        )
    }

    func testSleepDurationExcludesAwakeStageSamples() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5)))
        let awakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5)))
        let awakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5, minute: 15)))
        let remStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5, minute: 15)))
        let remEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7)))

        let duration = HealthKitWorkoutStore.sleepDuration(
            from: [
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: awakeStart, end: awakeEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: remStart, end: remEnd)
            ]
        )

        XCTAssertEqual(duration, 17_100)
    }

    func testSleepStageSegmentsShowSubMinuteAwakeSamplesByDefault() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4)))
        let subMinuteAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4, minute: 10)))
        let subMinuteAwakeEnd = subMinuteAwakeStart.addingTimeInterval(45)
        let minuteAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 5, minute: 20)))
        let minuteAwakeEnd = minuteAwakeStart.addingTimeInterval(60)

        let segments = HealthKitFetchEngine.sleepStageSegments(
            from: [
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: subMinuteAwakeStart, end: subMinuteAwakeEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: minuteAwakeStart, end: minuteAwakeEnd)
            ]
        )

        XCTAssertEqual(segments.map(\.stage), [SleepStage.core, .awake, .awake])
        XCTAssertEqual(segments[0].startDate, coreStart)
        XCTAssertEqual(segments[0].endDate, coreEnd)
        XCTAssertEqual(segments[1].startDate, subMinuteAwakeStart)
        XCTAssertEqual(segments[1].endDate, subMinuteAwakeEnd)
        XCTAssertEqual(segments[2].startDate, minuteAwakeStart)
        XCTAssertEqual(segments[2].endDate, minuteAwakeEnd)
    }

    func testSleepSummaryReadsTimeZoneFromMainSleepSession() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let mainStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let mainEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 7)))
        let napStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14)))
        let napEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14, minute: 30)))

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(
            from: [
                // A short nap from another source with a different zone must not win.
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: napStart,
                    end: napEnd,
                    metadata: [HKMetadataKeyTimeZone: "America/New_York"]
                ),
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: mainStart,
                    end: mainEnd,
                    metadata: [HKMetadataKeyTimeZone: "Europe/London"]
                )
            ],
            date: day
        ))

        XCTAssertEqual(summary.stageSnapshot.timeZoneIdentifier, "Europe/London")
    }

    func testSleepSummaryTimeZoneIgnoresNapSampleLongerThanEachMainStageSample() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let mainStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let napStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14)))
        let napEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 16)))

        // The main night is split into hour-long stage samples, each individually
        // shorter than the single two-hour nap sample from another zone; the
        // night's aggregated main session must still supply the zone.
        var samples = (0..<8).map { hour in
            HKCategorySample(
                type: sleepType,
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                start: mainStart.addingTimeInterval(TimeInterval(hour) * 3_600),
                end: mainStart.addingTimeInterval(TimeInterval(hour + 1) * 3_600),
                metadata: [HKMetadataKeyTimeZone: "Europe/London"]
            )
        }
        samples.append(HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: napStart,
            end: napEnd,
            metadata: [HKMetadataKeyTimeZone: "America/New_York"]
        ))

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(from: samples, date: day))

        XCTAssertEqual(summary.stageSnapshot.timeZoneIdentifier, "Europe/London")
    }

    func testSleepSummaryTimeZoneStaysNilWhenOnlyNapCarriesMetadata() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let mainStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let mainEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 7)))
        let napStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14)))
        let napEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 16)))

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(
            from: [
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: mainStart,
                    end: mainEnd
                ),
                // A zone known only for the nap must not label the main night.
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: napStart,
                    end: napEnd,
                    metadata: [HKMetadataKeyTimeZone: "America/New_York"]
                )
            ],
            date: day
        ))

        XCTAssertNil(summary.stageSnapshot.timeZoneIdentifier)
    }

    func testSleepSummaryLeavesTimeZoneNilWithoutMetadata() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 7)))

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(
            from: [
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: start,
                    end: end
                )
            ],
            date: day
        ))

        XCTAssertNil(summary.stageSnapshot.timeZoneIdentifier)
    }

    func testSleepSummaryFillsTimeZoneFromLedgerWhenMetadataMissing() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 7)))

        // Inject an ephemeral ledger recording that the device was in New York
        // before this night, then parse samples with no zone metadata (as Apple
        // Watch sleep does): the forwarder back-fills the ledger's zone for the
        // wake day so timezone-aware scoring can still place the night.
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let ledgerDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { ledgerDefaults.removePersistentDomain(forName: suiteName) }
        let ledger = BodyTimeZoneLedger(defaults: ledgerDefaults)
        ledger.recordCurrentZone(
            now: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))),
            zone: try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        )

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(
            from: [
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: start,
                    end: end
                )
            ],
            date: day,
            timeZoneLedger: ledger
        ))

        XCTAssertEqual(summary.stageSnapshot.timeZoneIdentifier, "America/New_York")
    }

    func testSleepStageSegmentsCanHideSubMinuteAwakeSamples() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4)))
        let subMinuteAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4, minute: 10)))
        let subMinuteAwakeEnd = subMinuteAwakeStart.addingTimeInterval(45)
        let minuteAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 5, minute: 20)))
        let minuteAwakeEnd = minuteAwakeStart.addingTimeInterval(60)

        let segments = HealthKitFetchEngine.sleepStageSegments(
            from: [
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: subMinuteAwakeStart, end: subMinuteAwakeEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: minuteAwakeStart, end: minuteAwakeEnd)
            ],
            showsSubMinuteAwakeStages: false
        )

        XCTAssertEqual(segments.map(\.stage), [SleepStage.core, .awake])
        XCTAssertEqual(segments[0].startDate, coreStart)
        XCTAssertEqual(segments[0].endDate, coreEnd)
        XCTAssertEqual(segments[1].startDate, minuteAwakeStart)
        XCTAssertEqual(segments[1].endDate, minuteAwakeEnd)
    }

    func testSleepStageSegmentsPreserveUnspecifiedSamplesThatAddCoverage() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 3)))
        let unspecifiedStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)))
        let unspecifiedEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5)))

        let segments = HealthKitFetchEngine.sleepStageSegments(
            from: [
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleep.rawValue, start: unspecifiedStart, end: unspecifiedEnd)
            ]
        )

        XCTAssertEqual(segments.map(\.stage), [SleepStage.core, .core])
        XCTAssertEqual(segments[0].startDate, coreStart)
        XCTAssertEqual(segments[0].endDate, coreEnd)
        XCTAssertEqual(segments[1].startDate, coreEnd)
        XCTAssertEqual(segments[1].endDate, unspecifiedEnd)
    }

    func testSleepStageSegmentsTrimLeadingAndTrailingAwakeWhenEnabled() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let leadingAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 0)))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 2)))
        let interiorAwakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 2, minute: 30)))
        let remEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4)))
        let trailingAwakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 5)))

        let samples = [
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: leadingAwakeStart, end: coreStart),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: coreEnd, end: interiorAwakeEnd),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: interiorAwakeEnd, end: remEnd),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: remEnd, end: trailingAwakeEnd)
        ]

        // Default keeps the leading/trailing awake blocks.
        let untrimmed = HealthKitFetchEngine.sleepStageSegments(from: samples)
        XCTAssertEqual(untrimmed.map(\.stage), [SleepStage.awake, .core, .awake, .rem, .awake])

        // Enabled: leading + trailing awake dropped, interior awake preserved.
        let trimmed = HealthKitFetchEngine.sleepStageSegments(from: samples, showsLeadingTrailingAwakeStages: false)
        XCTAssertEqual(trimmed.map(\.stage), [SleepStage.core, .awake, .rem])
        XCTAssertEqual(trimmed.first?.startDate, coreStart)
        XCTAssertEqual(trimmed.last?.endDate, remEnd)
    }

    func testSleepStageSegmentsTrimClampsOverlappingTrailingAwake() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 5)))
        // Awake starts before the sleep window ends but runs past it, so it is not
        // the last segment by start date — the naive drop-last-run would miss it.
        let awakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 4, minute: 30)))
        let awakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 6)))

        let samples = [
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: awakeStart, end: awakeEnd)
        ]

        let trimmed = HealthKitFetchEngine.sleepStageSegments(from: samples, showsLeadingTrailingAwakeStages: false)
        // The overlapping awake is clamped to the sleep window end, so the timeline
        // never extends past real sleep.
        XCTAssertEqual(trimmed.last?.stage, .awake)
        XCTAssertEqual(trimmed.last?.endDate, coreEnd)
        XCTAssertEqual(trimmed.map(\.endDate).max(), coreEnd)
    }

    func testSleepStageSegmentsTrimReturnsEmptyForAwakeOnlyNight() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let awakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 2)))
        let awakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 3)))
        let samples = [
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: awakeStart, end: awakeEnd)
        ]

        XCTAssertTrue(HealthKitFetchEngine.sleepStageSegments(from: samples, showsLeadingTrailingAwakeStages: false).isEmpty)
        // Default (shows leading/trailing awake) leaves the awake segment untouched.
        XCTAssertEqual(HealthKitFetchEngine.sleepStageSegments(from: samples).map(\.stage), [SleepStage.awake])
    }

    func testReadinessRecordSignatureChangesWithSleepStagePreferences() {
        func signature(showsSubMinuteAwake: Bool, showsLeadingTrailingAwake: Bool) -> String {
            HealthKitWorkoutStore.readinessRecordContextSignature(
                permissionSelection: .defaultValue,
                healthDataSourceSelection: .defaultValue,
                combinesHealthDataSourcesByName: false,
                idealSleepDuration: 8 * 60 * 60,
                showsSubMinuteAwakeStages: showsSubMinuteAwake,
                showsLeadingTrailingAwakeStages: showsLeadingTrailingAwake
            )
        }

        let base = signature(showsSubMinuteAwake: true, showsLeadingTrailingAwake: true)
        // Toggling either sleep-stage parser preference must change the signature so
        // frozen morning readiness records are invalidated and recomputed.
        XCTAssertNotEqual(base, signature(showsSubMinuteAwake: true, showsLeadingTrailingAwake: false))
        XCTAssertNotEqual(base, signature(showsSubMinuteAwake: false, showsLeadingTrailingAwake: true))
    }
}
