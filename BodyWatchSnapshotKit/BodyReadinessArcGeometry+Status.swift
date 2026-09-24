//
//  BodyReadinessArcGeometry+Status.swift
//  BodyWatchSnapshotKit
//
//  The status each hero band stands for. Kept out of the geometry file in
//  BodyWatchShared because the watch widget extension compiles that file but
//  not `ReadinessStatus` (BodyMetricsKit).
//

extension BodyReadinessArcGeometry {
    /// Left to right along the track, matching `bandScoreRanges`.
    static let segmentOrder: [ReadinessStatus] = [.poor, .low, .moderate, .high, .prime]
}
