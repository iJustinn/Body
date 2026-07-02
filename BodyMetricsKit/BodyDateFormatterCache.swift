//
//  BodyDateFormatterCache.swift
//  BodyShared
//

import Foundation

/// Process-wide cache for `DateFormatter` instances. Creating a formatter is
/// expensive (ICU setup per instance), and several call sites previously
/// created one per render or per row. `DateFormatter` is thread-safe on
/// modern OS versions; the lock only guards the cache dictionary, which is
/// also touched from the widget process and detached snapshot builders.
enum BodyDateFormatterCache {
    private static let lock = NSLock()
    private static var formattersByKey: [String: DateFormatter] = [:]

    static func formatter(
        dateFormat: String,
        calendar: Calendar = .bodyGregorian,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> DateFormatter {
        let key = "\(dateFormat)|\(calendar.identifier)-\(calendar.firstWeekday)|\(locale.identifier)|\(timeZone.identifier)"

        lock.lock()
        defer { lock.unlock() }

        if let cached = formattersByKey[key] {
            return cached
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        formattersByKey[key] = formatter
        return formatter
    }

    /// Like `formatter(dateFormat:)`, but derives a locale-appropriate pattern
    /// from an ICU template via `setLocalizedDateFormatFromTemplate(_:)`, so
    /// month/weekday ordering follows the locale (e.g. "MMM d" vs "d MMM").
    /// The cache key is prefixed to keep templates distinct from raw formats.
    static func formatter(
        template: String,
        calendar: Calendar = .bodyGregorian,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> DateFormatter {
        let key = "tpl:\(template)|\(calendar.identifier)-\(calendar.firstWeekday)|\(locale.identifier)|\(timeZone.identifier)"

        lock.lock()
        defer { lock.unlock() }

        if let cached = formattersByKey[key] {
            return cached
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        formattersByKey[key] = formatter
        return formatter
    }
}
