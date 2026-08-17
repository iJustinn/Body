//
//  WorkoutShareCard.swift
//  Body
//
//  Pure logic backing the workout share image: which metrics appear on the
//  card, how a GPS route projects into the card's route trace, the built-in
//  background presets, and the Pro gate on user photos. No rendering here —
//  see the share card/sheet views for the UI that consumes these.
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
/// workout's story and so takes a longer list including active energy.
enum WorkoutShareMetricsBuilder {
    static func metrics(for presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> [WorkoutShareMetric] {
        // The bottom-left row. Distance and duration live in the card's header (the
        // hero corner reads heroDistanceValue/Unit and durationClockText directly),
        // so the row carries the per-type extras: pace/speed, elevation, avg HR.
        let candidates: [WorkoutShareMetric?] = [
            presentation.heroDistanceValue == nil ? distanceTileMetric(presentation: presentation) : nil,
            rateMetric(presentation: presentation, type: type),
            elevationMetric(presentation: presentation, type: type),
            averageHeartRateMetric(presentation: presentation)
        ]
        return Array(candidates.compactMap { $0 }.prefix(2))
    }

    /// Up to 3 metrics for the centered card, where every metric is a label-over-value
    /// block — so distance and duration are part of the stack here rather than living in
    /// a header. Distance, rate, and time lead; elevation/avg HR only fill slots the
    /// workout couldn't (a distance-less or rate-less type), never push those out.
    static func centeredMetrics(for presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> [WorkoutShareMetric] {
        let candidates: [WorkoutShareMetric?] = [
            blockDistanceMetric(presentation: presentation),
            shortRateMetric(presentation: presentation, type: type),
            WorkoutShareMetric(title: String(localized: "Time"), value: presentation.durationClockText),
            elevationMetric(presentation: presentation, type: type),
            averageHeartRateMetric(presentation: presentation)
        ]
        return Array(candidates.compactMap { $0 }.prefix(3))
    }

    /// Up to 4 metrics for the route-less card. Same block-style selection as
    /// `centeredMetrics`, one slot longer and with active energy joining the list: with
    /// no trace and no header, the stack is all the card says about the workout, and an
    /// indoor workout (strength, yoga, HIIT) often has no distance or rate to fill it.
    static func routelessMetrics(for presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> [WorkoutShareMetric] {
        let candidates: [WorkoutShareMetric?] = [
            blockDistanceMetric(presentation: presentation),
            shortRateMetric(presentation: presentation, type: type),
            WorkoutShareMetric(title: String(localized: "Time"), value: presentation.durationClockText),
            activeEnergyMetric(presentation: presentation),
            elevationMetric(presentation: presentation, type: type),
            averageHeartRateMetric(presentation: presentation)
        ]
        return Array(candidates.compactMap { $0 }.prefix(4))
    }

    /// Distance as a label-over-value block: the hero value + unit when the type
    /// promotes distance, otherwise the Details `.distance` tile. Shared by the two
    /// block layouts, which read distance out of the stack rather than a header.
    private static func blockDistanceMetric(presentation: WorkoutDetailPresentation) -> WorkoutShareMetric? {
        if let heroValue = presentation.heroDistanceValue, let heroUnit = presentation.heroDistanceUnit {
            return WorkoutShareMetric(title: String(localized: "Distance"), value: heroValue + " " + heroUnit)
        }
        return distanceTileMetric(presentation: presentation)
    }

    /// The Details `.distance` tile, for workouts that don't promote distance to the
    /// hero corner (e.g. a strength workout with a recorded distance). Not present
    /// (e.g. a distance-less strength workout) → no candidate.
    private static func distanceTileMetric(presentation: WorkoutDetailPresentation) -> WorkoutShareMetric? {
        tile(.distance, in: presentation).map { WorkoutShareMetric(title: $0.title, value: $0.value) }
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

    private static func rateMetric(presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> WorkoutShareMetric? {
        rateTile(presentation: presentation, type: type).map { WorkoutShareMetric(title: $0.tile.title, value: $0.tile.value) }
    }

    /// Same value, but titled "Pace"/"Speed" instead of the tile's "Avg Pace"/"Avg Speed":
    /// the centered layout's labels are short by design, and its blocks are already read
    /// as workout averages.
    private static func shortRateMetric(presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> WorkoutShareMetric? {
        guard let rate = rateTile(presentation: presentation, type: type) else { return nil }
        let title: String
        switch rate.style {
        case .distancePace, .swimPace: title = String(localized: "Pace")
        case .speed: title = String(localized: "Speed")
        case .none: return nil
        }
        return WorkoutShareMetric(title: title, value: rate.tile.value)
    }

    /// Elevation only makes sense for activities that actually climb — hiking/climbing-
    /// style and snow-sports types (mirrors `BodyWorkoutType.colorHex`'s groupings for
    /// those activities) — and only when the workout recorded any gain.
    private static func elevationMetric(presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> WorkoutShareMetric? {
        guard isElevationEligible(type) else { return nil }
        return tile(.elevation, in: presentation).map { WorkoutShareMetric(title: $0.title, value: $0.value) }
    }

    private static func isElevationEligible(_ type: BodyWorkoutType) -> Bool {
        switch type {
        case .hiking, .climbing, .stairClimbing, .stairs, .stepTraining,
             .snowSports, .crossCountrySkiing, .downhillSkiing, .snowboarding, .curling:
            return true
        default:
            return false
        }
    }

    /// Active energy, titled from the `.activeEnergy` tile so kJ users and every
    /// locale get the tile's own wording ("Active kcal"/"Active kJ") with no second
    /// string to keep in sync. The value comes from the presentation, not the tile:
    /// the tile is always present and reads "No Data" when the workout recorded no
    /// energy, which must never land on a shared image.
    private static func activeEnergyMetric(presentation: WorkoutDetailPresentation) -> WorkoutShareMetric? {
        guard let value = presentation.activeEnergyText, let energyTile = tile(.activeEnergy, in: presentation) else {
            return nil
        }
        return WorkoutShareMetric(title: energyTile.title, value: value)
    }

    private static func averageHeartRateMetric(presentation: WorkoutDetailPresentation) -> WorkoutShareMetric? {
        guard let value = presentation.averageHeartRateText, let heartRateTile = tile(.avgHeartRate, in: presentation) else {
            return nil
        }
        return WorkoutShareMetric(title: heartRateTile.title, value: value)
    }

    private static func tile(_ kind: WorkoutDetailMetric.Kind, in presentation: WorkoutDetailPresentation) -> WorkoutDetailMetric? {
        presentation.detailMetrics.first { $0.kind == kind }
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

/// Built-in gradient backgrounds for the share card — free, code-defined (no assets).
/// User photos are a separate, Pro-gated path; see `WorkoutShareBackgroundPolicy`.
enum BodyWorkoutSharePreset: String, CaseIterable, Identifiable {
    case midnight
    case workoutTint

    var id: String { rawValue }

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

/// Where the centered card's info block (route trace + metric stack) sits, relative to
/// its default placement — the user drags and pinches it over a photo background, and
/// both the preview and the export read the same value so what's shared is what was
/// seen. Session-only, like the photo itself. The bounds keep a gesture from throwing
/// the block off into nowhere; they don't guarantee visibility, since an extreme
/// scale + offset pair can still clip it to a sliver — double-tapping to reset is the
/// recovery for that.
struct WorkoutShareInfoTransform: Equatable {
    /// In card points (the 360×640 space), not preview points.
    var offset: CGSize
    var scale: CGFloat

    static let identity = WorkoutShareInfoTransform(offset: .zero, scale: 1)

    static let scaleRange: ClosedRange<CGFloat> = 0.5...1.5
    /// Half the card on each axis.
    static let maximumOffsetWidth: CGFloat = 180
    static let maximumOffsetHeight: CGFloat = 320

    /// A degenerate gesture value (NaN/infinite) clamps to the identity component
    /// rather than to a bound — a non-finite number has no meaningful side.
    func clamped() -> WorkoutShareInfoTransform {
        WorkoutShareInfoTransform(
            offset: CGSize(
                width: Self.clamp(offset.width, limit: Self.maximumOffsetWidth, identity: 0),
                height: Self.clamp(offset.height, limit: Self.maximumOffsetHeight, identity: 0)
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
/// 360×640 space. Separate from `WorkoutShareInfoTransform` (which moves the info
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
    /// in the 360×640 frame, the offset can only travel as far as the overhang the
    /// scaled image has on each axis. A mismatched aspect ratio has overhang even at
    /// scale 1 — the photo may slide along its long axis, which is the point.
    ///
    /// A degenerate gesture value (NaN/infinite) resets that component to identity
    /// rather than pinning to a bound, the same rule `WorkoutShareInfoTransform` uses;
    /// an image with a non-positive side has no meaningful overhang, so the offset
    /// zeroes out and only the scale is clamped.
    func clamped(imageSize: CGSize) -> WorkoutSharePhotoTransform {
        let clampedScale = scale.isFinite
            ? min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            : 1

        let cardWidth = BodyWorkoutShareCardView.cardSize.width
        let cardHeight = BodyWorkoutShareCardView.cardSize.height
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
}
