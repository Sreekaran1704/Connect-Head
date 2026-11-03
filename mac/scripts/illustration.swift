// Renders the headphone illustration to PNG on a few backgrounds:  scripts/illustration.sh [out.png]
import AppKit
import SwiftUI

@main
struct RenderIllustration {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/illustration.png"
        let view = HStack(spacing: 0) {
            ForEach([Color(white: 0.95), Color(red: 0.89, green: 0.33, blue: 0.31), Color(red: 0.97, green: 0.66, blue: 0.3)], id: \.self) { bg in
                HeadphoneIllustration(level: 57)
                    .frame(width: 420, height: 420)
                    .padding(30)
                    .background(bg)
            }
        }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print(out)
    }
}
