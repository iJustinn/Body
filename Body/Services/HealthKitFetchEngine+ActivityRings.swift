//
//  HealthKitFetchEngine+ActivityRings.swift
//  Body
//

import Foundation
import HealthKit

/// Outcome of scanning for ring data older than the already-probed months.
/// `failed` (error) is distinct from `noOlderData` so a transient HealthKit
/// failure never gets recorded as the permanent start of history.
enum ActivityRingOlderHistoryProbe {
    case found(ActivityRingHistorySnapshot)
    case noOlderData
    case failed
}

// Activity Rings summary (one day) and history (range of days, plus the
// per-month-key overload that pages back through older months). The shared
// `activityRingHistoryInterval` and `activityRingSummary` helpers live on
// the main engine file and the sample-parsers extension respectively.
extension HealthKitFetchEngine {
    func fetchActivityRingSummary(calendar: Calendar, date: Date = Date()) async -> ActivityRingSummary {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        let dateComponents = Self.activityDateComponents(for: date, calendar: calendar)

        let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)

        do {
            guard let summary = try await descriptor.result(for: healthStore).first else {
                return .empty
            }

            return Self.activityRingSummary(from: summary)
        } catch {
            return .empty
        }
    }

    func fetchActivityRingHistory(calendar: Calendar, date: Date = Date()) async -> ActivityRingHistorySnapshot {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        let interval = activityRingHistoryInterval(calendar: calendar, date: date)
        let loadedMonthKeys = Self.recentActivityRingMonthKeys(
            count: HealthKitWorkoutStore.recentChartMonthCount,
            from: date,
            calendar: calendar
        )
        return await fetchActivityRingHistory(
            start: interval.start,
            end: interval.end,
            loadedMonthKeys: loadedMonthKeys,
            calendar: calendar
        )
    }

    func fetchDashboardActivityRingHistory(
        calendar: Calendar,
        selection: BodyDashboardFetchSelection,
        date: Date = Date()
    ) async -> ActivityRingHistorySnapshot {
        guard selection.includesActivityRings else {
            return .empty
        }

        return await fetchActivityRingHistory(calendar: calendar, date: date)
    }

    func fetchActivityRingHistory(
        monthKey: ActivityRingMonthKey,
        calendar: Calendar
    ) async -> ActivityRingHistorySnapshot {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        guard
            let start = monthKey.startDate(calendar: calendar),
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: start),
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonthStart)
        else {
            return ActivityRingHistorySnapshot(days: [], loadedMonthKeys: [monthKey])
        }

        return await fetchActivityRingHistory(
            start: start,
            end: end,
            loadedMonthKeys: [monthKey],
            calendar: calendar
        )
    }

    private func fetchActivityRingHistory(
        start: Date,
        end: Date,
        loadedMonthKeys: [ActivityRingMonthKey],
        calendar: Calendar
    ) async -> ActivityRingHistorySnapshot {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        let startComponents = Self.activityDateComponents(for: start, calendar: calendar)
        let endComponents = Self.activityDateComponents(for: end, calendar: calendar)
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComponents, end: endComponents)
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)

        do {
            let summaries = try await descriptor.result(for: healthStore)
            let days = summaries.compactMap { summary -> ActivityRingDaySummary? in
                let components = summary.dateComponents(for: calendar)
                guard let date = calendar.date(from: components) else {
                    return nil
                }

                return ActivityRingDaySummary(
                    date: calendar.startOfDay(for: date),
                    summary: Self.activityRingSummary(from: summary)
                )
            }
            .sorted { $0.date < $1.date }

            return ActivityRingHistorySnapshot(days: days, loadedMonthKeys: loadedMonthKeys)
                .filteringDaysToLoadedMonths(calendar: calendar)
        } catch {
            return .empty
        }
    }

    /// One wide scan for the most recent month with ring data strictly older
    /// than `monthKey`, back to the Apple Watch era (rings cannot predate the
    /// platform). Used when consecutive previous months come back empty so a
    /// long no-watch gap is crossed in a single query, and a true history
    /// start is detected exactly instead of guessed from an empty streak.
    func probeOlderActivityRingHistory(
        before monthKey: ActivityRingMonthKey,
        calendar: Calendar
    ) async -> ActivityRingOlderHistoryProbe {
        guard permissionSelection.includes(.activityRings) else {
            return .failed
        }

        guard
            let eraStart = calendar.date(from: DateComponents(year: 2014, month: 9, day: 1)),
            let monthStart = monthKey.startDate(calendar: calendar),
            let end = calendar.date(byAdding: .day, value: -1, to: monthStart),
            eraStart <= end
        else {
            return .noOlderData
        }

        let startComponents = Self.activityDateComponents(for: eraStart, calendar: calendar)
        let endComponents = Self.activityDateComponents(for: end, calendar: calendar)
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComponents, end: endComponents)
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)

        do {
            let summaries = try await descriptor.result(for: healthStore)
            let days = summaries.compactMap { summary -> ActivityRingDaySummary? in
                let components = summary.dateComponents(for: calendar)
                guard let date = calendar.date(from: components) else {
                    return nil
                }

                return ActivityRingDaySummary(
                    date: calendar.startOfDay(for: date),
                    summary: Self.activityRingSummary(from: summary)
                )
            }

            guard let latestDay = days.max(by: { $0.date < $1.date }) else {
                return .noOlderData
            }

            let foundKey = ActivityRingMonthKey(date: latestDay.date, calendar: calendar)
            let foundMonthDays = days.filter {
                ActivityRingMonthKey(date: $0.date, calendar: calendar) == foundKey
            }
            return .found(ActivityRingHistorySnapshot(days: foundMonthDays, loadedMonthKeys: [foundKey]))
        } catch {
            return .failed
        }
    }

    static func recentActivityRingMonthKeys(
        count: Int,
        from date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> [ActivityRingMonthKey] {
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: date)?.start else {
            return [ActivityRingMonthKey(date: date, calendar: calendar)]
        }

        return (0..<max(count, 1)).compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else {
                return nil
            }

            return ActivityRingMonthKey(date: monthDate, calendar: calendar)
        }
        .sorted { lhs, rhs in
            if lhs.year == rhs.year {
                return lhs.month < rhs.month
            }
            return lhs.year < rhs.year
        }
    }
}
