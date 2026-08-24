//
//  BodyCardFadeIn.swift
//  Body
//

import SwiftUI

/// Fades a card in the first time it is rendered. Cards that only exist once their
/// data lands — the workout detail charts, a metric's threshold warnings — otherwise
/// pop into the page fully drawn the moment the load returns.
///
/// The fade is opacity only: the card takes its final space immediately, so nothing
/// below it slides while the fade runs. Reduce Motion lands it opaque on the first
/// frame instead.
struct BodyCardFadeInModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The curve the card fades on. Matches the detail pages' other content fades.
    var duration: Double = 0.35
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    /// Fades this card in on its first render — see `BodyCardFadeInModifier`.
    func bodyCardFadeIn(duration: Double = 0.35) -> some View {
        modifier(BodyCardFadeInModifier(duration: duration))
    }
}
