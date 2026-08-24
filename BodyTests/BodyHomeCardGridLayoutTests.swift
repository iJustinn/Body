//
//  BodyHomeCardGridLayoutTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

/// Covers the Home summary grid after it moved from a `ForEach` of rows to a single flat
/// `ForEach` inside `BodyHomeCardGridLayout`. The move exists so each card keeps one view
/// identity across a reorder — a card destroyed mid-drag is what left UIKit's cancelled
/// set-down animation reading a freed AttributeGraph attribute — so identity is asserted
/// here next to the geometry the old `HStack` rows produced.
@MainActor
final class BodyHomeCardGridLayoutTests: XCTestCase {
    /// Home's 390 pt viewport minus its 16 pt horizontal padding.
    private static let gridWidth: CGFloat = 358
    private static let spacing: CGFloat = 14
    private static let columnWidth: CGFloat = (gridWidth - spacing) / 2

    // MARK: - Packing

    func testPackingGivesATwoSlotItemItsOwnRow() {
        XCTAssertEqual(BodyHomeCardGridPacking.rows(slotCounts: [2, 1, 1]), [[0], [1, 2]])
        XCTAssertEqual(BodyHomeCardGridPacking.rows(slotCounts: [1, 1, 2]), [[0, 1], [2]])
    }

    /// A lone one-slot card keeps its half-empty row when a two-slot card follows — the
    /// behaviour `BodyHomeCardKind.layoutRows` has always had.
    func testPackingKeepsAHalfEmptyRowBeforeATwoSlotItem() {
        XCTAssertEqual(BodyHomeCardGridPacking.rows(slotCounts: [1, 2, 1]), [[0], [1], [2]])
    }

    func testPackingHandlesEmptyTrailingAndDegenerateInput() {
        XCTAssertEqual(BodyHomeCardGridPacking.rows(slotCounts: []), [])
        XCTAssertEqual(BodyHomeCardGridPacking.rows(slotCounts: [1]), [[0]])
        XCTAssertEqual(BodyHomeCardGridPacking.rows(slotCounts: [1, 1, 1]), [[0, 1], [2]])
        // A zero or negative slot count would otherwise pack a row without bound.
        XCTAssertEqual(BodyHomeCardGridPacking.rows(slotCounts: [0, -1, 1]), [[0, 1], [2]])
    }

    /// The grid renders `visibleOrder`; the row model is still what the packing rule is
    /// specified against. They must describe the same cards in the same order.
    func testVisibleOrderMatchesTheRowModelFlattened() {
        let order: [BodyHomeCardKind] = [.sleep, .activityRings, .basics]
        let selection = BodySummaryCardSelection(selectedCards: [.sleep, .activityRings, .basics, .steps])

        XCTAssertEqual(
            BodyHomeCardKind.visibleOrder(from: order, visibleIn: selection),
            BodyHomeCardKind.layoutRows(from: order, visibleIn: selection).flatMap(\.cards)
        )
    }

    // MARK: - Geometry

    func testGridLaysOutTwoColumnsWithFourteenPointGutters() throws {
        let harness = try makeHarness(probes: [
            Probe(id: "a", slots: 1, height: 132),
            Probe(id: "b", slots: 1, height: 160),
            Probe(id: "c", slots: 2, height: 200),
            Probe(id: "d", slots: 1, height: 132)
        ])
        defer { harness.tearDown() }

        let a = try XCTUnwrap(harness.recorder.frames["a"])
        let b = try XCTUnwrap(harness.recorder.frames["b"])
        let c = try XCTUnwrap(harness.recorder.frames["c"])
        let d = try XCTUnwrap(harness.recorder.frames["d"])

        XCTAssertEqual(a.minX, 0, accuracy: 0.5)
        XCTAssertEqual(a.width, Self.columnWidth, accuracy: 0.5)
        XCTAssertEqual(b.minX, Self.columnWidth + Self.spacing, accuracy: 0.5)
        XCTAssertEqual(b.width, Self.columnWidth, accuracy: 0.5)

        // A two-slot card owns its row at the full grid width.
        XCTAssertEqual(c.minX, 0, accuracy: 0.5)
        XCTAssertEqual(c.width, Self.gridWidth, accuracy: 0.5)
        XCTAssertEqual(c.minY, 160 + Self.spacing, accuracy: 0.5)

        XCTAssertEqual(d.minY, 160 + Self.spacing + 200 + Self.spacing, accuracy: 0.5)
        XCTAssertEqual(d.width, Self.columnWidth, accuracy: 0.5)
    }

    /// The `HStack` this layout replaced used the default `.center` alignment, so a short
    /// card sat centered against a taller neighbour rather than pinned to the top.
    func testShortCardIsCenteredAgainstATallerNeighbour() throws {
        let harness = try makeHarness(probes: [
            Probe(id: "short", slots: 1, height: 132),
            Probe(id: "tall", slots: 1, height: 180)
        ])
        defer { harness.tearDown() }

        let short = try XCTUnwrap(harness.recorder.frames["short"])
        let tall = try XCTUnwrap(harness.recorder.frames["tall"])

        XCTAssertEqual(tall.minY, 0, accuracy: 0.5)
        XCTAssertEqual(short.minY, (180 - 132) / 2, accuracy: 0.5)
    }

    /// The regular size class puts the grid in an `HStack` beside the trends column, both
    /// `maxWidth: .infinity`. That split only lands if the layout answers SwiftUI's
    /// flexibility probes sanely instead of reporting a fixed or ideal-only width.
    func testGridSplitsAnHStackEvenlyWithAFlexibleSibling() throws {
        let containerWidth: CGFloat = 744
        let recorder = FrameRecorder()
        let order = ProbeOrder(probes: [
            Probe(id: "a", slots: 1, height: 132),
            Probe(id: "b", slots: 1, height: 132)
        ])
        let root = HStack(alignment: .top, spacing: Self.spacing) {
            ProbeGrid(order: order, recorder: recorder)
                .frame(maxWidth: .infinity)

            Color.clear
                .frame(height: 132)
                .frame(maxWidth: .infinity)
        }
        .frame(width: containerWidth)

        let harness = Harness(window: try hostedWindow(root), recorder: recorder, order: order)
        defer { harness.tearDown() }
        harness.settle()

        let expectedGridWidth = (containerWidth - Self.spacing) / 2
        let expectedColumn = (expectedGridWidth - Self.spacing) / 2
        let a = try XCTUnwrap(recorder.frames["a"])
        let b = try XCTUnwrap(recorder.frames["b"])

        XCTAssertEqual(a.width, expectedColumn, accuracy: 1)
        XCTAssertEqual(b.minX + b.width, expectedGridWidth, accuracy: 1)
    }

    // MARK: - Identity

    /// The crash this layout was introduced for: the reorder that runs while a drag is in
    /// flight used to change the enclosing row's identity, so SwiftUI destroyed the card
    /// being dragged and UIKit's cancelled set-down animation read a freed attribute. A
    /// second `onAppear` for a card that only moved means that regression is back.
    func testReorderingMovesCardsInsteadOfRebuildingThem() throws {
        let probes = [
            Probe(id: "a", slots: 1, height: 132),
            Probe(id: "b", slots: 1, height: 132),
            Probe(id: "rings", slots: 2, height: 200),
            Probe(id: "d", slots: 1, height: 132)
        ]
        let harness = try makeHarness(probes: probes)
        defer { harness.tearDown() }

        XCTAssertEqual(harness.recorder.appearances, ["a": 1, "b": 1, "rings": 1, "d": 1])

        // Move the last card to the front — the same shape as dragging a card upward.
        harness.order.probes = [probes[3], probes[0], probes[1], probes[2]]
        harness.settle()

        XCTAssertEqual(
            harness.recorder.appearances,
            ["a": 1, "b": 1, "rings": 1, "d": 1],
            "A reorder must move card views, not rebuild them"
        )
        XCTAssertEqual(try XCTUnwrap(harness.recorder.frames["d"]).minY, 0, accuracy: 0.5)
    }

    // MARK: - Harness

    private struct Probe: Identifiable, Equatable {
        let id: String
        let slots: Int
        let height: CGFloat
    }

    @MainActor
    private final class FrameRecorder {
        var frames: [String: CGRect] = [:]
        var appearances: [String: Int] = [:]
    }

    @MainActor
    private final class ProbeOrder: ObservableObject {
        @Published var probes: [Probe]

        init(probes: [Probe]) {
            self.probes = probes
        }
    }

    private struct ProbeGrid: View {
        @ObservedObject var order: ProbeOrder
        let recorder: FrameRecorder

        var body: some View {
            BodyHomeCardGridLayout(spacing: BodyHomeCardGridLayoutTests.spacing) {
                ForEach(order.probes) { probe in
                    Color.clear
                        .frame(height: probe.height)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named("grid"))
                        } action: { frame in
                            recorder.frames[probe.id] = frame
                        }
                        .onAppear { recorder.appearances[probe.id, default: 0] += 1 }
                        .bodyHomeCardSlots(probe.slots)
                }
            }
            .coordinateSpace(.named("grid"))
        }
    }

    private struct Harness {
        let window: UIWindow
        let recorder: FrameRecorder
        let order: ProbeOrder

        func settle() {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            window.layoutIfNeeded()
        }

        func tearDown() {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func makeHarness(probes: [Probe]) throws -> Harness {
        let recorder = FrameRecorder()
        let order = ProbeOrder(probes: probes)
        let root = VStack(spacing: 0) {
            ProbeGrid(order: order, recorder: recorder)
                .frame(width: Self.gridWidth)

            Spacer(minLength: 0)
        }

        let harness = Harness(window: try hostedWindow(root), recorder: recorder, order: order)
        harness.settle()
        return harness
    }

    private func hostedWindow<Content: View>(_ root: Content) throws -> UIWindow {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "BodyTests is app-hosted, so a UIWindowScene must exist"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 900)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        return window
    }
}
