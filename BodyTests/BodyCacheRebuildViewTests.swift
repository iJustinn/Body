//
//  BodyCacheRebuildViewTests.swift
//  BodyTests
//
//  Snapshots both entries of `BodyCacheRebuildView` in English and Simplified
//  Chinese from a hosted window: proves the page renders at all, and, with BODY_RENDER_OUTPUT_DIR
//  set, writes the PNGs so the layout can be reviewed by eye (the copy is long
//  enough that a zh-Hans overflow would not show up in any other assertion).
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

@MainActor
final class BodyCacheRebuildViewTests: XCTestCase {
    private static let pageSize = CGSize(width: 393, height: 852)
    private static let scale: CGFloat = 2

    /// Hosted in a real window: `ImageRenderer` draws a `ScrollView` blank, so
    /// the page body would never show up in its output.
    private func render(entry: BodyCacheRebuildView.Entry, locale: Locale) -> UIImage {
        let page = BodyCacheRebuildView(entry: entry)
            .environment(HealthKitWorkoutStore())
            .environment(\.locale, locale)
        let host = UIHostingController(rootView: page)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: Self.pageSize)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: Self.pageSize))
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.scale
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
        window.isHidden = true
        return image
    }

    func testBothEntriesRenderInEnglishAndSimplifiedChinese() throws {
        let entries: [(BodyCacheRebuildView.Entry, String)] = [(.update, "update"), (.settings, "settings")]
        let locales = ["en", "zh-Hans"]

        for (entry, entryName) in entries {
            for identifier in locales {
                let image = render(entry: entry, locale: Locale(identifier: identifier))
                let cgImage = try XCTUnwrap(image.cgImage, "\(entryName)/\(identifier)")
                XCTAssertEqual(cgImage.width, Int(Self.pageSize.width * Self.scale), "\(entryName)/\(identifier)")
                XCTAssertEqual(cgImage.height, Int(Self.pageSize.height * Self.scale), "\(entryName)/\(identifier)")

                write(image, name: "rebuild-\(entryName)-\(identifier).png")
            }
        }
    }

    private func write(_ image: UIImage, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["BODY_RENDER_OUTPUT_DIR"],
              let data = image.pngData() else {
            return
        }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? data.write(to: url.appendingPathComponent(name))
    }
}
