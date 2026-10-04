//
//  WatchMetricWarnings.swift
//  BodyWatch
//
//  What the watch draws for the phone's metric threshold warnings
//  (`WatchMetricsSnapshot.metricWarnings`): the warning rows on a metric's
//  detail page, the glyph on its dashboard card, and the badges under the
//  hero number. Pure, so the views stay thin and the rules are testable.
//
//  Only Heart Rate (Low and High Heart Rate) and Skin Temp (High Skin
//  Temperature) appear: they are the warned metrics with a watch card and
//  page. Blood Oxygen and Respiratory Rate have no watch home, so their
//  warnings have nothing to point at; the phone follows the same rule, where
//  a badge only points at a card the user can see. The phone publishes only
//  the carded kinds, and `title(for:)` drops any other kind a newer phone
//  might send.
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

    /// The warning card's title, the phone's. Nil for Low Blood Oxygen and High
    /// Respiratory Rate, whose metrics have no watch card.
    static func title(for kind: MetricWarningKind) -> String? {
        switch kind {
        case .lowHeartRate:
            return String(localized: "Low Heart Rate")
        case .highHeartRate:
            return String(localized: "High Heart Rate")
        case .highWristTemperature:
            return String(localized: "High Skin Temperature")
        case .lowBloodOxygen, .highRespiratoryRate:
            return nil
        }
    }

    /// The unfolded card's sentence, the phone's copy: the threshold and the
    /// episode's start time. Skin temperature's threshold arrives in °C and is
    /// shown in the Skin Temp card's unit (`usesFahrenheit`). Nil for the kinds
    /// without a watch title.
    static func sentence(for warning: WatchMetricWarning, kind: MetricWarningKind, usesFahrenheit: Bool) -> String? {
        let time = timeText(for: warning.startDate)
        let threshold = warning.threshold
        switch kind {
        case .lowHeartRate:
            return String(localized: "Your heart rate fell below \(Int(threshold)) BPM starting at \(time).")
        case .highHeartRate:
            return String(localized: "Your heart rate rose above \(Int(threshold)) BPM starting at \(time).")
        case .highWristTemperature:
            let temperature = BodyMetricWarningTemperatureText.text(
                celsius: threshold,
                temperatureUnitPreference: usesFahrenheit ? .fahrenheit : .celsius
            )
            return String(localized: "Your skin temperature rose above \(temperature) starting at \(time).")
        case .lowBloodOxygen, .highRespiratoryRate:
            return nil
        }
    }

    /// The phone card's time format: two digit hour and minute, no AM/PM.
    static func timeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
