import CoreMotion
import SpriteKit
import SwiftUI
import UIKit

/// Physics toy showing a workout's energy as bouncing food emojis.
/// Card chrome is owned by the caller; this view is the content only.
struct EnergyEquivalentCardContent: View {
    let emojis: [String]
    let hapticsEnabled: Bool
    /// User-set emoji scale (0.7…1.3, 1 = default size).
    var emojiScale: CGFloat = 1

    private static let physicsHeight: CGFloat = 140

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = EnergyEquivalentScene()
    // No scroll-visibility callback fires outside a ScrollView, so default to visible.
    @State private var isScrollVisible = true

    var body: some View {
        Group {
            if reduceMotion {
                staticRow
            } else {
                physicsView
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("equivalent.accessibility.emojis \(emojis.count) \(emojis.joined(separator: " "))"))
    }

    private var staticRow: some View {
        Text(emojis.joined(separator: " "))
            .font(.system(size: 36 * emojiScale))
            .lineLimit(2)
            .minimumScaleFactor(0.4)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var physicsView: some View {
        GeometryReader { proxy in
            SpriteView(scene: scene, options: [.allowsTransparency])
                .onAppear {
                    scene.size = CGSize(width: proxy.size.width, height: Self.physicsHeight)
                    scene.hapticsEnabled = hapticsEnabled
                    scene.emojiScale = emojiScale
                    scene.updateEmojis(emojis)
                    updateRunState()
                }
                .onChange(of: proxy.size.width) { _, width in
                    scene.size = CGSize(width: width, height: Self.physicsHeight)
                }
        }
        .frame(height: Self.physicsHeight)
        .onScrollVisibilityChange(threshold: 0.2) { visible in
            isScrollVisible = visible
            updateRunState()
        }
        .onChange(of: scenePhase) { _, _ in updateRunState() }
        .onChange(of: emojis) { _, newValue in scene.updateEmojis(newValue) }
        .onChange(of: hapticsEnabled) { _, newValue in scene.hapticsEnabled = newValue }
        .onChange(of: emojiScale) { _, newValue in
            scene.emojiScale = newValue
            scene.rebuildEmojis()
        }
        .onDisappear { scene.stop() }
    }

    private func updateRunState() {
        if isScrollVisible, scenePhase == .active {
            scene.start()
        } else {
            scene.stop()
        }
    }
}

final class EnergyEquivalentScene: SKScene, SKPhysicsContactDelegate {
    private enum Category {
        static let emoji: UInt32 = 1 << 0
        static let wall: UInt32 = 1 << 1
    }

    private static let baseGlyphRadius: CGFloat = 24
    private static let baseFontSize: CGFloat = 42

    /// User-set emoji scale; `rebuildEmojis()` applies a change to live nodes.
    var emojiScale: CGFloat = 1

    private var glyphRadius: CGFloat { Self.baseGlyphRadius * emojiScale }
    private static let hapticImpulseThreshold: CGFloat = 1.5
    private static let hapticImpulseCap: CGFloat = 25
    private static let hapticMinimumInterval: TimeInterval = 0.08
    /// Above real-world 9.8 so the toy feels lively at card scale.
    private static let gravityScale: Double = 15
    /// Below this delta in raw g-components, a new motion sample is noise, not a
    /// real tilt; ignoring it lets the scene actually go quiet while held still.
    private static let gravityDeadband: Double = 0.04
    private static let settleLinearSpeedThreshold: CGFloat = 6
    private static let settleRimSpeedThreshold: CGFloat = 6
    /// userAcceleration magnitude (g) above which the device counts as moving;
    /// generous enough that hand tremor while "holding still" doesn't count.
    private static let stillAccelerationThreshold: Double = 0.06
    /// rotationRate magnitude (rad/s) above which the device counts as moving.
    private static let stillRotationThreshold: Double = 0.25
    /// How long the device must be still before bodies are eligible to settle.
    private static let settleDelay: TimeInterval = 0.5
    /// Failsafe: force settle after this long still, even if a body is still
    /// creeping (e.g. resting against another body under residual damping).
    private static let settleFailsafeDelay: TimeInterval = 2.0

    var hapticsEnabled = true

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private let gravityLock = NSLock()
    private var pendingGravity: CGVector?
    /// Unscaled g-components paired with `pendingGravity`, applied to
    /// `lastAppliedGravityG` when the vector is actually assigned in `update(_:)`.
    private var pendingGravityG: (x: Double, y: Double)?
    /// Unscaled g-components of the last gravity actually applied to the world;
    /// the deadband compares new samples against this, not the scaled vector.
    private var lastAppliedGravityG: (x: Double, y: Double)?
    private var lastHapticTime: TimeInterval = 0
    private var currentEmojis: [String] = []
    private var isRunning = false
    /// CACurrentMediaTime() of the last device-motion sample that counted as
    /// moving; stamped by the motion queue, read by the scene under `gravityLock`.
    private var lastDeviceMovementTime: TimeInterval?
    private var isSettled = false

    override init() {
        super.init(size: CGSize(width: 320, height: 140))
        scaleMode = .resizeFill
        backgroundColor = .clear
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInitiated
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = CGVector(dx: 0, dy: -Self.gravityScale)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        rebuildWalls()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuildWalls()
    }

    override func update(_ currentTime: TimeInterval) {
        // Device-motion updates arrive on a background queue; applying the vector here
        // keeps every physicsWorld mutation on the scene's own thread.
        gravityLock.lock()
        let gravity = pendingGravity
        if let gravityG = pendingGravityG {
            // The motion callback reads this baseline under the same lock.
            lastAppliedGravityG = gravityG
        }
        pendingGravity = nil
        pendingGravityG = nil
        gravityLock.unlock()
        if let gravity {
            physicsWorld.gravity = gravity
        }

        gravityLock.lock()
        let movementTime = lastDeviceMovementTime
        gravityLock.unlock()
        // Use CACurrentMediaTime() (not `currentTime`) so this stays comparable
        // with the timestamp the motion queue stamps under the same lock.
        let deviceStill = movementTime.map { CACurrentMediaTime() - $0 >= Self.settleDelay } ?? true

        if !deviceStill {
            physicsWorld.speed = 1
            isSettled = false
        } else if isSettled {
            // Settled bodies get no boost, and the world itself is paused, so
            // there is nothing left to do until the device moves again.
            return
        }

        // Uniform gravity accelerates every body identically, so per-food feel
        // needs an extra push: heavier (higher-kcal) foods get a boost along the
        // current gravity vector, lighter ones ride gravity alone (their higher
        // damping already makes them the slowest — see `updateEmojis`).
        var allSlow = true
        if !deviceStill {
            let currentGravity = physicsWorld.gravity
            for node in children {
                guard let label = node as? SKLabelNode, let body = label.physicsBody, let emoji = label.text else { continue }
                let linearSpeed = hypot(body.velocity.dx, body.velocity.dy)
                let rimSpeed = abs(body.angularVelocity) * glyphRadius
                if linearSpeed >= Self.settleLinearSpeedThreshold || rimSpeed >= Self.settleRimSpeedThreshold {
                    allSlow = false
                }
                let boost = Self.weight(of: emoji) * 0.8
                guard boost > 0 else { continue }
                body.applyForce(CGVector(
                    dx: currentGravity.dx * body.mass * boost,
                    dy: currentGravity.dy * body.mass * boost
                ))
            }
        } else {
            // Device is still: skip the boost and let existing damping decay
            // the bodies naturally instead of fighting to keep them moving.
            for node in children {
                guard let label = node as? SKLabelNode, let body = label.physicsBody else { continue }
                let linearSpeed = hypot(body.velocity.dx, body.velocity.dy)
                let rimSpeed = abs(body.angularVelocity) * glyphRadius
                if linearSpeed >= Self.settleLinearSpeedThreshold || rimSpeed >= Self.settleRimSpeedThreshold {
                    allSlow = false
                }
            }
        }

        guard deviceStill else { return }

        let stillDuration = movementTime.map { CACurrentMediaTime() - $0 } ?? .greatestFiniteMagnitude
        if allSlow || stillDuration >= Self.settleFailsafeDelay {
            isSettled = true
            for node in children {
                guard let label = node as? SKLabelNode, let body = label.physicsBody else { continue }
                body.velocity = .zero
                body.angularVelocity = 0
            }
            physicsWorld.speed = 0
        }
    }

    /// 0…1 by the food's kcal in the fixed table (unknown emoji read as
    /// mid-weight), driving both the gravity boost and the damping spread.
    private static func weight(of emoji: String) -> CGFloat {
        if emoji == EnergyEquivalent.iceCube.emoji { return 0.1 }
        guard let food = EnergyEquivalent.foods.first(where: { $0.emoji == emoji }),
              let heaviest = EnergyEquivalent.foods.first?.kilocalories, heaviest > 0 else {
            return 0.5
        }
        return CGFloat(food.kilocalories / heaviest)
    }

    /// Respawns the current emoji set — used when the size setting changes.
    func rebuildEmojis() {
        let emojis = currentEmojis
        currentEmojis = []
        updateEmojis(emojis)
    }

    func updateEmojis(_ emojis: [String]) {
        guard emojis != currentEmojis else { return }
        currentEmojis = emojis
        removeAllChildren()
        rebuildWalls()
        // Freshly spawned bodies carry a spawn spin and must not be frozen.
        isSettled = false
        physicsWorld.speed = 1

        for (index, emoji) in emojis.enumerated() {
            let node = SKLabelNode(text: emoji)
            node.fontSize = Self.baseFontSize * emojiScale
            node.verticalAlignmentMode = .center
            node.horizontalAlignmentMode = .center
            node.position = spawnPosition(index: index, count: emojis.count)
            node.alpha = 0

            let body = SKPhysicsBody(circleOfRadius: glyphRadius)
            body.restitution = 0.4
            // Heavier foods coast, light ones stop quickly — this damping spread
            // (with the per-food gravity boost applied in `update`) is what makes
            // each food accelerate at its own pace under the same tilt.
            body.linearDamping = 0.1 + (1 - Self.weight(of: emoji)) * 0.35
            body.angularDamping = 0.4
            body.allowsRotation = true
            body.categoryBitMask = Category.emoji
            body.collisionBitMask = Category.emoji | Category.wall
            body.contactTestBitMask = Category.emoji | Category.wall
            node.physicsBody = body
            // A gentle alternating starting spin so the glyphs tumble instead of
            // sliding upright; collisions take over from there.
            body.angularVelocity = index.isMultiple(of: 2) ? 1.2 : -1.2

            addChild(node)
            node.run(.sequence([
                .wait(forDuration: Double(index) * 0.06),
                .fadeIn(withDuration: 0.25)
            ]))
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        physicsWorld.speed = 1
        isSettled = false
        gravityLock.lock()
        // So the scene runs lively on (re)appear even before motion arrives.
        lastDeviceMovementTime = CACurrentMediaTime()
        gravityLock.unlock()
        if hapticsEnabled {
            feedback.prepare()
        }
        // Raw device motion needs no usage description. Portrait is assumed: device
        // gravity axes map straight onto scene axes, so landscape simply tilts oddly.
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let g = (x: motion.gravity.x, y: motion.gravity.y)
            let gravity = CGVector(dx: g.x * Self.gravityScale, dy: g.y * Self.gravityScale)
            let a = motion.userAcceleration
            let accelMagnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let r = motion.rotationRate
            let rotationMagnitude = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            let isMoving = accelMagnitude > Self.stillAccelerationThreshold
                || rotationMagnitude > Self.stillRotationThreshold
            gravityLock.lock()
            if isMoving {
                lastDeviceMovementTime = CACurrentMediaTime()
            }
            // Held still, the raw g-components jitter within noise; only enqueue a
            // sample that represents a real tilt, so the scene can actually go quiet.
            // While the device is still, gravity deltas are noise and must not
            // reach the physics world at all.
            let hasBaseline = lastAppliedGravityG != nil
            if isMoving || !hasBaseline {
                let delta = lastAppliedGravityG.map { hypot(g.x - $0.x, g.y - $0.y) }
                if delta == nil || delta! > Self.gravityDeadband {
                    pendingGravity = gravity
                    pendingGravityG = g
                }
            }
            gravityLock.unlock()
        }
    }

    func stop() {
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        isPaused = true
        gravityLock.lock()
        pendingGravity = nil
        pendingGravityG = nil
        // Reset the baseline so the first sample after resume is always accepted,
        // instead of being compared against stale pre-background gravity.
        lastAppliedGravityG = nil
        gravityLock.unlock()
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard hapticsEnabled else { return }
        let impulse = contact.collisionImpulse
        guard impulse >= Self.hapticImpulseThreshold else { return }
        let now = CACurrentMediaTime()
        guard now - lastHapticTime >= Self.hapticMinimumInterval else { return }
        lastHapticTime = now
        let intensity = min(1, impulse / Self.hapticImpulseCap)
        DispatchQueue.main.async { [feedback] in
            feedback.impactOccurred(intensity: intensity)
        }
    }

    private func rebuildWalls() {
        guard size.width > 0, size.height > 0 else { return }
        let body = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size))
        body.categoryBitMask = Category.wall
        body.contactTestBitMask = Category.emoji
        physicsBody = body
    }

    private func spawnPosition(index: Int, count: Int) -> CGPoint {
        let columns = max(1, Int((size.width / (glyphRadius * 2.4)).rounded(.down)))
        let column = index % columns
        let row = index / columns
        let spacing = size.width / CGFloat(columns)
        let x = spacing * (CGFloat(column) + 0.5)
        let y = size.height - glyphRadius - CGFloat(row) * glyphRadius * 2.2
        return CGPoint(x: x, y: max(glyphRadius, y))
    }
}
