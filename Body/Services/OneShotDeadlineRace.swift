//
//  OneShotDeadlineRace.swift
//  Body
//

import Foundation

/// Races an async operation against a deadline and reports whichever landed
/// first, WITHOUT awaiting the loser.
///
/// A task group can't do this: its implicit await on the timed-out child would
/// still block on a HealthKit query that never resumes, which is exactly the
/// hang the deadline exists to prevent. Here the operation runs unstructured and
/// the caller is resumed by whichever racer reaches the one-shot continuation
/// first; on `.timedOut` the operation is simply abandoned, and the caller
/// decides whether to cancel it.
enum OneShotDeadlineRace {
    enum Outcome<Value: Sendable>: Sendable {
        case finished(Value)
        case timedOut
    }

    /// Runs `work`, returning `.timedOut` if `deadline` elapses first. The
    /// sleeper is cancelled as soon as `work` returns, so a short operation
    /// leaves nothing parked on the clock.
    static func run<Value: Sendable>(
        deadline: Duration,
        clock: ContinuousClock = .init(),
        _ work: @escaping @Sendable () async -> Value
    ) async -> Outcome<Value> {
        let box = OneShotOutcomeBox<Value>()
        return await withCheckedContinuation { continuation in
            box.arm(continuation)
            let sleeper = Task {
                try? await Task.sleep(for: deadline, clock: clock)
                // `try?` swallows the cancellation error too, and the winner
                // cancels this task — so an early wake must not report a
                // timeout that never happened.
                guard !Task.isCancelled else { return }
                box.finish(.timedOut)
            }
            Task {
                let value = await work()
                sleeper.cancel()
                box.finish(.finished(value))
            }
        }
    }
}

/// One-shot continuation shared by the two racers. Both call `finish` from
/// different tasks, so every access takes the lock, and the lock is never held
/// across the resume. `@unchecked Sendable` is sound because the continuation is
/// only ever touched under the lock.
private final class OneShotOutcomeBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<OneShotDeadlineRace.Outcome<Value>, Never>?

    /// Called synchronously inside `withCheckedContinuation`, before either
    /// racer exists.
    func arm(_ continuation: CheckedContinuation<OneShotDeadlineRace.Outcome<Value>, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    /// Resumes the caller. The loser's call is a no-op.
    func finish(_ outcome: OneShotDeadlineRace.Outcome<Value>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: outcome)
    }
}
