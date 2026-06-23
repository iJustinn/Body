//
//  WatchSettingsView.swift
//  BodyWatch
//
//  Watch settings: shows the app version. Metrics are computed on the iPhone
//  and pushed to the watch over WatchConnectivity.
//

import SwiftUI

struct WatchSettingsView: View {
    @EnvironmentObject private var model: WatchMetricsModel

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

    private var appVersionDisplay: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (build \(build))"
    }
}
