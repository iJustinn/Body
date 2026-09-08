//
//  BodyCacheRebuildView.swift
//  Body
//

import SwiftUI

/// One-page explainer that runs the one-time cache reload 1.1.0 needs.
///
/// `.update` is the version-gated page an upgrading 1.0.x user sees once on the
/// first 1.1.0 launch (MainTabView presents it and stamps the completion
/// version when the cover's binding goes false, so nothing here writes
/// UserDefaults). It has no close button and cannot be swiped away: the only
/// way into the app is a finished load, so a half-built Home is never shown.
/// `.settings` is the permanent copy behind Settings › Data › Cache › Rebuild
/// Cache, with the same close affordance as the replayable onboarding flow
/// until the load starts; while it runs the close goes away too.
///
/// The rebuild deliberately does NOT use the Settings Clear Cache path: that wipes the
/// frozen morning readiness, Body Radar, and stress records, which are
/// point-in-time captures HealthKit cannot regenerate. A plain user-initiated
/// refresh already rewrites every 1.1.0 structure and drops the legacy files,
/// so it achieves the cleanup without losing that history.
struct BodyCacheRebuildView: View {
    enum Entry {
        case update
        case settings
    }

    let entry: Entry

    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitWorkoutStore.self) private var workoutStore
    @State private var isLoading = false
    @State private var hasAttemptedRebuild = false
    @State private var hasSucceeded = false
    /// Retains the reload so leaving the page can cancel it instead of leaving
    /// `isLoading` stuck on.
    @State private var rebuildTask: Task<Void, Never>?

    init(entry: Entry) {
        self.entry = entry
    }

    var body: some View {
        ZStack {
            BodyAppBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                page
            }
        }
        // The buttons float over the scrolling page; `page` pads its content so
        // nothing hides under them.
        .overlay(alignment: .bottom) {
            primaryButton
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        // The same loading capsule the first-run onboarding floats over its
        // pages while its Health load runs, narrating the store's refresh stage.
        .overlay(alignment: .top) {
            if isLoading {
                BodySyncStatusBadgeLabel(icon: .spinner, text: stageText)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: isLoading)
        .interactiveDismissDisabled(entry == .update || isLoading)
        .onDisappear {
            cancelRebuild()
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Spacer()

            if entry == .settings && !isLoading {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .accessibilityLabel(Text("onboarding.close"))
                }
            }
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var page: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                header

                CacheRebuildFeatureRow(
                    iconName: "bolt.fill",
                    tintColor: .blue,
                    title: "updateOnboarding.feature.refresh.title",
                    subtitle: "updateOnboarding.feature.refresh.subtitle"
                )

                Text("updateOnboarding.keepOpen")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(isLoading ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if showsFailureNotice, let notice = workoutStore.healthDataNotice {
                    Text(notice)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            // Room for the floating buttons at the bottom.
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(.primary)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryButton: some View {
        Button(action: rebuild) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(primaryButtonTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            // Same flat glass chip as the onboarding CTA: translucent fill,
            // thin white rim, no gradient or material.
            .background(BodyGlassChip(color: .blue, cornerRadius: 16, fillOpacity: 0.7))
        }
        .disabled(isLoading)
    }

    // MARK: - Copy

    private var title: LocalizedStringKey {
        entry == .update ? "updateOnboarding.title" : "updateOnboarding.settings.title"
    }

    private var subtitle: LocalizedStringKey {
        entry == .update ? "updateOnboarding.subtitle" : "updateOnboarding.settings.subtitle"
    }

    private var stageText: LocalizedStringKey {
        workoutStore.refreshStage?.badgeText ?? "Loading data..."
    }

    /// `LocalizedStringKey` (not `String(localized:)`) so the label follows the
    /// environment locale like every other `Text` on the page.
    private var primaryButtonTitle: LocalizedStringKey {
        if isLoading {
            return stageText
        }

        if hasSucceeded {
            return entry == .update ? "updateOnboarding.getStarted" : "updateOnboarding.done"
        }

        return hasAttemptedRebuild ? "Try Again" : "updateOnboarding.rebuild"
    }

    private var showsFailureNotice: Bool {
        hasAttemptedRebuild && !isLoading && !hasSucceeded
    }

    // MARK: - Actions

    private func rebuild() {
        guard !isLoading else {
            return
        }

        if hasSucceeded {
            dismiss()
            return
        }

        isLoading = true
        hasAttemptedRebuild = true
        rebuildTask = Task {
            // The app-entry passive sync may still hold the refresh slot; without
            // this wait the call below would early-return on its `isRefreshing`
            // guard and the page would report a failure it never attempted.
            guard await workoutStore.awaitRefreshSlotFree() else {
                return
            }

            // Done means the full refresh ran to completion, the same rule the
            // first-run load uses: metrics Body cannot read are skipped, not
            // failures, so a user who denied some Health permissions still gets
            // through. Only a thrown, timed-out, or unavailable refresh leaves
            // the count unchanged and shows Try Again.
            let completionCount = workoutStore.fullRefreshCompletionCount
            await workoutStore.requestAuthorizationAndRefresh()
            guard !Task.isCancelled else {
                return
            }

            hasSucceeded = workoutStore.fullRefreshCompletionCount > completionCount
            isLoading = false
        }
    }

    private func cancelRebuild() {
        rebuildTask?.cancel()
        rebuildTask = nil
        isLoading = false
    }
}

private struct CacheRebuildFeatureRow: View {
    let iconName: String
    let tintColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BodySettingsIconTile(iconName: iconName, color: tintColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    BodyCacheRebuildView(entry: .update)
        .environment(HealthKitWorkoutStore())
}
