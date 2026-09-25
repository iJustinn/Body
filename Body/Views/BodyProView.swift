//
//  BodyProView.swift
//  Body
//

import Charts
import RevenueCatUI
import StoreKit
import SwiftUI
import UIKit

enum BodyProPalette {
    /// The Pro accent elsewhere in the app (the Settings entry, the profile card).
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.18)
    /// The Pro page itself uses the app's blue, like onboarding's Continue button, so it
    /// reads as part of the app rather than a store.
    static let accent = Color.blue
}

/// Legal links every subscription paywall must carry. Body uses Apple's standard license
/// agreement as its Terms of Use, as set in App Store Connect.
enum BodyProLinks {
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://docs.ijustinz.com/body/privacy")!
}

/// The Body Pro page. Sells by showing: a showcase of real Body surfaces drawn from sample
/// data (a year of sleep, a 3D route, widgets, two sources on one chart, background
/// profiles) leads, then the plans, the trial terms, and a compact grid of everything Pro
/// unlocks. Sits on the app's own background, like every other page, with gold reserved
/// for the Pro accents. A member gets the app icon with a thank-you on top, the showcase
/// under it, and no plans.
struct BodyProView: View {
    /// Adds a close button. The paywall sheets presented from locked controls need one; the
    /// Settings entry pushes this page and gets the back button instead.
    var showsCloseButton = false
    /// Set when the paywall is a step in a flow the app started (the end of onboarding, the
    /// one-time introduction after an update) rather than a page the user opened. The page
    /// then always offers Continue for Free, its close button continues too, and a purchase
    /// carries on by itself once the owned state has had a moment on screen.
    var onContinue: (() -> Void)?

    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Yearly first: it is the best value and the only plan with a free trial.
    @State private var selectedPlan: BodyProPlan = .yearly
    @State private var showRedeemSheet = false
    @State private var showCustomerCenter = false

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
                // A member's thank-you leads; the showcase then shows what they have.
                if isPro {
                    BodyProOwnedCard()
                }

                BodyProShowcase()

                if !isPro {
                    planSection
                }

                if offersPlans, let plan = activePlan, let product = activeProduct, let trial = product.freeTrial {
                    BodyProTrialTimeline(trial: trial, renewalText: renewalText(plan: plan, product: product))
                }

                BodyProFeatureGrid()

                // The recovery row and the legal links read as one footer; their 44pt tap
                // targets already keep them apart.
                VStack(spacing: 0) {
                    restoreSection
                    BodyProLegalFooter()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
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
            // The same backdrop as Settings and onboarding, so the page reads as part of
            // the app rather than a store bolted onto it.
            BodyAppBackground()
                .ignoresSafeArea()
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

    private var planCards: some View {
        VStack(spacing: 14) {
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
        .padding(.top, 2)
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
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            // bar itself is solid so nothing shows through behind the price terms. The
            // app background has faded to the plain page color by here.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)

                Color(.systemGroupedBackground)
            }
            .padding(.top, -28)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func purchaseControls(plan: BodyProPlan, product: BodyProProduct) -> some View {
        // Pending approval or a failure lands here, beside the button that caused it,
        // rather than below the feature grid.
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
                        .tint(.white)
                }
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 52)
            // The onboarding Continue button's flat glass chip.
            .background(BodyGlassChip(color: BodyProPalette.accent, cornerRadius: 16, fillOpacity: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        .foregroundColor(BodyProPalette.accent)
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
                        .foregroundColor(BodyProPalette.accent)
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
                        .foregroundColor(BodyProPalette.accent)
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

// MARK: - Showcase

/// What Pro looks like, one real surface at a time: a paged carousel of scenes built from
/// Body's own views over sample data, with a caption for each. It moves on by itself every
/// few seconds (a swipe restarts the clock), and holds still under Reduce Motion or VoiceOver.
private struct BodyProShowcase: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var selection = 0

    private static let slides = BodyProShowcaseSlide.allCases
    private static let dwell: Duration = .seconds(4.5)
    /// The page's horizontal padding, which the pager reaches back across.
    private static let margin: CGFloat = 18
    /// The fade sits inside the margin and stops short of it, so a scene in place is never
    /// touched; only what slides through the margins fades.
    private static let fadeWidth: CGFloat = margin - 2

    private var edgeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeWidth)

            Rectangle().fill(Color.black)

            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeWidth)
        }
    }

    private var slide: BodyProShowcaseSlide {
        Self.slides[selection]
    }

    var body: some View {
        VStack(spacing: 14) {
            // The pager runs out to the screen edges under the page margins and fades
            // there, like the detail page's day slider, so a scene slides in and out
            // through a soft edge instead of a hard cut at the column.
            TabView(selection: $selection) {
                ForEach(Array(Self.slides.enumerated()), id: \.offset) { index, slide in
                    slide.scene
                        .padding(.horizontal, Self.margin)
                        .tag(index)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(slide.title))
                        .accessibilityValue(Text(slide.subtitle))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 276)
            .padding(.horizontal, -Self.margin)
            // The mask reaches out across the margins with the pager, so its fades land in
            // the margins rather than on the resting scene.
            .mask(edgeMask.padding(.horizontal, -Self.margin))

            VStack(spacing: 5) {
                Text(slide.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(slide.subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .top)
            .id(selection)
            .transition(.opacity)

            BodyProShowcaseDots(count: Self.slides.count, selection: selection)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: selection)
        .task(id: selection) {
            // A swipe lands on a new selection, which restarts the dwell from there.
            guard !reduceMotion, !voiceOverEnabled else { return }
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled else { return }
            selection = (selection + 1) % Self.slides.count
        }
    }
}

private struct BodyProShowcaseDots: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selection ? BodyProPalette.accent : Color.primary.opacity(0.22))
                    .frame(width: index == selection ? 18 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

private enum BodyProShowcaseSlide: CaseIterable {
    case yearChart
    case route
    case widgets
    case sources
    case backgrounds

    var title: LocalizedStringKey {
        switch self {
        case .yearChart: return "A whole year, at a glance"
        case .route: return "Your routes, in 3D"
        case .widgets: return "Body on your Home Screen"
        case .sources: return "Two sources, one chart"
        case .backgrounds: return "Make it yours"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .yearChart: return "Month, 6 month, and year charts for every metric."
        case .route: return "Share workouts with the route as an elevation ribbon, over a photo or video."
        case .widgets: return "Widgets for your workouts and every metric."
        case .sources: return "Compare a second source, or merge several into a custom one."
        case .backgrounds: return "Custom backgrounds, saved as profiles you can switch anytime."
        }
    }

    @ViewBuilder
    var scene: some View {
        switch self {
        case .yearChart: BodyProYearChartSlide()
        case .route: BodyProRouteSlide()
        case .widgets: BodyProWidgetsSlide()
        case .sources: BodyProSourcesSlide()
        case .backgrounds: BodyProBackgroundsSlide()
        }
    }
}

private extension View {
    /// One showcase scene: a screen-shaped card on the page color, optionally with the
    /// metric detail page's wash (the tint fading out by the midpoint) at the top.
    func bodyProShowcaseScene(wash: Color? = nil) -> some View {
        bodyProShowcaseScene {
            if let wash {
                LinearGradient(
                    stops: [
                        .init(color: wash.opacity(0.45), location: 0),
                        .init(color: .clear, location: 0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    func bodyProShowcaseScene<Backdrop: View>(@ViewBuilder backdrop: () -> Backdrop) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    Color(.systemGroupedBackground)
                    backdrop()
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .allowsHitTesting(false)
    }
}

/// Deterministic noise for the sample data, so every launch draws the same scenes.
private struct BodyProSampleNoise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Uniform in 0..<1.
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// The HRV detail page over a sample year: the real range pills with Year chosen and
/// the real trend chart. A line metric, so the year's shape shows; a bar metric's axis
/// starts at zero and flattens a year into a wall.
private struct BodyProYearChartSlide: View {
    private static let tint = HealthWidgetMetric.heartRateVariability.tintColor

    /// A year of nights: a slow climb through a training block, a seasonal dip, and the
    /// night to night scatter HRV really has.
    private static let series: HealthTrendSeries = {
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        var noise = BodyProSampleNoise(seed: 0x5EED_5EED)
        let points = (0..<365).compactMap { offset -> HealthTrendDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: offset - 364, to: today) else {
                return nil
            }
            let progress = Double(offset) / 365
            let season = 5 * sin(progress * 2 * .pi - 1.4)
            let block = 7 * progress
            let value = 44 + season + block + (noise.next() - 0.5) * 12
            return HealthTrendDataPoint(date: date, value: value.rounded())
        }
        return HealthTrendSeries(points: points)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BodyHealthTrendRangeSelector(selectedRange: .constant(.recentYear), appearance: .onGradient)

            BodyHealthMetricTrendChart(
                title: String(localized: "HRV"),
                chartStyle: .line,
                symbolColor: Self.tint,
                selectedRange: .recentYear,
                series: Self.series,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) },
                isSleepDetail: false,
                chartIdentity: "bodyProShowcaseHRV"
            )
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .bodyProShowcaseScene(wash: Self.tint)
    }
}

/// A workout share card in the 3D route style: the ribbon drawn by the route hero's own
/// projection and painter over a sample loop, with the card's stats in the corner.
private struct BodyProRouteSlide: View {
    private static let workoutType = BodyWorkoutType.running

    /// A hilly loop: altitude on every fix, and enough climb for the ribbon's full relief.
    private static let projected: WorkoutRoute3DProjection.Projected3D? = {
        let route = (0..<160).map { index -> RouteCoordinate in
            let angle = Double(index) / 160 * 2 * .pi
            return RouteCoordinate(
                latitude: 37.7749 + 0.0030 * sin(angle) + 0.0009 * sin(3 * angle) + 0.0004 * cos(7 * angle),
                longitude: -122.4194 + 0.0045 * cos(angle) + 0.0007 * cos(2 * angle) + 0.0003 * sin(6 * angle),
                speed: 3.1,
                altitude: 120 + 110 * sin(2 * angle + 0.6) + 30 * sin(5 * angle)
            )
        }
        return WorkoutRoute3DProjection.projected(for: route)
    }()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Canvas { context, size in
                guard let projected = Self.projected,
                      let fit = BodyWorkoutRouteHeroFit.transform(
                          fitting: projected.fitReference,
                          in: size,
                          targetCenterY: size.height * 0.44,
                          topInset: 0
                      ) else {
                    return
                }
                let place = { (point: CGPoint) in
                    CGPoint(x: fit.offset.x + point.x * fit.scale, y: fit.offset.y + point.y * fit.scale)
                }
                BodyWorkoutRoute3DHero.drawRibbon(
                    top: projected.top.map(place),
                    base: projected.base.map(place),
                    tint: Self.workoutType.color,
                    in: &context
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(Self.workoutType.displayName)
                } icon: {
                    Image(systemName: Self.workoutType.symbolName)
                }
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    stat("8.4", unit: "km")
                    stat("42:18", unit: nil)
                    stat("5'02\"", unit: "/km")
                }
            }
            .padding(18)
        }
        .bodyProShowcaseScene {
            RadialGradient(
                colors: [Self.workoutType.color.opacity(0.32), .clear],
                center: .init(x: 0.7, y: 0.25),
                startRadius: 0,
                endRadius: 260
            )
        }
    }

    private func stat(_ value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            if let unit {
                Text(verbatim: unit)
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Two small metric widgets, as the widget gallery draws them over the placeholder
/// snapshot, on the app's own background.
private struct BodyProWidgetsSlide: View {
    private static let snapshot = HealthWidgetSnapshot.placeholder

    var body: some View {
        HStack(spacing: 14) {
            widget(.heartRate)
            widget(.sleep)
        }
        .padding(16)
        .bodyProShowcaseScene {
            BodyActivityRingsCard.heroBackground(colors: BodyHomeBackground.defaultColors)
        }
    }

    private func widget(_ metric: HealthWidgetMetric) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return HealthWidgetMetricCardView(metric: metric, trend: Self.snapshot.trend(for: metric))
            .padding(.horizontal, 15)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 150)
            .background {
                // The widget's Gradient background: the tint washing down from the top.
                shape
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: metric.tintColor.opacity(0.45), location: 0),
                                .init(color: .clear, location: 0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(shape)
                    }
            }
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }
}

/// A week of steps from two sources on one chart, in the detail chart's own line and
/// point style, the way a secondary source shows there.
private struct BodyProSourcesSlide: View {
    private static let tint = HealthWidgetMetric.steps.tintColor
    private static let secondaryTint = Color(red: 0.62, green: 0.84, blue: 1.0)

    private struct Day: Identifiable {
        let id: Int
        let date: Date
        let watch: Double
        let phone: Double
    }

    private static let days: [Day] = {
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        let watch: [Double] = [8_420, 11_260, 6_930, 9_780, 12_410, 7_350, 10_120]
        let phone: [Double] = [7_100, 10_340, 6_020, 8_610, 11_160, 6_480, 9_130]
        return watch.indices.compactMap { index in
            calendar.date(byAdding: .day, value: index - 6, to: today).map {
                Day(id: index, date: $0, watch: watch[index], phone: phone[index])
            }
        }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                legend(Self.tint, name: Text(verbatim: "Apple Watch"))
                legend(Self.secondaryTint, name: Text("Other Wearables"))

                Spacer(minLength: 0)

                Text("Steps")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Chart {
                ForEach(Self.days) { day in
                    line(day.watch, of: day, series: "watch", tint: Self.tint)
                    line(day.phone, of: day, series: "other", tint: Self.secondaryTint)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .font(.system(.caption2, design: .rounded))
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 3_000...14_000)
            .chartLegend(.hidden)
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .bodyProShowcaseScene(wash: Self.tint)
    }

    /// One source's line and dots, drawn as the week range draws them on a detail chart:
    /// straight segments and ringed points, the latest one filled.
    @ChartContentBuilder
    private func line(_ value: Double, of day: Day, series: String, tint: Color) -> some ChartContent {
        LineMark(
            x: .value("Date", day.date, unit: .day),
            y: .value("Steps", value),
            series: .value("Source", series)
        )
        .interpolationMethod(.linear)
        .foregroundStyle(tint)
        .lineStyle(StrokeStyle(lineWidth: BodyLineChartPreviewStyle.lineWidth, lineCap: .round, lineJoin: .round))

        PointMark(
            x: .value("Date", day.date, unit: .day),
            y: .value("Steps", value)
        )
        .symbol {
            BodyLineChartPreviewPointSymbol(
                tintColor: tint,
                isCurrent: day.id == Self.days.count - 1,
                pointDiameter: BodyHealthTrendRange.recentWeek.linePointDiameter,
                currentPointDiameter: BodyHealthTrendRange.recentWeek.lineCurrentPointDiameter
            )
        }
    }

    private func legend(_ color: Color, name: Text) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            name
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
}

/// Four saved background profiles, each on a small screen with the shapes of the Summary
/// page, so the mixes read as the app rather than as swatches.
private struct BodyProBackgroundsSlide: View {
    private static let profiles: [BodyHomeBackgroundProfile] = [.appDefault, .rose, .violet, .iJustin]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Self.profiles) { profile in
                screen(profile)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .bodyProShowcaseScene()
    }

    private func screen(_ profile: BodyHomeBackgroundProfile) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack(alignment: .top) {
            BodyActivityRingsCard.heroBackground(
                colors: BodyHomeBackground.colors(from: profile.colorsRawValue),
                separators: BodyHomeBackground.separators(from: profile.separatorsRawValue)
            )

            VStack(spacing: 8) {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 4)
                    .frame(width: 34, height: 34)
                    .padding(.top, 22)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.09))
                    .frame(height: 40)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                }
                .frame(height: 40)
            }
            .padding(.horizontal, 9)
        }
        .aspectRatio(0.46, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - Owned

/// A member's page leads with this card, the app icon and a thank-you, above the showcase.
private struct BodyProOwnedCard: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                BodyProIconGlow()

                BodyProAppIcon()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)

            VStack(spacing: 6) {
                Text("You have Body Pro")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Thanks for your support. All Pro features are unlocked.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .bodyCardBackground(cornerRadius: 26, translucent: true)
    }
}

/// The app's icon, whichever one is chosen in Settings, as onboarding's Welcome shows it.
private struct BodyProAppIcon: View {
    var body: some View {
        Image(BodyAppIconOption.option(named: UIApplication.shared.alternateIconName).previewAssetName)
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct BodyProIconGlow: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            BodyProPalette.accent.opacity(0.15),
                            BodyProPalette.accent.opacity(0.05),
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
                .fill(BodyProPalette.accent.opacity(0.04))
                .frame(width: 180, height: 70)
                .blur(radius: 22)
                .offset(y: 18)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Plans

/// One selectable plan. The whole row is the tap target; `accessory` renders below it
/// inside the same card (the Lifetime card's Just Me / Family switch).
private struct BodyProPlanCard<Accessory: View>: View {
    let title: LocalizedStringKey
    let detail: String
    let price: String
    let priceCaption: LocalizedStringKey
    var savingsPercent: Int?
    /// Tag on the card's top edge ("7 days free", "Best Value").
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
                                    .foregroundColor(BodyProPalette.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(BodyProPalette.accent.opacity(0.16)))
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
        .background(cardShape.fill(isSelected ? BodyProPalette.accent.opacity(0.12) : Color.primary.opacity(0.06)))
        .overlay(
            cardShape.strokeBorder(
                isSelected ? BodyProPalette.accent : Color.primary.opacity(0.1),
                lineWidth: isSelected ? 2 : 1
            )
        )
        .overlay(alignment: .topTrailing) {
            if let ribbon {
                Text(ribbon)
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.heavy)
                    .textCase(.uppercase)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(BodyProPalette.accent))
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
                .strokeBorder(isSelected ? BodyProPalette.accent : Color.primary.opacity(0.25), lineWidth: 2)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(BodyProPalette.accent))
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
                .foregroundColor(isOn ? .white : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(isOn ? BodyProPalette.accent : Color.clear))
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
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(BodyProPalette.accent))

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
                    .fill(BodyProPalette.accent.opacity(0.35))
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

// MARK: - Store states

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
            .tint(BodyProPalette.accent)
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
                .foregroundColor(BodyProPalette.accent)

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

// MARK: - Everything in Pro

/// The complete list, as a grid of short titles: the showcase has already shown what
/// they look like, so this is the checklist, not the pitch.
private struct BodyProFeatureGrid: View {
    private let features = BodyProFeature.defaultFeatures
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Everything in Pro")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(features) { feature in
                    BodyProFeatureTile(iconName: feature.iconName, title: feature.title)
                }

                BodyProFeatureTile(iconName: "bolt.fill", title: String(localized: "Future Pro Updates"))
            }
        }
    }
}

private struct BodyProFeatureTile: View {
    let iconName: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BodyProPalette.accent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BodyProPalette.accent.opacity(0.14))
                )

            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .bodyCardBackground(cornerRadius: 18, translucent: true)
        .accessibilityElement(children: .combine)
    }
}

private struct BodyProFeature: Identifiable {
    let id: String
    let title: String
    let iconName: String

    /// Grouped by what they touch — metric depth, data sources, share cards, then
    /// the rest of the app — so neighbouring tiles read as one subject.
    static let defaultFeatures = [
        // Metric depth: how far back the charts and day views reach.
        BodyProFeature(
            id: "longer-range-charts",
            title: String(localized: "Longer-Range Charts"),
            iconName: "chart.line.uptrend.xyaxis"
        ),
        BodyProFeature(
            id: "full-day-history",
            title: String(localized: "Full Day History"),
            iconName: "calendar"
        ),

        // Where the numbers come from.
        BodyProFeature(
            id: "secondary-source",
            title: String(localized: "Secondary Data Source"),
            iconName: "square.stack.3d.up.fill"
        ),
        BodyProFeature(
            id: "custom-sources",
            title: String(localized: "Custom Data Sources"),
            iconName: "heart.fill"
        ),

        // Workout share cards.
        BodyProFeature(
            id: "photo-share",
            title: String(localized: "Photo Activity Share"),
            iconName: "photo.fill"
        ),
        BodyProFeature(
            id: "video-share",
            title: String(localized: "Video Activity Share"),
            iconName: "video.fill"
        ),
        BodyProFeature(
            id: "three-d-route-share",
            title: String(localized: "3D Route Share"),
            iconName: "move.3d"
        ),
        BodyProFeature(
            id: "share-ratios",
            title: String(localized: "Share Card Sizes"),
            iconName: "aspectratio"
        ),
        BodyProFeature(
            id: "share-metrics",
            title: String(localized: "Share Card Metrics"),
            iconName: "list.bullet.rectangle.portrait"
        ),

        // Elsewhere in the app.
        BodyProFeature(
            id: "home-heroes",
            title: String(localized: "More Home Heroes"),
            iconName: "star.fill"
        ),
        BodyProFeature(
            id: "custom-backgrounds",
            title: String(localized: "Custom Backgrounds"),
            iconName: "paintpalette.fill"
        ),
        BodyProFeature(
            id: "body-widgets",
            title: String(localized: "Body Widgets"),
            iconName: "square.grid.2x2.fill"
        )
    ]
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
