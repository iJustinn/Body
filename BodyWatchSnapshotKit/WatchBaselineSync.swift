//
//  WatchBaselineSync.swift
//  Body
//
//  The watch Settings page's Sync Baseline request: the watch asks over
//  `WCSession.sendMessage` (the only call that wakes the iPhone app in the
//  background), the iPhone republishes its compute seed through the regular
//  application-context push and replies with a status only. The seed itself
//  never rides the reply, so it can't land out of order with a newer push.
//
//  Shared (rather than spelled as literals on both sides) because a key typo
//  is silent: the message still goes out and the iPhone simply ignores it.
//

import Foundation

enum WatchBaselineSync {
    /// Message key the watch sends to request a resend.
    static let requestKey = "baselineSyncRequest"
    /// Reply key carrying a `Reply` raw value.
    static let replyKey = "baselineSyncReply"

    enum Reply: String {
        /// The context now on the session carries a compute seed.
        case sent
        /// No seed to send: no full refresh yet, a cache clear in progress, or
        /// the seed was dropped for the context size budget.
        case unavailable
    }

    /// How long the watch waits after a `sent` reply for the seed to land.
    static let arrivalTimeout: Duration = .seconds(30)
}
