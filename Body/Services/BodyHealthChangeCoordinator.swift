import Foundation
import HealthKit
import UIKit

/// App-lifetime observation and durable repair ownership. Observer callbacks only
/// capture metadata; foreground debounce and BGTask opportunities do the reads.
@MainActor
final class BodyHealthChangeCoordinator {
    private unowned let store: HealthKitWorkoutStore
    private let ledger: BodyHealthDirtyWorkStore
    private let observing: any BodyHealthObserving
    private let suppressesInitialDelivery: @MainActor () -> Bool
    private var registrations: [BodyHealthObservation] = []
    private var context: BodyHealthObserverContext { store.currentObserverLedgerContext() }
    private var debounce: Task<Void, Never>?
    private var firstWake: ContinuousClock.Instant?
    private var repairing = false
    private var foregroundWork: Task<Bool, Never>?
    private var followupNeeded = false
    private lazy var observer = BodyHealthChangeObserver(observer: observing,
        suppressesInitialDelivery: suppressesInitialDelivery) { [weak self] identifier, failed in
        await self?.capture(identifier: identifier, failed: failed)
    }

    init(store: HealthKitWorkoutStore, file: URL, observing: (any BodyHealthObserving)? = nil,
         suppressesInitialDelivery: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState != .background }) {
        self.store = store
        self.suppressesInitialDelivery = suppressesInitialDelivery
        self.observing = observing ?? BodyHealthKitObserver()
        let registrations = BodyHealthObservationPolicy.registrations(permissions: store.permissionSelection, selection: .load(), includesCompanionConsumers: true)
        ledger = BodyHealthDirtyWorkStore(file: file, domains: Set(registrations.flatMap(\.metrics)),
                                         context: store.currentObserverLedgerContext())
    }

    func configure() async {
        let next = BodyHealthObservationPolicy.registrations(permissions: store.permissionSelection,
                                                            selection: .load(), includesCompanionConsumers: true)
        let nextContext = store.currentObserverLedgerContext()
        registrations = next
        _ = await ledger.synchronize(domains: Set(next.flatMap(\.metrics)), context: nextContext)
        await observer.configure(next)
    }

    func contextDidChange() {
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("coordinator contextDidChange repairing=\(repairing) busy=\(store.isRefreshing)")
        #endif
        Task { @MainActor [weak self] in
            await self?.configure()
            self?.scheduleForeground()
        }
    }

    func reset() async {
        debounce?.cancel()
        debounce = nil
        _ = await ledger.reset(domains: Set(registrations.flatMap(\.metrics)), context: context)
    }

    private func capture(identifier: String, failed: Bool) async {
        guard let registration = registrations.first(where: { $0.type.identifier == identifier }) else { return }
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("delivery observerError=\(failed) kinds=[\(registration.metrics.map(\.rawValue).sorted().joined(separator: ","))]")
        #endif
        // Bypass TTL admission before the first suspension. Capture failure keeps the
        // in-memory obligation and never withholds HealthKit's completion.
        store.invalidateObservedHealthChanges()
        _ = await ledger.mark(registration.metrics, context: context)
        if registration.invalidatesActivityRings { await store.captureRingObservation() }
        if registration.scansWorkouts { _ = await store.captureWorkoutObservation() }
        followupNeeded = true
        scheduleForeground()
        BodyDataRefreshScheduler.schedule()
    }

    private func scheduleForeground() {
        guard BodyAppRuntime.isForegroundActive else { return }
        let now = ContinuousClock.now
        if firstWake == nil { firstWake = now }
        let ceiling = firstWake!.advanced(by: BodyHealthObservationPolicy.foregroundMaximumWait)
        let delay = min(BodyHealthObservationPolicy.foregroundDebounce, max(.zero, now.duration(to: ceiling)))
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            self.debounce = nil
            self.firstWake = nil
            await self.repairOnActivation()
        }
    }

    func enteredBackground() {
        debounce?.cancel()
        debounce = nil
        firstWake = nil
        foregroundWork?.cancel()
    }

    func refreshDidFinish() {
        if followupNeeded, !repairing { scheduleForeground() }
    }

    func repairOnActivation() async {
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("admission foreground=\(BodyAppRuntime.isForegroundActive) repairing=\(repairing) busy=\(store.isRefreshing)")
        #endif
        guard BodyAppRuntime.isForegroundActive, !repairing else { return }
        repairing = true
        await configure()
        guard !store.isRefreshing, BodyAppRuntime.isForegroundActive else {
            repairing = false
            followupNeeded = true
            return
        }
        followupNeeded = false
        defer {
            repairing = false
            if followupNeeded { scheduleForeground() }
        }
        let durable = await ledger.flush()
        let work = await pending(history: true)
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("admission ledgerDurable=\(durable) pending=[\(BodyObserverRefreshDiagnostics.pending(await ledger.snapshot()))] rings=\(store.needsObservedRingRepair)")
        #endif
        _ = durable // The common repair entry rechecks durability after admission.
        if !work.isEmpty || store.needsObservedRingRepair {
            store.invalidateObservedHealthChanges()
            let operation = Task { await store.repairObservedMetrics(work, ledger: ledger) }
            foregroundWork = operation
            _ = await operation.value
            foregroundWork = nil
        }
        let remaining = await pending(history: true)
        store.observedRepairDidSettle(pending: !remaining.isEmpty || store.needsObservedRingRepair)
        store.scheduleWorkoutJournalIfNeeded()
        #if DEBUG
        let notificationStart = ContinuousClock.now
        #endif
        await store.evaluateNewNotifications()
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("activation notifications duration=\(BodyObserverRefreshDiagnostics.elapsed(since: notificationStart))")
        #endif
    }

    func runBackground(lease: BodyBackgroundLease) async -> Bool {
        await configure()
        guard lease.isValid, !BodyAppRuntime.isForegroundActive else { return false }
        _ = await ledger.flush()
        var work = await pending(history: false)
        // A fallback is a revalidation opportunity even when no observer fired.
        if work.isEmpty {
            _ = await ledger.mark(Set(registrations.flatMap(\.metrics).filter { store.observedMetricNeedsValidation($0) }), context: context, reason: "backgroundRevalidation")
            work = await pending(history: false)
        }
        return await lease.run {
            await store.scanObservedWorkouts(lease: lease, scanOnly: true)
            guard lease.isValid else { return false }
            let changed = await store.repairObservedMetrics(work, ledger: ledger, background: lease)
            // Metadata is sufficient for workout delivery; do not make the alert
            // wait for enriched month/detail repair to consume the lease.
            if lease.isValid { await store.evaluateNewNotifications(lease: lease, includesStress: false) }
            if lease.isValid { await store.scanObservedWorkouts(lease: lease, scanOnly: false) }
            if lease.isValid { await store.evaluateNewNotifications(lease: lease) }
            return changed
        }
    }

    private func pending(history: Bool) async -> [(HealthMetricKind, BodyHealthDirtyWorkStore.Receipt)] {
        let snapshot = await ledger.snapshot()
        // Old pending generations precede newer bursts; sleep leads within a
        // generation. Completed current leaves drop out of later BG passes.
        let entries = snapshot.entries.filter { $0.value.currentPending || (history && $0.value.historyPending) }
        var result: [(HealthMetricKind, BodyHealthDirtyWorkStore.Receipt)] = []
        for (key, entry) in entries.sorted(by: {
            if $0.value.generation != $1.value.generation { return $0.value.generation < $1.value.generation }
            if $0.key == "sleep" { return true }
            if $1.key == "sleep" { return false }
            return $0.key < $1.key
        }) {
            guard let kind = HealthMetricKind(rawValue: key),
                  let context = BodyHealthObserverContext(signature: entry.context) else { continue }
            result.append((kind, .init(resetID: snapshot.resetID, domain: key,
                                      generation: entry.generation, context: context)))
        }
        return result
    }
}
