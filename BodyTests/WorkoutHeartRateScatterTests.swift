//
//  WorkoutHeartRateScatterTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Covers `bodyWorkoutHeartRateScatterSamples`, the HR chart scatter layer's
/// downsampling helper (WP-E, `Body/Views/BodyWorkoutsView.swift`).
final class WorkoutHeartRateScatterTests: XCTestCase {
    private func samples(count: Int) -> [WorkoutHeartRateSample] {
        (0..<count).map { index in
            WorkoutHeartRateSample(
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                beatsPerMinute: Double(60 + index)
            )
        }
    }

    private func assertPreservesFirstAndLast(count: Int, maxCount: Int = 300, file: StaticString = #filePath, line: UInt = #line) {
        let input = samples(count: count)
        let result = bodyWorkoutHeartRateScatterSamples(input, maxCount: maxCount)

        XCTAssertLessThanOrEqual(result.count, maxCount, file: file, line: line)
        if let first = input.first, let last = input.last {
            XCTAssertEqual(result.first, first, file: file, line: line)
            XCTAssertEqual(result.last, last, file: file, line: line)
        }
    }

    func testSingleSample() {
        assertPreservesFirstAndLast(count: 1)
    }

    func testTwoSamples() {
        assertPreservesFirstAndLast(count: 2)
    }

    func testExactlyMaxCount() {
        let input = samples(count: 300)
        let result = bodyWorkoutHeartRateScatterSamples(input, maxCount: 300)
        XCTAssertEqual(result, input)
    }

    func testJustOverMaxCount() {
        assertPreservesFirstAndLast(count: 301)
    }

    func testManyMoreThanMaxCount() {
        assertPreservesFirstAndLast(count: 5_000)
    }

    func testEmptyInput() {
        XCTAssertEqual(bodyWorkoutHeartRateScatterSamples([]), [])
    }
}
