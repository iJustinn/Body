import CoreMotion
import SpriteKit
import SwiftUI
import UIKit

/// Physics toy showing a workout's energy as bouncing food emojis.
/// Card chrome is owned by the caller; this view is the content only.
struct EnergyEquivalentCardContent: View {
    let emojis: [String]
    let hapticsEnabled: Bool

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
            .font(.system(size: 30))
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

    private static let glyphRadius: CGFloat = 20
    private static let hapticImpulseThreshold: CGFloat = 1.5
    private static let hapticImpulseCap: CGFloat = 25
    private static let hapticMinimumInterval: TimeInterval = 0.08

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
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
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
    }

    func updateEmojis(_ emojis: [String]) {
        guard emojis != currentEmojis else { return }
        currentEmojis = emojis
        removeAllChildren()
        rebuildWalls()

        for (index, emoji) in emojis.enumerated() {
            let node = SKLabelNode(text: emoji)
            node.fontSize = 34
            node.verticalAlignmentMode = .center
            node.horizontalAlignmentMode = .center
            node.position = spawnPosition(index: index, count: emojis.count)
            node.alpha = 0

            let body = SKPhysicsBody(circleOfRadius: Self.glyphRadius)
            body.restitution = 0.4
            body.linearDamping = 0.35
            body.angularDamping = 0.6
            body.allowsRotation = false
            body.categoryBitMask = Category.emoji
            body.collisionBitMask = Category.emoji | Category.wall
            body.contactTestBitMask = Category.emoji | Category.wall
            node.physicsBody = body

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
            let gravity = CGVector(dx: motion.gravity.x * 9.8, dy: motion.gravity.y * 9.8)
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
        let columns = max(1, Int((size.width / (Self.glyphRadius * 2.4)).rounded(.down)))
        let column = index % columns
        let row = index / columns
        let spacing = size.width / CGFloat(columns)
        let x = spacing * (CGFloat(column) + 0.5)
        let y = size.height - Self.glyphRadius - CGFloat(row) * Self.glyphRadius * 2.2
        return CGPoint(x: x, y: max(Self.glyphRadius, y))
    }
}
