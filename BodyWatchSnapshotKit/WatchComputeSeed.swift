//
//  WatchComputeSeed.swift
//  Body
//
//  The phone→watch compute CONTEXT (distinct from `WatchMetricsSnapshot`, the
//  already-computed DISPLAY payload): the trimmed historical trends, sleep
//  history, and settings the watch needs to compute its own metrics on-device
//  and match the phone exactly, per the on-watch realtime compute plan. The
//  phone publishes this alongside its regular snapshot push; the watch splices
//  in a short HealthKit delta (`WatchDeltaSplicer`) and recomputes through the
//  same shared `BodyMetricsKit` code the phone uses — no hand-forked math.
//
//  Schema evolution: exactly like `WatchMetricsSnapshot`, the phone and watch
//  can run different builds, so every field here (and on `WatchComputeSettings`)
//  decodes leniently — see the custom `init(from:)` below.
//

import Foundation
import os

/// Whole-series min/max for one metric kind (`WatchMetricKindKey`), the same
/// bounds `WatchMetricsSnapshotBuilder`'s `values(_:)` filtering derives from a
/// trend series. Built from the phone's FULL (untrimmed) trends and carried on
/// the seed so the watch's freshly-computed metrics can union the phone's whole
/// history into their displayed range — including extremes older than the
/// seed's trimmed trend window, which the watch could never recover otherwise
/// (`WatchMetricsSnapshotBuilder.seriesRangeOverride`).
struct WatchSeriesRange: Codable, Equatable {
    var min: Double
    var max: Double
}

/// Compute-relevant settings, persisted-encoding-for-persisted-encoding with
/// the phone's `UserDefaults`/`BodyAppearancePreference` values — carried as
/// raw strings/primitives (not the iOS-only preference types) so this stays
/// Foundation-only and decodable by an older watch build.
struct WatchComputeSettings: Codable, Equatable {
    var idealSleepDurationMinutes: Int
    var followsSystemUnits: Bool
    /// `BodyValueFormat.TemperatureUnitPreference.rawValue`.
    var selectedTemperatureUnitRaw: String
    var showSleepScore: Bool
    var showsSubMinuteAwakeSleepStages: Bool
    var showsLeadingTrailingAwakeSleepStages: Bool
    /// `BodyHealthDataSourceSelection`'s persisted raw encoding (iOS-only
    /// type; carried as its raw string so this struct stays Foundation-only).
    var healthDataSourceSelectionRaw: String
    var combinesHealthDataSourcesByName: Bool
    /// `BodyCustomHealthSourceGroupStore`'s persisted raw JSON, so the watch
    /// rebuilds the same `custom:` source buckets the phone resolved against.
    /// Nil when the phone has no groups (or Body Pro has lapsed), which keeps
    /// the encoding byte-identical to a pre-feature seed.
    var customHealthSourceGroupsRaw: String?
    /// `BodyValueFormat.EnergyUnitPreference.rawValue` the phone formats Active
    /// Energy and Resting Energy in, so the watch's compute formats them the
    /// same way. Nil means kilocalories: the phone passes nil for kilocalorie
    /// users, which keeps their encoding and settings signature byte-identical
    /// to a pre-feature seed, so only kilojoule users re-seed once.
    var selectedEnergyUnitRaw: String?
    /// Recent per-night time zones, keyed by ISO day string (`"yyyy-MM-dd"`) —
    /// NEVER `[Date: String]`, whose JSON encoding is a nondeterministic
    /// unkeyed array of key/value pairs that would defeat `.sortedKeys`
    /// determinism and the byte-compare the watch/publisher dedupe on. Lets
    /// the watch's sleep assembly resolve a night's time zone the same way
    /// the phone's `BodyTimeZoneLedger` does, falling back to
    /// `TimeZone.current.identifier` for a day not covered.
    var recentTimeZoneIdentifiersByDay: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case idealSleepDurationMinutes
        case followsSystemUnits
        case selectedTemperatureUnitRaw
        case showSleepScore
        case showsSubMinuteAwakeSleepStages
        case showsLeadingTrailingAwakeSleepStages
        case healthDataSourceSelectionRaw
        case combinesHealthDataSourcesByName
        case customHealthSourceGroupsRaw
        case selectedEnergyUnitRaw
        case recentTimeZoneIdentifiersByDay
    }

    init(
        idealSleepDurationMinutes: Int,
        followsSystemUnits: Bool,
        selectedTemperatureUnitRaw: String,
        showSleepScore: Bool,
        showsSubMinuteAwakeSleepStages: Bool,
        showsLeadingTrailingAwakeSleepStages: Bool,
        healthDataSourceSelectionRaw: String,
        combinesHealthDataSourcesByName: Bool,
        customHealthSourceGroupsRaw: String? = nil,
        selectedEnergyUnitRaw: String? = nil,
        recentTimeZoneIdentifiersByDay: [String: String]? = nil
    ) {
        self.idealSleepDurationMinutes = idealSleepDurationMinutes
        self.followsSystemUnits = followsSystemUnits
        self.selectedTemperatureUnitRaw = selectedTemperatureUnitRaw
        self.showSleepScore = showSleepScore
        self.showsSubMinuteAwakeSleepStages = showsSubMinuteAwakeSleepStages
        self.showsLeadingTrailingAwakeSleepStages = showsLeadingTrailingAwakeSleepStages
        self.healthDataSourceSelectionRaw = healthDataSourceSelectionRaw
        self.combinesHealthDataSourcesByName = combinesHealthDataSourcesByName
        self.customHealthSourceGroupsRaw = customHealthSourceGroupsRaw
        self.selectedEnergyUnitRaw = selectedEnergyUnitRaw
        self.recentTimeZoneIdentifiersByDay = recentTimeZoneIdentifiersByDay
    }

    /// Lenient decode: every field falls back to a safe default when absent,
    /// so a seed encoded by a future phone build (extra/renamed fields) still
    /// decodes on an older watch instead of dropping the whole seed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idealSleepDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .idealSleepDurationMinutes)
            ?? BodySleepDurationGoal.defaultMinutes
        followsSystemUnits = try container.decodeIfPresent(Bool.self, forKey: .followsSystemUnits) ?? true
        selectedTemperatureUnitRaw = try container.decodeIfPresent(String.self, forKey: .selectedTemperatureUnitRaw)
            ?? BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
        showSleepScore = try container.decodeIfPresent(Bool.self, forKey: .showSleepScore) ?? true
        showsSubMinuteAwakeSleepStages = try container.decodeIfPresent(Bool.self, forKey: .showsSubMinuteAwakeSleepStages) ?? true
        showsLeadingTrailingAwakeSleepStages = try container.decodeIfPresent(Bool.self, forKey: .showsLeadingTrailingAwakeSleepStages) ?? true
        healthDataSourceSelectionRaw = try container.decodeIfPresent(String.self, forKey: .healthDataSourceSelectionRaw) ?? ""
        combinesHealthDataSourcesByName = try container.decodeIfPresent(Bool.self, forKey: .combinesHealthDataSourcesByName) ?? false
        customHealthSourceGroupsRaw = try container.decodeIfPresent(String.self, forKey: .customHealthSourceGroupsRaw)
        selectedEnergyUnitRaw = try container.decodeIfPresent(String.self, forKey: .selectedEnergyUnitRaw)
        recentTimeZoneIdentifiersByDay = try container.decodeIfPresent([String: String].self, forKey: .recentTimeZoneIdentifiersByDay)
    }
}

/// Phone→watch compute context. Distinct from `WatchMetricsSnapshot`
/// (the display payload): this carries the historical INPUTS the watch's own
/// recompute needs, not already-formatted metric cards.
struct WatchComputeSeed: Codable, Equatable {
    /// Bumped when this struct's shape changes in a way the watch must reject
    /// rather than partially adopt (mirrors `HealthDashboardSnapshot.schemaVersion`).
    /// `nil`/unrecognized ⇒ treated as incompatible by the watch's schema check.
    var schemaVersion: Int

    /// Transport bookkeeping only — when this seed was serialized. NOT the
    /// data watermark; see `dataThrough`. Every publish (including a
    /// settings-only republish) refreshes this.
    var publishedAt: Date

    /// The data-coverage watermark: the engine anchor date of the refresh that
    /// built `trends`/`summary`/the training-load loads below. Drives
    /// `WatchDeltaSplicer.deltaStart` and the watch's `maxComputeAge`
    /// staleness check. A settings-only republish (unit toggle, etc.) carries
    /// this forward UNCHANGED from the last full-refresh build — publishing
    /// more often must never look like fresher data.
    var dataThrough: Date

    var lastVitalsRefreshDate: Date?

    /// Fallback per-metric values (today's summary) for a kind the watch's own
    /// delta fetch doesn't refresh this compute (no permission, no fresh
    /// sample, etc.).
    var summary: HealthSummarySnapshot

    /// Trimmed compute-relevant trend history — see `watchComputeTrimmed`.
    var trends: HealthTrendSnapshot

    /// Recent-week min/max per metric kind, matching
    /// `WatchMetricsSnapshotBuilder`'s own filtering
    /// (`WatchMetricsSnapshotBuilder.seriesRanges(from:)`).
    var seriesRanges: [String: WatchSeriesRange]

    /// Dense day-indexed Training Load loads (zero-filled;
    /// `TrainingLoadCalculator.dailyLoadValues`'s exact shape), paired with
    /// `trainingLoadStartDay` so the watch can reconstitute `(date, load)`
    /// pairs, splice in its own delta days, and replay
    /// `TrainingLoadCalculator.series(fromDailyLoads:)`.
    var trainingLoadStartDay: Date?
    var trainingLoadDailyLoads: [Double]?
    /// The loads' OWN data-coverage watermark, which can lag the seed's
    /// `dataThrough`: a full refresh with the Training Load / Readiness cards
    /// hidden advances `dataThrough` without rebuilding the loads (phone-side
    /// cost gate), and after a phone relaunch the loads may be missing
    /// entirely. The watch replays the array only when this coverage still
    /// reaches its delta window — otherwise the uncovered days between the two
    /// watermarks would be silently zero-filled as fabricated rest days.
    var trainingLoadDataThrough: Date?
    /// The iPhone's effort ratings for the recent workouts (the last
    /// `maxComputeAge` days), keyed by workout UUID, which is identical on
    /// both devices. The watch overwrites every day of its delta window with
    /// its own workout reads, so without these a rating made on the iPhone
    /// (Fitness, the Effort card, Auto-Apply) counts at the default effort
    /// until it replicates to the watch's own store, and the watch's newer
    /// compute then outranks the iPhone's corrected number in the merge.
    /// `WatchComputeAssembly.applyingEffortHints` fills only workouts the
    /// watch read as unrated; a rating the watch read itself wins. `nil` from
    /// a phone build that predates them.
    var trainingLoadEffortHints: [String: Double]?

    /// The phone's own discovered source universe per compute kind (keyed by
    /// `HealthMetricKind.rawValue`, values = sorted disambiguated identity
    /// IDs). An All-Sources read on the watch is only phone-equivalent when
    /// every one of these is visible to the watch's HealthKit too — a
    /// phone-only or third-party source whose samples never replicate would
    /// otherwise make a "successful" watch-local query silently replace the
    /// phone-seeded points with a subset (`WatchSourceResolver.allSourcesRead`).
    var expectedSourceIDsByKind: [String: [String]]?

    var settings: WatchComputeSettings

    /// Hash of the compute-relevant settings above, so the watch can cheaply
    /// detect "did anything that changes the math change?" without a
    /// field-by-field compare.
    var settingsSignature: String

    /// Days of trend history carried in `trends` (readiness, vitals, Training
    /// Load, …); each windowed to this many most-recent days ending at the
    /// seed's `dataThrough`.
    static let trendDayCount = 70

    /// Nights of sleep history carried in `trends.sleepHistory`, more than
    /// `trendDayCount`: the watch's Sleep Debt (`SleepDebtChartModel.watchNightCount`
    /// nights) reads each night's 14 night window, the day before them, two
    /// days of time zone slack, and a whole 56 day HRV baseline and learned
    /// need behind those (`SleepDebtChartModel.historyDayCount(nightCount:)`),
    /// so the watch reads exactly the nights the phone's model does. Only the
    /// history is widened; `trends.sleep` and every other series stay at
    /// `trendDayCount`.
    static let sleepHistoryDayCount = SleepDebtChartModel.historyDayCount(nightCount: SleepDebtChartModel.watchNightCount)

    /// Nights of FULL sleep-stage detail kept in `trends.sleepHistory`; older
    /// nights collapse to one synthesized segment (see
    /// `SleepHistorySnapshot.watchComputeTrimmed`). Must cover the 14-day
    /// sleep-consistency baseline window (`Sleep.swift`'s
    /// `consistencyBaselineDayCount`) so collapsing a night never changes a
    /// still-relevant score — 15 covers "today" plus the full 14-day lookback.
    static let sleepSegmentDayCount = 15

    /// Days of `trends.recordedStressDays` carried, whole records, ending at
    /// `dataThrough`. The watch keeps only about a week of HealthKit, so these
    /// records are where its Stress baselines come from: each scored day reads
    /// the quiet heart rate and RMSSD medians of the 56 days before it
    /// (`ReadinessScoreCalculator.baselineDayCount`), plus a few days of slack
    /// at the calendar edges. They also draw the 7 day chart and its ranges.
    static let stressRecordDayCount = 60

    /// The watch's assumed HealthKit retention: the compute's ENTIRE delta
    /// window (which opens two calendar days before `dataThrough` for the
    /// re-fetch overlap — `WatchDeltaSplicer.deltaStart`) must fit inside this,
    /// so the effective maximum seed age is about two days less. A window
    /// reaching further back would get "successfully" empty results for days
    /// the watch simply no longer holds and splice them as authoritative.
    static let maxComputeAge: TimeInterval = 7 * 86_400

    static let currentSchemaVersion = 1

    /// The WatchConnectivity application-context key the compressed seed rides
    /// under. Shared (rather than spelled as a literal in the publisher, the
    /// watch's intake, and the tests) because a typo on either side is silent:
    /// the push still succeeds and the watch simply never gets a seed.
    static let applicationContextKey = "computeSeed"

    /// Sibling context key carrying just the seed's `settingsSignature` string.
    /// Sent whenever the phone is in a seed-worthy state — INCLUDING when the
    /// blob itself was dropped for size — so the watch can detect that its
    /// stored seed was built under compute settings the phone has since
    /// changed, and invalidate it instead of computing with a stale
    /// configuration.
    static let applicationContextSettingsSignatureKey = "computeSeedSettingsSignature"

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case publishedAt
        case dataThrough
        case lastVitalsRefreshDate
        case summary
        case trends
        case seriesRanges
        case trainingLoadStartDay
        case trainingLoadDailyLoads
        case trainingLoadDataThrough
        case trainingLoadEffortHints
        case expectedSourceIDsByKind
        case settings
        case settingsSignature
    }

    init(
        schemaVersion: Int = WatchComputeSeed.currentSchemaVersion,
        publishedAt: Date,
        dataThrough: Date,
        lastVitalsRefreshDate: Date? = nil,
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        seriesRanges: [String: WatchSeriesRange],
        trainingLoadStartDay: Date? = nil,
        trainingLoadDailyLoads: [Double]? = nil,
        trainingLoadDataThrough: Date? = nil,
        trainingLoadEffortHints: [String: Double]? = nil,
        expectedSourceIDsByKind: [String: [String]]? = nil,
        settings: WatchComputeSettings,
        settingsSignature: String
    ) {
        self.schemaVersion = schemaVersion
        self.publishedAt = publishedAt
        self.dataThrough = dataThrough
        self.lastVitalsRefreshDate = lastVitalsRefreshDate
        self.summary = summary
        self.trends = trends
        self.seriesRanges = seriesRanges
        self.trainingLoadStartDay = trainingLoadStartDay
        self.trainingLoadDailyLoads = trainingLoadDailyLoads
        self.trainingLoadDataThrough = trainingLoadDataThrough
        self.trainingLoadEffortHints = trainingLoadEffortHints
        self.expectedSourceIDsByKind = expectedSourceIDsByKind
        self.settings = settings
        self.settingsSignature = settingsSignature
    }

    /// Lenient decode mirroring `WatchMetricsSnapshot`/`HealthDashboardSnapshot`:
    /// every field falls back to a safe default when absent, so a seed built by
    /// a different-vintage phone still decodes instead of the whole payload
    /// being dropped. A seed decoded this way with an unrecognized
    /// `schemaVersion` is the watch's cue to discard it (Phase 4).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt) ?? .distantPast
        dataThrough = try container.decodeIfPresent(Date.self, forKey: .dataThrough) ?? .distantPast
        lastVitalsRefreshDate = try container.decodeIfPresent(Date.self, forKey: .lastVitalsRefreshDate)
        summary = try container.decodeIfPresent(HealthSummarySnapshot.self, forKey: .summary) ?? .empty
        trends = try container.decodeIfPresent(HealthTrendSnapshot.self, forKey: .trends) ?? .empty
        seriesRanges = try container.decodeIfPresent([String: WatchSeriesRange].self, forKey: .seriesRanges) ?? [:]
        trainingLoadStartDay = try container.decodeIfPresent(Date.self, forKey: .trainingLoadStartDay)
        trainingLoadDailyLoads = try container.decodeIfPresent([Double].self, forKey: .trainingLoadDailyLoads)
        trainingLoadDataThrough = try container.decodeIfPresent(Date.self, forKey: .trainingLoadDataThrough)
        trainingLoadEffortHints = try container.decodeIfPresent([String: Double].self, forKey: .trainingLoadEffortHints)
        expectedSourceIDsByKind = try container.decodeIfPresent([String: [String]].self, forKey: .expectedSourceIDsByKind)
        settings = try container.decodeIfPresent(WatchComputeSettings.self, forKey: .settings) ?? WatchComputeSeed.fallbackSettings
        settingsSignature = try container.decodeIfPresent(String.self, forKey: .settingsSignature) ?? ""
    }

    /// Encodes every field EXCEPT `publishedAt`, whose fresh stamp on every
    /// publication (including a settings-only republish of byte-identical data)
    /// would otherwise make the watch's byte-compare dedupe
    /// (`WatchComputeSeedStore.save`) see a change every time and bump the
    /// compute generation, discarding in-flight computes. Dropping it leaves
    /// the encoding a function of the seed's semantic content only; `publishedAt`
    /// stays a `CodingKey` so `init(from:)` still reads older payloads that
    /// carry it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(dataThrough, forKey: .dataThrough)
        try container.encodeIfPresent(lastVitalsRefreshDate, forKey: .lastVitalsRefreshDate)
        try container.encode(summary, forKey: .summary)
        try container.encode(trends, forKey: .trends)
        try container.encode(seriesRanges, forKey: .seriesRanges)
        try container.encodeIfPresent(trainingLoadStartDay, forKey: .trainingLoadStartDay)
        try container.encodeIfPresent(trainingLoadDailyLoads, forKey: .trainingLoadDailyLoads)
        try container.encodeIfPresent(trainingLoadDataThrough, forKey: .trainingLoadDataThrough)
        try container.encodeIfPresent(trainingLoadEffortHints, forKey: .trainingLoadEffortHints)
        try container.encodeIfPresent(expectedSourceIDsByKind, forKey: .expectedSourceIDsByKind)
        try container.encode(settings, forKey: .settings)
        try container.encode(settingsSignature, forKey: .settingsSignature)
    }

    private static let fallbackSettings = WatchComputeSettings(
        idealSleepDurationMinutes: BodySleepDurationGoal.defaultMinutes,
        followsSystemUnits: true,
        selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue,
        showSleepScore: true,
        showsSubMinuteAwakeSleepStages: true,
        showsLeadingTrailingAwakeSleepStages: true,
        healthDataSourceSelectionRaw: "",
        combinesHealthDataSourcesByName: false
    )
}

extension WatchComputeSeed {
    /// Deterministic JSON (matches `WatchMetricsSnapshot.encoded()`) then zlib,
    /// so the WatchConnectivity payload stays well inside
    /// `updateApplicationContext`'s undocumented size ceiling.
    func encodedCompressed() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let json = try? encoder.encode(self) else {
            return nil
        }
        return try? (json as NSData).compressed(using: .zlib) as Data
    }

    static func decoded(from compressed: Data) -> WatchComputeSeed? {
        guard let json = try? (compressed as NSData).decompressed(using: .zlib) as Data else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(WatchComputeSeed.self, from: json)
        } catch {
            Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchComputeSeed")
                .error("Compute seed decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Trimming

extension HealthTrendSnapshot {
    /// The compute-relevant slice of this snapshot for the phone→watch seed:
    /// windowed to `WatchComputeSeed.trendDayCount` most-recent days ending at
    /// `anchor` (the sleep history to `WatchComputeSeed.sleepHistoryDayCount`),
    /// keeping only the series the watch's on-device recompute
    /// reads (readiness, HR/RHR/HRV, the HR/HRV daily ranges for one week,
    /// respiratory, SpO₂, Training Load, wrist temperature, sleep + sleep
    /// history, recorded-readiness + its context, the recorded Stress days for
    /// `WatchComputeSeed.stressRecordDayCount` days + their context, the
    /// frozen Sleep Debt nights the watch's 14 night model reads + their context)
    /// — everything else (secondary-source series, day-sample series, Basics,
    /// Activity Rings inputs, …) collapses to `.empty` since the watch never
    /// computes those.
    func watchComputeTrimmed(anchor: Date, calendar: Calendar = .bodyGregorian) -> HealthTrendSnapshot {
        var trimmed = HealthTrendSnapshot.empty
        let days = WatchComputeSeed.trendDayCount

        trimmed.readiness = watchComputeWindowed(readiness, dayCount: days, anchor: anchor, calendar: calendar)
        trimmed.sleep = watchComputeWindowed(sleep, dayCount: days, anchor: anchor, calendar: calendar)
        trimmed.heartRate = watchComputeWindowed(heartRate, dayCount: days, anchor: anchor, calendar: calendar)
        trimmed.restingHeartRate = watchComputeWindowed(restingHeartRate, dayCount: days, anchor: anchor, calendar: calendar)
        trimmed.heartRateVariability = watchComputeWindowed(heartRateVariability, dayCount: days, anchor: anchor, calendar: calendar)
        trimmed.respiratoryRate = watchComputeWindowed(respiratoryRate, dayCount: days, anchor: anchor, calendar: calendar)
        trimmed.oxygenSaturation = watchComputeWindowed(oxygenSaturation, dayCount: days, anchor: anchor, calendar: calendar)
        trimmed.trainingLoad = watchComputeWindowed(trainingLoad, dayCount: days, anchor: anchor, calendar: calendar)
        trimmed.wristTemperature = watchComputeWindowed(wristTemperature, dayCount: days, anchor: anchor, calendar: calendar)
        // The Heart Rate and HRV week charts' daily min/max capsules keep only
        // a week, not `trendDayCount`: the builder reads them through
        // `.recentWeek` alone (nothing scores them), a seed is at most
        // `maxComputeAge` (7 days) old, and the delta re-reads them from
        // `dataThrough`'s day minus 2 days, so these 7 days plus the delta
        // always cover the 7 the chart draws. 70 would only grow the push.
        let rangeDays = BodyHealthTrendRange.recentWeek.dayCount
        trimmed.heartRateRanges = watchComputeWindowed(heartRateRanges, dayCount: rangeDays, anchor: anchor, calendar: calendar)
        trimmed.heartRateVariabilityRanges = watchComputeWindowed(
            heartRateVariabilityRanges, dayCount: rangeDays, anchor: anchor, calendar: calendar
        )
        trimmed.sleepHistory = sleepHistory.watchComputeTrimmed(anchor: anchor, calendar: calendar)

        let anchorDay = calendar.startOfDay(for: anchor)
        let oldestKeptDay = calendar.date(byAdding: .day, value: -(days - 1), to: anchorDay) ?? anchorDay
        trimmed.recordedReadiness = recordedReadiness.filter { entry in
            let day = calendar.startOfDay(for: entry.date)
            return day >= oldestKeptDay && day <= anchorDay
        }
        trimmed.recordedReadinessContext = recordedReadinessContext

        // Stress's baselines and week, same day bounds as the records above.
        let oldestStressDay = calendar.date(
            byAdding: .day,
            value: -(WatchComputeSeed.stressRecordDayCount - 1),
            to: anchorDay
        ) ?? anchorDay
        trimmed.recordedStressDays = recordedStressDays.filter { entry in
            let day = calendar.startOfDay(for: entry.date)
            return day >= oldestStressDay && day <= anchorDay
        }
        trimmed.recordedStressContext = recordedStressContext

        // The frozen Sleep Debt nights of the entry days the watch's model
        // reads (`watchNightCount + windowNightCount`, 28) ending at the anchor.
        // The watch never freezes a night itself: the phone is authoritative,
        // as for the readiness morning records (see the deviation note in
        // `WatchComputeAssembly`). So after midnight and before the next push
        // the watch computes yesterday live, and the next seed brings the
        // phone's record. The context rides along as is; the watch never re-keys.
        let oldestSleepDebtDay = calendar.date(
            byAdding: .day,
            value: -(SleepDebtChartModel.watchNightCount + SleepDebtChartModel.windowNightCount - 1),
            to: anchorDay
        ) ?? anchorDay
        trimmed.recordedSleepDebt = recordedSleepDebt.filter { record in
            let day = calendar.startOfDay(for: record.day)
            return day >= oldestSleepDebtDay && day <= anchorDay
        }
        trimmed.recordedSleepDebtContext = recordedSleepDebtContext

        return trimmed
    }
}

/// Points within the trailing `dayCount` calendar days ending at `anchor`
/// (inclusive of `anchor`'s own day), mirroring `HealthTrendSeries.limited(to:)`'s
/// day-boundary math but parameterized by a raw day count instead of a
/// `BodyHealthTrendRange` case (70 doesn't correspond to an existing range).
private func watchComputeWindowed(
    _ series: HealthTrendSeries,
    dayCount: Int,
    anchor: Date,
    calendar: Calendar
) -> HealthTrendSeries {
    let anchorDayStart = calendar.startOfDay(for: anchor)
    let startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: anchorDayStart) ?? anchorDayStart
    let endDate = calendar.date(byAdding: .day, value: 1, to: anchorDayStart) ?? anchor
    return HealthTrendSeries(
        points: series.points.filter { $0.date >= startDate && $0.date < endDate }
    )
}

/// `watchComputeWindowed` for a daily range series, with the same day-boundary
/// math (for `.recentWeek`'s 7 days it equals `HealthTrendRangeSeries.limited(to:)`).
private func watchComputeWindowed(
    _ series: HealthTrendRangeSeries,
    dayCount: Int,
    anchor: Date,
    calendar: Calendar
) -> HealthTrendRangeSeries {
    let anchorDayStart = calendar.startOfDay(for: anchor)
    let startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: anchorDayStart) ?? anchorDayStart
    let endDate = calendar.date(byAdding: .day, value: 1, to: anchorDayStart) ?? anchor
    return HealthTrendRangeSeries(
        points: series.points.filter { $0.date >= startDate && $0.date < endDate }
    )
}

extension SleepHistorySnapshot {
    /// Keeps a `WatchComputeSeed.sleepHistoryDayCount` (86) day lookback, the
    /// compute trends' 70 days (including the 56-day readiness baseline)
    /// widened to everything the watch's Sleep Debt reads, then collapses stage detail for nights `WatchComputeSeed.sleepSegmentDayCount`
    /// (or more) days before `anchor` into a single synthesized segment
    /// spanning the night's main-session interval — full per-stage detail
    /// (REM/Core/Deep/Awake) only matters for tonight's own sleep score and the
    /// 14-day consistency baseline (`Sleep.swift`'s `consistencyBaselineDayCount`),
    /// both of which stay inside the retained window for any anchor within
    /// `WatchComputeSeed.maxComputeAge` of `dataThrough`. `date`,
    /// `timeZoneIdentifier`, the day's `duration`, and `vitals` are untouched —
    /// baselines, the duration/vitals score categories, and Sleep Debt (stored
    /// duration and sleep HRV only) read those, not the segments.
    ///
    /// Deviation from a literal "unspecified sleep" stage: `SleepStage` has no
    /// such case, so `.core` stands in for the collapsed span. `.core` is one
    /// of `SleepStage.sleepStages`, so it still counts toward `asleepDuration`
    /// like the real detail it replaces, but — critically — it's excluded from
    /// `hasDetailedStages` (`.rem`/`.deep` only), so the deep/REM percentage
    /// score categories correctly stop scoring a night whose split is unknown.
    func watchComputeTrimmed(anchor: Date, calendar: Calendar = .bodyGregorian) -> SleepHistorySnapshot {
        let anchorDay = calendar.startOfDay(for: anchor)
        let trimmedDays = days.compactMap { day -> SleepDaySummary? in
            let dayStart = calendar.startOfDay(for: day.date)
            let ageInDays = calendar.dateComponents([.day], from: dayStart, to: anchorDay).day ?? 0
            guard ageInDays < WatchComputeSeed.sleepHistoryDayCount else { return nil }
            guard ageInDays >= WatchComputeSeed.sleepSegmentDayCount else {
                return day
            }

            var collapsed = day
            collapsed.summary.stageSnapshot.segments = Self.collapsedSegments(
                for: day.summary.stageSnapshot
            )
            return collapsed
        }
        return SleepHistorySnapshot(days: trimmedDays)
    }

    private static func collapsedSegments(for snapshot: SleepStageSnapshot) -> [SleepStageSegment] {
        // Collapse to the main session's span, not the whole-day span, so a
        // collapsed night keeps the nap-free bed/wake times consistency reads
        // should the retained-detail margin over the baseline window ever shrink.
        guard let interval = snapshot.mainSession.dateInterval else {
            // No (or degenerate) segments — nothing to collapse.
            return snapshot.segments
        }
        return [SleepStageSegment(stage: .core, startDate: interval.start, endDate: interval.end)]
    }
}
