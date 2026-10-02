//
//  WatchMetricsSnapshot.swift
//  BodyWatchShared
//
//  Compact metrics payload computed on the iPhone, pushed to the watch over
//  WatchConnectivity, and cached for the watch app + complications. Kept
//  deliberately small (formatted strings + a precomputed 0...1 ring fill) so
//  it fits comfortably in `updateApplicationContext`.
//
//  This file is the ONLY member of `BodyWatchShared` compiled into the iOS
//  `Body` target (it just needs to build + encode the snapshot), so it must
//  stay free of SwiftUI / watch-only dependencies.
//

import Foundation
import os

struct WatchMetricColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

/// One day's lowest and highest reading behind a metric's recent-week chart
/// (`WatchMetric.weeklyRanges`), in the metric's display unit: the iPhone's
/// daily range series for the same day.
struct WatchDayRange: Codable, Equatable {
    var low: Double
    var high: Double
}

/// Status band to highlight behind a metric's recent-week chart (Readiness,
/// Training Load) — the value range of TODAY's status, mirroring the iPhone
/// trend chart's highlighted range. A `nil` bound is open-ended (the band fills
/// to that chart edge); the band's color rides on `WatchMetric.tint`.
struct WatchStatusBand: Codable, Equatable {
    var min: Double?
    var max: Double?
    /// Status level name shown beside the value on the detail page (e.g.
    /// "Optimal"). Optional so older snapshots still decode.
    var label: String? = nil
}

/// String keys matching `HealthMetricKind.rawValue` on the iOS side, plus the
/// per-kind look (tint + SF Symbol) shared by the watch app, the complications,
/// and the iOS snapshot builder — one source of truth so the sides can't drift.
/// `ProjectConfigurationTests` pins these against the iOS widget enum.
enum WatchMetricKindKey {
    static let readiness = "readiness"
    static let sleep = "sleep"
    static let heartRate = "heartRate"
    static let heartRateVariability = "heartRateVariability"
    static let restingHeartRate = "restingHeartRate"
    static let trainingLoad = "trainingLoad"
    static let wristTemperature = "wristTemperature"
    /// Stress, the third card. Unlike the other kinds it has no iPhone widget
    /// (`HealthWidgetMetric`), so `ProjectConfigurationTests` pins its look
    /// against the iPhone's `HealthMetricPresentation` row instead.
    static let stress = "stress"
    /// The day's running totals, one card each directly under Resting HR:
    /// today's total so far as the headline and the last 7 days' totals as
    /// the week. Grouped in `dailyTotalKinds` below for the rules that treat
    /// them alike.
    static let steps = "steps"
    static let activeEnergy = "activeEnergy"
    static let restingEnergy = "restingEnergy"
    /// Legacy activity-ring exercise minutes. No longer published: the weekly
    /// workout complication reads `workoutMinutes` below and only falls back to
    /// this kind when it finds a cached snapshot from an older phone build.
    /// Deliberately absent from `displayOrder` (and from the tint/symbol tables
    /// below) so it never reaches the watch app's dashboard, settings, or
    /// detail pager, which all read `orderedMetrics`.
    static let exerciseMinutes = "exerciseMinutes"
    /// Carried for the weekly workout time complication only — the summed
    /// duration of the workouts the app imports, bucketed by the day each one
    /// started. Same complication-only treatment as `exerciseMinutes` above:
    /// absent from `displayOrder` and the tint/symbol tables, because that
    /// complication draws its own color + symbol.
    static let workoutMinutes = "workoutMinutes"

    /// Dashboard ordering — Readiness leads (drawn as the home screen's hero
    /// rather than a card), then Sleep, Training Load and Stress, the heart
    /// vitals, the day's running totals (Steps, Active Energy, Resting Energy)
    /// directly under Resting HR, and Skin Temp last. The watch complications
    /// are independent widgets and don't read this.
    static let displayOrder: [String] = [
        readiness, sleep, trainingLoad, stress, heartRate,
        heartRateVariability, restingHeartRate, steps, activeEnergy,
        restingEnergy, wristTemperature
    ]

    /// The kinds whose headline is today's running total rather than a
    /// reading or a score. It starts over at midnight, so a value built on an
    /// earlier day is cleared at display time (`WatchMetricsSnapshot.sanitized`)
    /// while its week stays, and the detail page draws that week as daily bars.
    static let dailyTotalKinds: Set<String> = [steps, activeEnergy, restingEnergy]

    /// Card/ring tints mirroring the iOS dashboard (`HealthWidgetMetric.tintColor`).
    static func tint(forKind kind: String) -> WatchMetricColor {
        switch kind {
        case readiness: return WatchMetricColor(red: 0.12, green: 0.68, blue: 0.55)
        case sleep: return WatchMetricColor(red: 0.20, green: 0.72, blue: 1.00)
        case heartRate, heartRateVariability, restingHeartRate:
            return WatchMetricColor(red: 1.00, green: 0.25, blue: 0.45)
        case trainingLoad: return WatchMetricColor(red: 1.00, green: 0.38, blue: 0.12)
        // The iPhone's move orange, the same as Training Load's.
        case steps, activeEnergy: return WatchMetricColor(red: 1.00, green: 0.38, blue: 0.12)
        case restingEnergy: return WatchMetricColor(red: 0.14, green: 0.72, blue: 0.42)
        case wristTemperature: return WatchMetricColor(red: 0.00, green: 0.75, blue: 0.85)
        case stress: return WatchMetricColor(red: 0.90, green: 0.35, blue: 0.75)
        default: return WatchMetricColor(red: 0.55, green: 0.55, blue: 0.60)
        }
    }

    /// SF Symbols mirroring the iOS dashboard (`HealthWidgetMetric.symbolName`).
    static func symbolName(forKind kind: String) -> String {
        switch kind {
        case readiness: return "bolt.heart.fill"
        case sleep: return "bed.double.fill"
        case heartRate, restingHeartRate: return "heart.fill"
        case heartRateVariability: return "waveform.path.ecg"
        case trainingLoad: return "figure.strengthtraining.traditional"
        case steps: return "figure.walk"
        case activeEnergy: return "flame.fill"
        case restingEnergy: return "leaf.fill"
        case wristTemperature: return "thermometer.medium"
        case stress: return "brain.head.profile.fill"
        default: return "heart.text.square"
        }
    }

    /// How old a locally-measured live reading (or the accepted HealthKit
    /// sample) may be before the watch treats that metric as stale. Evaluated
    /// PER KIND: heart rate moves minute-to-minute (30 min), HRV is a slow
    /// overnight metric (4h). A single shared window would either thrash HR or
    /// instantly re-stale a freshly-accepted multi-hour-old HRV, wedging the
    /// live-read loop. Used by both `WatchHealthStore` (sample acceptance) and
    /// `WatchMetricsModel.isStale`. Kinds without a live path fall back to the
    /// snapshot-level stale interval.
    static func liveFreshnessLimit(forKind kind: String) -> TimeInterval {
        switch kind {
        case heartRate: return 30 * 60
        case heartRateVariability: return 4 * 60 * 60
        default: return WatchMetricsSnapshot.staleInterval
        }
    }
}

/// Deep-link scheme shared by the watch complications (`widgetURL`) and the
/// watch app (`onOpenURL`), so tapping a metric complication opens that metric's
/// detail page directly instead of the dashboard.
enum WatchMetricDeepLink {
    static let scheme = "body"
    static let host = "metric"

    static func url(forKind kind: String) -> URL? {
        URL(string: "\(scheme)://\(host)/\(kind)")
    }

    /// Opens the watch home page rather than a metric's detail page. The
    /// Readiness complication uses it: Readiness is the home page's hero.
    static let homeHost = "home"
    static let homeURL = URL(string: "\(scheme)://\(homeHost)")

    static func isHome(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == homeHost
    }

    static func kind(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let kind = url.lastPathComponent
        return kind.isEmpty || kind == "/" ? nil : kind
    }
}

struct WatchMetric: Codable, Equatable, Identifiable {
    /// `HealthMetricKind.rawValue` from the iOS app. That enum is iOS-target
    /// bound, so the shared payload carries the raw string instead.
    var kind: String
    var title: String
    /// Primary value shown on the watch card (e.g. "62", "7h 32m", "99").
    var displayValue: String
    var unit: String
    /// 0...100 score for score-style metrics (Readiness, Sleep). The ring shows
    /// this number when present; otherwise it shows `displayValue`.
    var score: Int?
    /// 0...1 ring fill, precomputed on the iPhone. (The SF Symbol is derived
    /// from `kind` via `WatchMetricKindKey`; the tint usually is too, unless a
    /// score-dependent one is carried in `tint` — see `resolvedTint`.)
    var fillFraction: Double
    /// Current numeric value + recent-range bounds so the watch can recompute
    /// the fill for live-refreshed metrics (HR/HRV) without the iPhone.
    var rawValue: Double?
    var rangeMin: Double?
    var rangeMax: Double?
    /// For banded metrics (Readiness, Training Load): the min/max of the value's
    /// CURRENT status band, so the watch corner gauge spans just that band (e.g.
    /// High 80–94) instead of the full range. nil for unbanded metrics; the band
    /// color rides on `tint`.
    var levelMin: Double? = nil
    var levelMax: Double? = nil
    /// Set on the watch when this metric was refreshed from watch-local
    /// HealthKit; never set by the iPhone builder. Lets the watch keep a live
    /// reading that's fresher than the vitals a later phone push carries.
    var liveUpdatedAt: Date? = nil

    /// When this metric's underlying data was computed/measured (set by the
    /// snapshot builder). Provenance alongside `WatchMetricsSnapshot.source`.
    var computedAt: Date? = nil

    /// When the reading behind `displayValue` was actually MEASURED (a latest
    /// sample's `endDate`; the sleep night's end) — the value's event
    /// watermark, distinct from `computedAt`, which for a phone publish is the
    /// refresh/query time. The merge compares nonblank measurements
    /// event-to-event through this: under HealthKit replication lag the
    /// phone's query time exceeds the event time of the (older) sample it
    /// actually saw, and comparing against it would both reject a genuinely
    /// newer watch reading and let a later push overwrite one. Stamped by the
    /// shared builder for HR / Resting HR / HRV / Sleep; nil for computed
    /// metrics (Readiness, Training Load), whose `computedAt` is the honest
    /// watermark, and for payloads from before this field.
    var measuredAt: Date? = nil

    /// Tint that can't be derived from `kind` alone — Readiness carries its
    /// status-band color here. `nil` ⇒ fall back to the kind's static tint.
    var tint: WatchMetricColor? = nil

    /// Last 7 daily values (oldest → today; `nil` for a day with no reading), in
    /// the same unit as `displayValue`, feeding the watch metric-detail
    /// sparkline. Optional/defaulted per the schema-evolution note below so an
    /// older phone (omits it) or older watch (ignores it) still decodes.
    var weekly: [Double?]? = nil

    /// The instant `weekly`'s last slot was windowed on (the builder's `now`),
    /// so the series can be re-windowed from ITS OWN day rather than the
    /// snapshot's. The two differ after an on-watch compute: the merge keeps
    /// the phone's `generatedAt` (the publication line is never advanced) while
    /// the adopted week ends on the compute day, and rewinding a same-day week
    /// from yesterday's `generatedAt` shifted every bar one day too far.
    /// Optional/defaulted per the schema-evolution note below; a payload
    /// without it (an older phone) falls back to `generatedAt`.
    var weeklyAsOf: Date? = nil

    /// `weekly` re-windowed so its last slot lands on `today`: normalized to
    /// exactly 7 slots (newest kept, missing older days padded with nil), then
    /// days elapsed since the week's own day (`weeklyAsOf`, else the
    /// snapshot's build day) are shifted out with nil slots appended. A cached
    /// snapshot is only rewritten when the phone pushes or the watch computes,
    /// so without this a complication drawn after midnight would keep
    /// yesterday as its rightmost day.
    func weeklyRewound(from generatedAt: Date, to today: Date, calendar: Calendar = .current) -> [Double?] {
        rewound(weekly ?? [], from: generatedAt, to: today, calendar: calendar)
    }

    /// Each day's lowest and highest reading behind the recent-week chart
    /// (oldest → today, `nil` for a day without both), aligned slot for slot
    /// with `weekly` and windowed on the same `weeklyAsOf`. Heart Rate and HRV
    /// only, drawn as a capsule per day under the line. Not to be confused
    /// with `rangeMin`/`rangeMax`, the whole-series bounds the ring fill and
    /// corner gauge scale against. Optional/defaulted per the schema-evolution
    /// note below: an older phone omits it and the chart is the plain line.
    var weeklyRanges: [WatchDayRange?]? = nil

    /// `weeklyRanges` re-windowed onto `today` exactly like `weeklyRewound`,
    /// so a day's capsule stays under that day's point.
    func weeklyRangesRewound(from generatedAt: Date, to today: Date, calendar: Calendar = .current) -> [WatchDayRange?] {
        rewound(weeklyRanges ?? [], from: generatedAt, to: today, calendar: calendar)
    }

    /// The week's last 7 slots (missing older days padded with nil), shifted
    /// by the days elapsed from the week's own day (`weeklyAsOf`, else the
    /// snapshot's build day) to `today`, with nil slots appended.
    private func rewound<Slot>(_ slots: [Slot?], from generatedAt: Date, to today: Date, calendar: Calendar) -> [Slot?] {
        let recent = Array(slots.suffix(7))
        let padded = Array(repeating: Slot?.none, count: 7 - recent.count) + recent
        let snapshotDay = calendar.startOfDay(for: weeklyAsOf ?? generatedAt)
        let entryDay = calendar.startOfDay(for: today)
        let elapsed = calendar.dateComponents([.day], from: snapshotDay, to: entryDay).day ?? 0
        let shift = min(max(elapsed, 0), 7)
        guard shift > 0 else { return padded }
        return Array(padded.dropFirst(shift)) + Array(repeating: nil, count: shift)
    }

    /// Status band to highlight behind the recent-week chart for banded metrics
    /// (Readiness, Training Load) — TODAY's status range, in the same unit as
    /// `weekly`. `nil` for unbanded metrics. See `WatchStatusBand`.
    var statusBand: WatchStatusBand? = nil

    /// Today's live value when same-day activity lowered it below today's
    /// `weekly` slot (Readiness: the drained score under the frozen morning
    /// point) — feeds the detail sparkline's faded "current" dot. nil when
    /// nothing drained and for every other metric. Optional + defaulted per
    /// the schema-evolution note below.
    var weeklyCurrentValue: Double? = nil

    /// Readiness only: the PUBLISHER's own same-day drain report, the workouts
    /// it drained and the undrained score it started from. Stamped by the
    /// shared builder on both the phone's publish and the watch's compute; nil
    /// for every other metric, when Workouts isn't readable, and for payloads
    /// from before this field (an unknown report, never an empty one).
    var drain: WatchReadinessDrainReport? = nil

    /// Readiness only, WATCH SIDE only (the phone never sets it): the latest
    /// drain report received from each device, kept by the merge so the
    /// displayed score can carry the union of both. See
    /// `WatchReadinessDrainReconciler`.
    var drainReports: WatchReadinessDrainReports? = nil

    /// Whether `displayValue`/`unit` are in Fahrenheit, stamped by the builder
    /// for Skin Temp only (`nil` for every other metric, and for snapshots from
    /// a phone build before this field). Lets the corner gauge convert its
    /// carried Celsius range without sniffing the unit string.
    var usesFahrenheit: Bool? = nil

    /// Whether `displayValue`/`unit` and `weekly` are in kilojoules, stamped
    /// by the builder for Active Energy and Resting Energy only (`nil` for
    /// every other metric, and for snapshots from a phone build before this
    /// field). Unlike `unit` it survives `cleared()`, so the energy
    /// complications' header reads it to keep naming the week's unit after
    /// the midnight clear blanks the reading.
    var usesKilojoules: Bool? = nil

    var id: String { kind }

    /// Whether this metric carries a real reading (vs. a `--` placeholder). Used
    /// by the watch merge so an empty value never overwrites a good one. The
    /// sleep metric can have a real duration `displayValue` with no `rawValue`
    /// (its score hidden by the phone's "Show Sleep Score" toggle), so the
    /// placeholder `displayValue` — not just a nil `rawValue` — defines "no value."
    var hasValue: Bool { rawValue != nil || displayValue != "--" }

    /// The tint to render: the carried dynamic `tint`, else the kind default.
    var resolvedTint: WatchMetricColor { tint ?? WatchMetricKindKey.tint(forKind: kind) }

    /// This metric with its reading cleared to the builder's empty state
    /// ("--", no score/fill/value), keeping identity + chart context (kind,
    /// title, weekly, ranges, and the week's `usesKilojoules`). Reuses the
    /// file's existing "--" sentinel (see `hasValue`) so it matches the value
    /// the snapshot builder emits for a metric it has no reading for. Used by
    /// `WatchMetricsSnapshot.sanitized`.
    func cleared() -> WatchMetric {
        var metric = self
        metric.displayValue = "--"
        metric.unit = ""
        metric.score = nil
        metric.fillFraction = 0
        metric.rawValue = nil
        metric.liveUpdatedAt = nil
        metric.measuredAt = nil
        metric.weeklyCurrentValue = nil
        return metric
    }
}

/// What one device knew about today's activity drain when it produced a
/// readiness value. Self-contained (no BodyMetricsKit types) because this file
/// is also compiled into the watch widget extension.
struct WatchReadinessDrainReport: Codable, Equatable {
    struct Contribution: Codable, Equatable {
        /// The workout's HealthKit UUID string, identical on both devices.
        var id: String
        var start: Date
        /// Drain points before the total cap.
        var points: Double
    }

    /// The readiness score before any drain.
    var undrainedScore: Int
    /// Start of the wake cycle the workouts were read over.
    var cycleStart: Date
    var contributions: [Contribution]
}

struct WatchReadinessDrainReports: Codable, Equatable {
    var phone: WatchReadinessDrainReport?
    var watch: WatchReadinessDrainReport?
    /// Workouts the watch reported and then stopped finding (deleted), which
    /// the phone's report may keep listing until the deletion replicates.
    var watchRemovedIDs: [String]?
}

/// One stage segment of the night's main sleep session, for the watch
/// Sleep Stages complication. `stage` is the `SleepStage` raw value
/// ("awake" / "rem" / "core" / "deep") as a string so this file stays free
/// of BodyMetricsKit.
struct WatchSleepStageSegment: Codable, Equatable {
    var stage: String
    var startDate: Date
    var endDate: Date
}

/// The Sleep page's Sleep Debt for the last `SleepDebtChartModel.watchNightCount`
/// wake days: the same 14 night debt the iPhone's Sleep Debt card shows for
/// each of those nights, built by the shared snapshot builder on either device.
/// Plain values so this file stays free of BodyMetricsKit.
struct WatchSleepDebt: Codable, Equatable {
    struct Night: Codable, Equatable {
        /// Start of the wake day.
        var day: Date
        /// `SleepDebtNight.debtAfterNight`: nil while fewer than 5 of the
        /// window's nights were recorded, and for today until its night arrives.
        var debt: TimeInterval?
        /// Whether any sleep was recorded for the day.
        var isRecorded: Bool
    }

    /// The headline, `SleepDebtChartModel.debt`: today's debt once today's
    /// night is recorded, otherwise yesterday's.
    var debt: TimeInterval?
    /// Oldest first, ending on the day the debt was built.
    var nights: [Night]
    /// The information cutoff behind the debt, compared by the merge: the
    /// phone's refresh time for a pushed debt, the compute's coverage for one
    /// the watch built. Nil once a permission change stripped local provenance.
    var computedAt: Date?

    /// Whether any night has a debt to plot.
    var hasChartableNight: Bool {
        nights.contains { $0.debt != nil }
    }
}

/// The Stress page's "Last 12 hours" chart: the recent 15 minute Stress windows,
/// built by the shared `WatchStressTimelineBuilder` on either device. Compact
/// on purpose, since it rides every push: one entry per window from `start`
/// instead of a pair of dates each. Plain values so this file stays free of
/// BodyMetricsKit.
struct WatchStressTimeline: Codable, Equatable {
    /// The length of one window, `StressScoreCalculator.windowDuration`.
    static let slotLength: TimeInterval = 15 * 60
    /// The marker in `slots` for a window masked as movement.
    static let activityMarker = -1

    /// What one window shows.
    enum Slot: Equatable {
        /// A scored window, rounded. `StressBand`'s bounds sit on .5, so the
        /// rounded score always falls in the same band as the exact one.
        case scored(Int)
        /// Masked as movement (a workout or a busy hour): a stub, no score.
        case activity
        /// No score (too few readings): a gap.
        case none
    }

    /// The first window's start. Windows run back to back from here, on the
    /// stress grid (local midnight plus whole 15 minute steps).
    var start: Date
    /// When the timeline was built: the latest window is drawn only up to here.
    var end: Date
    /// One entry per window from `start`: a score 0...100, `activityMarker`,
    /// or nil for an unscored window. Read through `slot(at:)`.
    var slots: [Int?]
    /// Sleep and workout shading behind the windows, oldest first.
    var context: [WatchStressContextBand]
    /// The information cutoff behind the windows, compared by the merge like
    /// `WatchSleepDebt.computedAt`: the phone's refresh time for a pushed
    /// timeline, the compute's coverage for one the watch built. Nil once a
    /// permission change stripped local provenance.
    var computedAt: Date?

    func slot(at index: Int) -> Slot {
        guard slots.indices.contains(index), let value = slots[index] else { return .none }
        return value == Self.activityMarker ? .activity : .scored(value)
    }

    /// The window `index` covers: 15 minutes from its start, the latest one
    /// cut at `end`.
    func interval(at index: Int) -> DateInterval {
        let slotStart = start.addingTimeInterval(Double(index) * Self.slotLength)
        let slotEnd = min(slotStart.addingTimeInterval(Self.slotLength), max(end, slotStart))
        return DateInterval(start: slotStart, end: slotEnd)
    }

    /// Whether any window is drawn (scored or activity).
    var hasMarks: Bool {
        slots.contains { $0 != nil }
    }
}

/// One shaded stretch behind the Stress windows. `kind` is "sleep" (the main
/// session), "nap" or "workout"; `workoutType` is the `BodyWorkoutType` raw
/// value for a workout, so this file stays free of BodyMetricsKit.
struct WatchStressContextBand: Codable, Equatable {
    static let sleepKind = "sleep"
    static let napKind = "nap"
    static let workoutKind = "workout"

    var kind: String
    var start: Date
    var end: Date
    var workoutType: String? = nil
}

/// One workout for the watch Day Ring hero. `type` is the `BodyWorkoutType` raw
/// value as a string so this file stays free of BodyMetricsKit; `colorHex` is
/// the phone's resolved palette color, custom workout colors included.
struct WatchDayRingWorkout: Codable, Equatable {
    var id: String
    var type: String
    var startDate: Date
    var endDate: Date
    var colorHex: UInt32
}

/// Schema evolution: the phone and watch can run different builds, so any new
/// field here (or on `WatchMetric`) must be optional or defaulted — a required
/// field would make older watches silently reject the whole payload.
struct WatchMetricsSnapshot: Codable, Equatable {
    var generatedAt: Date
    var lastRefreshDate: Date?
    var metrics: [WatchMetric]
    /// Which device produced this snapshot: "phone" for an iPhone publish,
    /// "watch" for one the watch computed on-device from the phone's compute
    /// seed. Provenance only — the merge decides by per-metric recency and
    /// value presence, and a watch compute never advances the phone's
    /// `(publisherEpoch, revision)` line, so the displayed snapshot keeps the
    /// phone's `source` even after adopting watch-computed metrics.
    var source: String? = nil
    /// The calendar day the carried Sleep metric belongs to (the sleep
    /// session's day), stamped by the snapshot builder. Lets the watch re-check
    /// at DISPLAY time — via `sanitized(asOf:)` — that a persisted snapshot's
    /// Sleep still belongs to today; the phone's build-time `SleepSummary.asOf`
    /// guard can't cover a snapshot that outlives midnight in the App Group
    /// cache. Optional so snapshots from before this field decode (nil ⇒
    /// unknown, treated as not-today by `sanitized`).
    var sleepNight: Date? = nil
    /// The stage segments of the Sleep METRIC's night, for the watch Sleep
    /// Stages complication: the MAIN session only (naps excluded), matching the
    /// iPhone Home Screen Sleep Stages widget. Describes the same night as
    /// `sleepNight`, so it moves with the Sleep metric wherever that does (the
    /// merge) and is dropped with it (`sanitized(asOf:)`). `nil` when the night
    /// is unknown or carries no segments. Optional so snapshots from before
    /// this field decode.
    var sleepStages: [WatchSleepStageSegment]? = nil
    /// The Sleep page's Sleep Debt. Unlike `sleepStages` it does not move with
    /// the Sleep metric: it has its own provenance (`WatchSleepDebt.computedAt`)
    /// and merge rule, since the debt moves on at midnight and on a night with
    /// no sleep, when the Sleep card is not adopted. Optional so snapshots from
    /// before this field decode.
    var sleepDebt: WatchSleepDebt? = nil
    /// Whether the phone shows Sleep Debt: Body Pro unlocked and the Summary
    /// Cards toggle on. A display preference, so it rides the display payload
    /// and only a phone push sets it; the watch computes the debt either way
    /// and shows it only while this is true. Nil (an older phone, which never
    /// shipped a debt) reads as off.
    var showsSleepDebt: Bool? = nil
    /// The Stress page's "Last 12 hours" chart. Like `sleepDebt` it does not
    /// move with its card: it has its own provenance
    /// (`WatchStressTimeline.computedAt`) and merge rule, since the windows
    /// keep coming after midnight while the new day's average is still blank.
    /// No sanitize rule: the page draws only the windows inside its own last
    /// 12 hours. Optional so snapshots from before this field decode.
    var stressTimeline: WatchStressTimeline? = nil
    /// The phone's custom workout colors (`BodyWorkoutColorOverrides` raw
    /// form, empty without Body Pro), for the workout shading on the Stress
    /// chart. A display preference, so only a phone push sets it; nil (an
    /// older phone) reads as the built-in colors.
    var workoutColorOverrides: String? = nil

    /// The phone's Settings ▸ Home Hero ▸ Readiness Level switch: whether the
    /// readiness hero names today's level under the score. A display
    /// preference, so it rides the display payload rather than the compute
    /// seed (whose settings signature would invalidate computed values on a
    /// toggle). Optional so an older phone's payload decodes; nil reads as on,
    /// the phone's default.
    var readinessHeroShowsLevel: Bool? = nil

    /// The phone's Settings ▸ Home Hero choice, as the `BodyStarMetric` raw
    /// value ("readiness" / "dayRing", empty for None), so the watch shows the
    /// same hero. Optional so an older phone's payload decodes; nil and None
    /// read as the Readiness Ring, the hero the watch always had.
    var homeHero: String? = nil
    /// The phone's Home Hero ▸ Day Caption switch; nil reads as on.
    var dayRingShowsCaption: Bool? = nil
    /// The workouts around today for the Day Ring hero, published only while it
    /// is the chosen hero. The night's bar comes from `sleepStages`.
    var dayRingWorkouts: [WatchDayRingWorkout]? = nil

    /// Identifies the phone install that produced this snapshot: a UUID
    /// persisted in phone UserDefaults, regenerated on reinstall / data reset.
    /// Together with `revision` it lets the watch order snapshots WITHOUT
    /// trusting the device clock — a rollback can't make a stale payload outrank
    /// a newer one (see `supersedes`). Optional so a legacy payload (no epoch,
    /// from an older phone) still decodes and falls back to the `generatedAt`
    /// rule.
    var publisherEpoch: String? = nil
    /// Monotonic counter WITHIN `publisherEpoch`, persisted and advanced on the
    /// phone each time it publishes. Authoritative over `generatedAt` when the
    /// epochs match, so it survives a clock rollback. Optional/defaulted for
    /// schema evolution; a watch-local live HR/HRV refresh never advances it.
    var revision: UInt64? = nil

    /// Set by the phone's Clear-Cache path: this is a reset tombstone — empty
    /// metrics that the watch must ADOPT (replacing its snapshot) rather than
    /// blank-preserve merge, so cleared data doesn't linger. It still rides the
    /// normal `(publisherEpoch, revision)` ordering (`supersedes`), so a stale
    /// lower-revision push can't resurrect the data it cleared, and the watch
    /// persists it as a tombstone to keep that ordering across a restart.
    /// Optional so phone/watch version skew still decodes (an older watch just
    /// merges the empty-metrics payload, which clears it anyway).
    var isReset: Bool? = nil

    /// Pushed data older than this is stale: the watch app live-refreshes
    /// HR/HRV past it, and the complication timeline re-checks on the same
    /// cadence.
    static let staleInterval: TimeInterval = 30 * 60

    static let empty = WatchMetricsSnapshot(
        generatedAt: .distantPast,
        lastRefreshDate: nil,
        metrics: []
    )

    /// Representative sample data for the complication gallery — never shown
    /// on a configured complication (real timelines read the cached store).
    static let placeholder = WatchMetricsSnapshot(
        generatedAt: .distantPast,
        lastRefreshDate: nil,
        metrics: [
            WatchMetric(kind: WatchMetricKindKey.readiness, title: String(localized: "Readiness", table: "BodyWatchShared"), displayValue: "78", unit: "%", score: 78, fillFraction: 0.78, rawValue: 78, rangeMin: 0, rangeMax: 100, levelMin: 65, levelMax: 79, tint: WatchMetricColor(red: 0.10, green: 0.82, blue: 0.20), statusBand: WatchStatusBand(min: 65, max: 80, label: String(localized: "Moderate", table: "BodyWatchShared"))),
            WatchMetric(kind: WatchMetricKindKey.sleep, title: String(localized: "Sleep", table: "BodyWatchShared"), displayValue: "7h 32m", unit: "", score: 85, fillFraction: 0.85, rawValue: 85, rangeMin: 0, rangeMax: 100),
            WatchMetric(kind: WatchMetricKindKey.heartRate, title: String(localized: "Heart Rate", table: "BodyWatchShared"), displayValue: "62", unit: "bpm", score: nil, fillFraction: 0.45, rawValue: 62, rangeMin: 54, rangeMax: 72),
            WatchMetric(kind: WatchMetricKindKey.heartRateVariability, title: String(localized: "HRV", table: "BodyWatchShared"), displayValue: "48", unit: "ms", score: nil, fillFraction: 0.60, rawValue: 48, rangeMin: 30, rangeMax: 60),
            WatchMetric(kind: WatchMetricKindKey.restingHeartRate, title: String(localized: "Resting HR", table: "BodyWatchShared"), displayValue: "56", unit: "bpm", score: nil, fillFraction: 0.70, rawValue: 56, rangeMin: 52, rangeMax: 64),
            // The day's running totals draw their week as bars, so each needs a
            // sample week (oldest → today) ending on its headline. Filled
            // against the week's best day, as the builder fills them.
            WatchMetric(kind: WatchMetricKindKey.steps, title: String(localized: "Steps", table: "BodyWatchShared"), displayValue: "8,432", unit: "", score: nil, fillFraction: 8432.0 / 11020.0, rawValue: 8432, rangeMin: 0, rangeMax: 11020, weekly: [6210, 9870, 7540, 11020, 4980, 8300, 8432]),
            WatchMetric(kind: WatchMetricKindKey.activeEnergy, title: String(localized: "Active Energy", table: "BodyWatchShared"), displayValue: "512", unit: "kcal", score: nil, fillFraction: 512.0 / 720.0, rawValue: 512, rangeMin: 0, rangeMax: 720, weekly: [430, 610, 380, 720, 290, 540, 512], usesKilojoules: false),
            WatchMetric(kind: WatchMetricKindKey.restingEnergy, title: String(localized: "Resting Energy", table: "BodyWatchShared"), displayValue: "1,640", unit: "kcal", score: nil, fillFraction: 1640.0 / 1668.0, rawValue: 1640, rangeMin: 0, rangeMax: 1668, weekly: [1610, 1655, 1590, 1632, 1601, 1668, 1640], usesKilojoules: false),
            WatchMetric(kind: WatchMetricKindKey.trainingLoad, title: String(localized: "Training Load", table: "BodyWatchShared"), displayValue: "1.05", unit: "", score: nil, fillFraction: 0.53, rawValue: 1.05, rangeMin: 0, rangeMax: 2, levelMin: 0.8, levelMax: 1.3, tint: WatchMetricColor(red: 0.10, green: 0.82, blue: 0.20)),
            WatchMetric(kind: WatchMetricKindKey.wristTemperature, title: String(localized: "Skin Temp", table: "BodyWatchShared"), displayValue: "93.4", unit: "°F", score: nil, fillFraction: 0.50, rawValue: 34.1, rangeMin: 33.8, rangeMax: 34.4),
            // The weekly workout time complication draws only `weekly`, so the
            // gallery preview needs a sample week (oldest → today) rather than
            // seven empty bars. Rest days carry an explicit `0`, matching the
            // dense week the phone publishes.
            WatchMetric(kind: WatchMetricKindKey.workoutMinutes, title: String(localized: "Weekly Workout Time", table: "BodyWatchShared"), displayValue: "38", unit: "", score: nil, fillFraction: 0, weekly: [12, 30, 0, 45, 22, 0, 38])
        ],
        // The Sleep Stages complication draws only `sleepStages`, so the
        // gallery preview needs a sample night rather than an empty bar.
        sleepStages: placeholderSleepStages
    )

    /// The placeholder's night: a main session from 23:10 to 06:42 (7h 32m,
    /// matching the sample Sleep metric above), cycling through the stages with
    /// a brief wake at the start and one mid-night. Anchored to a FIXED instant
    /// (2026-06-03 23:10 UTC) rather than `Date()` so this `static let` stays
    /// deterministic.
    private static let placeholderSleepStages: [WatchSleepStageSegment] = {
        let pattern: [(stage: String, minutes: Double)] = [
            ("awake", 8), ("core", 42), ("deep", 38), ("core", 25), ("rem", 22),
            ("core", 34), ("deep", 29), ("core", 31), ("rem", 27), ("awake", 6),
            ("core", 46), ("deep", 18), ("core", 40), ("rem", 33), ("core", 53)
        ]
        var start = Date(timeIntervalSinceReferenceDate: 802_221_000)
        return pattern.map { segment in
            let end = start.addingTimeInterval(segment.minutes * 60)
            let built = WatchSleepStageSegment(stage: segment.stage, startDate: start, endDate: end)
            start = end
            return built
        }
    }()

    func metric(forKind kind: String) -> WatchMetric? {
        metrics.first { $0.kind == kind }
    }

    /// Whether this snapshot should replace `other` on the watch — the ordering
    /// that survives a device-clock rollback. When both carry the same
    /// `publisherEpoch`, the monotonic `revision` is authoritative (a rolled-back
    /// clock can't let an older payload's `generatedAt` outrank a newer one);
    /// equal revisions tie-break on `generatedAt`. A different or unknown epoch
    /// means a reinstall/reset produced this payload, so accept it and adopt its
    /// epoch (reinstall wins). When neither side carries an epoch (a legacy
    /// payload), fall back to the plain `generatedAt` rule.
    func supersedes(_ other: WatchMetricsSnapshot) -> Bool {
        switch (publisherEpoch, other.publisherEpoch) {
        case let (epoch?, otherEpoch?) where epoch == otherEpoch:
            let revision = revision ?? 0
            let otherRevision = other.revision ?? 0
            return revision == otherRevision
                ? generatedAt > other.generatedAt
                : revision > otherRevision
        case (nil, nil):
            return generatedAt > other.generatedAt
        default:
            return true
        }
    }

    /// Metrics in dashboard display order, skipping any kind absent from this
    /// snapshot. Shared by the watch dashboard and its settings list.
    var orderedMetrics: [WatchMetric] {
        WatchMetricKindKey.displayOrder.compactMap { metric(forKind: $0) }
    }

    /// Display-time staleness guard mirroring the phone's build-time
    /// `SleepSummary.asOf`: a persisted snapshot (App Group cache) can outlive
    /// midnight, so re-check that its carried Sleep metric still belongs to
    /// `now`'s day. When `sleepNight` is a prior day — or unknown (nil, e.g. a
    /// snapshot built before this field existed, or by an older phone) — the
    /// Sleep metric is cleared to the builder's "--"/nil-score empty state so
    /// the watch app and complications never show yesterday's sleep as today's.
    /// A blanked legacy snapshot is corrected on the next phone push (at most
    /// one sync away), which we prefer over presenting a night we can't verify.
    /// `sleepStages` describes the same night, so it goes with the card.
    ///
    /// Second, independent rule: a latest-sample metric whose reading has aged
    /// out of the daily trend window is cleared too, so the watch and its
    /// complications never headline a value the phone's charts can no longer
    /// show. See `isOutOfTrendWindow`.
    ///
    /// Third, independent rule: `sleepDebt` is dropped once its last night
    /// isn't `now`'s day (or it has none), since its nights are labeled as
    /// ending today. Unlike the Sleep card it doesn't wait for a night: the
    /// next watch compute or phone push rebuilds it for the new day.
    ///
    /// Fourth, independent rule: the Stress card is today's average, so once
    /// the day it was built on (`weeklyAsOf`, the builder's `now`; it travels
    /// with the value through every merge) isn't `now`'s day, or is unknown
    /// (nil reads as not today, like `sleepNight`), it is cleared to the
    /// builder's blank Stress card: no value and no status band, since today's
    /// band went with today's average. Its week stays for the chart.
    ///
    /// Fifth, independent rule: the same day check for the running daily
    /// totals (`WatchMetricKindKey.dailyTotalKinds`). Today's steps or energy
    /// so far starts over at midnight, so a total built on another day, or on
    /// an unknown one, is cleared to the builder's blank card. They carry no
    /// status band, so `cleared()` alone is that card, and their week (and
    /// its `usesKilojoules`) stays for the chart and the complications.
    func sanitized(asOf now: Date = Date()) -> WatchMetricsSnapshot {
        let clearsSleep = metric(forKind: WatchMetricKindKey.sleep) != nil
            && !isSleepNightCurrent(asOf: now)
        let windowStart = Self.recentTrendWindowStart(asOf: now)
        let clearsStale = metrics.contains { isOutOfTrendWindow($0, windowStart: windowStart) }
        let clearsSleepDebt = sleepDebt.map { debt -> Bool in
            // Same day-boundary convention as `isSleepNightCurrent`.
            guard let lastDay = debt.nights.last?.day else { return true }
            return !Calendar(identifier: .gregorian).isDate(lastDay, inSameDayAs: now)
        } ?? false
        let clearsStress = metric(forKind: WatchMetricKindKey.stress).map { stress -> Bool in
            // Same day-boundary convention as `isSleepNightCurrent`.
            guard stress.hasValue else { return false }
            guard let builtOn = stress.weeklyAsOf else { return true }
            return !Calendar(identifier: .gregorian).isDate(builtOn, inSameDayAs: now)
        } ?? false
        let clearedDailyTotals = Set(metrics.compactMap { metric -> String? in
            // Same day-boundary convention as `isSleepNightCurrent`.
            guard WatchMetricKindKey.dailyTotalKinds.contains(metric.kind), metric.hasValue else { return nil }
            guard let builtOn = metric.weeklyAsOf else { return metric.kind }
            return Calendar(identifier: .gregorian).isDate(builtOn, inSameDayAs: now) ? nil : metric.kind
        })
        guard clearsSleep || clearsStale || clearsSleepDebt || clearsStress || !clearedDailyTotals.isEmpty else { return self }

        var copy = self
        if clearsSleep { copy.sleepStages = nil }
        if clearsSleepDebt { copy.sleepDebt = nil }
        copy.metrics = metrics.map { metric in
            if clearsSleep, metric.kind == WatchMetricKindKey.sleep { return metric.cleared() }
            if clearsStress, metric.kind == WatchMetricKindKey.stress {
                var cleared = metric.cleared()
                cleared.levelMin = nil
                cleared.levelMax = nil
                cleared.tint = nil
                cleared.statusBand = nil
                return cleared
            }
            if clearedDailyTotals.contains(metric.kind) { return metric.cleared() }
            return isOutOfTrendWindow(metric, windowStart: windowStart) ? metric.cleared() : metric
        }
        return copy
    }

    /// A latest-sample metric whose reading predates the daily trend window the
    /// phone fetches over. Mirrors the phone's bounded `latestQuantity`: a
    /// persisted snapshot (App Group cache) can outlive the window its value was
    /// fetched in, and the compute merge deliberately PRESERVES a good local
    /// value when an incoming push is blank, so neither a re-push nor an on-watch
    /// recompute would clear it. Doing it at display time covers the watch app
    /// and its complications in one place.
    ///
    /// Gated on a non-nil `measuredAt`, which the shared builder stamps only for
    /// the latest-sample metrics (HR / Resting HR / HRV / Sleep). Computed
    /// metrics carry `computedAt` instead and must NOT be cleared by this rule —
    /// unlike Sleep's own "unknown night ⇒ clear" guard, a nil watermark here
    /// means "not a latest-sample metric", not "unverifiable".
    private func isOutOfTrendWindow(_ metric: WatchMetric, windowStart: Date) -> Bool {
        guard let measuredAt = metric.measuredAt, metric.hasValue else { return false }
        return measuredAt < windowStart
    }

    /// Oldest reading the watch will display, matching
    /// `BodyHealthTrendRange.recentTrendWindowStart` on the phone.
    /// `BodyMetricsKit` isn't linked into the watch widget target (same
    /// constraint as `Calendar.bodyGregorian` below), so the day count is
    /// duplicated here and pinned to the phone's by a test.
    static func recentTrendWindowStart(asOf now: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let oldestPastOffset = recentTrendWindowDayCount - 1
        let currentDayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -oldestPastOffset, to: currentDayStart)
            ?? now.addingTimeInterval(-TimeInterval(oldestPastOffset) * 86_400)
    }

    /// Kept equal to `BodyHealthTrendRange.maximumDayCount` by
    /// `RecentTrendWindowTests`.
    static let recentTrendWindowDayCount = 365

    private func isSleepNightCurrent(asOf now: Date) -> Bool {
        guard let sleepNight else { return false }
        // Same day-boundary convention as `SleepSummary.asOf` (Gregorian, local
        // time zone). `Calendar.bodyGregorian` isn't linked into the watch
        // widget target, but it only differs by `firstWeekday`, which doesn't
        // affect `isDate(_:inSameDayAs:)`.
        return Calendar(identifier: .gregorian).isDate(sleepNight, inSameDayAs: now)
    }
}

extension WatchMetricsSnapshot {
    /// Deterministic encoding (sorted keys) so the WatchConnectivity payload and
    /// the on-watch cache dedupe byte-for-byte.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    static func decoded(from data: Data) -> WatchMetricsSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(WatchMetricsSnapshot.self, from: data)
        } catch {
            Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchSnapshot")
                .error("Snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
