//
//  WatchBandRingViewTests.swift
//  BodyWatchTests
//
//  Locks the shared banded complication ring (`WatchBandRingView`, drawn by
//  the Readiness and Stress bands complications): which band a score lights,
//  and that the bands share the 300 degree ring in order without overlapping.
//

import SwiftUI
import XCTest
@testable import BodyWatch

final class WatchBandRingViewTests: XCTestCase {
    func testTheActiveBandFollowsTheScore() {
        let stress = WatchStressBands.scoreRanges
        XCTAssertEqual(WatchBandRingView.segmentIndex(forScore: 0, in: stress), 0)
        XCTAssertEqual(WatchBandRingView.segmentIndex(forScore: 25, in: stress), 0)
        XCTAssertEqual(WatchBandRingView.segmentIndex(forScore: 26, in: stress), 1)
        XCTAssertEqual(WatchBandRingView.segmentIndex(forScore: 75, in: stress), 2)
        XCTAssertEqual(WatchBandRingView.segmentIndex(forScore: 76, in: stress), 3)
        XCTAssertEqual(WatchBandRingView.segmentIndex(forScore: 100, in: stress), 3)
        // Out of range scores clamp to the end bands.
        XCTAssertEqual(WatchBandRingView.segmentIndex(forScore: -4, in: stress), 0)
        XCTAssertEqual(WatchBandRingView.segmentIndex(forScore: 140, in: stress), 3)

        // Readiness lights the band the home hero does.
        let readiness = BodyReadinessArcGeometry.bandScoreRanges
        for score in [-4, 0, 29, 30, 64, 65, 79, 80, 94, 95, 100, 140] {
            XCTAssertEqual(
                WatchBandRingView.segmentIndex(forScore: score, in: readiness),
                BodyReadinessArcGeometry.segmentIndex(forScore: score),
                "\(score)"
            )
        }
    }

    func testTheBandsShareTheRingInOrder() {
        // A circular slot's ring: 45 pt side, the stroke `WatchBandRingView` draws.
        let lineWidth: CGFloat = 45 * 0.16
        let radius = (45 - lineWidth) / 2
        let start = WatchBandRingView.startAngle.radians
        let end = start + WatchBandRingView.sweep.radians
        for ranges in [WatchStressBands.scoreRanges, BodyReadinessArcGeometry.bandScoreRanges] {
            let bands = WatchBandRingView.bandAngles(ranges, radius: radius, lineWidth: lineWidth)
            XCTAssertEqual(bands.count, ranges.count)
            for band in bands {
                XCTAssertLessThan(band.lowerBound.radians, band.upperBound.radians)
                XCTAssertGreaterThanOrEqual(band.lowerBound.radians, start)
                XCTAssertLessThanOrEqual(band.upperBound.radians, end + 1e-9)
            }
            // Each band starts past the previous band's end, a gap apart.
            for (previous, next) in zip(bands, bands.dropFirst()) {
                XCTAssertGreaterThan(next.lowerBound.radians, previous.upperBound.radians)
            }
        }
    }

    func testThePillSitsInsideItsBand() {
        let ranges = WatchStressBands.scoreRanges
        let bands = WatchBandRingView.bandAngles(ranges, radius: 19, lineWidth: 7.2)
        let band = bands[1]
        XCTAssertEqual(WatchBandRingView.pillAngle(score: 26, band: band, range: ranges[1]).radians, band.lowerBound.radians, accuracy: 1e-9)
        XCTAssertEqual(WatchBandRingView.pillAngle(score: 50, band: band, range: ranges[1]).radians, band.upperBound.radians, accuracy: 1e-9)
        let middle = WatchBandRingView.pillAngle(score: 42, band: band, range: ranges[1]).radians
        XCTAssertGreaterThan(middle, band.lowerBound.radians)
        XCTAssertLessThan(middle, band.upperBound.radians)
    }
}
