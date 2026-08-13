//
//  ReadinessEdgeBackSwipeTests.swift
//  BodyTests
//
//  Covers the Readiness detail overlay's stand-in for the interactive pop
//  gesture: only a drag that starts at the screen's left edge and travels
//  right, at no more than 45°, may dismiss the page. The gesture is attached
//  simultaneously over a scrolling page full of scrubbable charts, so every
//  other drag shape has to be rejected.
//

import SwiftUI
import XCTest
@testable import Body

final class ReadinessEdgeBackSwipeTests: XCTestCase {
    func testEdgeSwipeToTheRightDismisses() {
        XCTAssertTrue(BodyHomeView.isEdgeBackSwipe(startX: 4, translation: CGSize(width: 120, height: 0)))
        XCTAssertTrue(BodyHomeView.isEdgeBackSwipe(startX: 20, translation: CGSize(width: 80, height: -40)))
    }

    func testSwipeStartingAwayFromTheEdgeIsIgnored() {
        // A chart scrub or a card drag mid-page must never dismiss.
        XCTAssertFalse(BodyHomeView.isEdgeBackSwipe(startX: 21, translation: CGSize(width: 200, height: 0)))
        XCTAssertFalse(BodyHomeView.isEdgeBackSwipe(startX: 180, translation: CGSize(width: 200, height: 0)))
    }

    func testShortOrLeftwardSwipesAreIgnored() {
        XCTAssertFalse(BodyHomeView.isEdgeBackSwipe(startX: 4, translation: CGSize(width: 79, height: 0)))
        XCTAssertFalse(BodyHomeView.isEdgeBackSwipe(startX: 4, translation: CGSize(width: -120, height: 0)))
    }

    func testSteepSwipesAreIgnored() {
        // Scrolling the page from near the left edge: mostly vertical, so it
        // keeps scrolling instead of dismissing.
        XCTAssertFalse(BodyHomeView.isEdgeBackSwipe(startX: 4, translation: CGSize(width: 90, height: 200)))
        XCTAssertFalse(BodyHomeView.isEdgeBackSwipe(startX: 4, translation: CGSize(width: 90, height: -91)))
        XCTAssertTrue(BodyHomeView.isEdgeBackSwipe(startX: 4, translation: CGSize(width: 90, height: 90)))
    }
}
