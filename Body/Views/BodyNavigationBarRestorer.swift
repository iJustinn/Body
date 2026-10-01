//
//  BodyNavigationBarRestorer.swift
//  Body
//

import OSLog
import SwiftUI
import UIKit

/// Keeps the navigation bar showing while the page it sits on is the top of the stack.
///
/// Swiping a zoom-pushed detail partway closed fades its navigation bar out, and
/// dragging it back cancels the dismissal without fading the bar back in: the bar
/// stays in place at alpha 0, so the Back chevron, the title, and the toolbar buttons
/// are gone, and UIKit's next layout then drops the bar's height from the page, which
/// slides up under the status bar. So when a transition over this page ends, the bar
/// is made opaque again right away, before that layout runs. Later passes (after
/// UIKit's own cleanup, whenever the bar's hidden state is set, or the page's safe
/// area changes) catch anything that still slips through, and if the page did lose
/// the bar's height, hiding and showing the bar lays it out under the bar again.
final class BodyNavigationBarRestoringController: UIViewController {
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "NavigationBar")
    private var barHiddenObservation: NSKeyValueObservation?
    /// The repair re-lays out the page, which lands back here through the safe area.
    private var isRepairing = false

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if barHiddenObservation == nil, let navigationBar = navigationController?.navigationBar {
            barHiddenObservation = navigationBar.observe(\.isHidden) { [weak self] _, _ in
                // Not from inside UIKit's own update: look once that has finished.
                DispatchQueue.main.async { self?.showNavigationBarIfMissing() }
            }
        }
        showNavigationBarIfMissing()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        showNavigationBarIfMissing()
    }

    /// The page in the stack that this restorer sits on.
    private var stackPage: UIViewController? {
        var page: UIViewController = self
        while let parent = page.parent {
            if parent === navigationController { return page }
            page = parent
        }
        return nil
    }

    private func isPageLaidOutWithoutBar(_ page: UIViewController, in navigationController: UINavigationController) -> Bool {
        navigationController.isNavigationBarHidden
            || navigationController.navigationBar.isHidden
            || page.view.safeAreaInsets.top < navigationController.navigationBar.frame.maxY
    }

    private func showNavigationBarIfMissing(transitionEnded: Bool = false) {
        guard let navigationController, let page = stackPage else { return }
        let navigationBar = navigationController.navigationBar
        guard navigationBar.alpha < 1 || isPageLaidOutWithoutBar(page, in: navigationController) else { return }
        if !transitionEnded, let coordinator = navigationController.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                // Right away, before the stack lays the page out without the bar,
                self?.showNavigationBarIfMissing(transitionEnded: true)
                // and again after UIKit's own cleanup of the transition.
                DispatchQueue.main.async { self?.showNavigationBarIfMissing() }
            }
            return
        }
        guard navigationController.topViewController === page, !isRepairing else { return }
        isRepairing = true
        defer { isRepairing = false }
        Self.logger.notice("Restoring the navigation bar over the top page")
        navigationBar.alpha = 1
        if isPageLaidOutWithoutBar(page, in: navigationController) {
            navigationController.setNavigationBarHidden(true, animated: false)
            navigationController.setNavigationBarHidden(false, animated: false)
        }
    }
}

private struct BodyNavigationBarRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BodyNavigationBarRestoringController {
        BodyNavigationBarRestoringController()
    }

    func updateUIViewController(_ uiViewController: BodyNavigationBarRestoringController, context: Context) {}
}

extension View {
    /// For a pushed page that keeps the navigation bar: see `BodyNavigationBarRestoringController`.
    func bodyRestoresNavigationBar() -> some View {
        background(BodyNavigationBarRestorer().accessibilityHidden(true))
    }
}
