// Renders the Connect Head icon: the traced ULT WEAR drawing alone on black paper, like a
// product shot, edged in polished silver with a faint red reflection. Run from mac/:  scripts/make-icon.sh
// Writes build/AppIcon.iconset (for Resources/AppIcon.icns) and the Android launcher
// foreground, kept inside the adaptive-icon safe zone, to
// ../android/app/src/main/res/mipmap-*/ic_launcher_foreground.png.
import AppKit
import SwiftUI

private let paperTop = Color(red: 0.110, green: 0.102, blue: 0.094)
private let paperBottom = Color(red: 0.060, green: 0.056, blue: 0.052)

/// The drawing edged in polished silver, like a metal bezel, with the faintest red at its outer
/// edge, more a reflection of Sony's ULT stripe than a line. Each edge is the silhouette, cut
/// hard-edged (so the drawing's soft shading doesn't turn it into a glow) and nudged out in
/// every direction, layered under the drawing so only its rim shows.
private struct LinedHeadphones: View {
    let line: CGFloat
    private let metal = LinearGradient(stops: [
        .init(color: Color(white: 0.97), location: 0), .init(color: Color(white: 0.74), location: 0.42),
        .init(color: Color(white: 0.46), location: 0.5), .init(color: Color(white: 0.86), location: 0.72),
        .init(color: Color(white: 0.60), location: 1),
    ], startPoint: .top, endPoint: .bottom)

    var body: some View {
        ZStack {
            // The red only catches the light toward the lower right, and only just.
            Rectangle().fill(Color(red: 0.86, green: 0.16, blue: 0.13)).mask(silhouette(by: line * 2.9))
                .mask(LinearGradient(colors: [.clear, .white.opacity(0.22), .white.opacity(0.62)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(metal).mask(silhouette(by: line * 2.3))
            drawing
        }
    }

    private var drawing: some View { HeadphoneIllustration(level: 100, showsGauge: false, showsFloor: false) }

    private func silhouette(by d: CGFloat) -> some View {
        Canvas { ctx, size in
            guard let shape = ctx.resolveSymbol(id: 0) else { return }
            ctx.addFilter(.alphaThreshold(min: 0.5, color: .white))
            ctx.drawLayer { layer in
                for i in 0..<32 {
                    let a = Double(i) / 32 * 2 * .pi
                    layer.draw(shape, at: CGPoint(x: size.width / 2 + cos(a) * d, y: size.height / 2 + sin(a) * d))
                }
            }
        } symbols: {
            GeometryReader { _ in drawing }.tag(0)
        }
    }
}

/// macOS icon: the tile sits inside a 10% margin with a ~22.5% corner radius.
private struct MacIcon: View {
    let side: CGFloat
    var body: some View {
        let tile = side * 0.8
        ZStack {
            RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [paperTop, paperBottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: tile * 0.03, y: tile * 0.012)
                .frame(width: tile, height: tile)
            LinedHeadphones(line: max(tile * 0.006, 0.6))
                .frame(width: tile * 0.66, height: tile * 0.66)
                .offset(y: -tile * 0.01)
        }
        .frame(width: side, height: side)
    }
}

/// Android foreground: 108dp canvas; launchers show roughly the central 66–72dp.
private struct AndroidForeground: View {
    let side: CGFloat
    var body: some View {
        LinedHeadphones(line: max(side * 0.005, 0.6))
            .frame(width: side * 0.5, height: side * 0.5)
            .frame(width: side, height: side)
    }
}

@MainActor private func png<V: View>(_ view: V, _ px: Int) -> Data {
    let renderer = ImageRenderer(content: view.frame(width: CGFloat(px), height: CGFloat(px)))
    renderer.scale = 1
    return NSBitmapImageRep(cgImage: renderer.cgImage!).representation(using: .png, properties: [:])!
}

@main
struct MakeIcon {
    @MainActor static func main() {
        let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for (scale, suffix) in [(1, ""), (2, "@2x")] {
                let px = base * scale
                try! png(MacIcon(side: CGFloat(px)), px).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
            }
        }
        print(iconset.path)

        let res = URL(fileURLWithPath: "../android/app/src/main/res")
        for (dir, px) in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)] {
            let folder = res.appendingPathComponent("mipmap-\(dir)")
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try! png(AndroidForeground(side: CGFloat(px)), px).write(to: folder.appendingPathComponent("ic_launcher_foreground.png"))
        }
        print(res.path)
    }
}
