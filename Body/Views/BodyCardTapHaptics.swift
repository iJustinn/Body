//
//  BodyCardTapHaptics.swift
//  Body
//

import SwiftUI
import UIKit

/// The light tap a card plays when it is pressed to open its page: the Summary
/// metric cards, the Activity Rings card, the readiness hero, the trend cards,
/// the workout rows, the Workouts calendar days and type rows, and the workouts in
/// the list sheet they open. Gated by Settings > General > Vibration > Card Vibration.
enum BodyCardTapHaptics {
    static func play() {
        guard BodyHaptics.isEnabled(BodyAppearancePreference.cardTapHapticsEnabledKey) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

extension View {
    /// Plays the card tap alongside a `NavigationLink`'s own tap, which offers no
    /// action closure to hook.
    func bodyCardTapHaptics() -> some View {
        simultaneousGesture(TapGesture().onEnded { BodyCardTapHaptics.play() })
    }
}
