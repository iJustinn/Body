//
//  BodyHomeReadinessHeroPinTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

/// Hosts the real hero pin, hero and summary card in Home's scroll shape and drives
/// the scroll offset directly, so the pinned position is asserted on rendered frames
/// rather than on the pin's arithmetic.
@MainActor
final class BodyHomeReadinessHeroPinTests: XCTestCase {
    private static let viewport = CGSize(width: 390, height: 844)
    /// The width Home would hand the hero at this viewport: the ring's radius, and with
    /// it the hero's height and morph distance, are sized from it.
    private static let heroWidth = BodyReadinessArcGeometry.heroWidth(pageWidth: viewport.width)

    func testHeroPinsAtTheViewportTopWithoutANotice() throws {
        let harness = try makeHarness(notice: nil)
        defer { harness.tearDown() }

        let resting = try XCTUnwrap(harness.recorder.frames["hero"])
        XCTAssertEqual(resting.minY, 10, accuracy: 1, "At rest the hero sits under the page's top padding")
        let gridAtRest = try XCTUnwrap(harness.recorder.frames["grid"])

        try harness.scroll(to: 10 + BodyReadinessArcGeometry.morphDistance(width: Self.heroWidth) / 2)
        let pinned = try XCTUnwrap(harness.recorder.frames["hero"])
        XCTAssertEqual(pinned.minY, 0, accuracy: 1, "Past its resting position the hero holds the viewport top")

        let barBottom = BodyReadinessArcGeometry.flatY + BodyReadinessArcGeometry.flatBarWidth / 2
        let release = gridAtRest.minY - (barBottom + BodyReadinessArcGeometry.heldGridGap)
        XCTAssertGreaterThan(release, 10 + BodyReadinessArcGeometry.morphDistance(width: Self.heroWidth), "The comment scrolls under the bar before the grid arrives")

        try harness.scroll(to: release)
        let held = try XCTUnwrap(harness.recorder.frames["hero"])
        XCTAssertEqual(held.minY, 0, accuracy: 1, "Still held at the top when the first card row arrives")
        let grid = try XCTUnwrap(harness.recorder.frames["grid"])
        XCTAssertEqual(grid.minY, barBottom + BodyReadinessArcGeometry.heldGridGap, accuracy: 1.5, "The first card row sits the grid spacing under the flat bar")

        try harness.scroll(to: release + 60)
        let released = try XCTUnwrap(harness.recorder.frames["hero"])
        XCTAssertEqual(released.minY, -60, accuracy: 1, "Past the hold the hero scrolls away with the cards")
    }

    func testHeroPinsAtTheSameSpotWithANotice() throws {
        let harness = try makeHarness(notice: "Health data is still syncing. Some cards may lag behind for a few minutes while the first import finishes.")
        defer { harness.tearDown() }

        let resting = try XCTUnwrap(harness.recorder.frames["hero"])
        XCTAssertEqual(resting.minY, 10, accuracy: 1, "The notice sits under the hero text, so the hero rests where it does without one")
        let gridAtRest = try XCTUnwrap(harness.recorder.frames["grid"])
        let notice = try XCTUnwrap(harness.recorder.frames["notice"])
        let comment = try XCTUnwrap(harness.recorder.frames["card"])
        XCTAssertEqual(notice.minY - comment.maxY, 14, accuracy: 1, "One card gap under the hero text")
        XCTAssertEqual(gridAtRest.minY - notice.maxY, 14, accuracy: 1, "One card gap above the first card row")

        try harness.scroll(to: resting.minY + BodyReadinessArcGeometry.morphDistance(width: Self.heroWidth) / 2)
        let pinned = try XCTUnwrap(harness.recorder.frames["hero"])
        XCTAssertEqual(pinned.minY, 0, accuracy: 1, "The pin lands at the viewport top regardless of the notice's height")

        let barBottom = BodyReadinessArcGeometry.flatY + BodyReadinessArcGeometry.flatBarWidth / 2
        let release = gridAtRest.minY - (barBottom + BodyReadinessArcGeometry.heldGridGap)
        try harness.scroll(to: release + 60)
        let released = try XCTUnwrap(harness.recorder.frames["hero"])
        XCTAssertEqual(released.minY, -60, accuracy: 1, "The hold ends when the grid arrives, wherever the notice put it")
    }

    func testHeroReturnsToRestWhenScrolledBack() throws {
        let harness = try makeHarness(notice: nil)
        defer { harness.tearDown() }

        try harness.scroll(to: 300)
        try harness.scroll(to: 0)
        let resting = try XCTUnwrap(harness.recorder.frames["hero"])
        XCTAssertEqual(resting.minY, 10, accuracy: 1)
    }

    // MARK: - Harness

    private final class FrameRecorder {
        var frames: [String: CGRect] = [:]
    }

    private struct PinProbePage: View {
        let notice: String?
        let recorder: FrameRecorder
        @State private var scrollState = BodyHomeScrollState()

        var body: some View {
            let viewportCoordinateSpace = BodyHomeView.viewportCoordinateSpace
            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    BodyReadinessHeroScrollPin(
                        scrollState: scrollState,
                        width: BodyHomeReadinessHeroPinTests.heroWidth
                    ) { progress, _ in
                        BodyReadinessArcHero(
                            readiness: Self.sample,
                            width: BodyHomeReadinessHeroPinTests.heroWidth,
                            progress: progress
                        )
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(viewportCoordinateSpace))
                            } action: { frame in
                                recorder.frames["hero"] = frame
                            }
                    }

                    BodyReadinessHeroComment(readiness: Self.sample, morningScore: nil)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(viewportCoordinateSpace))
                        } action: { frame in
                            recorder.frames["card"] = frame
                        }

                    if let notice {
                        BodyHealthNoticeBanner(message: notice)
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(viewportCoordinateSpace))
                            } action: { frame in
                                recorder.frames["notice"] = frame
                            }
                    }

                    VStack(spacing: 14) {
                        ForEach(0..<8, id: \.self) { _ in
                            Color.clear.frame(height: 240)
                        }
                    }
                    .modifier(BodyHomeGridPositionReporter(scrollState: scrollState))
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(viewportCoordinateSpace))
                    } action: { frame in
                        recorder.frames["grid"] = frame
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .coordinateSpace(name: BodyHomeView.contentCoordinateSpace)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollState.offset = max(0, offset)
            }
            .coordinateSpace(name: BodyHomeView.viewportCoordinateSpace)
        }

        static let sample = ReadinessSummary(
            score: 80,
            status: .high,
            confidence: .high,
            components: [ReadinessComponent(kind: .sleep, score: 80, weight: 1, message: "")],
            drivers: []
        )
    }

    @MainActor
    private struct Harness {
        let window: UIWindow
        let recorder: FrameRecorder

        func settle() {
            for _ in 0..<6 {
                window.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            window.layoutIfNeeded()
        }

        func scroll(to offset: CGFloat) throws {
            let scrollView = try XCTUnwrap(
                BodyHomeReadinessHeroPinTests.firstScrollView(in: window),
                "No UIScrollView materialized in the hosted hierarchy"
            )
            scrollView.setContentOffset(CGPoint(x: 0, y: offset - scrollView.adjustedContentInset.top), animated: false)
            settle()
        }

        func tearDown() {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func makeHarness(notice: String?) throws -> Harness {
        let recorder = FrameRecorder()
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "BodyTests is app-hosted, so a UIWindowScene must exist"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.viewport)
        window.rootViewController = UIHostingController(rootView: PinProbePage(notice: notice, recorder: recorder))
        window.makeKeyAndVisible()
        let harness = Harness(window: window, recorder: recorder)
        harness.settle()
        return harness
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
