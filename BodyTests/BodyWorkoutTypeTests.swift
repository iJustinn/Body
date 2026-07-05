//
//  BodyWorkoutTypeTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

final class BodyWorkoutTypeTests: XCTestCase {
    func testWorkoutColorsUseOnlyAttachedPalette() throws {
        for type in BodyWorkoutType.allCases {
            let hex = try hexValue(for: type.color)
            XCTAssertTrue(BodyWorkoutType.attachedPaletteHexes.contains(hex), type.rawValue)
        }
    }

    func testAttachedPaletteSwatchesAreRepresented() {
        let usedHexes = Set(BodyWorkoutType.allCases.map(\.colorHex))

        XCTAssertTrue(usedHexes.isSuperset(of: BodyWorkoutType.attachedPaletteHexes))
    }

    func testKeyWorkoutColorsUseRequestedSwatches() throws {
        XCTAssertEqual(try hexValue(for: BodyWorkoutType.strengthTraining.color), 0xB7172D)
        XCTAssertEqual(try hexValue(for: BodyWorkoutType.walking.color), 0x0D9099)
        XCTAssertEqual(try hexValue(for: BodyWorkoutType.cycling.color), 0xEE9D58)
    }

    func testWalkingUsesMutedPalette() throws {
        let components = try colorComponents(for: BodyWorkoutType.walking.color)

        XCTAssertLessThan(components.red, 0.08)
        XCTAssertGreaterThan(components.green, 0.50)
        XCTAssertGreaterThan(components.blue, 0.50)
        XCTAssertLessThanOrEqual(components.luminance, 0.501)
    }

    // MARK: - Tolerant decoding (M23)

    func testDecodingUnknownRawValueFallsBackToOther() throws {
        let json = Data("\"someFutureWorkoutType\"".utf8)

        let decoded = try JSONDecoder().decode(BodyWorkoutType.self, from: json)

        XCTAssertEqual(decoded, .other)
    }

    func testDecodingKnownRawValueStillDecodesToThatCase() throws {
        let json = Data("\"running\"".utf8)

        let decoded = try JSONDecoder().decode(BodyWorkoutType.self, from: json)

        XCTAssertEqual(decoded, .running)
    }

    func testWorkoutSummaryDecodesUnknownWorkoutTypeAsOtherInsteadOfThrowing() throws {
        let json = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "type": "someFutureWorkoutType",
          "startDate": 780000000.0,
          "duration": 1800,
          "sourceName": "Apple Health"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(WorkoutSummary.self, from: json)

        XCTAssertEqual(decoded.type, .other)
        XCTAssertEqual(decoded.duration, 1800)
        XCTAssertEqual(decoded.sourceName, "Apple Health")
    }

    func testWorkoutMonthSnapshotDecodesUnknownWorkoutTypeWithoutLosingOtherWorkouts() throws {
        let snapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [
                workout(day: 6, type: .running, duration: 2_400),
                workout(day: 9, type: .strengthTraining, duration: 3_600)
            ],
            calendar: .bodyGregorian
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var json = String(decoding: try encoder.encode(snapshot), as: UTF8.self)

        // Simulate a version-skewed writer (e.g. the watch app) that persisted a
        // workout type this build doesn't recognize yet.
        json = json.replacingOccurrences(of: "\"type\":\"running\"", with: "\"type\":\"someFutureWorkoutType\"")

        let decoded = try JSONDecoder().decode(WorkoutMonthSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.workoutCount, 2)
        XCTAssertEqual(decoded.day(6)?.workouts.first?.type, .other)
        XCTAssertEqual(decoded.day(9)?.workouts.first?.type, .strengthTraining)
    }

    private func workout(day: Int, type: BodyWorkoutType, duration: TimeInterval) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", day))") ?? UUID(),
            type: type,
            startDate: Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: day, hour: 8)) ?? Date(),
            duration: duration,
            activeEnergyKilocalories: 100,
            distanceMeters: 1_000,
            sourceName: "Tests"
        )
    }

    private func hexValue(for color: Color) throws -> UInt32 {
        let components = try colorComponents(for: color)
        let red = UInt32((components.red * 255).rounded())
        let green = UInt32((components.green * 255).rounded())
        let blue = UInt32((components.blue * 255).rounded())

        return (red << 16) | (green << 8) | blue
    }

    private func colorComponents(for color: Color) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, luminance: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        let didReadComponents = UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertTrue(didReadComponents)

        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return (red, green, blue, luminance)
    }
}
