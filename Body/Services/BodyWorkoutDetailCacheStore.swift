import Foundation

/// The per-workout detail session caches, lifted out of `HealthKitWorkoutStore`
/// so the store's own surface is the app state views observe and this is not.
///
/// Deliberately a plain `@MainActor final class` rather than `@Observable`: none
/// of these caches is view-observed state. The only reads reachable from a
/// SwiftUI `body` are `cachedWorkoutRoute(for:)` and
/// `cachedWorkoutRoutePresence(for:)` in `BodyWorkoutsView`, and that view
/// prefers its own `@State route` and latches `routeWasCachedOnOpen` in
/// `.onAppear`, so a cache write never has to invalidate a body. Making these
/// tracked would only add re-render churn on every detail load.
///
/// Ownership is one-way: `HealthKitWorkoutStore` holds the only instance, its
/// loaders and `hydrateWorkoutDetailIfNeeded` read and write these dictionaries
/// directly, and every bulk clear goes through one of the named methods below so
/// the subsets stay in one place.
///
/// Per-workout entries are the store's to write; wholesale invalidation is not.
/// Clear through `clearAll()`, `clearHeartScopedCaches()` or
/// `clearWorkoutMetricsScopedCaches()`, never with an ad hoc `removeAll()` on a
/// cache: each named method also drops the hydration tasks and the eviction
/// order, and emptying one dictionary in place would leave both pointing at
/// workouts whose data is gone, so the next open reads a half-cleared session.
@MainActor
final class BodyWorkoutDetailCacheStore {
    /// Session cache of resolved workout routes keyed by workout UUID. A cached
    /// `.some(nil)` means "confirmed no readable route", so non-route workouts
    /// aren't re-queried and the city label isn't re-geocoded when a detail
    /// sheet is reopened. HealthKit read access is opaque, so this cache is
    /// cleared on the authorization pass that showed the permission sheet, and
    /// eagerly the moment the app enters the background (where access could have
    /// been changed in the Health app or Settings, with no signal on return);
    /// it is kept across in-session refreshes, month page-ins and intraday fills.
    ///
    /// The background clear is eager rather than deferred to the next
    /// authorization pass because the detail loaders serve this cache directly
    /// and a resume can skip that pass entirely (debounced, refresh already
    /// running, initial load pending).
    var routeCache: [UUID: WorkoutRoute?] = [:]
    /// Session cache of the cheap `HKWorkoutRoute` presence probe, keyed by workout
    /// UUID. Separate from `routeCache` because the probe can answer "yes" long before
    /// the coordinates exist, and kept consistent with it: the `< 2 coordinates` branch
    /// of the load writes `false` here too, so a workout whose route samples exist but
    /// yield no drawable line never reserves the detail hero's band a second time.
    /// Cleared wherever `routeCache` is, on the same terms, including the eager
    /// background clear.
    var routePresenceCache: [UUID: Bool] = [:]
    /// Session cache of a workout's raw distance samples keyed by UUID, feeding the
    /// detail Splits section. Empty results are cached only for workouts that ended
    /// more than 24 h ago; recent workouts may still be syncing from the watch, so
    /// their empty reads are retried on the next sheet open.
    var distanceSampleCache: [UUID: WorkoutSplitData] = [:]
    /// Session cache of a workout's per-bucket series inputs (pace/speed, cadence,
    /// stride length, running form) keyed by UUID, feeding the detail chart cards.
    /// Cached only for workouts that ended more than 24 h ago (a recent workout may
    /// still be syncing its samples from the watch, and caching now would pin the
    /// cards to a partial result for the rest of the session), plus: a bundle with a
    /// failed metric
    /// read is never cached, so a transient error can't hide a card all session.
    ///
    /// The 24 h settle rule is stricter than the splits cache's "cache anything
    /// non-empty" because this is a MULTI-FAMILY bundle: cadence can be synced while
    /// stride length isn't, so a successful read can still be partial without any
    /// query failing. A single-result read like splits has no such half-state — it's
    /// either there or empty — so it only needs the settle rule for the empty case.
    var metricSeriesCache: [UUID: WorkoutMetricSeriesData] = [:]
    /// Session cache of a workout's 1-minute heart-rate recovery keyed by UUID,
    /// feeding the detail tile. A confirmed absence (`nil`) is cached too, but —
    /// same settle rule as above — only for workouts that ended more than 24 h ago:
    /// the watch writes the recovery sample a minute after the workout ends, so a
    /// just-finished workout must be re-read on the next sheet open.
    var heartRateRecoveryCache: [UUID: Double?] = [:]
    /// Session cache of a workout's full-resolution heart-rate series keyed by UUID,
    /// feeding the detail sheet's chart and zones (the summary carries a ≤96-point
    /// downsample, enough for the list row but not the chart). Session-only and
    /// never persisted: the dense payload is large and re-readable on demand. Empty
    /// results follow the same settle rule as the splits cache — cached only for
    /// workouts that ended more than 24 h ago, since a recent one may still be
    /// syncing its samples from the watch.
    var heartRateSeriesCache: [UUID: [WorkoutHeartRateSample]] = [:]
    /// Session cache of a workout's persisted energy-equivalent breakdown,
    /// keyed by UUID. The full payload (not just the emojis) is kept so
    /// `energyEquivalentEmojis(for:hiddenFoods:)` can compare its kcal and
    /// hidden-food inputs against the current ones to decide whether the
    /// cached emojis are still valid.
    var energyEquivalentCache: [UUID: PersistedEnergyEquivalent] = [:]
    /// In-flight (or finished) disk hydrations of the persisted per-workout detail
    /// snapshot, keyed by workout UUID. A task map rather than a "done" flag Set
    /// because the detail sheet fires the route probe, the route load, the series
    /// load and the recovery load concurrently: a flag written only on completion
    /// would let three of them hydrate in parallel, and a flag written up front
    /// would let them skip past a hydration that hasn't read the file yet. Awaiting
    /// the shared task gives every entry point the seeded caches exactly once —
    /// which is why the task spans the read AND the seeding rather than
    /// resolving to the loaded snapshot: awaiting a read-only task would resume
    /// the other three before a single cache had been written.
    ///
    /// Finished entries are left in place (a completed task is tiny) and leave
    /// only with an LRU eviction or a bulk clear, so an evicted workout hydrates
    /// from its file again on the next open. The background clear empties this
    /// map along with the caches, and while `bypassesPersistedDetailSeeding` is
    /// set no hydration task is created at all, so detail opens go straight to
    /// the live HealthKit loaders instead of the on-disk seed.
    var detailHydrations: [UUID: Task<Void, Never>] = [:]
    /// Workout UUIDs whose detail caches are live, oldest opened first. Drives the
    /// `maximumCachedWorkoutDetails` eviction; every bulk clear of the detail
    /// caches resets it too.
    private(set) var workoutDetailCacheOrder: [UUID] = []

    /// Marks a workout's detail caches as most recently used and evicts the
    /// oldest beyond `maximumCachedWorkoutDetails`. Called from
    /// `HealthKitWorkoutStore.hydrateWorkoutDetailIfNeeded`, which every detail
    /// entry point runs before it fills any of these caches.
    func touch(_ id: UUID) {
        workoutDetailCacheOrder.removeAll { $0 == id }
        workoutDetailCacheOrder.append(id)

        let evicted = HealthKitWorkoutStore.evictableWorkoutDetailIDs(
            order: workoutDetailCacheOrder,
            maximum: HealthKitWorkoutStore.maximumCachedWorkoutDetails
        )
        guard !evicted.isEmpty else {
            return
        }

        let evictedSet = Set(evicted)
        workoutDetailCacheOrder.removeAll { evictedSet.contains($0) }
        for evictedID in evicted {
            // `removeValue` rather than `= nil`: two of these caches hold optional
            // values, where a `nil` assignment reads as "cache a negative".
            routeCache.removeValue(forKey: evictedID)
            routePresenceCache.removeValue(forKey: evictedID)
            distanceSampleCache.removeValue(forKey: evictedID)
            metricSeriesCache.removeValue(forKey: evictedID)
            heartRateRecoveryCache.removeValue(forKey: evictedID)
            heartRateSeriesCache.removeValue(forKey: evictedID)
            energyEquivalentCache.removeValue(forKey: evictedID)
            detailHydrations.removeValue(forKey: evictedID)
        }
    }

    /// Drops every per-workout detail cache. Used wherever what HealthKit will
    /// hand back may have changed wholesale, or the workouts themselves are
    /// gone: the authorization pass that presented the permission sheet, a
    /// Workouts permission toggle, the eager clear when the app enters the
    /// background, and Clear Cache.
    func clearAll() {
        routeCache.removeAll()
        routePresenceCache.removeAll()
        distanceSampleCache.removeAll()
        metricSeriesCache.removeAll()
        heartRateRecoveryCache.removeAll()
        heartRateSeriesCache.removeAll()
        energyEquivalentCache.removeAll()
        detailHydrations = [:]
        workoutDetailCacheOrder.removeAll()
    }

    /// Heart-rate recovery and the detail sheet's full-resolution series ride
    /// the Heart toggle; drop them rather than serving a toggle change a
    /// result read under the old selection.
    func clearHeartScopedCaches() {
        heartRateRecoveryCache.removeAll()
        heartRateSeriesCache.removeAll()
        detailHydrations = [:]
        workoutDetailCacheOrder.removeAll()
    }

    /// Cached split data carries per-split step cadence, and stride length is
    /// gated the same way — both ride on the Workout Metrics permission, so
    /// drop them rather than serving a toggle change stale results from a
    /// read taken under the previous selection.
    func clearWorkoutMetricsScopedCaches() {
        distanceSampleCache.removeAll()
        metricSeriesCache.removeAll()
        detailHydrations = [:]
        workoutDetailCacheOrder.removeAll()
    }
}
