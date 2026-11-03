// Renders the 3D headphone model from a few angles to PNGs, for checking the look without the app.
// Build/run via scripts/render3d.sh
import AppKit
import Metal
import SceneKit

@main
struct Render3D {
    static func main() {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/render3d")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let colorway = Colorway(rawValue: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Forest Gray") ?? .forestGray

        // Optional 3rd argument: a model file to render instead of the built-in model.
        // Optional 4th: "export" writes the built-in model to that path (for testing imports).
        let modelPath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : nil
        if let modelPath, CommandLine.arguments.count > 4, CommandLine.arguments[4] == "export" {
            let ok = HeadphoneScene(colorway: colorway, modelURL: nil).scene.write(
                to: URL(fileURLWithPath: modelPath), options: nil, delegate: nil, progressHandler: nil)
            print("exported:", ok)
            return
        }
        let hp = HeadphoneScene(colorway: colorway, modelURL: modelPath.map { URL(fileURLWithPath: $0) })
        print("custom model:", hp.usesCustomModel)
        hp.setBattery(level: 57, charging: false)
        hp.scene.background.contents = NSColor(white: 0.93, alpha: 1)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = hp.scene
        renderer.pointOfView = hp.camera

        let poses: [(String, Float, Float)] = [("front", 0, 0.12), ("three-quarter", 0.6, 0.18), ("side", 1.45, 0.1), ("top", 0.3, 0.6)]
        for (name, yaw, pitch) in poses {
            hp.pivot.eulerAngles = SCNVector3(pitch, yaw, 0)
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 900, height: 760), antialiasingMode: .multisampling4X)
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
        }
        print(out.path)
    }
}
