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

    /// The narrowest trend column worth laying beside the folded page on a foldable's
    /// inner screen.
    static let foldableTrendsMinimumWidth: CGFloat = 280

    /// Whether Home's content, `contentWidth` wide on an iPhone, is a foldable's inner
    /// screen and splits into the trend column plus the folded `columnWidth` page.
    /// Decided from the measured width rather than the size class: a fold changes the
    /// size class at the start of the resize, several frames before the window reaches
    /// its new width, and laying out for the wrong posture in those frames flashed a
    /// page-wide ring and grid. No non-folding iPhone is this wide (Body is portrait-only
    /// on iPhone); iPad is the pad idiom and keeps its own layout.
    static func isFoldableSplit(contentWidth: CGFloat, columnWidth: CGFloat) -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && contentWidth >= columnWidth + 14 + foldableTrendsMinimumWidth
    }

    /// The inner screen's right column on a foldable: the folded outer screen's Home
    /// content width (its page less the 32 pt of horizontal padding) as last stored, so
    /// the hero and metric cards keep their folded size. Before the outer screen has
    /// been measured (a first launch while open) a phone-sized column stands in.
    static func foldedHomeColumnWidth(stored: Double) -> CGFloat {
        stored > 0 ? CGFloat(stored) : 344
    }

    /// The inner screen's right column for a hinge posture. Half open, the columns split
    /// at the hinge, which sits at the middle of the whole screen (the page is inset on
    /// its trailing side for the camera): the column runs from just past the hinge to the
    /// content's trailing edge. Flat, or before the hinge has reported, the column is the
    /// folded outer screen's width and the trend cards take everything else.
    static func foldableHomeColumnWidth(
        hinge: BodyHingeStatus,
        pageWidth: CGFloat,
        safeAreaLeading: CGFloat,
        safeAreaTrailing: CGFloat,
        foldedColumnWidth: CGFloat
    ) -> CGFloat {
        guard hinge == .partiallyOpen else { return foldedColumnWidth }
        let screenWidth = safeAreaLeading + pageWidth + safeAreaTrailing
        let hingeX = screenWidth / 2 - safeAreaLeading
        let contentTrailing = (pageWidth + min(pageWidth, homeContentWidth)) / 2 - 16
        return max(0, contentTrailing - hingeX - 7)
    }

    /// Where the foldable's right column is centered on a page of `pageWidth`: the home
    /// content column is capped and centered, and the folded column sits at its trailing edge.
    static func foldedHomeColumnCenterX(pageWidth: CGFloat, columnWidth: CGFloat) -> CGFloat {
        let contentWidth = min(pageWidth, homeContentWidth)
        let contentTrailing = (pageWidth + contentWidth) / 2 - 16
        return contentTrailing - columnWidth / 2
    }
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
