//
//  BodyTestSupport.swift
//  BodyTests
//

import Foundation
import XCTest

/// Shared helpers for tests that read files out of the repo working tree
/// (Swift source, plists, string catalogs, docs). Centralised so a foreign
/// checkout (missing `body.xcodeproj`) skips these tests instead of failing
/// all of them, and so the root-resolution logic exists in one place.
enum BodyTestSupport {
    /// Resolves the repo root by walking up from this file's `#filePath`
    /// (`BodyTests/Support/BodyTestSupport.swift` -> `BodyTests` -> repo root),
    /// unless `BODY_SRCROOT` is set in the environment AND that path actually
    /// contains `body.xcodeproj`, in which case the override wins.
    static let projectRoot: URL = {
        let walkedUp = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        if let override = ProcessInfo.processInfo.environment["BODY_SRCROOT"] {
            let overrideURL = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: overrideURL.appendingPathComponent("body.xcodeproj").path) {
                return overrideURL
            }
        }

        return walkedUp
    }()

    /// Skips the calling test when `body.xcodeproj` is not present at
    /// `projectRoot` (a foreign checkout, or a stripped source archive)
    /// instead of letting file reads fail every source-guard test.
    static func requireProjectRoot() throws {
        let marker = projectRoot.appendingPathComponent("body.xcodeproj")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: marker.path),
            "body.xcodeproj not found at \(projectRoot.path); skipping source-guard test outside the full repo checkout"
        )
    }

    static func sourceText(at relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func propertyList(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent(relativePath))
        var format = PropertyListSerialization.PropertyListFormat.xml
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )
        return try XCTUnwrap(propertyList as? [String: Any])
    }

    static func catalogStrings(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent(relativePath))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], relativePath)
        return try XCTUnwrap(root["strings"] as? [String: Any], relativePath)
    }

    /// Every language the string catalogs ship, the development language first.
    /// Adding a language to the app means adding it here and to `knownRegions`.
    static let catalogLanguages = ["en", "zh-Hans", "de", "es", "tr", "hi", "fr", "ru"]

    /// The `stringUnit` dictionaries one language's catalog entry resolves to:
    /// the single unit of a plain entry, or one per plural form of a
    /// `variations.plural` entry (which must carry `other`).
    static func stringUnits(in localization: [String: Any], context: String) throws -> [[String: Any]] {
        if let unit = localization["stringUnit"] as? [String: Any] {
            return [unit]
        }
        let variations = try XCTUnwrap(localization["variations"] as? [String: Any], "\(context) has neither stringUnit nor variations")
        let plural = try XCTUnwrap(variations["plural"] as? [String: Any], "\(context) variation is not a plural")
        XCTAssertNotNil(plural["other"], "\(context) plural lacks other")
        return try plural.keys.sorted().map { form in
            let variant = try XCTUnwrap(plural[form] as? [String: Any], "\(context) \(form)")
            return try XCTUnwrap(variant["stringUnit"] as? [String: Any], "\(context) \(form) missing stringUnit")
        }
    }

    /// The value a plain entry shows, or the `other` form of a plural entry.
    static func stringValue(in localization: [String: Any], context: String) throws -> String {
        if let unit = localization["stringUnit"] as? [String: Any] {
            return try XCTUnwrap(unit["value"] as? String, "\(context) missing value")
        }
        let variations = try XCTUnwrap(localization["variations"] as? [String: Any], "\(context) has neither stringUnit nor variations")
        let plural = try XCTUnwrap(variations["plural"] as? [String: Any], "\(context) variation is not a plural")
        let other = try XCTUnwrap(plural["other"] as? [String: Any], "\(context) plural lacks other")
        let unit = try XCTUnwrap(other["stringUnit"] as? [String: Any], "\(context) other missing stringUnit")
        return try XCTUnwrap(unit["value"] as? String, "\(context) other missing value")
    }
}

extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
