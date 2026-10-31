#if canImport(SceneKit)
import CoreGraphics
import Foundation
import SceneKit

/// The finishing touches on a furnished room: rugs, curtains, pictures, things on tables and, for a
/// holiday, its decorations. Worked out from the room and layout each time it's drawn, so every design has
/// them, and they follow when a piece is moved or removed. They take no floor a piece or a door needs, and
/// nothing here is a product.
struct RoomDressing {
    let room: CanonicalRoom
    let layout: FurnitureLayout
    let style: DesignStyle?
    /// False when the walls are cut low: anything mounted on them would float.
    let tallWalls: Bool
    let root = SCNNode()

    private let look: ResolvedLook
    private let season: Season?

    init(room: CanonicalRoom, layout: FurnitureLayout, style: DesignStyle?, tallWalls: Bool) {
        self.room = room; self.layout = layout; self.style = style; self.tallWalls = tallWalls
        look = ResolvedLook(entry: nil, name: "", category: "", style: style)
        season = Season.of(style: style)
        root.name = "dressing"
    }

    /// Everything, as one node.
    func build() -> SCNNode {
        rugs()
        for p in layout.placed { onTop(of: p) }
        if tallWalls {
            for window in room.openings where window.type == .window { curtains(window) }
            wallPictures()
            switch season {
            case .christmas: christmasWalls()
            case .halloween: halloweenWalls()
            case nil: break
            }
        }
        floorTouches()
        return root
    }

    // MARK: Frames

    /// A set of parts in a frame at (x, z) turned to `rotation`, `y` up from the floor.
    private func parts(_ x: Double, _ z: Double, rotation: Double, y: Double = 0, name: String? = nil) -> FurnitureBuilder {
        let b = FurnitureBuilder(w: 0, d: 0, h: 0, category: "", look: look, season: season)
        b.root.position = SCNVector3(Float(x), Float(y), Float(z))
        b.root.eulerAngles = SCNVector3(0, Float(rotation * .pi / 180), 0)
        b.root.name = name
        root.addChildNode(b.root)
        return b
    }

    /// Parts on a wall: x runs along it, z points into the room, y is height. Hidden along with its wall.
    private func onWall(_ wall: Wall, at t: Double) -> FurnitureBuilder {
        let p = wall.point(at: t)
        return parts(p.x, p.z, rotation: PlanMath.rotationFacing(wall.inwardNormal), name: RoomScene.wallPartPrefix + wall.id)
    }

    private func onPiece(_ p: FurnitureLayout.Placed, y: Double? = nil) -> FurnitureBuilder {
        parts(p.x, p.z, rotation: p.rotation, y: y ?? p.height ?? 0)
    }

    /// The wall a piece has its back to, if any.
    private func wallBehind(_ p: FurnitureLayout.Placed) -> Wall? {
        let c = Point2(p.x, p.z), f = PlanMath.front(degrees: p.rotation), back = c - f * ((p.footprint.count > 1 ? p.footprint[1] : 0) / 2)
        return room.walls.first { PlanMath.distance(back, toSegment: $0.start, $0.end) < 0.12 && $0.inwardNormal.dot(f) > 0.7 }
    }

    /// True when a stretch of wall has no opening, nor a piece standing in front of it, between two heights.
    private func wallIsClear(_ wall: Wall, from t0: Double, to t1: Double, y0: Double, y1: Double, ignoring: String? = nil) -> Bool {
        guard t0 >= 0.05, t1 <= wall.length - 0.05, y1 <= wall.height - 0.05 else { return false }
        for o in room.openings(onWall: wall.id) where o.offset - 0.08 < t1 && o.offset + o.width + 0.08 > t0 && o.sill - 0.05 < y1 && o.sill + o.height + 0.2 > y0 {
            return false
        }
        // What hangs is on the wall whatever its stated height, so nothing else may go over it.
        for p in layout.placed where p.itemID != ignoring && ((p.height ?? 0) > y0 - 0.05 || FurnitureCatalog.wallMounted.contains(p.category ?? "")) {
            let corners = RoomRenderer.outline(p).map { (t: ($0 - wall.start).dot(wall.direction), out: ($0 - wall.start).dot(wall.inwardNormal)) }
            guard let near = corners.map(\.out).min(), near < 0.7, corners.map(\.out).max() ?? 0 > -0.05 else { continue }
            if corners.map(\.t).min()! < t1 && corners.map(\.t).max()! > t0 { return false }
        }
        return true
    }

    // MARK: Rugs

    private func rugs() {
        func spread(around p: FurnitureLayout.Placed, width: Double, depth: Double, shift: Double = 0, rotation: Double? = nil, pattern: Int) {
            let turn = rotation ?? p.rotation
            let c = Point2(p.x, p.z) + PlanMath.front(degrees: turn) * shift
            if let fitted = fit(c, width, depth, turn) { rug(fitted.centre, fitted.width, fitted.depth, turn, pattern: pattern) }
        }
        var used = false
        if let table = layout.placed.first(where: { $0.category == "dining_table" }) {
            let (w, d) = (table.footprint[0], table.footprint[1])
            spread(around: table, width: w + 1.3, depth: d + 1.4, pattern: 1)
            used = true
        }
        if let bed = layout.placed.first(where: { $0.category == "bed" }) {
            spread(around: bed, width: bed.footprint[0] + 1.3, depth: bed.footprint[1] * 0.62 + 0.6, shift: bed.footprint[1] * 0.3, pattern: 0)
            used = true
        }
        if let sofa = layout.placed.first(where: { $0.category == "sofa" }) {
            // Under the coffee table and the front of the sofa.
            let table = layout.placed.first { $0.category == "coffee_table" }
            let f = PlanMath.front(degrees: sofa.rotation)
            let reach = table.map { (Point2($0.x, $0.z) - Point2(sofa.x, sofa.z)).dot(f) } ?? 1.0
            spread(around: sofa, width: max(sofa.footprint[0] + 0.6, 2.4), depth: reach + 1.2, shift: reach * 0.62, pattern: 2)
            used = true
        }
        if !used, let desk = layout.placed.first(where: { $0.category == "desk" }) {
            spread(around: desk, width: desk.footprint[0] + 0.5, depth: 1.5, shift: desk.footprint[1] / 2 + 0.55, pattern: 0)
        }
        if let chair = layout.placed.first(where: { $0.category == "armchair" }), layout.placed.first(where: { $0.category == "sofa" }) == nil {
            spread(around: chair, width: 1.5, depth: 1.5, shift: 0.3, pattern: 1)
        }
    }

    /// The largest size up to the one asked for that stays on the floor, keeping clear of door swings.
    private func fit(_ c: Point2, _ width: Double, _ depth: Double, _ rotation: Double) -> (centre: Point2, width: Double, depth: Double)? {
        let floor = Shape.inset(room.floorPolygon, by: 0.04)
        for scale in stride(from: 1.0, through: 0.5, by: -0.1) {
            let (w, d) = (width * scale, depth * scale)
            let shape = Solver.localRect(c.x, c.z, rotation, (-w / 2, w / 2, -d / 2, d / 2))
            if Shape.covers(floor, shape) { return (c, w, d) }
        }
        return nil
    }

    private func rug(_ c: Point2, _ width: Double, _ depth: Double, _ rotation: Double, pattern: Int) {
        let b = parts(c.x, c.z, rotation: rotation, name: "rug")
        let main: Finish, edge: Finish, line: Finish
        switch season {
        case .christmas: (main, edge, line) = (Season.christmas.red, Finish(0.88, 0.82, 0.68, roughness: 0.95), Season.christmas.green)
        case .halloween: (main, edge, line) = (Finish(0.1, 0.07, 0.13, roughness: 0.95), Season.halloween.red, Season.halloween.green.scaled(1.4))
        case nil: (main, edge, line) = (look.bedding.scaled(0.92), look.accent, look.accent.scaled(0.8))
        }
        func flat(_ x: Double, _ z: Double, _ w: Double, _ d: Double, _ f: Finish, level: Double) {
            b.box(x, level, z, w, 0.004, d, f, chamfer: 0)
        }
        var soft = main; soft.roughness = 0.98
        b.box(0, 0, 0, width, 0.008, depth, soft, chamfer: 0)
        // A band inside the edge.
        let inset = 0.09
        for (x, z, w, d) in [(0.0, -depth / 2 + inset, width - inset * 2, 0.03), (0.0, depth / 2 - inset, width - inset * 2, 0.03),
                             (-width / 2 + inset, 0.0, 0.03, depth - inset * 2), (width / 2 - inset, 0.0, 0.03, depth - inset * 2)] {
            flat(x, z, w, d, edge, level: 0.008)
        }
        if season == .christmas || pattern == 2 {
            // A plaid.
            for x in stride(from: -width / 2 + 0.3, to: width / 2 - 0.2, by: 0.3) { flat(x, 0, 0.05, depth - inset * 2 - 0.06, line, level: 0.0085) }
            for z in stride(from: -depth / 2 + 0.3, to: depth / 2 - 0.2, by: 0.3) { flat(0, z, width - inset * 2 - 0.06, 0.05, line, level: 0.009) }
        } else if pattern == 1 {
            // Diamonds down the middle.
            for x in stride(from: -width / 2 + 0.45, to: width / 2 - 0.3, by: 0.42) {
                b.box(x, 0.0085, 0, 0.17, 0.003, 0.17, line, chamfer: 0)
                (b.root.childNodes.last)?.eulerAngles.y = .pi / 4
            }
        } else {
            for z in stride(from: -depth / 2 + 0.28, to: depth / 2 - 0.2, by: 0.24) { flat(0, z, width - inset * 2 - 0.06, 0.018, line, level: 0.0085) }
        }
        // A fringe at the short ends.
        for sign in [-1.0, 1.0] {
            for x in stride(from: -width / 2 + 0.02, to: width / 2, by: 0.05) { flat(x, sign * (depth / 2 - 0.012), 0.012, 0.024, edge, level: 0.008) }
        }
    }

    // MARK: Things on furniture

    private func onTop(of p: FurnitureLayout.Placed) {
        let w = p.footprint.first ?? 0.5, d = p.footprint.count > 1 ? p.footprint[1] : 0.5
        switch p.category ?? "" {
        case "nightstand": nightstand(p, w, d)
        case "coffee_table": coffeeTable(p, w, d)
        case "dresser", "storage": sideboard(p, w, d)
        case "desk": desk(p, w, d)
        case "dining_table": dining(p, w, d)
        case "tv_stand": television(p, w, d)
        case "side_table": sideTable(p, w, d)
        case "bench": bench(p, w, d)
        default: break
        }
    }

    private func books(_ b: FurnitureBuilder, _ x: Double, _ z: Double, count: Int, y: Double = 0) -> Double {
        var at = y
        let colours = [look.accent, look.bedding, look.accent.scaled(0.7), look.body.scaled(0.75)]
        for i in 0..<count {
            let t = 0.024 + 0.008 * Double(i % 2)
            b.box(x + 0.006 * Double(i % 2), at, z, 0.21 - 0.012 * Double(i), t, 0.15, colours[i % colours.count], chamfer: 0.002)
            at += t
        }
        return at
    }

    private func tableLamp(_ b: FurnitureBuilder, _ x: Double, _ z: Double, height: Double = 0.42) {
        b.cylinder(x, 0, z, 0.06, height * 0.12, look.frame)
        b.cylinder(x, height * 0.12, z, 0.035, height * 0.46, look.accent.scaled(0.9), top: 0.016)
        b.cylinder(x, height * 0.58, z, 0.12, height * 0.42, Finish(0.98, 0.9, 0.74, roughness: 0.9, glow: 0.6), top: 0.08)
        b.glowLight(x, height * 0.75, z, (1, 0.78, 0.5), intensity: 14, reach: 1.4)
    }

    private func vase(_ b: FurnitureBuilder, _ x: Double, _ z: Double, height: Double = 0.24) {
        b.cylinder(x, 0, z, 0.05, height, look.accent.scaled(0.85), top: 0.03)
        let stems = season == .christmas ? Season.christmas.green.scaled(1.2) : Finish(0.42, 0.45, 0.28, roughness: 0.85)
        for (dx, dz) in [(-0.05, 0.0), (0.04, 0.03), (0.01, -0.05)] {
            b.limb(SIMD3(x, height - 0.02, z), SIMD3(x + dx * 1.6, height + 0.2, z + dz * 1.6), 0.003, stems)
            b.ellipsoid(x + dx * 1.6, height + 0.21, z + dz * 1.6, 0.025, 0.05, 0.025, stems)
        }
    }

    private func nightstand(_ p: FurnitureLayout.Placed, _ w: Double, _ d: Double) {
        let b = onPiece(p)
        tableLamp(b, -w * 0.12, -d * 0.12)
        _ = books(b, w * 0.2, d * 0.15, count: 2)
    }

    private func coffeeTable(_ p: FurnitureLayout.Placed, _ w: Double, _ d: Double) {
        let b = onPiece(p)
        let top = books(b, -w * 0.22, 0, count: 3)
        b.cylinder(-w * 0.22, top, 0, 0.05, 0.03, look.frame)
        switch season {
        case .christmas:
            b.garland(from: w * 0.02, to: w * 0.42, y: 0.03, z: 0, thickness: 0.03)
            for (x, h) in [(0.12, 0.2), (0.22, 0.14), (0.32, 0.17)] { b.candle(w * x / 0.5 * 0.42 + 0.02, 0.04, 0, height: h, wax: Season.christmas.red) }
        case .halloween:
            b.pumpkin(w * 0.22, 0, 0, 0.1, carved: true)
            b.candle(w * 0.42, 0, -d * 0.2, height: 0.12, wax: Finish(0.1, 0.09, 0.1))
        case nil:
            b.cylinder(w * 0.22, 0, 0, 0.13, 0.022, look.frame)
            b.cylinder(w * 0.22, 0.022, 0, 0.09, 0.05, look.accent.scaled(0.9), top: 0.11)
        }
    }

    private func sideboard(_ p: FurnitureLayout.Placed, _ w: Double, _ d: Double) {
        let b = onPiece(p)
        switch season {
        case .christmas:
            b.garland(from: -w / 2 + 0.06, to: w / 2 - 0.06, y: 0.03, z: -d * 0.1, thickness: 0.035)
            for sign in [-1.0, 1.0] { b.candle(sign * w * 0.3, 0.035, d * 0.14, height: 0.2, wax: Season.christmas.red) }
        case .halloween:
            b.pumpkin(-w * 0.28, 0, 0, 0.11, carved: true)
            b.pumpkin(w * 0.05, 0, 0.02, 0.07, carved: false)
            for i in 0..<3 { b.candle(w * (0.22 + 0.08 * Double(i)), 0, -d * 0.08 + 0.04 * Double(i), height: 0.08 + 0.05 * Double(i), wax: Finish(0.12, 0.1, 0.12)) }
        case nil:
            vase(b, -w * 0.3, 0)
            _ = books(b, w * 0.26, 0, count: 3)
            // A framed photo, leaning.
            b.box(w * 0.04, 0, -d * 0.1, 0.18, 0.22, 0.015, look.frame, chamfer: 0.002)
            b.box(w * 0.04, 0.025, -d * 0.1 + 0.009, 0.14, 0.17, 0.004, look.bedding, chamfer: 0)
        }
    }

    private func desk(_ p: FurnitureLayout.Placed, _ w: Double, _ d: Double) {
        let b = onPiece(p)
        let screen = Finish(0.09, 0.14, 0.2, roughness: 0.2, glow: 0.7)
        b.cylinder(0, 0, -d * 0.22, 0.09, 0.012, look.frame)
        b.box(0, 0.012, -d * 0.22, 0.03, 0.14, 0.02, look.frame, chamfer: 0.003)
        b.box(0, 0.11, -d * 0.2, min(0.62, w * 0.5), 0.34, 0.018, Finish(0.05, 0.05, 0.06, roughness: 0.3), chamfer: 0.004)
        b.box(0, 0.122, -d * 0.2 + 0.01, min(0.59, w * 0.47), 0.316, 0.004, screen, chamfer: 0)
        b.box(0, 0, d * 0.13, min(0.38, w * 0.3), 0.012, 0.13, Finish(0.84, 0.84, 0.86, roughness: 0.4), chamfer: 0.003)
        b.ellipsoid(min(0.3, w * 0.25), 0.014, d * 0.14, 0.03, 0.014, 0.05, Finish(0.84, 0.84, 0.86, roughness: 0.4))
        b.cylinder(-w * 0.36, 0, d * 0.02, 0.038, 0.1, look.accent)
        _ = books(b, w * 0.34, -d * 0.1, count: 3)
    }

    /// Chairs around the table, within its own clearance, and a table set for a meal.
    private func dining(_ p: FurnitureLayout.Placed, _ w: Double, _ d: Double) {
        let seat: (w: Double, d: Double, h: Double) = (0.44, 0.46, 0.84)
        let chairLook = ResolvedLook(entry: nil, name: "", category: "chair", style: style)
        let perSide = w > 1.5 ? 3 : 2
        let c = Point2(p.x, p.z), f = PlanMath.front(degrees: p.rotation)
        let across = Point2(f.z, -f.x)
        var spots: [(Point2, Double)] = []
        for i in 0..<perSide {
            let along = -w / 2 + w * (Double(i) + 0.5) / Double(perSide)
            spots.append((c + across * along + f * (d / 2 + seat.d * 0.28), p.rotation + 180))
            spots.append((c + across * along - f * (d / 2 + seat.d * 0.28), p.rotation))
        }
        spots.append((c + across * (w / 2 + seat.d * 0.28), p.rotation - 90))
        spots.append((c - across * (w / 2 + seat.d * 0.28), p.rotation + 90))
        let others = layout.placed.filter { $0.itemID != p.itemID && !FurnitureCatalog.wallMounted.contains($0.category ?? "") }.map(RoomRenderer.outline)
        let floor = Shape.inset(room.floorPolygon, by: 0.02)
        for (spot, turn) in spots {
            let shape = Solver.localRect(spot.x, spot.z, turn, (-seat.w / 2, seat.w / 2, -seat.d / 2, seat.d / 2))
            guard Shape.covers(floor, shape), !others.contains(where: { Shape.intersects($0, shape) }) else { continue }
            let chair = FurnitureBuilder(w: seat.w, d: seat.d, h: seat.h, category: "chair", look: chairLook, season: season).build()
            chair.position = SCNVector3(Float(spot.x), 0, Float(spot.z))
            chair.eulerAngles = SCNVector3(0, Float(turn * .pi / 180), 0)
            root.addChildNode(chair)
        }

        let b = onPiece(p)
        let runner = season == .christmas ? Season.christmas.red : season == .halloween ? Season.halloween.green.scaled(1.2) : look.accent.scaled(0.9)
        b.box(0, 0, 0, w * 0.82, 0.004, d * 0.34, runner, chamfer: 0)
        let plate = Finish(0.93, 0.91, 0.86, roughness: 0.3)
        for i in 0..<perSide {
            let x = -w / 2 + w * (Double(i) + 0.5) / Double(perSide)
            for sign in [-1.0, 1.0] {
                b.cylinder(x, 0.002, sign * d * 0.32, 0.105, 0.012, plate)
                b.cylinder(x, 0.014, sign * d * 0.32, 0.065, 0.006, look.accent.scaled(1.1))
                b.box(x + 0.14, 0.002, sign * d * 0.32, 0.012, 0.004, 0.17, look.frame, chamfer: 0)
                b.cylinder(x - 0.13, 0.002, sign * (d * 0.32 - 0.09), 0.028, 0.1, Finish(0.78, 0.84, 0.86, roughness: 0.12, metal: 0.2), top: 0.035)
            }
        }
        switch season {
        case .christmas:
            b.garland(from: -w * 0.32, to: w * 0.32, y: 0.03, z: 0, thickness: 0.038)
            for x in [-0.3, 0.0, 0.3] { b.candle(x, 0.04, 0, height: 0.22, wax: Season.christmas.red) }
        case .halloween:
            b.pumpkin(0, 0.004, 0, 0.13, carved: true)
            for x in [-0.34, 0.34] { b.candle(x, 0.004, 0, height: 0.18, wax: Finish(0.1, 0.09, 0.1)) }
        case nil:
            vase(b, 0, 0)
        }
        if tallWalls {
            // A pendant over the table.
            let ceiling = room.ceilingHeight, shade = 0.3, drop = ceiling - p.height! - 0.75
            let lamp = parts(p.x, p.z, rotation: p.rotation, y: p.height! + 0.75)
            lamp.limb(SIMD3(0, shade * 0.6, 0), SIMD3(0, drop, 0), 0.005, look.frame)
            lamp.cylinder(0, 0, 0, shade, shade * 0.6, look.frame, top: 0.06)
            lamp.sphere(0, 0.02, 0, 0.06, Finish(1, 0.86, 0.6, glow: 1.4))
            lamp.glowLight(0, -0.05, 0, (1, 0.8, 0.55), intensity: 40, reach: 2.2)
        }
    }

    private func television(_ p: FurnitureLayout.Placed, _ w: Double, _ d: Double) {
        let b = onPiece(p)
        let tvW = min(w * 0.72, 1.3), tvH = tvW * 0.57
        b.box(0, 0, 0, tvW * 0.4, 0.015, d * 0.5, Finish(0.1, 0.1, 0.11, roughness: 0.4), chamfer: 0.003)
        b.box(0, 0.015, -d * 0.1, 0.06, 0.05, 0.03, Finish(0.1, 0.1, 0.11), chamfer: 0.003)
        b.box(0, 0.05, -d * 0.1, tvW, tvH, 0.03, Finish(0.04, 0.04, 0.05, roughness: 0.3), chamfer: 0.004)
        b.box(0, 0.058, -d * 0.1 + 0.017, tvW - 0.02, tvH - 0.018, 0.003, Finish(0.1, 0.16, 0.24, roughness: 0.12, glow: 0.4), chamfer: 0)
        if w > tvW + 0.5 { _ = books(b, -(w / 2 - 0.17), 0, count: 3); vase(b, w / 2 - 0.13, 0, height: 0.16) }
    }

    private func sideTable(_ p: FurnitureLayout.Placed, _ w: Double, _ d: Double) {
        let b = onPiece(p)
        switch season {
        case .halloween: b.pumpkin(0, 0, 0, 0.08, carved: true)
        case .christmas: b.candle(0, 0, 0, height: 0.2, radius: 0.028, wax: Season.christmas.red)
        case nil:
            _ = books(b, 0, 0, count: 2)
            b.cylinder(0.02, 0.055, 0, 0.042, 0.085, look.accent, top: 0.05)
        }
    }

    private func bench(_ p: FurnitureLayout.Placed, _ w: Double, _ d: Double) {
        let b = onPiece(p)
        b.box(-w * 0.28, 0, 0, w * 0.3, 0.06, d * 0.84, look.accent.scaled(0.9), chamfer: 0.015)
        b.box(w * 0.26, 0, -d * 0.14, 0.34, 0.2, 0.13, look.bedding.scaled(0.95), chamfer: 0.04)
    }

    // MARK: Curtains

    private func curtains(_ window: Opening) {
        guard let wall = room.wall(window.wallID) else { return }
        let top = min(window.sill + window.height + 0.14, wall.height - 0.04)
        let fabric: Finish
        switch season {
        case .christmas: fabric = Season.christmas.red.scaled(0.92)
        case .halloween: fabric = Finish(0.09, 0.05, 0.12, roughness: 0.75)
        case nil: fabric = look.upholstery.scaled(1.05)
        }
        let panel = 0.3, overlap = 0.1
        let left = max(window.offset - panel + overlap, 0.04), right = min(window.offset + window.width + panel - overlap, wall.length - 0.04)
        let b = onWall(wall, at: 0)
        let rodStart = max(left - 0.08, 0.03), rodEnd = min(right + 0.08, wall.length - 0.03)
        b.limb(SIMD3(rodStart, top, 0.07), SIMD3(rodEnd, top, 0.07), 0.012, look.frame)
        for (bracket, end) in [(left, rodStart), (right, rodEnd)] {
            b.box(bracket, top - 0.012, 0.035, 0.018, 0.024, 0.07, look.frame, chamfer: 0.002)
            b.sphere(end, top, 0.07, 0.025, look.frame)
        }
        // Pleated panels: to the floor unless a piece is standing there, then to just under the sill.
        for (from, to) in [(left, window.offset + overlap), (window.offset + window.width - overlap, right)] {
            let toFloor = wallIsClear(wall, from: from, to: to, y0: 0, y1: window.sill) || !layoutNear(wall, from: from, to: to)
            let bottom = toFloor ? 0.02 : max(window.sill - 0.1, 0.02)
            let height = top - bottom - 0.02
            let pleats = max(Int((to - from) / 0.045), 3), each = (to - from) / Double(pleats)
            for i in 0..<pleats {
                let shade = fabric.scaled(i % 2 == 0 ? 1 : 0.84)
                b.box(from + each * (Double(i) + 0.5), bottom, i % 2 == 0 ? 0.08 : 0.055, each + 0.004, height, 0.035, shade, chamfer: 0.006)
            }
        }
        // What's outside: a moon for Halloween, snow on the sill for Christmas.
        let middle = window.offset + window.width / 2
        if season == .halloween {
            b.ellipsoid(middle + window.width * 0.12, window.sill + window.height * 0.72, 0.022, 0.1, 0.1, 0.004, Finish(1, 0.93, 0.68, glow: 1.25))
        }
        b.box(middle, window.sill - 0.03, 0.04, window.width + 0.06, 0.03, 0.09, season == .christmas ? Finish(0.97, 0.98, 1, roughness: 0.95) : look.frame.metal > 0.5 ? Finish(0.92, 0.9, 0.86) : look.bedding, chamfer: 0.006)
    }

    private func layoutNear(_ wall: Wall, from t0: Double, to t1: Double) -> Bool {
        layout.placed.filter { !FurnitureCatalog.wallMounted.contains($0.category ?? "") }.contains { p in
            let corners = RoomRenderer.outline(p).map { (t: ($0 - wall.start).dot(wall.direction), out: ($0 - wall.start).dot(wall.inwardNormal)) }
            guard let near = corners.map(\.out).min(), near < 0.25, corners.map(\.out).max() ?? 0 > -0.05 else { return false }
            return corners.map(\.t).min()! < t1 && corners.map(\.t).max()! > t0
        }
    }

    // MARK: Pictures

    /// Art over the low pieces, then one or two pictures on what's left of each wall.
    private func wallPictures() {
        var taken: [String: [(Double, Double)]] = [:]
        func free(_ id: String, _ a: Double, _ b: Double) -> Bool { !(taken[id] ?? []).contains { $0.0 < b + 0.2 && $0.1 > a - 0.2 } }
        var seed = 0

        let hangOver: Set<String> = ["sofa", "bed", "dresser", "storage", "bench", "fireplace", "desk", "tv_stand"]
        for p in layout.placed where hangOver.contains(p.category ?? "") && (p.height ?? 3) < 1.3 {
            guard let wall = wallBehind(p) else { continue }
            let t = (Point2(p.x, p.z) - wall.start).dot(wall.direction)
            let bottom = max((p.height ?? 0) + (p.category == "tv_stand" ? 0.72 : 0.24), 1.05)
            let width = min(p.footprint[0] * 0.72, 1.7), height = min(0.82, wall.height - bottom - 0.28)
            guard height > 0.35, wallIsClear(wall, from: t - width / 2, to: t + width / 2, y0: bottom, y1: bottom + height, ignoring: p.itemID) else { continue }
            taken[wall.id, default: []].append((t - width / 2, t + width / 2))
            seed += 1
            if p.category == "dresser" {
                mirror(wall, at: t, bottom: bottom, width: min(width, 0.75), height: height)
            } else if p.category == "fireplace", season != nil {
                mantelFeature(wall, at: t, bottom: bottom, height: height)
            } else if width > 1.2, p.category == "sofa" || p.category == "bed" {
                for (i, shift) in [-width / 3, 0, width / 3].enumerated() {
                    picture(wall, at: t + shift, bottom: bottom + (i == 1 ? 0.0 : 0.06), width: width * 0.28, height: height * (i == 1 ? 1 : 0.8), seed: seed + i)
                }
            } else {
                picture(wall, at: t, bottom: bottom, width: width, height: height, seed: seed)
            }
        }
        for wall in room.walls where wall.length > 1.2 {
            let width = 0.85, height = 0.68, bottom = 1.22
            var placedHere = 0
            var t = 0.6
            while t < wall.length - 0.5, placedHere < (wall.length > 4.5 ? 2 : 1) {
                let a = t - width / 2, b = t + width / 2
                if free(wall.id, a, b), wallIsClear(wall, from: a, to: b, y0: bottom - 0.25, y1: bottom + height) {
                    taken[wall.id, default: []].append((a, b))
                    seed += 1
                    picture(wall, at: t, bottom: bottom, width: width, height: height, seed: seed)
                    placedHere += 1
                    t += 1.5
                }
                t += 0.2
            }
        }
    }

    private func mirror(_ wall: Wall, at t: Double, bottom: Double, width: Double, height: Double) {
        let b = onWall(wall, at: t)
        b.box(0, bottom, 0.015, width, height, 0.03, look.frame, chamfer: 0.006)
        b.box(0, bottom + 0.03, 0.032, width - 0.06, height - 0.06, 0.004, Finish(0.76, 0.82, 0.86, roughness: 0.08, metal: 0.9), chamfer: 0)
    }

    /// A framed picture of colour blocks, chosen from the seed so it doesn't change between draws.
    private func picture(_ wall: Wall, at t: Double, bottom: Double, width: Double, height: Double, seed: Int) {
        let b = onWall(wall, at: t)
        if season == .halloween && seed % 2 == 1 { return ghostPortrait(b, bottom, width, height) }
        if season == .christmas && seed % 2 == 1 { return wreath(b, y: bottom + height / 2, radius: min(width, height) * 0.42) }
        let frame = season == .christmas ? Finish(0.86, 0.66, 0.26, roughness: 0.3, metal: 0.9) : look.frame.metal > 0.5 && look.frame.r > 0.5 ? look.frame : Finish(0.16, 0.13, 0.11, roughness: 0.5)
        b.box(0, bottom, 0.012, width, height, 0.025, frame, chamfer: 0.004)
        b.box(0, bottom + 0.025, 0.026, width - 0.05, height - 0.05, 0.003, Finish(0.95, 0.93, 0.88, roughness: 0.9), chamfer: 0)
        let palette = [look.accent, look.accent.scaled(1.3), look.body.scaled(0.8), look.upholstery, look.bedding.scaled(0.7)]
        let w = width - 0.14, h = height - 0.14, y0 = bottom + 0.07
        // Three overlapping shapes of paint, in one of four arrangements.
        let layouts: [[(Double, Double, Double, Double)]] = [
            [(0.0, 0.0, 1.0, 0.55), (0.1, 0.42, 0.42, 0.58), (0.56, 0.5, 0.34, 0.34)],
            [(0.0, 0.0, 0.48, 1.0), (0.48, 0.0, 0.52, 0.42), (0.6, 0.52, 0.28, 0.28)],
            [(0.0, 0.62, 1.0, 0.38), (0.0, 0.3, 0.7, 0.3), (0.2, 0.0, 0.8, 0.28)],
            [(0.12, 0.12, 0.76, 0.76), (0.28, 0.28, 0.44, 0.44), (0.42, 0.42, 0.16, 0.16)],
        ]
        for (i, r) in layouts[seed % layouts.count].enumerated() {
            b.box(-w / 2 + w * (r.0 + r.2 / 2), y0 + h * r.1, 0.029 + 0.001 * Double(i), w * r.2, h * r.3, 0.002, palette[(seed + i) % palette.count], chamfer: 0)
        }
    }

    private func wreath(_ b: FurnitureBuilder, y: Double, radius: Double) {
        let green = Season.christmas.green
        b.ring(0, y, 0.04, radius * 0.78, radius * 0.24, green, standing: true)
        let count = 16
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            b.ellipsoid(cos(a) * radius * 0.78, y + sin(a) * radius * 0.78, 0.055, radius * 0.2, radius * 0.2, 0.03, green.scaled(i % 2 == 0 ? 1 : 1.35))
            if i % 3 == 0 { b.sphere(cos(a) * radius * 0.8, y + sin(a) * radius * 0.8, 0.078, 0.014 + radius * 0.02, Finish(0.82, 0.06, 0.08, roughness: 0.25)) }
            if i % 4 == 1 { b.sphere(cos(a) * radius * 0.68, y + sin(a) * radius * 0.68, 0.078, 0.009, Finish(1, 0.85, 0.5, glow: 1.3)) }
        }
        // A red bow at the bottom.
        let red = Season.christmas.red.scaled(1.15), bowY = y - radius * 0.82
        b.box(-radius * 0.18, bowY - radius * 0.06, 0.082, radius * 0.32, radius * 0.16, 0.018, red, chamfer: 0.008)
        b.box(radius * 0.18, bowY - radius * 0.06, 0.082, radius * 0.32, radius * 0.16, 0.018, red, chamfer: 0.008)
        b.box(0, bowY - radius * 0.1, 0.09, radius * 0.14, radius * 0.22, 0.022, red.scaled(0.8), chamfer: 0.008)
    }

    /// A portrait of a ghost, with eyes that catch the light.
    private func ghostPortrait(_ b: FurnitureBuilder, _ bottom: Double, _ width: Double, _ height: Double) {
        let gilt = Finish(0.55, 0.42, 0.18, roughness: 0.45, metal: 0.85)
        b.box(0, bottom, 0.015, width, height, 0.03, gilt, chamfer: 0.012)
        b.box(0, bottom + 0.05, 0.032, width - 0.1, height - 0.1, 0.004, Finish(0.06, 0.08, 0.12, roughness: 0.75), chamfer: 0)
        let cx = bottom + height * 0.52, r = min(width, height) * 0.19, pale = Finish(0.84, 0.86, 0.82, roughness: 0.8, glow: 0.2)
        b.ellipsoid(0, cx + r * 0.3, 0.036, r, r * 1.1, 0.004, pale)
        b.box(0, cx - r * 1.3, 0.036, r * 2, r * 1.65, 0.004, pale, chamfer: 0)
        for sign in [-1.0, 1.0] { b.ellipsoid(sign * r * 0.38, cx + r * 0.42, 0.041, r * 0.16, r * 0.26, 0.002, Finish(0.03, 0.03, 0.04)) }
        b.ellipsoid(0, cx - r * 0.05, 0.041, r * 0.14, r * 0.2, 0.002, Finish(0.03, 0.03, 0.04))
    }

    private func mantelFeature(_ wall: Wall, at t: Double, bottom: Double, height: Double) {
        let b = onWall(wall, at: t)
        if season == .christmas {
            wreath(b, y: bottom + height * 0.5, radius: min(height * 0.5, 0.36))
        } else {
            ghostPortrait(b, bottom, min(height * 0.8, 0.7), height)
        }
    }

    // MARK: Holiday walls

    /// A string of bulbs along a wall, sagging between hooks.
    private func stringLights(_ wall: Wall, colours: [Finish], cable: Finish) {
        let b = onWall(wall, at: 0), y = wall.height - 0.1
        let swags = max(Int(wall.length / 1.1), 1), each = wall.length / Double(swags)
        for s in 0..<swags {
            let bulbs = 7
            var last: SIMD3<Double>?
            for i in 0...bulbs {
                let u = Double(i) / Double(bulbs)
                let t = each * (Double(s) + u)
                let at = SIMD3(t, y - 0.16 * 4 * u * (1 - u), 0.025)
                if let last { b.limb(last, at, 0.0025, cable) }
                last = at
                if i > 0 && i < bulbs { b.sphere(at.x, at.y - 0.025, at.z, 0.019, colours[(s + i) % colours.count]) }
            }
        }
    }

    private func christmasWalls() {
        let warm = Finish(1, 0.82, 0.44, glow: 1.5), red = Finish(1, 0.15, 0.12, glow: 1.3), green = Finish(0.2, 0.95, 0.35, glow: 1.2), blue = Finish(0.4, 0.68, 1, glow: 1.25)
        for wall in room.walls where wall.length > 1.2 {
            stringLights(wall, colours: [warm, red, warm, green, warm, blue], cable: Finish(0.05, 0.14, 0.08))
        }
        for door in room.openings where door.type == .door {
            guard let wall = room.wall(door.wallID) else { continue }
            let b = onWall(wall, at: door.offset + door.width / 2)
            wreath(b, y: door.height * 0.68, radius: min(door.width * 0.3, 0.27))
            b.garland(from: -door.width / 2 - 0.1, to: door.width / 2 + 0.1, y: door.height + 0.1, z: 0.04, sag: 0.05, thickness: 0.05)
        }
        for window in room.openings where window.type == .window {
            guard let wall = room.wall(window.wallID) else { continue }
            let b = onWall(wall, at: window.offset + window.width / 2)
            let top = min(window.sill + window.height + 0.06, wall.height - 0.08)
            b.garland(from: -window.width / 2 - 0.05, to: window.width / 2 + 0.05, y: top, z: 0.1, sag: 0.1, thickness: 0.045)
            // A row of electric candles on the sill.
            for x in [-0.32, 0.0, 0.32] where abs(x) < window.width / 2 - 0.1 { b.candle(x, window.sill, 0.05, height: 0.14, radius: 0.012) }
        }
    }

    private func halloweenWalls() {
        let orange = Finish(1, 0.45, 0.05, glow: 1.5), purple = Finish(0.68, 0.25, 1, glow: 1.4)
        // A strand from the catalogue takes over from the drawn ones.
        if !layout.placed.contains(where: { $0.category == "string_lights" }) {
            for wall in room.walls where wall.length > 1.2 {
                stringLights(wall, colours: [orange, purple], cable: Finish(0.04, 0.04, 0.05))
            }
        }
        // Bats climbing the longest walls, and a web in each corner.
        var seed = 0
        for wall in room.walls.sorted(by: { $0.length > $1.length }).prefix(2) {
            let b = onWall(wall, at: wall.length / 2)
            for (x, y, s) in [(-0.95, 2.05, 0.2), (-0.55, 2.25, 0.14), (-0.1, 2.0, 0.17), (0.6, 2.2, 0.2), (1.1, 1.98, 0.13)] where y < wall.height - 0.25 && abs(x) < wall.length / 2 - 0.3 {
                let t = wall.length / 2 + x
                guard wallIsClear(wall, from: t - s, to: t + s, y0: y - 0.1, y1: y + 0.1) else { continue }
                bat(b, x: x, y: y, size: s, tilt: Double(seed % 3 - 1) * 0.22)
                seed += 1
            }
        }
        let count = room.walls.count
        for (i, wall) in room.walls.enumerated() {
            let next = room.walls[(i + 1) % count]
            guard wall.direction.cross(next.direction) > 0.5 else { continue } // Only corners that face into the room.
            cobweb(wall, next)
        }
        for door in room.openings where door.type == .door {
            guard let wall = room.wall(door.wallID) else { continue }
            let b = onWall(wall, at: door.offset + door.width / 2)
            // A black wreath with a small pumpkin.
            let y = door.height * 0.68, r = min(door.width * 0.3, 0.25)
            b.ring(0, y, 0.04, r * 0.78, r * 0.22, Finish(0.05, 0.05, 0.06, roughness: 0.9), standing: true)
            for i in 0..<14 {
                let a = Double(i) / 14 * 2 * .pi
                b.ellipsoid(cos(a) * r * 0.78, y + sin(a) * r * 0.78, 0.055, r * 0.2, r * 0.2, 0.025, i % 3 == 0 ? Season.halloween.green : Finish(0.05, 0.05, 0.06, roughness: 0.9))
            }
            let small = FurnitureBuilder(w: 0, d: 0, h: 0, category: "", look: look, season: season)
            small.root.position = SCNVector3(0, Float(y - r * 0.98), 0.04)
            b.root.addChildNode(small.root)
            small.pumpkin(0, 0, 0, r * 0.32, carved: true)
        }
        if !layout.placed.contains(where: { $0.category == "ghost" }) { ghosts() }
    }

    private func bat(_ b: FurnitureBuilder, x: Double, y: Double, size s: Double, tilt: Double) {
        let black = Finish(0.03, 0.02, 0.035, roughness: 0.75)
        b.ellipsoid(x, y, 0.012, s * 0.12, s * 0.19, 0.008, black)
        for sign in [-1.0, 1.0] {
            let tip = SIMD3(x + sign * s, y + s * 0.3 + sign * tilt * s, 0.012)
            b.limb(SIMD3(x, y + s * 0.08, 0.012), tip, s * 0.05, black)
            b.limb(SIMD3(x + sign * s * 0.3, y - s * 0.12, 0.012), tip, s * 0.075, black)
            b.limb(SIMD3(x + sign * s * 0.14, y + s * 0.04, 0.012), SIMD3(x + sign * s * 0.6, y - s * 0.08, 0.012), s * 0.08, black)
            b.ellipsoid(x + sign * s * 0.07, y + s * 0.26, 0.012, s * 0.04, s * 0.09, 0.006, black)
        }
        b.ellipsoid(x, y + s * 0.17, 0.014, s * 0.09, s * 0.08, 0.009, black)
    }

    /// A web across the top of a corner where one wall meets the next.
    private func cobweb(_ wall: Wall, _ next: Wall) {
        let silk = Finish(0.88, 0.88, 0.9, roughness: 0.8, glow: 0.12)
        let c = next.start, u = wall.direction * -1, v = next.direction
        let top = min(wall.height, next.height) - 0.02, reach = 0.68
        let b = parts(c.x, c.z, rotation: 0, name: RoomScene.wallPartPrefix + wall.id + "," + next.id)
        func point(_ along: Double, _ angle: Double) -> SIMD3<Double> {
            // A fan from the very corner: towards one wall, across, and down to the other.
            let spread = (u * cos(angle) + v * sin(angle)) * (along * 0.72)
            return SIMD3(spread.x, top - along * sin(angle * 2) * 0.62, spread.z)
        }
        let spokes = 7
        for s in 0..<spokes {
            let a = Double(s) / Double(spokes - 1) * .pi / 2
            b.limb(point(0.001, a), point(reach, a), 0.0028, silk)
        }
        for ringStep in 1...4 {
            let along = reach * Double(ringStep) / 4
            for s in 0..<(spokes - 1) {
                let a0 = Double(s) / Double(spokes - 1) * .pi / 2, a1 = Double(s + 1) / Double(spokes - 1) * .pi / 2
                b.limb(point(along, a0), point(along * 0.93, (a0 + a1) / 2), 0.002, silk)
                b.limb(point(along * 0.93, (a0 + a1) / 2), point(along, a1), 0.002, silk)
            }
        }
    }

    /// Ghosts hanging over open floor near the corners, above head height.
    private func ghosts() {
        let spots = RoomDressing.openSpots(room: room, layout: layout, size: 0.5, wallGap: 0.55)
        for (i, spot) in spots.prefix(2).enumerated() {
            let y = room.ceilingHeight - 0.72 - 0.08 * Double(i)
            let g = parts(spot.x, spot.z, rotation: Double(i) * 35 - 20, y: y)
            let sheet = Finish(0.95, 0.96, 0.94, roughness: 0.75, glow: 0.3)
            g.limb(SIMD3(0, 0.2, 0), SIMD3(0, room.ceilingHeight - y, 0), 0.002, Finish(0.5, 0.5, 0.5))
            g.ellipsoid(0, 0.1, 0, 0.12, 0.14, 0.12, sheet)
            g.cylinder(0, -0.26, 0, 0.17, 0.34, sheet, top: 0.11)
            for k in 0..<6 {
                let a = Double(k) / 6 * 2 * .pi
                g.ellipsoid(cos(a) * 0.14, -0.26, sin(a) * 0.14, 0.05, 0.06, 0.05, sheet)
            }
            for sign in [-1.0, 1.0] {
                g.ellipsoid(sign * 0.045, 0.12, 0.1, 0.02, 0.032, 0.012, Finish(0.03, 0.03, 0.04))
                g.limb(SIMD3(sign * 0.11, -0.03, 0), SIMD3(sign * 0.22, 0.03, 0.05), 0.025, sheet)
            }
            g.ellipsoid(0, 0.05, 0.115, 0.018, 0.026, 0.008, Finish(0.03, 0.03, 0.04))
        }
    }

    // MARK: Floor touches

    /// Small floor-standing touches: only where they're against a wall, and clear of pieces and doors.
    private func floorTouches() {
        let spots = RoomDressing.wallSpots(room: room, layout: layout, size: 0.36)
        for (i, spot) in spots.prefix(season == nil ? 2 : 3).enumerated() {
            let b = parts(spot.x, spot.z, rotation: Double(i) * 30)
            switch season {
            case .christmas:
                b.gift(0, 0, 0, 0.3, 0.2 + 0.03 * Double(i), 0.28, i % 2 == 0 ? Season.christmas.red : Season.christmas.green.scaled(1.3), Finish(0.86, 0.66, 0.26, roughness: 0.3, metal: 0.9))
            case .halloween:
                b.pumpkin(0, 0, 0, 0.14 + 0.03 * Double(i % 2), carved: i != 1)
            case nil:
                // A woven basket holding a throw.
                b.cylinder(0, 0, 0, 0.14, 0.3, Finish(0.68, 0.53, 0.34, roughness: 0.95), top: 0.17)
                for y in stride(from: 0.05, to: 0.3, by: 0.06) { b.ring(0, y, 0, 0.145 + y * 0.09, 0.006, Finish(0.56, 0.42, 0.26, roughness: 0.95)) }
                b.ellipsoid(0, 0.31, 0, 0.14, 0.07, 0.14, look.accent)
            }
        }
    }

    /// Spots along the walls, clear of every piece and of the door's approach, in a fixed order.
    static func wallSpots(room: CanonicalRoom, layout: FurnitureLayout, size: Double) -> [Point2] {
        var found: [Point2] = []
        let blockers = blockedShapes(room, layout)
        let floor = Shape.inset(room.floorPolygon, by: 0.02)
        for wall in room.walls.sorted(by: { $0.length > $1.length }) {
            var t = 0.35
            while t < wall.length - 0.3 {
                defer { t += 0.25 }
                let c = wall.point(at: t) + wall.inwardNormal * (size / 2 + 0.06)
                let shape = square(c, size)
                guard Shape.covers(floor, shape), !blockers.contains(where: { Shape.intersects($0, shape) }), !found.contains(where: { $0.distance(to: c) < 1.3 }) else { continue }
                found.append(c)
                break
            }
        }
        return found
    }

    /// Open spots away from the walls, for what hangs from the ceiling.
    static func openSpots(room: CanonicalRoom, layout: FurnitureLayout, size: Double, wallGap: Double) -> [Point2] {
        let b = room.derived.bounds
        let floor = Shape.inset(room.floorPolygon, by: wallGap)
        let tall = layout.placed.filter { ($0.height ?? 0) > 1.3 && !FurnitureCatalog.wallMounted.contains($0.category ?? "") }.map(RoomRenderer.outline)
        var found: [Point2] = []
        for x in stride(from: b.centre.x - b.width * 0.36, through: b.centre.x + b.width * 0.36, by: b.width * 0.24) {
            for z in stride(from: b.centre.z - b.depth * 0.34, through: b.centre.z + b.depth * 0.34, by: b.depth * 0.34) {
                let c = Point2(x, z), shape = square(c, size)
                guard Shape.covers(floor, shape), !tall.contains(where: { Shape.intersects($0, shape) }), !found.contains(where: { $0.distance(to: c) < 1.5 }) else { continue }
                found.append(c)
            }
        }
        return found
    }

    /// Every piece's footprint with its clearances, and each door's keep-clear zone.
    static func blockedShapes(_ room: CanonicalRoom, _ layout: FurnitureLayout) -> [[Point2]] {
        // What hangs on a wall takes no floor.
        let standing = layout.placed.filter { !FurnitureCatalog.wallMounted.contains($0.category ?? "") }
        var out = standing.map(RoomRenderer.outline)
        let specs = standing.map { p -> [[Point2]] in
            let d = p.footprint.count > 1 ? p.footprint[1] : 0
            return [Solver.localRect(p.x, p.z, p.rotation, (-(p.footprint.first ?? 0) / 2, (p.footprint.first ?? 0) / 2, d / 2, d / 2 + 0.5))]
        }
        out += specs.flatMap { $0 }
        for o in room.openings where o.type == .door {
            guard let wall = room.wall(o.wallID) else { continue }
            let zone = PlanGeometry.keepClearZone(o, wall: wall)
            out.append(zone.corners)
        }
        return out
    }

    static func square(_ c: Point2, _ size: Double) -> [Point2] {
        let h = size / 2
        return [Point2(c.x - h, c.z - h), Point2(c.x + h, c.z - h), Point2(c.x + h, c.z + h), Point2(c.x - h, c.z + h)]
    }
}
#endif
