//
//  WatchHeroWarningBadgeRowTests.swift
//  BodyWatchTests
//
//  The watch hero's warning row keeps the iPhone row's sizes in phone points
//  (`BodyHeroWarningBadgeRow`): one or two badges spend the row, three or
//  more share it, and the boxes only get air between them once there is more
//  than one.
//

import XCTest
@testable import BodyWatch

final class WatchHeroWarningBadgeRowTests: XCTestCase {
    func testSlotWidthNarrowsAsBadgesShareTheRow() {
        XCTAssertEqual(WatchHeroWarningBadgeRow.slotWidth(count: 0), 44)
        XCTAssertEqual(WatchHeroWarningBadgeRow.slotWidth(count: 1), 44)
        XCTAssertEqual(WatchHeroWarningBadgeRow.slotWidth(count: 2), 36)
        XCTAssertEqual(WatchHeroWarningBadgeRow.slotWidth(count: 3), 28)
        XCTAssertEqual(WatchHeroWarningBadgeRow.slotWidth(count: 5), 28)
    }

    func testSpacingOnlyBetweenMoreThanOneBadge() {
        XCTAssertEqual(WatchHeroWarningBadgeRow.spacing(count: 0), 0)
        XCTAssertEqual(WatchHeroWarningBadgeRow.spacing(count: 1), 0)
        XCTAssertEqual(WatchHeroWarningBadgeRow.spacing(count: 2), 12)
        XCTAssertEqual(WatchHeroWarningBadgeRow.spacing(count: 3), 12)
    }
}
