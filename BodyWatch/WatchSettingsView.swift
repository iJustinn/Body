//
//  WatchSettingsView.swift
//  BodyWatch
//
//  Watch settings: which metrics the home screen shows, the refresh
//  vibration, Sync Baseline (asks the iPhone to resend the compute seed the
//  watch's own metrics are computed from, with when one last arrived), and
//  the app version.
//

import SwiftUI

struct WatchSettingsView: View {
    /// Whether the dashboard's refresh button plays its click and success taps. Default true.
    static let hapticsEnabledKey = "watchHapticsEnabled"

    @EnvironmentObject private var model: WatchMetricsModel
    @AppStorage(Self.hapticsEnabledKey) private var hapticsEnabled = true

    var body: some View {
        Form {
            if !model.snapshot.orderedMetrics.isEmpty {
                Section {
                    ForEach(model.snapshot.orderedMetrics) { metric in
                        Toggle(isOn: visibilityBinding(for: metric.kind)) {
                            Label(metric.title, systemImage: WatchMetricKindKey.symbolName(forKind: metric.kind))
                        }
                    }
                } header: {
                    Text("Metrics")
                } footer: {
                    Text("Choose which metrics appear on the watch home screen.")
                }
            }

            Section {
                Toggle(isOn: $hapticsEnabled) {
                    Label("Vibration", systemImage: "waveform")
                }
            } footer: {
                Text("A click when you tap refresh and a tap when it finishes.")
            }

            Section {
                Button {
                    model.syncBaseline()
                } label: {
                    HStack {
                        Label("Sync Baseline", systemImage: "arrow.triangle.2.circlepath")
                        if model.baselineSync == .syncing {
                            Spacer()
                            ProgressView()
                                .fixedSize()
                        }
                    }
                }
                .disabled(model.baselineSync == .syncing)
            } footer: {
                Text(baselineFooter)
            }

            Section {
                VStack(spacing: 2) {
                    Text("Body")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(appVersionDisplay)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
    }

    private func visibilityBinding(for kind: String) -> Binding<Bool> {
        Binding(
            get: { model.isMetricVisible(kind) },
            set: { model.setMetric(kind, visible: $0) }
        )
    }

    /// The last sync line, led by one sentence when the last request failed.
    private var baselineFooter: String {
        let lastSynced = model.lastBaselineSyncDate.map {
            String(localized: "Last synced \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute())).")
        } ?? String(localized: "Not synced yet.")
        guard case .failed(let failure) = model.baselineSync else { return lastSynced }
        let reason: String
        switch failure {
        case .unreachable:
            reason = String(localized: "Couldn't reach Body on iPhone. Open it and try again.")
        case .unavailable:
            reason = String(localized: "iPhone has no baseline yet. Open Body on iPhone.")
        case .noArrival:
            reason = String(localized: "No baseline arrived. Try again.")
        }
        return reason + "\n" + lastSynced
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? String(localized: "Unknown")
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? String(localized: "Unknown")
        return String(localized: "\(version) (build \(build))")
    }
}
