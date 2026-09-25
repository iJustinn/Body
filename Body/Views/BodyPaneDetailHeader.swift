//
//  BodyPaneDetailHeader.swift
//  Body
//

import SwiftUI

/// The header a detail page draws when it is shown in a foldable's left pane instead
/// of pushed: a glass Back chevron, the page title, and the page's own actions on the
/// trailing side. It stands in for the navigation bar, which on a foldable's inner
/// screen floats its buttons in the screen's top-right camera column, far from the pane.
struct BodyPaneDetailHeader<Trailing: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, onClose: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.onClose = onClose
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .modifier(BodyPaneGlassCircle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        // The inner screen has no top inset, so this holds the chevron clear of the
        // display's rounded corner, at the same spot as the Workouts detail's Back.
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

private struct BodyPaneGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// The mask a detail page's backdrop draws through: everything, or in a foldable's
/// pane a fade to clear over the trailing 72 pt, so the page blends into the tab
/// background beside it.
struct BodyPaneBackdropMask: View {
    let fadesTrailingEdge: Bool

    var body: some View {
        if fadesTrailingEdge {
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 72)
            }
            .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}
