//
//  BodyAccessoryLockedView.swift
//  BodyWidgetExtension
//
//  Locked state shared by the Lock Screen widgets (Weekly Workout Time and
//  Sleep Stages).
//

import SwiftUI

/// Compact locked state sized for the accessory container (~72pt tall), too
/// small for the shared `BodyWidgetLockedView` (~87pt). No yellow: lock
/// screen widgets render in vibrant mode, which flattens tinted colors.
struct BodyAccessoryLockedView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(String(localized: "Body Pro", table: "BodyShared"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
