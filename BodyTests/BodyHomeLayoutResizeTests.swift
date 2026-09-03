//
//  BodyHomeLayoutResizeTests.swift
//  BodyTests
//
//  Home's scroll content must span exactly the scroll viewport at every window width.
//  Under Stage Manager the `containerRelativeFrame(.horizontal)` pin kept the width of
//  the window the scene was created with, so a resized window showed a fixed column:
//  centered with clipped cards in a wide window, overflowing both edges in a narrow one.
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

@MainActor
final class BodyHomeLayoutResizeTests: XCTestCase {
    private static let height: CGFloat = 900

    func testHomeContentTracksTheViewportWidthAcrossWindowResizes() throws {
        let window = try makeHostedHomeWindow(width: 1024)

        for width in [1024, 500, 400, 1100] as [CGFloat] {
            window.frame = CGRect(x: 0, y: 0, width: width, height: Self.height)
            settle(window)

            let scrollView = try XCTUnwrap(
                Self.firstScrollView(in: window),
                "No UIScrollView materialized in the hosted Home hierarchy"
            )
            XCTAssertEqual(
                scrollView.contentSize.width,
                scrollView.bounds.width,
                accuracy: 1,
                "Home content width should equal the viewport width at a \(Int(width)) pt window"
            )
            XCTAssertEqual(scrollView.contentOffset.x, 0, accuracy: 1, "Home must not pan horizontally at \(Int(width)) pt")
        }
    }

    // MARK: - Harness

    private func makeHostedHomeWindow(width: CGFloat) throws -> UIWindow {
        let calendar = Calendar.bodyGregorian
        let today = Date()
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: calendar.component(.month, from: today),
                year: calendar.component(.year, from: today),
                workouts: [],
                calendar: calendar
            ),
            initialHealthDashboardSnapshot: .empty,
            initialSummaryContextSignature: nil,
            initialPermissionSelection: BodyHealthPermissionSelection.defaultValue
        )

        let root = BodyHomeView()
            .environment(store)
            .environment(ReadinessCommentGenerator())

        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "BodyTests is app-hosted, so a UIWindowScene must exist"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: Self.height)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        settle(window)
        return window
    }

    private func settle(_ window: UIWindow) {
        for _ in 0..<6 {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}
