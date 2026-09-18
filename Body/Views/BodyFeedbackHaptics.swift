//
//  BodyFeedbackHaptics.swift
//  Body
//

import SwiftUI
import UIKit

/// The gate every haptic in Body passes: the app wide switch (Settings > General >
/// Vibration > All Vibrations) and, when the haptic has one, its own switch.
enum BodyHaptics {
    static var isMasterEnabled: Bool { isOn(BodyAppearancePreference.allHapticsEnabledKey) }

    static func isEnabled(_ key: String) -> Bool { isMasterEnabled && isOn(key) }

    private static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

/// Result haptics: a pulled refresh landing or failing, a share card saved to Photos,
/// a Body Pro purchase or restore, the readiness score landing on Home, and a warning
/// card's first appearance. Gated by Settings > General > Vibration > Confirmation Vibration.
@MainActor
enum BodyConfirmationHaptics {
    /// Set when a pull starts a refresh and consumed by the sync badge when that session
    /// ends, so a refresh the app started on its own stays silent.
    static var awaitsRefreshResult = false

    /// Warning episodes whose card already buzzed this session, keyed by kind and start
    /// so an episode that keeps growing is not announced again.
    private static var announcedWarnings: Set<String> = []

    nonisolated static var isEnabled: Bool {
        BodyHaptics.isEnabled(BodyAppearancePreference.confirmationHapticsEnabledKey)
    }

    static func play(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// The soft landing when the readiness score settles on Home.
    static func playScoreReveal() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// One warning buzz per episode per session, so reopening the page does not nag.
    static func playWarningAppeared(_ event: MetricWarningEvent) {
        let key = "\(event.kind)|\(event.startDate.timeIntervalSinceReferenceDate)"
        guard announcedWarnings.insert(key).inserted else { return }
        play(.warning)
    }
}

/// A selection tick when a Settings choice becomes the selected one, and the ticks of a
/// Summary card reorder. Gated by Settings > General > Vibration > Selection Vibration.
@MainActor
enum BodySelectionHaptics {
    nonisolated static var isEnabled: Bool {
        BodyHaptics.isEnabled(BodyAppearancePreference.selectionHapticsEnabledKey)
    }

    static func playTick() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func playDrop() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

extension View {
    /// Ticks when `isSelected` turns true, so the tap that picks a choice is felt once.
    func bodySelectionHaptics(isSelected: Bool) -> some View {
        sensoryFeedback(trigger: isSelected) { _, selected in
            selected && BodySelectionHaptics.isEnabled ? .selection : nil
        }
    }
}
