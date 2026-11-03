import SwiftUI

/// A flat-shaded vector drawing of the ULT WEAR, traced from Sony's straight-on product shot
/// (coordinates below are in that photo's pixels). From the front the cups are seen edge-on:
/// each is a leaning slab with the ear-pad strip on the inside, a diagonal housing seam, the
/// long slot where the yoke arm runs down into the housing, and an outer rim with the mic
/// grille. The tall headband has slider joints near its shoulders and a joint above each
/// yoke; its centre groove doubles as the battery gauge, filling from the left cup.
struct HeadphoneIllustration: View, Animatable {
    /// Battery 0…100.
    var level: Double
    var charging = false
    var gaugeColor: Color = .white
    /// Draw the battery level in the headband's groove (off when a ring shows it instead).
    var showsGauge = true
    /// The soft shadow on the floor under the cups (off for the app icon's outline).
    var showsFloor = true
    /// Base plastic colour (Forest Gray by default).
    var color: Color = Color(red: 0.36, green: 0.41, blue: 0.39)

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    /// Region of the reference photo that's drawn (with a little room for the floor shadow).
    private static let frame = CGRect(x: 360, y: 100, width: 815, height: 910)
    /// Mirror axis of the reference photo.
    private static let midX: CGFloat = 766.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !charging)) { timeline in
            let pulse = charging ? 0.75 + 0.25 * sin(timeline.date.timeIntervalSinceReferenceDate * 3) : 1
            Canvas { ctx, size in
                let f = Self.frame
                let s = min(size.width / f.width, size.height / f.height)
                ctx.translateBy(x: (size.width - f.width * s) / 2, y: (size.height - f.height * s) / 2)
                ctx.scaleBy(x: s, y: s)
                ctx.translateBy(x: -f.minX, y: -f.minY)
                draw(in: ctx, pulse: pulse)
            }
        }
        .accessibilityLabel("ULT WEAR headphones, battery \(Int(level)) percent")
    }

    // MARK: Palette

    private var light: Color { color.mix(.white, 0.2) }
    private var dark: Color { color.mix(.black, 0.28) }
    private var deep: Color { color.mix(.black, 0.55) }

    // MARK: Drawing

    private func draw(in ctx: GraphicsContext, pulse: Double) {
        // Floor shadow.
        if showsFloor {
        var floor = ctx
        floor.addFilter(.blur(radius: 18))
        floor.fill(Path(ellipseIn: CGRect(x: 420, y: 950, width: 693, height: 40)), with: .color(.black.opacity(0.3)))
        }

        drawHeadband(in: ctx, pulse: pulse)
        for side in [CGFloat(-1), 1] { drawCup(in: ctx, side: side) }
    }

    // Centre line of the right half of the band, top to bottom (photo pixels).
    private static let bandCentre: [CGPoint] = [
        CGPoint(x: 766.5, y: 158), CGPoint(x: 900, y: 175), CGPoint(x: 990, y: 223), CGPoint(x: 1044, y: 280),
        CGPoint(x: 1080, y: 340), CGPoint(x: 1102, y: 428), CGPoint(x: 1112, y: 500), CGPoint(x: 1114, y: 575),
    ]
    private static let bandWidth: CGFloat = 76

    /// The whole band's centre line, from the bottom of the left yoke over the top to the right.
    private var bandSpine: [CGPoint] {
        let right = Self.bandCentre
        let left = right.reversed().map { mirror($0, side: -1) }
        return smooth(Array(left.dropLast()) + right, samplesPerSegment: 14)
    }

    private func drawHeadband(in ctx: GraphicsContext, pulse: Double) {
        let spine = bandSpine
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for (i, p) in spine.enumerated() {
            let n = normal(spine, i)
            outer.append(CGPoint(x: p.x + n.x * Self.bandWidth / 2, y: p.y + n.y * Self.bandWidth / 2))
            inner.append(CGPoint(x: p.x - n.x * Self.bandWidth / 2, y: p.y - n.y * Self.bandWidth / 2))
        }
        // One closed outline (addLines would start a second subpath).
        let band = closedPath(outer + inner.reversed())

        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.22), radius: 10, y: 8))
        shadowed.fill(band, with: .linearGradient(Gradient(colors: [light, color, dark]),
                                                  startPoint: CGPoint(x: 0, y: 110), endPoint: CGPoint(x: 0, y: 600)))
        // Soft highlight along the top of the band, and a darker inner edge.
        var outerEdge = Path(); outerEdge.addLines(outer)
        ctx.stroke(outerEdge, with: .color(.white.opacity(0.14)), lineWidth: 5)
        var innerEdge = Path(); innerEdge.addLines(inner)
        ctx.stroke(innerEdge, with: .color(deep.opacity(0.45)), lineWidth: 3)

        // Joints: sliders near the shoulders, and where the band meets each yoke.
        // (The spine has 14 samples per traced point; the shoulders sit around the 6th point.)
        let count = spine.count
        for i in [65, 68, count - 66, count - 69] { seam(ctx, at: i, outer: outer, inner: inner, width: 2.2) }
        for i in [7, count - 8] { seam(ctx, at: i, outer: outer, inner: inner, width: 3) }

        // Battery gauge: a groove along the centre, lit from the left end.
        guard showsGauge else { return }
        var groove = Path()
        groove.addLines(Array(spine[14..<(count - 14)]))
        ctx.stroke(groove, with: .color(deep.opacity(0.75)), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        let fraction = min(max(level, 0), 100) / 100
        if fraction > 0.005 {
            var glow = ctx
            glow.addFilter(.shadow(color: gaugeColor.opacity(0.85 * pulse), radius: 9))
            glow.stroke(groove.trimmedPath(from: 0, to: fraction), with: .color(gaugeColor.opacity(pulse)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
    }

    private func seam(_ ctx: GraphicsContext, at i: Int, outer: [CGPoint], inner: [CGPoint], width: CGFloat) {
        var line = Path()
        line.move(to: outer[i])
        line.addLine(to: inner[i])
        ctx.stroke(line, with: .color(deep.opacity(0.85)), lineWidth: width)
        var catchLight = Path()
        catchLight.move(to: outer[i + 1])
        catchLight.addLine(to: inner[i + 1])
        ctx.stroke(catchLight, with: .color(.white.opacity(0.12)), lineWidth: 1.5)
    }

    // Right cup outline, clockwise from the top of the pad (photo pixels).
    private static let cupOutline: [CGPoint] = [
        CGPoint(x: 1008, y: 534), CGPoint(x: 1052, y: 548), CGPoint(x: 1092, y: 556), CGPoint(x: 1146, y: 566),
        CGPoint(x: 1150, y: 640), CGPoint(x: 1152, y: 722), CGPoint(x: 1118, y: 834), CGPoint(x: 1062, y: 914),
        CGPoint(x: 1024, y: 934), CGPoint(x: 950, y: 952), CGPoint(x: 892, y: 962), CGPoint(x: 846, y: 946),
        CGPoint(x: 808, y: 912), CGPoint(x: 800, y: 876), CGPoint(x: 820, y: 812), CGPoint(x: 858, y: 738),
        CGPoint(x: 928, y: 620), CGPoint(x: 972, y: 554),
    ]

    private func drawCup(in ctx: GraphicsContext, side: CGFloat) {
        let outline = closedPath(smooth(Self.cupOutline.map { mirror($0, side: side) }, samplesPerSegment: 10, closed: true))
        let m: (CGFloat, CGFloat) -> CGPoint = { mirror(CGPoint(x: $0, y: $1), side: side) }

        // Base: the ear pad strip (darker, it's leather seen from the side).
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.28), radius: 14, y: 10))
        shadowed.fill(outline, with: .linearGradient(Gradient(colors: [color.mix(.black, 0.12), deep]),
                                                     startPoint: m(980, 540), endPoint: m(820, 930)))

        var cup = ctx
        cup.clip(to: outline)

        // Housing: everything outside the pad seam (line A), lit from the top right.
        let seamA = (m(1056, 540), m(828, 940))
        let housing = halfPlane(through: seamA, towards: m(1200, 700))
        cup.fill(housing, with: .linearGradient(Gradient(colors: [light, color, dark]),
                                                startPoint: m(1100, 560), endPoint: m(900, 960)))
        // Outer rim beyond the second seam (line B), turning away from the light.
        let seamB = (m(1130, 650), m(950, 958))
        let rim = halfPlane(through: seamB, towards: m(1200, 900))
        cup.fill(rim, with: .linearGradient(Gradient(colors: [color, dark.mix(.black, 0.1)]),
                                            startPoint: m(1150, 650), endPoint: m(1000, 940)))

        // Seams with a highlight on the lit side.
        for (a, b) in [seamA, seamB] {
            var line = Path(); line.move(to: a); line.addLine(to: b)
            cup.stroke(line, with: .color(deep.opacity(0.7)), lineWidth: 2.4)
            var hi = Path()
            hi.move(to: CGPoint(x: a.x + side * 4, y: a.y))
            hi.addLine(to: CGPoint(x: b.x + side * 4, y: b.y))
            cup.stroke(hi, with: .color(.white.opacity(0.16)), lineWidth: 2.5)
        }

        // The yoke arm's slot: a long capsule running down into the housing.
        var slot = Path()
        slot.move(to: m(1086, 560))
        slot.addLine(to: m(1030, 760))
        let slotShape = slot.strokedPath(StrokeStyle(lineWidth: 46, lineCap: .round))
        cup.fill(slotShape, with: .linearGradient(Gradient(colors: [light.mix(.white, 0.05), color]),
                                                  startPoint: m(1090, 560), endPoint: m(1020, 780)))
        cup.stroke(slotShape, with: .color(deep.opacity(0.9)), lineWidth: 2.6)

        // Mic grille on the outer edge.
        for k in 0..<7 {
            let y = 652 + CGFloat(k) * 8
            var dash = Path()
            dash.move(to: m(1133 + CGFloat(k) * 1.6, y))
            dash.addLine(to: m(1146 + CGFloat(k) * 1.2, y + 3))
            cup.stroke(dash, with: .color(deep.opacity(0.6)), lineWidth: 2)
        }

        // Rim light along the outline.
        cup.stroke(outline, with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.2)]),
                                                  startPoint: m(1100, 540), endPoint: m(850, 960)), lineWidth: 3)

        if side > 0 {
            // Status LED, headphone jack and USB-C port on the right cup.
            ctx.fill(Path(ellipseIn: CGRect(x: 1040, y: 828, width: 9, height: 9)), with: .color(Color(red: 0.45, green: 1, blue: 0.6)))
            ctx.fill(Path(ellipseIn: CGRect(x: 880, y: 911, width: 30, height: 30)), with: .color(deep))
            ctx.fill(Path(ellipseIn: CGRect(x: 888, y: 919, width: 14, height: 14)), with: .color(.black.opacity(0.85)))
            ctx.fill(Path(roundedRect: CGRect(x: 873, y: 944, width: 22, height: 10), cornerRadius: 4), with: .color(.black.opacity(0.8)))
        }
    }

    // MARK: Geometry helpers

    private func mirror(_ p: CGPoint, side: CGFloat) -> CGPoint {
        side > 0 ? p : CGPoint(x: 2 * Self.midX - p.x, y: p.y)
    }

    /// A big polygon covering everything on one side of the line through `l`.
    private func halfPlane(through l: (CGPoint, CGPoint), towards target: CGPoint) -> Path {
        let (a, b) = l
        let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let len = max(hypot(d.x, d.y), 0.001)
        let u = CGPoint(x: d.x / len, y: d.y / len)
        var n = CGPoint(x: -u.y, y: u.x)
        if (target.x - a.x) * n.x + (target.y - a.y) * n.y < 0 { n = CGPoint(x: -n.x, y: -n.y) }
        let far: CGFloat = 2000
        var p = Path()
        p.move(to: CGPoint(x: a.x - u.x * far, y: a.y - u.y * far))
        p.addLine(to: CGPoint(x: a.x + u.x * far, y: a.y + u.y * far))
        p.addLine(to: CGPoint(x: a.x + u.x * far + n.x * far, y: a.y + u.y * far + n.y * far))
        p.addLine(to: CGPoint(x: a.x - u.x * far + n.x * far, y: a.y - u.y * far + n.y * far))
        p.closeSubpath()
        return p
    }

    private func closedPath(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    private func normal(_ pts: [CGPoint], _ i: Int) -> CGPoint {
        let a = pts[max(i - 1, 0)], b = pts[min(i + 1, pts.count - 1)]
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(hypot(dx, dy), 0.001)
        // Points to the left of travel; travelling left→right over the top that's upwards/outwards.
        return CGPoint(x: dy / len, y: -dx / len)
    }

    /// Catmull-Rom through the points.
    private func smooth(_ p: [CGPoint], samplesPerSegment n: Int, closed: Bool = false) -> [CGPoint] {
        guard p.count > 2 else { return p }
        let count = p.count
        func at(_ i: Int) -> CGPoint { closed ? p[(i % count + count) % count] : p[min(max(i, 0), count - 1)] }
        var out: [CGPoint] = []
        let segments = closed ? count : count - 1
        for i in 0..<segments {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            for k in 0..<n {
                let t = CGFloat(k) / CGFloat(n), t2 = t * t, t3 = t2 * t
                func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (cc - a) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (3 * b - a - 3 * cc + d) * t3)
                }
                out.append(CGPoint(x: c(p0.x, p1.x, p2.x, p3.x), y: c(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        if !closed { out.append(p[count - 1]) }
        return out
    }
}

private extension Color {
    /// Blends towards another colour (0 = self, 1 = other).
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.deviceRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.deviceRGB) ?? .gray
        return Color(red: a.redComponent + (b.redComponent - a.redComponent) * amount,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount)
    }
}
