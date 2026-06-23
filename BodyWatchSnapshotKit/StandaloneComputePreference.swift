//
//  StandaloneComputePreference.swift
//  BodyWatchSnapshotKit
//
//  The standalone-watch-compute toggle and its echo-safe phone↔watch sync.
//  Stored per-device in UserDefaults with a monotonic revision; the paired
//  device sends value + revision over WCSession `transferUserInfo` and the
//  receiver applies it only if the revision is newer (last-writer-wins).
//
//  No echo: local user changes go through `setLocal` (which also broadcasts),
//  while remote applies write UserDefaults directly — so a Toggle bound to
//  `@AppStorage` updates from a remote change without re-broadcasting.
//

import Foundation

enum StandaloneComputePreference {
    /// WCSession `transferUserInfo` payload keys.
    static let messageKey = "standaloneWatchCompute"
    static let revisionMessageKey = "standaloneWatchComputeRevision"

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: BodyAppearancePreference.standaloneWatchComputeKey) as? Bool ?? false
    }

    static func revision(_ defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: BodyAppearancePreference.standaloneWatchComputeRevisionKey)
    }

    /// Records a local user change and returns the new revision to broadcast.
    @discardableResult
    static func setLocal(enabled: Bool, defaults: UserDefaults = .standard) -> Int {
        let nextRevision = revision(defaults) + 1
        defaults.set(nextRevision, forKey: BodyAppearancePreference.standaloneWatchComputeRevisionKey)
        defaults.set(enabled, forKey: BodyAppearancePreference.standaloneWatchComputeKey)
        return nextRevision
    }

    /// Applies a value received from the paired device. Returns `true` when the
    /// incoming revision is newer, or — when `preferIncomingOnTie` — the revision
    /// is equal but the value differs. The watch passes `preferIncomingOnTie: true`
    /// so the phone (the settings source of truth) wins a same-revision conflict
    /// and its periodic application-context re-push heals any divergence; the
    /// phone passes `false` and keeps its own value on a tie. A genuine local
    /// change is never a tie (`setLocal` bumps to stored + 1), so a strictly
    /// newer value still wins both ways.
    @discardableResult
    static func applyRemote(enabled: Bool, revision incomingRevision: Int, preferIncomingOnTie: Bool = false, defaults: UserDefaults = .standard) -> Bool {
        let stored = revision(defaults)
        let breaksTie = preferIncomingOnTie && incomingRevision == stored && enabled != isEnabled(defaults)
        guard incomingRevision > stored || breaksTie else { return false }
        defaults.set(incomingRevision, forKey: BodyAppearancePreference.standaloneWatchComputeRevisionKey)
        defaults.set(enabled, forKey: BodyAppearancePreference.standaloneWatchComputeKey)
        return true
    }

    /// Parses a received WCSession userInfo payload.
    static func parse(_ userInfo: [String: Any]) -> (enabled: Bool, revision: Int)? {
        guard let enabled = userInfo[messageKey] as? Bool,
              let revision = userInfo[revisionMessageKey] as? Int else { return nil }
        return (enabled, revision)
    }
}
