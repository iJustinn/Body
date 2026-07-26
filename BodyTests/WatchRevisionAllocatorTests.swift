//
//  WatchRevisionAllocatorTests.swift
//  BodyTests
//
//  The phone-side counter/epoch that stamps `WatchMetricsSnapshot.publisherEpoch`
//  + `revision` before a push. `WatchConnectivityPublisher` is a Body-target-only
//  service, so this lives in the iOS test bundle. The allocator must mint one
//  stable epoch per install, advance a persisted monotonic revision, and — on a
//  reinstall / data reset (cleared defaults) — mint a new epoch and restart the
//  revision so the watch treats the next payload as a fresh install.
//

import XCTest
@testable import Body

final class WatchRevisionAllocatorTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "WatchRevisionAllocatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testEpochIsStableAcrossCalls() {
        let allocator = WatchRevisionAllocator(defaults: makeDefaults())
        let first = allocator.epoch()
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, allocator.epoch())
    }

    func testEpochPersistsAcrossAllocatorInstances() {
        let defaults = makeDefaults()
        let first = WatchRevisionAllocator(defaults: defaults).epoch()
        let second = WatchRevisionAllocator(defaults: defaults).epoch()
        XCTAssertEqual(first, second)
    }

    func testNextRevisionIsMonotonicStartingAtOne() {
        let allocator = WatchRevisionAllocator(defaults: makeDefaults())
        XCTAssertEqual(allocator.nextRevision(), 1)
        XCTAssertEqual(allocator.nextRevision(), 2)
        XCTAssertEqual(allocator.nextRevision(), 3)
    }

    func testRevisionPersistsAcrossAllocatorInstances() {
        let defaults = makeDefaults()
        XCTAssertEqual(WatchRevisionAllocator(defaults: defaults).nextRevision(), 1)
        XCTAssertEqual(WatchRevisionAllocator(defaults: defaults).nextRevision(), 2)
    }

    func testStampedAppliesEpochAndIncrementingRevision() {
        let allocator = WatchRevisionAllocator(defaults: makeDefaults())
        let base = WatchMetricsSnapshot(generatedAt: Date(), lastRefreshDate: nil, metrics: [])

        let first = allocator.stamped(base)
        let second = allocator.stamped(base)

        XCTAssertEqual(first.publisherEpoch, allocator.epoch())
        XCTAssertEqual(second.publisherEpoch, first.publisherEpoch)
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(second.revision, 2)
        // Same-install ordering: the later stamp supersedes the earlier one.
        XCTAssertTrue(second.supersedes(first))
    }

    func testFreshDefaultsMintNewEpochAndRestartRevision() {
        // Simulates a reinstall / data reset: a brand-new defaults suite.
        let firstInstall = WatchRevisionAllocator(defaults: makeDefaults())
        let firstEpoch = firstInstall.epoch()
        _ = firstInstall.nextRevision()
        _ = firstInstall.nextRevision()

        let reinstall = WatchRevisionAllocator(defaults: makeDefaults())
        XCTAssertNotEqual(reinstall.epoch(), firstEpoch)
        XCTAssertEqual(reinstall.nextRevision(), 1)
    }
}
