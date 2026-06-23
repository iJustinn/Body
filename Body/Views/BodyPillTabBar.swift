//
//  BodyPillTabBar.swift
//  Body
//

import SwiftUI

/// Custom floating "pill" tab bar that mimics the iOS 26 Liquid Glass look on
/// the iOS 18 deployment target: a translucent capsule with a neutral pill
/// highlight that slides behind the selected tab.
struct BodyPillTabBar: View {
    @Binding var selection: BodyMainTab
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BodyMainTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        selection = tab
                    }
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .frame(width: 90, height: 44)
                        .background {
                            if selection == tab {
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.16))
                                    .matchedGeometryEffect(id: "selected", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.accessibilityLabel)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .light ? 0.06 : 0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(colorScheme == .light ? 0.12 : 0.30), radius: 12, x: 0, y: 6)
        )
        .padding(.bottom, 4)
    }
}

#Preview {
    BodyPillTabBar(selection: .constant(.summary))
}
