//
//  WorkoutSummaryDecodeTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// L-24: `heartRateSamples` is non-optional, so every caller reads an array instead of
/// unwrapping. Month snapshots persisted before the key existed must still decode, with
/// the missing key landing as an empty array rather than throwing.
final class WorkoutSummaryDecodeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(
        heartRateSamples: [WorkoutHeartRateSample] = [],
        averagePowerWatts: Double? = nil,
        cardioFitnessVO2Max: Double? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: .running,
            startDate: start,
            duration: 1_800,
            activeEnergyKilocalories: 320,
            distanceMeters: 5_000,
            averageHeartRateBeatsPerMinute: 148,
            heartRateSamples: heartRateSamples,
            averagePowerWatts: averagePowerWatts,
            cardioFitnessVO2Max: cardioFitnessVO2Max,
            sourceName: "Apple Watch"
        )
    }

    /// Encodes `summary`, strips the named key from the JSON object, and decodes again.
    private func decodingWithoutKey(
        _ key: String,
        from summary: WorkoutSummary
    ) throws -> WorkoutSummary {
        let data = try JSONEncoder().encode(summary)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(object[key], "expected the encoder to write \(key)")
        object.removeValue(forKey: key)
        let stripped = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(WorkoutSummary.self, from: stripped)
    }

    func testLegacySummaryWithoutHeartRateSamplesKeyDecodesAsEmpty() throws {
        let decoded = try decodingWithoutKey(
            "heartRateSamples",
            from: summary(heartRateSamples: [
                WorkoutHeartRateSample(date: start, beatsPerMinute: 140)
            ])
        )
        XCTAssertTrue(decoded.heartRateSamples.isEmpty)
    }

    func testLegacySummaryWithoutWorkoutMetricsEqualsItsOwnStrippedCopy() throws {
        // A legacy month carries none of the Workout Metrics fields, so re-applying the
        // permission strip must be a no-op — the byte-dedupe only re-saves such a month
        // once, for the newly added heart-rate key.
        let decoded = try decodingWithoutKey("heartRateSamples", from: summary())
        XCTAssertEqual(decoded, decoded.removingWorkoutMetrics())
    }

    func testHeartRateSamplesSurviveACodableRoundTrip() throws {
        let samples = [
            WorkoutHeartRateSample(date: start, beatsPerMinute: 132),
            WorkoutHeartRateSample(date: start.addingTimeInterval(60), beatsPerMinute: 151)
        ]
        let original = summary(heartRateSamples: samples)
        let decoded = try JSONDecoder().decode(
            WorkoutSummary.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded.heartRateSamples, samples)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - M15: unknown workout types keep their raw string

    /// Replaces the encoded `type` string with a raw value this build does not know.
    private func encodingWithRawType(_ rawType: String, from summary: WorkoutSummary) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(summary)) as? [String: Any]
        )
        object["type"] = rawType
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testUnknownWorkoutTypeDecodesAsOther() throws {
        let data = try encodingWithRawType("underwaterBasketWeaving", from: summary())
        let decoded = try JSONDecoder().decode(WorkoutSummary.self, from: data)
        XCTAssertEqual(decoded.type, .other)
    }

    func testUnknownWorkoutTypeIsWrittenBackUnchanged() throws {
        let data = try encodingWithRawType("underwaterBasketWeaving", from: summary())
        let decoded = try JSONDecoder().decode(WorkoutSummary.self, from: data)

        let reencoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(decoded)) as? [String: Any]
        )
        XCTAssertEqual(reencoded["type"] as? String, "underwaterBasketWeaving")
    }

    func testKnownWorkoutTypeEncodesAsThePlainRawString() throws {
        // The stashed raw value must never reach the file for a known type, or the
        // save-if-changed byte compare would rewrite every cached month once.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try encoder.encode(summary()), encoding: .utf8))
        XCTAssertTrue(json.contains("\"type\":\"running\""), json)
    }

    func testUnknownWorkoutTypeSurvivesTwoRoundTrips() throws {
        let first = try JSONDecoder().decode(
            WorkoutSummary.self,
            from: try encodingWithRawType("underwaterBasketWeaving", from: summary())
        )
        let second = try JSONDecoder().decode(
            WorkoutSummary.self,
            from: try JSONEncoder().encode(first)
        )
        XCTAssertEqual(second, first)
        XCTAssertEqual(second.type, .other)
    }
}
