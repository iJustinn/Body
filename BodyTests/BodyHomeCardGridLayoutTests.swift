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

    // MARK: - Scroll targeting

    /// The readiness hero's warning badges scroll the page to the card they mirror, by
    /// `BodyHomeCardKind.id`. Two separate things have to hold for that, and each was a
    /// live theory for why it did not: the grid cards, which are subviews of a custom
    /// `Layout` and carry no explicit `.id()`, have to register as `scrollTo` targets at
    /// all, and nothing else drawn in Home's one ScrollView may answer to the same name.
    /// This case covers the first; the next covers the second.
    ///
    /// Measured on the simulator before the fix: with the badges publishing the bare
    /// `card.rawValue` the page sat at its resting offset, while the same page with no
    /// badges scrolled 1035 pt to the card. So the ForEach id does register from inside
    /// the custom `Layout`, and the collision alone was the bug.
    func testScrollToReachesACardInsideTheCustomGridLayout() throws {
        let harness = try makeScrollHarness(badges: [])
        defer { harness.tearDown() }

        try assertScrollCenters(harness, on: Self.scrollTarget)
    }

    /// The regression guard for the id collision. Renders the real `BodyReadinessHeroLabel`
    /// rather than a stand-in row, so deleting `BodyReadinessHeroWarningBadge.scrollIDPrefix`
    /// from the shipped view turns this red instead of leaving a copy of it green here.
    func testAHeroBadgeDoesNotShadowItsCardsScrollTarget() throws {
        let badges = BodyReadinessHeroWarningBadge.badges(
            visibleCards: [Self.scrollTarget],
            lookup: [
                .oxygenSaturation: BodyHealthMetricCard.Model(
                    kind: .oxygenSaturation,
                    title: "Blood Oxygen",
                    value: "--",
                    unit: "",
                    symbolName: "lungs.fill",
                    symbolColor: .blue,
                    warningSymbolName: "exclamationmark.triangle.fill",
                    warningColor: .yellow
                )
            ]
        )
        XCTAssertEqual(badges.count, 1, "The badge under test has to actually render")

        let harness = try makeScrollHarness(badges: badges)
        defer { harness.tearDown() }

        try assertScrollCenters(harness, on: Self.scrollTarget)
    }

    // MARK: - Scroll harness

    /// Blood Oxygen is the card the bug was reported on. It sits in the middle band of
    /// `scrollCards`, which matters: `anchor: .center` cannot be satisfied for a target
    /// without half a viewport of content below it, and a bottom-clamped scroll would
    /// fail these tests for a reason unrelated to what they cover.
    private static let scrollTarget: BodyHomeCardKind = .oxygenSaturation

    private static let scrollViewport = CGSize(width: 390, height: 844)

    private static let scrollCards: [BodyHomeCardKind] = [
        .sleep, .basics, .heartRate, .heartRateVariability,
        .oxygenSaturation,
        .respiratoryRate, .steps, .activeEnergy, .restingEnergy, .restingHeartRate
    ]

    @MainActor
    private final class ScrollCommand: ObservableObject {
        @Published var target: String?
    }

    /// Home's shape in miniature: one `ScrollViewReader` over one `ScrollView`, whose
    /// `VStack` holds the hero and then the grid inside `BodyHomeCardGridLayout`.
    private struct ScrollProbePage: View {
        @ObservedObject var command: ScrollCommand
        let badges: [BodyReadinessHeroWarningBadge]
        let recorder: FrameRecorder

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 14) {
                        BodyReadinessHeroLabel(
                            readiness: .unavailable,
                            morningScore: nil,
                            warningBadges: badges
                        )

                        BodyHomeCardGridLayout(spacing: BodyHomeCardGridLayoutTests.spacing) {
                            ForEach(BodyHomeCardGridLayoutTests.scrollCards) { card in
                                Color.clear
                                    .frame(height: 240)
                                    .onGeometryChange(for: CGRect.self) { proxy in
                                        proxy.frame(in: .named("viewport"))
                                    } action: { frame in
                                        recorder.frames[card.id] = frame
                                    }
                                    .bodyHomeCardSlots(card.slotCount)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .coordinateSpace(.named("viewport"))
                // Deliberately unanimated: these assert whether `scrollTo` resolves the
                // target, not how it travels, and an animated scroll would still be in
                // flight when the run loop stops spinning.
                .onChange(of: command.target) { _, target in
                    guard let target else { return }
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }

    private struct ScrollHarness {
        let window: UIWindow
        let recorder: FrameRecorder
        let command: ScrollCommand

        func settle() {
            for _ in 0..<6 {
                window.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            window.layoutIfNeeded()
        }

        func tearDown() {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func makeScrollHarness(badges: [BodyReadinessHeroWarningBadge]) throws -> ScrollHarness {
        let recorder = FrameRecorder()
        let command = ScrollCommand()
        let root = ScrollProbePage(command: command, badges: badges, recorder: recorder)

        let harness = ScrollHarness(
            window: try hostedWindow(root, size: Self.scrollViewport),
            recorder: recorder,
            command: command
        )
        harness.settle()
        return harness
    }

    private func assertScrollCenters(
        _ harness: ScrollHarness,
        on card: BodyHomeCardKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let scrollView = try XCTUnwrap(
            Self.firstScrollView(in: harness.window),
            "No UIScrollView materialized in the hosted hierarchy",
            file: file,
            line: line
        )
        let restingOffset = scrollView.contentOffset.y

        harness.command.target = card.id
        harness.settle()

        XCTAssertGreaterThan(
            scrollView.contentOffset.y,
            restingOffset,
            "scrollTo did not move the page: the card is not resolving as a scroll target",
            file: file,
            line: line
        )
        // UIKit's scroll view spans the whole window and compensates with content insets,
        // while the SwiftUI `ScrollView` whose coordinate space these frames are measured
        // in is only the visible band between them. `anchor: .center` centers within that
        // band, so neither the window's height nor `bounds.height` is the reference.
        let inset = scrollView.adjustedContentInset
        let visibleHeight = scrollView.bounds.height - inset.top - inset.bottom
        let frame = try XCTUnwrap(harness.recorder.frames[card.id], file: file, line: line)
        XCTAssertEqual(
            frame.midY,
            visibleHeight / 2,
            accuracy: 2,
            """
            The card landed off center, so `anchor: .center` did not resolve it. \
            midY \(frame.midY), bounds \(scrollView.bounds.height), \
            inset top \(inset.top) bottom \(inset.bottom), offset \(scrollView.contentOffset.y)
            """,
            file: file,
            line: line
        )
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

    private func hostedWindow<Content: View>(
        _ root: Content,
        size: CGSize = CGSize(width: 1024, height: 900)
    ) throws -> UIWindow {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "BodyTests is app-hosted, so a UIWindowScene must exist"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        return window
    }
}
