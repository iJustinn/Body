//
//  ActivityRingsDetailLayoutTests.swift
//  BodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

/// Hosts the real Activity Rings detail screen at an exact 390x844 pt viewport (the
/// iPhone 13/14 class the off-center report came from) and measures where its scroll
/// content actually lands, sample by sample, from first layout through the `.task`
/// turn. The bug only shows before the first user scroll, so a single settled sample
/// would miss it.
@MainActor
final class ActivityRingsDetailLayoutTests: XCTestCase {
    private static let viewport = CGSize(width: 390, height: 844)
    /// Matches `MainTabView`'s iOS 18 custom pill bar inset so the hosted geometry
    /// matches production rather than a bare window.
    private static let tabBarInset: CGFloat = 64

    /// The reported shape: the screen comes up with barely any content while the
    /// backfill is still running, so the anchors resolve against a single month that
    /// cannot fill the viewport. Built from the view's own `displayHistory` fallback
    /// (empty history + a live summary synthesizes one day), which needs no store
    /// mutation seam.
    func testActivityRingsDetailContentIsHorizontallyCenteredOnColdStart() throws {
        try assertHorizontallyCentered(snapshot: coldStartDashboardSnapshot(), shape: "cold start, single month")
    }

    /// The warm shape: a persisted snapshot, so the anchors resolve against months
    /// that overflow the viewport on the first layout pass.
    func testActivityRingsDetailContentIsHorizontallyCenteredWithPopulatedHistory() throws {
        try assertHorizontallyCentered(snapshot: try seededDashboardSnapshot(), shape: "populated, 13 months")
    }

    /// The real cold-launch shape since ring history left the refresh barrier: months
    /// arrive from a background task in newest-first chunks, so the content grows in
    /// discrete steps and `.defaultScrollAnchor(.bottom, for: .alignment)` re-resolves
    /// on each one. A cross-axis anchor that resolves repeatedly is exactly what would
    /// reintroduce the offset, so centring is asserted after every arrival.
    func testActivityRingsDetailStaysCenteredAsHistoryArrivesInChunks() throws {
        let calendar = Calendar.bodyGregorian
        let harness = try makeHarness(snapshot: coldStartDashboardSnapshot())
        defer { harness.tearDown() }

        var timeline: [Sample] = []
        harness.window.layoutIfNeeded()
        spinRunLoop()
        harness.window.layoutIfNeeded()
        timeline.append(try sample(harness, label: "before any chunk"))

        // Newest-first, matching the production walk: the recent span lands first and
        // the older span merges underneath it.
        for (index, monthsBack) in [0, 12].enumerated() {
            let chunk = try ringChunk(monthsBack: monthsBack, monthCount: 12, calendar: calendar)
            XCTAssertTrue(
                harness.store.applyActivityRingHistoryChunk(chunk, capturedEpoch: 0, calendar: calendar),
                "Chunk \(index + 1) was rejected by the epoch guard; the harness would be measuring nothing"
            )
            for _ in 1...3 {
                spinRunLoop()
                harness.window.layoutIfNeeded()
            }
            timeline.append(try sample(harness, label: "after chunk \(index + 1)"))
        }

        let report = "[chunked arrival]\n" + timeline.map(\.description).joined(separator: "\n")
        Self.writeDiagnostics(report: report, shape: "chunked arrival", harness: harness)

        // Without this the centring assertions below could pass vacuously: if the
        // chunks never reached the view, the anchor would never re-resolve and there
        // would be nothing to catch.
        for (previous, next) in zip(timeline, timeline.dropFirst()) {
            XCTAssertGreaterThan(
                next.contentSize.height,
                previous.contentSize.height,
                "Content did not grow between '\(previous.label)' and '\(next.label)', so this "
                    + "test is not exercising chunked arrival at all.\n\(report)"
            )
        }

        for sample in timeline {
            let container = sample.scrollViewBounds.width
            XCTAssertEqual(
                sample.contentOffset.x,
                0,
                accuracy: 0.5,
                "[chunked arrival] \(sample.label): the alignment anchor re-resolved into a "
                    + "horizontal offset as content grew.\n\(report)"
            )
            XCTAssertEqual(
                sample.contentViewCenterX,
                container / 2,
                accuracy: 0.5,
                "[chunked arrival] \(sample.label): content is not horizontally centered.\n\(report)"
            )
        }
    }

    /// `monthCount` months of closed rings ending `monthsBack` months before this month,
    /// shaped like one chunk of the newest-first backfill walk.
    private func ringChunk(
        monthsBack: Int,
        monthCount: Int,
        calendar: Calendar
    ) throws -> ActivityRingHistorySnapshot {
        let today = calendar.startOfDay(for: Date())
        let end = try XCTUnwrap(calendar.date(byAdding: .month, value: -monthsBack, to: today))
        let start = try XCTUnwrap(calendar.date(byAdding: .month, value: -monthCount, to: end))

        var days: [ActivityRingDaySummary] = []
        var monthKeys: Set<ActivityRingMonthKey> = []
        var cursor = try XCTUnwrap(calendar.dateInterval(of: .month, for: start)?.start)
        while cursor <= end {
            days.append(
                ActivityRingDaySummary(
                    date: cursor,
                    summary: ActivityRingSummary(
                        move: ActivityRingMetric(value: 620, goal: 600),
                        exercise: ActivityRingMetric(value: 42, goal: 30),
                        stand: ActivityRingMetric(value: 13, goal: 12)
                    )
                )
            )
            monthKeys.insert(ActivityRingMonthKey(date: cursor, calendar: calendar))
            cursor = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: cursor))
        }
        return ActivityRingHistorySnapshot(days: days, loadedMonthKeys: Array(monthKeys))
    }

    private func assertHorizontallyCentered(snapshot: HealthDashboardSnapshot, shape: String) throws {
        let harness = try makeHarness(snapshot: snapshot)
        defer { harness.tearDown() }

        var timeline: [Sample] = []
        harness.window.layoutIfNeeded()
        timeline.append(try sample(harness, label: "first layout"))

        // Let `.task` (refreshCalendarMonths + pinToCurrentMonth) and the layout
        // passes it schedules run.
        for turn in 1...6 {
            spinRunLoop()
            harness.window.layoutIfNeeded()
            timeline.append(try sample(harness, label: "turn \(turn)"))
        }

        let report = "[\(shape)]\n" + timeline.map(\.description).joined(separator: "\n")
        Self.writeDiagnostics(report: report, shape: shape, harness: harness)

        // Every sample, not just the last: the bug is visible before the first user
        // scroll and disappears afterwards, so a settled-only check would miss it.
        for sample in timeline {
            let container = sample.scrollViewBounds.width
            XCTAssertEqual(
                sample.contentSize.width,
                container,
                accuracy: 0.5,
                "[\(shape)] \(sample.label): scroll content is wider than its viewport, which "
                    + "gives the 2D anchors horizontal range to resolve into.\n\(report)"
            )
            XCTAssertEqual(
                sample.contentOffset.x,
                0,
                accuracy: 0.5,
                "[\(shape)] \(sample.label): scroll content is horizontally offset before any "
                    + "user scroll.\n\(report)"
            )
            XCTAssertEqual(
                sample.contentViewCenterX,
                container / 2,
                accuracy: 0.5,
                "[\(shape)] \(sample.label): scroll content is not horizontally centered in its "
                    + "viewport.\n\(report)"
            )
        }
    }

    // MARK: - Harness

    private struct Harness {
        let window: UIWindow
        let host: UIViewController
        let store: HealthKitWorkoutStore

        func tearDown() {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func makeHarness(snapshot: HealthDashboardSnapshot) throws -> Harness {
        let calendar = Calendar.bodyGregorian
        let today = Date()
        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [WorkoutMonthSnapshot.make(
                month: calendar.component(.month, from: today),
                year: calendar.component(.year, from: today),
                workouts: [],
                calendar: calendar
            )],
            initialHealthDashboardSnapshot: snapshot,
            initialSummaryContextSignature: nil,
            initialPermissionSelection: BodyHealthPermissionSelection.defaultValue
        )

        let root = NavigationStack {
            BodyActivityRingsDetailView()
                .environment(store)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Self.tabBarInset)
        }

        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "BodyTests is app-hosted, so a UIWindowScene must exist"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.viewport)
        window.rootViewController = host
        window.makeKeyAndVisible()
        return Harness(window: window, host: host, store: store)
    }

    /// No persisted ring history, but a live summary for today — which is what the
    /// detail view's `displayHistory` fallback turns into a single synthetic day, and
    /// therefore a single under-filling month. `loadPreviousActivityRingMonthIfNeeded`
    /// bails on `!needsInitialHealthDataLoad`, so this cannot reach HealthKit even
    /// though the content is deliberately underfilled.
    private func coldStartDashboardSnapshot() -> HealthDashboardSnapshot {
        var summary = HealthSummarySnapshot.empty
        summary.activityRings = ActivityRingSummary(
            move: ActivityRingMetric(value: 620, goal: 600),
            exercise: ActivityRingMetric(value: 42, goal: 30),
            stand: ActivityRingMetric(value: 13, goal: 12)
        )
        return HealthDashboardSnapshot(summary: summary, trends: .empty, activityRingHistory: .empty)
    }

    /// Thirteen fully-populated months ending today. Enough content that the view is
    /// never "underfilled", so `loadOlderMonthsIfNeeded` stays gated and no live
    /// HealthKit query runs during the test.
    private func seededDashboardSnapshot() throws -> HealthDashboardSnapshot {
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        let start = try XCTUnwrap(calendar.date(byAdding: .month, value: -12, to: today))
        let firstDay = try XCTUnwrap(calendar.dateInterval(of: .month, for: start)?.start)

        var days: [ActivityRingDaySummary] = []
        var monthKeys: Set<ActivityRingMonthKey> = []
        var cursor = firstDay
        while cursor <= today {
            days.append(
                ActivityRingDaySummary(
                    date: cursor,
                    summary: ActivityRingSummary(
                        move: ActivityRingMetric(value: 620, goal: 600),
                        exercise: ActivityRingMetric(value: 42, goal: 30),
                        stand: ActivityRingMetric(value: 13, goal: 12)
                    )
                )
            )
            monthKeys.insert(ActivityRingMonthKey(date: cursor, calendar: calendar))
            cursor = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: cursor))
        }

        return HealthDashboardSnapshot(
            summary: .empty,
            trends: .empty,
            activityRingHistory: ActivityRingHistorySnapshot(
                days: days,
                loadedMonthKeys: Array(monthKeys)
            )
        )
    }

    // MARK: - Measurement

    private struct Sample {
        let label: String
        let scrollViewFrameInWindow: CGRect
        let scrollViewBounds: CGRect
        let scrollViewTransform: CGAffineTransform
        let contentSize: CGSize
        let contentOffset: CGPoint
        let adjustedInset: UIEdgeInsets
        /// Center of the scroll view's content view, in window coordinates — the
        /// number directly comparable to the pixel measurement of the screenshot.
        let contentViewCenterX: CGFloat

        var description: String {
            String(
                format: "%@: scrollView frame %@ bounds.w %.2f transform %@ | "
                    + "contentSize.w %.4f contentOffset.x %.4f insets(l %.1f r %.1f) | "
                    + "content center x in window %.2f",
                label,
                NSCoder.string(for: scrollViewFrameInWindow),
                scrollViewBounds.width,
                scrollViewTransform.isIdentity ? "identity" : NSCoder.string(for: scrollViewTransform),
                contentSize.width,
                contentOffset.x,
                adjustedInset.left,
                adjustedInset.right,
                contentViewCenterX
            )
        }
    }

    private func sample(_ harness: Harness, label: String) throws -> Sample {
        let scrollView = try XCTUnwrap(
            Self.firstScrollView(in: harness.window),
            "No UIScrollView materialized in the hosted hierarchy"
        )
        let contentView = try XCTUnwrap(scrollView.subviews.first, "Scroll view has no content view")
        let contentInWindow = contentView.convert(contentView.bounds, to: harness.window)

        return Sample(
            label: label,
            scrollViewFrameInWindow: scrollView.convert(scrollView.bounds, to: harness.window),
            scrollViewBounds: scrollView.bounds,
            scrollViewTransform: scrollView.transform,
            contentSize: scrollView.contentSize,
            contentOffset: scrollView.contentOffset,
            adjustedInset: scrollView.adjustedContentInset,
            contentViewCenterX: contentInWindow.midX
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

    private func spinRunLoop(_ interval: TimeInterval = 0.15) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    /// Writes the timeline and a PNG of the hosted screen so the same pixel-measuring
    /// script used on the bug report can be run against it.
    private static func writeDiagnostics(report: String, shape: String, harness: Harness) {
        print("[rings-layout]\n\(report)")
        guard let directory = ProcessInfo.processInfo.environment["BODY_LAYOUT_DIAGNOSTICS_DIR"] else {
            return
        }

        let slug = shape.replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "-", options: .regularExpression)
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? report.write(
            to: url.appendingPathComponent("timeline-\(slug).txt"),
            atomically: true,
            encoding: .utf8
        )

        let renderer = UIGraphicsImageRenderer(bounds: harness.window.bounds)
        let image = renderer.image { context in
            if !harness.window.drawHierarchy(in: harness.window.bounds, afterScreenUpdates: true) {
                // drawHierarchy needs an on-screen window; fall back to the layer so the
                // PNG is never silently blank.
                harness.window.layer.render(in: context.cgContext)
            }
        }
        if let data = image.pngData() {
            try? data.write(to: url.appendingPathComponent("rings-detail-\(slug).png"))
        }
    }
}
