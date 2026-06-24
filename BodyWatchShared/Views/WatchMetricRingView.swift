//
//  WatchMetricRingView.swift
//  BodyWatchShared
//
//  The signature ring used by both the watch app cards and the complications:
//  a ~270° open ring with a solid stroke, the value centered, and the
//  metric's SF Symbol seated in the bottom gap.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchMetricRingView: View {
    let fillFraction: Double
    let value: String
    let unit: String
    let symbolName: String
    let tint: WatchMetricColor
    var showsUnit: Bool = true
    var showsGlyph: Bool = true
    var valueFontScale: Double = 0.40

    /// Fraction of the circle left open at the bottom (centered on 6 o'clock).
    private let gap: Double = 0.25

    private var clampedFill: Double { min(max(fillFraction, 0), 1) }
    private var color: Color { Color(tint) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth = max(side * 0.16, 4)

            ZStack {
                // Track — gap rotated to the bottom. Inset by half the stroke so
                // the thick round caps render in full (the circular complication
                // clips to its bounds).
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: gap / 2, to: 1 - gap / 2)
                    .stroke(color.opacity(0.20), style: strokeStyle(lineWidth))
                    .rotationEffect(.degrees(90))

                // Value arc — solid color so the round caps read as clean,
                // uniform dome tips (an angular gradient smears the cap).
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: gap / 2, to: gap / 2 + (1 - gap) * clampedFill)
                    .stroke(color, style: strokeStyle(lineWidth))
                    .rotationEffect(.degrees(90))

                // Centered value (+ optional unit).
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: side * valueFontScale, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    if showsUnit, !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: side * 0.15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, lineWidth)

                // Glyph in the bottom gap.
                if showsGlyph {
                    Image(systemName: symbolName)
                        .font(.system(size: side * 0.22, weight: .bold))
                        .foregroundStyle(color)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, side * 0.05)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func strokeStyle(_ lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }
}

extension Color {
    init(_ watch: WatchMetricColor) {
        self.init(red: watch.red, green: watch.green, blue: watch.blue)
    }
}
