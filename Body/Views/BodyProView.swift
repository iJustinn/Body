//
//  BodyProView.swift
//  Body
//

import SwiftUI
import UIKit

private enum BodyProPalette {
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.18)
}

struct BodyProView: View {
    @State private var statusMessage: String?

    private let features = BodyProFeature.defaultFeatures

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    BodyProHeroView()
                        .padding(.bottom, 12)

                    purchaseOptions
                    featureList
                    restoreSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("Body Pro")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var purchaseOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lifetime Access")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            BodyProPurchaseOptionCard {
                statusMessage = "Body Pro lifetime purchases are not available in this build."
            }
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Unlock All Pro Features")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 0) {
                ForEach(features) { feature in
                    BodyProFeatureRow(feature: feature)

                    if feature.id != features.last?.id {
                        Divider()
                            .padding(.leading, 68)
                    }
                }

                Divider()
                    .padding(.leading, 68)

                BodyProFutureUpdatesNote()
            }
            .bodyCardBackground(cornerRadius: 26)
        }
    }

    private var restoreSection: some View {
        VStack(spacing: 12) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Button {
                statusMessage = "Redeem Body Pro is not available in this build."
            } label: {
                Text("Redeem Pro")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(BodyProPalette.gold)

            Button {
                statusMessage = "Restore purchases is not available in this build."
            } label: {
                Text("Restore Purchases")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(BodyProPalette.gold)
        }
    }
}

private struct BodyProHeroView: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                BodyProConfetti()

                BodyProIconGlow()

                BodyProFlippableIcon()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 168)
        }
        .padding(.top, 6)
    }
}

private struct BodyProFlippableIcon: View {
    @AppStorage(BodyAppearancePreference.bodyProIconShowsBackKey) private var isShowingBack = false
    @State private var rotationDegrees = 0.0
    @State private var isFlipping = false

    var body: some View {
        Button(action: flipIcon) {
            iconImage
                .frame(width: 164, height: 104)
                .rotation3DEffect(
                    .degrees(rotationDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.58
                )
                .scaleEffect(isFlipping ? 1.03 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Body Pro icon")
        .accessibilityHint("Flips the icon")
    }

    private var iconImage: some View {
        Image(BodyAppearancePreference.bodyProIconAssetName(showsBack: isShowingBack))
            .resizable()
            .scaledToFit()
    }

    private func flipIcon() {
        guard !isFlipping else {
            return
        }

        playFlipHaptic()

        let nextIsShowingBack = !isShowingBack
        isFlipping = true

        withAnimation(.easeIn(duration: 0.18)) {
            rotationDegrees = 86
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isShowingBack = nextIsShowingBack
            rotationDegrees = -86

            withAnimation(.interpolatingSpring(stiffness: 230, damping: 18)) {
                rotationDegrees = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            isFlipping = false
        }
    }

    private func playFlipHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
    }
}

private struct BodyProIconGlow: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            BodyProPalette.gold.opacity(0.28),
                            BodyProPalette.gold.opacity(0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 116
                    )
                )
                .frame(width: 252, height: 140)
                .blur(radius: 18)

            Ellipse()
                .fill(BodyProPalette.gold.opacity(0.08))
                .frame(width: 180, height: 70)
                .blur(radius: 22)
                .offset(y: 18)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BodyProConfetti: View {
    private let items: [(icon: String, color: Color, x: CGFloat, y: CGFloat, rotation: Double, size: CGFloat)] = [
        ("diamond.fill", .green, -118, -38, 18, 11),
        ("sparkle", .blue, -82, 22, -12, 20),
        ("circle.fill", .pink, -124, 44, 0, 9),
        ("sparkles", .purple, 104, -24, 18, 25),
        ("diamond.fill", .orange, 96, 38, 24, 10),
        ("circle.fill", .red, -42, 58, 0, 8),
        ("diamond.fill", .blue, 48, -58, 20, 9)
    ]

    var body: some View {
        ZStack {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]

                Image(systemName: item.icon)
                    .font(.system(size: item.size, weight: .bold))
                    .foregroundColor(item.color)
                    .rotationEffect(.degrees(item.rotation))
                    .offset(x: item.x, y: item.y)
            }
        }
    }
}

private struct BodyProPurchaseOptionCard: View {
    let onChoose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Lifetime")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("One purchase for lifetime Body Pro access.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Text("$5.99")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: 66, alignment: .trailing)

            Button(action: onChoose) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundColor(BodyProPalette.gold)
            .background(Circle().fill(BodyProPalette.gold.opacity(0.14)))
            .accessibilityLabel("Choose Lifetime")
        }
        .padding(16)
        .bodyCardBackground(cornerRadius: 24)
    }
}

private struct BodyProFeatureRow: View {
    let feature: BodyProFeature

    var body: some View {
        HStack(spacing: 14) {
            BodyProFeatureIconTile(iconName: feature.iconName, color: BodyProPalette.gold)

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(feature.detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            BodyProFeatureCheckmark()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct BodyProFeatureIconTile: View {
    let iconName: String
    let color: Color

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 21, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.14))
            )
    }
}

private struct BodyProFeatureCheckmark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 23, weight: .semibold))
            .foregroundColor(BodyProPalette.gold)
    }
}

private struct BodyProFeature: Identifiable {
    let id: String
    let title: String
    let detail: String
    let iconName: String

    static let defaultFeatures = [
        BodyProFeature(
            id: "six-month-year-charts",
            title: "Six-Month and Year Charts",
            detail: "Open six-month and year views for metrics charts.",
            iconName: "chart.line.uptrend.xyaxis"
        ),
        BodyProFeature(
            id: "body-widgets",
            title: "Body Widgets",
            detail: "Use Body widgets to keep workout and metric context on the Home Screen.",
            iconName: "square.grid.2x2.fill"
        )
    ]
}

private struct BodyProFutureUpdatesNote: View {
    var body: some View {
        HStack(spacing: 14) {
            BodyProFeatureIconTile(iconName: "bolt.fill", color: BodyProPalette.gold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Future Pro Updates")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("More Body Pro features will be added in future updates.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            BodyProFeatureCheckmark()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    NavigationStack {
        BodyProView()
    }
}
