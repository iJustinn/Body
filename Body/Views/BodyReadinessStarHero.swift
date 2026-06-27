//
//  BodyReadinessStarHero.swift
//  Body
//

import SwiftUI

/// Layout constants shared by the readiness hero's fixed color backdrop and its
/// scrolling text label so they stay vertically aligned.
enum BodyReadinessHeroMetrics {
    /// Height of the colored band at the top of Home (measured from the screen's
    /// top edge, i.e. behind the status bar) before it melts into the page.
    static let coloredHeight: CGFloat = 360
    /// Minimum height of the text label so the headline sits low in the colored band.
    static let labelMinHeight: CGFloat = 255
    /// Vertical center of the big score number's row (measured from the top of the
    /// colored band, i.e. the screen's top edge behind the status bar), used to center
    /// the fill's highlight band on the number in `BodyReadinessHeroLabel`.
    static let numberRowFromTop: CGFloat = 190
}

/// Fixed, full-bleed color backdrop for the Readiness star hero. Lives in the home
/// page's `.ignoresSafeArea()` background so the readiness color reaches the very top
/// of the screen (behind the status bar) and melts into the page background lower down,
/// mirroring how the metric detail hero eases its tint behind the nav bar. The score
/// text scrolls over this in `BodyReadinessHeroLabel`.
struct BodyReadinessHeroBackdrop: View {
    let readiness: ReadinessSummary

    private var status: ReadinessStatus { readiness.status }
    private var tint: Color { BodyReadinessStatusPresentation.color(for: status) }

    private var fillFraction: Double {
        guard let score = readiness.score else { return 0 }
        return min(max(Double(score) / 100, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            BodyReadinessWaveFill(
                fraction: fillFraction,
                tint: tint
            )
            .frame(height: BodyReadinessHeroMetrics.coloredHeight)

            Color(.systemGroupedBackground)
        }
    }
}

/// The readiness score + status text that scrolls over `BodyReadinessHeroBackdrop`.
/// Transparent — the color comes entirely from the backdrop behind it.
struct BodyReadinessHeroLabel: View {
    let readiness: ReadinessSummary

    /// Animated score for the big number — counts up from 0 on launch and rolls to each
    /// new value, kept roughly in sync with the backdrop fill's rise.
    @State private var displayedScore = 0

    private var status: ReadinessStatus { readiness.status }

    private var numberText: String {
        readiness.score == nil ? "--" : "\(displayedScore)"
    }

    private var headline: String {
        status == .unavailable ? "Readiness" : "\(status.title) Readiness"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 95)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(numberText)
                    .font(.system(size: 66, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .animation(.smooth(duration: 0.4, extraBounce: 0), value: displayedScore)

                if readiness.score != nil {
                    Text("%")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .opacity(0.9)
                }
            }

            Spacer().frame(height: 35)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(status.explanation)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 6)
        }
        // `.primary` resolves to white in dark mode (the tuned look) but near-black in
        // light mode, so the headline/explanation stay legible where they extend past the
        // colored fill onto the light page background instead of vanishing white-on-light.
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: BodyReadinessHeroMetrics.labelMinHeight, alignment: .leading)
        // Whole area (including the transparent gaps) taps through to the detail page.
        .contentShape(Rectangle())
        .onAppear {
            // Flip from 0 up to today's score on launch. The roll lives on the number
            // itself (same .smooth / .numericText as the metric cards), nothing else.
            displayedScore = readiness.score ?? 0
        }
        .onChange(of: readiness.score) { _, newScore in
            displayedScore = newScore ?? 0
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let score = readiness.score else {
            return "Readiness, needs more data"
        }
        return "Readiness \(score) percent, \(status.title)"
    }
}

/// The animated fill: solid `tint` from the left edge out to `fraction` of the width,
/// with a soft horizontal highlight band centered on the score number's row, the fill
/// front cut crisply and the lower portion melting into the page background. The level
/// animates via frame width so it rises from empty and slosh-springs to each new value.
private struct BodyReadinessWaveFill: View {
    let fraction: Double
    let tint: Color

    @State private var hasAppeared = false

    private var clamped: Double { min(max(fraction, 0), 1) }

    /// Soft horizontal highlight across the fill, centered on the score number's row and
    /// kept fairly tight so the number sits precisely on its bright center line.
    private var highlightBand: LinearGradient {
        let center = BodyReadinessHeroMetrics.numberRowFromTop / BodyReadinessHeroMetrics.coloredHeight
        let halfSpread: CGFloat = 0.30
        return LinearGradient(
            stops: [
                .init(color: .clear, location: center - halfSpread),
                .init(color: .white.opacity(0.26), location: center),
                .init(color: .clear, location: center + halfSpread)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let target: CGFloat = hasAppeared ? CGFloat(clamped) : 0

            ZStack(alignment: .leading) {
                // "Unfilled" track = a much darker shade of the readiness color (the
                // tint laid over the page background) so the area past the score reads as
                // a deep version of today's color rather than a hard black block, while
                // still staying far dimmer than the filled side to keep the cut crisp.
                Color(.systemGroupedBackground)
                tint.opacity(0.28)

                // Filled color region: solid tint with a soft horizontal highlight band
                // centered on the score number's row, fading into the page at the fill
                // front via the mask below.
                ZStack {
                    Rectangle().fill(tint)

                    highlightBand
                        .blendMode(.screen)
                }
                .frame(width: target * width)
                .mask(
                    // A crisp cut at the score: hold full color almost to the fill front,
                    // then a short feather into the page so the percentage edge is clear.
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.98),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .animation(.interpolatingSpring(stiffness: 52, damping: 10), value: target)

                // Concentrate the color up top and melt the lower portion into the page
                // background — mirroring how the metric detail hero eases its tint into
                // the page — so the headline reads in white and the panel blends into
                // the cards below.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.42),
                        .init(color: Color(.systemGroupedBackground).opacity(0.85), location: 0.78),
                        .init(color: Color(.systemGroupedBackground), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: width, height: height)
        }
        .onAppear { hasAppeared = true }
    }
}
