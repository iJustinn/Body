//
//  BodyTimeZoneLedger.swift
//  Body
//

import Foundation

/// Append-only record of the zones the device has been in, so a night whose
/// sleep samples carry no `HKMetadataKeyTimeZone` (e.g. Apple Watch) can still
/// be read in the zone the device was in on that night rather than always
/// falling back to the current zone. Records are stored in `UserDefaults`
/// (device-local, matching the app's other small-state stores).
/// `@unchecked Sendable`: both stored properties are immutable references to
/// thread-safe Foundation types (`UserDefaults` is documented as thread-safe;
/// `Calendar` is a value type), so the struct carries no mutable shared state.
struct BodyTimeZoneLedger: @unchecked Sendable {
    struct Record: Codable, Equatable {
        let effectiveFrom: Date
        let identifier: String
    }

    private static let storageKey = "bodyDeviceTimeZoneLedger"

    private let defaults: UserDefaults
    private let calendar: Calendar

    /// `autoupdatingCurrent` so the long-lived static ledger keeps computing day
    /// boundaries in the device's *current* zone after an in-process zone change,
    /// rather than the zone captured at init.
    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
    }

    /// Appends the current zone iff it differs from the latest record's (the
    /// first call seeds one record), so the ledger only grows on real changes.
    func recordCurrentZone(now: Date = Date(), zone: TimeZone = .current) {
        var records = loadRecords()
        guard records.last?.identifier != zone.identifier else {
            return
        }
        records.append(Record(effectiveFrom: now, identifier: zone.identifier))
        saveRecords(records)
    }

    /// The identifier of the latest record in effect on `date` — the most recent
    /// record whose `effectiveFrom` is before the end of `date`'s day (computed
    /// via `Calendar` so DST-shortened/lengthened days keep the true next
    /// midnight as the exclusive boundary). `nil` when `date` predates the first
    /// record, so unknown history stays unknown rather than being back-filled
    /// with today's zone.
    func zoneIdentifier(on date: Date) -> String? {
        snapshot().zoneIdentifier(on: date)
    }

    /// The records read once, so a computation that resolves many days (sleep
    /// grouping, the watch's 14-day zone map, a month of workouts) pays a single
    /// `UserDefaults` read and JSON decode instead of one per lookup.
    func snapshot() -> BodyTimeZoneResolver {
        BodyTimeZoneResolver(records: loadRecords(), calendar: calendar)
    }

    /// The append-only record set (internal for tests to assert append behavior),
    /// sorted by `effectiveFrom` so a clock rollback between two records cannot
    /// make the newest stored record the wrong answer for a later date.
    func loadRecords() -> [Record] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let records = try? JSONDecoder().decode([Record].self, from: data) else {
            return []
        }
        return records.sorted { $0.effectiveFrom < $1.effectiveFrom }
    }

    private func saveRecords(_ records: [Record]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// One decoded reading of `BodyTimeZoneLedger`'s records, with the two pure
/// lookups the ledger's callers need. Held for the length of one computation so
/// the records are decoded once rather than once per resolved day.
struct BodyTimeZoneResolver: Sendable {
    let records: [BodyTimeZoneLedger.Record]
    let calendar: Calendar

    /// Day-scoped lookup: the latest record in effect anywhere within `date`'s
    /// day. What a night of sleep needs, since a night is named by its wake day
    /// rather than by an instant.
    func zoneIdentifier(on date: Date) -> String? {
        let dayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        return records.last { $0.effectiveFrom < nextDayStart }?.identifier
    }

    /// Instant-scoped lookup: the zone the device was in at `instant`. What a
    /// workout needs, because the day-scoped rule answers with the end-of-day
    /// zone, which is the wrong one for anything earlier on a travel day and
    /// flips again on the return leg, moving a stored workout's `dateKey` twice.
    func zoneIdentifier(at instant: Date) -> String? {
        records.last { $0.effectiveFrom <= instant }?.identifier
    }
}
