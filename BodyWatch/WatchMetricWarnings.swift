//
//  WatchMetricWarnings.swift
//  BodyWatch
//
//  What the watch draws for today's metric threshold warnings: the warning
//  rows on a metric's detail page, the glyph on its dashboard card, and the
//  badges under the hero number. Pure, so the views stay thin and the rules
//  are testable.
//
//  The warnings shown (`shown`) are the phone's pushed ones
//  (`WatchMetricsSnapshot.metricWarnings`) together with the ones this
//  watch's own compute found (`warningChecks`), checked under the phone's
//  thresholds and Warnings selection (`warningSettings`); per kind the
//  earlier start wins. A High Heart Rate warning that starts during a
//  workout this watch read (`workoutSpans`), or within 30 minutes after it,
//  is left out, whichever device found it.
//
//  Only Heart Rate (Low and High Heart Rate), Blood Oxygen (Low Blood
//  Oxygen) and Skin Temp (High Skin Temperature) appear: they are the warned
//  metrics with a watch card and page. Respiratory Rate has no watch home
//  (and Body Radar stays on the iPhone), so its warning has nothing to point
//  at; the phone follows the same rule, where a badge only points at a card
//  the user can see. The phone publishes only the carded kinds, and
//  `title(for:)` drops any other kind a newer phone might send.
//
//  The copy is the phone's own (`BodyMetricWarningCard`), with the same keys,
//  time format and temperature formatter, so the two read the same.
//

import Foundation

/// One warning on a metric's detail page, with its kind decoded and the fold
/// state the card shows.
struct WatchMetricWarningRow: Identifiable, Equatable {
    let warning: WatchMetricWarning
    let kind: MetricWarningKind
    let isFolded: Bool

    var id: String { warning.foldKey }
}

/// One badge under the hero number: a card with an unfolded warning.
struct WatchHeroWarningBadge: Identifiable, Equatable {
    /// The `WatchMetricKindKey` of the card the badge points at.
    let cardKind: String
    /// The card's unfolded warning titles, in kind order. Kept as a list, not
    /// one formatted string, so a hero joins every badge's titles into a single
    /// list for VoiceOver rather than nesting one list inside another.
    let titles: [String]

    var id: String { cardKind }
}

enum WatchMetricWarnings {
    /// Today's warnings for the dashboard and the detail pages: the phone's
    /// `pushed` warnings and this watch's own, from its compute's `checks`.
    ///
    /// * A High Heart Rate warning, pushed or the watch's, that starts inside
    ///   one of `workoutSpans` or the 30 minutes after it is left out
    ///   (`startsInsideWorkout`).
    /// * The watch's own warnings follow the phone's `settings`: an episode
    ///   that started on `now`'s day, of a kind turned on in Warnings and
    ///   with a watch card, checked against the limit the phone holds now. A
    ///   check made under an older limit is set aside until the next compute.
    /// * Per kind the earlier start wins, a tie going to the phone's. A
    ///   pushed warning keeps its own fold state; the watch's takes the fold
    ///   state the phone published for the same fold key.
    /// * Without `settings` (an older phone) only the pushed warnings show.
    static func shown(
        pushed: [WatchMetricWarning],
        checks: [WatchWarningCheck]?,
        workoutSpans: [WatchWorkoutSpan]?,
        settings: WatchWarningSettings?,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [WatchMetricWarning] {
        let isOutsideWorkouts: (WatchMetricWarning) -> Bool = { warning in
            guard let kind = MetricWarningKind(rawValue: warning.kind) else { return true }
            return !startsInsideWorkout(kind: kind, startDate: warning.startDate, spans: workoutSpans)
        }
        var shown = pushed.filter(isOutsideWorkouts)
        let candidates = watchWarnings(pushed: pushed, checks: checks, settings: settings, now: now, calendar: calendar)
        for candidate in candidates where isOutsideWorkouts(candidate) {
            if let index = shown.firstIndex(where: { $0.kind == candidate.kind }) {
                if candidate.startDate < shown[index].startDate {
                    shown[index] = candidate
                }
            } else {
                shown.append(candidate)
            }
        }
        return shown
    }

    /// The warnings whose folds the dashboard sends to the phone again on a
    /// push (`WatchWarningFoldStore.resendUnacknowledged(in:)`): every pushed
    /// warning and this watch's own, each fold key once (the pushed one
    /// first). No workout span leaves one out, so a fold on a warning a
    /// workout now hides, or on one only the watch found, still reaches the
    /// phone.
    static func foldResendList(
        pushed: [WatchMetricWarning],
        checks: [WatchWarningCheck]?,
        settings: WatchWarningSettings?,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [WatchMetricWarning] {
        var foldKeys = Set(pushed.map(\.foldKey))
        let candidates = watchWarnings(pushed: pushed, checks: checks, settings: settings, now: now, calendar: calendar)
        return pushed + candidates.filter { foldKeys.insert($0.foldKey).inserted }
    }

    /// Whether a `kind` warning that started at `startDate` falls inside one
    /// of this watch's workouts or the 30 minutes after it
    /// (`MetricThresholdWarning.workoutExclusionInterval`, both ends included,
    /// as in the phone's detection). Only a kind that leaves workouts out
    /// (High Heart Rate) can; any other kind never does.
    static func startsInsideWorkout(kind: MetricWarningKind, startDate: Date, spans: [WatchWorkoutSpan]?) -> Bool {
        guard kind.excludesWorkouts else { return false }
        return (spans ?? []).contains { span in
            MetricThresholdWarning.workoutExclusionInterval(start: span.start, end: span.end).contains(startDate)
        }
    }

    /// This watch's own warnings, one per check that `shown` lets through
    /// before the workout spans, keyed and folded as the phone keys and folds
    /// its own (`MetricWarningDayKey.foldKey`).
    private static func watchWarnings(
        pushed: [WatchMetricWarning],
        checks: [WatchWarningCheck]?,
        settings: WatchWarningSettings?,
        now: Date,
        calendar: Calendar
    ) -> [WatchMetricWarning] {
        guard let settings else { return [] }
        return (checks ?? []).compactMap { check in
            guard let kind = MetricWarningKind(rawValue: check.kind),
                  let episode = check.episode,
                  calendar.isDate(episode.startDate, inSameDayAs: now),
                  settings.enabledKinds.contains(check.kind),
                  settings.thresholds[check.kind] == check.threshold,
                  title(for: kind) != nil else { return nil }
            let foldKey = MetricWarningDayKey.foldKey(kind: kind, startDate: episode.startDate, calendar: calendar)
            let pushedFold = pushed.first { $0.foldKey == foldKey }
            return WatchMetricWarning(
                kind: check.kind,
                startDate: episode.startDate,
                threshold: check.threshold,
                foldKey: foldKey,
                isFolded: pushedFold?.isFolded ?? false,
                foldChangedAt: pushedFold?.foldChangedAt
            )
        }
    }

    /// The warnings shown on the `cardKind` page, in `MetricWarningKind` order
    /// (Low Heart Rate before High Heart Rate), each with `isFolded`'s state.
    /// A warning belongs to the card whose kind matches its metric
    /// (`MetricWarningKind.metric`, the same raw value as `WatchMetricKindKey`);
    /// unknown kinds and kinds without a watch title are skipped.
    static func rows(
        forCardKind cardKind: String,
        in warnings: [WatchMetricWarning],
        isFolded: (WatchMetricWarning) -> Bool
    ) -> [WatchMetricWarningRow] {
        MetricWarningKind.allCases.flatMap { kind -> [WatchMetricWarningRow] in
            guard kind.metric.rawValue == cardKind, title(for: kind) != nil else { return [] }
            return warnings
                .filter { MetricWarningKind(rawValue: $0.kind) == kind }
                .map { WatchMetricWarningRow(warning: $0, kind: kind, isFolded: isFolded($0)) }
        }
    }

    /// The `cardKind` card's glyph label: its unfolded warnings' titles, list
    /// formatted ("Low Heart Rate and High Heart Rate"). Nil when the card has
    /// none, which hides the glyph; folding a warning hides it from the glyph
    /// and the hero badges for the day, as on the phone.
    static func glyphLabel(
        forCardKind cardKind: String,
        in warnings: [WatchMetricWarning],
        isFolded: (WatchMetricWarning) -> Bool
    ) -> String? {
        let titles = unfoldedTitles(forCardKind: cardKind, in: warnings, isFolded: isFolded)
        guard !titles.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: titles)
    }

    /// The hero's badges: one per card in `cardKinds` (the dashboard's visible
    /// cards, in their order) that has an unfolded warning, carrying that
    /// card's unfolded titles (the glyph label's, before list formatting). A card missing from `cardKinds` (hidden on the
    /// watch, or not published) gets no badge, the phone's rule that a badge
    /// only points at a card the user can see. Empty when `showsOnHero` (the
    /// phone's Show on Home Hero switch) is off.
    static func heroBadges(
        cardKinds: [String],
        warnings: [WatchMetricWarning],
        showsOnHero: Bool,
        isFolded: (WatchMetricWarning) -> Bool
    ) -> [WatchHeroWarningBadge] {
        guard showsOnHero else { return [] }
        return cardKinds.compactMap { cardKind in
            let titles = unfoldedTitles(forCardKind: cardKind, in: warnings, isFolded: isFolded)
            return titles.isEmpty ? nil : WatchHeroWarningBadge(cardKind: cardKind, titles: titles)
        }
    }

    /// The `cardKind` card's unfolded warning titles, in kind order: what its
    /// glyph label lists and its hero badge carries.
    private static func unfoldedTitles(
        forCardKind cardKind: String,
        in warnings: [WatchMetricWarning],
        isFolded: (WatchMetricWarning) -> Bool
    ) -> [String] {
        rows(forCardKind: cardKind, in: warnings, isFolded: isFolded)
            .filter { !$0.isFolded }
            .compactMap { title(for: $0.kind) }
    }

    /// The warning card's title, the phone's. Nil for High Respiratory Rate,
    /// whose metric has no watch card.
    static func title(for kind: MetricWarningKind) -> String? {
        switch kind {
        case .lowHeartRate:
            return String(localized: "Low Heart Rate")
        case .highHeartRate:
            return String(localized: "High Heart Rate")
        case .lowBloodOxygen:
            return String(localized: "Low Blood Oxygen")
        case .highWristTemperature:
            return String(localized: "High Skin Temperature")
        case .highRespiratoryRate:
            return nil
        }
    }

    /// The unfolded card's sentence, the phone's copy: the threshold and the
    /// episode's start time. Blood oxygen's threshold is a whole percent, and
    /// skin temperature's arrives in °C and is shown in the Skin Temp card's
    /// unit (`usesFahrenheit`). Nil for the kind without a watch title.
    static func sentence(for warning: WatchMetricWarning, kind: MetricWarningKind, usesFahrenheit: Bool) -> String? {
        let time = timeText(for: warning.startDate)
        let threshold = warning.threshold
        switch kind {
        case .lowHeartRate:
            return String(localized: "Your heart rate fell below \(Int(threshold)) BPM starting at \(time).")
        case .highHeartRate:
            return String(localized: "Your heart rate rose above \(Int(threshold)) BPM starting at \(time).")
        case .lowBloodOxygen:
            return String(localized: "Your blood oxygen fell below \(Int(threshold))% starting at \(time).")
        case .highWristTemperature:
            let temperature = BodyMetricWarningTemperatureText.text(
                celsius: threshold,
                temperatureUnitPreference: usesFahrenheit ? .fahrenheit : .celsius
            )
            return String(localized: "Your skin temperature rose above \(temperature) starting at \(time).")
        case .highRespiratoryRate:
            return nil
        }
    }

    /// The phone card's time format: two digit hour and minute, no AM/PM.
    static func timeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
