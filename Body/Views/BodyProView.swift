//
//  BodyProView.swift
//  Body
//

import RevenueCatUI
import StoreKit
import SwiftUI
import UIKit

enum BodyProPalette {
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.18)
    /// The lighter top of the purchase button's gradient.
    static let goldHighlight = Color(red: 1.0, green: 0.86, blue: 0.47)
}

/// Legal links every subscription paywall must carry. Body uses Apple's standard license
/// agreement as its Terms of Use, as set in App Store Connect.
enum BodyProLinks {
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://docs.ijustinz.com/body/privacy")!
}

struct BodyProView: View {
    /// Adds a close button. The paywall sheets presented from locked controls need one; the
    /// Settings entry pushes this page and gets the back button instead.
    var showsCloseButton = false
    /// Set when the paywall is a step in a flow the app started (the end of onboarding, the
    /// one-time introduction after an update) rather than a page the user opened. The page
    /// then always offers Continue for Free, its close button continues too, and a purchase
    /// carries on by itself once the owned card has had a moment on screen.
    var onContinue: (() -> Void)?

    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Yearly first: it is the best value and the only plan with a free trial.
    @State private var selectedPlan: BodyProPlan = .yearly
    @State private var showRedeemSheet = false
    @State private var showCustomerCenter = false

    private let features = BodyProFeature.defaultFeatures

    private var isPro: Bool { proStore?.isPro ?? false }
    private var products: [BodyProPlan: BodyProProduct] { proStore?.products ?? [:] }
    private var productLoadFailed: Bool { proStore?.productLoadFailed ?? false }
    private var purchaseState: BodyProStore.PurchaseState { proStore?.purchaseState ?? .idle }

    /// `false` only during the first entitlement resolve. Until it flips, the purchase
    /// section shows a "checking" state so an existing purchaser never sees a buy card
    /// before their entitlement loads. Treated as resolved when there is no store.
    private var hasResolved: Bool { proStore?.hasResolved ?? true }

    /// A purchase, restore, or pending approval is in flight — or a completed purchase is
    /// still awaiting its entitlement — so the (re-)purchase action is disabled: it can't
    /// overlap, double-fire while awaiting Ask-to-Buy approval, or re-charge a buyer whose
    /// completed purchase just hasn't unlocked yet (Restore is that state's recovery path).
    private var isPurchaseFlowActive: Bool {
        switch purchaseState {
        case .purchasing, .restoring, .pending, .completedNotUnlocked:
            return true
        case .idle, .failed:
            return false
        }
    }

    /// Restore/Redeem only need to guard against an in-flight purchase or restore — a
    /// `.pending` Ask-to-Buy approval doesn't touch either of those flows, so both stay
    /// enabled in that state (the buyer may still want to restore a different purchase or
    /// redeem a code while waiting on approval).
    private var isRestoreOrRedeemDisabled: Bool {
        switch purchaseState {
        case .purchasing, .restoring:
            return true
        case .idle, .pending, .completedNotUnlocked, .failed:
            return false
        }
    }

    private var statusText: String? {
        switch purchaseState {
        case .pending:
            return String(localized: "Your purchase is pending approval. Body Pro unlocks once it's approved.")
        case .failed(let message):
            return message
        default:
            return nil
        }
    }

    /// The plan the purchase button buys: the chosen one while the store offers it,
    /// otherwise the first plan that loaded.
    private var activePlan: BodyProPlan? {
        if products[selectedPlan] != nil {
            return selectedPlan
        }
        return BodyProPlan.allCases.first { products[$0] != nil }
    }

    private var activeProduct: BodyProProduct? {
        activePlan.flatMap { products[$0] }
    }

    /// Plans are on sale: the entitlement resolved to locked, no completed purchase is
    /// waiting on its entitlement, and at least one product loaded.
    private var offersPlans: Bool {
        !isPro && hasResolved && purchaseState != .completedNotUnlocked && activePlan != nil
    }

    /// Which lifetime product the Lifetime card shows. It follows the Just Me / Family switch,
    /// and falls back to whichever of the two loaded.
    private var lifetimeCardPlan: BodyProPlan? {
        if selectedPlan == .lifetimeFamily, products[.lifetimeFamily] != nil {
            return .lifetimeFamily
        }
        if products[.lifetime] != nil {
            return .lifetime
        }
        return products[.lifetimeFamily] != nil ? .lifetimeFamily : nil
    }

    private var isLifetimeSelected: Bool {
        activePlan == .lifetime || activePlan == .lifetimeFamily
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 30) {
                BodyProHeroView()

                planSection

                if offersPlans, let plan = activePlan, let product = activeProduct, let trial = product.freeTrial {
                    BodyProTrialTimeline(trial: trial, renewalText: renewalText(plan: plan, product: product))
                }

                featureList
                restoreSection
                BodyProLegalFooter()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .readableContentColumn()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // In a flow the bar stays up without plans too, so Continue for Free is never
            // missing (still checking, or the products failed to load).
            if offersPlans || onContinue != nil {
                purchaseBar
            }
        }
        .background {
            BodyProBackdrop()
        }
        .navigationTitle("Body Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton || onContinue != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let onContinue {
                            onContinue()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: selectedPlan)
        .onChange(of: isPro) { _, unlocked in
            guard unlocked else { return }
            BodyConfirmationHaptics.play(.success)
            if let onContinue {
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    onContinue()
                }
            }
        }
        .onChange(of: purchaseState) { _, state in
            if case .failed = state { BodyConfirmationHaptics.play(.error) }
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isPro {
                BodyProOwnedCard()
            } else {
                Text("Choose Your Plan")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                if !hasResolved {
                    BodyProCheckingCard()
                } else if purchaseState == .completedNotUnlocked {
                    // A completed purchase awaiting its entitlement must not re-offer the buy
                    // cards (an enabled purchase button right after "your purchase completed"
                    // reads as a double-charge invitation) — the recovery path is Restore.
                    BodyProVerifyingPurchaseCard()
                } else if activePlan != nil {
                    planCards
                } else if productLoadFailed {
                    BodyProUnavailableCard {
                        Task { await proStore?.loadProducts() }
                    }
                } else {
                    BodyProLoadingPriceCard()
                }
            }
        }
    }

    private var planCards: some View {
        VStack(spacing: 16) {
            if let yearly = products[.yearly] {
                let savingsPercent = products[.monthly].flatMap { yearly.yearlySavingsPercent(comparedWith: $0) }

                BodyProPlanCard(
                    title: "Yearly",
                    detail: yearly.displayPricePerMonth.map { String(localized: "\($0) per month, billed yearly") }
                        ?? String(localized: "Cancel anytime"),
                    price: yearly.displayPrice,
                    priceCaption: "per year",
                    savingsPercent: savingsPercent,
                    // Best Value only where Yearly really is cheaper than twelve months.
                    ribbon: yearly.freeTrial.map { String(localized: "\($0.localizedDuration) free") }
                        ?? (savingsPercent != nil ? String(localized: "Best Value") : nil),
                    isSelected: activePlan == .yearly
                ) {
                    selectedPlan = .yearly
                }
            }

            if let monthly = products[.monthly] {
                BodyProPlanCard(
                    title: "Monthly",
                    detail: monthly.freeTrial.map { String(localized: "\($0.localizedDuration) free") }
                        ?? String(localized: "Cancel anytime"),
                    price: monthly.displayPrice,
                    priceCaption: "per month",
                    isSelected: activePlan == .monthly
                ) {
                    selectedPlan = .monthly
                }
            }

            if let lifetimePlan = lifetimeCardPlan, let lifetime = products[lifetimePlan] {
                BodyProPlanCard(
                    title: "Lifetime",
                    detail: lifetimePlan == .lifetimeFamily
                        ? String(localized: "Share with up to 5 family members")
                        : String(localized: "Pay once, keep Pro forever"),
                    price: lifetime.displayPrice,
                    priceCaption: "one time",
                    isSelected: isLifetimeSelected
                ) {
                    if !isLifetimeSelected {
                        selectedPlan = lifetimePlan
                    }
                } accessory: {
                    // The switch only matters once Lifetime is chosen, and only when both
                    // lifetime products loaded.
                    if isLifetimeSelected, products[.lifetime] != nil, products[.lifetimeFamily] != nil {
                        BodyProLifetimeSwitch(selection: $selectedPlan)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// The sticky purchase button, with the price disclosure App Review expects right
    /// beside it: trial length, then the renewal price and period. In a flow it also
    /// carries the way out, Continue for Free.
    private var purchaseBar: some View {
        VStack(spacing: 9) {
            if offersPlans, let plan = activePlan, let product = activeProduct {
                purchaseControls(plan: plan, product: product)
            }

            if let onContinue {
                Button(action: onContinue) {
                    Text("Continue for Free")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(purchaseState == .purchasing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .readableContentColumn()
        .background {
            // Content scrolls under the bar: it fades out just above the button, and the
            // bar itself is solid so nothing shows through behind the price terms.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)

                Color.black
            }
            .padding(.top, -28)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func purchaseControls(plan: BodyProPlan, product: BodyProProduct) -> some View {
        // Pending approval or a failure lands here, beside the button that caused it,
        // rather than below the feature list.
        if let statusText {
            Text(statusText)
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }

        Button {
            Task { await proStore?.purchase(plan) }
        } label: {
            ZStack {
                Text(purchaseButtonTitle(plan: plan, product: product))
                    .opacity(purchaseState == .purchasing ? 0 : 1)

                if purchaseState == .purchasing {
                    ProgressView()
                        .tint(.black)
                }
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [BodyProPalette.goldHighlight, BodyProPalette.gold],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .shadow(color: BodyProPalette.gold.opacity(0.3), radius: 16, x: 0, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPurchaseFlowActive)
        .opacity(isPurchaseFlowActive && purchaseState != .purchasing ? 0.55 : 1)

        Text(purchaseCaption(plan: plan, product: product))
            .font(.system(.footnote, design: .rounded))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func purchaseButtonTitle(plan: BodyProPlan, product: BodyProProduct) -> LocalizedStringKey {
        if product.freeTrial != nil {
            return "Start Free Trial"
        }
        return plan.isSubscription ? "Subscribe" : "Unlock Lifetime"
    }

    private func purchaseCaption(plan: BodyProPlan, product: BodyProProduct) -> String {
        switch plan {
        case .lifetime:
            return String(localized: "One payment of \(product.displayPrice). No subscription.")
        case .lifetimeFamily:
            return String(localized: "One payment of \(product.displayPrice), shared with your family.")
        case .yearly, .monthly:
            let renewal = renewalText(plan: plan, product: product)
            if let trial = product.freeTrial {
                return String(localized: "\(trial.localizedDuration) free, then \(renewal). Cancel anytime.")
            }
            return String(localized: "\(renewal). Renews automatically, cancel anytime.")
        }
    }

    /// The store price with its period ("… per year"): what a subscription costs each
    /// period once any trial is over.
    private func renewalText(plan: BodyProPlan, product: BodyProProduct) -> String {
        plan == .monthly
            ? String(localized: "\(product.displayPrice) per month")
            : String(localized: "\(product.displayPrice) per year")
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
            .bodyCardBackground(cornerRadius: 26, translucent: true)
        }
    }

    private var restoreSection: some View {
        VStack(spacing: 12) {
            // While plans are on sale the purchase bar shows this instead.
            if !offersPlans, let statusText {
                Text(statusText)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Plain text, not buttons: recovery paths that shouldn't compete with
            // the purchase button.
            HStack(spacing: 8) {
                Button {
                    showRedeemSheet = true
                } label: {
                    Text("Redeem")
                        .foregroundColor(BodyProPalette.gold)
                        // Each label carries its own tap target: text this size is
                        // well under the 44pt minimum on its own.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRestoreOrRedeemDisabled)

                Text(verbatim: "·")
                    .foregroundColor(.secondary)

                Button {
                    Task { await proStore?.restore() }
                } label: {
                    Text("Restore")
                        .foregroundColor(BodyProPalette.gold)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRestoreOrRedeemDisabled)

                Text(verbatim: "·")
                    .foregroundColor(.secondary)

                // RevenueCat Customer Center: restore, manage, and get help with purchases.
                Button {
                    showCustomerCenter = true
                } label: {
                    Text("Manage")
                        .foregroundColor(BodyProPalette.gold)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRestoreOrRedeemDisabled)
            }
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .opacity(isRestoreOrRedeemDisabled ? 0.45 : 1)
            .frame(maxWidth: .infinity)
        }
        .offerCodeRedemption(isPresented: $showRedeemSheet) { _ in
            // Sync with the App Store so RevenueCat ingests the redeemed transaction, then
            // re-resolve the entitlement. Covers subscription offer codes and the lifetime
            // purchase's one-time codes alike.
            Task { await proStore?.refreshAfterRedemption() }
        }
        .sheet(isPresented: $showCustomerCenter) {
            CustomerCenterView()
        }
    }
}

/// Black with a warm gold glow falling from the top, so the page reads as premium without
/// competing with the plan cards.
private struct BodyProBackdrop: View {
    var body: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [BodyProPalette.gold.opacity(0.2), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

private struct BodyProHeroView: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                BodyProConfetti()

                BodyProIconGlow()

                BodyProFlippableIcon()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)

            VStack(spacing: 8) {
                Text("See the Full Picture")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Unlock every chart, data source, and share style in Body.")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            BodyProHighlights()
                .padding(.top, 6)
        }
        .padding(.top, 4)
    }
}

/// Four headline benefits, scannable before the plans. The full list sits further down.
private struct BodyProHighlights: View {
    private let items: [(iconName: String, title: LocalizedStringKey)] = [
        ("chart.line.uptrend.xyaxis", "Year Charts"),
        ("square.stack.3d.up.fill", "More Sources"),
        ("move.3d", "3D Routes"),
        ("square.grid.2x2.fill", "Widgets")
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                VStack(spacing: 7) {
                    Image(systemName: items[index].iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(BodyProPalette.gold)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(BodyProPalette.gold.opacity(0.14)))

                    Text(items[index].title)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BodyProFlippableIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

        guard !reduceMotion else {
            isShowingBack = nextIsShowingBack
            return
        }

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
        guard BodyHaptics.isMasterEnabled else { return }
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

struct BodyProConfetti: View {
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

/// One selectable plan. The whole row is the tap target; `accessory` renders below it
/// inside the same card (the Lifetime card's Just Me / Family switch).
private struct BodyProPlanCard<Accessory: View>: View {
    let title: LocalizedStringKey
    let detail: String
    let price: String
    let priceCaption: LocalizedStringKey
    var savingsPercent: Int?
    /// Gold tag on the card's top edge ("7 days free", "Best Value").
    var ribbon: String?
    let isSelected: Bool
    let onSelect: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 14) {
                    BodyProSelectionMark(isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            if let savingsPercent {
                                Text("Save \((Double(savingsPercent) / 100).formatted(.percent))")
                                    .font(.system(.caption, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(BodyProPalette.gold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(BodyProPalette.gold.opacity(0.16)))
                            }
                        }

                        Text(detail)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(priceCaption)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            accessory()
        }
        .padding(16)
        .background(cardShape.fill(isSelected ? BodyProPalette.gold.opacity(0.1) : Color.primary.opacity(0.06)))
        .overlay(
            cardShape.strokeBorder(
                isSelected ? BodyProPalette.gold : Color.primary.opacity(0.1),
                lineWidth: isSelected ? 2 : 1
            )
        )
        .overlay(alignment: .topTrailing) {
            if let ribbon {
                Text(ribbon)
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.heavy)
                    .textCase(.uppercase)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(BodyProPalette.gold))
                    .offset(x: -16, y: -10)
            }
        }
        .bodySelectionHaptics(isSelected: isSelected)
    }
}

extension BodyProPlanCard where Accessory == EmptyView {
    init(
        title: LocalizedStringKey,
        detail: String,
        price: String,
        priceCaption: LocalizedStringKey,
        savingsPercent: Int? = nil,
        ribbon: String? = nil,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.init(
            title: title,
            detail: detail,
            price: price,
            priceCaption: priceCaption,
            savingsPercent: savingsPercent,
            ribbon: ribbon,
            isSelected: isSelected,
            onSelect: onSelect,
            accessory: { EmptyView() }
        )
    }
}

private struct BodyProSelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? BodyProPalette.gold : Color.primary.opacity(0.25), lineWidth: 2)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(BodyProPalette.gold))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// Just Me or Family for the lifetime purchase. The Family product has Family Sharing on,
/// so one purchase unlocks Pro for everyone in the buyer's family group.
private struct BodyProLifetimeSwitch: View {
    @Binding var selection: BodyProPlan

    var body: some View {
        HStack(spacing: 4) {
            option(.lifetime, title: "Just Me", iconName: "person.fill")
            option(.lifetimeFamily, title: "Family", iconName: "person.3.fill")
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func option(_ plan: BodyProPlan, title: LocalizedStringKey, iconName: String) -> some View {
        let isOn = selection == plan

        return Button {
            selection = plan
        } label: {
            Label(title, systemImage: iconName)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(isOn ? .black : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(isOn ? BodyProPalette.gold : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// What happens between starting the trial and the first payment, with the real date, so
/// nobody starts a trial unsure when they will be charged.
private struct BodyProTrialTimeline: View {
    let trial: BodyProFreeTrial
    let renewalText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How Your Free Trial Works")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 0) {
                BodyProTimelineStep(
                    iconName: "lock.open.fill",
                    title: Text("Today"),
                    detail: Text("Get full access to every Pro feature."),
                    continues: true
                )

                BodyProTimelineStep(
                    iconName: "creditcard.fill",
                    title: Text(trial.endDate(from: .now), format: .dateTime.month(.abbreviated).day()),
                    detail: Text("Billing starts at \(renewalText). Cancel at least 24 hours before and you won't be charged."),
                    continues: false
                )
            }
            .padding(16)
            .bodyCardBackground(cornerRadius: 24, translucent: true)
        }
    }
}

private struct BodyProTimelineStep: View {
    let iconName: String
    let title: Text
    let detail: Text
    /// Draws the connector down to the next step.
    let continues: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 34, height: 34)
                .background(Circle().fill(BodyProPalette.gold))

            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                detail
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
            .padding(.bottom, continues ? 20 : 0)

            Spacer(minLength: 0)
        }
        .background(alignment: .topLeading) {
            if continues {
                Rectangle()
                    .fill(BodyProPalette.gold.opacity(0.35))
                    .frame(width: 2)
                    .padding(.top, 34)
                    .padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Terms, privacy, and the auto-renewal terms App Review requires on a subscription paywall.
private struct BodyProLegalFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Link(destination: BodyProLinks.termsOfUse) {
                    Text("Terms of Use")
                        // On the label itself: Link would otherwise draw it in the tint.
                        .foregroundColor(.secondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }

                Text(verbatim: "·")
                    .foregroundColor(.secondary)

                Link(destination: BodyProLinks.privacyPolicy) {
                    Text("Privacy Policy")
                        .foregroundColor(.secondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .font(.system(.footnote, design: .rounded))
            .fontWeight(.semibold)

            Text("Payment is charged to your Apple Account when you confirm the purchase, or when a free trial ends. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel anytime in your Apple Account settings.")
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BodyProCheckingCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ProgressView()

            Text("Checking your purchases…")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(cornerRadius: 24, translucent: true)
    }
}

private struct BodyProLoadingPriceCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ProgressView()

            Text("Loading price…")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(cornerRadius: 24, translucent: true)
    }
}

private struct BodyProUnavailableCard: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("Body Pro is temporarily unavailable.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Spacer(minLength: 8)

            Button(action: onRetry) {
                Text("Retry")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(BodyProPalette.gold)
        }
        .padding(16)
        .bodyCardBackground(cornerRadius: 24, translucent: true)
    }
}

private struct BodyProVerifyingPurchaseCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.seal.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(BodyProPalette.gold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Purchase Completed")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Body Pro isn't unlocked yet. Try Restore Purchases below, or contact support if this persists.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(16)
        .bodyCardBackground(cornerRadius: 24, translucent: true)
    }
}

private struct BodyProOwnedCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(BodyProPalette.gold)

            VStack(alignment: .leading, spacing: 4) {
                Text("You have Body Pro")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Thanks for your support. All Pro features are unlocked.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(16)
        .bodyCardBackground(cornerRadius: 24, translucent: true)
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

    /// Grouped by what they touch — metric depth, data sources, share cards, then
    /// the rest of the app — so neighbouring rows read as one subject.
    static let defaultFeatures = [
        // Metric depth: how far back the charts and day views reach.
        BodyProFeature(
            id: "longer-range-charts",
            title: String(localized: "Longer-Range Charts"),
            detail: String(localized: "Open month, six-month, and year views for metric charts."),
            iconName: "chart.line.uptrend.xyaxis"
        ),
        BodyProFeature(
            id: "full-day-history",
            title: String(localized: "Full Day History"),
            detail: String(localized: "Open any past day in the metric and sleep day views, beyond the most recent three."),
            iconName: "calendar"
        ),

        // Where the numbers come from.
        BodyProFeature(
            id: "secondary-source",
            title: String(localized: "Secondary Data Source"),
            detail: String(localized: "Compare a secondary data source on your metric charts."),
            iconName: "square.stack.3d.up.fill"
        ),
        BodyProFeature(
            id: "custom-sources",
            title: String(localized: "Custom Data Sources"),
            detail: String(localized: "Create your own sources that merge several data sources into one."),
            iconName: "heart.fill"
        ),

        // Workout share cards.
        BodyProFeature(
            id: "photo-share",
            title: String(localized: "Photo Activity Share"),
            detail: String(localized: "Use your own photos as the background of workout share cards."),
            iconName: "photo.fill"
        ),
        BodyProFeature(
            id: "video-share",
            title: String(localized: "Video Activity Share"),
            detail: String(localized: "Use your own videos as the background of workout share cards."),
            iconName: "video.fill"
        ),
        BodyProFeature(
            id: "three-d-route-share",
            title: String(localized: "3D Route Share"),
            detail: String(localized: "Share workout cards with the route drawn as a 3D elevation ribbon on any background."),
            iconName: "move.3d"
        ),
        BodyProFeature(
            id: "share-ratios",
            title: String(localized: "Share Card Sizes"),
            detail: String(localized: "Export workout share cards as 16:9, 3:4, 4:3, or square, or as a long image of the whole workout."),
            iconName: "aspectratio"
        ),
        BodyProFeature(
            id: "share-metrics",
            title: String(localized: "Share Card Metrics"),
            detail: String(localized: "Choose which metrics your workout share card shows."),
            iconName: "list.bullet.rectangle.portrait"
        ),

        // Elsewhere in the app.
        BodyProFeature(
            id: "custom-backgrounds",
            title: String(localized: "Custom Backgrounds"),
            detail: String(localized: "Personalize the app background with your own color mixes and saved profiles."),
            iconName: "paintpalette.fill"
        ),
        BodyProFeature(
            id: "body-widgets",
            title: String(localized: "Body Widgets"),
            detail: String(localized: "Use Body widgets to keep workout and metric context on the Home Screen."),
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

#if DEBUG
/// Scripted store for the previews: every plan loads at US prices, with the yearly trial
/// still available, and the entitlement resolves to `isPro`.
private struct BodyProPreviewPurchasesClient: BodyPurchasesClient {
    var isPro = false
    let entitlementUpdates: AsyncStream<Bool> = AsyncStream { $0.finish() }

    /// A store already showing this client's state, since the preview snapshot is taken
    /// before the launch tasks could resolve it.
    @MainActor
    static func settledStore(isPro: Bool) -> BodyProStore {
        let client = BodyProPreviewPurchasesClient(isPro: isPro)
        let store = BodyProStore(client: client, entitlementDefaults: UserDefaults(suiteName: "BodyProPreview"))
        store.settleForPreview(isPro: isPro, products: client.allProducts)
        return store
    }

    private var allProducts: [BodyProProduct] {
        [
            product(BodyProStore.yearlyProductID, "9.99", perMonth: "0.83", freeTrial: BodyProFreeTrial(value: 1, unit: .week)),
            product(BodyProStore.monthlyProductID, "0.99"),
            product(BodyProStore.lifetimeProductID, "19.99"),
            product(BodyProStore.lifetimeFamilyProductID, "29.99")
        ]
    }

    func products(ids: [String]) async -> [BodyProProduct] {
        allProducts.filter { ids.contains($0.id) }
    }

    /// Prices are formatted here, the way the US storefront would, rather than written out
    /// as display strings the paywall could be mistaken for guessing.
    private func product(_ id: String, _ price: String, perMonth: String? = nil, freeTrial: BodyProFreeTrial? = nil) -> BodyProProduct {
        let usd = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        let amount = Decimal(string: price) ?? 0
        return BodyProProduct(
            id: id,
            displayPrice: amount.formatted(usd),
            price: amount,
            displayPricePerMonth: perMonth.flatMap { Decimal(string: $0)?.formatted(usd) },
            freeTrial: freeTrial
        )
    }

    func purchase(productID: String) async throws -> BodyPurchaseOutcome { .cancelled }
    func restorePurchases() async throws -> BodyRestoreOutcome { .nothingToRestore }
    func currentEntitlement() async throws -> Bool { isPro }
    func syncPurchases() async throws -> Bool { isPro }
}

// Dark like the app, which pins its color scheme at the root.
#Preview("Plans") {
    @Previewable @State var store = BodyProPreviewPurchasesClient.settledStore(isPro: false)

    NavigationStack {
        BodyProView(showsCloseButton: true)
    }
    .environment(store)
    .preferredColorScheme(.dark)
}

// The end of onboarding and the one-time introduction after an update.
#Preview("In a Flow") {
    @Previewable @State var store = BodyProPreviewPurchasesClient.settledStore(isPro: false)

    NavigationStack {
        BodyProView(onContinue: {})
    }
    .environment(store)
    .preferredColorScheme(.dark)
}

#Preview("Owned") {
    @Previewable @State var store = BodyProPreviewPurchasesClient.settledStore(isPro: true)

    NavigationStack {
        BodyProView()
    }
    .environment(store)
    .preferredColorScheme(.dark)
}
#endif
