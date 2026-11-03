import SwiftUI

struct EqualizerPage: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var drafts: [Int: Double] = [:]

    private let bandLabels = ["400", "1k", "2.5k", "6.3k", "16k"]
    private let presetColumns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    /// Bands as displayed, including any slider mid-drag.
    private var shownBands: [Int] {
        hp.state.eqBands.enumerated().map { i, v in drafts[i + 1].map(Int.init) ?? v }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Equalizer", subtitle: "Presets and a 5-band EQ with Clear Bass")

            Card(title: "Preset", systemImage: "music.note.list") {
                LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 8) {
                    ForEach(EqPreset.allCases) { preset in
                        let selected = hp.state.eqPreset == preset
                        Button { hp.setEqPreset(preset) } label: {
                            Text(preset.name)
                                .font(.callout.weight(selected ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundStyle(selected ? Theme.sheet : Theme.ink)
                                .background(selected ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(selected ? 1 : 0.3), lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Card(title: "Custom", systemImage: "slider.vertical.3") {
                EqCurve(bands: shownBands, showGrid: true)
                    .frame(height: 110)

                HStack(alignment: .bottom, spacing: 0) {
                    band(0, label: "Clear Bass", value: hp.state.clearBass)
                        .padding(.trailing, 8)
                    Divider().frame(height: 170)
                    ForEach(0..<5, id: \.self) { i in
                        band(i + 1, label: bandLabels[i], value: hp.state.eqBands[i])
                    }
                }

                HStack {
                    Text("Moving a fader switches the preset to Manual. Changes apply when you let go.")
                        .font(.headline(12, weight: .regular)).italic()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Flat") { hp.resetEq() }
                }
            }
        }
    }

    private func band(_ index: Int, label: String, value: Int) -> some View {
        let shown = drafts[index] ?? Double(value)
        return VStack(spacing: 6) {
            Text(String(format: "%+d", Int(shown)))
                .font(.headline(14, weight: .medium)).monospacedDigit()
            PrintFader(value: Binding(get: { shown }, set: { drafts[index] = $0 })) {
                if let d = drafts[index] {
                    hp.setEqBand(index, to: Int(d))
                    drafts[index] = nil
                }
            }
            .frame(width: 44, height: 150)
            Text(label)
                .font(.system(size: 9.5, weight: .semibold)).tracking(1).textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Smooth response curve through the five band gains (-10…+10).
struct EqCurve: View {
    let bands: [Int]
    var showGrid = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let points = bands.enumerated().map { i, v in
                CGPoint(x: w * (CGFloat(i) + 0.5) / CGFloat(bands.count),
                        y: h / 2 - CGFloat(v) / 10 * (h / 2 - 6))
            }
            let curve = Self.smoothPath(points, from: CGPoint(x: 0, y: points.first?.y ?? h / 2),
                                        to: CGPoint(x: w, y: points.last?.y ?? h / 2))
            ZStack {
                if showGrid {
                    Path { p in
                        for f in [0.0, 0.5, 1.0] {
                            p.move(to: CGPoint(x: 0, y: h * f))
                            p.addLine(to: CGPoint(x: w, y: h * f))
                        }
                    }
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                var fill = curve
                let _ = {
                    fill.addLine(to: CGPoint(x: w, y: h))
                    fill.addLine(to: CGPoint(x: 0, y: h))
                    fill.closeSubpath()
                }()
                fill.fill(Theme.ink.opacity(0.06))
                curve.stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                ForEach(points.indices, id: \.self) { i in
                    Circle().fill(Theme.sheet).frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
                        .position(points[i])
                }
            }
            .animation(.easeOut(duration: 0.25), value: bands)
        }
    }

    /// Catmull-Rom spline through every point (so the curve hits each band), flat to the edges.
    private static func smoothPath(_ points: [CGPoint], from start: CGPoint, to end: CGPoint) -> Path {
        let all = [start] + points + [end]
        var path = Path()
        path.move(to: all[0])
        for i in 0..<(all.count - 1) {
            let p0 = all[max(i - 1, 0)], p1 = all[i], p2 = all[i + 1], p3 = all[min(i + 2, all.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// The EQ curve with its five band points draggable up and down. The gain shows above the
/// point while dragging and is sent to the headphones when the drag ends (which switches the
/// preset to Manual).
struct EditableEqCurve: View {
    @EnvironmentObject private var hp: HeadphoneController
    @State private var drafts: [Int: Int] = [:]
    @State private var active: Int?

    private static let labels = ["400", "1k", "2.5k", "6.3k", "16k"]

    var body: some View {
        let bands = hp.state.eqBands.enumerated().map { drafts[$0.offset] ?? $0.element }
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    EqCurve(bands: bands, showGrid: true)
                    ForEach(0..<bands.count, id: \.self) { i in
                        let x = w * (CGFloat(i) + 0.5) / CGFloat(bands.count)
                        let y = h / 2 - CGFloat(bands[i]) / 10 * (h / 2 - 6)
                        ZStack {
                            if active == i {
                                Text(String(format: "%+d", bands[i]))
                                    .font(.headline(11, weight: .medium)).monospacedDigit()
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 2))
                                    .foregroundStyle(Theme.sheet)
                                    .offset(y: -18)
                            }
                            Circle().fill(active == i ? Theme.ink : .clear).frame(width: 11, height: 11)
                        }
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .position(x: x, y: y)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("eq"))
                                .onChanged { g in
                                    active = i
                                    let v = (h / 2 - g.location.y) / (h / 2 - 6) * 10
                                    drafts[i] = Int(min(max(v, -10), 10).rounded())
                                }
                                .onEnded { _ in
                                    if let v = drafts[i] { hp.setEqBand(i + 1, to: v) }
                                    drafts[i] = nil
                                    active = nil
                                }
                        )
                        .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    }
                }
                .coordinateSpace(name: "eq")
            }
            HStack(spacing: 0) {
                ForEach(Self.labels, id: \.self) { l in
                    Text(l).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Vertical -10…+10 fader in the print style: a hairline track with tick marks, an inked bar
/// from the zero line to the value, and a square knob. Steps of 1; `onCommit` runs when the
/// drag ends.
struct PrintFader: View {
    @Binding var value: Double
    var onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height, mid = geo.size.width / 2
            let knob: CGFloat = 16
            let travel = h - knob
            let y = { (v: Double) in knob / 2 + travel * CGFloat((10 - v) / 20) }
            ZStack {
                // Ticks every 2 dB, longer at 0 and the ends.
                ForEach(0...10, id: \.self) { i in
                    let v = Double(10 - i * 2)
                    let major = v == 0 || abs(v) == 10
                    Rectangle()
                        .fill(Theme.ink.opacity(major ? 0.6 : 0.25))
                        .frame(width: major ? 16 : 8, height: major ? 1 : 0.75)
                        .position(x: mid, y: y(v))
                }
                Rectangle().fill(Theme.ink.opacity(0.35)).frame(width: 1, height: travel).position(x: mid, y: h / 2)
                // Inked bar from 0 to the value.
                let top = min(y(value), y(0)), bottom = max(y(value), y(0))
                Rectangle().fill(Theme.ink).frame(width: 3, height: max(bottom - top, 0)).position(x: mid, y: (top + bottom) / 2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.sheet)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.ink, lineWidth: 1.5))
                    .frame(width: 22, height: knob)
                    .position(x: mid, y: y(value))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = 10 - Double((g.location.y - knob / 2) / travel) * 20
                        value = min(max(v, -10), 10).rounded()
                    }
                    .onEnded { _ in onCommit() }
            )
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
        }
    }
}
