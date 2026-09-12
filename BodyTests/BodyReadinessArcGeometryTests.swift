//
//  BodyReadinessArcGeometryTests.swift
//  BodyTests
//

import SwiftUI
import XCTest
@testable import Body

/// The readiness hero's bars are pure geometry, so the things a screenshot would catch are
/// all assertable here: the five bands always fit the width they are given, they keep their
/// score proportions where they are not pinned to the minimum length, they stay physically
/// apart at every frame of the scroll morph rather than only at the two ends, and the dot
/// stays on the band its score belongs to.
final class BodyReadinessArcGeometryTests: XCTestCase {
    private typealias Geometry = BodyReadinessArcGeometry

    private let widths: [CGFloat] = [320, 343, 375, 393, 430, 700]

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func nearestSampleDistance(from point: CGPoint, to segment: [CGPoint]) -> CGFloat {
        segment.map { distance($0, point) }.min() ?? .greatestFiniteMagnitude
    }

    // MARK: - Layout shape

    func testBothLayoutsHaveFiveFullySampledSegmentsInAscendingOrder() {
        for width in widths {
            for (name, layout) in [
                ("arc", Geometry.arcLayout(width: width)),
                ("flat", Geometry.flatLayout(width: width))
            ] {
                XCTAssertEqual(layout.segments.count, 5, "\(name) at \(width)")
                XCTAssertEqual(layout.segmentLengths.count, 5, "\(name) at \(width)")
                XCTAssertEqual(layout.segmentSpans.count, 5, "\(name) at \(width)")

                for segment in layout.segments {
                    XCTAssertEqual(segment.count, Geometry.sampleCount, "\(name) at \(width)")
                    for point in segment {
                        XCTAssertTrue(point.x.isFinite && point.y.isFinite, "\(name) at \(width)")
                    }
                }

                for span in layout.segmentSpans {
                    XCTAssertTrue(span.lowerBound.isFinite && span.upperBound.isFinite)
                    XCTAssertGreaterThan(span.upperBound, span.lowerBound, "\(name) at \(width)")
                }

                for index in 0..<4 {
                    XCTAssertLessThan(
                        layout.segmentSpans[index].upperBound,
                        layout.segmentSpans[index + 1].lowerBound,
                        "\(name) spans overlap at \(width)"
                    )
                }

                for index in 0..<5 {
                    let span = layout.segmentSpans[index]
                    XCTAssertEqual(
                        span.upperBound - span.lowerBound,
                        layout.segmentLengths[index],
                        accuracy: 1e-6,
                        "\(name) at \(width)"
                    )
                }

                XCTAssertGreaterThanOrEqual(layout.segmentSpans[0].lowerBound, 0)
                XCTAssertLessThanOrEqual(layout.segmentSpans[4].upperBound, layout.trackLength + 1e-6)
            }
        }
    }

    func testEveryBandIsAtLeastTheMinimumLengthUnlessTheTrackCannotHoldFiveOfThem() {
        for width in widths {
            for (name, layout) in [
                ("arc", Geometry.arcLayout(width: width)),
                ("flat", Geometry.flatLayout(width: width))
            ] {
                let gap = layout.barWidth + Geometry.visualGap + Geometry.morphMargin
                let minimum = Geometry.minimumSegmentLength(barWidth: layout.barWidth)
                let shrinkToFit = minimum * 5 + gap * 4 > layout.trackLength + 1e-9

                if shrinkToFit {
                    for length in layout.segmentLengths {
                        XCTAssertEqual(
                            length,
                            layout.segmentLengths[0],
                            accuracy: 1e-6,
                            "\(name) at \(width) should share equally when it cannot fit"
                        )
                    }
                } else {
                    for length in layout.segmentLengths {
                        XCTAssertGreaterThanOrEqual(
                            length,
                            minimum - 1e-6,
                            "\(name) at \(width) drew a band under the minimum"
                        )
                    }
                }

                let used = layout.segmentLengths.reduce(0, +) + gap * 4
                XCTAssertEqual(used, layout.trackLength, accuracy: 1e-6, "\(name) at \(width)")
            }
        }
    }

    func testBandsAboveTheMinimumKeepTheirScoreProportions() {
        let shares = Geometry.bandScoreRanges.map { CGFloat($0.count) / 101 }

        for width in widths {
            for (name, layout) in [
                ("arc", Geometry.arcLayout(width: width)),
                ("flat", Geometry.flatLayout(width: width))
            ] {
                let minimum = Geometry.minimumSegmentLength(barWidth: layout.barWidth)
                let ratios = (0..<5)
                    .filter { layout.segmentLengths[$0] > minimum + 1e-6 }
                    .map { layout.segmentLengths[$0] / shares[$0] }

                guard let first = ratios.first else { continue }
                for ratio in ratios {
                    XCTAssertEqual(
                        ratio / first,
                        1,
                        accuracy: 1e-6,
                        "\(name) at \(width) lost the score proportions: \(ratios)"
                    )
                }
            }
        }
    }

    func testFlatLayoutKeepsItsRoundCapsInsideTheWidth() {
        for width in widths {
            let layout = Geometry.flatLayout(width: width)
            guard let leading = layout.segments.first?.first,
                  let trailing = layout.segments.last?.last else {
                return XCTFail("missing flat endpoints at \(width)")
            }
            XCTAssertGreaterThanOrEqual(leading.x - layout.barWidth / 2, 0, "left cap at \(width)")
            XCTAssertLessThanOrEqual(trailing.x + layout.barWidth / 2, width, "right cap at \(width)")
        }
    }

    // MARK: - Morph

    func testTheTrackStaysInsideTheWidthAtEveryStageOfTheMorph() {
        // Phone widths are the ones that bind: there the flat bar is longer than the
        // arc, so a naive length lerp let the half-flattened chord poke past both
        // edges. The track's end to end width must never exceed the flat bar's, and
        // the track length moves one way only: shrinking on phones (holding its arc
        // length until that width is reached), growing on wide layouts.
        for width in widths {
            let flat = Geometry.flatLayout(width: width)
            let arc = Geometry.arcLayout(width: width)
            let shrinks = arc.trackLength > flat.trackLength
            var previousTrackLength = arc.trackLength
            for step in 0...120 {
                let progress = Double(step) / 120
                let layout = Geometry.layout(progress: progress, width: width)
                let points = layout.segments.flatMap { $0 }
                let minX = points.map(\.x).min() ?? 0
                let maxX = points.map(\.x).max() ?? width
                XCTAssertGreaterThanOrEqual(minX, flat.segments.first!.first!.x - 0.5, "left end at \(width) progress \(progress)")
                XCTAssertLessThanOrEqual(maxX, flat.segments.last!.last!.x + 0.5, "right end at \(width) progress \(progress)")
                if shrinks {
                    XCTAssertLessThanOrEqual(layout.trackLength, previousTrackLength + 0.001, "track never grows at \(width) progress \(progress)")
                } else {
                    XCTAssertGreaterThanOrEqual(layout.trackLength, previousTrackLength - 0.001, "track never shrinks at \(width) progress \(progress)")
                }
                previousTrackLength = layout.trackLength
            }
        }
    }

    func testAdjacentBandsStayPhysicallyApartThroughTheWholeMorph() {
        for width in widths {
            for step in 0...60 {
                let progress = Double(step) / 60
                let segments = Geometry.segmentPoints(progress: progress, width: width)
                let barWidth = Geometry.barWidth(progress: progress)
                let required = barWidth + Geometry.visualGap - 1

                for index in 0..<4 {
                    guard let end = segments[index].last,
                          let start = segments[index + 1].first else {
                        return XCTFail("missing samples at \(width)")
                    }
                    XCTAssertGreaterThanOrEqual(
                        distance(end, start),
                        required,
                        "bands \(index) and \(index + 1) closed up at width \(width), progress \(progress)"
                    )
                }
            }
        }
    }

    func testEndpointStatesAreTheFlatLineAndTheDesignedArc() {
        for width in widths {
            for segment in Geometry.segmentPoints(progress: 1, width: width) {
                for point in segment {
                    XCTAssertEqual(point.y, Geometry.flatY, accuracy: 1e-6, "flat state at \(width)")
                }
            }

            let radius = Geometry.arcRadius(width: width)
            let center = CGPoint(x: width / 2, y: Geometry.arcCenterY(width: width))
            for segment in Geometry.segmentPoints(progress: 0, width: width) {
                for point in segment {
                    XCTAssertEqual(distance(point, center), radius, accuracy: 1e-6, "arc state at \(width)")
                }
            }
        }
    }

    // MARK: - Dot

    func testDotRidesItsOwnBandAtEveryStageOfTheMorph() {
        let width: CGFloat = 393
        let scores = [0, 29, 30, 64, 65, 79, 80, 94, 95, 100]

        for score in scores {
            for progress in [0.0, 0.5, 1.0] {
                let center = Geometry.dotCenter(score: Double(score), progress: progress, width: width)
                let segments = Geometry.segmentPoints(progress: progress, width: width)
                let index = Geometry.segmentIndex(forScore: score)

                XCTAssertLessThanOrEqual(
                    nearestSampleDistance(from: center, to: segments[index]),
                    6,
                    "score \(score) at progress \(progress) left its band"
                )

                for other in 0..<segments.count where other != index {
                    XCTAssertGreaterThan(
                        nearestSampleDistance(from: center, to: segments[other]),
                        Geometry.barWidth(progress: progress) / 2,
                        "score \(score) at progress \(progress) touched band \(other)"
                    )
                }
            }
        }
    }

    func testTheEndsOfTheScaleStayInsideTheTrack() {
        let width: CGFloat = 393
        for layout in [Geometry.arcLayout(width: width), Geometry.flatLayout(width: width)] {
            for score in [0.0, 100.0] {
                let distanceAlongTrack = layout.dotDistance(score: score)
                // The pill may run into the bar's round cap but not past it.
                let capReach = layout.barWidth / 2
                XCTAssertGreaterThanOrEqual(distanceAlongTrack - Geometry.dotLength / 2, -capReach + 1)
                XCTAssertLessThanOrEqual(
                    distanceAlongTrack + Geometry.dotLength / 2,
                    layout.trackLength + capReach - 1
                )
            }
        }
    }

    // MARK: - Score and text mapping

    func testTextFadesOutOverTheNumberFadeDistance() {
        for width in widths {
            let fadeEnd = Double(Geometry.numberFadeDistance / Geometry.morphDistance(width: width))
            XCTAssertEqual(Geometry.textOpacity(progress: 0, width: width), 1, accuracy: 1e-9)
            XCTAssertEqual(Geometry.textOpacity(progress: fadeEnd, width: width), 0, accuracy: 1e-9)
            XCTAssertEqual(Geometry.textOpacity(progress: 1, width: width), 0, accuracy: 1e-9)
            XCTAssertGreaterThan(
                Geometry.textOpacity(progress: 0.2, width: width),
                Geometry.textOpacity(progress: 0.3, width: width)
            )
        }
    }

    func testTextStopsBeingVisibleOnceItIsUnderTheThreshold() {
        // The number fades over `numberFadeDistance` scroll points of a `morphDistance`
        // morph, so it is gone well before the bar is flat and drops under the visibility
        // threshold a little before that.
        let width: CGFloat = 393
        let fadeEnd = Double(Geometry.numberFadeDistance / Geometry.morphDistance(width: width))
        let thresholdProgress = fadeEnd * (1 - Geometry.textVisibleThreshold)
        XCTAssertEqual(Geometry.textOpacity(progress: 0, width: width), 1)
        XCTAssertEqual(Geometry.textOpacity(progress: fadeEnd, width: width), 0, accuracy: 1e-9)
        XCTAssertTrue(Geometry.isTextVisible(progress: 0, width: width))
        XCTAssertTrue(Geometry.isTextVisible(progress: thresholdProgress - 0.01, width: width))
        XCTAssertFalse(Geometry.isTextVisible(progress: thresholdProgress + 0.01, width: width))
        XCTAssertFalse(Geometry.isTextVisible(progress: fadeEnd, width: width))
        XCTAssertFalse(Geometry.isTextVisible(progress: 1, width: width))
    }

    func testSegmentIndexFollowsTheBandBoundaries() {
        XCTAssertEqual(Geometry.segmentIndex(forScore: 29), 0)
        XCTAssertEqual(Geometry.segmentIndex(forScore: 30), 1)
        XCTAssertEqual(Geometry.segmentIndex(forScore: 64), 1)
        XCTAssertEqual(Geometry.segmentIndex(forScore: 65), 2)
        XCTAssertEqual(Geometry.segmentIndex(forScore: 79), 2)
        XCTAssertEqual(Geometry.segmentIndex(forScore: 80), 3)
        XCTAssertEqual(Geometry.segmentIndex(forScore: 94), 3)
        XCTAssertEqual(Geometry.segmentIndex(forScore: 95), 4)
        XCTAssertEqual(Geometry.segmentIndex(forScore: 100), 4)
    }

    func testPillMoveKeepsEveryFrameInTheStartOrTargetBand() {
        // The spring overshoots by a few percent of the distance travelled.
        XCTAssertGreaterThan(Geometry.pillSpringOvershootRatio, 0.03)
        XCTAssertLessThan(Geometry.pillSpringOvershootRatio, 0.1)

        XCTAssertEqual(Geometry.pillMove(from: 0, to: 72), .bounce)
        XCTAssertEqual(Geometry.pillMove(from: 40, to: 50), .bounce)

        // Landing on the edge it enters through: rush past, then return inside the band.
        guard case .overshootThenReturn(let up) = Geometry.pillMove(from: 0, to: 65) else {
            return XCTFail("65 from below is the near edge of Moderate")
        }
        XCTAssertGreaterThan(up, 65)
        XCTAssertLessThan(up, 80)
        guard case .overshootThenReturn(let down) = Geometry.pillMove(from: 100, to: 64) else {
            return XCTFail("64 from above is the near edge of Low")
        }
        XCTAssertLessThan(down, 64)
        XCTAssertGreaterThanOrEqual(down, 30)
        XCTAssertLessThanOrEqual(abs(up - 65), Geometry.pillMaxDeliberateOvershoot)

        // Landing on the far edge: no overshoot at all.
        XCTAssertEqual(Geometry.pillMove(from: 0, to: 64), .settle)
        XCTAssertEqual(Geometry.pillMove(from: 100, to: 65), .settle)
        XCTAssertEqual(Geometry.pillMove(from: 0, to: 100), .settle)
        XCTAssertEqual(Geometry.pillMove(from: 100, to: 0), .settle)
    }

    func testPullStretchGrowsWithThePullAndStaysUnderItsCap() {
        XCTAssertEqual(Geometry.pullStretch(pull: 0), 0)
        XCTAssertEqual(Geometry.pullStretch(pull: -20), 0, "Scrolling up never stretches the ring")
        let small = Geometry.pullStretch(pull: 40)
        let large = Geometry.pullStretch(pull: 160)
        XCTAssertGreaterThan(small, 0)
        XCTAssertGreaterThan(large, small)
        XCTAssertLessThanOrEqual(Geometry.pullStretch(pull: 5000), Geometry.maxPullStretch)
    }

    func testAStretchedRingPullsItsBandsApartWithoutLiftingItsTop() {
        for width in widths {
            let rest = Geometry.layout(progress: 0, width: width)
            let stretched = Geometry.layout(progress: 0, width: width, stretch: 1)
            XCTAssertEqual(stretched.topY, rest.topY, accuracy: 0.001, "The top of the arc stays put")
            XCTAssertGreaterThan(stretched.trackLength, rest.trackLength)
            XCTAssertEqual(stretched.curveRadius!, rest.curveRadius!, accuracy: 0.001, "The ring keeps its radius")
            for (restLength, stretchedLength) in zip(rest.segmentLengths, stretched.segmentLengths) {
                XCTAssertEqual(stretchedLength, restLength, accuracy: 0.001, "Bands keep their resting length")
            }
            let restEnd = rest.point(atDistance: rest.trackLength)
            let stretchedEnd = stretched.point(atDistance: stretched.trackLength)
            XCTAssertGreaterThan(stretchedEnd.y, restEnd.y, "The ends drop further down the sides")
            for index in 0..<(rest.segments.count - 1) {
                let restGap = distance(rest.segments[index].last!, rest.segments[index + 1].first!)
                let stretchedGap = distance(stretched.segments[index].last!, stretched.segments[index + 1].first!)
                XCTAssertGreaterThan(stretchedGap, restGap * 1.5, "Band \(index) pulls clear of its neighbour at \(width)")
            }
            XCTAssertEqual(Geometry.layout(progress: 0, width: width, stretch: 0).trackLength, rest.trackLength, accuracy: 0.001)
        }
    }
}
