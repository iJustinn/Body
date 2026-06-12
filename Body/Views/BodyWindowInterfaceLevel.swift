//
//  BodyWindowInterfaceLevel.swift
//  Body
//

import SwiftUI
import UIKit

/// Pins the hosting window's interface level to `.base`.
///
/// When iPadOS presents the app in a window (Stage Manager, Split View,
/// Slide Over) the system raises the trait collection to `.elevated`, which
/// lightens every semantic background color (e.g. `systemGroupedBackground`,
/// `secondarySystemBackground`) by one step and makes the UI look washed-out
/// gray. Forcing `.base` keeps the windowed appearance identical to full screen.
private final class BaseInterfaceLevelView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        window?.traitOverrides.userInterfaceLevel = .base
    }
}

private struct BaseInterfaceLevelApplier: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        BaseInterfaceLevelView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    func bodyBaseInterfaceLevel() -> some View {
        background(BaseInterfaceLevelApplier())
    }
}
