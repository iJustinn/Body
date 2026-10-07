//
//  WatchWarningFoldStore.swift
//  BodyWatch
//
//  The watch side of the two way warning fold sync (`WatchWarningFoldSync`).
//  The phone publishes each of today's warnings with its own fold state and
//  stamp (`WatchMetricWarning.isFolded` / `foldChangedAt`); a fold or unfold
//  tapped on the watch becomes a local record, stamped strictly after the
//  state it replaced, which this store keeps, shows at once and sends to the
//  phone. A record shows only while it beats the phone's published stamp, so
//  once the phone accepts it and republishes, the pushed warning carries the
//  same stamp and the phone's state takes over again (a tie goes to the
//  phone); a later change on the phone wins the same way.
//
//  Standalone rather than part of `WatchMetricsModel`: fold state is display
//  only and touches neither the snapshot nor its merge, so a push or a watch
//  compute can never overwrite a tap. Records persist in the watch's own
//  defaults so a fold survives a relaunch before the phone has answered.
//

import Foundation
import os
import WatchConnectivity

@MainActor
final class WatchWarningFoldStore: ObservableObject {
    static let shared = WatchWarningFoldStore()

    /// Delivers a change to the phone; injected so tests can see what would
    /// be sent without a live `WCSession`.
    typealias Send = @MainActor ([WatchWarningFoldSync.Record]) -> Void

    static let defaultsKey = "watchMetricWarningFolds"

    /// How long a record is kept: the phone's
    /// `BodyDismissedMetricWarnings.retentionDayCount`, which lives in the
    /// phone only code. The watch only ever shows today's warnings, so this
    /// is generous; it just keeps the stored list from growing.
    private static let retentionDayCount = 60

    /// The watch's own fold records, keyed by fold key.
    @Published private(set) var records: [String: WatchWarningFoldSync.Record]

    private let defaults: UserDefaults
    private let now: () -> Date
    private let send: Send

    private nonisolated static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchWarningFolds")

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        send: @escaping Send = { WatchWarningFoldStore.sendToPhone($0) }
    ) {
        self.defaults = defaults
        self.now = now
        self.send = send
        self.records = Self.loadRecords(from: defaults)
    }

    /// Whether `warning`'s card shows folded: the watch's record when it is
    /// stamped strictly after the phone's published stamp, else the phone's
    /// state. A tie goes to the phone.
    func isFolded(_ warning: WatchMetricWarning) -> Bool {
        winningRecord(for: warning)?.isFolded ?? warning.isFolded
    }

    /// Flips `warning`'s shown fold state: records the change stamped strictly
    /// after the state it replaces (the winning side's stamp), persists it,
    /// and sends that one record to the phone.
    func toggle(_ warning: WatchMetricWarning) {
        let winner = winningRecord(for: warning)
        let record = WatchWarningFoldSync.Record(
            key: warning.foldKey,
            isFolded: !(winner?.isFolded ?? warning.isFolded),
            changedAt: WatchWarningFoldSync.stamp(now: now(), after: winner?.changedAt ?? warning.foldChangedAt)
        )

        var next = records
        next[record.key] = record
        records = pruned(next)
        persist(records)
        send([record])
    }

    /// Sends again the local records the phone's push doesn't reflect yet:
    /// those whose key is one of `warnings`' fold keys and that still beat
    /// that warning's published stamp (`foldChangedAt`). Such a record keeps
    /// winning on the watch while the phone never learns of it when it was
    /// tapped before the session activated, or when the phone lost its stamps
    /// on a reinstall; the dashboard calls this on every phone push, so the
    /// phone catches up on the next one. All of them go in one `send`, and
    /// nothing is sent when every record is reflected. Safe to repeat: on the
    /// phone a duplicate is a tie and an older record is rejected. Keys not in
    /// `warnings` (another day's, or a warning the phone no longer publishes)
    /// stay put and are never sent.
    func resendUnacknowledged(in warnings: [WatchMetricWarning]) {
        let pending = warnings
            .compactMap { winningRecord(for: $0) }
            .sorted { $0.key < $1.key }
        guard !pending.isEmpty else { return }
        send(pending)
    }

    /// Sends records to the phone: always `transferUserInfo`, which is queued
    /// and survives either side being suspended, and also `sendMessage` while
    /// the phone is reachable, which wakes the iPhone app in the background so
    /// the change lands without waiting for the queue. A duplicate delivery is
    /// a tie on the phone and changes nothing. Before the session has
    /// activated nothing is sent: the fold still shows on the watch, since the
    /// unsent record keeps beating the phone's stamp, and the phone learns of
    /// it only when `resendUnacknowledged(in:)` sends it again on the phone's
    /// next push.
    static func sendToPhone(_ records: [WatchWarningFoldSync.Record]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            Self.logger.info("Warning fold not sent: the session isn't activated")
            return
        }
        guard let payload = WatchWarningFoldSync.payload(for: records) else {
            Self.logger.error("Warning fold not sent: the records didn't encode")
            return
        }

        let session = WCSession.default
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: { _ in },
                errorHandler: { error in
                    Self.logger.error("Warning fold message failed: \(error.localizedDescription, privacy: .public)")
                }
            )
        }
    }

    /// The local record for `warning`'s fold key while it beats the phone's
    /// published stamp, else nil.
    private func winningRecord(for warning: WatchMetricWarning) -> WatchWarningFoldSync.Record? {
        guard let record = records[warning.foldKey],
              WatchWarningFoldSync.supersedes(record.changedAt, current: warning.foldChangedAt) else {
            return nil
        }
        return record
    }

    /// `records` without those changed before the retention window.
    private func pruned(_ records: [String: WatchWarningFoldSync.Record]) -> [String: WatchWarningFoldSync.Record] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now())
        let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDayCount, to: today) ?? today
        return records.filter { $0.value.changedAt >= cutoff }
    }

    private func persist(_ records: [String: WatchWarningFoldSync.Record]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let sorted = records.values.sorted { $0.key < $1.key }
        guard let data = try? encoder.encode(sorted) else {
            Self.logger.error("Warning folds not saved: the records didn't encode")
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func loadRecords(from defaults: UserDefaults) -> [String: WatchWarningFoldSync.Record] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode([WatchWarningFoldSync.Record].self, from: data) else {
            Self.logger.error("Warning folds not loaded: the stored records didn't decode")
            return [:]
        }
        // Keyed by fold key; a duplicate (never written by `persist`) keeps
        // the later stamp rather than trapping.
        return Dictionary(stored.map { ($0.key, $0) }) { first, second in
            second.changedAt > first.changedAt ? second : first
        }
    }
}
