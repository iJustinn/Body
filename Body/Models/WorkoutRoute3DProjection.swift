//
//  WorkoutRoute3DProjection.swift
//  Body
//
//  Projects a GPS route into the oblique, elevation-extruded ribbon drawn by the
//  3D route hero (Route Style › 3D). Pure geometry — no drawing, no SwiftUI — so
//  the camera math is unit-testable on its own: it turns the route's ground trace
//  and altitudes into a lifted `top` line and the `base` line directly beneath it,
//  in unit-ish camera space (y down). The hero fits both into hero space.
//
//  The route can also be turned about its own centre (`yaw`), which is what the
//  hero's horizontal swipe drives; the projection hands back the rest pose alongside
//  the turned one so the framing doesn't move while it spins.
//

import Foundation
import CoreGraphics

enum WorkoutRoute3DProjection {
    /// Fraction of the fixes that must carry a usable altitude before the route is
    /// drawn in 3D at all. Below it the hero falls back to the Plain trace rather
    /// than inventing terrain from a handful of readings.
    private static let minimumAltitudeCoverage = 0.5
    /// Low/high percentiles of the altitude range. Trimming the tails keeps one bad
    /// barometric spike from flattening the whole ribbon into the floor.
    private static let lowPercentile = 0.02
    private static let highPercentile = 0.98
    /// Relief (in unit ground spans) of a route with `fullReliefMetres` or more of
    /// climb; smaller ranges rise proportionally, so a rolling route doesn't read as
    /// dramatically as an alpine one.
    private static let maximumReliefUnits = 0.30
    /// Altitude range that earns the full relief.
    private static let fullReliefMetres = 200.0
    /// Constant lift under every point: even a dead-flat route is a raised plank with
    /// visible walls rather than a Plain lookalike.
    private static let deckUnits = 0.05
    /// Vertical squash of the ground plane — the fixed oblique camera looking down at
    /// the route from the south, north-up.
    private static let groundSquash = 0.55

    /// The two polylines of the ribbon, same count and route order: `top` is the
    /// lifted line, `base` the ground trace directly below each of its points —
    /// plus the pose the caller should frame by.
    struct Projected3D: Equatable {
        let top: [CGPoint]
        let base: [CGPoint]
        /// The rest (yaw 0) ribbon, `top + base`, whatever the requested yaw. The hero
        /// fits this rather than the turned ribbon, so the route frames exactly as it
        /// did before rotation existed and neither the scale nor the centre shifts
        /// while it turns. At yaw 0 it is `top + base`.
        let fitReference: [CGPoint]
    }

    /// The ribbon for this route, or `nil` when it can't be drawn — a degenerate
    /// (treadmill-jitter) ground trace, or too few fixes carrying altitude. Callers
    /// fall back to the flat route trace.
    ///
    /// - Parameter yaw: Rotation of the ground plane about the route's centre, in
    ///   radians — positive turns the route clockwise as seen from above. Non-finite
    ///   values are treated as 0.
    static func projected(for coordinates: [RouteCoordinate], yaw: Double = 0) -> Projected3D? {
        let filtered = filteredCoordinates(coordinates)
        guard let ground = WorkoutShareRouteProjection.normalizedPoints(for: filtered),
              ground.count == filtered.count,
              let lift = lift(for: filtered) else {
            return nil
        }

        let angle = yaw.isFinite ? yaw : 0
        let rest = lifted(ground: ground, lift: lift)
        // Yaw 0 reuses the rest pose outright: no rotation arithmetic runs, so the
        // unturned ribbon is bit-identical to the pre-rotation projection.
        let turned = angle == 0 ? rest : lifted(ground: rotated(ground: ground, angle: angle), lift: lift)
        let fitReference = rest.top + rest.base

        guard turned.top.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              turned.base.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              fitReference.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }
        return Projected3D(top: turned.top, base: turned.base, fitReference: fitReference)
    }

    /// How far above the ground each fix stands, in unit ground spans (deck + relief),
    /// or `nil` when the route can't be drawn in 3D — the same degeneracy and altitude-
    /// coverage rules `projected(for:yaw:)` applies. Exposed on its own so the share
    /// card's map background can raise the route over real map geometry, without the
    /// oblique camera the ribbon hero frames through.
    static func liftUnits(for coordinates: [RouteCoordinate]) -> [Double]? {
        let filtered = filteredCoordinates(coordinates)
        guard let ground = WorkoutShareRouteProjection.normalizedPoints(for: filtered),
              ground.count == filtered.count else {
            return nil
        }
        return lift(for: filtered)
    }

    /// The same predicate `normalizedPoints` uses, applied once up front so the
    /// altitudes read off the result stay index-aligned with the points it returns
    /// (it re-filters the already-filtered input harmlessly).
    private static func filteredCoordinates(_ coordinates: [RouteCoordinate]) -> [RouteCoordinate] {
        coordinates.filter {
            $0.latitude.isFinite && $0.longitude.isFinite &&
            abs($0.latitude) <= 90 && abs($0.longitude) <= 180
        }
    }

    /// Deck + relief per fix, or `nil` when too few fixes carry a usable altitude. A
    /// property of the altitudes alone, so it survives the yaw and is computed once for
    /// both poses.
    private static func lift(for coordinates: [RouteCoordinate]) -> [Double]? {
        let rawAltitudes: [Double?] = coordinates.map { coordinate in
            guard let altitude = coordinate.altitude, altitude.isFinite else {
                return nil
            }
            return altitude
        }
        let validCount = rawAltitudes.compactMap { $0 }.count
        guard validCount >= 2,
              Double(validCount) >= minimumAltitudeCoverage * Double(rawAltitudes.count) else {
            return nil
        }

        let altitudes = filledAltitudes(rawAltitudes)
        let (lo, hi) = percentileRange(of: altitudes)
        let range = hi - lo
        let reliefUnits = maximumReliefUnits * min(1, range / fullReliefMetres)

        return altitudes.map { altitude -> Double in
            // A flat (or unusable) range lifts every point onto the same deck.
            guard range > 0, range.isFinite else {
                return deckUnits
            }
            return deckUnits + min(max((altitude - lo) / range, 0), 1) * reliefUnits
        }
    }

    /// Raises a ground trace into the ribbon: the ground plane squashed by the oblique
    /// camera, and the deck + relief lift standing above each of its points.
    private static func lifted(ground: [CGPoint], lift: [Double]) -> (top: [CGPoint], base: [CGPoint]) {
        var top: [CGPoint] = []
        var base: [CGPoint] = []
        top.reserveCapacity(ground.count)
        base.reserveCapacity(ground.count)
        for (index, point) in ground.enumerated() {
            let groundY = point.y * groundSquash
            top.append(CGPoint(x: point.x, y: groundY - lift[index]))
            base.append(CGPoint(x: point.x, y: groundY))
        }
        return (top, base)
    }

    /// Turns the unit-square ground trace about the route's centre (0.5, 0.5), before
    /// the ground squash — so the camera stays put and the route spins under it,
    /// rather than the whole squashed picture rotating in the plane of the screen.
    private static func rotated(ground: [CGPoint], angle: Double) -> [CGPoint] {
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        return ground.map { point in
            let dx = Double(point.x) - 0.5
            let dy = Double(point.y) - 0.5
            return CGPoint(
                x: 0.5 + dx * cosAngle - dy * sinAngle,
                y: 0.5 + dx * sinAngle + dy * cosAngle
            )
        }
    }

    /// Fills the gaps in a partly-covered altitude track: internal gaps interpolate
    /// linearly by index between their neighbours, leading and trailing gaps take the
    /// nearest valid reading (there is nothing to interpolate towards).
    private static func filledAltitudes(_ altitudes: [Double?]) -> [Double] {
        var filled = altitudes
        var lastValidIndex: Int?
        for index in filled.indices where filled[index] != nil {
            if let previous = lastValidIndex, previous < index - 1 {
                let start = filled[previous]!
                let end = filled[index]!
                let steps = Double(index - previous)
                for gap in (previous + 1)..<index {
                    filled[gap] = start + (end - start) * Double(gap - previous) / steps
                }
            } else if lastValidIndex == nil, index > 0 {
                for leading in 0..<index {
                    filled[leading] = filled[index]
                }
            }
            lastValidIndex = index
        }
        if let last = lastValidIndex, last < filled.count - 1 {
            for trailing in (last + 1)..<filled.count {
                filled[trailing] = filled[last]
            }
        }
        // Every slot is filled: the caller guarantees at least two valid readings.
        return filled.map { $0 ?? 0 }
    }

    /// Outlier-trimmed [lo, hi] altitude range.
    private static func percentileRange(of altitudes: [Double]) -> (lo: Double, hi: Double) {
        let sorted = altitudes.sorted()
        let lastIndex = Double(sorted.count - 1)
        return (sorted[Int(lastIndex * lowPercentile)], sorted[Int(lastIndex * highPercentile)])
    }
}
