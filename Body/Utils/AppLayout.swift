//
//  AppLayout.swift
//  Body
//

import SwiftUI

/// Shared layout metrics for adapting Body's single-column UI to wide canvases
/// (iPad landscape, Split View, Stage Manager) without stretching content.
enum AppLayout {
    /// Maximum width of a screen's primary content column. On canvases wider than
    /// this the column is centered with the grouped background filling the sides,
    /// keeping cards at a comfortable reading width instead of stretching edge to edge.
    static let readableContentWidth: CGFloat = 640

    /// Maximum width of the home dashboard, which uses a wider two-column (metrics +
    /// trends) layout than the single-column reading pages.
    static let homeContentWidth: CGFloat = 880
}

extension View {
    /// Caps the view at `maxWidth` and centers it within the available width.
    ///
    /// On narrow canvases (iPhone, compact multitasking widths) the content simply
    /// fills the available width, matching the prior single-column layout. On wider
    /// canvases it stops growing at `maxWidth` and centers, with the surrounding
    /// background filling the remaining space.
    func readableContentColumn(maxWidth: CGFloat = AppLayout.readableContentWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
