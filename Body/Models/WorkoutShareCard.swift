//
//  WorkoutShareCard.swift
//  Body
//
//  Pure logic backing the workout share image: which metrics appear on the
//  card, how a GPS route projects into the card's route trace, the built-in
//  background presets, the Pro gates on user photos / 3D / non-9:16 sizes, and
//  `WorkoutShareCardGeometry` — every layout number the card, the sheet's map
//  region, the transforms, and the render tests read, derived from the chosen
//  aspect ratio so none of them can drift apart. No rendering here — see the
//  share card/sheet views for the UI that consumes these.
//

import SwiftUI
import UIKit

struct WorkoutShareMetric: Equatable {
    let title: String
    let value: String
}

/// Picks the share card's metrics, in priority order, by reusing the same
/// `WorkoutDetailPresentation` the detail page already built — so values, units,
/// and locale never drift from what the user just saw. Only title/value are
/// copied; `WorkoutDetailMetric.comparison` (the "vs 30-day avg" badge) never
/// appears on a shared image. Three selections, one per card layout: `metrics` for
/// the classic card's bottom row, `centeredMetrics` for the centered card's stack,
/// and `routelessMetrics` for the route-less card, which has no trace to carry the
/// workout's story and so also offers active energy.
///
/// All three are the *automatic* selection: they run the same pool
/// (`availableMetrics`) and defaults (`defaultMetricIDs`) that a Body Pro user's
/// manual pick resolves against, so there is one source of truth for what the card
/// can show and for what it shows when nobody picked.
enum WorkoutShareMetricsBuilder {
    static func metrics(for presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> [WorkoutShareMetric] {
        // The bottom-left row. Distance and duration live in the card's header (the
        // hero corner reads heroDistanceValue/Unit and durationClockText directly),
        // so the row carries the per-type extras: pace/speed, elevation, avg HR.
        classicRowMetrics(
            selectedIDs: defaultMetricIDs(for: presentation, type: type, hasRoute: true),
            available: availableMetrics(for: presentation, type: type),
            presentation: presentation,
            type: type
        )
    }

    /// Up to `WorkoutShareMetricSelection.defaultCount` metrics for the centered card,
    /// where every metric is a label-over-value
    /// block — so distance and duration are part of the stack here rather than living in
    /// a header. Distance, rate, and time lead; elevation/avg HR only fill slots the
    /// workout couldn't (a distance-less or rate-less type), never push those out.
    static func centeredMetrics(for presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> [WorkoutShareMetric] {
        blockMetrics(for: presentation, type: type, hasRoute: true)
    }

    /// Up to `WorkoutShareMetricSelection.defaultCount` metrics for the route-less card.
    /// Same block-style selection as
    /// `centeredMetrics`, with active energy joining the list: with no trace and no
    /// header, the stack is all the card says about the workout, and an indoor workout
    /// (strength, yoga, HIIT) often has no distance or rate to fill it.
    static func routelessMetrics(for presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> [WorkoutShareMetric] {
        blockMetrics(for: presentation, type: type, hasRoute: false)
    }

    /// The block layouts' automatic stack: the default ids for this workout, rendered
    /// with the centered card's short labels.
    private static func blockMetrics(
        for presentation: WorkoutDetailPresentation,
        type: BodyWorkoutType,
        hasRoute: Bool
    ) -> [WorkoutShareMetric] {
        let available = availableMetrics(for: presentation, type: type)
        return defaultMetricIDs(for: presentation, type: type, hasRoute: hasRoute).compactMap { id in
            available.first { $0.id == id }?.centeredMetric
        }
    }

    /// Pace/speed/swim-pace, matched by `Kind` — never by localized title, so it can't
    /// mix up two types whose tiles happen to share a translation (e.g. running's and
    /// swimming's both say "Avg Pace"). The style comes back with the tile so callers
    /// can relabel without repeating the match.
    private static func rateTile(
        presentation: WorkoutDetailPresentation,
        type: BodyWorkoutType
    ) -> (tile: WorkoutDetailMetric, style: WorkoutPaceStyle)? {
        let kind: WorkoutDetailMetric.Kind
        switch type.paceStyle {
        case .distancePace: kind = .pace
        case .speed: kind = .speed
        case .swimPace: kind = .swimPace
        case .none: return nil
        }
        guard let tile = tile(kind, in: presentation) else { return nil }
        return (tile: tile, style: type.paceStyle)
    }

    /// Elevation only makes sense for activities that actually climb — hiking/climbing-
    /// style and snow-sports types (mirrors `BodyWorkoutType.colorHex`'s groupings for
    /// those activities). Other types keep the tile in the pool (a Pro user may pick it)
    /// but never get it by default.
    private static func isElevationEligible(_ type: BodyWorkoutType) -> Bool {
        switch type {
        case .hiking, .climbing, .stairClimbing, .stairs, .stepTraining,
             .snowSports, .crossCountrySkiing, .downhillSkiing, .snowboarding, .curling:
            return true
        default:
            return false
        }
    }

    private static func tile(_ kind: WorkoutDetailMetric.Kind, in presentation: WorkoutDetailPresentation) -> WorkoutDetailMetric? {
        presentation.detailMetrics.first { $0.kind == kind }
    }
}

/// One pickable metric for the share card: a Details tile with real data, plus the
/// two synthetic entries the card can show that Details doesn't have as tiles —
/// the header `Distance` (hero value + unit) and `Time`.
///
/// `id` is stable across workouts and locales (a `Kind` case name, or "distance"/
/// "time"), because it is what gets remembered per workout type; titles and values
/// are the localized strings the detail page already built.
struct WorkoutShareMetricOption: Identifiable, Equatable {
    static let distanceID = "distance"
    static let timeID = "time"

    let id: String
    /// The Details tile's own label ("Avg Pace", "Active kcal"), or "Distance"/"Time".
    let tileTitle: String
    let value: String
    /// The Details tile behind this option; nil for `Time`, which has no tile.
    let kind: WorkoutDetailMetric.Kind?

    /// The classic card's bottom row keeps the tile's own wording, matching Details.
    var classicMetric: WorkoutShareMetric {
        WorkoutShareMetric(title: tileTitle, value: value)
    }

    /// The block layouts label rates "Pace"/"Speed" instead of the tile's "Avg Pace"/
    /// "Avg Speed": those labels are short by design, and the blocks are already read
    /// as workout averages.
    var centeredMetric: WorkoutShareMetric {
        switch kind {
        case .pace, .swimPace: return WorkoutShareMetric(title: String(localized: "Pace"), value: value)
        case .speed: return WorkoutShareMetric(title: String(localized: "Speed"), value: value)
        default: return WorkoutShareMetric(title: tileTitle, value: value)
        }
    }

    /// Stable id per Details tile kind. Exhaustive on purpose: a new `Kind` must be
    /// given a key here rather than silently colliding with another metric's stored
    /// preference.
    static func key(for kind: WorkoutDetailMetric.Kind) -> String {
        switch kind {
        case .activeEnergy: return "activeEnergy"
        case .totalEnergy: return "totalEnergy"
        case .avgHeartRate: return "avgHeartRate"
        case .maxHeartRate: return "maxHeartRate"
        case .distance: return distanceID
        case .pace: return "pace"
        case .speed: return "speed"
        case .swimPace: return "swimPace"
        case .elevation: return "elevation"
        case .stepCadence: return "stepCadence"
        case .cyclingCadence: return "cyclingCadence"
        case .power: return "power"
        case .cardioFitness: return "cardioFitness"
        case .strokeCount: return "strokeCount"
        case .humidity: return "humidity"
        case .averageMETs: return "averageMETs"
        case .heartRateRecovery: return "heartRateRecovery"
        }
    }
}

extension WorkoutShareMetricsBuilder {
    /// Everything this workout could put on the card, in the card's own display order:
    /// distance, the type's rate, time, then the remaining Details tiles in Details
    /// order. Excluded: the "No Data" placeholder tiles (active/total energy and avg HR
    /// read "No Data" rather than being omitted, and that must never land on a shared
    /// image) and the duplicates of the entries already placed up front.
    ///
    /// HR Recovery is appended to Details asynchronously by the detail view, not by
    /// `WorkoutDetailPresentation`, so it only appears here when the workout's own
    /// statistics carried it.
    static func availableMetrics(
        for presentation: WorkoutDetailPresentation,
        type: BodyWorkoutType
    ) -> [WorkoutShareMetricOption] {
        var options: [WorkoutShareMetricOption] = []

        if let heroValue = presentation.heroDistanceValue, let heroUnit = presentation.heroDistanceUnit {
            options.append(WorkoutShareMetricOption(
                id: WorkoutShareMetricOption.distanceID,
                tileTitle: String(localized: "Distance"),
                value: heroValue + " " + heroUnit,
                kind: .distance
            ))
        } else if let distanceTile = tile(.distance, in: presentation) {
            options.append(WorkoutShareMetricOption(
                id: WorkoutShareMetricOption.distanceID,
                tileTitle: distanceTile.title,
                value: distanceTile.value,
                kind: .distance
            ))
        }

        let rate = rateTile(presentation: presentation, type: type)?.tile
        if let rate {
            options.append(option(for: rate))
        }

        options.append(WorkoutShareMetricOption(
            id: WorkoutShareMetricOption.timeID,
            tileTitle: String(localized: "Time"),
            value: presentation.durationClockText,
            kind: nil
        ))

        for tile in presentation.detailMetrics {
            if tile.kind == .distance || tile.kind == rate?.kind { continue }
            if isNoDataPlaceholder(tile, in: presentation) { continue }
            options.append(option(for: tile))
        }

        return options
    }

    /// What the card shows when nobody picked (and what a non-Pro user always gets):
    /// the story the layout tells best, filtered to what this workout actually has and
    /// capped at `WorkoutShareMetricSelection.defaultCount` — the automatic card stays
    /// at three blocks even though a deliberate pick may go to five. The route-less card adds
    /// active energy, because with no trace the stack is all the card says.
    static func defaultMetricIDs(
        for presentation: WorkoutDetailPresentation,
        type: BodyWorkoutType,
        hasRoute: Bool
    ) -> [String] {
        let available = availableMetrics(for: presentation, type: type)
        let rateID = rateTile(presentation: presentation, type: type).map { WorkoutShareMetricOption.key(for: $0.tile.kind) }
        let elevationID = isElevationEligible(type) ? WorkoutShareMetricOption.key(for: .elevation) : nil
        let preferred: [String?]
        if hasRoute {
            preferred = [
                WorkoutShareMetricOption.distanceID,
                rateID,
                WorkoutShareMetricOption.timeID,
                elevationID,
                WorkoutShareMetricOption.key(for: .avgHeartRate)
            ]
        } else {
            preferred = [
                WorkoutShareMetricOption.distanceID,
                rateID,
                WorkoutShareMetricOption.timeID,
                WorkoutShareMetricOption.key(for: .activeEnergy),
                elevationID,
                WorkoutShareMetricOption.key(for: .avgHeartRate)
            ]
        }
        let availableIDs = Set(available.map(\.id))
        return Array(preferred.compactMap { $0 }.filter { availableIDs.contains($0) }.prefix(WorkoutShareMetricSelection.defaultCount))
    }

    /// The classic card's bottom row: the picked metrics minus the ones its header
    /// already carries (time always, distance when it's promoted to the hero corner),
    /// then — only if that left fewer than two — backfilled with the row's classic
    /// extras. Capped at two: a third block doesn't fit beside the branding on a
    /// 360-wide card.
    static func classicRowMetrics(
        selectedIDs: [String],
        available: [WorkoutShareMetricOption],
        presentation: WorkoutDetailPresentation,
        type: BodyWorkoutType
    ) -> [WorkoutShareMetric] {
        var rowIDs: [String] = []
        for id in selectedIDs {
            guard id != WorkoutShareMetricOption.timeID else { continue }
            guard id != WorkoutShareMetricOption.distanceID || presentation.heroDistanceValue == nil else { continue }
            guard available.contains(where: { $0.id == id }), !rowIDs.contains(id) else { continue }
            rowIDs.append(id)
        }

        let backfill: [String?] = [
            rateTile(presentation: presentation, type: type).map { WorkoutShareMetricOption.key(for: $0.tile.kind) },
            isElevationEligible(type) ? WorkoutShareMetricOption.key(for: .elevation) : nil,
            WorkoutShareMetricOption.key(for: .avgHeartRate)
        ]
        for id in backfill.compactMap({ $0 }) where rowIDs.count < 2 {
            guard available.contains(where: { $0.id == id }), !rowIDs.contains(id) else { continue }
            rowIDs.append(id)
        }

        return rowIDs.prefix(2).compactMap { id in
            available.first { $0.id == id }?.classicMetric
        }
    }

    private static func option(for tile: WorkoutDetailMetric) -> WorkoutShareMetricOption {
        WorkoutShareMetricOption(
            id: WorkoutShareMetricOption.key(for: tile.kind),
            tileTitle: tile.title,
            value: tile.value,
            kind: tile.kind
        )
    }

    /// The three tiles Details always emits, reading "No Data" when the workout has
    /// none — the only placeholder values in `detailMetrics`.
    private static func isNoDataPlaceholder(
        _ tile: WorkoutDetailMetric,
        in presentation: WorkoutDetailPresentation
    ) -> Bool {
        switch tile.kind {
        case .activeEnergy: return presentation.activeEnergyText == nil
        case .totalEnergy: return presentation.totalEnergyText == nil
        case .avgHeartRate: return presentation.averageHeartRateText == nil
        default: return false
        }
    }
}

/// The user's per-workout-type pick of which metrics the card shows, stored as one
/// JSON blob (`{workoutTypeRawValue: [metricID]}`) under a single `@AppStorage` key.
///
/// Stored ids are *preferences*, not a guarantee: a later workout of the same type
/// may not have every tile, so `resolved(stored:available:defaults:)` intersects the
/// pick with what's actually available and falls back to the automatic defaults when
/// nothing survives. Nothing here ever rewrites the stored blob — a Pro lapse or a
/// leaner workout must not silently erase the user's choice.
enum WorkoutShareMetricSelection {
    static let storageKey = "workoutShareMetricSelections"
    /// The ceiling of a deliberate Body Pro pick — five blocks is the most the card's
    /// layouts can place without crowding the branding.
    static let maximumCount = 5
    /// What the *automatic* selection stops at, so a card nobody configured (and every
    /// non-Pro card) keeps the three-block composition it has always had.
    static let defaultCount = 3

    /// The remembered pick for this type, or nil when nothing is stored for it (or the
    /// blob is unreadable — an unparseable value is treated as no preference, never as
    /// an error the user has to clear).
    static func stored(json: String?, type: BodyWorkoutType) -> [String]? {
        guard let ids = decode(json)[type.rawValue], !ids.isEmpty else { return nil }
        return ids
    }

    /// The blob with this type's pick replaced, every other type's kept. A malformed
    /// input starts fresh rather than failing the write.
    static func storing(_ ids: [String], for type: BodyWorkoutType, into json: String?) -> String {
        var selections = decode(json)
        selections[type.rawValue] = ids
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(selections), let encoded = String(data: data, encoding: .utf8) else {
            return json ?? ""
        }
        return encoded
    }

    /// What the card actually shows for a Pro user: the stored pick narrowed to the
    /// metrics this workout has, deduped, in pool order (so the card's order never
    /// depends on the order the chips were tapped), capped at `maximumCount`. Nothing
    /// left → the automatic defaults.
    static func resolved(
        stored: [String]?,
        available: [WorkoutShareMetricOption],
        defaults: [String]
    ) -> [String] {
        guard let stored else { return Array(defaults.prefix(maximumCount)) }
        let picked = Set(stored)
        let intersection = available.map(\.id).filter { picked.contains($0) }
        guard !intersection.isEmpty else { return Array(defaults.prefix(maximumCount)) }
        return Array(intersection.prefix(maximumCount))
    }

    /// One chip tap: add when there's room, remove unless it's the last one standing.
    /// Both bounds are no-ops rather than errors, and the result comes back in pool
    /// order so it can be stored as-is.
    static func toggling(
        _ id: String,
        in current: [String],
        available: [WorkoutShareMetricOption]
    ) -> [String] {
        let order = available.map(\.id)
        var updated: Set<String>
        if current.contains(id) {
            guard current.count > 1 else { return current }
            updated = Set(current)
            updated.remove(id)
        } else {
            guard order.contains(id), current.count < maximumCount else { return current }
            updated = Set(current)
            updated.insert(id)
        }
        let ordered = order.filter { updated.contains($0) }
        return ordered.isEmpty ? current : ordered
    }

    /// The long image's own pick, under its own key: it has no five-metric ceiling
    /// (the tall export has room for every tile) and defaults to *everything*, so
    /// sharing the two through one blob would silently move the card's pick around.
    static let longStorageKey = "workoutShareLongMetricSelections"

    /// What the long image actually shows: the stored pick narrowed to this workout's
    /// metrics, in pool order. Nothing stored, an empty pick, or a pick whose ids are
    /// all stale (every one belongs to a workout with different tiles) all mean the
    /// same thing here — show everything, which is the long image's default.
    static func resolvedLong(
        stored: [String]?,
        available: [WorkoutShareMetricOption]
    ) -> [String] {
        let order = available.map(\.id)
        guard let stored, !stored.isEmpty else { return order }
        let picked = Set(stored)
        let intersection = order.filter { picked.contains($0) }
        return intersection.isEmpty ? order : intersection
    }

    /// One long-image chip tap: no ceiling, the same "at least one stays on" floor as
    /// the card, and the result in pool order so it can be stored as-is.
    static func togglingLong(
        _ id: String,
        in current: [String],
        available: [WorkoutShareMetricOption]
    ) -> [String] {
        let order = available.map(\.id)
        var updated: Set<String>
        if current.contains(id) {
            guard current.count > 1 else { return current }
            updated = Set(current)
            updated.remove(id)
        } else {
            guard order.contains(id) else { return current }
            updated = Set(current)
            updated.insert(id)
        }
        let ordered = order.filter { updated.contains($0) }
        return ordered.isEmpty ? current : ordered
    }

    /// The month-summary card's own pick, under its own key. A month has no single
    /// workout type to file the pick under, so this one is a plain JSON `[String]`
    /// rather than the per-type blob the workout card stores.
    static let summaryStorageKey = "workoutShareSummaryMetricSelections"
    /// The month card's own ceiling: three blocks in one row above the chart, so the
    /// chart keeps its height on the 3:4 card.
    static let summaryMaximumCount = 3

    /// The remembered summary pick, or nil when nothing is stored (or the value is
    /// unreadable — treated as no preference, exactly like `stored(json:type:)`). An
    /// empty array is a real answer here, not an absence: the month card may carry no
    /// totals at all, and that choice has to survive a relaunch.
    static func storedSummary(json: String?) -> [String]? {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return ids
    }

    /// The pick as it goes back to `@AppStorage`. An unencodable value stores nothing
    /// rather than failing the write.
    static func storingSummary(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids), let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }

    /// What the summary card actually shows for a Pro user: the stored pick narrowed
    /// to the metrics this month has, in pool order, capped at `summaryMaximumCount`.
    /// Nothing left → the automatic defaults, themselves narrowed to the pool; an
    /// empty month (which offers no energy) resolves those to Workouts and Time.
    static func resolvedSummary(
        stored: [String]?,
        available: [WorkoutShareSummaryMetricOption],
        defaults: [String]
    ) -> [String] {
        let order = available.map(\.id)
        if let stored {
            // "None" is a pick of its own; only a pick the month can't honour at all
            // (every id stale) falls back to the defaults.
            if stored.isEmpty { return [] }
            let picked = Set(stored)
            let intersection = order.filter { picked.contains($0) }
            if !intersection.isEmpty { return Array(intersection.prefix(summaryMaximumCount)) }
        }
        let fallback = Set(defaults)
        let defaulted = order.filter { fallback.contains($0) }
        // A pool that shares nothing with the defaults still owes the card one
        // metric — the 1-to-5 floor is what the layouts are built on.
        return Array((defaulted.isEmpty ? Array(order.prefix(1)) : defaulted).prefix(summaryMaximumCount))
    }

    /// One summary chip tap. No floor — the month card can go without totals — and a
    /// lower ceiling (`summaryMaximumCount`) than the workout card's, on the month's
    /// pool.
    static func togglingSummary(
        _ id: String,
        in current: [String],
        available: [WorkoutShareSummaryMetricOption]
    ) -> [String] {
        let order = available.map(\.id)
        var updated: Set<String>
        if current.contains(id) {
            updated = Set(current)
            updated.remove(id)
        } else {
            guard order.contains(id), current.count < summaryMaximumCount else { return current }
            updated = Set(current)
            updated.insert(id)
        }
        return order.filter { updated.contains($0) }
    }

    private static func decode(_ json: String?) -> [String: [String]] {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8),
              let selections = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return selections
    }
}

/// Which chart sections the long image draws, given what the workout has and which
/// metric chips are on. Pure and separate from the view so the rule can be read (and
/// tested) in one place instead of being spread over eight `if` statements.
///
/// The rule: a section is tied to the pool chips that name the same thing, and shows
/// when one of them is on. A section whose chips this workout's pool doesn't offer at
/// all (stride length, ground contact and vertical oscillation never have a Details
/// tile; splits on a type with no pace/speed tile) has no control the user could
/// reach, so it always shows — hiding it would make the data unreachable.
enum WorkoutShareLongImageSections {
    /// What this workout actually has data for — each flag is "the presentation this
    /// section draws exists", nothing more.
    struct Availability: Equatable {
        var heartRate = false
        var pace = false
        var splits = false
        var elevation = false
        var cadence = false
        var power = false
        var strideLength = false
        var groundContact = false
        var verticalOscillation = false
    }

    /// What the long image draws. Every flag implies its `Availability` counterpart.
    struct Visibility: Equatable {
        var heartRate = false
        var pace = false
        var splits = false
        var elevation = false
        var cadence = false
        var power = false
        var strideLength = false
        var groundContact = false
        var verticalOscillation = false

        /// The merged Pace card carries both halves, so it's drawn when either is.
        var showsPaceCard: Bool { pace || splits }
    }

    private static let heartRateIDs = ["avgHeartRate", "maxHeartRate"]
    /// Every rate a type can have. At most one of them is ever in a pool (a workout
    /// has one pace style), so listing all three matches "the applicable rate chip"
    /// without the caller having to work out which one that is.
    private static let rateIDs = ["pace", "speed", "swimPace"]
    private static let elevationIDs = ["elevation"]
    private static let cadenceIDs = ["stepCadence", "cyclingCadence"]
    /// Power has a Details tile chip, unlike stride/GC/VO, but only when the workout
    /// has an average to show — so `isOn` still falls back to always-on for the (more
    /// common) case where power data exists only as a series, with no chip offered.
    private static let powerIDs = ["power"]

    static func sections(
        available: [WorkoutShareMetricOption],
        selectedIDs: [String],
        data: Availability
    ) -> Visibility {
        let pool = Set(available.map(\.id))
        let selected = Set(selectedIDs)

        func isOn(_ ids: [String]) -> Bool {
            let offered = ids.filter { pool.contains($0) }
            // No chip names this section — nothing could turn it back on.
            guard !offered.isEmpty else { return true }
            return offered.contains { selected.contains($0) }
        }

        let rateOn = isOn(rateIDs)
        return Visibility(
            heartRate: data.heartRate && isOn(heartRateIDs),
            pace: data.pace && rateOn,
            splits: data.splits && rateOn,
            elevation: data.elevation && isOn(elevationIDs),
            cadence: data.cadence && isOn(cadenceIDs),
            power: data.power && isOn(powerIDs),
            strideLength: data.strideLength,
            groundContact: data.groundContact,
            verticalOscillation: data.verticalOscillation
        )
    }
}

/// Projects a GPS route into the unit square (0...1 on each axis) for drawing as a
/// route trace on the share card, independent of the card's actual pixel size.
enum WorkoutShareRouteProjection {
    /// Below this span (in degrees, longitude already corrected for latitude), an axis
    /// is treated as having no real extent. ~2.5e-4° ≈ 28 m of latitude: ordinary GPS
    /// jitter on a stationary/treadmill "route" stays under it (→ metrics-only card,
    /// not noise blown up to a full-size trace), while any real outdoor route exceeds it.
    private static let degenerateSpanEpsilon = 2.5e-4

    static func normalizedPoints(for coordinates: [RouteCoordinate]) -> [CGPoint]? {
        let validCoordinates = coordinates.filter {
            $0.latitude.isFinite && $0.longitude.isFinite &&
            abs($0.latitude) <= 90 && abs($0.longitude) <= 180
        }
        guard validCoordinates.count >= 2, let referenceLongitude = validCoordinates.first?.longitude else {
            return nil
        }

        // Unwrap longitudes around the first point so an antimeridian crossing (e.g.
        // 179.9° → -179.9°) reads as a small span instead of the naive ~360° one.
        let points = validCoordinates.map { coordinate -> (lat: Double, lon: Double) in
            var longitude = coordinate.longitude
            while longitude - referenceLongitude > 180 { longitude -= 360 }
            while longitude - referenceLongitude < -180 { longitude += 360 }
            return (coordinate.latitude, longitude)
        }

        let latitudes = points.map(\.lat)
        let longitudes = points.map(\.lon)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else {
            return nil
        }

        // Equirectangular projection: longitude degrees are scaled by cos(mid-latitude)
        // so they represent the same ground distance as latitude degrees.
        let midLatitudeRadians = (minLatitude + maxLatitude) / 2 * .pi / 180
        let longitudeScale = cos(midLatitudeRadians)

        let latitudeSpan = maxLatitude - minLatitude
        let longitudeSpan = (maxLongitude - minLongitude) * longitudeScale

        guard latitudeSpan > degenerateSpanEpsilon || longitudeSpan > degenerateSpanEpsilon else {
            return nil
        }

        // Aspect-preserving fit into the unit square: both axes divide by the longer
        // span, so the shorter axis lands compressed around the 0.5 centerline instead
        // of being stretched to fill the square.
        let span = max(latitudeSpan, longitudeSpan)

        return points.map { point in
            let x: Double
            if longitudeSpan > degenerateSpanEpsilon {
                let scaledLongitude = (point.lon - minLongitude) * longitudeScale
                x = 0.5 + (scaledLongitude - longitudeSpan / 2) / span
            } else {
                x = 0.5
            }

            let y: Double
            if latitudeSpan > degenerateSpanEpsilon {
                // North-up: a larger latitude maps to a smaller y (higher on the card).
                let offsetLatitude = point.lat - minLatitude
                y = 0.5 - (offsetLatitude - latitudeSpan / 2) / span
            } else {
                y = 0.5
            }

            return CGPoint(x: x, y: y)
        }
    }
}

/// Which way a share export's ink runs — one value the card and the long image both
/// read instead of hard-coding white text over black scrims. `.light` is every
/// dark-backed export (the Midnight and Workout Color presets, and every photo, map,
/// and video background, which are dark-backed by their scrims); `.dark` is the
/// Daylight preset's white card.
///
/// Only the export's *own* chrome reads this. The trace colour, the type tint, and the
/// branding icon are user/asset colours and stay as they are.
enum WorkoutShareCardInk {
    case light
    case dark

    /// The colour of full-strength text.
    var primary: Color {
        switch self {
        case .light: return .white
        case .dark: return .black
        }
    }

    /// The same ink at one of the card's secondary strengths (`.white.opacity(0.7)` and
    /// friends), so an opacity site converts without picking a colour of its own.
    func primary(_ opacity: Double) -> Color {
        primary.opacity(opacity)
    }

    /// The base colour of the top/bottom scrim gradients. The gradients keep their own
    /// opacities; only the colour flips, so a white card darkens nothing.
    var scrim: Color {
        switch self {
        case .light: return .black
        case .dark: return .white
        }
    }

    /// The legibility halo behind text and the 2D trace, for the moments the ink lands
    /// on a background the scrims don't reach (a bright photo, the tint gradient's
    /// edge). Slightly stronger on the dark ink: a white halo has less contrast against
    /// mid-tones than a black one.
    var legibilityShadow: Color {
        switch self {
        case .light: return Color.black.opacity(0.45)
        case .dark: return Color.white.opacity(0.55)
        }
    }
}

/// Built-in gradient backgrounds for the share card — free, code-defined (no assets).
/// User photos are a separate, Pro-gated path; see `WorkoutShareBackgroundPolicy`.
enum BodyWorkoutSharePreset: String, CaseIterable, Identifiable {
    case midnight
    case workoutTint
    case daylight

    var id: String { rawValue }

    /// Which way the ink runs on this preset — the one place the polarity is decided,
    /// read by the card, the long image, and the sheet's chrome.
    var ink: WorkoutShareCardInk {
        switch self {
        case .midnight, .workoutTint: return .light
        case .daylight: return .dark
        }
    }

    func gradient(tint: Color) -> LinearGradient {
        switch self {
        case .midnight:
            // Pure black, not a gray fade — flat by design; kept as a LinearGradient
            // only so both presets share a return type.
            return LinearGradient(
                colors: [Color.black, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        case .daylight:
            // Midnight inverted: pure white, flat by design for the same reason.
            return LinearGradient(
                colors: [Color.white, Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
        case .workoutTint:
            // Mirrors the detail sheet's routeless backdrop (BodyWorkoutsView.sheetBackdrop).
            return LinearGradient(
                colors: [tint.opacity(0.45), Color.black],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.5)
            )
        }
    }

    var localizedName: String {
        switch self {
        case .midnight: return String(localized: "Midnight")
        case .workoutTint: return String(localized: "Workout Color")
        case .daylight: return String(localized: "Daylight")
        }
    }
}

/// Whether the card draws the route flat or as the oblique elevation ribbon. Stored
/// across sessions like the background choice; `WorkoutShareBackgroundPolicy` is the
/// only seam that decides whether a stored `.threeD` may actually render.
enum WorkoutShareRouteDimension: String, CaseIterable {
    case twoD = "2d"
    case threeD = "3d"

    static let storageKey = "workoutShareRouteDimension"

    /// Anything unknown (or nothing stored) is the flat trace.
    static func stored(rawValue: String?) -> WorkoutShareRouteDimension {
        guard let rawValue, let dimension = WorkoutShareRouteDimension(rawValue: rawValue) else {
            return .twoD
        }
        return dimension
    }
}

/// Whether the card draws its route at all. Free, stored across sessions like the
/// dimension. Only the card-drawn trace (gradient and photo backgrounds) honours it:
/// the map background's route is baked into the snapshot the card is framed to, so
/// the sheet disables the option there rather than shipping a map of nothing.
enum WorkoutShareRouteVisibility: String, CaseIterable {
    case shown
    case hidden

    static let storageKey = "workoutShareRouteVisibility"

    /// Anything unknown (or nothing stored) shows the route.
    static func stored(rawValue: String?) -> WorkoutShareRouteVisibility {
        guard let rawValue, let visibility = WorkoutShareRouteVisibility(rawValue: rawValue) else {
            return .shown
        }
        return visibility
    }
}

/// Whether the route-less card draws its type glyph. Free, stored across sessions
/// like the route visibility it mirrors. Only meaningful on a route-less card — a
/// workout with a trace has no glyph to hide.
enum WorkoutShareIconVisibility: String, CaseIterable {
    case shown
    case hidden

    static let storageKey = "workoutShareIconVisibility"

    /// Anything unknown (or nothing stored) shows the icon.
    static func stored(rawValue: String?) -> WorkoutShareIconVisibility {
        guard let rawValue, let visibility = WorkoutShareIconVisibility(rawValue: rawValue) else {
            return .shown
        }
        return visibility
    }
}

/// Whether the month-summary card's calendar carries its row of weekday letters.
/// Stored across sessions like the icon visibility it mirrors; shown by default.
enum WorkoutShareWeekdayVisibility: String, CaseIterable {
    case shown
    case hidden

    static let storageKey = "workoutShareWeekdayVisibility"

    /// Anything unknown (or nothing stored) shows the letters.
    static func stored(rawValue: String?) -> WorkoutShareWeekdayVisibility {
        guard let rawValue, let visibility = WorkoutShareWeekdayVisibility(rawValue: rawValue) else {
            return .shown
        }
        return visibility
    }
}

/// Whether the card draws the Settings profile avatar beside the watermark. Stored
/// across sessions like the route/icon visibility it sits next to, but the default is
/// **hidden** — the opposite of those — because attribution is opt-in: showing someone's
/// name and photo on a shared image is a decision the user makes, not a default.
enum WorkoutShareAvatarVisibility: String, CaseIterable {
    case shown
    case hidden

    static let storageKey = "workoutShareAvatarVisibility"

    /// Anything unknown (or nothing stored) hides the avatar.
    static func stored(rawValue: String?) -> WorkoutShareAvatarVisibility {
        guard let rawValue, let visibility = WorkoutShareAvatarVisibility(rawValue: rawValue) else {
            return .hidden
        }
        return visibility
    }
}

/// Whether the card draws the Settings profile `@name` beside the watermark. Same
/// shape and default as `WorkoutShareAvatarVisibility` — hidden until the user opts in.
enum WorkoutShareNicknameVisibility: String, CaseIterable {
    case shown
    case hidden

    static let storageKey = "workoutShareNicknameVisibility"

    /// Anything unknown (or nothing stored) hides the nickname.
    static func stored(rawValue: String?) -> WorkoutShareNicknameVisibility {
        guard let rawValue, let visibility = WorkoutShareNicknameVisibility(rawValue: rawValue) else {
            return .hidden
        }
        return visibility
    }
}

/// Whether the card draws the dash between the watermark and the attribution. Sits
/// beside the avatar/nickname toggles but defaults to **shown**: the dash is what the
/// card has always drawn once attribution is on, so an existing user's card keeps its
/// look until they turn the separator off. Moot while the attribution is empty — there
/// is nothing to separate the wordmark from.
enum WorkoutShareSeparatorVisibility: String, CaseIterable {
    case shown
    case hidden

    static let storageKey = "workoutShareSeparatorVisibility"

    /// Anything unknown (or nothing stored) shows the separator.
    static func stored(rawValue: String?) -> WorkoutShareSeparatorVisibility {
        guard let rawValue, let visibility = WorkoutShareSeparatorVisibility(rawValue: rawValue) else {
            return .shown
        }
        return visibility
    }
}

/// What the card actually draws beside the watermark, resolved by the sheet from the
/// visibility toggles above and whatever the Settings profile currently has on hand —
/// a `.shown` toggle with a since-deleted photo or name draws nothing for that field.
struct WorkoutShareAttribution {
    let avatar: UIImage?
    let name: String?
    /// Only consulted when the attribution is non-empty; defaulted so the card
    /// previews and tests that predate the toggle keep the dash they were drawing.
    var showsSeparator: Bool = true

    var isEmpty: Bool { avatar == nil && name == nil }

    static let empty = WorkoutShareAttribution(avatar: nil, name: nil)
}

/// What Share/Save actually produce: the fixed-shape card, or the tall "long image"
/// of the detail page's tiles and charts. Deliberately *not* a
/// `WorkoutShareAspectRatio` case — a new ratio would join every `allCases` sweep,
/// the Pro gate, the centered-layout modes, and the map-snapshot keys, none of which
/// mean anything for a naturally sized export. Only the tray *tile* lives beside the
/// ratios. Pro-gated through `WorkoutShareBackgroundPolicy.resolvedOutputStyle`.
enum WorkoutShareOutputStyle: String, CaseIterable {
    case card
    case longImage

    static let storageKey = "workoutShareOutputStyle"

    /// Anything unknown (or nothing stored) is the ordinary card.
    static func stored(rawValue: String?) -> WorkoutShareOutputStyle {
        guard let rawValue, let style = WorkoutShareOutputStyle(rawValue: rawValue) else {
            return .card
        }
        return style
    }
}

/// What one Share/Save tap has to produce. One value rather than two booleans read in
/// two places: the export path, the save path, and the photo-permission error copy all
/// have to agree, and forcing the background selection does *not* nil out a clip the
/// user already picked.
enum WorkoutShareOutput: Equatable {
    case cardImage
    case video
    case longImage
}

/// The shape of the exported card. Every ratio is 1080 px on its short side at
/// `ImageRenderer.scale = 3`, so the point sizes below are those pixels / 3. Only
/// 9:16 is free — the rest are Pro, gated through `WorkoutShareBackgroundPolicy`
/// so a lapse falls back for the session without rewriting the stored key.
enum WorkoutShareAspectRatio: String, CaseIterable, Identifiable {
    case portrait9x16 = "9:16"
    case landscape16x9 = "16:9"
    case portrait3x4 = "3:4"
    case landscape4x3 = "4:3"
    case square = "1:1"

    var id: String { rawValue }

    static let storageKey = "workoutShareAspectRatio"

    /// Anything unknown (or nothing stored) is the original vertical card.
    static func stored(rawValue: String?) -> WorkoutShareAspectRatio {
        guard let rawValue, let ratio = WorkoutShareAspectRatio(rawValue: rawValue) else {
            return .portrait9x16
        }
        return ratio
    }

    var cardSize: CGSize {
        switch self {
        case .portrait9x16: return CGSize(width: 360, height: 640)
        case .landscape16x9: return CGSize(width: 640, height: 360)
        case .portrait3x4: return CGSize(width: 360, height: 480)
        case .landscape4x3: return CGSize(width: 480, height: 360)
        case .square: return CGSize(width: 360, height: 360)
        }
    }

    var isLandscape: Bool { cardSize.width > cardSize.height }

    var isProGated: Bool { self != .portrait9x16 }

    /// The tile's own label: numerals, deliberately not localized — "16:9" is the
    /// same string in every locale and translating it would only invite drift.
    var ratioLabel: String { rawValue }

    var localizedName: String {
        switch self {
        case .portrait9x16: return String(localized: "Portrait 9:16")
        case .landscape16x9: return String(localized: "Landscape 16:9")
        case .portrait3x4: return String(localized: "Portrait 3:4")
        case .landscape4x3: return String(localized: "Landscape 4:3")
        case .square: return String(localized: "Square")
        }
    }
}

/// How a landscape card splits the centered layout's route and metrics. Only
/// meaningful when the card is wider than tall and actually draws a trace; the
/// classic (Map) layout bakes its route into the snapshot and ignores this.
enum WorkoutShareLandscapeArrangement: String, CaseIterable, Identifiable {
    case stacked
    case sideBySide

    var id: String { rawValue }

    static let storageKey = "workoutShareLandscapeArrangement"

    static func stored(rawValue: String?) -> WorkoutShareLandscapeArrangement {
        guard let rawValue, let arrangement = WorkoutShareLandscapeArrangement(rawValue: rawValue) else {
            return .stacked
        }
        return arrangement
    }

    var localizedName: String {
        switch self {
        case .stacked: return String(localized: "Stacked")
        case .sideBySide: return String(localized: "Side by Side")
        }
    }

    var symbolName: String {
        switch self {
        case .stacked: return "rectangle.split.1x2"
        case .sideBySide: return "rectangle.split.2x1"
        }
    }
}

/// The card's type design, picked by the user and applied to every string the card
/// draws except the brand wordmark. Free — no Pro gate.
enum WorkoutShareFontChoice: String, CaseIterable, Identifiable {
    case rounded
    case standard
    case serif
    case monospaced

    var id: String { rawValue }

    static let storageKey = "workoutShareFont"

    static func stored(rawValue: String?) -> WorkoutShareFontChoice {
        guard let rawValue, let choice = WorkoutShareFontChoice(rawValue: rawValue) else {
            return .rounded
        }
        return choice
    }

    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .standard: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    var localizedName: String {
        switch self {
        case .rounded: return String(localized: "Rounded")
        case .standard: return String(localized: "Standard")
        case .serif: return String(localized: "Serif")
        case .monospaced: return String(localized: "Monospaced")
        }
    }
}

/// Colour of the trace the card draws itself — the 2D polyline and the 3D ribbon on
/// gradient and photo backgrounds. The map background ignores it: that route is
/// composited into the snapshot and keeps its pace colouring.
enum WorkoutShareRouteColorChoice: String, CaseIterable, Identifiable {
    case bodyBlue
    case workoutTint
    case white
    case black
    case orange
    case green
    case pink

    var id: String { rawValue }

    static let storageKey = "workoutShareRouteColor"

    static func stored(rawValue: String?) -> WorkoutShareRouteColorChoice {
        guard let rawValue, let choice = WorkoutShareRouteColorChoice(rawValue: rawValue) else {
            return .bodyBlue
        }
        return choice
    }

    /// - Parameter tint: The workout type's colour, for the `.workoutTint` option.
    func color(tint: Color) -> Color {
        switch self {
        case .bodyBlue: return BodyWorkoutShareCardView.defaultRouteColor
        case .workoutTint: return tint
        case .white: return .white
        case .black: return .black
        case .orange: return .orange
        case .green: return .green
        case .pink: return .pink
        }
    }

    var localizedName: String {
        switch self {
        case .bodyBlue: return String(localized: "Body Blue")
        case .workoutTint: return String(localized: "Workout Color")
        case .white: return String(localized: "White")
        case .black: return String(localized: "Black")
        case .orange: return String(localized: "Orange")
        case .green: return String(localized: "Green")
        case .pink: return String(localized: "Pink")
        }
    }
}

/// What the share sheet restores when it opens: a gradient preset (Midnight is the
/// default) or the route map. Photos stay session-only — a Pro entitlement can lapse
/// between sessions, and `WorkoutShareBackgroundPolicy` is the only seam that
/// decides whether one may render.
enum BodyWorkoutShareBackgroundChoice: Equatable {
    case map
    case preset(BodyWorkoutSharePreset)

    /// Unchanged from the preset-only key it replaces: a stored "ocean"/"sunset"/
    /// "forest" from an earlier build is now unknown and resolves to the default.
    static let storageKey = "workoutShareBackgroundPreset"

    private static let mapRawValue = "map"

    var rawValue: String {
        switch self {
        case .map: return Self.mapRawValue
        case .preset(let preset): return preset.rawValue
        }
    }

    /// Midnight when nothing (or something invalid, including a retired preset) is
    /// stored; the map only ever comes back from an explicit "map" pick — and only
    /// when there's a route to map. A route-less workout resolves a stored "map" to
    /// Midnight for the session without rewriting the key, so the next routed share
    /// still opens on the map (the same session-only fallback a failed snapshot takes).
    static func stored(rawValue: String?, hasRoute: Bool) -> BodyWorkoutShareBackgroundChoice {
        guard let rawValue else { return .preset(.midnight) }
        if rawValue == mapRawValue { return hasRoute ? .map : .preset(.midnight) }
        guard let preset = BodyWorkoutSharePreset(rawValue: rawValue) else { return .preset(.midnight) }
        return .preset(preset)
    }
}

/// Every layout number the share card draws with, derived from the chosen ratio.
/// The card, the sheet (preview box, export frame, map region), the transforms'
/// clamps, and the render tests all read this one value, so a size can't be
/// changed in one place and missed in another. Point space, 3× at export.
///
/// The 9:16 numbers are the card's original literals, reproduced exactly: the
/// default share must stay pixel-identical to the build that had no ratio picker.
struct WorkoutShareCardGeometry: Equatable {
    /// How the centered layout (presets and photos) splits route from metrics.
    enum CenteredBlockMode {
        /// 9:16 only — the original column: route, then a vertical metric stack.
        case column
        /// Route square above a horizontal row of metrics. Short cards can't afford
        /// a column, so the metrics go wide instead of the route going tiny.
        case routeOverRow
        /// Landscape, user-picked: route in the left half, metric column in the right.
        case sideBySide
    }

    /// How big one metric block is drawn. Four or five blocks only fit on a 360 pt-tall
    /// card once they shrink, so the short cards' multi-row grids go `.compact`.
    enum MetricBlockStyle {
        case regular
        case compact

        /// A label line over a value line, plus the 2 pt gap between them.
        var rowHeight: CGFloat {
            switch self {
            case .regular: return 68
            case .compact: return 54
            }
        }

        var rowGap: CGFloat {
            switch self {
            case .regular: return 20
            case .compact: return 16
            }
        }

        var labelSize: CGFloat {
            switch self {
            case .regular: return 15
            case .compact: return 13
            }
        }

        var valueSize: CGFloat {
            switch self {
            case .regular: return 40
            case .compact: return 30
            }
        }
    }

    let aspectRatio: WorkoutShareAspectRatio
    let layout: WorkoutShareCardLayout
    let arrangement: WorkoutShareLandscapeArrangement
    /// How many metric blocks the card actually draws. Defaults to the automatic
    /// three, which is what every non-centered caller (the sheet's map region, the
    /// transforms' clamps) is asking about anyway.
    let metricCount: Int

    init(
        aspectRatio: WorkoutShareAspectRatio,
        layout: WorkoutShareCardLayout,
        arrangement: WorkoutShareLandscapeArrangement,
        metricCount: Int = WorkoutShareMetricSelection.defaultCount
    ) {
        self.aspectRatio = aspectRatio
        self.layout = layout
        self.arrangement = arrangement
        self.metricCount = metricCount
    }

    var size: CGSize { aspectRatio.cardSize }

    /// Inset of the drawing rect inside a route region, so the stroke never clips.
    static let routeInset: CGFloat = 12
    /// Baseline of the pinned brand wordmark.
    static let brandingBottomPadding: CGFloat = 26

    /// Top margin of the centered block on every non-column layout.
    private static let topMargin: CGFloat = 24
    /// Gap between the route square's bottom edge and the metric row.
    private static let routeGap: CGFloat = 30
    /// Branding baseline + wordmark height + breathing room — nothing may enter it.
    /// The "+18" is now headroom rather than the exact mark height (the drawn
    /// watermark shrank to 15/13 pt), kept as-is on purpose so this zone — and every
    /// geometry test pinned to it — doesn't move.
    static let brandingZoneHeight: CGFloat = brandingBottomPadding + 18 + 12
    /// The largest a centered route square ever gets, on any ratio.
    private static let maximumCenteredRouteSide: CGFloat = 260

    // MARK: - Scrims

    /// Today's 280/170 over 640, as a fraction of the card's height: a landscape
    /// card is 360 tall, and a fixed 280 pt scrim would swallow most of it.
    func topScrimHeight(isMap: Bool) -> CGFloat {
        size.height * (isMap ? 280 / 640 : 170 / 640)
    }

    func bottomScrimHeight(isMap: Bool) -> CGFloat {
        size.height * (isMap ? 210 / 640 : 160 / 640)
    }

    /// The clear band between the map background's scrims — where the composited
    /// route has to land, so the sheet's `mapRegion` frames to it.
    var mapBand: (top: CGFloat, bottom: CGFloat) {
        (topScrimHeight(isMap: true), size.height - bottomScrimHeight(isMap: true))
    }

    // MARK: - Classic layout (map background)

    /// The classic layout's route square: sized to the map band plus a margin, so
    /// the card-drawn trace sits on the same geometry the map snapshot's route does.
    /// 9:16 lands on the original 324×324 at (180, 375).
    var classicRouteRect: CGRect {
        let band = mapBand
        let side = min(size.width * 0.9, (band.bottom - band.top) + 0.3 * size.height, size.width, size.height)
        // 20 pt below the band's centre: the header sits above the band and the
        // metrics row below it, and the trace reads better nudged off the middle.
        let centerY = (band.top + band.bottom) / 2 + 20
        let x = min(max(size.width / 2, side / 2), size.width - side / 2)
        let y = min(max(centerY, side / 2), size.height - side / 2)
        return CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
    }

    // MARK: - Centered layout (presets and photos)

    var centeredMode: CenteredBlockMode {
        if aspectRatio == .portrait9x16 { return .column }
        if aspectRatio.isLandscape && arrangement == .sideBySide { return .sideBySide }
        return .routeOverRow
    }

    /// The region the route Canvas is framed to (`routeInset` is applied inside it).
    var centeredRouteRect: CGRect {
        switch centeredMode {
        case .column:
            // The original: 260 square centred at (180, 170). Four or five blocks keep
            // the square's top edge where it was and shrink it from the bottom, so the
            // column under it still clears the branding.
            let side = columnRouteSide
            return CGRect(x: size.width / 2 - side / 2, y: Self.columnRouteTop, width: side, height: side)
        case .routeOverRow:
            let side = routeOverRowSide
            return CGRect(x: size.width / 2 - side / 2, y: Self.topMargin, width: side, height: side)
        case .sideBySide:
            let side = sideBySideRouteSide
            let centerY = Self.topMargin + (size.height - Self.topMargin - Self.brandingZoneHeight) / 2
            return CGRect(x: size.width / 4 - side / 2, y: centerY - side / 2, width: side, height: side)
        }
    }

    /// Top edge of the 9:16 column's route square — the original 170 − 130.
    private static let columnRouteTop: CGFloat = 170 - maximumCenteredRouteSide / 2

    /// The full 260 for one to three blocks; four compact ones take it to 250, five
    /// to 180.
    private var columnRouteSide: CGFloat {
        guard metricCount > WorkoutShareMetricSelection.defaultCount else { return Self.maximumCenteredRouteSide }
        return min(
            Self.maximumCenteredRouteSide,
            size.height - Self.columnRouteTop - Self.routeGap - metricContentHeight - Self.brandingZoneHeight
        )
    }

    /// Shrinks until the metric rows and the branding both fit under it: with one
    /// regular row 3:4 keeps the full 260 and the 360-tall cards drop to 182; extra
    /// rows come out of the square.
    private var routeOverRowSide: CGFloat {
        min(
            Self.maximumCenteredRouteSide,
            size.height - Self.topMargin - Self.routeGap - metricContentHeight - Self.brandingZoneHeight
        )
    }

    /// Never crosses the midline (`width / 2 − 24`), never enters the branding zone.
    private var sideBySideRouteSide: CGFloat {
        min(size.height - Self.topMargin - Self.brandingZoneHeight, size.width / 2 - Self.topMargin)
    }

    /// Where the metric stack/row is positioned. Top-anchored in `.column` (the
    /// original frame runs to the card's bottom edge; the stack sits at its top).
    var metricsFrame: CGRect {
        switch centeredMode {
        case .column:
            guard metricCount > WorkoutShareMetricSelection.defaultCount else {
                let top: CGFloat = 330
                return CGRect(x: 24, y: top, width: size.width - 48, height: size.height - top)
            }
            // Four or five: the column follows the route's ink the way the row layouts
            // do, and is exactly as tall as its blocks.
            let top = Self.columnRouteTop + columnRouteSide - Self.routeInset + Self.routeGap
            return CGRect(x: 24, y: top, width: size.width - 48, height: metricContentHeight)
        case .routeOverRow:
            // The route is bottom-anchored on its inset drawing rect, so the row
            // follows the ink (side − inset), not the region's edge.
            let top = Self.topMargin + routeOverRowSide - Self.routeInset + Self.routeGap
            return CGRect(x: 24, y: top, width: size.width - 48, height: metricContentHeight)
        case .sideBySide:
            return CGRect(
                x: size.width / 2 + 12,
                y: Self.topMargin,
                width: size.width / 2 - 24,
                height: size.height - Self.topMargin - Self.brandingZoneHeight
            )
        }
    }

    var metricsAxis: Axis {
        centeredMode == .routeOverRow ? .horizontal : .vertical
    }

    /// The route-less card has no trace to carry the workout, so it keeps the
    /// original column on 9:16 and goes wide on every shorter card.
    var routelessMetricsAxis: Axis {
        aspectRatio == .portrait9x16 ? .vertical : .horizontal
    }

    // MARK: - Metric rows

    /// How many blocks a wide row may carry before it wraps: a 360 pt card fits three
    /// at a readable size, a 480 pt one four, a 640 pt one five.
    var metricsPerRow: Int {
        if size.width >= 600 { return 5 }
        if size.width >= 450 { return 4 }
        return 3
    }

    /// How the blocks are split into rows, top row first — `[3, 2]` is a row of three
    /// over a row of two, and `[1, 1, 1]` is the original vertical stack. One to three
    /// blocks keep exactly the arrangement they have always had on every shape; only a
    /// deliberate four- or five-metric pick wraps.
    var metricRowSizes: [Int] {
        let count = max(1, metricCount)
        if layout == .routeless {
            guard routelessMetricsAxis == .horizontal else { return Self.columnRowSizes(count) }
            // A 360-wide card can't fit three blocks on one line at a readable size, so
            // they wrap (2 + a centred remainder); 450/640-wide cards keep a single row.
            return Self.rowSizes(count, perRow: size.width < 400 ? 2 : metricsPerRow)
        }
        switch centeredMode {
        case .column:
            return Self.columnRowSizes(count)
        case .routeOverRow:
            return Self.rowSizes(count, perRow: metricsPerRow)
        case .sideBySide:
            // Half a card's width, so a row never carries more than a pair.
            return count <= WorkoutShareMetricSelection.defaultCount
                ? Array(repeating: 1, count: count)
                : Self.rowSizes(count, perRow: 2)
        }
    }

    /// The vertical column's rule: always one block per line, top to bottom — four and
    /// five compact, with the route square above giving up the height they need.
    private static func columnRowSizes(_ count: Int) -> [Int] {
        Array(repeating: 1, count: count)
    }

    /// Balanced chunking with the earlier rows larger: `perRow` only fixes how many
    /// rows are needed, and the blocks then spread evenly over them — 4 at 3 per row is
    /// `[2, 2]` rather than a lopsided `[3, 1]`; 5 at 3 is `[3, 2]`, 5 at 2 is
    /// `[2, 2, 1]`.
    private static func rowSizes(_ count: Int, perRow: Int) -> [Int] {
        let rows = max(1, Int(ceil(Double(count) / Double(perRow))))
        let base = count / rows
        let remainder = count % rows
        return (0..<rows).map { $0 < remainder ? base + 1 : base }
    }

    /// Smaller type and tighter rows, for the cards where four or five blocks only fit
    /// once the route square has given up all it can: the short cards, and the 9:16
    /// column (five regular blocks would be 420 pt tall). Side by side never compacts:
    /// its metric column doesn't compete with the route, and three regular rows
    /// (244 pt) fit its 280 pt frame.
    var metricBlockStyle: MetricBlockStyle {
        metricCount > WorkoutShareMetricSelection.defaultCount
            && metricRowSizes.count > 1
            && (size.height <= 360 || aspectRatio == .portrait9x16)
            && !(layout != .routeless && centeredMode == .sideBySide)
            ? .compact
            : .regular
    }

    /// The metric block's real extent — distinct from `metricsFrame.height`, which in
    /// `.column` runs to the card's bottom edge by design.
    var metricContentHeight: CGFloat {
        let style = metricBlockStyle
        let rows = CGFloat(metricRowSizes.count)
        return rows * style.rowHeight + (rows - 1) * style.rowGap
    }

    /// The pinch anchor for the draggable info block: its visual centre, so a pinch
    /// doesn't push the trace off the top the way anchoring on the card would.
    func blockAnchor(showsTrace: Bool) -> UnitPoint {
        guard showsTrace else { return .center }
        if centeredMode == .column, metricCount <= WorkoutShareMetricSelection.defaultCount {
            // The original: midpoint of the route region's top edge and a
            // three-metric stack's bottom.
            return UnitPoint(x: 0.5, y: 305 / size.height)
        }
        if centeredMode == .column {
            // The shrunken route and the taller column: the anchor comes from the
            // block's real extent rather than the original literal.
            let content = CGRect(
                x: metricsFrame.minX,
                y: metricsFrame.minY,
                width: metricsFrame.width,
                height: metricContentHeight
            )
            let union = centeredRouteRect.union(content)
            return UnitPoint(x: union.midX / size.width, y: union.midY / size.height)
        }
        let union = centeredRouteRect.union(metricsFrame)
        return UnitPoint(x: union.midX / size.width, y: union.midY / size.height)
    }

    var blockAnchor: UnitPoint { blockAnchor(showsTrace: true) }

    /// Half the card on each axis — far enough to park the block off any edge, not
    /// far enough to lose it entirely.
    var maximumInfoOffset: CGSize {
        CGSize(width: size.width / 2, height: size.height / 2)
    }

    /// Top edge of the centered metrics — the render tests sample against it.
    var centeredMetricsTopY: CGFloat { metricsFrame.minY }
}

/// Every layout number the *month summary* card draws with. Same contract as
/// `WorkoutShareCardGeometry` — one value the card, the sheet's preview and the render
/// tests all read — for a different composition: a month title, one to five metric
/// blocks, and a chart region, with no route square anywhere.
///
/// Only three shapes exist here: the two portrait ratios stack title, metrics, and
/// chart; the square is the chart alone. Landscape never reaches this geometry — a
/// month's grid or bars have no good home beside a title at 360 pt tall, so the sheet
/// doesn't offer those tiles in summary mode (`supportedAspectRatios`).
struct WorkoutShareSummaryCardGeometry: Equatable {
    /// How the card composes its pieces.
    enum Arrangement {
        /// The portrait ratios: title, metrics, then the chart taking the rest.
        case stacked
        /// The square: the chart fills the content area and nothing else is drawn.
        case chartOnly
    }

    /// The ratios the summary card is offered at, in the tray's order.
    static let supportedAspectRatios: [WorkoutShareAspectRatio] = [.portrait9x16, .portrait3x4, .square]

    let aspectRatio: WorkoutShareAspectRatio
    /// How many metric blocks the card actually draws — the rows they need come out
    /// of the chart's height. Ignored by the chart-only square.
    let metricCount: Int
    /// Whether the calendar draws its weekday letters — 28 pt the grid gets back when
    /// they're hidden.
    let showsWeekdayHeader: Bool

    init(
        aspectRatio: WorkoutShareAspectRatio,
        metricCount: Int = WorkoutShareMetricSelection.defaultCount,
        showsWeekdayHeader: Bool = true
    ) {
        self.aspectRatio = aspectRatio
        self.metricCount = metricCount
        self.showsWeekdayHeader = showsWeekdayHeader
    }

    var size: CGSize { aspectRatio.cardSize }

    /// Margin between the card's edge and everything it draws.
    private static let inset: CGFloat = 20
    /// The month title's single line.
    private static let titleHeight: CGFloat = 30
    /// Gap under the title, and under the metrics.
    private static let titleGap: CGFloat = 8
    /// Reads as the same air the title has above the totals: the title's glyphs carry
    /// leading the metric labels don't, so the number is larger than `titleGap`.
    private static let chartGap: CGFloat = 14
    /// The bars take less than the full width — at 320 pt the rows read oversized.
    private static let barWidthFraction: CGFloat = 0.86
    /// One `WorkoutTypeBreakdownView` row and the gap under it.
    private static let barRowHeight: CGFloat = 48
    private static let barRowSpacing: CGFloat = 12
    /// `.widgetLarge`'s own ceiling — asking for more rows than the view will ever
    /// draw would only make the limit meaningless.
    private static let maximumBarRows = 5
    /// The calendar grid's fixed furniture: the weekday band (18 pt of type plus its
    /// 10 pt of padding), the five 7 pt gaps between its six rows, and the six 7 pt
    /// gaps between its seven columns.
    private static let calendarHeaderHeight: CGFloat = 28
    private static let calendarSpacing: CGFloat = 35
    private static let calendarColumnSpacing: CGFloat = 42
    private static let calendarRowCount: CGFloat = 6
    private static let calendarColumnCount: CGFloat = 7

    var arrangement: Arrangement {
        aspectRatio == .square ? .chartOnly : .stacked
    }

    /// Everything the card may draw in: inset on three sides, and stopping short of
    /// the branding zone `WorkoutShareCardGeometry` already reserves at the bottom.
    private var contentRect: CGRect {
        CGRect(
            x: Self.inset,
            y: Self.inset,
            width: size.width - Self.inset * 2,
            height: size.height - Self.inset - WorkoutShareCardGeometry.brandingZoneHeight
        )
    }

    /// Empty on the chart-only square, so a caller positioning by it draws nothing.
    var titleRect: CGRect {
        guard arrangement == .stacked else { return .zero }
        return CGRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: Self.titleHeight)
    }

    /// Empty on the chart-only square, like `titleRect`.
    var metricsRect: CGRect {
        guard arrangement == .stacked else { return .zero }
        return CGRect(
            x: contentRect.minX,
            y: titleRect.maxY + Self.titleGap,
            width: contentRect.width,
            height: metricContentHeight
        )
    }

    var chartRect: CGRect {
        switch arrangement {
        case .stacked:
            let top = metricsRect.maxY + Self.chartGap
            return CGRect(x: contentRect.minX, y: top, width: contentRect.width, height: contentRect.maxY - top)
        case .chartOnly:
            return contentRect
        }
    }

    /// More than three blocks only fit once they shrink — and the 3:4 card shrinks its
    /// three as well, which is exactly what gives its grid the 9:16 card's cell size.
    var metricBlockStyle: WorkoutShareCardGeometry.MetricBlockStyle {
        metricCount > WorkoutShareMetricSelection.defaultCount || aspectRatio == .portrait3x4 ? .compact : .regular
    }

    /// Both stacked ratios are 360 pt wide, which fits three blocks at a readable size.
    var metricsPerRow: Int { 3 }

    /// The frame the chart view is given. The bar chart takes its rows' natural height
    /// across the region's width; the calendar is square-celled, so whichever axis binds first sets the cell and the frame
    /// follows it on both axes — never stretching rows to fill a tall region, never
    /// overflowing a short one — and it is centered in the region it sits in.
    func chartFrame(for style: WorkoutSummaryChartStyle) -> CGSize {
        switch style {
        case .bar:
            // Natural height for the rows it may draw, so the bars sit right under
            // the totals instead of centering themselves down a tall region.
            let rows = CGFloat(barRowLimit)
            let natural = rows * Self.barRowHeight + (rows - 1) * Self.barRowSpacing
            return CGSize(width: chartRect.width * Self.barWidthFraction, height: min(chartRect.height, natural))
        case .calendar:
            let headerHeight = showsWeekdayHeader ? Self.calendarHeaderHeight : 0
            let cellSide = max(
                0,
                min(
                    (chartRect.height - headerHeight - Self.calendarSpacing) / Self.calendarRowCount,
                    (chartRect.width - Self.calendarColumnSpacing) / Self.calendarColumnCount
                )
            )
            return CGSize(
                width: cellSide * Self.calendarColumnCount + Self.calendarColumnSpacing,
                height: cellSide * Self.calendarRowCount + headerHeight + Self.calendarSpacing
            )
        }
    }

    /// How many activity rows the breakdown chart may draw here — five on the portrait
    /// cards, four on the square, where the chart region is 284 pt tall.
    var barRowLimit: Int {
        let rows = Int((chartRect.height + Self.barRowSpacing) / (Self.barRowHeight + Self.barRowSpacing))
        return min(Self.maximumBarRows, max(1, rows))
    }

    /// Zero rows for zero metrics, so the chart moves straight up under the title.
    private var metricRowCount: Int {
        Int(ceil(Double(max(0, metricCount)) / Double(metricsPerRow)))
    }

    private var metricContentHeight: CGFloat {
        let style = metricBlockStyle
        let rows = CGFloat(metricRowCount)
        guard rows > 0 else { return 0 }
        return rows * style.rowHeight + (rows - 1) * style.rowGap
    }

    /// How far the stacked title, metrics, and chart slide down together so the group
    /// sits centered in the content area rather than the chart floating alone at the
    /// middle of a tall region with the totals stranded above it. Zero for the bar
    /// chart (which fills its region) and for the chart-only square.
    func verticalShift(for style: WorkoutSummaryChartStyle) -> CGFloat {
        guard arrangement == .stacked else { return 0 }
        return max(0, chartRect.height - chartFrame(for: style).height) / 2
    }
}

/// Where the centered card's info block (route trace + metric stack) sits, relative to
/// its default placement — the user drags and pinches it over a photo background, and
/// both the preview and the export read the same value so what's shared is what was
/// seen. Session-only, like the photo itself. The bounds keep a gesture from throwing
/// the block off into nowhere; they don't guarantee visibility, since an extreme
/// scale + offset pair can still clip it to a sliver — double-tapping to reset is the
/// recovery for that.
struct WorkoutShareInfoTransform: Equatable {
    /// In card points (whatever `cardSize` the chosen ratio has), not preview points.
    var offset: CGSize
    var scale: CGFloat

    static let identity = WorkoutShareInfoTransform(offset: .zero, scale: 1)

    static let scaleRange: ClosedRange<CGFloat> = 0.5...1.5

    /// - Parameter cardSize: The card the block lives on; the offset may travel half
    ///   of it on each axis (`WorkoutShareCardGeometry.maximumInfoOffset`). Passed in
    ///   rather than fixed, so a clamp can't outlive the ratio it was written for.
    ///
    /// A degenerate gesture value (NaN/infinite) clamps to the identity component
    /// rather than to a bound — a non-finite number has no meaningful side.
    func clamped(cardSize: CGSize) -> WorkoutShareInfoTransform {
        WorkoutShareInfoTransform(
            offset: CGSize(
                width: Self.clamp(offset.width, limit: cardSize.width / 2, identity: 0),
                height: Self.clamp(offset.height, limit: cardSize.height / 2, identity: 0)
            ),
            scale: scale.isFinite ? min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) : 1
        )
    }

    private static func clamp(_ value: CGFloat, limit: CGFloat, identity: CGFloat) -> CGFloat {
        guard value.isFinite else { return identity }
        return min(max(value, -limit), limit)
    }
}

/// How the user has panned and zoomed the photo behind the card, in the card's own
/// point space. Separate from `WorkoutShareInfoTransform` (which moves the info
/// block): the photo step adjusts the backdrop, the layout step adjusts the block, and
/// the export bakes both. Session-only, like the photo itself.
struct WorkoutSharePhotoTransform: Equatable {
    /// In card points, applied after `scale` — so a drag stays 1:1 at any zoom.
    var offset: CGSize
    var scale: CGFloat

    static let identity = WorkoutSharePhotoTransform(offset: .zero, scale: 1)

    /// Never below 1: the photo fills the card with `scaledToFill`, so zooming out
    /// past that could only uncover the background.
    static let scaleRange: ClosedRange<CGFloat> = 1...4

    /// Keeps the photo covering the whole card: given the size `scaledToFill` gives it
    /// in the `cardSize` frame, the offset can only travel as far as the overhang the
    /// scaled image has on each axis. A mismatched aspect ratio has overhang even at
    /// scale 1 — the photo may slide along its long axis, which is the point. The card
    /// is a parameter because the same photo covers a different shape on every ratio.
    ///
    /// A degenerate gesture value (NaN/infinite) resets that component to identity
    /// rather than pinning to a bound, the same rule `WorkoutShareInfoTransform` uses;
    /// an image with a non-positive side has no meaningful overhang, so the offset
    /// zeroes out and only the scale is clamped.
    func clamped(imageSize: CGSize, cardSize: CGSize) -> WorkoutSharePhotoTransform {
        let clampedScale = scale.isFinite
            ? min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            : 1

        let cardWidth = cardSize.width
        let cardHeight = cardSize.height
        guard imageSize.width > 0, imageSize.height > 0,
              imageSize.width.isFinite, imageSize.height.isFinite else {
            return WorkoutSharePhotoTransform(offset: .zero, scale: clampedScale)
        }

        let aspect = imageSize.width / imageSize.height
        let fillWidth = max(cardWidth, cardHeight * aspect)
        let fillHeight = max(cardHeight, cardWidth / aspect)
        let maximumOffsetWidth = max(0, (fillWidth * clampedScale - cardWidth) / 2)
        let maximumOffsetHeight = max(0, (fillHeight * clampedScale - cardHeight) / 2)

        return WorkoutSharePhotoTransform(
            offset: CGSize(
                width: Self.clamp(offset.width, limit: maximumOffsetWidth),
                height: Self.clamp(offset.height, limit: maximumOffsetHeight)
            ),
            scale: clampedScale
        )
    }

    private static func clamp(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, -limit), limit)
    }
}

/// The single seam that keeps a user photo from ever rendering for a non-Pro user, even
/// if UI state slips (e.g. a photo picked before the entitlement lapses). Mirrors
/// `BodyHomeBackground.proGatedColors`.
enum WorkoutShareBackgroundPolicy {
    static func resolvedPhoto(_ photo: UIImage?, isProUnlocked: Bool) -> UIImage? {
        isProUnlocked ? photo : nil
    }

    /// The same gate for a video background: a clip picked before the entitlement lapses
    /// stops rendering (and stops playing) without the sheet having to drop the pick.
    static func resolvedVideo(
        _ clip: WorkoutShareVideoClip?, isProUnlocked: Bool
    ) -> WorkoutShareVideoClip? {
        isProUnlocked ? clip : nil
    }

    /// The dimension the card may actually draw: 3D is Pro-only and needs a route with
    /// usable altitude. Never rewrites the stored key — a Pro lapse or a flat route
    /// falls back to 2D for the session only, so the next eligible share opens in 3D
    /// again (the same session-only fallback a stored map takes on a routeless share).
    static func resolvedDimension(
        _ dimension: WorkoutShareRouteDimension,
        isProUnlocked: Bool,
        isThreeDAvailable: Bool
    ) -> WorkoutShareRouteDimension {
        guard dimension == .threeD, isProUnlocked, isThreeDAvailable else { return .twoD }
        return .threeD
    }

    /// The ratio the card may actually render at: everything but 9:16 is Pro. Never
    /// rewrites the stored key, exactly like `resolvedDimension` — a lapsed Pro user
    /// shares at 9:16 for the session and gets their 16:9 back when they resubscribe.
    ///
    /// - Parameter supportsLandscape: Whether this share has landscape shapes at all.
    ///   The month summary offers only the portrait ratios and the square, so a 16:9
    ///   or 4:3 remembered from a workout share falls back to 9:16 for the session.
    static func resolvedAspectRatio(
        _ ratio: WorkoutShareAspectRatio,
        isProUnlocked: Bool,
        supportsLandscape: Bool = true
    ) -> WorkoutShareAspectRatio {
        guard supportsLandscape || !ratio.isLandscape else { return .portrait9x16 }
        guard ratio.isProGated, !isProUnlocked else { return ratio }
        return .portrait9x16
    }

    /// The output style the sheet may actually use: the long image is Pro. Same
    /// session-only fallback as the ratio — a lapsed subscriber shares the card and
    /// gets the long image back on resubscribe, with the stored key untouched.
    ///
    /// - Parameter supportsLongImage: Whether this share has a long image at all. The
    ///   month summary has no per-workout charts to stack, so it passes `false` and
    ///   the stored style resolves to the card without its key being rewritten.
    static func resolvedOutputStyle(
        _ style: WorkoutShareOutputStyle,
        isProUnlocked: Bool,
        supportsLongImage: Bool = true
    ) -> WorkoutShareOutputStyle {
        style == .longImage && isProUnlocked && supportsLongImage ? .longImage : .card
    }

    /// What one Share/Save tap produces. The long image wins over a held clip: forcing
    /// the background selection doesn't nil out `renderableVideo`, so without this seam
    /// a user who picked a video and then switched to the long image would get an MP4
    /// of the card they aren't looking at.
    static func resolvedOutput(
        style: WorkoutShareOutputStyle,
        hasRenderableVideo: Bool
    ) -> WorkoutShareOutput {
        if style == .longImage { return .longImage }
        return hasRenderableVideo ? .video : .cardImage
    }

    /// The gradient the long image paints. It never draws a map, a photo, or a clip, so
    /// a stored background that isn't a preset resolves to Midnight for the session —
    /// the key is left alone, exactly like every other fallback here, and the tray's
    /// selection ring reads this so it matches what renders.
    static func longPreset(storedBackground: String?, hasRoute: Bool) -> BodyWorkoutSharePreset {
        guard case .preset(let preset) = BodyWorkoutShareBackgroundChoice.stored(
            rawValue: storedBackground,
            hasRoute: hasRoute
        ) else {
            return .midnight
        }
        return preset
    }

    /// The metrics the card may actually show: picking them is Pro, so everyone else
    /// gets the automatic defaults. Same session-only fallback as the rest — a lapse
    /// never rewrites the stored pick, so resubscribing brings it straight back.
    static func resolvedMetricIDs(
        _ resolved: [String],
        defaults: [String],
        isProUnlocked: Bool
    ) -> [String] {
        isProUnlocked ? resolved : defaults
    }
}
