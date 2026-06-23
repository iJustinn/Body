//
//  WatchSettingsView.swift
//  BodyWatch
//
//  Watch settings: shows the app version. Metrics are computed on the iPhone
//  and pushed to the watch over WatchConnectivity.
//

import SwiftUI

struct WatchSettingsView: View {
    var body: some View {
        Form {
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

    private var appVersionDisplay: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (build \(build))"
    }
}
