//
//  WatchMetricWarningCard.swift
//  BodyWatch
//
//  The foldable warning cards at the bottom of a watch metric detail page:
//  the phone's `BodyMetricWarningCard` at watch size, for today's warnings,
//  the phone's and the watch's own (`WatchMetricWarnings.shown`). The header row
//  (the triangle, the title and a chevron) folds and unfolds the card; the
//  chevron points left while it is folded and turns to point down once it is
//  unfolded, like the phone's `BodyWarningCardHeader`. Unfolded, the card
//  reads the phone's sentence and, for High Heart Rate, its workout footnote.
//  There is no chart: the watch has no readings around the episode.
//
//  Folding a card also hides its glyph on the dashboard card and its badge
//  under the hero number, and the fold syncs with the phone through
//  `WatchWarningFoldStore`, which owns the fold state. These views only draw
//  the row they're handed and report a tap, so they render in tests.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

/// One warning card: the header row, and while unfolded the sentence (plus
/// the workout footnote for High Heart Rate). Folding it hides the warning's
/// card glyph and hero badge on the watch for the day, and syncs to the phone.
struct WatchMetricWarningCard: View {
    /// Grows the header row's tap area to the 44 pt minimum without moving
    /// anything or changing the card's height: the slop is padded in and
    /// cancelled out again, as on the phone's header.
    private static var tapSlop: CGFloat { 8 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let row: WatchMetricWarningRow
    /// Whether the Skin Temp metric reads in Fahrenheit, so the threshold in
    /// the sentence matches the page's value. Ignored by the heart and blood
    /// oxygen warnings.
    let usesFahrenheit: Bool
    /// Folds or unfolds `row.warning` (the pager hands it to the fold store).
    let onToggleFold: (WatchMetricWarning) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if !row.isFolded {
                Text(verbatim: WatchMetricWarnings.sentence(for: row.warning, kind: row.kind, usesFahrenheit: usesFahrenheit) ?? "")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if row.kind.excludesWorkouts {
                    Text("If you were working out, this warning will disappear once the workout is logged.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }

    /// The whole row is one button, so a tap anywhere on it folds or unfolds
    /// the card.
    private var header: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0)) {
                onToggleFold(row.warning)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(verbatim: WatchMetricWarnings.title(for: row.kind) ?? "")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    // A plain gray, not the hierarchical style, which would take
                    // the header's warning tint.
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(row.isFolded ? 0 : -90))
                    // A fixed square, so the turning glyph never shifts the title.
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            .padding(Self.tapSlop)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-Self.tapSlop)
        .foregroundStyle(.yellow)
        .accessibilityHint(row.isFolded ? Text("Expand Warning") : Text("Collapse Warning"))
    }
}

/// A detail page's warning cards, stacked below its last chart with the
/// page's chart section padding. The caller adds it only for a page with
/// warnings; an empty `rows` draws an empty stack.
struct WatchMetricWarningSection: View {
    let rows: [WatchMetricWarningRow]
    /// See `WatchMetricWarningCard.usesFahrenheit`.
    let usesFahrenheit: Bool
    /// See `WatchMetricWarningCard.onToggleFold`.
    let onToggleFold: (WatchMetricWarning) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                WatchMetricWarningCard(row: row, usesFahrenheit: usesFahrenheit, onToggleFold: onToggleFold)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}
