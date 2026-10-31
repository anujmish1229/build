#if canImport(SceneKit)
import CoreGraphics
import Foundation
import SceneKit

/// Draws each piece in code at its real size, in a form that suits its kind (FR-O5). Parts are built in the
/// piece's own frame: width along x, depth along z with the front at +z, y up, origin on the floor. Every
/// part stays inside the size the product states; only a rug extends past it, flat on the floor.
struct FurnitureBuilder {
    let w: Double
    let d: Double
    let h: Double
    let category: String
    let look: ResolvedLook
    /// How far a rug may reach in front: the piece's own clear space.
    let rugReach: Double
    let root = SCNNode()

    static let rugName = "rug"

    static func material(_ f: Finish) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = CGColor(srgbRed: f.r, green: f.g, blue: f.b, alpha: 1)
        m.roughness.contents = f.roughness
        m.metalness.contents = f.metal
        return m
    }

    /// A box by its centre in x and z, and its bottom in y.
    func box(_ x: Double, _ y: Double, _ z: Double, _ sw: Double, _ sh: Double, _ sd: Double, _ f: Finish, chamfer: Double = 0.006, name: String? = nil) {
        let g = SCNBox(width: CGFloat(max(sw, 0.002)), height: CGFloat(max(sh, 0.002)), length: CGFloat(max(sd, 0.002)),
                       chamferRadius: CGFloat(min(chamfer, min(sw, sh, sd) / 2.5)))
        g.materials = [Self.material(f)]
        let node = SCNNode(geometry: g)
        node.position = SCNVector3(Float(x), Float(y + sh / 2), Float(z))
        node.name = name
        root.addChildNode(node)
    }

    func cylinder(_ x: Double, _ y: Double, _ z: Double, _ r: Double, _ sh: Double, _ f: Finish, top: Double? = nil) {
        let geometry: SCNGeometry
        if let top {
            geometry = SCNCone(topRadius: CGFloat(max(top, 0.002)), bottomRadius: CGFloat(max(r, 0.002)), height: CGFloat(max(sh, 0.002)))
        } else {
            geometry = SCNCylinder(radius: CGFloat(max(r, 0.002)), height: CGFloat(max(sh, 0.002)))
        }
        geometry.materials = [Self.material(f)]
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(Float(x), Float(y + sh / 2), Float(z))
        root.addChildNode(node)
    }

    func sphere(_ x: Double, _ y: Double, _ z: Double, _ r: Double, _ f: Finish) {
        let g = SCNSphere(radius: CGFloat(max(r, 0.002)))
        g.materials = [Self.material(f)]
        let node = SCNNode(geometry: g)
        node.position = SCNVector3(Float(x), Float(y), Float(z))
        root.addChildNode(node)
    }

    /// Four legs under a top.
    func legs(height: Double, inset: Double = 0.04, thickness: Double = 0.04, _ f: Finish) {
        let x = w / 2 - inset - thickness / 2, z = d / 2 - inset - thickness / 2
        for (sx, sz) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            box(sx * x, 0, sz * z, thickness, height, thickness, f, chamfer: 0.002)
        }
    }

    func build() -> SCNNode {
        switch category {
        case "bed": bed()
        case "sofa": sofa(seats: w > 1.8 ? 3 : 2)
        case "armchair": sofa(seats: 1)
        case "chair": chair()
        case "bench": bench()
        case "desk": desk()
        case "dining_table": table(thickness: 0.04)
        case "coffee_table", "side_table": table(thickness: 0.03)
        case "nightstand": drawers(rows: 2, onLegs: true)
        case "dresser": drawers(rows: w > 1.1 ? 3 : 3, columns: w > 1.1 ? 2 : 1, onLegs: true)
        case "wardrobe": wardrobe()
        case "bookshelf": bookshelf()
        case "storage", "tv_stand": cabinet()
        case "lamp": lamp()
        case "plant": plant()
        default: box(0, 0, 0, w, h, d, look.body)
        }
        return root
    }

    private func rug(under: Bool) {
        guard rugReach > 0.05 else { return }
        let reach = min(rugReach * 0.9, 0.5)
        box(0, 0, d / 2 - d * 0.15 + reach / 2, w * 0.96, 0.008, d * 0.3 + reach, look.accent.scaled(0.95), chamfer: 0, name: Self.rugName)
    }

    private func bed() {
        let frameH = min(0.3, h * 0.34), mattress = min(0.2, h * 0.24), head = 0.06
        box(0, 0.05, 0.02, w, frameH - 0.05, d - 0.04 - head + 0.0, look.body)
        legs(height: 0.05, inset: 0.03, thickness: 0.05, look.body)
        box(0, 0, -d / 2 + head / 2, w, h, head, look.body)
        let top = frameH + mattress
        box(0, frameH, head / 2, w - 0.04, mattress, d - head - 0.04, look.bedding, chamfer: 0.04)
        // A throw across the foot, and pillows at the head.
        box(0, top - 0.04, d * 0.28, w - 0.02, 0.05, d * 0.3, look.accent, chamfer: 0.02)
        for sign in [-1.0, 1.0] {
            box(sign * w * 0.23, top, -d / 2 + head + 0.2, w * 0.4, min(0.12, h - top), 0.36, look.bedding.scaled(0.97), chamfer: 0.04)
        }
        rug(under: true)
    }

    private func sofa(seats: Int) {
        let arm = min(0.14, w * 0.12), seatH = min(0.42, h * 0.55), back = min(0.2, d * 0.24)
        legs(height: 0.08, inset: 0.05, thickness: 0.04, look.body)
        box(0, 0.08, 0, w, seatH - 0.2, d, look.upholstery, chamfer: 0.03)
        box(0, 0.08, -d / 2 + back / 2, w, h - 0.08, back, look.upholstery, chamfer: 0.04)
        for sign in [-1.0, 1.0] { box(sign * (w / 2 - arm / 2), 0.08, 0, arm, seatH + 0.12 - 0.08, d, look.upholstery, chamfer: 0.04) }
        // Seat and back cushions, one per seat.
        let inner = w - 2 * arm, each = inner / Double(seats)
        let cushion = look.upholstery.scaled(1.06)
        for i in 0..<seats {
            let x = -inner / 2 + each * (Double(i) + 0.5)
            box(x, seatH - 0.12, back / 2, each - 0.015, 0.12, d - back - 0.01, cushion, chamfer: 0.03)
            box(x, seatH, -d / 2 + back + 0.07, each - 0.03, min(0.28, h - seatH), 0.13, cushion, chamfer: 0.04)
        }
        // A cushion from the design's look.
        box(-inner / 2 + 0.18, seatH, 0, 0.3, min(0.26, h - seatH), 0.12, look.accent, chamfer: 0.04)
        if seats > 1 { rug(under: true) }
    }

    private func chair() {
        let seat = h * 0.56, t = 0.03
        legs(height: seat - t, inset: 0.02, thickness: 0.03, look.body)
        box(0, seat - t, 0, w, t + 0.02, d, look.upholstery.scaled(1.0), chamfer: 0.012)
        box(0, seat, -d / 2 + 0.015, w, h - seat, 0.03, look.body, chamfer: 0.008)
    }

    private func bench() {
        legs(height: h - 0.05, inset: 0.05, thickness: 0.04, look.body)
        box(0, h - 0.07, 0, w, 0.05, d, look.body)
        box(0, h - 0.03, 0, w - 0.02, 0.03, d - 0.02, look.upholstery, chamfer: 0.012)
    }

    private func desk() {
        legs(height: h - 0.03, inset: 0.03, thickness: 0.04, look.frame)
        box(0, h - 0.03, 0, w, 0.03, d, look.body)
        box(w / 2 - 0.2, h - 0.18, 0, 0.34, 0.15, d - 0.06, look.body.scaled(0.92))
        box(w / 2 - 0.2, h - 0.11, d / 2 - 0.028, 0.12, 0.012, 0.012, look.hardware, chamfer: 0.002)
    }

    private func table(thickness: Double) {
        if look.rounded {
            let r = min(w, d) / 2
            cylinder(0, h - thickness, 0, r, thickness, look.body)
            cylinder(0, 0, 0, 0.035, h - thickness, look.frame)
            cylinder(0, 0, 0, r * 0.55, 0.02, look.frame)
        } else {
            legs(height: h - thickness, inset: 0.04, thickness: 0.04, look.frame)
            box(0, h - thickness, 0, w, thickness, d, look.body)
        }
    }

    private func drawers(rows: Int, columns: Int = 1, onLegs: Bool) {
        let foot = onLegs ? min(0.1, h * 0.15) : 0
        if onLegs { legs(height: foot, inset: 0.03, thickness: 0.03, look.frame) }
        box(0, foot, -0.01, w, h - foot, d - 0.02, look.body)
        let rowH = (h - foot - 0.04) / Double(rows), colW = (w - 0.04) / Double(columns)
        for r in 0..<rows {
            for c in 0..<columns {
                let x = -w / 2 + 0.02 + colW * (Double(c) + 0.5), y = foot + 0.02 + rowH * Double(r)
                box(x, y + 0.006, d / 2 - 0.012, colW - 0.012, rowH - 0.012, 0.02, look.body.scaled(1.08), chamfer: 0.003)
                box(x, y + rowH / 2, d / 2 - 0.002 - 0.002, min(0.1, colW * 0.4), 0.012, 0.004, look.hardware, chamfer: 0.001)
            }
        }
    }

    private func wardrobe() {
        box(0, 0.03, -0.01, w, h - 0.03, d - 0.02, look.body)
        box(0, 0, -0.01, w - 0.04, 0.03, d - 0.05, look.body.scaled(0.6), chamfer: 0)
        let doors = w > 1.2 ? 3 : 2, each = (w - 0.03) / Double(doors)
        for i in 0..<doors {
            let x = -w / 2 + 0.015 + each * (Double(i) + 0.5)
            box(x, 0.05, d / 2 - 0.012, each - 0.008, h - 0.07, 0.02, look.body.scaled(1.06), chamfer: 0.003)
            box(x + (i % 2 == 0 ? 1 : -1) * (each / 2 - 0.04), h * 0.45, d / 2 - 0.004, 0.012, 0.16, 0.006, look.hardware, chamfer: 0.002)
        }
    }

    private func bookshelf() {
        let side = 0.025, shelves = max(3, Int(h / 0.36))
        for sign in [-1.0, 1.0] { box(sign * (w / 2 - side / 2), 0, 0, side, h, d, look.body, chamfer: 0.002) }
        box(0, 0, -d / 2 + 0.006, w - 2 * side, h, 0.012, look.body.scaled(0.8), chamfer: 0)
        let gap = (h - side) / Double(shelves)
        let colours = [look.accent, look.bedding, look.accent.scaled(0.7), look.body.scaled(0.6)]
        for s in 0...shelves {
            let y = gap * Double(s)
            box(0, y, 0, w - 2 * side, side, d, look.body, chamfer: 0.002)
            guard s < shelves else { continue }
            // Books on every other shelf, leaving room to breathe.
            guard s % 2 == 1 else { continue }
            var x = -w / 2 + side + 0.03, n = 0
            while x < w * 0.1 {
                let t = 0.025 + 0.012 * Double(n % 3)
                box(x + t / 2, y + side, 0.01, t, gap * (0.6 + 0.08 * Double(n % 4)), d * 0.7, colours[n % colours.count], chamfer: 0.002)
                x += t + 0.003
                n += 1
            }
        }
    }

    private func cabinet() {
        let foot = min(0.12, h * 0.2)
        legs(height: foot, inset: 0.05, thickness: 0.03, look.frame)
        box(0, foot, -0.01, w, h - foot, d - 0.02, look.body)
        let doors = w > 1.5 ? 4 : w > 0.9 ? 3 : 2, each = (w - 0.03) / Double(doors)
        for i in 0..<doors {
            let x = -w / 2 + 0.015 + each * (Double(i) + 0.5)
            box(x, foot + 0.015, d / 2 - 0.012, each - 0.008, h - foot - 0.03, 0.02, look.body.scaled(1.07), chamfer: 0.003)
            box(x, h - 0.08, d / 2 - 0.004, 0.09, 0.012, 0.006, look.hardware, chamfer: 0.002)
        }
    }

    private func lamp() {
        let r = min(w, d) / 2, shade = min(0.34, h * 0.24)
        cylinder(0, 0, 0, r * 0.65, 0.03, look.frame)
        cylinder(0, 0.03, 0, 0.012, h - shade - 0.03, look.frame)
        cylinder(0, h - shade, 0, r, shade, Finish(0.95, 0.9, 0.8, roughness: 0.9), top: r * 0.72)
    }

    private func plant() {
        let r = min(w, d) / 2, pot = min(0.34, h * 0.28)
        cylinder(0, 0, 0, r * 0.62, pot, look.bedding.scaled(0.9), top: r * 0.8)
        cylinder(0, pot, 0, 0.02, (h - pot) * 0.55, Finish(0.32, 0.22, 0.14))
        let leaf = Finish(0.22, 0.42, 0.2, roughness: 0.75)
        let crown = min(r * 0.62, (h - pot) * 0.28)
        for (dx, dy, dz) in [(0.0, 0.0, 0.0), (0.55, -0.45, 0.2), (-0.5, -0.55, -0.2), (0.1, -0.7, -0.55), (-0.15, -0.35, 0.55)] {
            sphere(dx * r * 0.6, h - crown + dy * crown, dz * r * 0.6, crown, dy == 0 ? leaf : leaf.scaled(1.15))
        }
    }
}
#endif
