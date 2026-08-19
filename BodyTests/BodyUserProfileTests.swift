//
//  BodyUserProfileTests.swift
//  BodyTests
//

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

    // MARK: - Helpers

    private func solidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
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
