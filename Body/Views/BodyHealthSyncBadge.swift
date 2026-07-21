//
//  BodyHealthSyncBadge.swift
//  Body
//

import Accessibility
import SwiftUI

/// Floating capsule status badge (Apple Health-style "Syncing…" pill) shown
/// top-center over all tabs while a HealthKit refresh runs, then briefly
/// confirming completion before auto-dismissing.
struct BodyHealthSyncBadge: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True while the first-launch load overlay is presented; that modal
    /// already narrates the initial load, so the badge suppresses the whole
    /// refresh cycle (no late "updated" flash or announcement).
    let isSuppressed: Bool

    private enum Phase: Equatable { case hidden, syncing, updated }
    @State private var phase: Phase = .hidden
    /// The store's success count captured when syncing began; confirmation
    /// shows only if the count advanced past this (i.e. the refresh actually
    /// succeeded — finishRefresh() also runs on errors). The count, not
    /// `lastSuccessfulRefreshDate`, because workout-month, single-metric, and
    /// warm-resume refreshes deliberately leave that date alone.
    @State private var successCountAtSyncStart = 0

    var body: some View {
        ZStack(alignment: .top) {
            if phase != .hidden {
                badgeLabel
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        // Animate only presence (slide/fade in and out). Binding the animation to
        // `phase` itself would crossfade the syncing → updated content swap,
        // briefly double-exposing both strings in the capsule.
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: phase == .hidden)
        .allowsHitTesting(false)
        .onAppear {
            if workoutStore.isRefreshing && !isSuppressed { beginSyncing() }
        }
        .onChange(of: isSuppressed) { _, suppressed in
            if suppressed {
                phase = .hidden
            } else if workoutStore.isRefreshing {
                beginSyncing()
            }
        }
        .onChange(of: workoutStore.isRefreshing) { _, isRefreshing in
            guard !isSuppressed, isRefreshing else { return }
            beginSyncing()
        }
        // Falling edge, debounced: a chained follow-up refresh cancels this
        // (task id flips back to true) and the badge stays in .syncing; the
        // 0.6 s floor also keeps the syncing state readable on fast refreshes.
        .task(id: workoutStore.isRefreshing) {
            guard !workoutStore.isRefreshing, phase == .syncing else { return }
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled, !workoutStore.isRefreshing, phase == .syncing else { return }
            if workoutStore.syncBadgeSuccessCount != successCountAtSyncStart {
                phase = .updated
                AccessibilityNotification.Announcement(String(localized: "Health data updated")).post()
            } else {
                phase = .hidden   // failed/no-op refresh: no false confirmation
            }
        }
        // task(id:) cancels the pending dismiss if a new refresh flips back to .syncing.
        .task(id: phase) {
            guard phase == .updated else { return }
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { phase = .hidden }
        }
    }

    private func beginSyncing() {
        if phase != .syncing {
            successCountAtSyncStart = workoutStore.syncBadgeSuccessCount
        }
        phase = .syncing
    }

    private var badgeLabel: some View {
        BodySyncStatusBadgeLabel(
            icon: phase == .syncing ? .spinner : .checkmark,
            text: phase == .syncing ? "Syncing health data…" : "Health data updated"
        )
    }
}

/// The badge's visual: a small leading spinner or checkmark plus a short
/// status label in the shared capsule chrome. Also used by the Workouts
/// month-load indicator so every loading pill shares one design.
struct BodySyncStatusBadgeLabel: View {
    enum Icon { case spinner, checkmark }

    let icon: Icon
    let text: LocalizedStringKey
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            switch icon {
            case .spinner:
                ProgressView().controlSize(.small).tint(.secondary)
            case .checkmark:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.green)
            }
            Text(text)
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .modifier(BodyHealthSyncBadgeBackground(colorScheme: colorScheme))
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// iOS 26 Liquid Glass capsule; on iOS 18 mirrors the BodyPillTabBar recipe.
private struct BodyHealthSyncBadgeBackground: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .light ? 0.06 : 0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(colorScheme == .light ? 0.12 : 0.30), radius: 12, x: 0, y: 6)
            )
        }
    }
}

#Preview {
    BodyHealthSyncBadge(isSuppressed: false)
        .environmentObject(HealthKitWorkoutStore())
}
