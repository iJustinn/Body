//
//  BodyPullToRefreshTrigger.swift
//  Body
//

import SwiftUI
import UIKit

/// Replaces `.refreshable`: fires `action` once when the user pulls the scroll
/// view down past `threshold`, re-arming only after the content returns to rest.
/// No system refresh control is installed, so no system spinner ever appears —
/// the floating sync badge is the refresh UI.
private struct BodyPullToRefreshTrigger: ViewModifier {
    /// Pull distance (in points, past the resting top) that fires `action`.
    let threshold: CGFloat
    /// When true the pull is ignored, so an in-flight refresh can't re-trigger.
    let isRefreshing: Bool
    let action: () -> Void

    /// Latch that lets a single pull fire once; re-armed when the content
    /// scrolls back to (near) rest so the next distinct pull can fire again.
    @State private var isArmed = true
    /// True only while the user's finger is on the scroll view. A momentum
    /// rubber-band bounce (fling to top) can overshoot the threshold too, but
    /// arrives in the `.decelerating`/`.animating` phase — only a held pull
    /// counts as a refresh gesture.
    @State private var isTouchDriven = false

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, newPhase in
                isTouchDriven = newPhase == .tracking || newPhase == .interacting
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                if offset < -threshold {
                    guard isArmed, isTouchDriven, !isRefreshing else { return }
                    isArmed = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                } else if offset >= -1 {
                    isArmed = true
                }
            }
    }
}

extension View {
    /// Custom pull-to-refresh with no system refresh control (and therefore no
    /// system spinner). See `BodyPullToRefreshTrigger`.
    func bodyPullToRefresh(
        threshold: CGFloat = 70,
        isRefreshing: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        modifier(BodyPullToRefreshTrigger(threshold: threshold, isRefreshing: isRefreshing, action: action))
    }
}
