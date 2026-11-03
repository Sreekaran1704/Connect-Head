import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO

/// A real 3D model of the headphones imported by the user (e.g. a USDZ from Sketchfab or CGTrader),
/// kept in Application Support. When present it replaces the built-in procedural model.
enum ModelStore {
    /// Formats SceneKit / Model I/O can open. glTF/GLB isn't supported by macOS; convert those to USDZ.
    static let fileExtensions = ["usdz", "usd", "usda", "usdc", "scn", "dae", "obj", "stl", "ply", "abc"]
    /// Files that may sit next to an OBJ/DAE (materials and textures) and are copied along with it.
    private static let companionExtensions = ["mtl", "png", "jpg", "jpeg", "tga", "bmp", "tif", "tiff", "exr", "hdr"]

    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Connect Head/Model", isDirectory: true)

    private static let fileKey = "customModelFile"
    private static let turnsKey = "customModelQuarterTurns"

    static var currentURL: URL? {
        guard let name = UserDefaults.standard.string(forKey: fileKey) else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Fixes models exported lying down or facing sideways: quarter turns about X and Y.
    static var quarterTurns: (x: Int, y: Int) {
        get {
            let v = UserDefaults.standard.array(forKey: turnsKey) as? [Int] ?? [0, 0]
            return (v.first ?? 0, v.count > 1 ? v[1] : 0)
        }
        set { UserDefaults.standard.set([newValue.x % 4, newValue.y % 4], forKey: turnsKey) }
    }

    /// Copies the model (plus any material/texture files beside it) into Application Support.
    /// Throws if the file can't be opened as a 3D model.
    static func install(from source: URL) throws {
        guard HeadphoneScene.loadModel(source) != nil else { throw ImportError.unreadable }
        let fm = FileManager.default
        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: directory.appendingPathComponent(source.lastPathComponent))

        let ext = source.pathExtension.lowercased()
        if ext == "obj" || ext == "dae" {
            let folder = source.deletingLastPathComponent()
            let siblings = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for item in siblings where item != source {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let name = item.lastPathComponent.lowercased()
                if (isDir && name.hasPrefix("tex")) || companionExtensions.contains(item.pathExtension.lowercased()) {
                    try? fm.copyItem(at: item, to: directory.appendingPathComponent(item.lastPathComponent))
                }
            }
        }
        UserDefaults.standard.set(source.lastPathComponent, forKey: fileKey)
        quarterTurns = (0, 0)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removeObject(forKey: fileKey)
        UserDefaults.standard.removeObject(forKey: turnsKey)
    }

    enum ImportError: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "This file couldn't be opened as a 3D model. Use USDZ (or OBJ). GLB/glTF files can be converted to USDZ with Apple's free Reality Converter."
        }
    }
}

extension HeadphoneScene {
    /// Opens a model file and returns its content (without the file's own lights and cameras).
    static func loadModel(_ url: URL) -> SCNNode? {
        var loaded = try? SCNScene(url: url, options: [.checkConsistency: false, .convertToYUp: true])
        if loaded == nil, MDLAsset.canImportFileExtension(url.pathExtension.lowercased()) {
            let asset = MDLAsset(url: url)
            asset.loadTextures()
            if asset.count > 0 { loaded = SCNScene(mdlAsset: asset) }
        }
        guard let root = loaded?.rootNode else { return nil }
        let content = SCNNode()
        for child in root.childNodes {
            child.removeFromParentNode()
            content.addChildNode(child)
        }
        var hasGeometry = false
        content.enumerateHierarchy { node, _ in
            node.light = nil
            node.camera = nil
            if node.geometry != nil { hasGeometry = true }
        }
        return hasGeometry ? content : nil
    }

    /// Bounding box of all geometry under `node`, in `node`'s coordinates.
    static func bounds(of node: SCNNode) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        node.enumerateHierarchy { child, _ in
            guard let g = child.geometry else { return }
            let (a, b) = g.boundingBox
            for corner in 0..<8 {
                let p = SCNVector3(corner & 1 == 0 ? a.x : b.x, corner & 2 == 0 ? a.y : b.y, corner & 4 == 0 ? a.z : b.z)
                let q = child.convertPosition(p, to: node)
                let v = SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z))
                lo = simd_min(lo, v)
                hi = simd_max(hi, v)
            }
        }
        return lo.x <= hi.x ? (lo, hi) : nil
    }
}
