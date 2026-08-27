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

    var hapticsEnabled = true

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private let gravityLock = NSLock()
    private var pendingGravity: CGVector?
    private var lastHapticTime: TimeInterval = 0
    private var currentEmojis: [String] = []
    private var isRunning = false

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
        pendingGravity = nil
        gravityLock.unlock()
        if let gravity {
            physicsWorld.gravity = gravity
        }

        // Uniform gravity accelerates every body identically, so per-food feel
        // needs an extra push: heavier (higher-kcal) foods get a boost along the
        // current gravity vector, lighter ones ride gravity alone (their higher
        // damping already makes them the slowest — see `updateEmojis`).
        let currentGravity = physicsWorld.gravity
        for node in children {
            guard let label = node as? SKLabelNode, let body = label.physicsBody, let emoji = label.text else { continue }
            let boost = Self.weight(of: emoji) * 0.8
            guard boost > 0 else { continue }
            body.applyForce(CGVector(
                dx: currentGravity.dx * body.mass * boost,
                dy: currentGravity.dy * body.mass * boost
            ))
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
        if hapticsEnabled {
            feedback.prepare()
        }
        // Raw device motion needs no usage description. Portrait is assumed: device
        // gravity axes map straight onto scene axes, so landscape simply tilts oddly.
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = CGVector(dx: motion.gravity.x * Self.gravityScale, dy: motion.gravity.y * Self.gravityScale)
            gravityLock.lock()
            pendingGravity = gravity
            gravityLock.unlock()
        }
    }

    func stop() {
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        isPaused = true
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
