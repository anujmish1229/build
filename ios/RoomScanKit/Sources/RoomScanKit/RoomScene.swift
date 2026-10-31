#if canImport(SceneKit)
import CoreGraphics
import Foundation
import Metal
import SceneKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The room in 3D, built from data at real scale in metres, Y up (FR-O1, FR-O8). Each piece's node is
/// named "item:<item id>", so a tap can be traced back to its product.
public enum RoomScene {
    public static let itemPrefix = "item:"
    /// Walls stand outside the outline, so interior dimensions are exact.
    public static let wallThickness = 0.06

    /// The item id behind a tapped node (it or one of its parents), if it is a piece of furniture.
    public static func itemID(of node: SCNNode?) -> String? {
        var node = node
        while let n = node {
            if let name = n.name, name.hasPrefix(itemPrefix) { return String(name.dropFirst(itemPrefix.count)) }
            node = n.parent
        }
        return nil
    }

    /// The scene, everything under one "room" node. `cutaway` draws the walls only that tall, like a doll's house.
    public static func make(_ room: CanonicalRoom, _ layout: FurnitureLayout?, colours: RoomColours? = nil, wallPaint: String? = nil,
                            cutaway: Double? = nil, products: [CatalogEntry] = [], style: DesignStyle? = nil,
                            catalog: FurnitureCatalog = .current) -> SCNScene {
        let scene = SCNScene()
        let root = SCNNode()
        root.name = "room"
        scene.rootNode.addChildNode(root)
        var paint = colours ?? RoomColours()
        if let wallPaint { paint.wall = wallPaint }
        root.addChildNode(floor(room, paint))
        for node in walls(room, paint, cutaway: cutaway) { root.addChildNode(node) }
        let known = FurnitureCatalog(entries: products).merged(with: catalog)
        for placed in layout?.placed ?? [] {
            root.addChildNode(furniture(placed, entry: known.entry(placed.catalogID), style: style))
        }
        return scene
    }

    /// The scene as a USDZ file (FR-O8). Returns the file's address, or nil if it couldn't be written.
    public static func writeUSDZ(_ room: CanonicalRoom, _ layout: FurnitureLayout?, colours: RoomColours? = nil,
                                 wallPaint: String? = nil, products: [CatalogEntry] = [], style: DesignStyle? = nil, name: String = "room") -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        let url = dir.appendingPathComponent("\(name).usdz")
        let scene = make(room, layout, colours: colours, wallPaint: wallPaint, products: products, style: style)
        return scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) ? url : nil
    }

    /// A still picture from above and in front, leaving out the walls nearest the camera (FR-O7).
    public static func snapshot(_ room: CanonicalRoom, _ layout: FurnitureLayout?, colours: RoomColours? = nil, wallPaint: String? = nil,
                                products: [CatalogEntry] = [], style: DesignStyle? = nil,
                                size: CGSize = CGSize(width: 720, height: 900)) -> CGImage? {
        let scene = make(room, layout, colours: colours, wallPaint: wallPaint, products: products, style: style)
        scene.background.contents = CGColor(srgbRed: 0.93, green: 0.91, blue: 0.88, alpha: 1)
        let b = room.derived.bounds
        let span = max(b.width, b.depth, 2)
        let eye = Point2(b.centre.x, b.centre.z + span * 0.95)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name, name.hasPrefix("wall:") || name.hasPrefix("opening:") else { return }
            let id = name.split(separator: ":").last.map(String.init) ?? ""
            let wallID = name.hasPrefix("wall:") ? id : room.opening(id)?.wallID ?? ""
            guard let wall = room.wall(wallID) else { return }
            if wall.inwardNormal.dot(eye - (wall.start + wall.end) * 0.5) < 0 { node.isHidden = true }
        }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 48
        camera.position = SCNVector3(Float(eye.x), Float(span * 1.35), Float(eye.z))
        camera.look(at: SCNVector3(Float(b.centre.x), 0.2, Float(b.centre.z)))
        scene.rootNode.addChildNode(camera)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 850
        sun.eulerAngles = SCNVector3(-1.05, 0.55, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        #if canImport(UIKit)
        return image.cgImage
        #else
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    static func colour(_ hex: String) -> CGColor {
        let c = RoomColours.rgb(hex) ?? (0.8, 0.8, 0.8)
        return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    static func material(_ colour: CGColor, opacity: Double = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = colour
        m.roughness.contents = 0.8
        m.metalness.contents = 0.0
        m.transparency = CGFloat(opacity)
        return m
    }

    static func box(_ w: Double, _ h: Double, _ d: Double, _ m: SCNMaterial) -> SCNNode {
        let g = SCNBox(width: CGFloat(max(w, 0.001)), height: CGFloat(max(h, 0.001)), length: CGFloat(max(d, 0.001)), chamferRadius: 0)
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    static func floor(_ room: CanonicalRoom, _ paint: RoomColours) -> SCNNode {
        let triangles = triangulate(room.floorPolygon)
        let vertices = room.floorPolygon.map { SCNVector3(Float($0.x), 0, Float($0.z)) }
        var indices: [Int32] = []
        // Reversed, so the faces point up.
        for t in stride(from: 0, to: triangles.count, by: 3) { indices += [Int32(triangles[t]), Int32(triangles[t + 2]), Int32(triangles[t + 1])] }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                             SCNGeometrySource(normals: vertices.map { _ in SCNVector3(0, 1, 0) })],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let m = material(colour(paint.floor))
        m.isDoubleSided = true
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.name = "floor"
        return node
    }

    static func walls(_ room: CanonicalRoom, _ paint: RoomColours, cutaway: Double?) -> [SCNNode] {
        var out: [SCNNode] = []
        let wallMaterial = material(colour(paint.wall))
        for wall in room.walls {
            let d = wall.direction, n = wall.inwardNormal
            let angle = atan2(-d.z, d.x)
            let mid = (wall.start + wall.end) * 0.5 - n * (wallThickness / 2)
            let height = min(wall.height, cutaway ?? wall.height)
            let node = box(wall.length, height, wallThickness, wallMaterial)
            node.position = SCNVector3(Float(mid.x), Float(height / 2), Float(mid.z))
            node.eulerAngles = SCNVector3(0, Float(angle), 0)
            node.name = "wall:\(wall.id)"
            out.append(node)
            for o in room.openings(onWall: wall.id) where o.sill < height - 0.05 {
                let top = min(o.sill + o.height, height)
                let c = wall.point(at: o.offset + o.width / 2) + n * 0.006
                let isWindow = o.type == .window
                let panelColour = isWindow ? CGColor(srgbRed: 0.62, green: 0.78, blue: 0.9, alpha: 1)
                    : o.type == .door ? CGColor(srgbRed: 0.62, green: 0.45, blue: 0.3, alpha: 1)
                    : CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
                let panel = box(o.width, top - o.sill, 0.02, material(panelColour, opacity: isWindow ? 0.55 : 1))
                panel.position = SCNVector3(Float(c.x), Float((o.sill + top) / 2), Float(c.z))
                panel.eulerAngles = SCNVector3(0, Float(angle), 0)
                panel.name = "opening:\(o.id)"
                out.append(panel)
            }
        }
        return out
    }

    /// A piece drawn at its real size in a form that suits it. Its origin is the middle of its footprint on the floor.
    static func furniture(_ p: FurnitureLayout.Placed, entry: CatalogEntry? = nil, style: DesignStyle? = nil) -> SCNNode {
        let category = entry?.category ?? p.category ?? ""
        let look = ResolvedLook(entry: entry, name: entry?.name ?? p.name ?? "", category: category, style: style)
        let builder = FurnitureBuilder(w: p.footprint.first ?? 0.1, d: p.footprint.count > 1 ? p.footprint[1] : 0.1, h: p.height ?? 0.5,
                                       category: category, look: look, rugReach: entry?.clearance.front ?? 0)
        let holder = builder.build()
        holder.name = itemPrefix + p.itemID
        holder.position = SCNVector3(Float(p.x), 0, Float(p.z))
        holder.eulerAngles = SCNVector3(0, Float(p.rotation * .pi / 180), 0)
        return holder
    }

    /// Triangles of a simple polygon by ear clipping, as index triples.
    static func triangulate(_ polygon: [Point2]) -> [Int] {
        var idx = Array(polygon.indices)
        if PlanMath.signedArea(polygon) < 0 { idx.reverse() }
        var out: [Int] = []
        var attempts = 0
        while idx.count > 3 && attempts < 10_000 {
            attempts += 1
            var clipped = false
            for k in idx.indices {
                let i0 = idx[(k + idx.count - 1) % idx.count], i1 = idx[k], i2 = idx[(k + 1) % idx.count]
                let a = polygon[i0], b = polygon[i1], c = polygon[i2]
                if PlanMath.signedArea([a, b, c]) <= 0 { continue }
                let blocked = idx.contains { j in j != i0 && j != i1 && j != i2 && Shape.strictlyContains([a, b, c], polygon[j]) }
                if blocked { continue }
                out += [i0, i1, i2]
                idx.remove(at: k)
                clipped = true
                break
            }
            if !clipped { break }
        }
        if idx.count == 3 { out += idx }
        return out
    }
}
#endif
