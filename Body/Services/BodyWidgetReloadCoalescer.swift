//
//  BodyWidgetReloadCoalescer.swift
//  Body
//

import Foundation
import WidgetKit

/// Coalesces `WidgetCenter.reloadAllTimelines()` requests. A single refresh
/// can finish the dashboard, workout, and widget snapshot saves within a few
/// hundred milliseconds of each other, and each used to issue its own XPC
/// reload; one debounced reload covers them all and spends less of the
/// system's widget-reload budget.
@MainActor
final class BodyWidgetReloadCoalescer {
    static let shared = BodyWidgetReloadCoalescer()

    private let debounceNanoseconds: UInt64
    private let reload: () -> Void
    private var pendingReload: Task<Void, Never>?

    init(
        debounceNanoseconds: UInt64 = 1_000_000_000,
        reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.debounceNanoseconds = debounceNanoseconds
        self.reload = reload
    }

    func requestReload() {
        guard pendingReload == nil else {
            return
        }

        pendingReload = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            pendingReload = nil
            reload()
        }
    }
}
