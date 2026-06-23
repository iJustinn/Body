//
//  WatchSettingsView.swift
//  BodyWatch
//
//  On-watch toggle for standalone compute. Changes are recorded locally and
//  pushed to the iPhone (and reconciled with the background machinery) so the
//  setting stays in sync across devices.
//

import SwiftUI

struct WatchSettingsView: View {
    @EnvironmentObject private var model: WatchMetricsModel
    @AppStorage(BodyAppearancePreference.standaloneWatchComputeKey) private var standaloneEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Standalone Compute", isOn: Binding {
                    standaloneEnabled
                } set: { enabled in
                    let revision = StandaloneComputePreference.setLocal(enabled: enabled)
                    model.sendStandalonePreference(enabled: enabled, revision: revision)
                    model.reconcileStandalone(enabled: enabled)
                })
            } footer: {
                Text("Compute readiness, sleep, training load, and vitals on your watch so they update without opening the iPhone app.")
            }
        }
        .navigationTitle("Settings")
    }
}
