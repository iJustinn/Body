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
                BodyPaneHeaderIcon(systemName: "chevron.backward")
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

/// A pane header action drawn as a 44 pt glass circle, the way a navigation bar draws
/// its toolbar buttons. The header has no navigation bar, so its actions draw their own.
struct BodyPaneHeaderIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .modifier(BodyPaneGlass(shape: Circle()))
            .contentShape(Circle())
    }
}

/// A pane header text action drawn as a 44 pt tall glass capsule.
struct BodyPaneHeaderText: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .modifier(BodyPaneGlass(shape: Capsule()))
            .contentShape(Capsule())
    }
}

private struct BodyPaneGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    /// Masks a detail page's backdrop in a foldable's pane with a fade to clear over the
    /// trailing 72 pt, so the page blends into the tab background beside it. Outside a
    /// pane nothing fades, so the backdrop goes unmasked.
    @ViewBuilder
    func bodyPaneBackdropFade(_ fades: Bool) -> some View {
        if fades {
            mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 72)
                }
                .ignoresSafeArea()
            }
        } else {
            self
        }
    }
}
