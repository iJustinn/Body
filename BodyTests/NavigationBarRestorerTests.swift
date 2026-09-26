//
//  NavigationBarRestorerTests.swift
//  BodyTests
//
//  Covers the repair for a metric detail's navigation bar going missing after a
//  swipe-dismiss is dragged back and cancelled. On device the cancelled zoom left
//  the bar in place at alpha 0 and the page then lost the bar's height, so while
//  the detail is the top of the stack a faded or hidden bar must come back, even
//  when the cancel never sends the page `viewDidAppear` again; once the page is
//  popped or covered the bar is the stack's to change.
//

import SwiftUI
import UIKit
import XCTest
@testable import Body

@MainActor
final class NavigationBarRestorerTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func makePushedPage() throws -> (UINavigationController, UIViewController) {
        let page = UIViewController()
        let restorer = BodyNavigationBarRestoringController()
        page.addChild(restorer)
        page.view.addSubview(restorer.view)
        restorer.didMove(toParent: page)

        let navigationController = UINavigationController(rootViewController: UIViewController())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
        navigationController.pushViewController(page, animated: false)
        spin()
        return (navigationController, page)
    }

    private func spin(_ seconds: TimeInterval = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testHidingTheBarOverTheShownPageIsUndone() throws {
        let (navigationController, _) = try makePushedPage()

        navigationController.setNavigationBarHidden(true, animated: false)
        spin()

        XCTAssertFalse(navigationController.isNavigationBarHidden)
    }

    func testFadedOutBarOverTheShownPageIsRestored() throws {
        let (navigationController, _) = try makePushedPage()

        // What the cancelled zoom leaves behind; the stack's hidden state is set again
        // on its next update, which is when the repair looks.
        navigationController.navigationBar.alpha = 0
        navigationController.setNavigationBarHidden(false, animated: false)
        navigationController.navigationBar.isHidden = false
        spin()

        XCTAssertEqual(navigationController.navigationBar.alpha, 1)
        XCTAssertFalse(navigationController.isNavigationBarHidden)
    }

    func testPoppedPageLeavesAFadedBarAlone() throws {
        let (navigationController, _) = try makePushedPage()

        navigationController.popViewController(animated: false)
        navigationController.navigationBar.alpha = 0
        navigationController.navigationBar.isHidden = false
        spin()

        XCTAssertEqual(navigationController.navigationBar.alpha, 0)
    }

    func testCancelledDismissalWithoutReappearingStillUndoesAHide() throws {
        let (navigationController, page) = try makePushedPage()

        // The dismissal starts, is cancelled, and the page is never told it appeared again.
        page.beginAppearanceTransition(false, animated: true)
        navigationController.setNavigationBarHidden(true, animated: false)
        spin()

        XCTAssertFalse(navigationController.isNavigationBarHidden)
    }

    func testPoppedPageLetsTheRootHideTheBar() throws {
        let (navigationController, _) = try makePushedPage()

        navigationController.popViewController(animated: false)
        navigationController.setNavigationBarHidden(true, animated: false)
        spin()

        XCTAssertTrue(navigationController.isNavigationBarHidden)
    }

    func testCoveredPageLetsThePageAboveHideTheBar() throws {
        let (navigationController, _) = try makePushedPage()

        navigationController.pushViewController(UIViewController(), animated: false)
        spin()
        navigationController.setNavigationBarHidden(true, animated: false)
        spin()

        XCTAssertTrue(navigationController.isNavigationBarHidden)
    }

    private final class StackModel: ObservableObject {
        @Published var path: [Int] = []
    }

    private struct UntitledRootStack: View {
        @ObservedObject var model: StackModel

        var body: some View {
            NavigationStack(path: $model.path) {
                Text("Summary")
                    .navigationDestination(for: Int.self) { _ in
                        Text("Detail")
                            .navigationTitle("Detail")
                            .bodyRestoresNavigationBar()
                    }
            }
        }
    }

    func testAnimatedPopToAnUntitledRootStillHidesTheBar() throws {
        let model = StackModel()
        let host = UIHostingController(rootView: UntitledRootStack(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        spin()
        let navigationController = try XCTUnwrap(host.children.first as? UINavigationController)
        XCTAssertTrue(navigationController.isNavigationBarHidden)

        model.path = [1]
        spin(1.2)
        XCTAssertEqual(navigationController.viewControllers.count, 2)
        XCTAssertFalse(navigationController.isNavigationBarHidden)

        model.path = []
        spin(1.2)
        XCTAssertEqual(navigationController.viewControllers.count, 1)
        XCTAssertTrue(navigationController.isNavigationBarHidden)
    }

    func testZoomPushedHomeDetailsCarryTheRestorer() throws {
        let home = try BodyTestSupport.sourceText(at: "Body/Views/BodyHomeView.swift")
        XCTAssertTrue(home.contains(
            ".navigationTransition(.zoom(sourceID: route, in: metricZoom))\n"
            + "                // A swipe-dismiss dragged back and cancelled can leave the bar hidden.\n"
            + "                .bodyRestoresNavigationBar()"
        ))
    }
}
