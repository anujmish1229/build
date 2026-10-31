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

/// The room in 3D, built from data at real scale in metres, Y up. Each piece's node is
/// named "item:<item id>", so a tap can be traced back to its product.
public enum RoomScene {
    public static let itemPrefix = "item:"
    /// Names what's mounted on walls, followed by the ids of the walls it's on.
    static let wallPartPrefix = "onwall:"
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
        for node in walls(room, paint, cutaway: cutaway, season: Season.of(style: style)) { root.addChildNode(node) }
        let known = FurnitureCatalog(entries: products).merged(with: catalog)
        for placed in layout?.placed ?? [] {
            let piece = furniture(placed, entry: known.entry(placed.catalogID), style: style)
            if FurnitureCatalog.wallMounted.contains(placed.category ?? "") || placed.category == "cobweb", let wall = nearestWall(placed, in: room) {
                // What hangs on a wall hides along with it; a tap still finds the piece inside.
                let holder = SCNNode()
                holder.name = wallPartPrefix + wall.id
                holder.addChildNode(piece)
                root.addChildNode(holder)
            } else {
                root.addChildNode(piece)
            }
        }
        if let layout, !layout.placed.isEmpty {
            root.addChildNode(RoomDressing(room: room, layout: layout, style: style, tallWalls: cutaway == nil).build())
        }
        return scene
    }

    static func nearestWall(_ p: FurnitureLayout.Placed, in room: CanonicalRoom) -> Wall? {
        room.walls.min { PlanMath.distance(Point2(p.x, p.z), toSegment: $0.start, $0.end) < PlanMath.distance(Point2(p.x, p.z), toSegment: $1.start, $1.end) }
    }

    /// The kinds of prop that light themselves. Their glow only reads in the dark, so a layout holding any is drawn at night.
    public static let litCategories: Set<String> = ["neon_sign", "led_strip", "string_lights", "projector", "prop_light"]

    /// True when the layout holds a prop that lights up, so the room wants night, not noon.
    public static func isLit(_ layout: FurnitureLayout?) -> Bool {
        layout?.placed.contains { litCategories.contains($0.category ?? "") } ?? false
    }

    /// Where to look at a room from: above and at an angle, on the side that sees the fronts of its biggest
    /// pieces. Used for pictures and as the viewer's starting point.
    public static func viewpoint(_ room: CanonicalRoom, layout: FurnitureLayout? = nil, fieldOfView: Double = 48) -> (eye: SCNVector3, target: SCNVector3) {
        let b = room.derived.bounds
        let across = (b.width * b.width + b.depth * b.depth).squareRoot()
        let distance = max(across, 2.5) * 0.74 / tan(fieldOfView / 2 * .pi / 180) * 0.7
        // Eight angles around the room, in a fixed order, so a tie always gives the same one.
        let steps = [(0.44, 0.72), (-0.44, 0.72), (0.72, 0.44), (-0.72, 0.44), (0.44, -0.72), (-0.44, -0.72), (0.72, -0.44), (-0.72, -0.44)]
        var best = steps[0], bestScore = -Double.infinity
        for step in steps {
            let direction = Point2(step.0, step.1) * (1 / Point2(step.0, step.1).length)
            var score = 0.0
            for p in layout?.placed ?? [] {
                let w = p.footprint.first ?? 0, d = p.footprint.count > 1 ? p.footprint[1] : 0
                score += PlanMath.front(degrees: p.rotation).dot(direction) * w * d * (p.height ?? 0.5)
            }
            // A slight preference for the usual view: from the front, on the right.
            score += step.1 * 0.01 + step.0 * 0.005
            if score > bestScore + 1e-9 { best = step; bestScore = score }
        }
        return (SCNVector3(Float(b.centre.x + best.0 * distance), Float(distance * 0.88), Float(b.centre.z + best.1 * distance)),
                SCNVector3(Float(b.centre.x), 0.45, Float(b.centre.z)))
    }

    /// Everything that hides along with a wall.
    public static func wallParts(in root: SCNNode) -> [SCNNode] {
        root.childNodes { node, _ in node.name.map(isWallPart) ?? false }
    }

    /// Hides the walls between the camera and the room, and what's on them.
    public static func hideWalls(_ parts: [SCNNode], room: CanonicalRoom, from eye: Point2) {
        let centre = room.derived.bounds.centre
        let hidden = Set(room.walls.filter { wall in
            let middle = (wall.start + wall.end) * 0.5
            // Its back is to the camera, or it's a wall of an alcove or an L standing nearer than the room's middle.
            return wall.inwardNormal.dot(eye - middle) < 0 || (middle - eye).length < (centre - eye).length
        }.map(\.id))
        for node in parts {
            guard let name = node.name else { continue }
            let ids: [String]
            if name.hasPrefix("opening:") {
                ids = [room.opening(String(name.dropFirst(8)))?.wallID ?? ""]
            } else {
                let tail = name.split(separator: ":").last.map(String.init) ?? ""
                ids = tail.split(separator: ",").map(String.init)
            }
            node.isHidden = ids.contains(where: hidden.contains)
        }
    }

    /// True for a wall, an opening, or something mounted on a wall.
    public static func isWallPart(_ name: String) -> Bool {
        name.hasPrefix("wall:") || name.hasPrefix("opening:") || name.hasPrefix(wallPartPrefix)
    }

    /// The light for a design: soft shadows and a gentle fill, warmer and dimmer for a holiday evening.
    public static func addLights(to scene: SCNScene, room: CanonicalRoom, style: DesignStyle?, layout: FurnitureLayout? = nil) {
        // Neon needs the dark whatever the theme: Christmas keeps its own evening, anything else gets Halloween's.
        var season = Season.of(style: style)
        if season == nil && isLit(layout) { season = .halloween }
        let span = max(room.derived.bounds.width, room.derived.bounds.depth, 2)
        let sun = SCNNode()
        let light = SCNLight()
        light.type = .directional
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowSampleCount = 16
        light.shadowRadius = 5
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.42)
        light.orthographicScale = CGFloat(span)
        light.zNear = 0.1
        light.zFar = CGFloat(span * 5)
        light.automaticallyAdjustsShadowProjection = true
        let fill = SCNLight()
        fill.type = .directional
        let ambient = SCNLight()
        ambient.type = .ambient
        switch season {
        case .christmas:
            light.intensity = 520
            light.color = CGColor(srgbRed: 1, green: 0.86, blue: 0.7, alpha: 1)
            fill.intensity = 160
            fill.color = CGColor(srgbRed: 0.85, green: 0.86, blue: 1, alpha: 1)
            ambient.intensity = 330
            ambient.color = CGColor(srgbRed: 1, green: 0.88, blue: 0.75, alpha: 1)
        case .halloween:
            light.intensity = 230
            light.color = CGColor(srgbRed: 0.68, green: 0.7, blue: 1, alpha: 1)
            fill.intensity = 80
            fill.color = CGColor(srgbRed: 0.75, green: 0.5, blue: 1, alpha: 1)
            ambient.intensity = 170
            ambient.color = CGColor(srgbRed: 0.68, green: 0.62, blue: 0.95, alpha: 1)
        case nil:
            light.intensity = 780
            light.color = CGColor(srgbRed: 1, green: 0.95, blue: 0.87, alpha: 1)
            fill.intensity = 230
            fill.color = CGColor(srgbRed: 0.86, green: 0.91, blue: 1, alpha: 1)
            ambient.intensity = 390
            ambient.color = CGColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1)
        }
        sun.light = light
        sun.eulerAngles = SCNVector3(-0.98, 0.62, 0)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.5, -2.2, 0)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        for node in [sun, fillNode, ambientNode] { scene.rootNode.addChildNode(node) }
    }

    /// The scene as a USDZ file. Returns the file's address, or nil if it couldn't be written.
    public static func writeUSDZ(_ room: CanonicalRoom, _ layout: FurnitureLayout?, colours: RoomColours? = nil,
                                 wallPaint: String? = nil, products: [CatalogEntry] = [], style: DesignStyle? = nil, name: String = "room") -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        let url = dir.appendingPathComponent("\(name).usdz")
        let scene = make(room, layout, colours: colours, wallPaint: wallPaint, products: products, style: style)
        return scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) ? url : nil
    }

    private static let snapshotLock = NSLock()

    /// A still picture from above and in front, leaving out the walls nearest the camera.
    public static func snapshot(_ room: CanonicalRoom, _ layout: FurnitureLayout?, colours: RoomColours? = nil, wallPaint: String? = nil,
                                products: [CatalogEntry] = [], style: DesignStyle? = nil,
                                size: CGSize = CGSize(width: 720, height: 900)) -> CGImage? {
        // One at a time: pictures of rooms with the same floor share its texture, and rendering them together
        // can draw a picture before the texture is ready, leaving the floor blank.
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        let scene = make(room, layout, colours: colours, wallPaint: wallPaint, products: products, style: style)
        scene.background.contents = CGColor(srgbRed: 0.118, green: 0.161, blue: 0.208, alpha: 1)
        let view = viewpoint(room, layout: layout)
        hideWalls(wallParts(in: scene.rootNode), room: room, from: Point2(Double(view.eye.x), Double(view.eye.z)))
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 48
        camera.camera?.zNear = 0.05
        camera.camera?.wantsHDR = false
        camera.position = view.eye
        camera.look(at: view.target)
        scene.rootNode.addChildNode(camera)
        addLights(to: scene, room: room, style: style, layout: layout)
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
        // One copy of the texture covers a fixed area of floor, so boards are the same size in every room.
        let coordinates = room.floorPolygon.map { CGPoint(x: $0.x / FloorTexture.tile, y: $0.z / FloorTexture.tile) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                             SCNGeometrySource(normals: vertices.map { _ in SCNVector3(0, 1, 0) }),
                                             SCNGeometrySource(textureCoordinates: coordinates)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let m = material(colour(paint.floor))
        if let surface = FloorTexture.image(hex: paint.floor, type: paint.floorType) {
            m.diffuse.contents = surface
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.roughness.contents = 0.82
        }
        m.isDoubleSided = true
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.name = "floor"
        return node
    }

    static func walls(_ room: CanonicalRoom, _ paint: RoomColours, cutaway: Double?, season: Season? = nil) -> [SCNNode] {
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
                // Daylight outside, a blue winter dusk at Christmas, a dark night at Halloween.
                let sky: (Double, Double, Double) = season == .halloween ? (0.05, 0.07, 0.17) : season == .christmas ? (0.18, 0.28, 0.5) : (0.62, 0.78, 0.92)
                let panelColour = isWindow ? CGColor(srgbRed: sky.0, green: sky.1, blue: sky.2, alpha: 1)
                    : o.type == .door ? CGColor(srgbRed: 0.62, green: 0.45, blue: 0.3, alpha: 1)
                    : CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
                let panelMaterial = material(panelColour)
                // A window shows the light outside, so it stays bright whatever the room's lighting.
                if isWindow { panelMaterial.emission.contents = CGColor(srgbRed: sky.0 * 0.5, green: sky.1 * 0.5, blue: sky.2 * 0.5, alpha: 1) }
                let panel = box(o.width, top - o.sill, 0.02, panelMaterial)
                panel.position = SCNVector3(Float(c.x), Float((o.sill + top) / 2), Float(c.z))
                panel.eulerAngles = SCNVector3(0, Float(angle), 0)
                panel.name = "opening:\(o.id)"
                out.append(panel)
            }
            out.append(wallTrim(wall, room: room, paint: paint, height: height))
        }
        return out
    }

    /// A skirting board around the wall, with frames around its doors and windows.
    static func wallTrim(_ wall: Wall, room: CanonicalRoom, paint: RoomColours, height: Double) -> SCNNode {
        let isDark = (RoomColours.rgb(paint.wall).map { $0.r + $0.g + $0.b } ?? 3) < 1.0
        let trim = isDark ? Finish(0.13, 0.11, 0.13, roughness: 0.5) : Finish(0.95, 0.94, 0.9, roughness: 0.5)
        let parts = FurnitureBuilder(w: 0, d: 0, h: 0, category: "", look: ResolvedLook(entry: nil, name: "", category: "", style: nil))
        let start = wall.start
        parts.root.position = SCNVector3(Float(start.x), 0, Float(start.z))
        parts.root.eulerAngles = SCNVector3(0, Float(PlanMath.rotationFacing(wall.inwardNormal) * .pi / 180), 0)
        parts.root.name = wallPartPrefix + wall.id
        let openings = room.openings(onWall: wall.id)
        // Local x runs along the wall from its start.
        var from = 0.0
        for door in openings.filter({ $0.type == .door }).sorted(by: { $0.offset < $1.offset }) + [nil as Opening?] {
            let to = door.map { $0.offset - 0.06 } ?? wall.length
            if to > from { parts.box((from + to) / 2, 0, 0.009, to - from, 0.095, 0.018, trim, chamfer: 0.002) }
            from = door.map { $0.offset + $0.width + 0.06 } ?? from
        }
        let jamb = 0.06, depth = 0.028
        for o in openings where o.sill < height - 0.05 {
            let t0 = o.offset, t1 = o.offset + o.width, top = min(o.sill + o.height, height), middle = (t0 + t1) / 2
            for t in [t0 - jamb / 2, t1 + jamb / 2] where t > 0 && t < wall.length {
                parts.box(t, o.sill, depth / 2, jamb, top - o.sill, depth, trim, chamfer: 0.002)
            }
            if top + jamb <= height { parts.box(middle, top, depth / 2, o.width + jamb * 2, jamb, depth, trim, chamfer: 0.002) }
            switch o.type {
            case .window:
                parts.box(middle, o.sill + (top - o.sill) * 0.5, 0.016, o.width, 0.03, 0.022, trim, chamfer: 0.002)
                parts.box(middle, o.sill, 0.016, 0.03, top - o.sill, 0.022, trim, chamfer: 0.002)
                parts.box(middle, o.sill - 0.03, 0.03, o.width + 0.1, 0.03, 0.06, trim, chamfer: 0.004)
            case .door:
                // Two recessed panels and a handle.
                let leaf = Finish(0.56, 0.4, 0.27, roughness: 0.55)
                for (bottom, panel) in [(0.14, 0.72), (0.98, top - 1.12)] where panel > 0.1 {
                    parts.box(middle, bottom, 0.02, o.width - 0.2, panel, 0.008, leaf.scaled(0.8), chamfer: 0.002)
                }
                let handle = Finish(0.72, 0.58, 0.32, roughness: 0.3, metal: 0.9)
                parts.box(t1 - 0.08, 0.98, 0.035, 0.11, 0.018, 0.018, handle, chamfer: 0.004)
                parts.sphere(t1 - 0.05, 0.99, 0.03, 0.022, handle)
            default:
                break
            }
        }
        return parts.root
    }

    /// A piece drawn at its real size in a form that suits it. Its origin is the middle of its footprint on the floor.
    static func furniture(_ p: FurnitureLayout.Placed, entry: CatalogEntry? = nil, style: DesignStyle? = nil) -> SCNNode {
        let category = entry?.category ?? p.category ?? ""
        if let entry, entry.isProp {
            let holder = HalloweenPropBuilder(entry: entry, w: p.footprint.first ?? 0.1, d: p.footprint.count > 1 ? p.footprint[1] : 0.1, h: p.height ?? 0.5).build()
            holder.name = itemPrefix + p.itemID
            holder.position = SCNVector3(Float(p.x), 0, Float(p.z))
            holder.eulerAngles = SCNVector3(0, Float(p.rotation * .pi / 180), 0)
            return holder
        }
        let look = ResolvedLook(entry: entry, name: entry?.name ?? p.name ?? "", category: category, style: style)
        let builder = FurnitureBuilder(w: p.footprint.first ?? 0.1, d: p.footprint.count > 1 ? p.footprint[1] : 0.1, h: p.height ?? 0.5,
                                       category: category, look: look, season: Season.of(style: style))
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
