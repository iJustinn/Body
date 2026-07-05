//
//  BodyFirstLaunchOverlay.swift
//  Body
//

import SwiftUI

/// First-launch gate shown while the app has no cached Health data (fresh
/// install or wiped cache). The automatic app-entry sync is suppressed in
/// that state, so the button here is what triggers the first big load —
/// the full dashboard refresh plus the one-time ten-year activity-ring
/// backfill. Dismisses itself once a refresh succeeds; "Not Now" hides it
/// for the session (a pull-to-refresh later runs the same first load).
struct BodyFirstLaunchLoadOverlay: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @State private var isLoading = false
    @State private var hasAttemptedLoad = false
    @State private var isDismissedForSession = false

    var body: some View {
        Group {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()

                    card
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }

    private var isPresented: Bool {
        !isDismissedForSession && (isLoading || workoutStore.needsInitialHealthDataLoad)
    }

    private var card: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.heart.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.primary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Load Your Health Data")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Body sets up your dashboard with your Apple Health data. This one-time load can take a moment.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if showsFailureNotice, let notice = workoutStore.healthDataNotice {
                Text(notice)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button(action: loadData) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .tint(Color(.systemBackground))
                        }

                        Text(primaryButtonTitle)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary)
                    )
                }
                .disabled(isLoading)

                Button {
                    isDismissedForSession = true
                } label: {
                    Text("Not Now")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                }
                .disabled(isLoading)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 10)
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
    }

    private var primaryButtonTitle: String {
        if isLoading {
            return String(localized: "Loading Health Data…")
        }

        return hasAttemptedLoad ? String(localized: "Try Again") : String(localized: "Load Health Data")
    }

    /// Failed attempts leave `needsInitialHealthDataLoad` true and surface
    /// the store's notice here; a success dismisses the overlay before this
    /// can show.
    private var showsFailureNotice: Bool {
        hasAttemptedLoad && !isLoading
    }

    private func loadData() {
        guard !isLoading else {
            return
        }

        isLoading = true
        hasAttemptedLoad = true
        Task {
            await workoutStore.requestAuthorizationAndRefresh()
            await workoutStore.awaitRefreshCompletion()
            isLoading = false
        }
    }
}

#Preview {
    BodyFirstLaunchLoadOverlay()
        .environmentObject(HealthKitWorkoutStore())
}
