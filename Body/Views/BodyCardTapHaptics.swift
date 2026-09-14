//
//  BodyCardTapHaptics.swift
//  Body
//

import SwiftUI
import UIKit

/// The light tap a card plays when it is pressed to open its page: the Summary
/// metric cards, the Activity Rings card, the readiness hero, the trend cards,
/// and the workout rows. Gated by Settings > General > Vibration > Card Vibration.
enum BodyCardTapHaptics {
    static func play() {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: BodyAppearancePreference.cardTapHapticsEnabledKey) as? Bool ?? true
        guard isEnabled else { return }
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
