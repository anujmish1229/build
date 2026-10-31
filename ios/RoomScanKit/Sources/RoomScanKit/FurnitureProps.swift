#if canImport(SceneKit)
import Foundation
import SceneKit

/// The holiday decorations, drawn in code like the furniture and kept inside their stated size.
extension FurnitureBuilder {
    private var gold: Finish { Finish(0.86, 0.66, 0.26, roughness: 0.28, metal: 0.95) }
    private var ivory: Finish { Finish(0.93, 0.89, 0.78, roughness: 0.7) }
    private var flame: Finish { Finish(1, 0.62, 0.16, roughness: 0.9, glow: 1.5) }
    private var coal: Finish { Finish(0.07, 0.06, 0.06, roughness: 0.8) }
    private var red: Finish { Season.christmas.red }
    private var pine: Finish { Season.christmas.green }

    /// A candle with a lit flame on top, standing on `y`.
    func candle(_ x: Double, _ y: Double, _ z: Double, height: Double, radius: Double = 0.016, wax: Finish? = nil) {
        cylinder(x, y, z, radius, height, wax ?? ivory)
        ellipsoid(x, y + height + 0.022, z, 0.012, 0.024, 0.012, flame)
    }

    /// A short swag of greenery with small lights, along x.
    func garland(from x0: Double, to x1: Double, y: Double, z: Double, sag: Double = 0, thickness: Double = 0.05) {
        let steps = max(Int(abs(x1 - x0) / 0.1), 2)
        let lights = [Finish(1, 0.82, 0.45, glow: 1.2), Finish(0.82, 0.08, 0.1, roughness: 0.3, glow: 0.3), Finish(0.86, 0.66, 0.26, roughness: 0.3, metal: 0.9)]
        for i in 0...steps {
            let t = Double(i) / Double(steps), x = x0 + (x1 - x0) * t
            let dip = sag * 4 * t * (1 - t)
            ellipsoid(x, y - dip, z, thickness * 1.25, thickness * 0.85, thickness * 0.85, pine.scaled(i % 2 == 0 ? 1 : 1.3))
            if i % 2 == 1 { sphere(x, y - dip + thickness * 0.1, z + thickness * 0.72, 0.016, lights[(i / 2) % lights.count]) }
        }
    }

    /// A wrapped box with a ribbon each way and a bow.
    func gift(_ x: Double, _ y: Double, _ z: Double, _ sw: Double, _ sh: Double, _ sd: Double, _ paper: Finish, _ ribbon: Finish) {
        box(x, y, z, sw, sh, sd, paper, chamfer: 0.004)
        box(x, y, z, sw + 0.002, sh + 0.002, min(0.03, sd * 0.2), ribbon, chamfer: 0)
        box(x, y, z, min(0.03, sw * 0.2), sh + 0.002, sd + 0.002, ribbon, chamfer: 0)
        sphere(x, y + sh + 0.008, z, 0.018, ribbon)
    }

    // MARK: Both holidays

    func fireplace() {
        let haunted = season == .halloween
        let stone = haunted ? Finish(0.2, 0.19, 0.22, roughness: 0.95) : Finish(0.82, 0.76, 0.68, roughness: 0.9)
        let mantelH = h - 0.08, surroundD = d * 0.7, backZ = -d / 2 + surroundD / 2
        // The hearth slab, the surround around a dark firebox, and a mantel shelf.
        box(0, 0, 0, w, 0.06, d, stone.scaled(0.8), chamfer: 0.004)
        box(0, 0.06, backZ, w * 0.92, mantelH - 0.06, surroundD, stone)
        let openW = w * 0.52, openH = (mantelH - 0.06) * 0.62, front = backZ + surroundD / 2
        box(0, 0.06, front - 0.004, openW + 0.08, openH + 0.05, 0.012, stone.scaled(0.72), chamfer: 0.002)
        box(0, 0.06, front - 0.002, openW, openH, 0.012, coal, chamfer: 0)
        // Courses of stone across the surround, for texture.
        var course = 0.2
        while course < mantelH - 0.04 {
            let beside = course < openH + 0.1
            for sign in [-1.0, 1.0] where beside {
                box(sign * (openW / 2 + (w * 0.92 - openW) / 4), course, front - 0.003, (w * 0.92 - openW) / 2 - 0.06, 0.012, 0.01, stone.scaled(0.8), chamfer: 0)
            }
            if !beside { box(0, course, front - 0.003, w * 0.86, 0.012, 0.01, stone.scaled(0.8), chamfer: 0) }
            course += 0.17
        }
        box(0, mantelH, -d / 2 + (d * 0.82) / 2, w, 0.08, d * 0.82, look.body.scaled(haunted ? 0.5 : 1), chamfer: 0.006)
        // Logs and a fire, green when haunted.
        let log = Finish(0.24, 0.14, 0.09, roughness: 0.9)
        limb(SIMD3(-openW * 0.32, 0.09, front - 0.01), SIMD3(openW * 0.3, 0.1, front - 0.02), 0.03, log)
        limb(SIMD3(-openW * 0.26, 0.11, front - 0.025), SIMD3(openW * 0.34, 0.09, front - 0.012), 0.028, log)
        let fire = haunted ? Finish(0.28, 0.95, 0.42, roughness: 0.9, glow: 1.5) : flame
        let core = haunted ? Finish(0.75, 1, 0.55, roughness: 0.9, glow: 1.5) : Finish(1, 0.88, 0.42, roughness: 0.9, glow: 1.6)
        for (x, height) in [(-0.14, 0.2), (0.0, 0.28), (0.13, 0.17)] {
            cylinder(x, 0.1, front - 0.02, 0.05, height, fire, top: 0.004)
            cylinder(x, 0.1, front - 0.012, 0.025, height * 0.6, core, top: 0.003)
        }
        glowLight(0, 0.3, d / 2 + 0.12, haunted ? (0.35, 1, 0.5) : (1, 0.55, 0.22), intensity: haunted ? 150 : 170, reach: 3.2)

        let top = mantelH + 0.08, shelfZ = -d / 2 + d * 0.4, room = max(h - top, 0.002)
        switch season {
        case .christmas:
            garland(from: -w / 2 + 0.06, to: w / 2 - 0.06, y: top + min(room * 0.2, 0.012), z: shelfZ + 0.06, thickness: 0.012 + room * 0.1)
            // Stockings hung along the mantel.
            for (i, x) in [-0.42, -0.14, 0.14, 0.42].enumerated() {
                let colour = i % 2 == 0 ? red : pine.scaled(1.2)
                let front = -d / 2 + d * 0.82 + 0.02
                box(x, mantelH - 0.3, front, 0.1, 0.26, 0.03, colour, chamfer: 0.01)
                box(x + 0.05, mantelH - 0.31, front, 0.17, 0.08, 0.03, colour, chamfer: 0.015)
                box(x, mantelH - 0.08, front, 0.12, 0.07, 0.035, ivory, chamfer: 0.012)
            }
        case .halloween:
            let cobweb = Finish(0.8, 0.8, 0.82, roughness: 0.9)
            for i in 0..<4 { limb(SIMD3(-w / 2 + 0.02, mantelH - 0.34 + 0.08 * Double(i), d * 0.18), SIMD3(-w / 2 + 0.34 - 0.07 * Double(i), mantelH, d * 0.18), 0.002, cobweb) }
            for (x, drop) in [(-0.46, 0.2), (0.3, 0.14), (0.52, 0.24)] {
                limb(SIMD3(x, mantelH, d * 0.2), SIMD3(x, mantelH - drop, d * 0.2), 0.0025, cobweb)
                ellipsoid(x, mantelH - drop, d * 0.2, 0.018, 0.018, 0.018, coal)
            }
        default: break
        }
    }

    // MARK: Christmas

    func christmasTree() {
        let r = min(w, d) / 2, cx = 0.0, cz = 0.0
        cylinder(cx, 0, cz, r * 0.82, 0.015, red.scaled(0.95))
        cylinder(cx, 0.015, cz, r * 0.18, 0.14, Finish(0.16, 0.1, 0.07))
        cylinder(cx, 0.015, cz, r * 0.3, 0.2, gold, top: r * 0.22)
        let starR = 0.07, topY = h - starR * 2.05, base = 0.2, tiers = 6
        let span = topY - base
        for i in 0..<tiers {
            let t = Double(i) / Double(tiers)
            let y = base + span * t * 0.9
            let height = span * (0.34 - 0.13 * t)
            let radius = r * (1 - t * 0.86) * 0.97
            let top = min(y + height, topY)
            var needles = pine.scaled(0.92 + 0.15 * Double(i % 2))
            needles.roughness = 0.98
            cylinder(cx, y, cz, radius, top - y, needles, top: radius * 0.12)
            // Ornaments and small lights around each tier's skirt.
            let count = max(5, Int(radius / r * 13))
            for k in 0..<count {
                let angle = Double(k) / Double(count) * 2 * .pi + Double(i) * 0.7
                let spot = 0.97 * radius, yy = y + 0.02
                let lit = k % 2 == 0
                if lit {
                    let colour = [Finish(1, 0.84, 0.45, glow: 1.3), Finish(1, 0.36, 0.26, glow: 1.2), Finish(0.5, 0.82, 1, glow: 1.2)][(k / 2 + i) % 3]
                    sphere(cos(angle) * spot, yy, sin(angle) * spot, 0.012, colour)
                } else {
                    let colour = [Finish(0.75, 0.05, 0.08, roughness: 0.18, metal: 0.45), gold, Finish(0.86, 0.86, 0.9, roughness: 0.2, metal: 0.85)][(k + i) % 3]
                    let size = 0.024 + 0.018 * (1 - t)
                    sphere(cos(angle) * (spot - size * 0.3), yy - size * 0.2, sin(angle) * (spot - size * 0.3), size, colour)
                }
            }
            // A ribbon of gold on the higher tiers.
            if i % 2 == 0 { ring(cx, y + height * 0.42, cz, radius * 0.62, 0.006, gold) }
        }
        // A star on top.
        let star = Finish(1, 0.82, 0.32, roughness: 0.25, metal: 0.4, glow: 1.25)
        let cy = h - starR
        sphere(cx, cy, cz, starR * 0.5, star)
        for angle in stride(from: 0.0, to: Double.pi, by: Double.pi / 3) {
            limb(SIMD3(cx - cos(angle) * starR, cy - sin(angle) * starR, cz), SIMD3(cx + cos(angle) * starR, cy + sin(angle) * starR, cz), 0.012, star)
        }
        // Presents in the corners of its footprint, under the branches.
        let inset = max(w, d) / 2 - 0.15
        gift(inset * 0.9, 0.015, inset * 0.72, 0.26, 0.2, 0.26, red, gold)
        gift(-inset * 0.85, 0.015, inset * 0.82, 0.3, 0.16, 0.22, pine.scaled(1.4), ivory)
        gift(inset * 0.25, 0.015, inset * 0.98, 0.18, 0.24, 0.18, gold, red)
    }

    func giftPile() {
        let s = min(w, d)
        gift(-w * 0.26, 0, -d * 0.12, w * 0.42, h * 0.62, s * 0.66, red, gold)
        gift(w * 0.27, 0, -d * 0.18, w * 0.36, h * 0.5, s * 0.56, Finish(0.86, 0.84, 0.78, roughness: 0.6), red)
        gift(w * 0.1, 0, d * 0.27, w * 0.28, h * 0.32, s * 0.38, pine.scaled(1.4), ivory)
        gift(-w * 0.3, h * 0.62, -d * 0.12, w * 0.2, h * 0.32, s * 0.3, gold, pine)
        gift(w * 0.27, h * 0.5, -d * 0.18, w * 0.16, h * 0.42, s * 0.25, red.scaled(1.2), ivory)
    }

    func nutcracker() {
        let r = min(w, d) / 2, u = h / 1.1
        cylinder(0, 0, 0, r * 0.95, 0.04 * u, gold)
        for sign in [-1.0, 1.0] {
            cylinder(sign * r * 0.34, 0.04 * u, 0, r * 0.28, 0.3 * u, coal)
            limb(SIMD3(sign * r * 0.6, 0.72 * u, 0), SIMD3(sign * r * 0.78, 0.46 * u, r * 0.25), r * 0.17, red)
            sphere(sign * r * 0.78, 0.45 * u, r * 0.25, r * 0.17, ivory)
        }
        cylinder(0, 0.34 * u, 0, r * 0.58, 0.42 * u, red, top: r * 0.48)
        cylinder(0, 0.5 * u, 0, r * 0.6, 0.03 * u, gold)
        box(0, 0.36 * u, r * 0.5, r * 0.14, 0.36 * u, 0.02, gold, chamfer: 0.002)
        sphere(0, 0.84 * u, 0, r * 0.42, Finish(0.92, 0.76, 0.62, roughness: 0.6))
        sphere(-r * 0.15, 0.87 * u, r * 0.38, r * 0.05, coal)
        sphere(r * 0.15, 0.87 * u, r * 0.38, r * 0.05, coal)
        box(0, 0.74 * u, r * 0.26, r * 0.5, 0.09 * u, r * 0.2, Finish(0.95, 0.95, 0.93, roughness: 0.95), chamfer: 0.012)
        cylinder(0, 0.91 * u, 0, r * 0.4, 0.15 * u, coal, top: r * 0.44)
        cylinder(0, 0.91 * u, 0, r * 0.44, 0.022 * u, gold)
        sphere(0, 1.0 * u, r * 0.38, r * 0.08, gold)
    }

    func reindeer() {
        let wire = Finish(0.86, 0.66, 0.26, roughness: 0.3, metal: 0.9, glow: 0.12)
        let bodyY = h * 0.56, bodyR = min(d / 2, h * 0.14)
        ellipsoid(-w * 0.07, bodyY, 0, w * 0.27, bodyR, bodyR * 0.9, wire)
        for (x, z) in [(-w * 0.26, -bodyR * 0.6), (-w * 0.26, bodyR * 0.6), (w * 0.14, -bodyR * 0.6), (w * 0.14, bodyR * 0.6)] {
            limb(SIMD3(x, bodyY - bodyR * 0.5, z * 0.7), SIMD3(x, 0.01, z), 0.012, wire)
        }
        let head = SIMD3(w * 0.3, h * 0.8, 0.0)
        limb(SIMD3(w * 0.1, bodyY + bodyR * 0.4, 0), head, 0.03, wire)
        ellipsoid(head.x + 0.04, head.y, 0, 0.08, 0.04, 0.035, wire)
        for sign in [-1.0, 1.0] {
            let base = SIMD3(head.x - 0.01, head.y + 0.03, sign * 0.02)
            let tip = SIMD3(min(w / 2 - 0.02, head.x + 0.07), h - 0.01, sign * min(d / 2 - 0.01, 0.12))
            limb(base, tip, 0.006, wire)
            limb((base + tip) / 2, SIMD3(head.x - 0.12, h * 0.94, sign * 0.1), 0.005, wire)
        }
        sphere(head.x + 0.115, head.y - 0.005, 0, 0.017, Finish(0.9, 0.08, 0.08, roughness: 0.3, glow: 0.9))
    }

    // MARK: Halloween

    /// One ribbed pumpkin on `y`. A carved one has a lit face looking along +z.
    func pumpkin(_ x: Double, _ y: Double, _ z: Double, _ r: Double, carved: Bool) {
        let orange = Season.halloween.red, ry = r * 0.82, cy = y + ry
        ellipsoid(x, cy, z, r * 0.8, ry, r * 0.8, orange.scaled(0.86))
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            ellipsoid(x + cos(a) * r * 0.5, cy, z + sin(a) * r * 0.5, r * 0.5, ry * 0.98, r * 0.5, orange.scaled(k % 2 == 0 ? 1 : 0.92))
        }
        limb(SIMD3(x, cy + ry * 0.9, z), SIMD3(x + r * 0.08, min(cy + ry * 1.22, cy + ry + 0.05), z), r * 0.09, Finish(0.26, 0.32, 0.12))
        guard carved else { return }
        let lit = Finish(1, 0.72, 0.15, roughness: 0.9, glow: 1.6), face = z + r * 0.97
        // Two eyes, a nose and a jagged grin.
        box(x - r * 0.32, cy + ry * 0.14, face, r * 0.24, r * 0.26, 0.012, lit, chamfer: 0.003)
        box(x + r * 0.32, cy + ry * 0.14, face, r * 0.24, r * 0.26, 0.012, lit, chamfer: 0.003)
        box(x, cy - ry * 0.06, face + 0.002, r * 0.13, r * 0.14, 0.012, lit, chamfer: 0.003)
        for k in -2...2 {
            let tooth = abs(k) % 2 == 0 ? r * 0.14 : r * 0.24
            box(x + Double(k) * r * 0.17, cy - ry * 0.5, face - abs(Double(k)) * r * 0.045, r * 0.15, tooth, 0.012, lit, chamfer: 0.003)
        }
    }

    func pumpkinPatch() {
        let big = min(d * 0.47, h / 2.65)
        pumpkin(-w * 0.2, 0, -d * 0.02, big, carved: true)
        pumpkin(-w * 0.2 + big * 0.1, big * 1.6, -d * 0.02, big * 0.5, carved: true)
        pumpkin(w * 0.25, 0, d * 0.08, big * 0.72, carved: true)
        pumpkin(w * 0.38, 0, -d * 0.3, big * 0.42, carved: false)
        pumpkin(w * 0.06, 0, d * 0.35, big * 0.32, carved: false)
        glowLight(0, h * 0.6, d, (1, 0.5, 0.12), intensity: 170, reach: 2.4)
    }

    func cauldron() {
        let r = min(w, d) / 2, iron = Finish(0.08, 0.08, 0.09, roughness: 0.42, metal: 0.72)
        let bowlY = h * 0.5, bowlR = r * 0.74
        for k in 0..<3 {
            let a = Double(k) / 3 * 2 * .pi + 0.5
            limb(SIMD3(cos(a) * r * 0.93, 0.01, sin(a) * r * 0.93), SIMD3(0, h - 0.015, 0), 0.014, Finish(0.17, 0.11, 0.08, roughness: 0.9))
        }
        ellipsoid(0, bowlY, 0, bowlR, bowlR * 0.74, bowlR, iron)
        ring(0, bowlY + bowlR * 0.56, 0, bowlR * 0.72, 0.022, iron)
        let brew = Finish(0.35, 0.96, 0.28, roughness: 0.5, glow: 1.25)
        cylinder(0, bowlY + bowlR * 0.54, 0, bowlR * 0.68, 0.012, brew)
        for (dx, dz, br) in [(-0.12, 0.05, 0.035), (0.08, -0.1, 0.045), (0.1, 0.12, 0.025), (-0.03, -0.04, 0.03)] {
            sphere(dx, bowlY + bowlR * 0.56 + br * 0.5, dz, br, brew)
        }
        // Coals and fire below.
        for k in 0..<5 {
            let a = Double(k) * 1.26
            sphere(cos(a) * r * 0.32, 0.035, sin(a) * r * 0.32, 0.038, k % 2 == 0 ? coal : Finish(1, 0.32, 0.05, glow: 1.2))
        }
        cylinder(0, 0.02, 0, 0.07, bowlY * 0.42, flame, top: 0.004)
        glowLight(0, h, 0, (0.4, 1, 0.3), intensity: 130, reach: 2)
    }

    func skeleton() {
        let bone = Finish(0.9, 0.87, 0.76, roughness: 0.75), u = h / 1.75, halfW = w / 2
        // On a small stand with a pole up its back, as a display skeleton is.
        cylinder(0, 0, 0, min(w, d) * 0.42, 0.025, coal)
        cylinder(0, 0.025, -0.05, 0.012, 1.42 * u, Finish(0.3, 0.3, 0.32, metal: 0.8))
        // Legs.
        for sign in [-1.0, 1.0] {
            limb(SIMD3(sign * 0.09, 0.9 * u, 0), SIMD3(sign * 0.11, 0.5 * u, 0.01), 0.018, bone)
            limb(SIMD3(sign * 0.11, 0.5 * u, 0.01), SIMD3(sign * 0.11, 0.07 * u, 0), 0.015, bone)
            sphere(sign * 0.11, 0.5 * u, 0.012, 0.027, bone)
            ellipsoid(sign * 0.11, 0.05 * u, 0.05, 0.035, 0.022, min(0.08, d / 2 - 0.05), bone)
        }
        // Hips, spine and ribs.
        ellipsoid(0, 0.94 * u, 0, 0.13, 0.055, 0.06, bone)
        limb(SIMD3(0, 0.94 * u, -0.01), SIMD3(0, 1.46 * u, -0.01), 0.015, bone)
        for i in 0..<6 {
            let y = (1.14 + 0.055 * Double(i)) * u, rib = 0.105 - 0.008 * abs(Double(i) - 3)
            ring(0, y, 0, rib, 0.007, bone)
        }
        // A wave with one arm, and the other at its side.
        limb(SIMD3(-0.15, 1.42 * u, 0), SIMD3(-halfW + 0.05, 1.12 * u, 0.04), 0.014, bone)
        limb(SIMD3(-halfW + 0.05, 1.12 * u, 0.04), SIMD3(-halfW + 0.07, 0.86 * u, 0.08), 0.012, bone)
        limb(SIMD3(0.15, 1.42 * u, 0), SIMD3(halfW - 0.04, 1.22 * u, 0.02), 0.014, bone)
        limb(SIMD3(halfW - 0.04, 1.22 * u, 0.02), SIMD3(halfW - 0.05, 1.46 * u, 0.06), 0.012, bone)
        sphere(halfW - 0.05, 1.49 * u, 0.06, 0.03, bone)
        limb(SIMD3(-0.15, 1.43 * u, -0.01), SIMD3(0.15, 1.43 * u, -0.01), 0.013, bone)
        // The skull.
        let skullY = 1.61 * u, skullR = 0.1 * u
        ellipsoid(0, skullY, 0, skullR * 0.92, skullR, skullR * 1.02, bone)
        box(0, skullY - skullR * 1.38, skullR * 0.32, skullR * 1.05, skullR * 0.5, skullR * 0.8, bone, chamfer: 0.012)
        let socket = Finish(0.03, 0.02, 0.03, roughness: 1)
        for sign in [-1.0, 1.0] { ellipsoid(sign * skullR * 0.38, skullY, skullR * 0.8, skullR * 0.25, skullR * 0.3, skullR * 0.24, socket) }
        box(0, skullY - skullR * 0.5, skullR * 0.92, skullR * 0.14, skullR * 0.22, 0.012, socket, chamfer: 0.002)
    }

    func candelabra() {
        let r = min(w, d) / 2, iron = Finish(0.08, 0.075, 0.08, roughness: 0.42, metal: 0.8)
        let candleH = 0.15, armY = h - candleH - 0.15, reach = r - 0.03
        cylinder(0, 0, 0, r * 0.72, 0.025, iron)
        cylinder(0, 0.025, 0, r * 0.3, 0.1, iron, top: 0.018)
        cylinder(0, 0.1, 0, 0.016, armY - 0.1, iron)
        sphere(0, armY * 0.55, 0, 0.04, iron)
        for x in [-reach, -reach / 2, 0, reach / 2, reach] {
            limb(SIMD3(0, armY, 0), SIMD3(x, armY + (abs(x) < 0.01 ? 0.02 : 0.03), 0), 0.009, iron)
            cylinder(x, armY + 0.02, 0, 0.032, 0.012, iron)
            candle(x, armY + 0.03, 0, height: candleH - 0.03, radius: 0.015)
        }
        glowLight(0, armY + 0.2, 0.15, (1, 0.62, 0.28), intensity: 120, reach: 2.4)
    }

    func tombstones() {
        let stone = Finish(0.42, 0.42, 0.45, roughness: 0.95)
        let carve = Finish(0.17, 0.17, 0.19, roughness: 1)
        // Mounds of earth, then a rounded stone, a square one and a cross.
        box(0, 0, 0, w, 0.04, d, Finish(0.14, 0.1, 0.07, roughness: 1), chamfer: 0.015)
        func arched(_ x: Double, _ width: Double, _ height: Double, _ shade: Double) {
            let rise = width / 2
            box(x, 0.04, 0, width, height - rise - 0.04, d * 0.42, stone.scaled(shade), chamfer: 0.006)
            let g = SCNCylinder(radius: CGFloat(rise), height: CGFloat(d * 0.42))
            g.materials = [Self.material(stone.scaled(shade))]
            let top = SCNNode(geometry: g)
            top.position = SCNVector3(Float(x), Float(height - rise), 0)
            top.eulerAngles.x = .pi / 2
            root.addChildNode(top)
            let face = d * 0.21 + 0.002
            box(x, height * 0.55, face, width * 0.5, height * 0.05, 0.004, carve, chamfer: 0)
            for row in 0..<2 { box(x, height * (0.34 + 0.09 * Double(row)), face, width * 0.42, 0.012, 0.004, carve, chamfer: 0) }
        }
        arched(-w * 0.28, w * 0.36, h, 1.0)
        arched(w * 0.08, w * 0.26, h * 0.72, 0.85)
        // The cross.
        let x = w * 0.36
        box(x, 0.04, 0, 0.07, h * 0.8 - 0.04, 0.07, stone.scaled(0.92), chamfer: 0.006)
        box(x, h * 0.56, 0, 0.24, 0.07, 0.07, stone.scaled(0.92), chamfer: 0.006)
    }

    func spookyTree() {
        let r = min(w, d) / 2
        let bark = Finish(0.05, 0.04, 0.05, roughness: 0.85)
        cylinder(0, 0, 0, r * 0.55, 0.26, Finish(0.1, 0.08, 0.09, roughness: 0.7), top: r * 0.68)
        cylinder(0, 0.26, 0, r * 0.62, 0.012, Finish(0.1, 0.07, 0.05, roughness: 1))
        // A gnarled trunk, then branches forking twice, all from a fixed table so it never changes.
        let fork = SIMD3(0.03, h * 0.5, 0.01)
        limb(SIMD3(0, 0.26, 0), SIMD3(0.04, h * 0.3, -0.02), 0.05, bark)
        limb(SIMD3(0.04, h * 0.3, -0.02), fork, 0.04, bark)
        let bough: [(Double, Double, Double)] = [(0.75, 0.74, 0.2), (-0.72, 0.72, -0.2), (0.2, 0.86, -0.7), (-0.15, 0.8, 0.72), (0.35, 0.94, 0.3)]
        var tips: [SIMD3<Double>] = []
        for (i, b) in bough.enumerated() {
            let end = SIMD3(b.0 * r * 0.75, h * b.1, b.2 * r * 0.75)
            limb(fork, end, 0.024, bark)
            for (j, turn) in [-0.55, 0.65].enumerated() {
                let c = cos(turn + Double(i)), s = sin(turn + Double(i))
                let raw = SIMD3(end.x + c * r * 0.3, min(end.y + h * (0.08 + 0.03 * Double(j)), h - 0.015), end.z + s * r * 0.3)
                let tip = SIMD3(max(min(raw.x, r - 0.015), -r + 0.015), raw.y, max(min(raw.z, r - 0.015), -r + 0.015))
                limb(end, tip, 0.011, bark)
                tips.append(tip)
            }
        }
        // Little lanterns, and two sleeping bats.
        let lit = Finish(1, 0.55, 0.12, roughness: 0.9, glow: 1.5)
        for tip in tips.enumerated().filter({ $0.offset % 3 == 0 }).map(\.element) {
            let at = (tip + SIMD3(0, -0.02, 0))
            limb(tip, SIMD3(at.x, at.y - 0.05, at.z), 0.002, bark)
            sphere(at.x, at.y - 0.09, at.z, 0.035, lit)
        }
        for tip in tips.enumerated().filter({ $0.offset % 3 == 1 }).prefix(2).map(\.element) {
            ellipsoid(tip.x, tip.y - 0.06, tip.z, 0.028, 0.055, 0.022, coal)
        }
        glowLight(0, h * 0.7, r, (1, 0.5, 0.15), intensity: 70, reach: 2)
    }
}
#endif
