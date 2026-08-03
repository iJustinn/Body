//
//  BodyCardBackground.swift
//  Body
//

import SwiftUI

struct BodyCardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    /// Renders the translucent "glass" fill used by the trend-range pills
    /// (`bodyTrendRangeTabBackgroundOnGradient`) instead of the solid card fill.
    var translucent: Bool = false
    /// Fill opacity for the translucent variant. Home preview cards use a higher value so
    /// they read against the colored home backdrop; detail cards keep the default.
    var translucentFillOpacity: Double = 0.06

    private var fillColor: Color {
        if translucent {
            return Color.primary.opacity(translucentFillOpacity)
        }
        return colorScheme == .light ? Color(.systemBackground) : Color(.secondarySystemBackground)
    }

    private var shadowColor: Color {
        if translucent {
            return .clear
        }
        return Color.black.opacity(colorScheme == .light ? 0.07 : 0)
    }

    private var strokeColor: Color {
        if translucent {
            return Color.primary.opacity(translucentFillOpacity + 0.04)
        }
        return Color.primary.opacity(colorScheme == .light ? 0.04 : 0)
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
                    .shadow(
                        color: shadowColor,
                        radius: 14,
                        x: 0,
                        y: 6
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}

private enum BodySheetBackgroundStyle {
    /// Black wash over the iOS 26 Liquid Glass sheet background so sheets read as tinted
    /// glass instead of fully clear. The app is dark-only, so this is unconditional.
    static let glassTintOpacity = 0.50
}

extension View {
    /// Standard sheet backdrop: a black wash over the iOS 26 Liquid Glass, or the opaque
    /// base color on older systems (which have no glass to tint).
    func bodySheetBackground(_ base: Color = Color(.systemGroupedBackground)) -> some View {
        background {
            Group {
                if #available(iOS 26.0, *) {
                    Color.black.opacity(BodySheetBackgroundStyle.glassTintOpacity)
                } else {
                    base
                }
            }
            .ignoresSafeArea()
        }
    }

    func bodyCardBackground(cornerRadius: CGFloat = 30, translucent: Bool = false, translucentFillOpacity: Double = 0.06) -> some View {
        modifier(BodyCardBackgroundModifier(cornerRadius: cornerRadius, translucent: translucent, translucentFillOpacity: translucentFillOpacity))
    }

    func bodyTrendRangeTabBackground(isSelected: Bool, colorScheme: ColorScheme) -> some View {
        background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(colorScheme == .light ? 0.12 : 0.22)
                        : (colorScheme == .light ? Color(.systemBackground) : Color(.secondarySystemBackground))
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .light ? 0.045 : 0),
                    radius: 8,
                    x: 0,
                    y: 3
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(colorScheme == .light ? 0.05 : 0),
                    lineWidth: 1
                )
        )
    }

    /// Translucent "glass" pills that float over the metric hero gradient, used by
    /// the `.onGradient` appearance of `BodyHealthTrendRangeSelector`. Built on
    /// `.primary` so they adapt: faint dark pills on the light-mode wash, faint
    /// light pills on the dark-mode wash.
    func bodyTrendRangeTabBackgroundOnGradient(isSelected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.16 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(isSelected ? 0.24 : 0.10), lineWidth: 1)
        )
    }
}
