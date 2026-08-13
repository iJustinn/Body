//
//  VitalsPreviewDotLayoutTests.swift
//  BodyTests
//
//  Covers the Vitals card's dots-preview geometry: the high / typical / low
//  regions share the preview's height by which of them actually hold rings —
//  an even three-way split, an even split between two with the empty region
//  held at its minimum, or one region at its maximum with the other two at
//  minimum — while the three heights always sum to the drawable height.
//

import SwiftUI
import XCTest
@testable import Body

final class VitalsPreviewDotLayoutTests: XCTestCase {
    private typealias Layout = BodyHealthMetricCardTrendPreview.DotPreviewLayout

    /// The two sizes the card actually renders at: compact phones and the
    /// roomier iPad-class preview.
    private static let sizes: [CGSize] = [
        CGSize(width: 42, height: 42),
        CGSize(width: 50, height: 50)
    ]

    private let accuracy: CGFloat = 0.001

    private func layout(_ size: CGSize, _ occupied: Set<SleepVitalRegion>) -> Layout {
        Layout(size: size, occupied: occupied)
    }

    private func heights(_ layout: Layout) -> [CGFloat] {
        [layout.height(for: .high), layout.height(for: .typical), layout.height(for: .low)]
    }

    /// Every case has to fill the preview's fixed frame exactly — the regions
    /// morph between proportions, they never leave a gap or overflow.
    private func assertHeightsFillTheFrame(
        _ layout: Layout,
        in size: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let total = heights(layout).reduce(0, +) + 2 * layout.gap
        XCTAssertEqual(total, size.height, accuracy: accuracy, file: file, line: line)
    }

    func testRingsInAllThreeRegionsSplitTheHeightEvenly() {
        for size in Self.sizes {
            let layout = layout(size, [.high, .typical, .low])
            let available = size.height - 2 * layout.gap

            for height in heights(layout) {
                XCTAssertEqual(height, available / 3, accuracy: accuracy)
            }

            assertHeightsFillTheFrame(layout, in: size)
        }
    }

    func testRingsInTwoRegionsShareTheHeightWhileTheEmptyOneStaysAtMinimum() {
        let pairings: [Set<SleepVitalRegion>] = [
            [.high, .typical],
            [.typical, .low],
            [.high, .low]
        ]

        for size in Self.sizes {
            for occupied in pairings {
                let layout = layout(size, occupied)
                let available = size.height - 2 * layout.gap
                let expectedShared = (available - layout.minRegionHeight) / 2

                for region in [SleepVitalRegion.high, .typical, .low] {
                    let expected = occupied.contains(region) ? expectedShared : layout.minRegionHeight
                    XCTAssertEqual(layout.height(for: region), expected, accuracy: accuracy)
                }

                // The two occupied regions must be the taller ones, or the split
                // would be reading occupancy backwards.
                XCTAssertGreaterThan(expectedShared, layout.minRegionHeight)
                assertHeightsFillTheFrame(layout, in: size)
            }
        }
    }

    func testRingsInOneRegionGiveItTheMaximumHeight() {
        for size in Self.sizes {
            for occupiedRegion in [SleepVitalRegion.high, .typical, .low] {
                let layout = layout(size, [occupiedRegion])

                for region in [SleepVitalRegion.high, .typical, .low] {
                    let expected = region == occupiedRegion ? layout.maxRegionHeight : layout.minRegionHeight
                    XCTAssertEqual(layout.height(for: region), expected, accuracy: accuracy)
                }

                assertHeightsFillTheFrame(layout, in: size)
            }
        }
    }

    /// The single-region case has to reproduce the old fixed layout exactly:
    /// 0.17h for the two thin regions and the remainder for the tall one.
    func testSingleOccupiedCaseMatchesThePreviousFixedGeometry() {
        for size in Self.sizes {
            let layout = layout(size, [.typical])
            let legacyBarHeight = max(size.height * 0.17, 4)
            let legacyGap = max(size.height * 0.045, 1.5)
            let legacyBandHeight = max(size.height - 2 * (legacyBarHeight + legacyGap), 8)

            XCTAssertEqual(layout.gap, legacyGap, accuracy: accuracy)
            XCTAssertEqual(layout.height(for: .high), legacyBarHeight, accuracy: accuracy)
            XCTAssertEqual(layout.height(for: .low), legacyBarHeight, accuracy: accuracy)
            XCTAssertEqual(layout.height(for: .typical), legacyBandHeight, accuracy: accuracy)
        }
    }

    func testPendingNightSplitsTheHeightEvenly() {
        for size in Self.sizes {
            let pending = layout(size, [])
            let assessed = layout(size, [.high, .typical, .low])

            XCTAssertEqual(heights(pending), heights(assessed))
            assertHeightsFillTheFrame(pending, in: size)
        }
    }

    /// Rings glide while the regions morph — they must not resize on the way,
    /// and they must still be what the old fixed layout drew.
    func testRingSizeIsConstantAcrossOccupancyCases() {
        let cases: [Set<SleepVitalRegion>] = [
            [],
            [.high],
            [.typical],
            [.low],
            [.high, .typical],
            [.typical, .low],
            [.high, .low],
            [.high, .typical, .low]
        ]

        for size in Self.sizes {
            let legacyBandHeight = max(size.height - 2 * (max(size.height * 0.17, 4) + max(size.height * 0.045, 1.5)), 8)
            let legacyDiameter = max(min(legacyBandHeight * 0.32, size.width * 0.16), 5)

            for occupied in cases {
                let layout = layout(size, occupied)
                XCTAssertEqual(layout.dotDiameter, legacyDiameter, accuracy: accuracy)
                XCTAssertEqual(layout.dotStroke, max(legacyDiameter * 0.26, 2), accuracy: accuracy)
                // A ring has to fit the thinnest region it can be placed in.
                XCTAssertLessThanOrEqual(layout.dotDiameter, layout.minRegionHeight)
            }
        }
    }

    /// Clamping the minimum region to a third of the drawable height is what
    /// keeps the sum exact; without it the floors overflow a small frame.
    func testHeightsStayInsideDegenerateFrames() {
        let cases: [Set<SleepVitalRegion>] = [
            [],
            [.high],
            [.high, .low],
            [.high, .typical, .low]
        ]

        for side in stride(from: CGFloat(10), through: 60, by: 2) {
            let size = CGSize(width: side, height: side)

            for occupied in cases {
                let layout = layout(size, occupied)
                assertHeightsFillTheFrame(layout, in: size)

                for height in heights(layout) {
                    XCTAssertGreaterThan(height, 0)
                }

                XCTAssertLessThanOrEqual(layout.dotDiameter, layout.minRegionHeight)
            }
        }
    }

    func testRegionSlotBoundariesMatchTheTypicalBandsMiddleThird() {
        XCTAssertEqual(Layout.regionSlot(for: 1.0), .high)
        XCTAssertEqual(Layout.regionSlot(for: 0.7), .high)
        XCTAssertEqual(Layout.regionSlot(for: 2.0 / 3.0), .typical)
        XCTAssertEqual(Layout.regionSlot(for: 0.5), .typical)
        XCTAssertEqual(Layout.regionSlot(for: 1.0 / 3.0), .typical)
        XCTAssertEqual(Layout.regionSlot(for: 0.2), .low)
        XCTAssertEqual(Layout.regionSlot(for: 0.0), .low)
    }

    /// The slot a ring is drawn in must agree with the region the vitals model
    /// assigned it, or the layout would grow a region holding no rings.
    func testRegionSlotAgreesWithTheReferenceRangeForRealValues() {
        let range = SleepVitalReferenceRange(typicalLowerBound: 52, typicalUpperBound: 61)

        for value in stride(from: 30.0, through: 85.0, by: 0.25) {
            XCTAssertEqual(
                Layout.regionSlot(for: range.markerPosition(for: value)),
                range.region(for: value),
                "value \(value) landed in the wrong region slot"
            )
        }
    }

    func testDotYLandsInsideTheRegionThePositionClassifiesTo() {
        let positions: [Double] = [0, 0.1, 0.32, 1.0 / 3.0, 0.4, 0.5, 0.6, 2.0 / 3.0, 0.75, 1]
        let cases: [Set<SleepVitalRegion>] = [
            [],
            [.high],
            [.typical],
            [.high, .low],
            [.typical, .low],
            [.high, .typical, .low]
        ]

        for size in Self.sizes {
            for occupied in cases {
                let layout = layout(size, occupied)

                for position in positions {
                    let region = Layout.regionSlot(for: position)
                    let top = layout.topY(for: region)
                    let bottom = top + layout.height(for: region)
                    let y = layout.dotY(for: position)

                    XCTAssertGreaterThanOrEqual(y, top - accuracy)
                    XCTAssertLessThanOrEqual(y, bottom + accuracy)
                }
            }
        }
    }

    /// Regions stack top to bottom with the fixed gap between them, so the low
    /// region's bottom edge is the preview's bottom edge.
    func testRegionsStackWithoutOverlap() {
        for size in Self.sizes {
            let layout = layout(size, [.high, .typical])

            XCTAssertEqual(layout.topY(for: .high), 0, accuracy: accuracy)
            XCTAssertEqual(
                layout.topY(for: .typical),
                layout.height(for: .high) + layout.gap,
                accuracy: accuracy
            )
            XCTAssertEqual(
                layout.topY(for: .low),
                layout.height(for: .high) + layout.height(for: .typical) + 2 * layout.gap,
                accuracy: accuracy
            )
            XCTAssertEqual(
                layout.topY(for: .low) + layout.height(for: .low),
                size.height,
                accuracy: accuracy
            )
        }
    }
}
