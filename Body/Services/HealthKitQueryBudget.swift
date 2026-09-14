//
//  HealthKitQueryBudget.swift
//  Body
//

import Foundation

/// Which HealthKit concurrency budget a query spends
/// (RefreshOptimizationPlan-02 P0-C).
///
/// `healthd` is a single XPC service, so past roughly a dozen concurrent
/// queries the app only buys queueing. The budget is split in two rather than
/// pooled globally because the pools have incompatible failure modes: the
/// refresh is bounded by the 120 s deadline, while the off-refresh walks (the
/// ten-year ring backfill, the Stress history walk, the workout-record scan)
/// are explicitly allowed to run for minutes or hang outright. A single budget
/// would let one of those stall the visible dashboard leaves; two budgets mean
/// a wedged background walk can never hold a permit the refresh is waiting for.
enum HealthKitQueryPool: Sendable {
    /// Everything on the refresh path: the dashboard summary/trend leaves, the
    /// per-workout effort/cadence/distance pools, batched heart rate and
    /// VO₂max, sleep, training load.
    case interactive
    /// The long walks kept deliberately off the refresh path: ring backfill and
    /// ring pagination, the Stress history walk and its input load, the
    /// workout-record baseline scan, lazy month loads, intraday day samples.
    case background
    case appRefresh

    /// Pool for the current task. Queries default to `.interactive`; the
    /// background entry points bind `.background` around their whole task
    /// (`withBackgroundQueryPool`), so every query they reach — including ones
    /// in fetch functions the refresh path shares — lands in the smaller
    /// budget. A task-local rather than a parameter because the background
    /// walks reuse the same shared fetch functions as the refresh (e.g. the
    /// lazy month load and the refresh both run `refresh(monthKeys:)`), so a
    /// parameter would have to be threaded through most of the fetch layer.
    /// Task locals propagate into child tasks and task groups, which is exactly
    /// the fan-out shape these walks use; only `Task.detached` drops the
    /// binding, and the detached tasks in the fetch layer are pure compute.
    @TaskLocal static var current: HealthKitQueryPool = .interactive

    var semaphore: HealthKitQuerySemaphore {
        switch self {
        case .interactive: return HealthKitQuerySemaphore.interactive
        case .background: return HealthKitQuerySemaphore.background
        case .appRefresh: return HealthKitQuerySemaphore.appRefresh
        }
    }

    var profileName: String {
        switch self {
        case .interactive: return "interactive"
        case .background: return "background"
        case .appRefresh: return "appRefresh"
        }
    }
}

/// Runs `operation` with every HealthKit query it reaches charged to the
/// background budget instead of the interactive one.
///
/// `nonisolated(nonsending)` keeps `operation` running on the caller's actor:
/// several of these bodies capture non-`Sendable` HealthKit closures, and the
/// ring query in particular is unstructured precisely to stay on the engine.
nonisolated(nonsending)
func withBackgroundQueryPool<Value>(
    _ operation: nonisolated(nonsending) () async throws -> Value
) async rethrows -> Value {
    try await HealthKitQueryPool.$current.withValue(
        BodyBackgroundLease.current == nil ? .background : .appRefresh,
        operation: operation
    )
}

/// Permit pool bounding how many HealthKit queries one budget keeps in
/// flight at once.
///
/// Cancellation removes ordinary queued waiters without borrowing a permit.
/// An already admitted caller still owns its permit and releases it in defer.
///
/// `@unchecked Sendable` is sound because every access is lock-guarded, and the
/// lock is never held across a continuation resume.
final class HealthKitQuerySemaphore: @unchecked Sendable {
    /// ~10 in flight: enough to keep `healthd` saturated without paying the
    /// queueing and IPC overhead the 100+ concurrent queries of the unbounded
    /// refresh bought.
    static let interactive = HealthKitQuerySemaphore(limit: 10, name: "interactive")
    /// Small on purpose: these walks are latency-insensitive, and their whole
    /// job is to stay out of the refresh's way.
    static let background = HealthKitQuerySemaphore(limit: 4, name: "background")

    static let appRefresh = HealthKitQuerySemaphore(limit: 2, name: "appRefresh")

    private let limit: Int
    private let name: String
    private let lock = NSLock()
    private var inFlight = 0
    private final class Waiter: @unchecked Sendable {
        var continuation: UnsafeContinuation<Bool, Never>?
        var cancelled = false
    }
    private var waiters: [Waiter] = []

    init(limit: Int, name: String) {
        self.limit = limit
        self.name = name
    }

    /// Takes a permit, waiting in FIFO order when the budget is full. Every
    /// caller must pair this with exactly one `release()`, in a `defer`.
    func acquire() async {
        _ = await enqueue(Waiter())
    }

    private func enqueue(_ waiter: Waiter) async -> Bool {
        await withUnsafeContinuation { continuation in
            lock.lock()
            if waiter.cancelled {
                lock.unlock()
                continuation.resume(returning: false)
            } else if inFlight < limit {
                inFlight += 1
                let depth = inFlight
                lock.unlock()
                BodyRefreshProfile.shared.notePoolDepth(name, depth: depth)
                continuation.resume(returning: true)
            } else {
                waiter.continuation = continuation
                waiters.append(waiter)
                lock.unlock()
            }
        }
    }

    private func cancel(_ waiter: Waiter) {
        lock.lock()
        waiter.cancelled = true
        let continuation = waiter.continuation
        waiter.continuation = nil
        waiters.removeAll { $0 === waiter }
        lock.unlock()
        continuation?.resume(returning: false)
    }

    func acquireForCurrentTask() async -> Bool {
        if let lease = BodyBackgroundLease.current {
            // A lease can expire independently of task cancellation.
            while lease.isValid && !Task.isCancelled {
                if tryAcquire() { return true }
                do { try await Task.sleep(for: .milliseconds(10)) }
                catch { return false }
            }
            return false
        }
        guard !Task.isCancelled else { return false }
        let waiter = Waiter()
        return await withTaskCancellationHandler {
            await enqueue(waiter)
        } onCancel: {
            self.cancel(waiter)
        }
    }

    func tryAcquire() -> Bool {
        lock.lock()
        guard inFlight < limit else { lock.unlock(); return false }
        inFlight += 1
        let depth = inFlight
        lock.unlock()
        BodyRefreshProfile.shared.notePoolDepth(name, depth: depth)
        return true
    }

    /// Returns a permit, handing it straight to the oldest waiter if there is
    /// one (so `inFlight` stays at the ceiling rather than dipping and racing).
    func release() {
        lock.lock()
        guard !waiters.isEmpty else {
            inFlight -= 1
            lock.unlock()
            return
        }
        let waiter = waiters.removeFirst()
        let continuation = waiter.continuation
        waiter.continuation = nil
        lock.unlock()
        continuation?.resume(returning: true)
    }
}
