//
//  WatchWarningFoldSync.swift
//  Body
//
//  Two way sync of the metric warning cards' fold state between the iPhone
//  and the watch. A fold or unfold on either device applies to both; the unit
//  is one fold key, the iPhone's `dismissedMetricWarnings` entry for that
//  warning ("highHeartRate@2026-10-04"), which the watch receives with each
//  warning (`WatchMetricWarning.foldKey`) and uses verbatim.
//
//  Last writer wins per fold key, on these rules:
//  * Stamps are whole seconds. The snapshot encodes dates as ISO 8601 without
//    fractions, so a fractional stamp would come back a fraction earlier and
//    no longer compare equal to the one the device kept.
//  * Every new stamp is strictly after the last stamp the device knows for
//    that key (`stamp(now:after:)`), so a fold on one device followed by an
//    unfold on the other always resolves to the later action, even when the
//    second device's clock runs behind the first's. Only truly concurrent
//    edits fall back to the later wall clock time.
//  * A record replaces the known state only when it is stamped strictly later
//    (`supersedes`), so ties go to the iPhone: the watch keeps a record only
//    while it beats the iPhone's published stamp.
//  * A device that accepts the other side's record stores that record's stamp
//    verbatim, never its own "now", so after one round trip both devices hold
//    the same record and stop flipping, and a duplicate delivery is a tie.
//
//  The watch sends records with `transferUserInfo` (queued, survives
//  suspension) and, while the iPhone is reachable, `sendMessage` too; the
//  iPhone answers through its regular application context push. Shared
//  (rather than spelled as literals on both sides) because a key typo is
//  silent, like `WatchBaselineSync`.
//

import Foundation

enum WatchWarningFoldSync {
    /// Payload key carrying the JSON encoded `[Record]`.
    static let recordsKey = "metricWarningFolds"

    /// One device's fold state for one warning, and when it was set.
    struct Record: Codable, Equatable, Sendable {
        /// The iPhone's `dismissedMetricWarnings` entry, "<kind>@yyyy-MM-dd".
        var key: String
        var isFolded: Bool
        /// Whole seconds, from `stamp(now:after:)` on the device that made
        /// the change; copied verbatim by the device that accepts it.
        var changedAt: Date
    }

    /// The stamp for a change made at `now` to a key whose latest known stamp
    /// is `current`: `now` floored to whole seconds, moved to one second past
    /// `current` (also floored) when that is later, so the new stamp is
    /// strictly after every stamp this device has seen for the key even when
    /// its clock runs behind the device that set `current`.
    static func stamp(now: Date, after current: Date?) -> Date {
        let floored = wholeSeconds(now)
        guard let current else { return floored }
        return max(floored, wholeSeconds(current).addingTimeInterval(1))
    }

    /// Whether a record stamped `changedAt` replaces the state stamped
    /// `current`: strictly later only, so a tie keeps what is there. A key
    /// never stamped (`nil`, such as a fold from before two way sync) counts
    /// as `.distantPast` and loses to any record.
    static func supersedes(_ changedAt: Date, current: Date?) -> Bool {
        changedAt > (current ?? .distantPast)
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

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }
}
