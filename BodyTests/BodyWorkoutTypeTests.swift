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
