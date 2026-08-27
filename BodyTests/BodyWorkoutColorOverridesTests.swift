//
//  BodyWorkoutColorOverridesTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

final class BodyWorkoutColorOverridesTests: XCTestCase {

    // MARK: - Parsing

    func testParsesSimpleOverrideList() {
        let parsed = BodyWorkoutColorOverrides.overrides(from: "running:112233,cycling:AABBCC")

        XCTAssertEqual(parsed, [.running: 0x112233, .cycling: 0xAABBCC])
    }

    func testAcceptsLowercaseHexAndSurroundingWhitespace() {
        let parsed = BodyWorkoutColorOverrides.overrides(from: "  running : 1a2b3c ,\n cycling:aabbcc ")

        XCTAssertEqual(parsed, [.running: 0x1A2B3C, .cycling: 0xAABBCC])
    }

    func testDuplicateKeysAreLastWins() {
        let parsed = BodyWorkoutColorOverrides.overrides(from: "running:112233,running:445566")

        XCTAssertEqual(parsed, [.running: 0x445566])
    }

    func testDuplicateKeyResolvingBackToDefaultIsDropped() {
        let defaultHex = BodyWorkoutColorOverrides.hexText(from: BodyWorkoutType.running.colorHex)
        let parsed = BodyWorkoutColorOverrides.overrides(from: "running:112233,running:\(defaultHex)")

        XCTAssertTrue(parsed.isEmpty)
    }

    func testUnknownWorkoutTypesAreDropped() {
        let parsed = BodyWorkoutColorOverrides.overrides(from: "someFutureWorkout:112233,running:445566")

        XCTAssertEqual(parsed, [.running: 0x445566])
    }

    func testMalformedTokensAreDroppedButValidOnesSurvive() {
        let raw = "running,cycling:ZZZZZZ,walking:12345,hiking:1234567,yoga:112233,:445566,swimming:,other:11:22"
        let parsed = BodyWorkoutColorOverrides.overrides(from: raw)

        XCTAssertEqual(parsed, [.yoga: 0x112233])
    }

    func testEntriesMatchingTheBuiltInDefaultAreDropped() {
        let defaultHex = BodyWorkoutColorOverrides.hexText(from: BodyWorkoutType.running.colorHex)
        let parsed = BodyWorkoutColorOverrides.overrides(from: "running:\(defaultHex),cycling:AABBCC")

        XCTAssertEqual(parsed, [.cycling: 0xAABBCC])
    }

    func testEmptyRawValueParsesToNoOverrides() {
        XCTAssertTrue(BodyWorkoutColorOverrides.overrides(from: "").isEmpty)
    }

    func testOverlongRawValueIsRejectedWholesale() {
        let padding = String(repeating: "x", count: BodyWorkoutColorOverrides.maximumRawValueLength)
        let raw = "running:112233,\(padding)"

        XCTAssertGreaterThan(raw.count, BodyWorkoutColorOverrides.maximumRawValueLength)
        XCTAssertTrue(BodyWorkoutColorOverrides.overrides(from: raw).isEmpty)
    }

    func testRawValueAtExactlyTheCapIsStillParsed() {
        let token = "running:112233"
        let filler = String(repeating: ",", count: BodyWorkoutColorOverrides.maximumRawValueLength - token.count)
        let raw = token + filler

        XCTAssertEqual(raw.count, BodyWorkoutColorOverrides.maximumRawValueLength)
        XCTAssertEqual(BodyWorkoutColorOverrides.overrides(from: raw), [.running: 0x112233])
    }

    // MARK: - Serialization

    func testSerializesSortedUppercaseAndUnprefixed() {
        let raw = BodyWorkoutColorOverrides.rawValue(from: [.running: 0x1A2B3C, .cycling: 0xAABBCC, .yoga: 0x000102])

        XCTAssertEqual(raw, "cycling:AABBCC,running:1A2B3C,yoga:000102")
        XCTAssertFalse(raw.contains("#"))
    }

    func testSerializationOmitsDefaultEqualEntries() {
        let raw = BodyWorkoutColorOverrides.rawValue(from: [.running: BodyWorkoutType.running.colorHex, .cycling: 0xAABBCC])

        XCTAssertEqual(raw, "cycling:AABBCC")
    }

    func testSerializingNoOverridesProducesEmptyString() {
        XCTAssertEqual(BodyWorkoutColorOverrides.rawValue(from: [:]), "")
    }

    func testRoundTripsThroughRawValue() {
        let overrides: [BodyWorkoutType: UInt32] = [.running: 0x1A2B3C, .cycling: 0xAABBCC, .swimming: 0x010203]

        let raw = BodyWorkoutColorOverrides.rawValue(from: overrides)

        XCTAssertEqual(BodyWorkoutColorOverrides.overrides(from: raw), overrides)
    }

    func testCanonicalizationIsStableForEquivalentInputs() {
        let messy = " cycling:aabbcc , running:1a2b3c , running:1a2b3c "
        let canonical = BodyWorkoutColorOverrides.rawValue(from: BodyWorkoutColorOverrides.overrides(from: messy))

        XCTAssertEqual(canonical, "cycling:AABBCC,running:1A2B3C")
        XCTAssertEqual(
            BodyWorkoutColorOverrides.rawValue(from: BodyWorkoutColorOverrides.overrides(from: canonical)),
            canonical
        )
    }

    // MARK: - Palette resolution

    func testPaletteAppliesOverridesWhenProIsUnlocked() {
        let palette = BodyWorkoutColorPalette(rawOverrides: "running:AABBCC", isProUnlocked: true)

        XCTAssertEqual(palette.resolvedHex(for: .running), 0xAABBCC)
        XCTAssertTrue(palette.isCustomized)
    }

    func testPaletteIgnoresOverridesWhenProIsLocked() {
        let palette = BodyWorkoutColorPalette(rawOverrides: "running:AABBCC", isProUnlocked: false)

        XCTAssertEqual(palette.resolvedHex(for: .running), BodyWorkoutType.running.colorHex)
        XCTAssertFalse(palette.isCustomized)
        XCTAssertEqual(palette, .builtIn)
    }

    func testPaletteFallsBackToBuiltInForUncustomizedTypes() {
        let palette = BodyWorkoutColorPalette(rawOverrides: "running:AABBCC", isProUnlocked: true)

        XCTAssertEqual(palette.resolvedHex(for: .cycling), BodyWorkoutType.cycling.colorHex)
    }

    func testBuiltInPaletteIsNotCustomized() {
        XCTAssertFalse(BodyWorkoutColorPalette.builtIn.isCustomized)
        XCTAssertEqual(BodyWorkoutColorPalette.builtIn.resolvedHex(for: .yoga), BodyWorkoutType.yoga.colorHex)
    }

    func testPaletteEquatabilityTracksResolvedOverrides() {
        let lhs = BodyWorkoutColorPalette(rawOverrides: "running:AABBCC", isProUnlocked: true)
        let rhs = BodyWorkoutColorPalette(rawOverrides: " running : aabbcc ", isProUnlocked: true)
        let other = BodyWorkoutColorPalette(rawOverrides: "running:AABBCD", isProUnlocked: true)

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, other)
    }

    // MARK: - Rendering parity

    func testDefaultPaletteColorsMatchWorkoutTypeColors() throws {
        for type in BodyWorkoutType.allCases {
            XCTAssertEqual(try hexValue(for: BodyWorkoutColorPalette.builtIn.color(for: type)), try hexValue(for: type.color), type.rawValue)
        }
    }

    func testOverriddenColorRendersTheOverrideHex() throws {
        let palette = BodyWorkoutColorPalette(rawOverrides: "running:AABBCC", isProUnlocked: true)

        XCTAssertEqual(try hexValue(for: palette.color(for: .running)), 0xAABBCC)
    }

    func testContentColorIsDarkAboveTheLuminanceThreshold() throws {
        // 0x949494 → luminance 148/255 ≈ 0.5804, just above the 0.58 gate.
        let palette = BodyWorkoutColorPalette(rawOverrides: "running:949494", isProUnlocked: true)

        XCTAssertGreaterThan(BodyWorkoutType.luminance(hex: 0x949494), 0.58)
        let components = try colorComponents(for: palette.contentColor(for: .running))
        XCTAssertEqual(components.red, 0, accuracy: 0.01)
        XCTAssertEqual(components.green, 0, accuracy: 0.01)
        XCTAssertEqual(components.blue, 0, accuracy: 0.01)
        XCTAssertEqual(components.alpha, 0.82, accuracy: 0.01)
    }

    func testContentColorIsLightBelowTheLuminanceThreshold() throws {
        // 0x939393 → luminance 147/255 ≈ 0.5765, just below the 0.58 gate.
        let palette = BodyWorkoutColorPalette(rawOverrides: "running:939393", isProUnlocked: true)

        XCTAssertLessThan(BodyWorkoutType.luminance(hex: 0x939393), 0.58)
        let components = try colorComponents(for: palette.contentColor(for: .running))
        XCTAssertEqual(components.red, 1, accuracy: 0.01)
        XCTAssertEqual(components.green, 1, accuracy: 0.01)
        XCTAssertEqual(components.blue, 1, accuracy: 0.01)
        XCTAssertEqual(components.alpha, 1, accuracy: 0.01)
    }

    func testDefaultContentColorsMatchCalendarContentColors() throws {
        for type in BodyWorkoutType.allCases {
            let palette = try colorComponents(for: BodyWorkoutColorPalette.builtIn.contentColor(for: type))
            let builtIn = try colorComponents(for: type.calendarContentColor)

            XCTAssertEqual(palette.red, builtIn.red, accuracy: 0.001, type.rawValue)
            XCTAssertEqual(palette.green, builtIn.green, accuracy: 0.001, type.rawValue)
            XCTAssertEqual(palette.blue, builtIn.blue, accuracy: 0.001, type.rawValue)
            XCTAssertEqual(palette.alpha, builtIn.alpha, accuracy: 0.001, type.rawValue)
        }
    }

    // MARK: - Known workout types census

    func testCensusRoundTrips() {
        let types: Set<BodyWorkoutType> = [.running, .cycling, .yoga]

        let raw = BodyKnownWorkoutTypesCensus.rawValue(from: types)

        XCTAssertEqual(raw, "cycling,running,yoga")
        XCTAssertEqual(BodyKnownWorkoutTypesCensus.types(from: raw), types)
    }

    func testCensusSerializationIsDeterministicallyOrdered() {
        let first = BodyKnownWorkoutTypesCensus.rawValue(from: [.yoga, .cycling, .running])
        let second = BodyKnownWorkoutTypesCensus.rawValue(from: [.running, .yoga, .cycling])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "cycling,running,yoga")
    }

    func testCensusDropsUnknownAndEmptyEntries() {
        let types = BodyKnownWorkoutTypesCensus.types(from: "running,someFutureWorkout,, cycling ,")

        XCTAssertEqual(types, [.running, .cycling])
    }

    func testCensusMergingUnionsWithoutDuplicating() {
        let merged = BodyKnownWorkoutTypesCensus.merging(rawValue: "running,cycling", with: [.cycling, .yoga])

        XCTAssertEqual(merged, "cycling,running,yoga")
    }

    func testCensusMergingIntoEmptyStorageStartsTheList() {
        XCTAssertEqual(BodyKnownWorkoutTypesCensus.merging(rawValue: "", with: [.swimming]), "swimming")
    }

    func testCensusMergingNothingKeepsExistingEntriesCanonical() {
        XCTAssertEqual(BodyKnownWorkoutTypesCensus.merging(rawValue: "yoga,running", with: []), "running,yoga")
    }

    // MARK: - Helpers

    private func hexValue(for color: Color) throws -> UInt32 {
        let components = try colorComponents(for: color)
        let red = UInt32((components.red * 255).rounded())
        let green = UInt32((components.green * 255).rounded())
        let blue = UInt32((components.blue * 255).rounded())

        return (red << 16) | (green << 8) | blue
    }

    private func colorComponents(for color: Color) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        let didReadComponents = UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertTrue(didReadComponents)

        return (red, green, blue, alpha)
    }
}
