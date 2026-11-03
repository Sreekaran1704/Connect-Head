import AppKit
import SceneKit

/// Colour options matching the ULT WEAR's finishes.
enum Colorway: String, CaseIterable, Identifiable {
    case forestGray = "Forest Gray", black = "Black", offWhite = "Off White"
    var id: Self { self }

    /// Matte plastic of the housings and headband sides.
    var plastic: NSColor {
        switch self {
        case .forestGray: NSColor(red: 0.30, green: 0.33, blue: 0.315, alpha: 1)
        case .black: NSColor(white: 0.075, alpha: 1)
        case .offWhite: NSColor(red: 0.85, green: 0.83, blue: 0.79, alpha: 1)
        }
    }

    /// Slider pieces at the band ends read a touch lighter on the real thing.
    var slider: NSColor { plastic.blended(withFraction: 0.12, of: .white) ?? plastic }

    /// Protein leather on the headband top and ear pads.
    var leather: NSColor {
        switch self {
        case .forestGray: NSColor(red: 0.28, green: 0.31, blue: 0.295, alpha: 1)
        case .black: NSColor(white: 0.09, alpha: 1)
        case .offWhite: NSColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1)
        }
    }

    var swatch: NSColor { plastic }
}

/// A procedurally built ULT WEAR (units ≈ cm), modelled after the real headphones: a sectioned
/// headband (leather top, plastic sides, sliders), thick stems curving into the back of each cup,
/// rounded-trapezoid cups with a raised outer plate, mic grilles, pads, and the ULT button.
/// A thin inlay along the headband shows the battery level.
final class HeadphoneScene {
    let scene = SCNScene()
    /// Rotated by the animator (yaw/pitch/roll) and bobbed up and down.
    let pivot = SCNNode()
    let camera = SCNNode()

    // Headband geometry (angles in radians, from +X; the left end is at `bandEnd`).
    private let bandRadius: CGFloat = 10
    private let bandStart: CGFloat = 8 * .pi / 180
    private let bandEnd: CGFloat = 172 * .pi / 180
    private let bandHalfThickness: CGFloat = 0.55
    private let bandHalfWidth: CGFloat = 1.95

    // Ear cups.
    private let cupX: CGFloat = 10.45
    private let cupHeight: CGFloat = 10
    private let cupTopWidth: CGFloat = 7.0
    private let cupBottomWidth: CGFloat = 8.3

    private let plastic = SCNMaterial()
    private let sliderPlastic = SCNMaterial()
    private let leather = SCNMaterial()
    private let seam = SCNMaterial()
    private let mesh = SCNMaterial()
    private let fabric = SCNMaterial()
    private let trackMaterial = SCNMaterial()
    private let fillMaterial = SCNMaterial()
    private let fillNode = SCNNode()

    // Battery gauge arc (the headband inlay, or a halo over an imported model's headband).
    private lazy var gaugeRadius: CGFloat = bandRadius + bandHalfThickness + 0.1
    private lazy var gaugeStart: CGFloat = bandStart + 0.05
    private lazy var gaugeEnd: CGFloat = bandEnd - 0.05

    /// True when showing a real model file imported by the user instead of the built-in one.
    private(set) var usesCustomModel = false
    private(set) var batteryLevel = -1
    private(set) var charging = false
    var accent: NSColor = .controlAccentColor

    init(colorway: Colorway = .forestGray, modelURL: URL? = ModelStore.currentURL) {
        setUpMaterials()
        setColorway(colorway)
        if let url = modelURL, let model = Self.loadModel(url) {
            addImportedModel(model)
        } else {
            buildModel()
        }
        setUpLighting()
        setUpCamera()
    }

    // MARK: Public updates

    func setColorway(_ c: Colorway) {
        plastic.diffuse.contents = c.plastic
        sliderPlastic.diffuse.contents = c.slider
        leather.diffuse.contents = c.leather
        seam.diffuse.contents = c == .offWhite ? NSColor(white: 0.45, alpha: 1) : NSColor(white: 0.04, alpha: 1)
        fabric.diffuse.contents = c == .offWhite ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.06, alpha: 1)
        mesh.diffuse.contents = c == .offWhite ? NSColor(white: 0.5, alpha: 1) : NSColor(white: 0.1, alpha: 1)
        trackMaterial.diffuse.contents = usesCustomModel ? NSColor(white: 0.55, alpha: 1)
            : c.plastic.blended(withFraction: 0.25, of: .black)
    }

    func setBattery(level: Int, charging: Bool) {
        self.charging = charging
        let color = charging ? NSColor.systemGreen : level <= 15 ? .systemRed : level <= 30 ? .systemOrange : accent
        fillMaterial.diffuse.contents = color
        fillMaterial.emission.contents = color
        guard level != batteryLevel else { return }
        batteryLevel = level
        // Fills from the left ear cup towards the right, like a progress bar.
        let fraction = CGFloat(min(max(level, 0), 100)) / 100
        guard fraction > 0.005 else { fillNode.geometry = nil; return }
        let from = gaugeEnd - (gaugeEnd - gaugeStart) * fraction
        fillNode.geometry = inlay(from: from, to: gaugeEnd, material: fillMaterial, raise: 0.025)
    }

    /// Called every frame from the render loop.
    func tick(time: TimeInterval) {
        fillMaterial.emission.intensity = charging ? 0.4 + 0.35 * CGFloat(sin(time * 3)) : 0.35
    }

    // MARK: Materials

    private func setUpMaterials() {
        for m in [plastic, sliderPlastic, leather, seam, mesh, fabric, trackMaterial, fillMaterial] {
            m.lightingModel = .physicallyBased
            m.metalness.contents = 0.0
        }
        plastic.roughness.contents = 0.55          // soft-touch matte
        sliderPlastic.roughness.contents = 0.5
        leather.roughness.contents = 0.42          // a little sheen, like the headband top in the photo
        leather.normal.contents = Self.noiseNormalMap(size: 256, cell: 6, strength: 0.5)
        leather.normal.intensity = 0.35
        leather.normal.wrapS = .repeat
        leather.normal.wrapT = .repeat
        leather.normal.contentsTransform = SCNMatrix4MakeScale(6, 2, 1)
        seam.roughness.contents = 0.8
        mesh.roughness.contents = 0.9
        mesh.normal.contents = Self.meshPattern()
        mesh.normal.wrapS = .repeat
        mesh.normal.wrapT = .repeat
        mesh.normal.contentsTransform = SCNMatrix4MakeScale(8, 2, 1)
        fabric.roughness.contents = 1.0
        trackMaterial.roughness.contents = 0.5
        fillMaterial.roughness.contents = 0.3
    }

    // MARK: Model

    private func buildModel() {
        let model = SCNNode()
        model.position = SCNVector3(0, 0.3, 0)
        pivot.addChildNode(model)
        scene.rootNode.addChildNode(pivot)

        // Headband sections, separated by small gaps over a dark core (the seams).
        let deg = CGFloat.pi / 180
        let gap = 0.7 * deg
        let sections: [(CGFloat, CGFloat, SCNMaterial, CGFloat)] = [
            (bandStart, 22 * deg, sliderPlastic, bandHalfThickness),              // right slider
            (22 * deg + gap, 50 * deg, plastic, bandHalfThickness),                // right side
            (50 * deg + gap, 130 * deg - gap, leather, bandHalfThickness + 0.12),  // padded leather top
            (130 * deg, 158 * deg - gap, plastic, bandHalfThickness),              // left side
            (158 * deg, bandEnd, sliderPlastic, bandHalfThickness),                // left slider
        ]
        model.addChildNode(SCNNode(geometry: arcSweep(radius: bandRadius, from: bandStart, to: bandEnd,
                                                      halfRadial: bandHalfThickness - 0.12, halfWidth: bandHalfWidth - 0.12,
                                                      squareness: 4, material: seam)))
        for (from, to, material, halfThickness) in sections {
            model.addChildNode(SCNNode(geometry: arcSweep(radius: bandRadius, from: from, to: to,
                                                          halfRadial: halfThickness, halfWidth: bandHalfWidth,
                                                          squareness: material === leather ? 3.2 : 4.2, material: material)))
        }

        // Battery inlay along the centre line.
        model.addChildNode(SCNNode(geometry: inlay(from: gaugeStart, to: gaugeEnd, material: trackMaterial, raise: 0)))
        model.addChildNode(fillNode)

        for side in [CGFloat(-1), 1] {
            model.addChildNode(earAssembly(side: side))
        }
    }

    /// Fits an imported model into the same space as the built-in one (about 28 wide, 22 tall,
    /// centred) and floats a thin battery arc just above its headband.
    private func addImportedModel(_ model: SCNNode) {
        usesCustomModel = true
        scene.rootNode.addChildNode(pivot)
        let turns = ModelStore.quarterTurns
        model.eulerAngles = SCNVector3(CGFloat(turns.x) * .pi / 2, CGFloat(turns.y) * .pi / 2, 0)
        let fitted = SCNNode()
        fitted.addChildNode(model)
        pivot.addChildNode(fitted)
        guard let (lo, hi) = Self.bounds(of: fitted) else { return }
        let size = hi - lo, mid = (lo + hi) / 2
        let s = CGFloat(min(28 / max(size.x, 0.001), 22 / max(size.y, 0.001)))
        fitted.scale = SCNVector3(s, s, s)
        fitted.position = SCNVector3(-CGFloat(mid.x) * s, -CGFloat(mid.y) * s + 0.3, -CGFloat(mid.z) * s)

        // Headphones' bands are roughly a semicircle about a third of the overall width across.
        let width = CGFloat(size.x) * s, top = CGFloat(size.y) * s / 2 + 0.3
        let r = width * 0.35
        gaugeRadius = r + 0.7
        gaugeStart = 28 * .pi / 180
        gaugeEnd = 152 * .pi / 180
        let gauge = SCNNode()
        gauge.position = SCNVector3(0, top - r, 0)
        gauge.addChildNode(SCNNode(geometry: inlay(from: gaugeStart, to: gaugeEnd, material: trackMaterial, raise: 0)))
        gauge.addChildNode(fillNode)
        pivot.addChildNode(gauge)
        trackMaterial.diffuse.contents = NSColor(white: 0.55, alpha: 1)
        trackMaterial.transparency = 0.5
    }

    /// Stem and ear cup for one side (-1 = left, +1 = right).
    private func earAssembly(side: CGFloat) -> SCNNode {
        let node = SCNNode()
        let angle = side > 0 ? bandStart : bandEnd
        let endX = bandRadius * cos(angle), endY = bandRadius * sin(angle)
        let cupTop = endY - 2.4
        let cupCenterY = cupTop - cupHeight / 2
        let cx = side * cupX

        // End cap of the slider, rounding off the band.
        let cap = SCNNode(geometry: roundedBox(width: 1.25, height: 1.3, length: bandHalfWidth * 2, chamfer: 0.55, material: sliderPlastic))
        cap.position = SCNVector3(endX + side * 0.02, endY - 0.35, 0)
        node.addChildNode(cap)

        // Thick stem curving from the band end down into the top-back of the cup.
        let stemPath = [
            SCNVector3(endX + side * 0.02, endY - 0.3, 0),
            SCNVector3(endX + side * 0.12, endY - 1.3, -0.35),
            SCNVector3(cx - side * 0.1, cupTop - 0.15, -1.55),
            SCNVector3(cx - side * 0.1, cupTop - 1.0, -2.0),
        ]
        node.addChildNode(SCNNode(geometry: tube(through: stemPath, radius: { 0.72 + 0.28 * $0 }, material: plastic)))

        let cup = SCNNode()
        cup.position = SCNVector3(cx, cupCenterY, 0)
        node.addChildNode(cup)

        let housingThickness: CGFloat = 3.3
        // Inner and outer housing halves; their rounded edges meet in a seam groove.
        let inner = SCNNode(geometry: extruded(cupShape(scale: 1), depth: housingThickness * 0.62, chamfer: 0.75, material: plastic))
        inner.eulerAngles.y = .pi / 2
        inner.position.x = -side * housingThickness * 0.19
        cup.addChildNode(inner)

        let outer = SCNNode(geometry: extruded(cupShape(scale: 0.965), depth: housingThickness * 0.42, chamfer: 0.6, material: plastic))
        outer.eulerAngles.y = .pi / 2
        outer.position.x = side * housingThickness * 0.31
        cup.addChildNode(outer)

        // Raised round plate on the outer face.
        let plateDiameter: CGFloat = 5.9
        let plate = SCNNode(geometry: extruded(squircle(width: plateDiameter, height: plateDiameter, n: 2.2),
                                               depth: 0.55, chamfer: 0.22, material: plastic))
        plate.eulerAngles.y = .pi / 2
        plate.position = SCNVector3(side * (housingThickness * 0.52 + 0.14), 0.9, 0.35)
        cup.addChildNode(plate)

        // Mic grille on the top edge, towards the front.
        let grille = SCNNode(geometry: {
            let g = SCNCapsule(capRadius: 0.34, height: 2.4)
            g.materials = [mesh]
            return g
        }())
        grille.eulerAngles.x = .pi / 2
        grille.position = SCNVector3(side * housingThickness * 0.28, cupHeight / 2 - 0.42, 1.0)
        cup.addChildNode(grille)

        // Ear pad (leather ring) and the fabric inside it.
        let padDepth: CGFloat = 2.3
        let pad = SCNNode(geometry: extrudedRing(outer: cupShape(scale: 0.95), inner: cupShape(scale: 0.56),
                                                 depth: padDepth, chamfer: padDepth * 0.44, material: leather))
        pad.eulerAngles.y = .pi / 2
        pad.position.x = -side * (housingThickness * 0.5 + padDepth / 2 - 0.45)
        cup.addChildNode(pad)

        let cloth = SCNNode(geometry: extruded(cupShape(scale: 0.58), depth: 0.2, chamfer: 0.06, material: fabric))
        cloth.eulerAngles.y = .pi / 2
        cloth.position.x = -side * (housingThickness * 0.5 + 0.15)
        cup.addChildNode(cloth)

        if side < 0 {
            addControls(to: cup, side: side, housingThickness: housingThickness)
        }
        return node
    }

    /// ULT button on the outer housing, plus buttons and USB-C along the back edge.
    private func addControls(to cup: SCNNode, side: CGFloat, housingThickness: CGFloat) {
        let ult = SCNNode()
        ult.position = SCNVector3(side * (housingThickness * 0.52 + 0.02), -3.1, -2.6)
        cup.addChildNode(ult)
        let button = SCNNode(geometry: {
            let c = SCNCylinder(radius: 0.62, height: 0.28)
            c.materials = [sliderPlastic]
            return c
        }())
        button.eulerAngles.z = .pi / 2
        ult.addChildNode(button)
        let label = SCNText(string: "ULT", extrusionDepth: 0.02)
        label.font = NSFont.systemFont(ofSize: 1, weight: .heavy)
        label.flatness = 0.02
        label.materials = [seam]
        let labelNode = SCNNode(geometry: label)
        let (minB, maxB) = labelNode.boundingBox
        labelNode.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
        labelNode.scale = SCNVector3(0.42, 0.42, 0.42)
        labelNode.eulerAngles.y = side < 0 ? -.pi / 2 : .pi / 2
        labelNode.position.x = side * 0.15
        ult.addChildNode(labelNode)

        for (i, y) in [-0.9, -2.0, -3.0].enumerated() {
            let b = SCNNode(geometry: {
                let c = SCNCapsule(capRadius: 0.2, height: i == 0 ? 0.9 : 0.6)
                c.materials = [sliderPlastic]
                return c
            }())
            b.position = SCNVector3(side * housingThickness * 0.25, CGFloat(y), -cupBottomWidth / 2 + 0.05)
            cup.addChildNode(b)
        }
        let port = SCNNode(geometry: {
            let c = SCNCapsule(capRadius: 0.17, height: 0.95)
            c.materials = [seam]
            return c
        }())
        port.eulerAngles.z = .pi / 2
        port.position = SCNVector3(side * housingThickness * 0.1, -cupHeight / 2 + 0.2, -0.8)
        cup.addChildNode(port)
    }

    // MARK: Shapes

    /// Cup outline: a rounded trapezoid, narrower at the top and flatter at the bottom.
    private func cupShape(scale: CGFloat) -> NSBezierPath {
        let h = cupHeight * scale, top = cupTopWidth * scale, bottom = cupBottomWidth * scale
        let path = NSBezierPath()
        let steps = 160
        for i in 0..<steps {
            let phi = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
            let c = cos(phi), s = sin(phi)
            let n: CGFloat = s < 0 ? 3.6 : 2.6          // squarer at the bottom, rounder on top
            let ux = sign(c) * pow(abs(c), 2 / n), uy = sign(s) * pow(abs(s), 2 / n)
            let t = (uy + 1) / 2                          // 0 at bottom, 1 at top
            let halfWidth = (bottom + (top - bottom) * t) / 2
            let p = NSPoint(x: ux * halfWidth, y: uy * h / 2)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        return path
    }

    private func squircle(width: CGFloat, height: CGFloat, n: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let steps = 120
        for i in 0..<steps {
            let phi = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
            let c = cos(phi), s = sin(phi)
            let p = NSPoint(x: sign(c) * pow(abs(c), 2 / n) * width / 2, y: sign(s) * pow(abs(s), 2 / n) * height / 2)
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        return path
    }

    private static let roundChamfer: NSBezierPath = {
        // Quarter-circle chamfer profile so extruded edges are rounded, not bevelled.
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 0, y: 1))
        p.curve(to: NSPoint(x: 1, y: 0), controlPoint1: NSPoint(x: 0.552, y: 1), controlPoint2: NSPoint(x: 1, y: 0.552))
        return p
    }()

    private func extruded(_ path: NSBezierPath, depth: CGFloat, chamfer: CGFloat, material: SCNMaterial) -> SCNGeometry {
        path.flatness = 0.02
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = chamfer
        shape.chamferProfile = Self.roundChamfer
        shape.chamferMode = .both
        shape.materials = [material]
        return shape
    }

    private func extrudedRing(outer: NSBezierPath, inner: NSBezierPath, depth: CGFloat, chamfer: CGFloat,
                              material: SCNMaterial) -> SCNGeometry {
        let path = outer.copy() as! NSBezierPath
        path.append(inner.reversed)
        path.windingRule = .evenOdd
        return extruded(path, depth: depth, chamfer: chamfer, material: material)
    }

    private func roundedBox(width: CGFloat, height: CGFloat, length: CGFloat, chamfer: CGFloat,
                            material: SCNMaterial) -> SCNGeometry {
        let box = SCNBox(width: width, height: height, length: length, chamferRadius: chamfer)
        box.chamferSegmentCount = 6
        box.materials = [material]
        return box
    }

    /// Thin strip on the outer surface of the headband.
    private func inlay(from: CGFloat, to: CGFloat, material: SCNMaterial, raise: CGFloat) -> SCNGeometry {
        arcSweep(radius: gaugeRadius + raise, from: from, to: to,
                 halfRadial: 0.05, halfWidth: 0.15, squareness: 2.2, material: material)
    }

    /// Sweeps a superellipse cross-section along an arc in the XY plane. `squareness` 2 = ellipse,
    /// higher = boxier padded profile.
    private func arcSweep(radius: CGFloat, from: CGFloat, to: CGFloat, halfRadial a: CGFloat, halfWidth b: CGFloat,
                          squareness n: CGFloat, material: SCNMaterial, steps: Int = 120, ring: Int = 40) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [UInt32] = []
        let e = 2 / n
        for i in 0...steps {
            let t = from + (to - from) * CGFloat(i) / CGFloat(steps)
            let radial = SCNVector3(cos(t), sin(t), 0)
            for j in 0..<ring {
                let phi = 2 * CGFloat.pi * CGFloat(j) / CGFloat(ring)
                let c = cos(phi), s = sin(phi)
                let u = a * sign(c) * pow(abs(c), e)
                let v = b * sign(s) * pow(abs(s), e)
                vertices.append(SCNVector3((radius + u) * radial.x, (radius + u) * radial.y, v))
                let nu = sign(c) * pow(abs(c), 2 - e) / a
                let nv = sign(s) * pow(abs(s), 2 - e) / b
                let len = max(sqrt(nu * nu + nv * nv), 1e-6)
                normals.append(SCNVector3(radial.x * nu / len, radial.y * nu / len, nv / len))
            }
        }
        for i in 0..<steps {
            for j in 0..<ring {
                let a0 = UInt32(i * ring + j), a1 = UInt32(i * ring + (j + 1) % ring)
                let b0 = a0 + UInt32(ring), b1 = a1 + UInt32(ring)
                indices += [a0, b0, a1, a1, b0, b1]
            }
        }
        // Flat end caps.
        for (i, dir) in [(0, CGFloat(-1)), (steps, CGFloat(1))] {
            let t = from + (to - from) * CGFloat(i) / CGFloat(steps)
            let centerIndex = UInt32(vertices.count)
            vertices.append(SCNVector3(radius * cos(t), radius * sin(t), 0))
            normals.append(SCNVector3(-sin(t) * dir, cos(t) * dir, 0))
            let base = UInt32(i * ring)
            for j in 0..<ring {
                let p0 = base + UInt32(j), p1 = base + UInt32((j + 1) % ring)
                indices += dir > 0 ? [centerIndex, p0, p1] : [centerIndex, p1, p0]
            }
        }
        return makeGeometry(vertices, normals, indices, material)
    }

    /// Round tube through control points (Catmull-Rom), radius varying along its length (0…1).
    private func tube(through controls: [SCNVector3], radius: (CGFloat) -> CGFloat, material: SCNMaterial,
                      steps: Int = 48, ring: Int = 28) -> SCNGeometry {
        func catmull(_ p0: SIMD3<Double>, _ p1: SIMD3<Double>, _ p2: SIMD3<Double>, _ p3: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
            let t2 = t * t, t3 = t2 * t
            let a = 2 * p1
            let b = (p2 - p0) * t
            let c = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
            let d = (3 * p1 - p0 - 3 * p2 + p3) * t3
            return 0.5 * (a + b + c + d)
        }
        let pts = controls.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }
        var samples: [SIMD3<Double>] = []
        let segments = pts.count - 1
        for i in 0...steps {
            let u = Double(i) / Double(steps) * Double(segments)
            let seg = min(Int(u), segments - 1)
            let t = u - Double(seg)
            samples.append(catmull(pts[max(seg - 1, 0)], pts[seg], pts[seg + 1], pts[min(seg + 2, pts.count - 1)], t))
        }
        // Parallel-transport frames so the ring doesn't twist.
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [UInt32] = []
        var normal = SIMD3<Double>(0, 0, 1)
        for i in 0...steps {
            let tangent = simd_normalize(samples[min(i + 1, steps)] - samples[max(i - 1, 0)])
            normal = simd_normalize(normal - simd_dot(normal, tangent) * tangent)
            let binormal = simd_cross(tangent, normal)
            let r = Double(radius(CGFloat(i) / CGFloat(steps)))
            for j in 0..<ring {
                let phi = 2 * Double.pi * Double(j) / Double(ring)
                let dir = cos(phi) * normal + sin(phi) * binormal
                let p = samples[i] + r * dir
                vertices.append(SCNVector3(p.x, p.y, p.z))
                normals.append(SCNVector3(dir.x, dir.y, dir.z))
            }
        }
        for i in 0..<steps {
            for j in 0..<ring {
                let a0 = UInt32(i * ring + j), a1 = UInt32(i * ring + (j + 1) % ring)
                let b0 = a0 + UInt32(ring), b1 = a1 + UInt32(ring)
                indices += [a0, a1, b0, a1, b1, b0]
            }
        }
        return makeGeometry(vertices, normals, indices, material)
    }

    private func makeGeometry(_ v: [SCNVector3], _ n: [SCNVector3], _ i: [UInt32], _ material: SCNMaterial) -> SCNGeometry {
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n)],
                            elements: [SCNGeometryElement(indices: i, primitiveType: .triangles)])
        g.materials = [material]
        return g
    }

    // MARK: Lighting & camera

    private func setUpLighting() {
        scene.lightingEnvironment.contents = Self.studioEnvironment()
        scene.lightingEnvironment.intensity = 1.5

        let key = SCNLight()
        key.type = .directional
        key.intensity = 850
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.9, -0.5, 0)
        scene.rootNode.addChildNode(keyNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 650
        rim.color = NSColor(red: 0.8, green: 0.86, blue: 1, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.35, .pi * 0.85, 0)
        scene.rootNode.addChildNode(rimNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 140
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Soft contact shadow on an invisible floor (stays put while the model floats).
        let floor = SCNPlane(width: 30, height: 14)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.shadowBlob()
        m.writesToDepthBuffer = false
        floor.materials = [m]
        let floorNode = SCNNode(geometry: floor)
        floorNode.eulerAngles.x = -.pi / 2
        floorNode.position = SCNVector3(0, -13, 0)
        scene.rootNode.addChildNode(floorNode)
    }

    private func setUpCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 28
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = 0.2
        cam.bloomThreshold = 0.9
        cam.zNear = 1
        cam.zFar = 200
        camera.camera = cam
        camera.position = SCNVector3(0, 4, 56)
        camera.look(at: SCNVector3(0, -1.5, 0))
        scene.rootNode.addChildNode(camera)
    }

    /// Equirectangular "photo studio": bright softboxes above, dim floor. Drives reflections.
    private static func studioEnvironment() -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 512), flipped: false) { rect in
            NSGradient(colors: [NSColor(white: 0.1, alpha: 1), NSColor(white: 0.38, alpha: 1), NSColor(white: 0.92, alpha: 1)],
                       atLocations: [0, 0.5, 1], colorSpace: .deviceRGB)!
                .draw(in: rect, angle: 90)
            NSColor(white: 1, alpha: 0.95).setFill()
            for x in [0.12, 0.45, 0.78] {
                NSBezierPath(roundedRect: NSRect(x: rect.width * x, y: rect.height * 0.72, width: rect.width * 0.12,
                                                 height: rect.height * 0.12), xRadius: 12, yRadius: 12).fill()
            }
            return true
        }
    }

    private static func shadowBlob() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 256), flipped: false) { rect in
            NSGradient(colors: [NSColor(white: 0, alpha: 0.3), NSColor(white: 0, alpha: 0)])!
                .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
    }

    /// Fine dot pattern (as a normal map) for the mic grille mesh.
    private static func meshPattern() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(red: 0.5, green: 0.5, blue: 1, alpha: 1).setFill()
            rect.fill()
            NSColor(red: 0.5, green: 0.5, blue: 0.6, alpha: 1).setFill()
            for x in stride(from: 4, to: 64, by: 8) {
                for y in stride(from: 4, to: 64, by: 8) {
                    NSBezierPath(ovalIn: NSRect(x: x - 2, y: y - 2, width: 4, height: 4)).fill()
                }
            }
            return true
        }
    }

    /// Subtle random bumps, used as the leather grain normal map.
    private static func noiseNormalMap(size: Int, cell: Int, strength: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            var rng = SystemRandomNumberGenerator()
            NSColor(red: 0.5, green: 0.5, blue: 1, alpha: 1).setFill()
            rect.fill()
            for x in stride(from: 0, to: size, by: cell) {
                for y in stride(from: 0, to: size, by: cell) {
                    let dx = CGFloat.random(in: -strength...strength, using: &rng) * 0.5 + 0.5
                    let dy = CGFloat.random(in: -strength...strength, using: &rng) * 0.5 + 0.5
                    NSColor(red: dx, green: dy, blue: 1, alpha: 0.6).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: cell, height: cell)).fill()
                }
            }
            return true
        }
    }
}

private func sign(_ x: CGFloat) -> CGFloat { x < 0 ? -1 : 1 }
