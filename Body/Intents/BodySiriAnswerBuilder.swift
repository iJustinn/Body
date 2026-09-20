//
//  BodySiriAnswerBuilder.swift
//  Body
//
//  Turns Body's persisted snapshots into spoken answers for Siri. Everything
//  here is pure except `BodySiriSnapshotBundle.loadCurrent`, which is the one
//  place that touches the stores, so the wording and the freshness rules are
//  fully testable.
//

import Foundation

// MARK: - Bundle

/// Everything an answer can be built from, read once per request.
struct BodySiriSnapshotBundle {
    var dashboard: HealthDashboardSnapshot?
    /// When the dashboard snapshot was last refreshed successfully.
    var dashboardAsOf: Date?
    var widget: HealthWidgetSnapshot?
    var currentMonthWorkouts: WorkoutMonthSnapshot?
    var previousMonthWorkouts: WorkoutMonthSnapshot?
    var now: Date

    init(
        dashboard: HealthDashboardSnapshot? = nil,
        dashboardAsOf: Date? = nil,
        widget: HealthWidgetSnapshot? = nil,
        currentMonthWorkouts: WorkoutMonthSnapshot? = nil,
        previousMonthWorkouts: WorkoutMonthSnapshot? = nil,
        now: Date = Date()
    ) {
        self.dashboard = dashboard
        self.dashboardAsOf = dashboardAsOf
        self.widget = widget
        self.currentMonthWorkouts = currentMonthWorkouts
        self.previousMonthWorkouts = previousMonthWorkouts
        self.now = now
    }

    /// The only impure code in this file: reads the caches Body already keeps.
    /// Never touches HealthKit.
    static func loadCurrent(now: Date = Date()) -> BodySiriSnapshotBundle {
        // A missing file makes `loadWithContext` migrate legacy defaults and
        // write the file back; a Siri read must never write, so skip it then.
        let loaded = HealthDashboardSnapshotStore.exists()
            ? HealthDashboardSnapshotStore.loadWithContext()
            : nil
        let asOf = loaded?.metadata.freshness?.date
            ?? UserDefaults.standard.object(
                forKey: HealthDashboardSnapshotStore.lastSuccessfulRefreshDateKey
            ) as? Date
        return BodySiriSnapshotBundle(
            dashboard: loaded?.snapshot,
            dashboardAsOf: loaded == nil ? nil : asOf,
            widget: HealthWidgetSnapshotStore.load(),
            currentMonthWorkouts: WorkoutSnapshotStore.load(),
            previousMonthWorkouts: WorkoutSnapshotStore.loadPrevious(),
            now: now
        )
    }
}

// MARK: - Answer

enum BodySiriAvailability: Equatable {
    case available
    case stale
    case partial
    case unavailable
}

struct BodySiriAnswer: Equatable {
    var title: String
    var spoken: String
    var supporting: String
    var valueText: String?
    var unit: String?
    /// The named band behind a score, e.g. readiness "High". Nil otherwise.
    var statusText: String?
    var asOf: Date?
    var availability: BodySiriAvailability
    /// Named items behind the answer, e.g. the warning titles. Empty otherwise.
    var items: [String]
    /// A counted answer's number, e.g. this week's workouts.
    var count: Int?

    init(
        title: String,
        spoken: String,
        supporting: String,
        valueText: String? = nil,
        unit: String? = nil,
        statusText: String? = nil,
        asOf: Date? = nil,
        availability: BodySiriAvailability,
        items: [String] = [],
        count: Int? = nil
    ) {
        self.title = title
        self.spoken = spoken
        self.supporting = supporting
        self.valueText = valueText
        self.unit = unit
        self.statusText = statusText
        self.asOf = asOf
        self.availability = availability
        self.items = items
        self.count = count
    }

    var hasValue: Bool {
        availability == .available || availability == .stale
    }
}

// MARK: - Builder

enum BodySiriAnswerBuilder {

    /// How old a same-day snapshot may be before the answer says when it was taken.
    static let staleInterval: TimeInterval = 6 * 3600

    // MARK: Readiness

    static func readiness(
        bundle: BodySiriSnapshotBundle,
        calendar: Calendar = .bodyGregorian
    ) -> BodySiriAnswer {
        let title = BodySiriMetric.readiness.title

        guard
            let summary = bundle.dashboard?.summary.readiness,
            let score = summary.score,
            let asOf = bundle.dashboardAsOf,
            calendar.isDate(asOf, inSameDayAs: bundle.now)
        else {
            return unavailableAnswer(title: title)
        }

        let isStale = bundle.now.timeIntervalSince(asOf) > staleInterval
        let scoreText = "\(score)"
        let statusTitle = summary.status.title
        var spoken = String(
            localized: "Your readiness in Body is \(scoreText), \(statusTitle)."
        )
        if isStale {
            spoken += " " + String(localized: "That is as of \(timeText(asOf)).")
        }

        return BodySiriAnswer(
            title: title,
            spoken: spoken,
            supporting: String(localized: "\(scoreText), \(statusTitle)."),
            valueText: scoreText,
            unit: readinessUnit,
            statusText: statusTitle,
            asOf: asOf,
            availability: isStale ? .stale : .available
        )
    }

    // MARK: Metrics

    static func metric(
        _ metric: BodySiriMetric,
        bundle: BodySiriSnapshotBundle,
        calendar: Calendar = .bodyGregorian
    ) -> BodySiriAnswer {
        // One source of truth for readiness: the live tile, not the widget cache.
        if metric == .readiness {
            return readiness(bundle: bundle, calendar: calendar)
        }

        let title = metric.title

        guard let widget = bundle.widget else {
            return unavailableAnswer(title: title)
        }

        let sanitized = widget.sanitizingStaleSleep(asOf: bundle.now, calendar: calendar)
        let values = (sanitized.trend(for: metric.widgetMetric)?.displayValues ?? [])
            .filter { !$0.value.isEmpty && $0.value != "--" }

        guard let primary = values.first else {
            return unavailableAnswer(title: title)
        }

        let asOf = widget.generatedDate
        let isStale = !calendar.isDate(asOf, inSameDayAs: bundle.now)
            || bundle.now.timeIntervalSince(asOf) > staleInterval

        let reading = values
            .map { valueText(for: $0) }
            .joined(separator: ", ")
        var spoken = String(localized: "Your \(title) in Body is \(reading).")
        if isStale {
            spoken += " " + String(localized: "That is from the snapshot taken \(dateAndTimeText(asOf)).")
        }

        return BodySiriAnswer(
            title: title,
            spoken: spoken,
            supporting: reading + ".",
            valueText: primary.value,
            unit: primary.unit.isEmpty ? nil : primary.unit,
            asOf: asOf,
            availability: isStale ? .stale : .available
        )
    }

    // MARK: Warnings

    static func warnings(
        bundle: BodySiriSnapshotBundle,
        calendar: Calendar = .bodyGregorian
    ) -> BodySiriAnswer {
        let title = String(localized: "Health Warnings")

        guard
            let summary = bundle.dashboard?.summary,
            let asOf = bundle.dashboardAsOf,
            calendar.isDate(asOf, inSameDayAs: bundle.now)
        else {
            return unavailableAnswer(title: title)
        }

        let events = summary.metricWarnings.filter {
            calendar.isDate($0.endDate, inSameDayAs: bundle.now)
        }

        // A warning can land after the last refresh, so an old snapshot says
        // when it was taken instead of passing as the current state.
        let isStale = bundle.now.timeIntervalSince(asOf) > staleInterval
        let staleNote = " " + String(localized: "That is as of \(timeText(asOf)).")

        guard !events.isEmpty else {
            let supporting = String(localized: "No warnings in Body's cached data for today.")
            return BodySiriAnswer(
                title: title,
                spoken: isStale ? supporting + staleNote : supporting,
                supporting: supporting,
                asOf: asOf,
                availability: isStale ? .stale : .available
            )
        }

        let names = events.map { warningTitle(for: $0.kind) }
        let list = listText(names)
        var spoken = String(localized: "Body's cached data shows \(list) today.")
        if isStale {
            spoken += staleNote
        }

        return BodySiriAnswer(
            title: title,
            spoken: spoken,
            supporting: list + ".",
            valueText: "\(events.count)",
            asOf: asOf,
            availability: isStale ? .stale : .available,
            items: names,
            count: events.count
        )
    }

    // MARK: Workouts

    static func recentWorkouts(
        bundle: BodySiriSnapshotBundle,
        calendar: Calendar = .bodyGregorian
    ) -> BodySiriAnswer {
        let title = String(localized: "Workouts This Week")

        guard let week = calendar.dateInterval(of: .weekOfYear, for: bundle.now) else {
            return unavailableAnswer(title: title)
        }

        let cached = [bundle.currentMonthWorkouts, bundle.previousMonthWorkouts].compactMap { $0 }
        // Coverage only has to reach `now`: the rest of the week has not
        // happened yet, and a week that runs into next month would otherwise
        // demand a month snapshot that cannot exist.
        let required = requiredMonths(start: week.start, end: bundle.now, calendar: calendar)

        var months: [WorkoutMonthSnapshot] = []
        for month in required {
            guard let snapshot = cached.first(where: { $0.year == month.year && $0.month == month.month }) else {
                let spoken = String(
                    localized: "Body has only part of this week's workouts cached. Open Body to refresh."
                )
                return BodySiriAnswer(
                    title: title,
                    spoken: spoken,
                    supporting: spoken,
                    availability: .partial
                )
            }
            months.append(snapshot)
        }

        let workouts = months
            .flatMap(\.days)
            .flatMap(\.workouts)
            .filter { week.contains($0.startDate) }
        let asOf = months.map(\.generatedAt).max()

        guard !workouts.isEmpty else {
            let spoken = String(localized: "No workouts logged in Body this week yet.")
            return BodySiriAnswer(
                title: title,
                spoken: spoken,
                supporting: spoken,
                valueText: "0",
                unit: workoutsUnit,
                asOf: asOf,
                availability: .available,
                count: 0
            )
        }

        let count = workouts.count
        let countText = "\(count)"
        let total = workouts.reduce(0) { $0 + $1.duration }
        let durationText = durationText(for: total)

        var names: [String] = []
        for workout in workouts.sorted(by: { $0.startDate < $1.startDate }) {
            let name = workout.type.displayName
            if !names.contains(name) {
                names.append(name)
            }
        }
        let listed = Array(names.prefix(3))

        let spoken: String
        if listed.isEmpty {
            spoken = String(
                localized: "You have logged \(countText) workouts in Body this week, \(durationText) in total."
            )
        } else {
            let types = listText(listed)
            spoken = String(
                localized: "You have logged \(countText) workouts in Body this week, \(durationText) in total, including \(types)."
            )
        }

        return BodySiriAnswer(
            title: title,
            spoken: spoken,
            supporting: String(localized: "\(countText) workouts, \(durationText)."),
            valueText: countText,
            unit: workoutsUnit,
            asOf: asOf,
            availability: .available,
            items: listed,
            count: count
        )
    }

    // MARK: Shared

    static func unavailableAnswer(title: String) -> BodySiriAnswer {
        let spoken = String(localized: "Open Body once to load your health data, then ask again.")
        return BodySiriAnswer(
            title: title,
            spoken: spoken,
            supporting: spoken,
            availability: .unavailable
        )
    }

    /// Matches the unit the widget's readiness card shows.
    static let readinessUnit = "%"

    static let workoutsUnit = String(localized: "workouts")

    // MARK: - Helpers

    private struct MonthKey: Equatable {
        let year: Int
        let month: Int
    }

    private static func requiredMonths(start: Date, end: Date, calendar: Calendar) -> [MonthKey] {
        let keys = [start, end].map { date -> MonthKey in
            let components = calendar.dateComponents([.year, .month], from: date)
            return MonthKey(year: components.year ?? 0, month: components.month ?? 0)
        }
        return keys[0] == keys[1] ? [keys[0]] : keys
    }

    private static func valueText(for display: HealthWidgetDisplayValue) -> String {
        display.unit.isEmpty ? display.value : "\(display.value) \(display.unit)"
    }

    private static func listText(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        let leading = items.dropLast().joined(separator: ", ")
        return String(localized: "\(leading) and \(last)")
    }

    private static func durationText(for duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(0, duration.rounded())) ?? ""
    }

    private static func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func dateAndTimeText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// The same names the warning cards and Settings rows use.
    private static func warningTitle(for kind: MetricWarningKind) -> String {
        switch kind {
        case .lowHeartRate:
            return String(localized: "Low Heart Rate")
        case .highHeartRate:
            return String(localized: "High Heart Rate")
        case .lowBloodOxygen:
            return String(localized: "Low Blood Oxygen")
        case .highRespiratoryRate:
            return String(localized: "High Respiratory Rate")
        case .highWristTemperature:
            return String(localized: "High Skin Temperature")
        }
    }
}
