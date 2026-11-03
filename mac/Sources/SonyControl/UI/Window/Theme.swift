import AppKit
import SwiftUI

/// "Printed edition" look, after the DialHack app but quieter: warm paper, ink, hairline and
/// double rules, panels with a hard offset ink shadow (never a blur), one vermilion accent.
enum Theme {
    /// Page background.
    static let paper = dynamic(light: (0.957, 0.941, 0.910), dark: (0.067, 0.064, 0.058))
    /// Panels sitting on the paper.
    static let sheet = dynamic(light: (0.985, 0.976, 0.957), dark: (0.102, 0.098, 0.090))
    /// Text, rules, borders and offset shadows.
    static let ink = dynamic(light: (0.102, 0.098, 0.090), dark: (0.906, 0.886, 0.843))
    /// Hard offset shadow under panels (softer than ink in dark mode, where white would glare).
    static let shade = dynamic(light: (0.102, 0.098, 0.090), dark: (0.400, 0.388, 0.365))
    /// Used sparingly: low battery, the "live" dot, the active tag.
    static let accent = dynamic(light: (0.784, 0.247, 0.157), dark: (0.910, 0.384, 0.282))

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// The page: paper colour with a faint fibre grain, so it reads as stock rather than a flat
/// fill (in dark mode, black paper).
struct PaperBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Theme.paper
            .overlay(Image(nsImage: Self.grain).resizable(resizingMode: .tile)
                .opacity(scheme == .dark ? 0.09 : 0.06)
                .blendMode(scheme == .dark ? .screen : .multiply))
            .ignoresSafeArea()
    }

    /// 192×192 tile of soft grey speckle, generated once.
    private static let grain: NSImage = {
        let size = 192
        var pixels = [UInt8](repeating: 0, count: size * size)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in pixels.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Double(seed >> 40 & 0xFFFF) / 65535
            // Mostly mid-grey, with the occasional darker fleck.
            pixels[i] = UInt8(r < 0.04 ? 40 : 110 + r * 100)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: image, size: NSSize(width: size / 2, height: size / 2))
    }()
}

/// A thin ink line; `double` draws the heavy-over-hairline rule used under mastheads.
struct Rule: View {
    var double = false

    var body: some View {
        if double {
            VStack(spacing: 2) {
                Rectangle().fill(Theme.ink).frame(height: 2)
                Rectangle().fill(Theme.ink).frame(height: 0.75)
            }
        } else {
            Rectangle().fill(Theme.ink.opacity(0.85)).frame(height: 0.75)
        }
    }
}

/// Ink border plus a solid offset shadow, the print-panel look.
struct PrintPanel: ViewModifier {
    var fill: Color = Theme.sheet
    var offset: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.shade).offset(x: offset, y: offset))
    }
}

/// Default push button for the window: outlined in ink, inked in while pressed.
struct PrintButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(configuration.isPressed ? Theme.sheet : Theme.ink)
            .background(configuration.isPressed ? Theme.ink : Theme.sheet, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink.opacity(0.6), lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// On/off switch in the print style: a squared ink-outlined track whose square knob slides
/// across; when on, the track is inked in and the knob turns paper-coloured.
struct PrintToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(configuration.isOn ? Theme.ink : Color.clear)
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.ink.opacity(configuration.isOn ? 1 : 0.55), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(configuration.isOn ? Theme.sheet : Theme.ink.opacity(0.7))
                        .frame(width: 13, height: 13)
                        .padding(3.5)
                }
                .frame(width: 38, height: 20)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.4)
        }
    }
}

extension View {
    func printPanel(fill: Color = Theme.sheet, offset: CGFloat = 3) -> some View {
        modifier(PrintPanel(fill: fill, offset: offset))
    }
}
