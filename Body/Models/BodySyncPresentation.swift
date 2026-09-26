import Foundation

/// Presentation only. Explicit monotonic time makes dwell and settlement testable
/// without sleeping, and never holds the store's execution slot open.
struct BodySyncPresentation: Hashable {
    enum Phase: Hashable { case hidden, syncing, updated, partial }
    enum Calculation: String, CaseIterable, Sendable { case readiness, stress, trainingLoad, bodyRadar }
    enum Stage: Hashable, Sendable {
        case authorizing, fetching, syncing, updatingHealth, updatingRings
        case updating(HealthMetricKind)
        case computing(Calculation)
        case writingEffort, finishing
    }

    private(set) var sessionID: UUID?
    private(set) var passID: UUID?
    private(set) var phase: Phase = .hidden
    private(set) var pending: Set<UUID> = []
    private(set) var stage: Stage = .fetching
    private(set) var displayedStage: Stage = .fetching
    private(set) var didPublish = false
    private(set) var hadFailure = false
    private(set) var completedAt: Date?
    /// Whether this session's badge is on screen. Automatic work stays hidden for
    /// `revealDelay`, so a quick read never flashes the badge.
    private(set) var isRevealed = false
    private var revealAt: TimeInterval?
    private var stageChangedAt: TimeInterval = 0
    private var settleAt: TimeInterval?
    private var dismissAt: TimeInterval?

    static let dwell: TimeInterval = 0.5
    static let settleDelay: TimeInterval = 0.6
    static let confirmationDuration: TimeInterval = 1.8
    static let revealDelay: TimeInterval = 0.5

    var nextDeadline: TimeInterval? {
        if let dismissAt { return dismissAt }
        let dwellAt = phase == .syncing && stage != displayedStage ? stageChangedAt + Self.dwell : nil
        // Only while work runs: a session that is only settling ends hidden instead.
        let revealDue = !isRevealed && hasRunningPass ? revealAt : nil
        return [dwellAt, settleAt, revealDue].compactMap { $0 }.min()
    }

    /// Only a running pass reveals. A queued follow-up alone keeps the session
    /// open, but never brings a hidden one on screen.
    private var hasRunningPass: Bool { phase == .syncing && passID != nil }

    mutating func begin(now: TimeInterval) {
        advance(now: now)
        if phase != .syncing {
            sessionID = UUID()
            phase = .syncing
            didPublish = false
            hadFailure = false
            completedAt = nil
            isRevealed = false
            revealAt = now + Self.revealDelay
            stage = .fetching
            displayedStage = .fetching
            stageChangedAt = now
        }
        passID = UUID()
        settleAt = nil
        dismissAt = nil
        revealIfDue(now: now)
    }

    /// A refresh the user asked for shows at once instead of after `revealDelay`.
    mutating func reveal() {
        guard phase == .syncing else { return }
        isRevealed = true
    }

    mutating func enqueue(_ token: UUID, replacing previous: UUID? = nil, now: TimeInterval) {
        pending.insert(token)
        if let previous { pending.remove(previous) }
        reconcile(now: now)
    }

    mutating func release(_ token: UUID, now: TimeInterval) {
        pending.remove(token)
        reconcile(now: now)
    }

    mutating func report(_ next: Stage, owner: UUID, now: TimeInterval) {
        guard phase == .syncing, passID == owner else { return }
        stage = next == .fetching && stage != .fetching && stage != .authorizing ? .updatingHealth : next
        advance(now: now)
    }

    mutating func record(published: Bool = false, failed: Bool = false, owner: UUID) {
        guard phase == .syncing, passID == owner else { return }
        didPublish = didPublish || published
        hadFailure = hadFailure || failed
    }

    mutating func finish(now: TimeInterval) {
        passID = nil
        reconcile(now: now)
    }

    mutating func invalidate() {
        self = Self()
    }

    private mutating func reconcile(now: TimeInterval) {
        guard phase == .syncing else { return }
        if passID == nil, !pending.isEmpty {
            stage = .syncing
        }
        if passID == nil, pending.isEmpty {
            if settleAt == nil { settleAt = now + Self.settleDelay }
        } else {
            settleAt = nil
        }
        advance(now: now)
    }

    mutating func advance(now: TimeInterval, date: Date = .now) {
        if phase == .syncing {
            revealIfDue(now: now)
            if stage != displayedStage, now >= stageChangedAt + Self.dwell {
                displayedStage = stage
                stageChangedAt = now
            }
            if let settleAt, now >= settleAt, passID == nil, pending.isEmpty {
                // A session that never showed ends silently, with no confirmation.
                phase = didPublish && isRevealed ? (hadFailure ? .partial : .updated) : .hidden
                completedAt = phase == .hidden ? nil : date
                self.settleAt = nil
                dismissAt = phase == .hidden ? nil : now + Self.confirmationDuration
            }
        } else if let dismissAt, now >= dismissAt {
            phase = .hidden
            self.dismissAt = nil
        }
    }

    private mutating func revealIfDue(now: TimeInterval) {
        guard !isRevealed, hasRunningPass, let revealAt, now >= revealAt else { return }
        isRevealed = true
    }
}
