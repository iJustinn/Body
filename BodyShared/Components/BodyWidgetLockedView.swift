//
//  BodyWidgetLockedView.swift
//  BodyShared
//

import SwiftUI

/// Shown in place of a Body widget's content when Body Pro is not unlocked. Body widgets
/// are a Body Pro feature; the entitlement comes from the App Group-shared
/// `BodyProEntitlement`, and the timelines refresh (via `WidgetCenter`) when a purchase
/// completes so the real content takes over.
struct BodyWidgetLockedView: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.yellow)

            Text(String(localized: "Body Pro", table: "BodyShared"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(String(localized: "Unlock Body widgets in the app", table: "BodyShared"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
