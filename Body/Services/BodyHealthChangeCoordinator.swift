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
    private var quietWork: Task<Void, Never>?
    private var quietAttempts: [BodyHealthDirtyWorkStore.Receipt] = []
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
            await self.store.syncWhenAppBecomesActive()
        }
    }

    func enteredBackground() {
        store.retireBackgroundRefresh()
        quietWork?.cancel()
        debounce?.cancel()
        debounce = nil
        firstWake = nil
        foregroundWork?.cancel()
    }

    func refreshDidFinish() {
        if followupNeeded, !repairing { scheduleForeground() }
        offerQuietRepair()
    }

    /// Metadata only: activation decides current freshness before reading history.
    func prepareActivation() async {
        quietAttempts.removeAll()
        await configure()
        let current = await pending(history: false)
        #if DEBUG
        BodyObserverRefreshDiagnostics.log("activation currentPending=\(current.count) ledger=[\(BodyObserverRefreshDiagnostics.pending(await ledger.snapshot()))]")
        #endif
        store.observedRepairDidSettle(pending: !current.isEmpty || store.needsObservedRingRepair)
    }

    func captureReceipts() async -> [BodyHealthDirtyWorkStore.Receipt] {
        guard await ledger.flush() else { return [] }
        return await pending(history: true).map { $0.1 }
    }

    func acknowledgeCoverage(_ receipts: [BodyHealthDirtyWorkStore.Receipt],
                             kinds: Set<HealthMetricKind>, history: Bool) async {
        for receipt in receipts {
            guard let kind = HealthMetricKind(rawValue: receipt.domain), kinds.contains(kind),
                  !Task.isCancelled, receipt.context == store.currentObserverLedgerContext() else { continue }
            _ = await ledger.acknowledge(receipt, current: true, history: history)
        }
        let current = await pending(history: false)
        store.observedRepairDidSettle(pending: !current.isEmpty || store.needsObservedRingRepair)
    }

    /// Failed generations get one attempt per external opportunity. New
    /// deliveries have new receipts; history alone never creates a visible pass.
    func offerQuietRepair() {
        guard quietWork == nil, store.mayStartQuietMaintenance else { return }
        quietWork = Task { @MainActor [weak self] in
            guard let self else { return }
            // Retirement does not join the read. Keep its store alive through
            // the final ledger/freshness update even if the scene releases it.
            let store = self.store
            defer { self.quietWork = nil }
            while !Task.isCancelled, store.mayStartQuietMaintenance {
                let work = await self.pending(history: true)
                guard let next = work.first(where: { !self.quietAttempts.contains($0.1) }) else { break }
                self.quietAttempts.append(next.1)
                _ = await store.repairObservedMetricsQuietly([next], ledger: self.ledger)
            }
            let current = await self.pending(history: false)
            store.observedRepairDidSettle(pending: !current.isEmpty || store.needsObservedRingRepair)
        }
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
        let work = await pending(history: false)
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
        let remaining = await pending(history: false)
        store.observedRepairDidSettle(pending: !remaining.isEmpty || store.needsObservedRingRepair)
        store.offerQuietMaintenance()
    }

    func runBackground(lease: BodyBackgroundLease) async -> Bool {
        await configure()
        guard lease.isValid, !BodyAppRuntime.isForegroundActive else { return false }
        _ = await ledger.flush()
        let work = await pending(history: false)
        // Periodic reads are opportunistic, not evidence of a historical change.
        // An expired/denied fallback must not leave synthetic foreground repairs.
        let revalidationKinds = work.isEmpty
            ? Set(registrations.flatMap(\.metrics).filter { store.observedMetricNeedsValidation($0) })
                .sorted {
                    if ($0 == .sleep) != ($1 == .sleep) { return $0 == .sleep }
                    return $0.rawValue < $1.rawValue
                }
            : []
        return await lease.run {
            await store.scanObservedWorkouts(lease: lease, scanOnly: true)
            guard lease.isValid else { return false }
            let changed = await store.repairObservedMetrics(work, ledger: ledger, background: lease,
                                                          revalidating: revalidationKinds)
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
            if ($0.key == "sleep") != ($1.key == "sleep") { return $0.key == "sleep" }
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
