//
//  WatchHeroWarningBadgeRow.swift
//  BodyWatch
//
//  The warning signs under the watch hero's number: the iPhone's
//  `BodyHeroWarningBadgeRow` (`Body/Views/BodyReadinessStarHero.swift`) with
//  every size laid out in phone points and multiplied by the hero's `scale`, so
//  the row sits where the phone's does once the hero is scaled to the watch.
//  Shared by the Readiness Ring and the Day Ring heroes.
//
//  Display only. The phone lays a tap target over each badge that scrolls to
//  its Home card; the watch has no such target (the badges point at the cards
//  right under the hero, which carry the same glyph), so the row publishes no
//  anchors and takes no taps of its own. On the Readiness Ring a tap on the row
//  opens Readiness like the rest of the hero.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchHeroWarningBadgeRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One badge per card with an unfolded warning, in the dashboard's card order.
    let badges: [WatchHeroWarningBadge]
    /// The hero's text opacity, so the row fades with the number as the ring flattens.
    let opacity: Double
    /// The hero's phone-to-watch scale (`WatchReadinessHero.scale(width:)`).
    let scale: CGFloat

    /// The width of one badge's box in phone points, as on the iPhone: three
    /// badges have to share the row; one or two can spend it.
    static func slotWidth(count: Int) -> CGFloat {
        switch count {
        case 0, 1:
            return 44
        case 2:
            return 36
        default:
            return 28
        }
    }

    /// Air between the boxes in phone points once more than one warning is
    /// showing, so the glyphs read as separate signs rather than one clump.
    static func spacing(count: Int) -> CGFloat {
        count > 1 ? 12 : 0
    }

    var body: some View {
        let count = badges.count
        HStack(spacing: Self.spacing(count: count) * scale) {
            ForEach(badges) { _ in
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20 * scale, weight: .bold))
                    .foregroundStyle(.yellow)
                    .frame(
                        width: Self.slotWidth(count: count) * scale,
                        height: BodyReadinessArcGeometry.badgeRowHeight * scale
                    )
                    .transition(.opacity)
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.3), radius: 6 * scale, y: 1 * scale)
        .opacity(opacity)
        // The same fade the card glyphs use, so a warning arriving mid-refresh
        // reads as one change in both places.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: badges)
        // The hero speaks the warnings in its own accessibility value.
        .accessibilityHidden(true)
    }
}
