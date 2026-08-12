//
//  ChartFloatingCalloutLayerTests.swift
//  BodyTests
//
//  Covers `BodyChartFloatingCalloutLayer.calloutFrame`, the placement math for
//  the scrub callout floated on the topmost layer: centered on the selection
//  rule, bottom edge 8pt above the plot top, clamped to the container's edges.

import XCTest
@testable import Body

final class ChartFloatingCalloutLayerTests: XCTestCase {
    private let container = CGSize(width: 400, height: 800)
    private let size = CGSize(width: 120, height: 60)

    func testCentersOnAnchorWithBottomEdgeAbovePlotTop() {
        let frame = BodyChartFloatingCalloutLayer.calloutFrame(
            anchor: CGPoint(x: 200, y: 300),
            size: size,
            in: container
        )

        XCTAssertEqual(frame.midX, 200)
        // 8pt spacing above the anchor (the plot's top edge), matching the
        // in-chart annotation's `spacing: 8`.
        XCTAssertEqual(frame.maxY, 292)
        XCTAssertEqual(frame.size, size)
    }

    func testClampsToLeadingEdge() {
        let frame = BodyChartFloatingCalloutLayer.calloutFrame(
            anchor: CGPoint(x: 10, y: 300),
            size: size,
            in: container
        )

        XCTAssertEqual(frame.minX, 8)
    }

    func testClampsToTrailingEdge() {
        let frame = BodyChartFloatingCalloutLayer.calloutFrame(
            anchor: CGPoint(x: 395, y: 300),
            size: size,
            in: container
        )

        XCTAssertEqual(frame.maxX, container.width - 8)
    }

    func testClampsToContainerTopInsteadOfRunningUnderTheStatusBar() {
        let frame = BodyChartFloatingCalloutLayer.calloutFrame(
            anchor: CGPoint(x: 200, y: 40),
            size: size,
            in: container
        )

        XCTAssertEqual(frame.minY, 0)
    }

    func testCalloutWiderThanContainerPinsToLeadingMargin() {
        let frame = BodyChartFloatingCalloutLayer.calloutFrame(
            anchor: CGPoint(x: 200, y: 300),
            size: CGSize(width: 500, height: 60),
            in: container
        )

        XCTAssertEqual(frame.minX, 8)
    }

    // MARK: - Flipping placement (the calendar's hold-to-peek callout)

    func testFlippingPlacementSitsAboveTheAnchorWhenItFits() {
        let frame = BodyChartFloatingCalloutLayer.flippingCalloutFrame(
            anchor: CGPoint(x: 200, y: 300),
            anchorBottom: 348,
            size: size,
            in: container
        )

        XCTAssertEqual(frame.midX, 200)
        XCTAssertEqual(frame.maxY, 292)
        XCTAssertEqual(frame.size, size)
    }

    func testFlippingPlacementFlipsBelowTheAnchorWhenThereIsNoRoomAbove() {
        let frame = BodyChartFloatingCalloutLayer.flippingCalloutFrame(
            anchor: CGPoint(x: 200, y: 40),
            anchorBottom: 88,
            size: size,
            in: container
        )

        // 8pt below the cell's bottom edge rather than clamped to the container
        // top, where it would detach from the cell and cover the rows above.
        XCTAssertEqual(frame.minY, 96)
        XCTAssertEqual(frame.midX, 200)
    }

    func testFlippedCalloutStaysInsideTheContainerBottom() {
        let frame = BodyChartFloatingCalloutLayer.flippingCalloutFrame(
            anchor: CGPoint(x: 200, y: 20),
            anchorBottom: container.height - 10,
            size: size,
            in: container
        )

        XCTAssertEqual(frame.maxY, container.height - 8)
    }

    func testFlippingPlacementClampsToHorizontalEdges() {
        let leading = BodyChartFloatingCalloutLayer.flippingCalloutFrame(
            anchor: CGPoint(x: 10, y: 300),
            anchorBottom: 348,
            size: size,
            in: container
        )
        let trailing = BodyChartFloatingCalloutLayer.flippingCalloutFrame(
            anchor: CGPoint(x: 395, y: 300),
            anchorBottom: 348,
            size: size,
            in: container
        )

        XCTAssertEqual(leading.minX, 8)
        XCTAssertEqual(trailing.maxX, container.width - 8)
    }
}
