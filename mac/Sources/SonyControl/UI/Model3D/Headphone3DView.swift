import AppKit
import SceneKit
import SwiftUI

/// The interactive 3D headphones: floats and sways on its own, tilts toward the pointer,
/// spins when dragged (with inertia), does a full turn on double-click, and pinch-zooms.
struct Headphone3DView: NSViewRepresentable {
    let level: Int
    let charging: Bool
    let mode: NoiseMode?
    let colorway: Colorway

    func makeNSView(context: Context) -> HeadphoneSCNView {
        let view = HeadphoneSCNView(colorway: colorway)
        view.model.setBattery(level: level, charging: charging)
        context.coordinator.lastMode = mode
        return view
    }

    func updateNSView(_ view: HeadphoneSCNView, context: Context) {
        view.model.setColorway(colorway)
        view.model.setBattery(level: level, charging: charging)
        if mode != context.coordinator.lastMode {
            if context.coordinator.lastMode != nil { view.motion.nod() }
            context.coordinator.lastMode = mode
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastMode: NoiseMode?
    }
}

/// Pose state shared between mouse handling (main thread) and the render loop.
final class HeadphoneMotion {
    var yaw: Float = 0.35
    var pitch: Float = 0.2
    var yawVelocity: Float = 0
    var pitchVelocity: Float = 0
    var dragging = false
    /// Pointer position over the view, -1…1 on each axis (0 when outside).
    var hover = SIMD2<Float>(0, 0)
    /// Extra yaw added by double-click spins; the spring rotates the model towards it.
    var spinOffset: Float = 0
    var zoom: Float = 1

    func nod() { pitchVelocity += 0.045 }
    func spin() { spinOffset += 2 * .pi }
}

final class HeadphoneSCNView: SCNView {
    let model: HeadphoneScene
    let motion = HeadphoneMotion()
    private let animator: HeadphoneAnimator
    private var lastDrag: NSPoint?

    init(colorway: Colorway) {
        model = HeadphoneScene(colorway: colorway)
        animator = HeadphoneAnimator(model: model, motion: motion)
        super.init(frame: .zero, options: nil)
        scene = model.scene
        pointOfView = model.camera
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        rendersContinuously = true
        preferredFramesPerSecond = 60
        delegate = animator
        isPlaying = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        motion.hover = SIMD2(Float(p.x / max(bounds.width, 1)) * 2 - 1, Float(p.y / max(bounds.height, 1)) * 2 - 1)
    }

    override func mouseExited(with event: NSEvent) { motion.hover = .zero }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { motion.spin() }
        lastDrag = event.locationInWindow
        motion.dragging = true
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDrag else { return }
        let p = event.locationInWindow
        let dx = Float(p.x - last.x), dy = Float(p.y - last.y)
        lastDrag = p
        motion.yaw += dx * 0.012
        motion.pitch = min(max(motion.pitch - dy * 0.008, -0.6), 0.9)
        motion.yawVelocity = dx * 0.012
        motion.pitchVelocity = -dy * 0.008
    }

    override func mouseUp(with event: NSEvent) {
        motion.dragging = false
        lastDrag = nil
        NSCursor.pop()
    }

    override func magnify(with event: NSEvent) {
        motion.zoom = min(max(motion.zoom * Float(1 + event.magnification), 0.7), 1.6)
    }

    override func scrollWheel(with event: NSEvent) {
        // Two-finger horizontal swipe spins too.
        motion.yawVelocity += Float(event.scrollingDeltaX) * 0.0015
    }
}

/// Runs on SceneKit's render thread: idle float/sway, hover tilt, and spring-back with inertia.
final class HeadphoneAnimator: NSObject, SCNSceneRendererDelegate {
    private let model: HeadphoneScene
    private let motion: HeadphoneMotion
    private var lastTime: TimeInterval?

    init(model: HeadphoneScene, motion: HeadphoneMotion) {
        self.model = model
        self.motion = motion
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = Float(min(time - (lastTime ?? time), 1.0 / 20))
        lastTime = time
        let t = Float(time)
        let m = motion
        // Frame-rate independent factors (tuned at 60 fps).
        let k = dt * 60

        if !m.dragging {
            // Idle: slow sway plus a lean towards the pointer.
            let targetYaw = 0.35 + 0.45 * sin(t * 0.35) + m.hover.x * 0.4 + m.spinOffset
            let targetPitch = 0.2 + 0.06 * sin(t * 0.5) - m.hover.y * 0.22
            m.yawVelocity = (m.yawVelocity + (targetYaw - m.yaw) * 0.012 * k) * pow(0.93, k)
            m.pitchVelocity = (m.pitchVelocity + (targetPitch - m.pitch) * 0.02 * k) * pow(0.9, k)
            m.yaw += m.yawVelocity * k
            m.pitch += m.pitchVelocity * k
        }

        let roll = 0.05 * sin(t * 0.3)
        let bob = 0.35 * sin(t * 0.9)
        model.pivot.eulerAngles = SCNVector3(CGFloat(m.pitch), CGFloat(m.yaw), CGFloat(roll))
        model.pivot.position.y = CGFloat(bob)
        model.camera.position.z = CGFloat(56 / m.zoom)
        model.tick(time: time)
    }
}
