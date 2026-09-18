//
//  ComplicationBorder.swift
//  BodyWatchWidgetExtension
//
//  The thin rounded border line every rectangular Body complication draws
//  around its slot, with the inner padding that keeps content off the line.
//

import SwiftUI

extension View {
    /// `verticalPadding` is for content that fills the slot's height (the bar
    /// complications); a vertically centered row needs none.
    func rectangularComplicationBorder(verticalPadding: CGFloat = 0) -> some View {
        self
            .padding(.horizontal, 7)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
            }
    }
}
