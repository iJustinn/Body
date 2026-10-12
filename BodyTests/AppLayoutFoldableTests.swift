//
//  AppLayoutFoldableTests.swift
//  BodyTests
//
//  The foldable split never turns on for a portrait iPhone, whatever folded
//  column width was stored.
//

import XCTest
@testable import Body

final class AppLayoutFoldableTests: XCTestCase {
    func testFoldedHomeColumnWidthFloorsImplausibleStoredValues() {
        XCTAssertEqual(AppLayout.foldedHomeColumnWidth(stored: 0), 344)
        XCTAssertEqual(AppLayout.foldedHomeColumnWidth(stored: 100), 344)
        XCTAssertEqual(AppLayout.foldedHomeColumnWidth(stored: 199), 344)
        XCTAssertEqual(AppLayout.foldedHomeColumnWidth(stored: 200), 200)
        XCTAssertEqual(AppLayout.foldedHomeColumnWidth(stored: 380), 380)
    }

    func testNoPortraitIPhoneSplitsForAnyStoredColumnWidth() {
        let storedWidths: [Double] = [0, 1, 50, 100, 146, 199, 200, 250, 344, 400]
        let pageWidths: [CGFloat] = [375, 390, 393, 402, 414, 428, 430, 440]

        for stored in storedWidths {
            let columnWidth = AppLayout.foldedHomeColumnWidth(stored: stored)
            for width in pageWidths {
                // Summary measures with its 32 pt of padding, so check both.
                XCTAssertFalse(
                    AppLayout.isFoldableSplit(contentWidth: width - 32, columnWidth: columnWidth),
                    "stored \(stored), page \(width) less padding"
                )
                XCTAssertFalse(
                    AppLayout.isFoldableSplit(contentWidth: width, columnWidth: columnWidth),
                    "stored \(stored), page \(width)"
                )
            }
        }
    }
}
