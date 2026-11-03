import SwiftUI

/// The headphones drawing from the design sketch: the headband doubles as the battery gauge,
/// filling from the left ear cup towards the right, with the percentage above it.
struct HeadphoneBattery: View {
    @Environment(\.colorScheme) private var colorScheme
    let level: Int
    let charging: Bool
    var width: CGFloat = 340

    private var height: CGFloat { width * 0.8 }
    private var bandWidth: CGFloat { width * 0.1 }
    private var radius: CGFloat { width * 0.36 }
    private var center: CGPoint { CGPoint(x: width / 2, y: height * 0.56) }

    private var fillColor: Color {
        if charging { return .green }
        switch level {
        case ..<16: return .red
        case ..<31: return .orange
        default: return .accentColor
        }
    }

    var body: some View {
        ZStack {
            // Headband track and battery fill.
            Headband(center: center, radius: radius)
                .stroke(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: bandWidth, lineCap: .butt))
            Headband(center: center, radius: radius)
                .trim(from: 0, to: CGFloat(min(max(level, 0), 100)) / 100)
                .stroke(fillColor.gradient, style: StrokeStyle(lineWidth: bandWidth, lineCap: .butt))
                .animation(.easeOut(duration: 0.8), value: level)
            // Thin inner edge of the headband, like the sketch.
            Headband(center: center, radius: radius - bandWidth / 2 - width * 0.012)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1.5)

            cup(side: "L", x: center.x - radius)
            cup(side: "R", x: center.x + radius)

            // Percentage above the band.
            HStack(spacing: 4) {
                if charging { Image(systemName: "bolt.fill").foregroundStyle(.green) }
                Text("\(level)%").monospacedDigit()
            }
            .font(.system(size: width * 0.085, weight: .bold, design: .rounded))
            .position(x: center.x, y: center.y - radius - bandWidth / 2 - width * 0.07)
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel("Battery \(level) percent\(charging ? ", charging" : "")")
    }

    /// An ear cup hanging below one end of the headband.
    private func cup(side: String, x: CGFloat) -> some View {
        let w = width * 0.15, h = width * 0.3
        return ZStack {
            // Graphite in both appearances, a touch lighter in dark mode so it reads on black.
            let base = colorScheme == .dark ? 0.36 : 0.22
            RoundedRectangle(cornerRadius: w / 2)
                .fill(LinearGradient(colors: [Color(white: base + 0.1), Color(white: base)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: w / 2 - 6)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
                .padding(6)
            Text(side)
                .font(.system(size: w * 0.32, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: w, height: h)
        .position(x: x, y: center.y + h * 0.42)
    }
}

/// Upper half-circle, drawn left to right so `trim` fills from the left cup.
private struct Headband: Shape {
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        return p
    }
}
