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

/// Picks up to 3 metrics for the share card, in priority order, by reusing the
/// same `WorkoutDetailPresentation` the detail page already built — so values,
/// units, and locale never drift from what the user just saw. Only title/value
/// are copied; `WorkoutDetailMetric.comparison` (the "vs 30-day avg" badge)
/// never appears on a shared image.
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
        return Array(candidates.compactMap { $0 }.prefix(3))
    }

    /// The Details `.distance` tile, for workouts that don't promote distance to the
    /// hero corner (e.g. a strength workout with a recorded distance). Not present
    /// (e.g. a distance-less strength workout) → no candidate.
    private static func distanceTileMetric(presentation: WorkoutDetailPresentation) -> WorkoutShareMetric? {
        tile(.distance, in: presentation).map { WorkoutShareMetric(title: $0.title, value: $0.value) }
    }

    /// Pace/speed/swim-pace, matched by `Kind` — never by localized title, so it can't
    /// mix up two types whose tiles happen to share a translation (e.g. running's and
    /// swimming's both say "Avg Pace").
    private static func rateMetric(presentation: WorkoutDetailPresentation, type: BodyWorkoutType) -> WorkoutShareMetric? {
        let kind: WorkoutDetailMetric.Kind
        switch type.paceStyle {
        case .distancePace: kind = .pace
        case .speed: kind = .speed
        case .swimPace: kind = .swimPace
        case .none: return nil
        }
        return tile(kind, in: presentation).map { WorkoutShareMetric(title: $0.title, value: $0.value) }
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
    case ocean
    case sunset
    case forest

    var id: String { rawValue }

    static let storageKey = "workoutShareBackgroundPreset"

    /// The default when nothing (or something invalid) is stored.
    static func stored(rawValue: String?) -> BodyWorkoutSharePreset {
        guard let rawValue, let preset = BodyWorkoutSharePreset(rawValue: rawValue) else {
            return .midnight
        }
        return preset
    }

    func gradient(tint: Color) -> LinearGradient {
        switch self {
        case .midnight:
            return LinearGradient(
                colors: [Color(white: 0.16), Color.black],
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
        case .ocean:
            return LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.16, blue: 0.26),
                    Color(red: 0.00, green: 0.05, blue: 0.11)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .sunset:
            return LinearGradient(
                colors: [
                    Color(red: 0.36, green: 0.10, blue: 0.14),
                    Color(red: 0.17, green: 0.05, blue: 0.15),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .forest:
            return LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.15, blue: 0.09),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var localizedName: String {
        switch self {
        case .midnight: return String(localized: "Midnight")
        case .workoutTint: return String(localized: "Workout Color")
        case .ocean: return String(localized: "Ocean")
        case .sunset: return String(localized: "Sunset")
        case .forest: return String(localized: "Forest")
        }
    }
}

/// The single seam that keeps a user photo from ever rendering for a non-Pro user, even
/// if UI state slips (e.g. a photo picked before the entitlement lapses). Mirrors
/// `BodyHomeBackground.proGatedColors`.
enum WorkoutShareBackgroundPolicy {
    static func resolvedPhoto(_ photo: UIImage?, isProUnlocked: Bool) -> UIImage? {
        isProUnlocked ? photo : nil
    }
}
