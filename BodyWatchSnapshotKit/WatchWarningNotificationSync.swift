//
//  WatchWarningNotificationSync.swift
//  Body
//
//  The watch telling the iPhone it notified a threshold warning it detected
//  itself, so the iPhone doesn't notify the same kind again that day. The
//  iPhone records each one in its notification ledger
//  (`MetricWarningBackgroundEvaluator.seed`), and its next push carries that
//  ledger back (`WatchWarningSettings.notifiedDays`), so the watch also skips
//  a kind the iPhone already notified. Shaped like `WatchWarningFoldSync`:
//  the watch sends with `transferUserInfo` and, while the iPhone is
//  reachable, `sendMessage` too, and the key is shared rather than spelled as
//  a literal on both sides.
//

import Foundation

enum WatchWarningNotificationSync {
    /// Payload key carrying the JSON encoded `[Record]`.
    static let recordsKey = "metricWarningNotified"

    /// One warning the watch notified: its `MetricWarningKind` raw value and
    /// when its episode started, which names the day the ledger marks.
    struct Record: Codable, Equatable, Sendable {
        var kind: String
        var startDate: Date
    }

    /// The WatchConnectivity payload for `records`, or nil if they don't
    /// encode. The dates use ISO 8601, the snapshot's own encoding.
    static func payload(for records: [Record]) -> [String: Any]? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return nil }
        return [recordsKey: data]
    }

    /// The records a payload carries, or nil when it has no `recordsKey` (some
    /// other message) or its data doesn't decode.
    static func records(from payload: [String: Any]) -> [Record]? {
        guard let data = payload[recordsKey] as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Record].self, from: data)
    }
}
