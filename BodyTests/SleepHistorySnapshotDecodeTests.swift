//
//  SleepHistorySnapshotDecodeTests.swift
//  BodyTests
//
//  `SleepHistorySnapshot.days` gained a custom `init(from:)` mirroring
//  `ActivityRingHistorySnapshot` so decoded (as well as constructed) history
//  is always date-sorted, since `days.first` in `summary(on:)` and the
//  baseline windowing elsewhere assume that order.
//

import XCTest
@testable import Body

final class SleepHistorySnapshotDecodeTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ day: Int, duration: TimeInterval = 6 * 3_600) -> SleepDaySummary {
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: 7))!
        return SleepDaySummary(
            date: date,
            summary: SleepSummary(
                duration: duration,
                stageSnapshot: SleepStageSnapshot(date: date, segments: [])
            )
        )
    }

    func testDecodingOutOfOrderJSONSortsDaysByDate() throws {
        // Encode the raw out-of-order array directly (not through
        // `init(days:)`, which already sorts) to prove the decoder itself
        // sorts on `init(from:)`.
        struct RawSnapshot: Encodable {
            let days: [SleepDaySummary]
        }
        let raw = RawSnapshot(days: [day(3), day(1), day(2)])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(raw)
        let decoded = try decoder.decode(SleepHistorySnapshot.self, from: data)

        XCTAssertEqual(decoded.days.map(\.date), [day(1), day(2), day(3)].map(\.date))
    }

    func testEncodeDecodeRoundTripPreservesEquality() throws {
        let snapshot = SleepHistorySnapshot(days: [day(1), day(2), day(3)])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(SleepHistorySnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }
}
