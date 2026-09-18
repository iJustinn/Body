//
//  WatchWorkoutChangeTracker.swift
//  BodyWatch
//
//  The watch's change cursor over its own workouts: one anchored query per
//  type (workouts, and the effort scores rated onto them), resumed from a
//  persisted anchor. Anything added OR deleted since the last committed anchor
//  counts as a change, which is what a "newest workout end date" compare can
//  never see: a deletion, a rating that lands later, or a workout saved a few
//  seconds after a compute had already started.
//
//  Detection is cheap (two bounded queries) and is all this type does. Turning
//  a detection into a compute, and deciding when that compute has actually
//  consumed it, is `WatchPendingRecomputePolicy`'s job in the model.
//

import Foundation
import HealthKit

protocol WatchWorkoutChangeDetecting: Sendable {
    /// Whether any tracked workout data changed since the last committed
    /// cursor. `false` on a query failure: nothing was learned.
    func detectChanges(now: Date) async -> Bool
    /// Advances the persisted cursor past the changes the last `detectChanges`
    /// saw. Called only AFTER the caller has recorded them as pending work, so
    /// a process that dies in between re-detects instead of losing the change.
    func commitDetectedChanges() async
}

actor WatchWorkoutChangeTracker: WatchWorkoutChangeDetecting {
    /// How far back added samples are considered. The drain window is one wake
    /// cycle (at most 24 hours); two days also covers a Training Load slot
    /// changing under the delta window.
    static let lookback: TimeInterval = 48 * 60 * 60

    private let store = HKHealthStore()
    private let defaults: UserDefaults
    private var stagedAnchors: [String: HKQueryAnchor] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var trackedTypes: [HKSampleType] {
        var types: [HKSampleType] = [HKObjectType.workoutType()]
        if let effortType = HKObjectType.quantityType(forIdentifier: .workoutEffortScore) {
            types.append(effortType)
        }
        return types
    }

    private static func anchorKey(for type: HKSampleType) -> String {
        "watchWorkoutChangeAnchor.\(type.identifier)"
    }

    func detectChanges(now: Date) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        stagedAnchors = [:]
        var changed = false
        for type in Self.trackedTypes {
            guard let result = await changes(of: type, now: now) else { continue }
            stagedAnchors[Self.anchorKey(for: type)] = result.anchor
            changed = changed || result.changed
        }
        return changed
    }

    func commitDetectedChanges() {
        for (key, anchor) in stagedAnchors {
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: anchor, requiringSecureCoding: true
            ) else { continue }
            defaults.set(data, forKey: key)
        }
        stagedAnchors = [:]
    }

    /// Drops the persisted cursor, so tracking restarts from scratch the next
    /// time Workouts is permitted.
    func reset() {
        stagedAnchors = [:]
        for type in Self.trackedTypes {
            defaults.removeObject(forKey: Self.anchorKey(for: type))
        }
    }

    private func storedAnchor(for type: HKSampleType) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: Self.anchorKey(for: type)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func changes(
        of type: HKSampleType,
        now: Date
    ) async -> (changed: Bool, anchor: HKQueryAnchor)? {
        let anchor = storedAnchor(for: type)
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-Self.lookback), end: nil
        )
        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                guard error == nil, let newAnchor else {
                    continuation.resume(returning: nil)
                    return
                }
                let changed = !(samples ?? []).isEmpty || !(deleted ?? []).isEmpty
                continuation.resume(returning: (changed, newAnchor))
            }
            store.execute(query)
        }
    }
}
