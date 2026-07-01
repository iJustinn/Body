//
//  BodyGlassChip.swift
//  Body
//

import SwiftUI

/// A rounded-rect "glass chip" backing for the colored workout surfaces
/// (calendar day squares, type-breakdown bars). Flat by design to match the
/// app's glass language: the workout color as a translucent flat fill with an
/// optional thin white edge rim — no material blur, gradient, or specular
/// sheen. `fillOpacity` tunes translucency; `showsRim` toggles the rim (the
/// breakdown bars keep it; the calendar squares drop it).
struct BodyGlassChip: View {
    let color: Color
    let cornerRadius: CGFloat
    var fillOpacity: Double = 0.85
    var showsRim: Bool = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(color.opacity(fillOpacity))
            .overlay {
                if showsRim {
                    shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
            }
    }
}
