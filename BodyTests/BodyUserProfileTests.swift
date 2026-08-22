//
//  BodyUserProfileTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

final class BodyUserProfileTests: XCTestCase {
    func testDisplayNameTrimsSurroundingWhitespace() {
        XCTAssertEqual(BodyUserProfile.displayName(from: "  Justin \n"), "Justin")
    }

    func testDisplayNameIsNilWhenNothingButWhitespace() {
        XCTAssertNil(BodyUserProfile.displayName(from: ""))
        XCTAssertNil(BodyUserProfile.displayName(from: "   \n\t"))
    }

    func testDisplayNamePassesThroughAName() {
        XCTAssertEqual(BodyUserProfile.displayName(from: "Justin Z"), "Justin Z")
    }

    func testAvatarDataFitsWithinTheMaximumDimension() throws {
        let source = solidImage(size: CGSize(width: 1_200, height: 800))
        let data = try XCTUnwrap(BodyProfileImageCodec.avatarData(from: source))
        let decoded = try XCTUnwrap(UIImage(data: data))

        XCTAssertEqual(decoded.size.width, BodyProfileImageCodec.avatarMaxDimension, accuracy: 1)
        XCTAssertLessThanOrEqual(decoded.size.height, BodyProfileImageCodec.avatarMaxDimension)
    }

    func testAvatarDataNeverUpscalesASmallImage() throws {
        let source = solidImage(size: CGSize(width: 100, height: 100))
        let data = try XCTUnwrap(BodyProfileImageCodec.avatarData(from: source))
        let decoded = try XCTUnwrap(UIImage(data: data))

        XCTAssertEqual(decoded.size.width, 100, accuracy: 1)
        XCTAssertEqual(decoded.size.height, 100, accuracy: 1)
    }

    func testSettingsShowsTheProfileCardAboveAppearance() throws {
        let settingsSource = try text(at: "Body/Views/BodySettingsView.swift")
        let profileRange = try XCTUnwrap(settingsSource.range(of: "profileEntryCard"))
        let appearanceRange = try XCTUnwrap(settingsSource.range(of: "appearanceSection"))

        XCTAssertLessThan(profileRange.lowerBound, appearanceRange.lowerBound)
        XCTAssertTrue(settingsSource.contains("BodyProfileView()"))
    }

    func testProfilePageKeepsThePickerCropAndZoomAffordances() throws {
        let profileSource = try text(at: "Body/Views/BodyProfileView.swift")

        XCTAssertTrue(profileSource.contains(".photosPicker("))
        XCTAssertTrue(profileSource.contains("fullScreenCover"))
        XCTAssertTrue(profileSource.contains("MagnifyGesture"))
    }

    func testProfileHeroPlaceholderIsWhiteAndGlowFallsBackToBodyBlue() throws {
        let profileSource = try text(at: "Body/Views/BodyProfileView.swift")

        XCTAssertTrue(profileSource.contains("fallbackGlowColor = BodyWorkoutShareCardView.defaultRouteColor"))
        XCTAssertFalse(profileSource.contains("BodyProPalette.gold.opacity(0.14)"))
    }

    func testGlowColorFollowsThePhotosOwnHue() throws {
        let blue = try XCTUnwrap(BodyProfileImageCodec.glowColor(from: solidImage(size: CGSize(width: 40, height: 40))))

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(UIColor(blue).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha))

        // systemBlue sits near 0.59 on the hue wheel; gold would be near 0.11.
        XCTAssertEqual(Double(hue), 0.59, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(Double(brightness), 0.55)
    }

    func testGlowColorLiftsADarkPhotoIntoAVisibleGlow() throws {
        let nearBlack = solidImage(size: CGSize(width: 40, height: 40), color: UIColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1))
        let glow = try XCTUnwrap(BodyProfileImageCodec.glowColor(from: nearBlack))

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(UIColor(glow).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha))

        XCTAssertEqual(Double(brightness), 0.55, accuracy: 0.01)
    }

    func testGlowColorFloorsAMutedPhotosSaturation() throws {
        // Average saturation ~0.19: chromatic, but far too washed out to glow as-is.
        let muted = solidImage(size: CGSize(width: 40, height: 40), color: UIColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1))
        let glow = try XCTUnwrap(BodyProfileImageCodec.glowColor(from: muted))

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(UIColor(glow).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha))

        XCTAssertGreaterThanOrEqual(Double(saturation), 0.45)
    }

    func testGlowColorFallsBackForAGrayscalePhoto() {
        let gray = solidImage(size: CGSize(width: 40, height: 40), color: UIColor(white: 0.42, alpha: 1))

        // Nil, not a hue invented from near-gray noise: the hero stays on Body Blue.
        XCTAssertNil(BodyProfileImageCodec.glowColor(from: gray))
    }

    func testMotivationLineHoldsStillThroughTheDay() throws {
        let morning = try XCTUnwrap(date(year: 2026, month: 8, day: 22, hour: 7))
        let night = try XCTUnwrap(date(year: 2026, month: 8, day: 22, hour: 23))

        XCTAssertEqual(BodyProfileMotivation.line(for: morning), BodyProfileMotivation.line(for: night))
    }

    func testMotivationLineTurnsOverAtMidnight() throws {
        let today = try XCTUnwrap(date(year: 2026, month: 8, day: 22, hour: 23))
        let tomorrow = try XCTUnwrap(date(year: 2026, month: 8, day: 23, hour: 0))

        XCTAssertNotEqual(BodyProfileMotivation.line(for: today), BodyProfileMotivation.line(for: tomorrow))
    }

    func testMotivationLinesAreDistinct() {
        let rendered = BodyProfileMotivation.lines.map { String(describing: $0) }

        XCTAssertEqual(Set(rendered).count, BodyProfileMotivation.lines.count)
    }

    // MARK: - Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date? {
        Calendar.bodyGregorian.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }

    private func solidImage(size: CGSize, color: UIColor = .systemBlue) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
