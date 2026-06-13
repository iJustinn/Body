//
//  WatchMetricRingView.swift
//  BodyWatchShared
//
//  The signature ring used by both the watch app cards and the complications:
//  a ~290° open ring with a gradient stroke, the value centered, and the
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

    /// Fraction of the circle left open at the bottom (centered on 6 o'clock).
    private let gap: Double = 0.20

    private var clampedFill: Double { min(max(fillFraction, 0), 1) }
    private var color: Color { Color(tint) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth = max(side * 0.11, 3)

            ZStack {
                // Track — gap rotated to the bottom.
                Circle()
                    .trim(from: gap / 2, to: 1 - gap / 2)
                    .stroke(color.opacity(0.20), style: strokeStyle(lineWidth))
                    .rotationEffect(.degrees(90))

                // Value arc.
                Circle()
                    .trim(from: gap / 2, to: gap / 2 + (1 - gap) * clampedFill)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.55), color]),
                            center: .center
                        ),
                        style: strokeStyle(lineWidth)
                    )
                    .rotationEffect(.degrees(90))

                // Centered value (+ optional unit).
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: side * 0.32, weight: .bold, design: .rounded))
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
                        .font(.system(size: side * 0.15, weight: .bold))
                        .foregroundStyle(color)
                        .frame(maxHeight: .infinity, alignment: .bottom)
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
