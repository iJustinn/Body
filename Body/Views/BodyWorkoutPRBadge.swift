//
//  BodyWorkoutPRBadge.swift
//  Body
//

import SwiftUI
import UIKit

/// The "PR" pill marking a workout that holds — or once held — an all-time,
/// per-type personal record. Shared by the detail sheet's metric tiles and (in
/// the `onMedia` style) the share cards, so every surface draws one badge.
///
/// Dense surfaces — the workout list rows — deliberately don't use this pill;
/// they draw the bare `trophy.fill` glyph instead so row height is untouched.
struct BodyWorkoutPRBadge: View {
    enum Style {
        /// On card/tile backgrounds: tinted glyph and text over a tint wash.
        case tinted
        /// On photo, map, and gradient share backgrounds, where the raw tint
        /// isn't contrast-safe: white over the same scrim the map attribution uses.
        case onMedia
    }

    var style: Style = .tinted
    /// A record this workout has since lost. The pill stays — the achievement
    /// happened — but drops its tint for the app's neutral pill so it can't be
    /// mistaken for the live record on the workout that took it.
    var standing: WorkoutRecordStanding = .current

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9, weight: .bold))

            Text("pr.badge")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(background, in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(BodyWorkoutPRAccessibility.label(for: standing)))
    }

    private var foreground: AnyShapeStyle {
        switch (style, standing) {
        case (.tinted, .current): return AnyShapeStyle(Color.bodyPRGold)
        case (.tinted, .former): return AnyShapeStyle(HierarchicalShapeStyle.secondary)
        case (.onMedia, .current): return AnyShapeStyle(Color.white)
        case (.onMedia, .former): return AnyShapeStyle(Color.white.opacity(0.6))
        }
    }

    private var background: Color {
        switch (style, standing) {
        case (.tinted, .current): return Color.bodyPRGold.opacity(0.14)
        // The app's neutral pill fill (see BodyProfileView's name field), so a
        // former record reads as a quiet chip rather than a faded workout colour.
        case (.tinted, .former): return Color.primary.opacity(0.06)
        case (.onMedia, _): return .black.opacity(0.35)
        }
    }
}

/// The capsule-less form for dense surfaces: list rows and the detail hero's
/// caption line, where a pill would either stretch the row or squeeze the
/// fixed-width number column.
struct BodyWorkoutPRGlyph: View {
    var size: CGFloat = 12
    var standing: WorkoutRecordStanding = .current

    var body: some View {
        Image(systemName: "trophy.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(foreground)
            .accessibilityLabel(Text(BodyWorkoutPRAccessibility.label(for: standing)))
    }

    private var foreground: AnyShapeStyle {
        switch standing {
        case .current: return AnyShapeStyle(Color.bodyPRGold)
        case .former: return AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }
}

extension Color {
    /// Trophy gold, shared by every current-record badge. A live record is the
    /// same achievement whatever the workout's colour, so the trophy doesn't
    /// borrow the type tint — darker in light mode for contrast on white cards,
    /// brighter in dark mode so it doesn't read as brown.
    static let bodyPRGold = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.78, blue: 0.24, alpha: 1)
            : UIColor(red: 0.71, green: 0.51, blue: 0.05, alpha: 1)
    })
}

/// The one place the two standings' VoiceOver strings are chosen, so the pill, the
/// glyph, and the detail tile's combined label can't drift apart. The *visible*
/// text stays "PR" in both standings and every language.
enum BodyWorkoutPRAccessibility {
    static func label(for standing: WorkoutRecordStanding) -> LocalizedStringKey {
        switch standing {
        case .current: return "pr.accessibility.personalRecord"
        case .former: return "pr.accessibility.formerPersonalRecord"
        }
    }

    /// The resolved string, for surfaces that build one combined label out of
    /// several parts (the detail metric tile ignores child accessibility).
    static func string(for standing: WorkoutRecordStanding) -> String {
        switch standing {
        case .current: return String(localized: "pr.accessibility.personalRecord")
        case .former: return String(localized: "pr.accessibility.formerPersonalRecord")
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        BodyWorkoutPRBadge()
        BodyWorkoutPRBadge(standing: .former)
        BodyWorkoutPRBadge(style: .onMedia)
        BodyWorkoutPRBadge(style: .onMedia, standing: .former)
        BodyWorkoutPRGlyph()
        BodyWorkoutPRGlyph(standing: .former)
    }
    .padding()
}
