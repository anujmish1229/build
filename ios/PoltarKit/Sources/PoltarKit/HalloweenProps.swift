#if canImport(SceneKit)
import CoreGraphics
import Foundation
import SceneKit
import simd

/// The Halloween props and wall decor of Resources/halloween.json, each in its own forms: slab, cross and
/// obelisk tombstones, carved and talking pumpkins, posters, neon signs, string lights, LED strips. Ported from
/// the private-uoft app, whose materials are built differently, so this holds the few finish and look types
/// those models were written against and turns them into this app's materials. Width runs along x, depth along
/// z with the front at +z, y up, origin at the middle of the footprint on the floor. What hangs on a wall has
/// its back at -d / 2 and draws itself at a real hanging height, above its footprint.
struct HalloweenPropBuilder {
    enum Palette { typealias RGB = (Double, Double, Double) }
    enum Kind { case wood, paint, fabric, knit, leather, velvet, stone, metal, patina, glass, lacquer, foliage, bulb, jute }

    struct Finish {
        var kind: Kind
        var rgb: Palette.RGB
        init(_ kind: Kind, _ rgb: Palette.RGB) { self.kind = kind; self.rgb = rgb }
        func with(_ kind: Kind) -> Finish { Finish(kind, rgb) }
        func scaled(_ f: Double) -> Finish { Finish(kind, (min(1, rgb.0 * f), min(1, rgb.1 * f), min(1, rgb.2 * f))) }
        var isSoft: Bool { [.fabric, .velvet, .knit, .leather].contains(kind) }
        var isMetal: Bool { kind == .metal || kind == .patina }
    }

    enum Finishes {
        static let table: [String: Finish] = [
            "black": Finish(.paint, (0.08, 0.08, 0.09)), "black metal": Finish(.metal, (0.09, 0.09, 0.1)), "black-brown": Finish(.paint, (0.13, 0.09, 0.07)),
            "bone": Finish(.stone, (0.89, 0.86, 0.76)), "bone white": Finish(.paint, (0.89, 0.86, 0.76)), "burlap": Finish(.jute, (0.72, 0.62, 0.45)),
            "canvas": Finish(.fabric, (0.76, 0.72, 0.62)), "charcoal": Finish(.paint, (0.17, 0.17, 0.19)), "cheesecloth": Finish(.fabric, (0.93, 0.92, 0.88)),
            "chrome": Finish(.metal, (0.8, 0.8, 0.82)), "corpse": Finish(.leather, (0.55, 0.58, 0.47)), "cream": Finish(.fabric, (0.93, 0.89, 0.8)),
            "dark brown": Finish(.wood, (0.3, 0.2, 0.13)), "ebony": Finish(.wood, (0.12, 0.09, 0.08)), "glass": Finish(.glass, (0.78, 0.84, 0.86)),
            "jute": Finish(.jute, (0.72, 0.6, 0.42)), "latex": Finish(.leather, (0.74, 0.58, 0.5)), "orange": Finish(.paint, (0.9, 0.45, 0.08)),
            "paper": Finish(.fabric, (0.96, 0.93, 0.86)), "pink": Finish(.paint, (0.92, 0.66, 0.7)), "pumpkin": Finish(.paint, (0.88, 0.42, 0.1)),
            "purple": Finish(.paint, (0.4, 0.22, 0.45)), "red": Finish(.paint, (0.62, 0.1, 0.1)), "resin": Finish(.stone, (0.74, 0.72, 0.68)),
            "blood red": Finish(.paint, (0.42, 0.05, 0.05)), "sky blue": Finish(.paint, (0.55, 0.76, 0.9)), "slime green": Finish(.paint, (0.45, 0.76, 0.16)),
            "smoked glass": Finish(.glass, (0.2, 0.2, 0.22)), "steel": Finish(.metal, (0.62, 0.63, 0.65)), "stone": Finish(.stone, (0.46, 0.46, 0.46)),
            "straw": Finish(.jute, (0.8, 0.68, 0.38)), "white": Finish(.paint, (0.94, 0.94, 0.92)), "witch purple": Finish(.paint, (0.26, 0.1, 0.34)),
            "wrought iron": Finish(.metal, (0.13, 0.13, 0.14)),
        ]
        static func named(_ name: String) -> Finish? { table[name] }
    }

    struct Kit {
        let wood = Finishes.table["ebony"]!
        let metal = Finishes.table["wrought iron"]!
        let art: [Palette.RGB] = [(0.72, 0.33, 0.07), (0.26, 0.1, 0.34), (0.12, 0.12, 0.13)]
    }

    struct Look {
        var body: Finish
        var upholstery: Finish
        var form: String?
        var details: [String]
        var hasOwnBody: Bool
        var entryHasNoBody: Bool { !hasOwnBody }
    }

    let w: Double, d: Double, h: Double
    let category: String
    let kit = Kit()
    let look: Look
    let seed: UInt64
    let node = SCNNode()

    init(entry: CatalogEntry, w: Double, d: Double, h: Double) {
        self.w = w; self.d = d; self.h = h
        category = entry.category
        let own = entry.look?.body.flatMap { Finishes.named($0) }
        look = Look(body: own ?? kit.wood, upholstery: entry.look?.upholstery.flatMap { Finishes.named($0) } ?? Finish(.velvet, (0.26, 0.1, 0.34)),
                    form: entry.look?.form, details: entry.look?.details ?? [], hasOwnBody: own != nil)
        // The same prop always gets the same small variations.
        seed = entry.catalogID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    func build() -> SCNNode {
        switch category {
        case "skeleton": skeleton()
        case "reaper": reaper()
        case "ghost": ghost()
        case "groundbreaker": groundbreaker()
        case "tombstone": tombstone()
        case "cauldron": cauldron()
        case "jack_o_lantern": jackOLantern()
        case "fog_machine": fogMachine()
        case "prop_light": propLight()
        case "gore": gore()
        case "spider": spider()
        case "cobweb": cobweb()
        case "coffin": coffin()
        case "candelabra": candelabra()
        case "curio": curio()
        case "fence": fence()
        case "tree": tree()
        case "poster": poster()
        case "neon_sign": neonSign()
        case "string_lights": stringLights()
        case "led_strip": ledStrip()
        case "projector": projector()
        default: box(w, h, d, bodyM, 0, h / 2, 0)
        }
        return node
    }

    // MARK: materials

    private func m(_ f: Finish) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = CGColor(srgbRed: f.rgb.0, green: f.rgb.1, blue: f.rgb.2, alpha: 1)
        let (roughness, metal): (Double, Double)
        switch f.kind {
        case .metal: (roughness, metal) = (0.35, 0.9)
        case .patina: (roughness, metal) = (0.55, 0.7)
        case .glass: (roughness, metal) = (0.1, 0.1)
        case .lacquer: (roughness, metal) = (0.25, 0)
        case .paint: (roughness, metal) = (0.5, 0)
        case .leather: (roughness, metal) = (0.45, 0)
        case .wood: (roughness, metal) = (0.65, 0)
        case .stone, .foliage: (roughness, metal) = (0.9, 0)
        case .fabric, .knit, .velvet, .jute, .bulb: (roughness, metal) = (0.92, 0)
        }
        material.roughness.contents = roughness
        material.metalness.contents = metal
        return material
    }
    private var bodyM: SCNMaterial { m(look.body) }
    private var frameM: SCNMaterial { m(kit.metal) }
    private var softM: SCNMaterial { m(look.upholstery) }
    private var metalM: SCNMaterial { m(kit.metal) }
    private func glow(_ rgb: Palette.RGB = (1, 0.86, 0.6), strength: Double = 0.9) -> SCNMaterial {
        let mat = m(Finish(.bulb, rgb))
        mat.emission.contents = CGColor(srgbRed: rgb.0 * strength, green: rgb.1 * strength, blue: rgb.2 * strength, alpha: 1)
        return mat
    }

    // MARK: primitives (all direct children)

    @discardableResult
    private func add(_ g: SCNGeometry, _ mat: SCNMaterial, _ x: Double, _ y: Double, _ z: Double,
                     rotate: SCNVector3? = nil, name: String? = nil) -> SCNNode {
        g.materials = [mat]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y, z)
        if let rotate { n.eulerAngles = rotate }
        n.name = name
        node.addChildNode(n)
        return n
    }

    @discardableResult
    private func box(_ bw: Double, _ bh: Double, _ bd: Double, _ mat: SCNMaterial, _ x: Double, _ y: Double, _ z: Double,
                     round: Double = 0.004, rotate: SCNVector3? = nil, name: String? = nil) -> SCNNode {
        let r = min(round, min(bw, bh, bd) / 2 * 0.95)
        return add(SCNBox(width: max(bw, 0.001), height: max(bh, 0.001), length: max(bd, 0.001), chamferRadius: max(0, r)),
                   mat, x, y, z, rotate: rotate, name: name)
    }

    @discardableResult
    private func cyl(_ r: Double, _ ch: Double, _ mat: SCNMaterial, _ x: Double, _ y: Double, _ z: Double,
                     rotate: SCNVector3? = nil, name: String? = nil) -> SCNNode {
        add(SCNCylinder(radius: max(r, 0.001), height: max(ch, 0.001)), mat, x, y, z, rotate: rotate, name: name)
    }

    @discardableResult
    private func ball(_ r: Double, _ mat: SCNMaterial, _ x: Double, _ y: Double, _ z: Double, name: String? = nil) -> SCNNode {
        let s = SCNSphere(radius: max(r, 0.001))
        s.segmentCount = r < 0.03 ? 10 : 24
        return add(s, mat, x, y, z, name: name)
    }

    /// A rod (or tapered leg when r2 is given) from one point to another.
    @discardableResult
    private func rod(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ r: Double, _ mat: SCNMaterial, r2: Double? = nil, name: String? = nil) -> SCNNode {
        let v = b - a, len = simd_length(v)
        let g: SCNGeometry = r2.map { SCNCone(topRadius: max(r, 0.001), bottomRadius: max($0, 0.001), height: max(len, 0.001)) }
            ?? SCNCylinder(radius: max(r, 0.001), height: max(len, 0.001))
        g.materials = [mat]
        let n = SCNNode(geometry: g)
        let mid = (a + b) / 2
        n.position = SCNVector3(mid.x, mid.y, mid.z)
        // The cylinder runs along +y; turn it onto b - a (its top towards b... cones: top radius at b).
        let dir = simd_normalize(v)
        let up = SIMD3<Double>(0, 1, 0)
        let axis = simd_cross(up, dir)
        let angle = acos(max(-1, min(1, simd_dot(up, dir))))
        if simd_length(axis) > 1e-6 {
            n.simdOrientation = simd_quatf(angle: Float(angle), axis: SIMD3<Float>(simd_normalize(axis)))
        } else if simd_dot(up, dir) < 0 {
            n.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }
        n.name = name
        node.addChildNode(n)
        return n
    }

    private func random(_ k: Int) -> Double {
        var x = seed &+ UInt64(k) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 33; x = x &* 0xff51_afd7_ed55_8ccd; x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }

    // MARK: halloween props

    /// A poseable plastic skeleton: the 5-ft shop one, the 12-ft lawn giant or the dog on all fours. Every
    /// bone is measured off h, so 1.52 m and 3.66 m read alike; only the giant's eye sockets light up.
    private func skeleton() {
        if look.form == "dog" { skeletonDog(); return }
        let bone = bodyM, giant = look.form == "giant"
        let r = h * 0.016                                       // a long bone's radius
        // A 1.52 m skeleton is only 0.2 m front to back, so the skull cannot be as round as h suggests.
        let skull = min(h * 0.07, d * 0.4), chestD = min(h * 0.045, d * 0.34)
        let shoulder = h * 0.8, hip = h * 0.5
        let half = min(giant ? w * 0.22 : w * 0.42, h * 0.11)   // half the shoulder span: the giant stands wider
        // Skull: squashed a little front to back, with sunken sockets and a hinged jaw.
        ball(skull, bone, 0, h - skull, 0).scale = SCNVector3(0.9, 1, 1.05)
        let socket = giant ? glow((0.45, 0.78, 0.16), strength: 1.2) : m(Finish(.paint, (0.06, 0.05, 0.05)))
        for s in [-1.0, 1.0] { ball(skull * 0.28, socket, s * skull * 0.34, h - skull * 0.95, skull * 0.72) }
        box(skull * 1.05, skull * 0.4, skull * 0.9, bone, 0, h - skull * 1.6, skull * 0.12, round: skull * 0.14)
        rod(SIMD3(0, shoulder, 0), SIMD3(0, h - skull * 1.7, 0), r * 0.8, bone)
        // Spine, clavicle bar, pelvis and sternum.
        for k in 0...6 { ball(r * 1.25, bone, 0, hip + (shoulder - hip) * Double(k) / 6, -chestD * 0.5) }
        rod(SIMD3(-half, shoulder, 0), SIMD3(half, shoulder, 0), r * 0.7, bone)
        box(half * 1.5, h * 0.07, chestD * 1.6, bone, 0, hip - h * 0.015, 0, round: h * 0.02)
        box(r * 2.2, (shoulder - hip) * 0.38, r, bone, 0, shoulder - h * 0.1, chestD * 0.62)
        // Ribs: five pairs of two-rod arcs from the spine out to the sternum, tapering towards the waist.
        for k in 0..<5 {
            let t = Double(k) / 4, y = shoulder - h * 0.035 - t * (shoulder - hip - h * 0.08)
            let side = half * (0.78 - t * 0.2), deep = chestD * (1 - t * 0.15)
            for s in [-1.0, 1.0] {
                rod(SIMD3(0, y, -deep * 0.5), SIMD3(s * side, y - h * 0.004, 0), r * 0.4, bone)
                rod(SIMD3(s * side, y - h * 0.004, 0), SIMD3(s * side * 0.3, y - h * 0.012, deep * 0.6), r * 0.4, bone)
            }
        }
        // Arms and legs. A posable prop never hangs straight, so every joint takes its own draw; the hands
        // and feet stay inside the footprint the catalogue gives (arms down at the sides, not out).
        let pose = look.details.contains("posable") ? 1.0 : 0.0
        let reach = min(giant ? w * 0.42 : half * 1.35, w / 2 - r * 2)
        for (i, s) in [-1.0, 1.0].enumerated() {
            let lift = pose * (random(i) - 0.3) * h * 0.09
            let cuff = SIMD3(s * reach, shoulder - h * 0.3 + lift * 2, min(chestD + pose * random(i + 3) * h * 0.03, d * 0.3))
            boneLimb(SIMD3(s * half, shoulder, 0), SIMD3(s * (half + (reach - half) * 0.45), shoulder - h * 0.16 + lift, chestD * 0.3), cuff, r * 0.8, bone)
            let foot = s * (giant ? w * 0.26 : half * 0.7)
            boneLimb(SIMD3(s * half * 0.6, hip - h * 0.04, 0), SIMD3(foot, h * 0.26, pose * (random(i + 7) - 0.5) * h * 0.02), SIMD3(foot, r * 1.4, 0), r, bone)
            box(r * 3, r * 1.6, min(h * 0.055, d * 0.4), bone, foot, r * 0.8, min(h * 0.012, d * 0.08), round: r * 0.4)
        }
    }

    /// One jointed limb: the upper bone, a ball at the visible knee or elbow, then the lower bone and the
    /// knuckle it ends on.
    private func boneLimb(_ top: SIMD3<Double>, _ joint: SIMD3<Double>, _ end: SIMD3<Double>, _ r: Double, _ mat: SCNMaterial) {
        ball(r * 1.3, mat, top.x, top.y, top.z)
        rod(top, joint, r, mat)
        ball(r * 1.5, mat, joint.x, joint.y, joint.z)
        rod(joint, end, r * 0.82, mat)
        ball(r * 1.25, mat, end.x, end.y, end.z)
    }

    /// The skeleton dog: a low skull pushed forward, a long spine, four jointed legs and a cocked tail.
    /// The catalogue gives it as 0.62 by 0.26, so the spine runs along whichever floor axis is longer.
    private func skeletonDog() {
        let bone = bodyM, alongZ = d >= w
        let len = max(w, d) * 0.94, span = min(w, d)
        // One mapping from (along the spine, up, across) into the frame, so the build reads the same either way.
        let put: (Double, Double, Double) -> SIMD3<Double> = { a, y, s in alongZ ? SIMD3(s, y, a) : SIMD3(a, y, s) }
        let back = h * 0.72, r = h * 0.024, hip = span * 0.24
        let pose = look.details.contains("posable") ? 1.0 : 0.0
        // Spine: vertebrae from the tail to the withers, dipping a little in the middle.
        for k in 0...8 {
            let t = Double(k) / 8, p = put(-len * 0.44 + len * 0.72 * t, back - h * 0.03 * sin(t * .pi), 0)
            ball(r * 1.3, bone, p.x, p.y, p.z)
        }
        // Neck and skull: dropped forward, with a tapered muzzle and sockets out on the surface of the skull.
        let withers = put(len * 0.28, back, 0), head = put(len * 0.38, h * 0.54, 0), nose = put(len * 0.47, h * 0.49, 0)
        let skull = min(h * 0.16, span * 0.4)
        rod(withers, head, r * 0.9, bone)
        ball(skull, bone, head.x, head.y, head.z).scale = SCNVector3(0.95, 0.85, 0.95)
        rod(head, nose, skull * 0.3, bone, r2: skull * 0.6)
        let socket = m(Finish(.paint, (0.06, 0.05, 0.05)))
        for s in [-1.0, 1.0] {
            let eye = put(len * 0.38 + skull * 0.45, h * 0.57, s * skull * 0.72)
            ball(skull * 0.22, socket, eye.x, eye.y, eye.z)
        }
        // Ribs: three pairs of arcs from the spine down and round towards the breastbone.
        for k in 0..<3 {
            let a = len * (0.2 - Double(k) * 0.16), deep = span * 0.3 * (1 - Double(k) * 0.12)
            for s in [-1.0, 1.0] {
                rod(put(a, back - r, 0), put(a, h * 0.52, s * deep), r * 0.35, bone)
                rod(put(a, h * 0.52, s * deep), put(a, h * 0.38, s * deep * 0.35), r * 0.35, bone)
            }
        }
        // Four legs: the front pair under the withers, the hind pair kicked back behind the pelvis.
        for (i, a) in [len * 0.26, -len * 0.32].enumerated() {
            for s in [-1.0, 1.0] {
                let bend = (i == 0 ? h * 0.05 : -h * 0.07) + pose * (random(i * 2 + Int(s) + 2) - 0.5) * h * 0.03
                boneLimb(put(a, back - h * 0.06, s * hip), put(a + bend, h * 0.32, s * hip), put(a, r * 1.3, s * hip), r * 0.8, bone)
            }
        }
        // Tail: three rods swinging up and out, so it reads as cocked rather than dragging.
        var last = put(-len * 0.44, back - h * 0.02, 0)
        for k in 0..<3 {
            let next = put(-len * (0.45 + 0.02 * Double(k)), back + h * (0.04 + 0.05 * Double(k)), h * 0.03 * (random(k) - 0.5))
            rod(last, next, r * 0.45, bone)
            last = next
        }
    }

    /// A standing figure: the lurching reaper with its scythe, the witch with hat and broom, or the burlap
    /// scarecrow. All three are a robe cone with a head and two sleeves; look.form decides what it carries.
    private func reaper() {
        let form = look.form
        let shoulder = h * (form == "witch" ? 0.72 : 0.82)   // the witch's pointed hat takes the top of the frame
        let headR = min(h * 0.062, d * 0.28), hemR = min(w * 0.46, d * 0.46)
        let robe = m(form == "witch" ? Finishes.named("witch purple")! : look.upholstery)
        robe.isDoubleSided = true                            // the hem is open: the inside shows from below
        add(SCNCone(topRadius: headR * 1.6, bottomRadius: hemR, height: shoulder), robe, 0, shoulder / 2, 0)
        box(headR * 2.6, h * 0.04, headR * 1.8, m(look.body), 0, shoulder, 0, round: headR * 0.3)
        if form == "scarecrow" {
            // A sack of burlap, tied at the crown, with two stitches crossed over each eye.
            let sack = m(Finishes.named("burlap")!), thread = m(Finishes.named("charcoal")!)
            ball(headR * 1.15, sack, 0, shoulder + headR, 0).scale = SCNVector3(1, 1.1, 0.95)
            cyl(headR * 0.45, h * 0.022, sack, 0, shoulder + headR * 2.15, 0)
            for s in [-1.0, 1.0] {
                for k in 0..<2 {
                    box(headR * 0.34, headR * 0.07, headR * 0.05, thread, s * headR * 0.4, shoulder + headR * 1.1, headR * 0.84,
                        round: headR * 0.02, rotate: SCNVector3(0, 0, Float(k == 0 ? 0.7 : -0.7)))
                }
            }
        } else {
            // A hollow dark face set deep in a hood: the cone is tilted forward so its opening faces +z.
            ball(headR, m(Finish(.paint, (0.05, 0.04, 0.05))), 0, shoulder + headR * 0.95, 0)
            let hood = m(look.body)
            hood.isDoubleSided = true
            add(SCNCone(topRadius: headR * 0.2, bottomRadius: headR * 1.5, height: headR * 2.8), hood,
                0, shoulder + headR * 1.2, -headR * 0.3, rotate: SCNVector3(-0.25, 0, 0))
            let eyes = glow(form == "witch" ? (0.45, 0.78, 0.16) : (0.8, 0.14, 0.05), strength: 1.1)
            for s in [-1.0, 1.0] { ball(headR * 0.19, eyes, s * headR * 0.32, shoulder + headR, headR * 0.78) }
        }
        // Sleeves: tapered from the shoulder out to a cuff held forward, each at its own height.
        let hands = m(Finishes.named(form == "scarecrow" ? "burlap" : "bone")!)
        for (i, s) in [-1.0, 1.0].enumerated() {
            let cuff = SIMD3(s * min(w * 0.4, hemR + headR), shoulder - h * (0.17 + 0.04 * random(i)), min(d * 0.3, h * 0.11))
            rod(SIMD3(s * headR * 1.1, shoulder - h * 0.02, 0), cuff, headR * 0.42, robe, r2: headR * 0.62)
            ball(headR * 0.42, hands, cuff.x, cuff.y, cuff.z)
        }
        reaperExtras(shoulder: shoulder, headR: headR)
    }

    /// What each standing figure carries: the reaper's scythe, the witch's hat and broom, the scarecrow's
    /// straw and its lantern.
    private func reaperExtras(shoulder: Double, headR: Double) {
        switch look.form {
        case "witch":
            // Hat: a brim disc on the hood, with the cone run right up to the top of the frame.
            let felt = m(Finish(.fabric, (0.09, 0.07, 0.11))), brim = shoulder + headR * 2.5
            cyl(headR * 2.3, h * 0.01, felt, 0, brim, 0)
            add(SCNCone(topRadius: h * 0.004, bottomRadius: headR * 1.3, height: h - brim), felt, 0, (brim + h) / 2, 0)
            // Broom: the haft runs up to the hand, the straw is bound low and splays onto the floor.
            let bind = SIMD3(w * 0.36, h * 0.19, min(d * 0.3, h * 0.1))
            rod(bind, SIMD3(bind.x - w * 0.08, shoulder - h * 0.15, bind.z), h * 0.009, m(Finishes.named("dark brown")!))
            let straw = m(Finishes.named("straw")!)
            for k in 0..<10 {
                let a = Double(k) * 0.63, spread = h * 0.03 * (0.5 + random(k))
                rod(bind, SIMD3(bind.x + spread * cos(a), h * 0.004, bind.z + spread * sin(a)), h * 0.004, straw)
            }
            cyl(h * 0.016, h * 0.022, m(Finishes.named("jute")!), bind.x, bind.y, bind.z)
        case "scarecrow":
            let straw = m(Finishes.named("straw")!)
            // Straw bursting out of the collar and both cuffs: eight at the neck, three per sleeve.
            for k in 0..<14 {
                let a = Double(k) * 0.45
                let base: SIMD3<Double> = k < 8 ? SIMD3(0, shoulder + h * 0.01, 0)
                    : SIMD3(Double(k % 2 == 0 ? -1 : 1) * min(w * 0.4, h * 0.2), shoulder - h * 0.19, min(d * 0.3, h * 0.11))
                rod(base, base + SIMD3(h * 0.055 * cos(a), -h * 0.045, h * 0.045 * sin(a)), h * 0.004, straw)
            }
            guard look.details.contains("lit") else { return }
            // A lantern hung from the near cuff: the glowing block is the light, the cage is four uprights.
            let x = min(w * 0.4, h * 0.2), z = min(d * 0.3, h * 0.11), y = shoulder - h * 0.32
            rod(SIMD3(x, shoulder - h * 0.19, z), SIMD3(x, y + h * 0.05, z), h * 0.003, metalM)
            box(h * 0.05, h * 0.06, h * 0.05, glow((1, 0.72, 0.3), strength: 1.2), x, y, z, round: h * 0.004)
            for c in 0..<4 {
                let a = Double(c) * .pi / 2 + .pi / 4, cx = x + h * 0.028 * cos(a), cz = z + h * 0.028 * sin(a)
                rod(SIMD3(cx, y - h * 0.036, cz), SIMD3(cx, y + h * 0.036, cz), h * 0.0035, metalM)
            }
            box(h * 0.062, h * 0.008, h * 0.062, metalM, x, y + h * 0.04, z)
        default:
            // The scythe: a haft leaning across the body, and a blade swept back from its head in three
            // plates (SceneKit has no arc, so each plate is turned a little further than the last).
            let top = SIMD3(w * 0.28, h * 0.99, min(d * 0.26, h * 0.12))
            rod(SIMD3(-w * 0.2, 0, min(d * 0.34, h * 0.16)), top, h * 0.01, m(Finishes.named("dark brown")!))
            let steel = m(Finishes.named("steel")!)
            for k in 0..<3 {
                let t = Double(k) / 3, blade = h * 0.15
                box(blade * (1 - t * 0.3), h * 0.045, h * 0.008, steel,
                    top.x - blade * (0.45 + t * 0.75), top.y - blade * t * t * 1.1, top.z,
                    round: h * 0.002, rotate: SCNVector3(0, 0, Float(-0.35 * t - 0.08)))
            }
        }
    }

    /// The hanging ghost: it never touches the floor. The hem stops at a third of the frame and the head
    /// sits near the top, so the gap underneath is what makes it read as floating.
    private func ghost() {
        let headY = h * 0.9, hem = h * 0.35
        let headR = min(h * 0.075, d * 0.42), hemR = min(w * 0.4, d * 0.46)
        let cloth = m(look.body)
        cloth.isDoubleSided = true                    // the hem is open, so you see up inside the shroud
        if look.details.contains("lit") {
            // Lit from within: a soft ball inside the head does the lighting and the cloth only glows
            // faintly, so the whole shroud reads as a lantern rather than as a bulb.
            cloth.emission.contents = CGColor(srgbRed: 0.26, green: 0.29, blue: 0.36, alpha: 1)
            ball(headR * 0.72, glow((0.72, 0.8, 0.95), strength: 1.2), 0, headY, 0)
        }
        ball(headR, cloth, 0, headY, 0)
        add(SCNCone(topRadius: headR * 0.8, bottomRadius: hemR, height: headY - hem), cloth, 0, (headY + hem) / 2, 0)
        // Trailing sleeves: tapered, swept out and forward, each ending at its own height above the hem.
        for (i, s) in [-1.0, 1.0].enumerated() {
            let tip = SIMD3(s * w * 0.44, hem + h * (0.05 + 0.09 * random(i)), min(d * 0.26, headR))
            rod(SIMD3(s * headR * 0.5, headY - headR * 1.3, 0), tip, headR * 0.28, cloth, r2: headR * 0.55)
            ball(headR * 0.28, cloth, tip.x, tip.y, tip.z)
        }
        // Ragged tatters round the hem: a different length each, so the edge is torn rather than cut.
        for k in 0..<12 {
            let a = Double(k) * .pi / 6 + random(k) * 0.2
            let length = h * (0.05 + 0.13 * random(k + 30))
            box(hemR * 0.45, length, h * 0.004, cloth, hemR * 0.92 * cos(a), hem - length / 2 + h * 0.01, hemR * 0.92 * sin(a),
                round: h * 0.002, rotate: SCNVector3(0, Float(-a), Float((random(k + 60) - 0.5) * 0.3)))
        }
    }

    /// The crouching zombie groundbreaker: at 0.46 m it is a torso and two arms, not a body. The mound of
    /// turned earth is what sells it — the corpse is coming up through the lawn, so the soil comes with it.
    private func groundbreaker() {
        let flesh = bodyM, soil = m(Finish(.stone, (0.19, 0.15, 0.11)))
        // The mound: a unit ball scaled to the footprint, so only its top half shows above the floor.
        ball(0.5, soil, 0, 0, -d * 0.05).scale = SCNVector3(w * 0.92, h * 0.6, d * 0.86)
        for k in 0..<6 {
            let a = Double(k) * 1.05, r = min(w, d) * (0.02 + 0.03 * random(k))
            ball(r, soil, w * 0.4 * cos(a), r * 0.6, d * 0.36 * sin(a) + d * 0.02)
        }
        // Head and shoulders breaking through, tilted back towards +z so the face looks at the sky.
        let shoulderY = h * 0.4, headR = min(h * 0.26, d * 0.28)
        box(w * 0.44, h * 0.3, d * 0.42, flesh, 0, shoulderY * 0.82, -d * 0.02, round: h * 0.05, rotate: SCNVector3(0.38, 0, 0))
        ball(headR, flesh, 0, h * 0.7, d * 0.1).scale = SCNVector3(0.9, 1, 0.95)
        let socket = m(Finish(.paint, (0.05, 0.04, 0.04)))
        for s in [-1.0, 1.0] { ball(headR * 0.26, socket, s * headR * 0.36, h * 0.74, d * 0.1 + headR * 0.72) }
        box(headR * 0.9, headR * 0.3, headR * 0.7, flesh, 0, h * 0.63, d * 0.1 + headR * 0.5, round: headR * 0.1,
            rotate: SCNVector3(0.3, 0, 0))                    // the jaw, hanging open
        // Both arms out of the soil, reaching forward and up.
        for (i, s) in [-1.0, 1.0].enumerated() {
            let elbow = SIMD3(s * w * 0.3, h * 0.28, d * 0.16)
            let wrist = SIMD3(s * w * 0.4, h * (0.5 + 0.16 * random(i)), min(d * 0.34, w * 0.3))
            rod(SIMD3(s * w * 0.17, shoulderY, -d * 0.02), elbow, h * 0.055, flesh, r2: h * 0.07)
            ball(h * 0.06, flesh, elbow.x, elbow.y, elbow.z)
            rod(elbow, wrist, h * 0.045, flesh, r2: h * 0.056)
            clawedHand(at: wrist, side: s, k: i)
        }
        // Torn fabric: shreds of shirt left on the shoulders and snagged on the front rim of the hole.
        let rag = m(Finish(.fabric, (0.22, 0.2, 0.17)))
        rag.isDoubleSided = true
        for k in 0..<6 {
            let a = Double.pi * (0.1 + 0.16 * Double(k)), length = h * (0.1 + 0.12 * random(k + 40))
            box(w * 0.1, length, h * 0.006, rag, w * 0.26 * cos(a), shoulderY * 0.9 - length / 2, d * 0.24 * sin(a) + d * 0.04,
                round: h * 0.004, rotate: SCNVector3(Float((random(k) - 0.5) * 0.3), Float(-a), 0))
        }
    }

    /// A clawing hand: a palm and four fingers fanned forward and up, a couple of them curled much further
    /// than the rest, so the grasp does not look moulded from one finger.
    private func clawedHand(at wrist: SIMD3<Double>, side: Double, k: Int) {
        let flesh = bodyM, nail = m(Finishes.named("charcoal")!)
        ball(h * 0.055, flesh, wrist.x, wrist.y, wrist.z)
        for f in 0..<4 {
            let spread = (Double(f) - 1.5) * h * 0.042, curl = 0.4 + 0.9 * random(k * 10 + f)
            let knuckle = wrist + SIMD3(side * h * 0.025 + spread, h * 0.05, h * 0.045)
            let tip = knuckle + SIMD3(spread * 0.4, h * 0.07 * (1 - curl * 0.5), h * 0.05 * curl)
            rod(wrist, knuckle, h * 0.016, flesh, r2: h * 0.022)
            rod(knuckle, tip, h * 0.011, flesh, r2: h * 0.016)
            ball(h * 0.013, nail, tip.x, tip.y, tip.z)
        }
    }

/// A headstone: the classic rounded RIP slab, a ringed Celtic cross or a cracked obelisk, each standing on
/// a plinth a little wider than itself. Lettering is suggested with shallow carved bars, since nothing in
/// the scene draws text. Stone is look.body.
private func tombstone() {
    let stone = bodyM, dark = m(look.body.scaled(0.52)), plinthH = h * 0.08
    box(w, plinthH, d, m(look.body.scaled(0.84)), 0, plinthH / 2, 0, round: 0.006)
    switch look.form {
    case "cross":
        box(w * 0.78, h * 0.055, d * 0.86, m(look.body.scaled(0.9)), 0, plinthH + h * 0.028, 0)
        let foot = plinthH + h * 0.055, arm = foot + (h - foot) * 0.68
        box(w * 0.3, h - foot, d * 0.58, stone, 0, foot + (h - foot) / 2, 0, round: 0.006)
        box(w, h * 0.14, d * 0.54, stone, 0, arm, 0, round: 0.006)
        // the ring at the crossing is what makes it Celtic rather than a plain cross
        add(SCNTorus(ringRadius: w * 0.3, pipeRadius: w * 0.05), stone, 0, arm, 0, rotate: SCNVector3(Float.pi / 2, 0, 0))
    case "obelisk":
        box(w * 0.86, h * 0.05, d * 0.86, m(look.body.scaled(0.9)), 0, plinthH + h * 0.025, 0)
        let foot = plinthH + h * 0.05, shaft = h * 0.62
        var y = foot
        for (f, part) in [(0.68, 0.46), (0.56, 0.32), (0.46, 0.22)] {   // a battered taper in three drums
            box(w * f, shaft * part, d * f, stone, 0, y + shaft * part / 2, 0)
            y += shaft * part
        }
        add(SCNPyramid(width: w * 0.46, height: h - y, length: d * 0.46), stone, 0, y, 0)
        // the crack stays on the bottom drum: the only face wide enough to carry it without floating off
        box(w * 0.03, shaft * 0.38, 0.006, dark, w * 0.07, foot + shaft * 0.22, d * 0.345, rotate: SCNVector3(0, 0, 0.38))
    default: // slab: the cap is a cylinder lying along z, so only its upper half shows above the slab
        let sw = w * 0.88, st = d * 0.78, cap = sw / 2
        let bodyH = max(h - cap - plinthH, h * 0.25)        // clamped in case a stone is wider than it is tall
        box(sw, bodyH, st, stone, 0, plinthH + bodyH / 2, 0, round: 0.008)
        cyl(cap, st, stone, 0, plinthH + bodyH, 0, rotate: SCNVector3(Float.pi / 2, 0, 0))
        let face = st / 2 + 0.002, bars = m(look.body.scaled(0.36))     // carving reads as darker, not deeper
        box(sw - w * 0.14, bodyH * 0.8 + cap * 0.8, 0.004, dark, 0, plinthH + bodyH * 0.62, face, round: 0.012)
        box(sw * 0.34, h * 0.035, 0.004, bars, 0, plinthH + bodyH * 0.9, face + 0.003)      // "RIP", short and centred
        for k in 0..<2 { box(sw * 0.56, h * 0.02, 0.004, bars, 0, plinthH + bodyH * (0.6 - Double(k) * 0.17), face + 0.003) }
    }
    if look.details.contains("weathered") {
        for k in 0..<4 {                                    // chipping low down, where a stone loses its edges
            let s = 0.04 + 0.06 * random(k)
            box(w * s, h * s * 0.7, d * 0.5, dark, (random(k + 5) - 0.5) * w * 0.8, h * (0.03 + 0.26 * random(k + 11)), d * 0.05)
        }
    }
    if look.details.contains("mossy") {
        let moss = m(Finish(.foliage, (0.16, 0.26, 0.13)))
        for k in 0..<3 {
            ball(w * (0.06 + 0.05 * random(k + 30)), moss, (random(k + 40) - 0.5) * w * 0.6, h * 0.04, d * 0.18)
                .scale = SCNVector3(1, 0.45, 0.6)
        }
    }
}

/// A witch's cauldron: a cast-iron belly on three bowed legs under a rolled rim, brewing something green
/// when it fogs. Iron is look.body.
private func cauldron() {
    let iron = bodyM, s = min(w, d), rx = w / 2
    let legH = h * 0.15, top = h * 0.95, ry = (top - legH) / 2, yc = legH + ry
    // the collar comes off the narrow axis so it can never poke out of an oval footprint
    let collarR = s / 2 * 0.83, collarY = yc + ry * 0.55, rimY = top - h * 0.03
    ball(rx, iron, 0, yc, 0).scale = SCNVector3(1, Float(ry / rx), Float(d / w))
    // straight sides from the waist up: the collar swallows the sphere's dome, so the pot reads as open
    cyl(collarR, rimY - collarY, iron, 0, (collarY + rimY) / 2, 0)
    var rimM = iron
    if look.form == "fogging" {                             // the rim catches the light off its own brew
        rimM = m(look.body)
        rimM.emission.contents = CGColor(srgbRed: 0.06, green: 0.2, blue: 0.04, alpha: 1)
    }
    add(SCNTorus(ringRadius: collarR, pipeRadius: s * 0.045), rimM, 0, rimY, 0)
    for k in 0..<3 {                                        // three stubby legs, bowed out under the belly
        let a = Double(k) * 2 * .pi / 3 + .pi / 6
        rod(SIMD3(rx * 0.45 * cos(a), legH * 1.3, d / 2 * 0.45 * sin(a)),
            SIMD3(rx * 0.62 * cos(a), 0, d / 2 * 0.62 * sin(a)), s * 0.05, iron, r2: s * 0.07)
    }
    for sx in [-1.0, 1.0] {                                 // lugs where a bail would hang
        add(SCNTorus(ringRadius: s * 0.06, pipeRadius: s * 0.02), iron, sx * (collarR - s * 0.03), rimY - s * 0.09, 0,
            rotate: SCNVector3(0, 0, Float.pi / 2))
    }
    switch look.form {
    case "fogging":
        // the brew sits over the collar's cap, just under the rim's top edge
        cyl(collarR * 0.94, h * 0.012, glow((0.35, 0.8, 0.25), strength: 1.1), 0, rimY, 0)
        let fog = m(Finish(.paint, (0.84, 0.92, 0.82)))
        fog.transparency = 0.12                             // vapour: the one part of a prop allowed to drift
        fog.emission.contents = CGColor(srgbRed: 0.08, green: 0.2, blue: 0.06, alpha: 1)
        for k in 0..<3 {
            let a = Double(k) * 2.3, pooled = k == 2        // two spilling over the rim, one pooling at the feet
            ball(s * (pooled ? 0.28 : 0.22), fog, (pooled ? rx * 0.3 : collarR * 0.6) * cos(a),
                 pooled ? h * 0.1 : rimY - h * 0.03 + h * 0.06 * random(k),
                 (pooled ? d / 2 * 0.3 : collarR * 0.6) * sin(a))
        }
    default: break                                          // "cauldron": an empty pot
    }
}

/// A carved pumpkin: a lobed gourd with a twisted stalk and a candle-lit face, the projector pumpkin's flat
/// glowing panel, or three gourds stacked. The skin is look.body ("pumpkin").
private func jackOLantern() {
    let ribbed = m(look.body.scaled(0.78)), stalkM = m(Finish(.wood, (0.34, 0.37, 0.17)))
    /// one gourd: a wide centre ball ringed with lobes, which is what makes the ribs read in silhouette
    func gourd(_ cy: Double, _ pw: Double, _ ph: Double, _ pd: Double, _ turn: Double) {
        ball(0.5, bodyM, 0, cy, 0).scale = SCNVector3(Float(pw * 0.82), Float(ph), Float(pd * 0.82))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4 + turn
            ball(0.5, k % 2 == 0 ? bodyM : ribbed, pw * 0.29 * cos(a), cy, pd * 0.29 * sin(a))
                .scale = SCNVector3(Float(pw * 0.42), Float(ph * 0.97), Float(pd * 0.42))
        }
    }
    /// a face set just proud of the skin: the glow is the candle inside showing through the cuts
    func carve(_ cy: Double, _ s: Double, _ fz: Double) {
        let lit = glow((1, 0.62, 0.18), strength: 1.2)
        for sx in [-1.0, 1.0] { add(SCNPyramid(width: s * 0.25, height: s * 0.2, length: s * 0.12), lit, sx * s * 0.19, cy + s * 0.05, fz) }
        add(SCNPyramid(width: s * 0.1, height: s * 0.11, length: s * 0.1), lit, 0, cy - s * 0.06, fz)
        for k in 0..<5 {                                    // a grin: five bars stepping down to the corners
            let t = Double(k) / 4 - 0.5
            box(s * 0.12, s * 0.12 - abs(t) * s * 0.1, s * 0.1, lit, t * s * 0.5, cy - s * 0.22 - abs(t) * s * 0.06, fz)
        }
        for sx in [-1.0, 1.0] { box(s * 0.06, s * 0.09, s * 0.11, m(look.body), sx * s * 0.14, cy - s * 0.2, fz) }   // two teeth
    }
    switch look.form {
    case "talking":
        let bodyH = h * 0.86                                // the top of the frame belongs to the stalk
        gourd(bodyH / 2, w, bodyH, d * 0.9, 0)              // a shallower gourd leaves the panel room to sit proud
        rod(SIMD3(0, bodyH * 0.9, 0), SIMD3(w * 0.05, h, d * 0.03), min(w, d) * 0.06, stalkM, r2: min(w, d) * 0.1)
        ball(0.5, glow((1, 0.7, 0.24), strength: 1.4), 0, bodyH * 0.54, d * 0.32)
            .scale = SCNVector3(Float(w * 0.64), Float(bodyH * 0.62), Float(d * 0.3))
        let ink = m(Finish(.paint, (0.07, 0.05, 0.04)))     // features painted across the panel, not cut into it
        for sx in [-1.0, 1.0] { box(w * 0.11, bodyH * 0.1, 0.004, ink, sx * w * 0.14, bodyH * 0.64, d * 0.475, round: 0.01) }
        box(w * 0.32, bodyH * 0.1, 0.004, ink, 0, bodyH * 0.42, d * 0.475, round: 0.012)
    case "stack":
        var y = 0.0
        for k in 0..<3 {                                    // falling sizes, each turned so no two show the same ribs
            let f = 1 - Double(k) * 0.26, ph = h * 0.455 * f
            gourd(y + ph / 2, w * f, ph, d * f, random(k) * .pi / 4)
            if k == 2 {
                carve(y + ph * 0.52, w * f, d * f * 0.44)
                rod(SIMD3(0, y + ph * 0.92, 0), SIMD3(w * 0.04, h, d * 0.02), min(w, d) * 0.05, stalkM, r2: min(w, d) * 0.08)
            }
            y += ph * 0.86                                  // they settle into one another a little
        }
    default: // blowmold: one carved gourd with a candle in it
        let bodyH = h * 0.86
        gourd(bodyH / 2, w, bodyH, d, 0)
        rod(SIMD3(0, bodyH * 0.9, 0), SIMD3(w * 0.05, h, d * 0.03), min(w, d) * 0.06, stalkM, r2: min(w, d) * 0.1)
        carve(bodyH * 0.52, w, d * 0.44)
        if look.details.contains("lit") { ball(min(w, d) * 0.2, glow((1, 0.78, 0.4), strength: 0.7), 0, bodyH * 0.42, 0) }
    }
}

/// A six-sided coffin stood on its foot end and tipped back onto the wall behind it: a dark shell with the
/// lid proud of it, so the reveal between the two reads as a lid that opens. Wood is look.body.
private func coffin() {
    let lean = 0.02, t = d * 0.56                           // thin for its footprint, and tipped back a hair
    let backZ = -d / 2 + h * lean / 2                       // the lean is taken about mid-height, so it costs
    let lidZ = backZ + t * 0.98                             // half as much depth at the top as at the floor
    let shoulderY = h * 0.7, narrowW = w * 0.52             // shoulders about 0.3 h down, twice the head's width
    let wood = bodyM, shell = m(look.body.scaled(0.42)), seam = m(look.body.scaled(0.3))
    /// one board, sheared back with the lean so every part of the prop leans by the same hair
    func plank(_ bw: Double, _ bh: Double, _ bd: Double, _ mat: SCNMaterial, _ x: Double, _ y: Double, _ z: Double, _ ang: Double = 0) {
        box(bw, bh, bd, mat, x, y, z - (y - h / 2) * lean, rotate: SCNVector3(Float(-lean), 0, Float(ang)))
    }
    /// a slanted board with its outer edge lying on the taper from (±wTop/2, yTop) to (±wBot/2, yBot)
    func rail(_ yTop: Double, _ wTop: Double, _ yBot: Double, _ wBot: Double, _ sx: Double, _ f: Double, _ bd: Double, _ z: Double, _ mat: SCNMaterial) {
        let yA = (yTop - h / 2) * f + h / 2, yB = (yBot - h / 2) * f + h / 2
        let ux = sx * (wTop - wBot) * f / 2, bw = w * 0.34
        let len = ((yA - yB) * (yA - yB) + ux * ux).squareRoot(), ang = atan2(-ux, yA - yB)
        plank(bw, len, bd, mat, sx * (wTop + wBot) * f / 4 - sx * bw / 2 * cos(ang),
              (yA + yB) / 2 - sx * bw / 2 * sin(ang), z, ang)
    }
    // the outline twice over: the shell, then the lid inset a little and standing proud of it
    for (f, bd, z, mat) in [(1.0, t * 0.72, backZ + t * 0.36, shell), (0.94, t * 0.3, lidZ - t * 0.15, wood)] {
        plank(narrowW * f, h * f, bd, mat, 0, h / 2, z)     // the spine, as wide as the head and foot ends
        for sx in [-1.0, 1.0] {
            rail(h, narrowW, shoulderY, w, sx, f, bd, z, mat)
            rail(shoulderY, w, 0, narrowW, sx, f, bd, z, mat)
        }
    }
    for k in 0..<4 {                                        // plank seams, with a board or two weathered off-tint
        let x = (Double(k) - 1.5) * w * 0.12
        plank(w * 0.014, h * 0.68, 0.005, seam, x, h / 2, lidZ)
        if look.details.contains("weathered"), random(k) > 0.45 {
            plank(w * 0.1, h * 0.66, 0.004, m(look.body.scaled(0.84 + 0.34 * random(k + 9))), x + w * 0.06, h / 2, lidZ)
        }
    }
    plank(w * 0.07, h * 0.3, 0.012, metalM, 0, shoulderY + h * 0.02, lidZ + 0.004)      // a cross over the shoulders
    plank(w * 0.34, h * 0.07, 0.012, metalM, 0, shoulderY + h * 0.07, lidZ + 0.004)
    for sx in [-1.0, 1.0] {
        for y in [h * 0.2, h * 0.44, h * 0.66] {            // iron handles, following the taper out to the shoulders
            let edge = (narrowW + (w - narrowW) * y / shoulderY) / 2 - w * 0.025
            add(SCNTorus(ringRadius: w * 0.05, pipeRadius: w * 0.016), metalM, sx * edge, y,
                lidZ - t * 0.2 - (y - h / 2) * lean, rotate: SCNVector3(0, 0, Float.pi / 2))
        }
    }
}

    /// A giant poseable spider. The leg span is the whole footprint width, so the body is barely a third of
    /// it and every knee rises above the back — that high-kneed silhouette is what reads as a spider.
    private func spider() {
        let fur = m(look.body.isMetal ? look.body : look.body.with(.knit))      // flocked, not glossy plastic
        let bristle = m(look.body.scaled(0.5)), eyes = glow((0.9, 0.07, 0.05), strength: 1.2)
        let span = w / 2, br = w * 0.085, by = h * 0.4, headZ = br * 0.95       // body a third of the span
        ball(br, fur, 0, by, -br * 0.8).scale = SCNVector3(1, 0.85, 1.7)        // abdomen: an egg, long along z
        ball(br * 0.62, fur, 0, by * 0.97, headZ).scale = SCNVector3(1, 0.9, 1.2)
        for s in [-1.0, 1.0] {
            ball(br * 0.1, eyes, s * br * 0.22, by + br * 0.3, headZ + br * 0.5)
            rod(SIMD3(s * br * 0.2, by - br * 0.2, headZ + br * 0.4),           // fangs: thick at the head, thin at the tip
                SIMD3(s * br * 0.3, by - br * 0.8, headZ + br * 0.7), br * 0.03, fur, r2: br * 0.14)
        }
        let loose = look.details.contains("posable") ? 0.3 : 0.12               // bent legs sit at odder angles
        for k in 0..<8 {
            let s: Double = k < 4 ? -1 : 1, i = k % 4
            let lean = 0.55 - Double(i) * 0.38 + (random(k) - 0.5) * loose      // front pair reaches forward, back trails
            let hip = SIMD3(s * br * 0.5, by, br * (0.9 - Double(i) * 0.6))
            let foot = SIMD3(s * span * (0.72 + 0.26 * random(k + 8)), 0, d / 2 * max(-0.95, min(0.95, lean)))
            let knee = SIMD3(s * span * (0.4 + 0.12 * random(k + 16)), h * (0.86 + 0.1 * random(k + 24)), (hip.z + foot.z) / 2)
            let ankle = SIMD3(foot.x * 0.92, h * 0.12, foot.z * 0.88 + hip.z * 0.12)
            rod(hip, knee, w * 0.011, fur, r2: w * 0.018)                       // femur, out and up over the body
            rod(knee, ankle, w * 0.008, fur, r2: w * 0.012)                     // tibia, back down to the floor
            rod(ankle, foot, w * 0.006, fur, r2: w * 0.009)                     // tarsus, the little foot
            guard look.details.contains("hairy") else { continue }
            for j in 0..<3 {
                let p = hip + (knee - hip) * (0.3 + 0.25 * Double(j))
                ball(w * 0.008, bristle, p.x, p.y, p.z)
            }
        }
        guard look.details.contains("hairy") else { return }
        for k in 0..<14 {                                                       // bristles sampled over the abdomen
            let a = random(k) * 2 * .pi, u = random(k + 40) * 2 - 1, rr = sqrt(max(0, 1 - u * u))
            ball(w * 0.0075, bristle, br * rr * cos(a), by + br * 0.85 * u, -br * 0.8 + br * 1.7 * rr * sin(a))
        }
    }

    /// A corner cobweb or a cluster of hanging bats. The web lies flat against the back of the frame and is
    /// named like the wall decor, since both belong to the wall rather than to the floor under them.
    private func cobweb() {
        let tag = "walldecor"
        let silk = look.body.isSoft ? bodyM : m(Finishes.named("cheesecloth")!)
        switch look.form {
        case "bats":
            let fur = bodyM, skin = m(look.body.with(.leather)), eye = glow((0.85, 0.1, 0.08), strength: 1.1)
            let cell = w / 3, br = cell * 0.17                                  // each bat keeps inside its own third
            for k in 0..<3 {
                let bx = (Double(k) - 1) * cell, bz = (random(k) - 0.5) * d * 0.4
                let by = h * (0.55 + 0.28 * random(k + 3))                      // staggered heights read as a cluster
                rod(SIMD3(bx, h, bz), SIMD3(bx, by + br * 0.6, bz), br * 0.07, silk, name: tag)
                ball(br, fur, bx, by, bz, name: tag).scale = SCNVector3(1, 0.9, 1.5)
                ball(br * 0.6, fur, bx, by + br * 0.1, bz + br * 1.25, name: tag)
                for s in [-1.0, 1.0] {
                    add(SCNCone(topRadius: 0, bottomRadius: br * 0.2, height: br * 0.5), fur,
                        bx + s * br * 0.28, by + br * 0.6, bz + br * 1.1, name: tag)                // ears
                    ball(br * 0.1, eye, bx + s * br * 0.24, by + br * 0.2, bz + br * 1.55, name: tag)
                    let wing = ball(cell * 0.19, skin, bx + s * cell * 0.28, by + br * 0.1, bz, name: tag)
                    wing.scale = SCNVector3(1, 0.07, 0.8)                                           // a membrane, not a blade
                    wing.eulerAngles = SCNVector3(0, 0, Float(-s * 0.2))
                    for j in 1...2 {                                                                // finger struts
                        rod(SIMD3(bx + s * br * 0.7, by + br * 0.1, bz + br * 0.2),
                            SIMD3(bx + s * cell * 0.45, by + br * 0.1, bz + br * (0.6 - 1.2 * Double(j))),
                            br * 0.05, fur, name: tag)
                    }
                }
            }
        default:
            let pad = min(w, h) * 0.01, z = -d / 2 + pad, thread = min(w, h) * 0.006
            let anchor = SIMD3(-w / 2 + pad, h - pad, z)                        // strung from the top left corner
            var ends: [SIMD3<Double>] = []
            for k in 0...6 {
                let a = Double(k) / 6 * .pi / 2                                 // 0 along the top edge, pi/2 straight down
                let reach = min((w - 2 * pad) / max(cos(a), 0.001), (h - 2 * pad) / max(sin(a), 0.001))
                ends.append(anchor + SIMD3(reach * cos(a), -reach * sin(a), 0))
                rod(anchor, ends[k], thread, silk, name: tag)
            }
            for ring in 1...5 {
                let f = Double(ring) / 5.6
                var prev = anchor
                for k in 0...6 {
                    // odd spokes catch the thread further out, so each cross-thread sags away from the corner
                    let g = min(0.97, f * (k % 2 == 0 ? 1 : 1 + 0.07 * Double(ring)))
                    let p = anchor + (ends[k] - anchor) * g
                    if k > 0 { rod(prev, p, thread * 0.6, silk, name: tag) }
                    prev = p
                }
            }
            let ink = m(Finish(.lacquer, (0.05, 0.05, 0.05)))
            for k in 0..<3 {                                                    // the residents, sat on a spoke
                let p = anchor + (ends[1 + k * 2] - anchor) * (0.4 + 0.45 * random(k)), sr = min(w, h) * 0.022
                ball(sr, ink, p.x, p.y, z + sr, name: tag).scale = SCNVector3(1, 0.9, 0.7)
                for j in 0..<6 {
                    let a = Double(j) * .pi / 3 + 0.3
                    rod(SIMD3(p.x, p.y, z + sr), SIMD3(p.x + sr * 2.2 * cos(a), p.y + sr * 2.2 * sin(a), z + sr),
                        sr * 0.18, ink, name: tag)
                }
            }
        }
    }

    /// A wrought-iron candelabra standing on the floor, or a chandelier hung from the ceiling. Each arm is
    /// two rods so it curls rather than jutting out, and the middle candle is tallest — a level row of
    /// candles reads as a birthday cake. Both forms end in the same cup, so the candles are built once.
    private func candelabra() {
        let iron = look.body.isMetal ? bodyM : m(Finishes.named("wrought iron")!)
        let wax = m(Finishes.named("cream")!), wick = m(Finishes.named("charcoal")!)
        let flame = glow((1, 0.72, 0.25), strength: 1.3)
        let lit = look.details.contains("lit"), cr = min(w, d) * 0.055
        var spots: [SIMD4<Double>] = []                                  // x, the cup rim's y, z, candle height
        switch look.form {
        case "chandelier":
            let ringR = w / 2 * 0.9, ringY = h * 0.34, hub = SIMD3(0, ringY + h * 0.2, 0)
            for k in 0...4 {                                             // chain links, each turned across the last
                let y = h - h * 0.05 - (h - h * 0.05 - hub.y) * Double(k) / 4
                add(SCNTorus(ringRadius: w * 0.03, pipeRadius: w * 0.008), iron, 0, y, 0,
                    rotate: SCNVector3(Float.pi / 2, k % 2 == 0 ? 0 : Float.pi / 2, 0))
            }
            add(SCNTorus(ringRadius: ringR, pipeRadius: ringR * 0.05), iron, 0, ringY, 0)   // a torus already lies flat
            ball(ringR * 0.11, iron, 0, ringY - ringR * 0.16, 0)         // a drop finial under the ring
            for k in 0..<6 {
                let a = Double(k) * .pi / 3, p = SIMD3(ringR * cos(a), ringY, ringR * sin(a))
                if k % 2 == 0 { rod(hub, p, w * 0.008, iron) }           // three stays carry the ring
                spots.append(SIMD4(p.x, ringY + ringR * 0.05, p.z, h * 0.2))
            }
            if look.details.contains("cobwebbed") {
                let gauze = m(Finishes.named("cheesecloth")!)
                for k in 0..<4 {                                         // threads draped from the chain to the ring
                    let a = Double(k) * 1.6 + 0.4
                    rod(hub, SIMD3(ringR * 0.97 * cos(a), ringY + ringR * 0.2 * random(k), ringR * 0.97 * sin(a)),
                        ringR * 0.012, gauze)
                }
            }
        default:
            let baseR = min(w, d) * 0.46, stemTop = h * 0.74             // the middle candle stands on the stem itself
            add(SCNCone(topRadius: baseR * 0.5, bottomRadius: baseR, height: h * 0.05), iron, 0, h * 0.025, 0)
            cyl(baseR * 0.6, h * 0.025, iron, 0, h * 0.062, 0)           // a second step: it has to look weighted
            cyl(w * 0.02, stemTop - h * 0.05, iron, 0, (stemTop + h * 0.05) / 2, 0)
            ball(w * 0.045, iron, 0, h * 0.44, 0)                        // a knop where the arms leave the stem
            let arms = w > 0.46 ? 5 : 3, half = (arms - 1) / 2           // a wider piece has room for five
            for i in 0..<arms where i != half {
                let t = Double(i - half) / Double(half)
                let x = t * (w / 2 - cr * 1.7)                           // the cup rim is the widest point
                let elbow = SIMD3(x * 0.7, h * 0.33, 0)
                rod(SIMD3(0, h * 0.44, 0), elbow, w * 0.013, iron)       // out and down...
                rod(elbow, SIMD3(x, h * (0.56 - 0.06 * abs(t)), 0), w * 0.013, iron)   // ...then up: an S-curl
                spots.append(SIMD4(x, h * (0.56 - 0.06 * abs(t)), 0, h * 0.13))
            }
            spots.append(SIMD4(0, stemTop, 0, h * 0.19))
        }
        for (k, s) in spots.enumerated() {
            let ch = s.w                                                 // this candle's height
            cyl(cr * 1.5, ch * 0.07, iron, s.x, s.y, s.z)                // the cup
            cyl(cr, ch, wax, s.x, s.y + ch / 2, s.z)
            ball(cr, wax, s.x, s.y + ch, s.z).scale = SCNVector3(1, 0.4, 1)        // wax melted over the rim
            cyl(cr * 0.1, ch * 0.07, wick, s.x, s.y + ch * 1.06, s.z)
            if lit { add(SCNCapsule(capRadius: cr * 0.42, height: ch * 0.3), flame, s.x, s.y + ch * 1.2, s.z) }
            guard look.details.contains("dripping"), k % 2 == 0 else { continue }
            for j in 0..<3 {                                             // runs down one side, each stopped lower
                let a = Double(j) * 1.9 + random(k)
                rod(SIMD3(s.x + cr * 0.92 * cos(a), s.y + ch * 0.92, s.z + cr * 0.92 * sin(a)),
                    SIMD3(s.x + cr * 0.96 * cos(a), s.y + ch * (0.45 - 0.12 * Double(j)), s.z + cr * 0.96 * sin(a)),
                    cr * 0.1, wax)
            }
            ball(cr * 0.17, wax, s.x + cr * 1.2, s.y - ch * 0.05, s.z)   // and one drip caught on the arm
        }
    }

    /// Small decor: an oversized resin skull on a plinth, a perched raven, or an apothecary shelf of potions.
    private func curio() {
        switch look.form {
        case "raven":
            let feather = m(look.details.contains("feathered") ? look.body.with(.fabric) : look.body)
            let beak = m(Finish(.lacquer, (0.1, 0.09, 0.09))), eye = m(Finish(.lacquer, (0.04, 0.03, 0.03)))
            let wood = m(Finishes.named("dark brown")!)
            let perchY = h * 0.09, br = min(w, d * 0.42) * 0.5, by = perchY + h * 0.42
            rod(SIMD3(-w / 2 + br * 0.1, perchY, -d * 0.04), SIMD3(w / 2 - br * 0.1, perchY * 0.9, d * 0.04),
                br * 0.3, wood)                                                  // the branch it grips
            ball(br, feather, 0, by, -d * 0.04).scale = SCNVector3(1, 1.1, 2.1)  // breast to tail, long along z
            ball(br * 0.62, feather, 0, by + br * 0.95, d * 0.14)                // the head is carried forward
            add(SCNCone(topRadius: 0, bottomRadius: br * 0.3, height: br * 1.1), beak,
                0, by + br * 0.9, d * 0.14 + br, rotate: SCNVector3(Float.pi / 2, 0, 0))   // a cone turned onto +z
            for s in [-1.0, 1.0] {
                ball(br * 0.08, eye, s * br * 0.3, by + br * 1.1, d * 0.14 + br * 0.4)
                ball(br * 0.8, feather, s * br * 0.62, by, -d * 0.02).scale = SCNVector3(0.25, 1, 1.5)   // folded wing
                rod(SIMD3(s * br * 0.3, by - br * 0.7, 0), SIMD3(s * br * 0.25, perchY, d * 0.01), br * 0.1, wood)
            }
            for k in 0..<3 {                                                     // tail: three feathers fanned down
                let a = (Double(k) - 1) * 0.22
                box(br * 0.3, br * 0.1, d * 0.4, feather, sin(a) * br * 0.5,
                    by - br * 0.35 - Double(k % 2) * br * 0.12, -d * 0.28, rotate: SCNVector3(0.3, Float(a), 0))
            }
        case "potions":
            let gm = m(look.body.kind == .glass ? look.body : Finishes.named("smoked glass")!)
            let cork = m(Finishes.named("straw")!), paper = m(Finishes.named("paper")!)
            let lights: [Palette.RGB] = [(0.45, 0.78, 0.16), (0.52, 0.2, 0.74), (0.95, 0.62, 0.12)]
            let shelfY = h * 0.55
            box(w * 0.96, h * 0.045, d * 0.8, frameM, 0, shelfY, 0)              // the plank
            for s in [-1.0, 1.0] { box(w * 0.05, h * 0.07, d * 0.5, frameM, s * w * 0.38, shelfY - h * 0.055, 0) }
            for k in 0..<9 {
                let onShelf = k < 5, row = onShelf ? 5 : 4, i = onShelf ? k : k - 5
                let gap = w * 0.9 / Double(row)
                let x = (Double(i) - Double(row - 1) / 2) * gap
                let base = onShelf ? shelfY + h * 0.022 : 0                      // five above, four on the floor
                let head = onShelf ? h : shelfY - h * 0.1                        // headroom for this one
                let bh = (head - base) * (0.55 + 0.4 * random(k)), r = min(bh * 0.28, gap * 0.4)
                cyl(r, bh * 0.72, gm, x, base + bh * 0.36, 0)
                ball(r, gm, x, base + bh * 0.72, 0).scale = SCNVector3(1, 0.5, 1)        // the shoulder
                let neck = r * (0.3 + 0.2 * random(k + 9))                               // necks vary as much as bodies
                cyl(neck, bh * 0.26, gm, x, base + bh * 0.85, 0)
                cyl(neck * 1.15, bh * 0.08, cork, x, base + bh, 0)
                box(r * 1.2, bh * 0.3, r * 0.08, paper, x, base + bh * 0.4, r * 0.98)    // a label on the front face
                if look.details.contains("lit") {
                    cyl(r * 0.8, bh * 0.45, glow(lights[k % 3], strength: 1.1), x, base + bh * 0.24, 0)
                }
            }
        default:
            let bone = bodyM, dark = m(Finish(.paint, (0.05, 0.045, 0.04)))
            let plinthH = h * 0.06, cr = w * 0.46, clear = h - plinthH
            cyl(min(w, d) * 0.48, plinthH, m(Finishes.named("ebony")!), 0, plinthH / 2, 0)
            let cy = plinthH + clear * 0.56
            // the cranium's width comes from w but its height from what is left over the plinth, or a wide
            // skull would stand taller than its own frame
            ball(cr, bone, 0, cy, -d * 0.04).scale = SCNVector3(1, Float(clear * 0.44 / cr), 1.2)
            let face = -d * 0.04 + cr * 1.2                                      // the front of the cranium
            ball(cr * 0.82, bone, 0, cy + cr * 0.22, face * 0.3).scale = SCNVector3(1, 0.3, 0.4)   // brow ridge
            for s in [-1.0, 1.0] {
                // a short dark cylinder sunk into the face reads as a socket; a ball would bulge out of it
                cyl(cr * 0.28, cr * 0.3, dark, s * cr * 0.4, cy, face - cr * 0.2, rotate: SCNVector3(Float.pi / 2, 0, 0))
                ball(cr * 0.3, bone, s * cr * 0.6, cy - cr * 0.35, face * 0.5).scale = SCNVector3(0.6, 0.5, 1)
            }
            add(SCNCone(topRadius: 0, bottomRadius: cr * 0.15, height: cr * 0.32), dark, 0, cy - cr * 0.42, face - cr * 0.05)
            let jawY = plinthH + h * 0.2
            ball(cr * 0.74, bone, 0, jawY + cr * 0.1, face * 0.26).scale = SCNVector3(1, 0.55, 1.05)
            for k in 0..<7 {                                                     // a row of teeth along the jaw
                box(cr * 0.08, cr * 0.1, cr * 0.07, bone, (Double(k) - 3) * cr * 0.13, jawY + cr * 0.42, face * 0.26 + cr * 0.44)
            }
            guard look.details.contains("weathered") else { return }
            for k in 0..<4 {                                                     // age mottles the resin unevenly
                let a = random(k) * 2 * .pi
                ball(cr * 0.13, m(look.body.scaled(0.82)), cr * 0.72 * cos(a), cy + cr * 0.45 * sin(a),
                     -d * 0.04 + cr * 0.6).scale = SCNVector3(1, 1, 0.25)
            }
        }
    }

    /// A fog machine, running: the cased 400 W fogger, or the chill box that takes its hose and makes the
    /// fog crawl. The fog is a squashed ball (and, on the chiller, a disc on the floor) at a transparency
    /// low enough to read as output without hiding the prop behind it.
    private func fogMachine() {
        let fog = m(Finish(.paint, (0.88, 0.9, 0.93)))
        fog.transparency = 0.12
        let dark = m(look.body.scaled(0.4))
        switch look.form {
        case "chiller":
            let tub = h * 0.78, lid = h * 0.14, port = h * 0.12
            box(w, tub, d, bodyM, 0, tub / 2, 0, round: h * 0.04)
            box(w * 0.98, lid, d * 0.98, m(look.body.scaled(1.3)), 0, tub + h * 0.025 + lid / 2, 0, round: h * 0.03)
            for k in 0..<2 { // ice jammed in the gap the lid sits proud of, pushed forward so you read it first
                let s = h * 0.09
                box(s, s, s, m(Finishes.named("glass")!), (random(k) - 0.4) * w * 0.4, tub + h * 0.005, d / 2 - s,
                    round: s * 0.2, rotate: SCNVector3(0, Float(random(k + 3)), 0))
            }
            // Hose port in at the top, drain spout out at the bottom. Both stand about 9 mm proud, because
            // a flush spout is not a spout, and the entry leaves 0.2 m at the sides for exactly these.
            add(SCNTube(innerRadius: port * 0.5, outerRadius: port * 0.7, height: w * 0.06), metalM, -w / 2 + w * 0.012, tub * 0.72, 0, rotate: SCNVector3(0, 0, Float.pi / 2))
            cyl(port * 0.55, w * 0.055, metalM, w / 2 - w * 0.012, h * 0.1, 0, rotate: SCNVector3(0, 0, Float.pi / 2))
            // What a chiller is for: the fog falls out of the spout and pools instead of rising.
            ball(h * 0.2, fog, w * 0.3, h * 0.08, d / 2 + h * 0.05).scale = SCNVector3(1.3, 0.5, 1)
            cyl(w * 0.33, h * 0.03, fog, w * 0.14, h * 0.015, d / 2 + w * 0.16)
        default: // "fogger": the 400 W case, nozzle to the front
            let ft = h * 0.06, caseH = h * 0.78, top = h * 0.84, oy = h * 0.06 + h * 0.78 * 0.82
            box(w, caseH, d, bodyM, 0, ft + caseH / 2, 0, round: h * 0.03)
            for x in [-1.0, 1.0] { for z in [-1.0, 1.0] { cyl(h * 0.03, ft, dark, x * w * 0.34, ft / 2, z * d * 0.34) } }
            for k in 0..<5 { // louvres: slats set back from the front face and tipped down, so the gaps read as shadow
                box(w * 0.6, h * 0.016, h * 0.02, dark, 0, ft + caseH * (0.18 + 0.1 * Double(k)), d / 2 - h * 0.02,
                    round: 0.002, rotate: SCNVector3(-0.35, 0, 0))
            }
            cyl(w * 0.17, h * 0.05, dark, 0, oy, d / 2 - h * 0.02, rotate: SCNVector3(Float.pi / 2, 0, 0))
            add(SCNTorus(ringRadius: w * 0.2, pipeRadius: w * 0.035), m(Finishes.named("chrome")!), 0, oy, d / 2 - h * 0.02, rotate: SCNVector3(Float.pi / 2, 0, 0))
            cyl(w * 0.05, h * 0.012, glow((1, 0.1, 0.06), strength: 1.3), w * 0.3, ft + caseH * 0.22, d / 2 - h * 0.008,
                rotate: SCNVector3(Float.pi / 2, 0, 0)) // standby light, sunk into the face
            for x in [-1.0, 1.0] { cyl(w * 0.03, h * 0.08, metalM, x * w * 0.22, top + h * 0.04, 0) }
            rod(SIMD3(-w * 0.22, top + h * 0.08, 0), SIMD3(w * 0.22, top + h * 0.08, 0), w * 0.035, metalM) // carry bail
            // The lead is the one part allowed past w / 2: it lies on the floor, inside the side clearance.
            var p = SIMD3<Double>(-w / 2 + 0.004, ft + caseH * 0.15, 0)
            for k in 0..<3 {
                let q = SIMD3(p.x - w * 0.28, h * 0.02, p.z + (random(k) - 0.5) * d * 0.6)
                rod(p, q, h * 0.016, m(Finishes.named("black")!))
                p = q
            }
            ball(h * 0.3, fog, 0, oy - h * 0.04, d / 2 + h * 0.3).scale = SCNVector3(1.2, 0.55, 1.5)
        }
    }

    /// A prop light: the flickering-flame LED on a ground spike, or a purple LED flood on a yoke. The flame
    /// is three glowing cones of falling radius, each leaning a little differently — a taper reads as fire
    /// where a single cone reads as a traffic cone.
    private func propLight() {
        switch look.form {
        case "strobe":
            let caseW = w * 0.74, caseH = h * 0.72, caseD = d * 0.7
            box(w * 0.92, h * 0.05, d * 0.7, m(look.body.scaled(0.8)), 0, h * 0.025, 0) // wide enough to stand the yoke on
            box(caseW, caseH, caseD, bodyM, 0, h * 0.55, 0, round: w * 0.04)
            for x in [-1.0, 1.0] { // the yoke it tilts on, bolted at the case's centre of rotation
                box(w * 0.07, h * 0.52, d * 0.5, metalM, x * (caseW / 2 + w * 0.055), h * 0.3, 0, round: w * 0.02)
                ball(w * 0.055, metalM, x * (caseW / 2 + w * 0.055), h * 0.55, 0)
            }
            box(caseW * 0.84, caseH * 0.66, h * 0.012, glow((0.55, 0.25, 0.9), strength: 1.4), 0, h * 0.55, caseD / 2 - h * 0.004)
            for k in 0..<4 { // a grille of bars across the lens, which is most of what you see of a flood
                box(w * 0.022, caseH * 0.7, h * 0.02, metalM, (Double(k) - 1.5) * caseW * 0.2, h * 0.55, caseD / 2)
            }
        default: // "flame": the LED fire light, aimed up and forward off its spike
            let spike = h * 0.4, headR = w * 0.3, headL = h * 0.26, aim = 0.4
            add(SCNCone(topRadius: w * 0.06, bottomRadius: 0, height: spike), m(look.body.scaled(0.7)), 0, spike / 2, 0)
            ball(w * 0.1, metalM, 0, spike, 0) // the ball joint the head swivels on
            let axis = SIMD3<Double>(0, cos(aim), sin(aim))
            let mid = SIMD3<Double>(0, spike + h * 0.14, 0)
            let aimed = SCNVector3(Float(aim), 0, 0)
            cyl(headR, headL, bodyM, mid.x, mid.y, mid.z, rotate: aimed)
            let lens = mid + axis * (headL / 2)
            cyl(headR * 0.92, h * 0.012, glow((1, 0.55, 0.15), strength: 1.2), lens.x, lens.y, lens.z, rotate: aimed)
            let flame = glow((1, 0.5, 0.12), strength: 1.4)
            var p = lens
            for k in 0..<3 {
                // Each cone eats 55% of the headroom left under h and stands straighter than the last, so
                // the flame leaves the lens on the aim, turns vertical as fire does, and can never poke
                // out of the top. It keeps a third of the aim's lean: any more and the base of the first
                // cone is through the front of a frame only 0.08 deep.
                let len = (h - p.y) * 0.55, tip = aim * 0.35 * (1 - Double(k) / 3)
                add(SCNCone(topRadius: headR * (0.6 - 0.18 * Double(k)), bottomRadius: headR * (0.85 - 0.2 * Double(k)), height: len),
                    flame, p.x + (random(k + 5) - 0.5) * w * 0.06, p.y + len / 2 * cos(tip), p.z + len / 2 * sin(tip),
                    rotate: SCNVector3(Float(tip), Float((random(k) - 0.5) * 0.3), 0))
                p = SIMD3(p.x, p.y + len * cos(tip), p.z + len * sin(tip))
            }
        }
    }

    /// A severed arm lying along z with the hand at the front, so what you see first is a hand on the floor
    /// and the shock is the torn shoulder when you look twice. Everything rests on the floor at its own
    /// radius: an arm this flat (h 0.1) has no room to lie on anything.
    private func gore() {
        let flesh = bodyM, blood = m(Finishes.named("blood red")!)
        let shoulder = SIMD3<Double>(-w * 0.1, h * 0.46, -d / 2 + h * 0.3)
        let elbow = SIMD3<Double>(w * 0.12, h * 0.4, -d * 0.06)
        let wrist = SIMD3<Double>(-w * 0.02, h * 0.28, d * 0.2)
        rod(shoulder, elbow, h * 0.34, flesh, r2: h * 0.46) // upper arm, thick at the shoulder
        ball(h * 0.36, flesh, elbow.x, elbow.y, elbow.z)
        rod(elbow, wrist, h * 0.26, flesh, r2: h * 0.34) // forearm, turned a little in off the elbow
        let palm = SIMD3<Double>(wrist.x - w * 0.02, h * 0.19, d * 0.3)
        box(w * 0.58, h * 0.22, d * 0.14, flesh, palm.x, palm.y, palm.z, round: h * 0.06) // palm down
        let tipZ = d / 2 - h * 0.06
        for k in 0..<5 {
            let thumb = k == 4
            let x0 = palm.x + (thumb ? -w * 0.22 : (Double(k) - 1.5) * w * 0.14)
            let x1 = thumb ? x0 - w * 0.08 : x0
            let z0 = thumb ? d * 0.24 : d * 0.35, r = h * (thumb ? 0.1 : 0.075)
            let curl = 0.25 + 0.6 * random(k + 3) // every finger is clenched by a different amount
            let midZ = z0 + (tipZ - z0) * 0.5
            let knuckle = SIMD3<Double>(x1, palm.y - h * 0.02 * curl, midZ)
            rod(SIMD3(x0, palm.y, z0), knuckle, r, flesh, r2: r * 1.25)
            let tip = SIMD3<Double>(x1 + (thumb ? -w * 0.05 : 0), palm.y - h * 0.06 * curl,
                                    midZ + (tipZ - midZ) * (1 - 0.3 * curl))
            rod(knuckle, tip, r * 0.8, flesh, r2: r)
            cyl(r * 0.7, h * 0.01, m(Finishes.named("bone white")!), tip.x, tip.y + r * 0.7, tip.z) // nail
        }
        // The torn end: a ragged collar of blood round the bone, kept inside -d / 2 so the panel stays true.
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + random(k)
            ball(h * (0.16 + 0.1 * random(k + 7)), blood, shoulder.x + h * 0.2 * cos(a),
                 shoulder.y + h * 0.2 * sin(a), -d / 2 + h * 0.3)
        }
        cyl(h * 0.13, h * 0.3, m(Finishes.named("bone")!), shoulder.x, shoulder.y, -d / 2 + h * 0.24,
            rotate: SCNVector3(Float.pi / 2, 0, 0))
        for k in 0..<2 { // two drips, flattened where they met the floor
            ball(h * 0.08, blood, shoulder.x + (random(k) - 0.5) * w * 0.5, h * 0.04,
                 -d * (0.3 + 0.1 * random(k + 5))).scale = SCNVector3(1, 0.4, 1.3)
        }
    }

    /// A wrought-iron graveyard fence panel: a flat panel on the floor, stout posts at the ends and
    /// spear-pointed pickets between the rails. A rusted one leans and has a picket shoved out of true,
    /// because a panel that is dead straight reads as new, which is the wrong century.
    private func fence() {
        let iron = bodyM, rust = m(Finish(.patina, (0.4, 0.22, 0.13)))
        let worn = look.details.contains("rusted")
        // The lean tips the panel back on its posts. Capped at 0.02 rad: the drift of the top plus half a
        // post is all the room there is inside d / 2 (the panel is only 0.1 deep).
        let lean = worn ? (random(1) - 0.5) * 0.04 : 0
        let tilt = SCNVector3(Float(lean), 0, 0)
        func zAt(_ y: Double) -> Double { -y * sin(lean) }
        let ps = min(d * 0.55, w * 0.06), postH = h * 0.86
        for x in [-1.0, 1.0] {
            let px = x * (w / 2 - ps / 2)
            box(ps, postH, ps, iron, px, postH / 2, zAt(postH / 2), rotate: tilt)
            box(ps * 1.25, h * 0.03, ps * 1.25, iron, px, postH, zAt(postH), rotate: tilt) // cap collar
            add(SCNCone(topRadius: 0, bottomRadius: ps * 0.62, height: h * 0.1), iron,
                px, postH + h * 0.06, zAt(postH + h * 0.06), rotate: tilt) // finial
        }
        let span = w - 2 * ps
        for y in [h * 0.16, h * 0.72] { box(span, h * 0.035, d * 0.3, iron, 0, y, zAt(y), rotate: tilt) }
        let count = 10, bent = Int(random(4) * Double(count)), shaft = h * 0.84
        for k in 0..<count {
            // Pickets pass in front of the rails, as iron ones do, and a couple have gone further than the
            // rest: rust never takes a whole panel evenly.
            let x = ((Double(k) + 0.5) / Double(count) - 0.5) * (span - 0.2 * ps)
            let mat = worn && random(k + 20) > 0.74 ? rust : iron
            let bend = worn && k == bent ? (random(9) - 0.5) * 0.24 : 0 // capped: an end picket must stay inside w / 2
            let twist = SCNVector3(Float(lean), 0, Float(bend))
            box(w * 0.014, shaft, d * 0.18, mat, x + bend * shaft * 0.4, shaft / 2, zAt(shaft / 2) + d * 0.08, rotate: twist)
            add(SCNCone(topRadius: 0, bottomRadius: w * 0.016, height: h * 0.14), mat,
                x + bend * shaft * 0.9, shaft + h * 0.07, zAt(shaft + h * 0.07) + d * 0.08, rotate: twist)
        }
    }

    /// A bare twisted tree: a trunk of four leaning rods, then primary branches off the crown with two
    /// twigs each, all thinning and all jittered so no two trees in a yard match. The reach budget is the
    /// tight part — trunk drift plus a primary plus a twig has to land inside w / 2 — so every span is a
    /// fraction of w and every rise a fraction of the headroom left under h.
    private func tree() {
        let bark = bodyM, lit = look.details.contains("lit")
        let leaf = m(Finish(.foliage, (0.19, 0.13, 0.11)))
        var p = SIMD3<Double>(0, 0, 0), r = h * 0.045
        for k in 0..<4 {
            let next = SIMD3(p.x + (random(k) - 0.5) * w * 0.06, h * 0.5 * Double(k + 1) / 4,
                             p.z + (random(k + 5) - 0.5) * w * 0.06)
            let thin = r * (0.76 - 0.06 * random(k + 9))
            rod(p, next, thin, bark, r2: r)
            ball(thin * 1.2, bark, next.x, next.y, next.z) // the knot at every kink in the trunk
            p = next
            r = thin
        }
        let crown = p, limbs = 4 + Int(random(2) * 2)
        var bulbs: [SIMD3<Double>] = []
        for k in 0..<limbs {
            let a = Double(k) * 2 * .pi / Double(limbs) + random(k + 20) * 0.8
            let reach = w * (0.18 + 0.06 * random(k + 30))
            let tip = crown + SIMD3(reach * cos(a), h * (0.24 + 0.1 * random(k + 40)), reach * sin(a))
            rod(crown, tip, r * 0.4, bark, r2: r * 0.8)
            for s in 0..<2 {
                let base = crown + (tip - crown) * (0.5 + 0.35 * Double(s))
                let b = a + (s == 0 ? 0.7 : -0.7) * (0.6 + 0.6 * random(k * 3 + s))
                let out = w * (0.1 + 0.05 * random(k + s + 50))
                let twig = base + SIMD3(out * cos(b), h * (0.1 + 0.07 * random(k + s + 60)), out * sin(b))
                rod(base, twig, r * 0.14, bark, r2: r * 0.32)
                ball(r * 0.34, bark, base.x, base.y, base.z) // the knot at the fork
                if lit { bulbs.append((base + twig) / 2) }
                if random(k + s + 70) > 0.4 {
                    ball(w * 0.03, leaf, twig.x, twig.y - h * 0.01, twig.z).scale = SCNVector3(1, 0.3, 1.3)
                }
            }
        }
        for (k, b) in bulbs.enumerated() { // eight to ten warm bulbs, each on a short flex
            rod(b, SIMD3(b.x, b.y - h * 0.02, b.z), h * 0.002, bark)
            ball(h * 0.007 + h * 0.003 * random(k + 80), glow(), b.x, b.y - h * 0.027, b.z)
        }
    }

    // MARK: wall decor and lighting

    /// A poster on the wall: the framed one-sheet, a stretched canvas on battens, a blacklight print that
    /// fluoresces, a lenticular portrait, a dented tin sign, or a big projection screen. Hung by its centre
    /// line at 1.55 m, which is where a picture rail puts one, rather than at a fraction of its own height.
    private func poster() {
        let z0 = -d / 2, ink = z0 + d * 0.62              // the wall face, and the plane the printing sits on
        let screen = look.form == "projection"
        // A screen hangs a little lower than a print. Clamped off the 2.25 m a 2.3 m ceiling leaves, with
        // the 0.08 h over the sheet a canvas batten and its cord need.
        let cy = min(screen ? 1.45 : 1.55, 2.25 - h * 0.58)
        switch look.form {
        case "canvas":
            // No frame at all: the print is stretched between two battens and hung on a cord over the top
            // one, so the ground is the entry's own cloth colour with a dark figure standing in the middle.
            let top = cy + h * 0.44, cord = m(Finishes.named("jute")!)
            box(w, h * 0.88, d * 0.3, m(look.body), 0, cy, z0 + d * 0.4)
            ball(min(w, h) * 0.22, m(Finish(.paint, (0.14, 0.12, 0.14))), 0, cy, ink).scale = SCNVector3(1, 1.6, 0.05)
            for s in [-1.0, 1.0] {
                cyl(d * 0.3, w, m(kit.wood), 0, cy + s * h * 0.44, z0 + d * 0.4, rotate: SCNVector3(0, 0, Float.pi / 2))
                rod(SIMD3(s * w * 0.44, top, z0 + d * 0.4), SIMD3(0, top + h * 0.1, z0 + d * 0.4), d * 0.06, cord)
            }
        case "blacklight":
            // The sheet is the body colour (black); UV ink is not, so the skull glows in fluorescent green
            // whatever the sheet is — that contrast under a blacklight is the whole product.
            let uv: Palette.RGB = (0.55, 0.95, 0.45), lit = glow(uv, strength: 0.95)
            box(w, h, d * 0.3, m(Finish(.paint, (0.04, 0.04, 0.06))), 0, cy, z0 + d * 0.4)
            let cranium = cyl(min(w * 0.32, h * 0.21), d * 0.2, lit, 0, cy + h * 0.1, ink, rotate: SCNVector3(Float.pi / 2, 0, 0))
            for s in [-1.0, 1.0] {                        // the sockets stay dark: ink fluoresces, paper does not
                ball(min(w, h) * 0.075, m(Finish(.paint, (0.03, 0.03, 0.05))), s * w * 0.1, cy + h * 0.13, ink)
                    .scale = SCNVector3(1, 1, 0.1)        // flattened: a sheet is 0.02 m deep, a socket is not
            }
            for k in 0..<5 {                              // the grin: five short bars, which is how teeth read
                box(w * 0.04, h * 0.05, d * 0.2, lit, (Double(k) - 2) * w * 0.055, cy - h * 0.11, ink)
            }
            neonLight(cranium, uv, intensity: 62, reach: 1.8)
        case "lenticular":
            // A moulded plastic frame, a dim portrait, then the ridges: a row of thin vertical bars is what
            // catches the light on a lenticular print and swaps the face as you walk past it.
            let ridge = m(Finish(.lacquer, (0.72, 0.74, 0.78)))
            box(w, h, d * 0.55, m(look.body.with(.lacquer)), 0, cy, z0 + d * 0.3, round: min(w, h) * 0.06)
            box(w * 0.86, h * 0.86, d * 0.2, m(Finish(.paint, kit.art[0])), 0, cy, ink - d * 0.1)
            ball(min(w, h) * 0.2, m(Finish(.paint, (0.08, 0.07, 0.09))), 0, cy + h * 0.07, ink - d * 0.05)
                .scale = SCNVector3(1, 1.3, 0.06)
            for k in 0..<14 { box(w * 0.012, h * 0.84, d * 0.12, ridge, (Double(k) - 6.5) * w * 0.062, cy, ink) }
        case "tin":
            // Rounded corners, four screws and a painted band of lettering: a reproduction sign, rusted off
            // the seed, because a plate with no specks on it reads as new, which is the wrong decade.
            let paint = m(Finish(.paint, (0.78, 0.72, 0.58))), letters = m(Finish(.paint, (0.1, 0.09, 0.09)))
            box(w, h, d * 0.4, bodyM, 0, cy, z0 + d * 0.35, round: min(w, h) * 0.12)
            for s in [-1.0, 1.0] { for t in [-1.0, 1.0] {
                cyl(min(w, h) * 0.022, d * 0.2, metalM, s * w * 0.43, cy + t * h * 0.4, ink, rotate: SCNVector3(Float.pi / 2, 0, 0))
            } }
            box(w * 0.84, h * 0.32, d * 0.15, paint, 0, cy + h * 0.05, ink)
            for k in 0..<4 { box(w * 0.15, h * 0.13, d * 0.1, letters, (Double(k) - 1.5) * w * 0.19, cy + h * 0.05, ink + d * 0.03) }
            for k in 0..<5 {                              // rust: flattened, so each speck stays in the paint
                ball(min(w, h) * (0.03 + 0.04 * random(k)), m(Finish(.patina, (0.42, 0.24, 0.14))),
                     (random(k + 5) - 0.5) * w * 0.9, cy + (random(k + 9) - 0.5) * h * 0.86, ink)
                    .scale = SCNVector3(1, 1, 0.08)
            }
        case "projection":
            // A sheet of projection cloth on grommets, lit from behind: the figure stands between the cloth
            // and the wall, so what you see is a shape through the weave rather than a prop hung on it.
            let cloth = m(look.body), fig = glow(look.body.rgb, strength: 0.95)
            cloth.transparency = 0.35
            cloth.isDoubleSided = true                    // a hanging sheet shows you its back as well
            // Pressed flat and held back behind the cloth: a figure 0.6 m across is round in z as well, and
            // the frame is only 0.03 m deep, so at any real thickness it comes through the screen.
            let head = ball(min(w * 0.1, h * 0.14), fig, -w * 0.08, cy + h * 0.22, z0 + d * 0.35)
            head.scale = SCNVector3(1, 1, 0.03)
            add(SCNCone(topRadius: min(w * 0.08, h * 0.11), bottomRadius: min(w * 0.18, h * 0.25), height: h * 0.5),
                fig, -w * 0.08, cy - h * 0.05, z0 + d * 0.35).scale = SCNVector3(1, 1, 0.03)
            box(w, h, d * 0.2, cloth, 0, cy, z0 + d * 0.74)
            for s in [-1.0, 1.0] { for t in [-1.0, 1.0] {
                add(SCNTube(innerRadius: min(w, h) * 0.012, outerRadius: min(w, h) * 0.022, height: d * 0.2),
                    metalM, s * w * 0.47, cy + t * h * 0.47, z0 + d * 0.74, rotate: SCNVector3(Float.pi / 2, 0, 0))
            } }
            neonLight(head, look.body.rgb, intensity: 72, reach: 2.2)
        default:
            // "movie": a glossy one-sheet in a slim moulding — three flat blocks of kit.art for the artwork,
            // a pale border left round the print, and the billing block across the bottom third.
            box(w, h, d * 0.5, m(Finish(.lacquer, (0.08, 0.08, 0.09))), 0, cy, z0 + d * 0.3, round: d * 0.1)
            box(w * 0.94, h * 0.95, d * 0.2, m(look.body), 0, cy, z0 + d * 0.5)
            for k in 0..<3 {
                let bh = h * (0.3 - 0.07 * Double(k))
                box(w * (0.82 - 0.16 * Double(k)), bh, d * 0.1, m(Finish(.paint, kit.art[k % kit.art.count])),
                    (random(k) - 0.5) * w * 0.1, cy + h * 0.2 - bh * Double(k) * 0.9, ink)
            }
            box(w * 0.86, h * 0.14, d * 0.1, m(Finish(.paint, (0.07, 0.07, 0.08))), 0, cy - h * 0.34, ink)
            for k in 0..<3 {                              // the credits, suggested with three pale bars
                box(w * 0.2, h * 0.03, d * 0.08, m(Finish(.paint, (0.85, 0.83, 0.78))), (Double(k) - 1) * w * 0.24,
                    cy - h * 0.34, ink + d * 0.03)
            }
        }
    }

    /// An LED neon sign on the wall, centred at 1.60 m: a ghost, a word of script, a bat, a pumpkin or a
    /// skull, all bent from the same silicone flex on a clear acrylic plate. The flex glows at full strength
    /// and one segment carries a real light, because a neon sign that does not light the wall behind it
    /// reads as painted plastic.
    private func neonSign() {
        let z0 = -d / 2, zt = z0 + d * 0.66               // the wall, and the plane the tubing stands off it
        let cy = min(1.6, 2.25 - h * 0.55)                // eye level, clamped under a low ceiling
        let r = min(w, h) * 0.04, neon = glow(look.body.rgb, strength: 0.95)
        let plate = m(Finish(.glass, (0.86, 0.9, 0.93)))
        plate.transparency = 0.25                         // clear acrylic: what a shop-bought sign is screwed to
        box(w * 0.96, h * 0.94, d * 0.25, plate, 0, cy, z0 + d * 0.22, round: min(w, h) * 0.05)
        /// Points along an arc of flex at the tubing plane; the tube itself is rods between them.
        func arc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, _ n: Int) -> [SIMD3<Double>] {
            (0...n).map { k in
                let a = a0 + (a1 - a0) * Double(k) / Double(n)
                return SIMD3<Double>(x + rx * cos(a), y + ry * sin(a), zt)
            }
        }
        var paths: [[SIMD3<Double>]] = []
        switch look.form {
        case "text":
            // There is no SCNText in this scene, so a word is nine strokes in a row: a leaning rod, every
            // third one a loop, over a baseline. At arm's length that reads as cursive, which is the job.
            let step = w * 0.84 / 9, base = cy - h * 0.12
            for k in 0..<9 {
                let x = -w * 0.42 + step * (Double(k) + 0.5), tall = h * (0.3 + 0.22 * random(k))
                paths.append(k % 3 == 2 ? arc(x, base + tall * 0.45, step * 0.4, tall * 0.45, -1.4, 4.4, 7)
                                        : [SIMD3<Double>(x - step * 0.22, base, zt), SIMD3<Double>(x + step * 0.22, base + tall, zt)])
            }
            paths.append([SIMD3<Double>(-w * 0.44, base, zt), SIMD3<Double>(w * 0.44, base, zt)])
            // The dimmer on the cable: the one detail that says this is USB flex rather than glass neon.
            box(w * 0.07, h * 0.16, d * 0.45, m(Finishes.named("black")!), w * 0.32, cy - h * 0.62, z0 + d * 0.4, round: 0.004)
            rod(SIMD3(w * 0.32, base - h * 0.08, z0 + d * 0.4), SIMD3(w * 0.32, cy - h * 0.54, z0 + d * 0.4), r * 0.35,
                m(Finishes.named("black")!))
        case "bat":
            // A sign this shape is wide and short, so a wing drawn as one chevron reads as an envelope. It
            // takes a leading edge that rises to the wrist, a dropped tip, then a scalloped trailing edge
            // with a finger between the scallops: that notch is the whole silhouette of a bat.
            let span = w * 0.45, br = min(w, h) * 0.085
            ball(br, neon, 0, cy, zt).scale = SCNVector3(0.7, 1.4, 0.5)
            for s in [-1.0, 1.0] {
                paths.append([SIMD3<Double>(s * br * 0.9, cy + h * 0.2, zt), SIMD3<Double>(s * span * 0.55, cy + h * 0.3, zt),
                              SIMD3<Double>(s * span, cy + h * 0.06, zt), SIMD3<Double>(s * span * 0.5, cy - h * 0.14, zt),
                              SIMD3<Double>(s * span * 0.22, cy + h * 0.02, zt), SIMD3<Double>(0, cy - h * 0.26, zt)])
                rod(SIMD3(s * br * 0.5, cy + br, zt), SIMD3(s * br * 1.1, cy + br * 2.4, zt), r * 0.8, neon)   // an ear
            }
        case "pumpkin":
            // One closed ring of flex with a stalk on it, and the face carved in the same tubing.
            let pr = min(w * 0.42, h * 0.4)
            paths.append(arc(0, cy, pr, pr * 1.05, 0, 2 * .pi, 14))
            paths.append([SIMD3<Double>(0, cy + pr * 1.02, zt), SIMD3<Double>(w * 0.05, cy + pr * 1.32, zt)])
            for s in [-1.0, 1.0] {                        // a triangular eye and half the grin, either side
                paths.append([SIMD3<Double>(s * pr * 0.2, cy + pr * 0.12, zt), SIMD3<Double>(s * pr * 0.56, cy + pr * 0.42, zt),
                              SIMD3<Double>(s * pr * 0.56, cy + pr * 0.12, zt), SIMD3<Double>(s * pr * 0.2, cy + pr * 0.12, zt)])
                paths.append([SIMD3<Double>(s * pr * 0.62, cy - pr * 0.28, zt), SIMD3<Double>(s * pr * 0.3, cy - pr * 0.56, zt),
                              SIMD3<Double>(0, cy - pr * 0.34, zt)])
            }
        case "skull":
            // A cranium over a jaw line, with a ring for each socket: the three lengths a skull is bent from.
            let sr = min(w * 0.4, h * 0.34)
            paths.append(arc(0, cy + h * 0.05, sr, sr * 1.1, -0.2, .pi + 0.2, 10))
            paths.append([SIMD3<Double>(-sr * 0.92, cy + h * 0.05, zt), SIMD3<Double>(-sr * 0.6, cy - h * 0.3, zt),
                          SIMD3<Double>(sr * 0.6, cy - h * 0.3, zt), SIMD3<Double>(sr * 0.92, cy + h * 0.05, zt)])
            for s in [-1.0, 1.0] { paths.append(arc(s * sr * 0.42, cy + h * 0.08, sr * 0.26, sr * 0.26, 0, 2 * .pi, 8)) }
        default:
            // "ghost": a half-circle crown on two short sides, then a hem of three scallops under it — the
            // sheet ghost every flex sign bends, drawn as one path so it reads as one length of tubing.
            let rx = w * 0.42, ry = h * 0.3, hem = cy - h * 0.2
            paths.append([SIMD3<Double>(-rx, hem, zt)] + arc(0, cy + h * 0.1, rx, ry, .pi, 0, 8) + [SIMD3<Double>(rx, hem, zt)])
            paths.append((0...6).map { k in
                let t = Double(k) / 6
                return SIMD3<Double>(-rx + 2 * rx * t, hem - h * 0.09 * abs(sin(t * .pi * 3)), zt)
            })
            for s in [-1.0, 1.0] {                        // the eyes: flex leaves them unlit, so they stay dark
                ball(r * 1.4, m(Finish(.lacquer, (0.05, 0.04, 0.06))), s * rx * 0.4, cy + h * 0.1, zt + r * 0.6)
                    .scale = SCNVector3(1, 1, 0.4)
            }
        }
        for (k, p) in paths.enumerated() {
            let seg = neonTube(p, r, neon)
            // One light, on the first run of tubing: scaled off the sign's width, and dying away inside a
            // few metres, so it washes its own wall rather than lighting the far side of the room.
            if k == 0 { neonLight(seg, look.body.rgb, intensity: 45 + 34 * min(1, w), reach: 1.9) }
        }
    }

    /// A run of festoon lights along the top of the wall: pegs at 2.05 m with the wire sagging between them
    /// and the lamps hung underneath — two-colour fairy beads, little pumpkins, a continuous glowing rope,
    /// ghost caps or icicle drops. The sag is what sells a string of lights; a straight wire reads as a cable.
    private func stringLights() {
        let z0 = -d / 2, zw = z0 + d * 0.5, pegY = 2.05   // picture-rail height, well clear of a 2.3 m ceiling
        let sag = min(h * 0.5, 0.2)                       // the entry's own height is the depth of one swag
        let rope = look.form == "rope", swags = 3, per = 7
        let half = w / 2 - min(d * 0.5, 0.035)            // inset, so the end lamps hang inside the footprint
        var pts: [SIMD3<Double>] = []
        for s in 0..<swags {
            for k in (s == 0 ? 0 : 1)...per {
                // A parabola, not an arc of a circle: it is what a slack wire between two pegs hangs in.
                let t = Double(k) / Double(per), x = -half + 2 * half * (Double(s) + t) / Double(swags)
                pts.append(SIMD3(x, pegY - sag * 4 * t * (1 - t), zw))
            }
        }
        let flex = m(Finishes.named("black")!)
        let wire = neonTube(pts, rope ? min(d * 0.2, 0.012) : min(d * 0.05, 0.003),
                            rope ? glow(look.body.rgb, strength: 0.95) : flex)
        for s in 0...swags {                              // the pegs: a run this long is hung, not stuck on
            cyl(min(d * 0.08, 0.004), d * 0.4, metalM, -half + 2 * half * Double(s) / Double(swags), pegY + d * 0.12,
                z0 + d * 0.3, rotate: SCNVector3(Float.pi / 2, 0, 0))
        }
        guard !rope else { neonLight(wire, look.body.rgb, intensity: 72, reach: 2.2); return }
        let bead = min(d * 0.28, 0.018)
        let warm = glow(look.body.rgb, strength: 0.95), violet = glow((0.46, 0.18, 0.78), strength: 0.95)
        var lamp: SCNNode?
        for (k, p) in pts.enumerated() where k % (look.form == "icicle" ? 4 : 1) == 0 {
            let made: SCNNode
            switch look.form {
            case "pumpkin":
                made = ball(bead * 1.5, warm, p.x, p.y - bead * 2.2, p.z)
                made.scale = SCNVector3(1.15, 0.8, 1.15)  // squashed: a gourd rather than a bauble
                cyl(bead * 0.3, bead * 0.9, m(Finish(.wood, (0.3, 0.34, 0.16))), p.x, p.y - bead * 1.2, p.z)
            case "ghost":
                made = ball(bead * 1.2, warm, p.x, p.y - bead * 2, p.z)
                add(SCNCone(topRadius: bead * 1.1, bottomRadius: bead * 1.7, height: bead * 1.8), warm,
                    p.x, p.y - bead * 3.1, p.z)           // the skirt under the cap, flared
            case "icicle":
                made = ball(bead * 0.7, warm, p.x, p.y - bead * 2, p.z)
                rod(p, SIMD3(p.x, p.y - bead * 8, p.z), bead * 0.12, flex)
                for j in 2...4 { ball(bead * 0.7, warm, p.x, p.y - bead * 2 * Double(j), p.z) }
            default:                                      // "fairy": the dual-colour run, bead about bead
                made = ball(bead * 0.75, k % 2 == 0 ? warm : violet, p.x, p.y - bead * 1.2, p.z)
            }
            if lamp == nil, k >= pts.count / 2 { lamp = made }   // the light goes on a lamp near the middle
        }
        if let lamp { neonLight(lamp, look.body.rgb, intensity: 56, reach: 2) }
    }

    /// An LED strip against the wall: a cove line at 2.15 m, just under a low ceiling, with its diffuser
    /// facing into the room; the same line in RGBIC, whose colour walks along its length, which is what the
    /// IC in the name does; or a short UV bar at 1.9 m on brackets, pointed down at the props under it.
    private func ledStrip() {
        let z0 = -d / 2
        switch look.form {
        case "uv":
            let y = 1.9, bar = w * 0.9, br = min(d * 0.26, 0.022)
            for s in [-1.0, 1.0] {                        // two stamped brackets: all that holds a UV bar up
                box(br, br * 3, d * 0.5, metalM, s * bar * 0.46, y + br * 1.6, z0 + d * 0.3, round: 0.002)
            }
            box(bar, br * 2.2, d * 0.45, m(look.body.scaled(0.4)), 0, y + br * 1.3, z0 + d * 0.34, round: br * 0.4)
            cyl(br, bar, glow(look.body.rgb, strength: 0.95), 0, y, z0 + d * 0.5, rotate: SCNVector3(0, 0, Float.pi / 2))
            for s in [-1.0, 1.0] {                        // end caps, where the mains lead goes in
                cyl(br * 1.15, bar * 0.04, metalM, s * bar * 0.5, y, z0 + d * 0.5, rotate: SCNVector3(0, 0, Float.pi / 2))
            }
            // The lens under the tube carries the light: a UV bar is hung to wash what is below it, so the
            // lamp sits at the bottom of the fitting and reaches further than a sign's would.
            let lens = box(bar * 0.96, br * 0.5, d * 0.4, glow(look.body.rgb, strength: 0.95), 0, y - br, z0 + d * 0.5)
            neonLight(lens, look.body.rgb, intensity: 95, reach: 2.4)
        default:
            // An aluminium channel screwed up high, on clips, with the diffuser snapped into its face.
            let y = 2.15, ch = min(d * 0.6, 0.02)
            box(w, ch, d * 0.55, metalM, 0, y, z0 + d * 0.3, round: 0.002)
            for k in 0..<4 { box(ch * 0.8, ch * 1.4, d * 0.3, metalM, (Double(k) - 1.5) * w * 0.3, y, z0 + d * 0.12) }
            // RGBIC addresses its LEDs in groups, so the run is drawn in six segments with the colour walked
            // from the body colour towards a violet; a plain cove is one length of one colour.
            let segs = look.form == "rgbic" ? 6 : 1, c = look.body.rgb, second: Palette.RGB = (0.34, 0.12, 0.72)
            var mid: SCNNode?
            for k in 0..<segs {
                let t = segs == 1 ? 0 : Double(k) / Double(segs - 1)
                let rgb: Palette.RGB = (c.0 + (second.0 - c.0) * t, c.1 + (second.1 - c.1) * t, c.2 + (second.2 - c.2) * t)
                let seg = box(w / Double(segs) * 0.98, ch * 0.7, d * 0.2, glow(rgb, strength: 0.95),
                              -w / 2 + w * (Double(k) + 0.5) / Double(segs), y - ch * 0.15, z0 + d * 0.62)
                if k == segs / 2 { mid = seg }
            }
            // One light, in the middle of the run and scaled to how long it is: a 2.4 m cove throws a lot
            // more light than a 0.9 m one, and both have to die away before the opposite wall.
            if let mid { neonLight(mid, c, intensity: 50 + 28 * min(2, w), reach: 2.2) }
        }
    }

    /// A gobo projector, which stands on the floor: a weatherproof case on a yoke and a ground spike, and
    /// the part that matters — the beam it throws forward and up into the room, with its pattern scattered
    /// over the far end of it.
    private func projector() {
        let spike = h * 0.38, caseH = h * 0.42, caseW = w * 0.74
        add(SCNCone(topRadius: w * 0.08, bottomRadius: 0, height: spike), m(look.body.scaled(0.7)), 0, spike / 2, 0)
        let yoke = spike + caseH * 0.6                    // the height the case pivots at
        box(caseW, caseH, d * 0.6, bodyM, 0, yoke, 0, round: w * 0.06)
        for s in [-1.0, 1.0] {                            // the yoke it tilts on, and the bolt through it
            box(w * 0.07, caseH * 1.1, d * 0.5, metalM, s * (caseW / 2 + w * 0.05), spike + caseH * 0.45, 0, round: w * 0.02)
            ball(w * 0.05, metalM, s * (caseW / 2 + w * 0.05), yoke, 0)
        }
        // The case is charcoal, so the beam cannot take the body colour: a swirl projector throws violet, a
        // gobo one the cold white its stencils are cut for.
        let swirl = look.form == "swirl", rgb: Palette.RGB = swirl ? (0.52, 0.2, 0.86) : (0.5, 0.88, 0.72)
        let lensR = min(caseW, d * 0.6) * 0.38, lensZ = d * 0.3 + lensR * 0.2
        add(SCNTorus(ringRadius: lensR, pipeRadius: lensR * 0.22), metalM, 0, yoke, d * 0.3, rotate: SCNVector3(Float.pi / 2, 0, 0))
        cyl(lensR * 0.9, d * 0.1, glow(rgb, strength: 0.95), 0, yoke, lensZ, rotate: SCNVector3(Float.pi / 2, 0, 0))
        // Aimed up about 29°, but no further than keeps the end of the beam under 2.25 m: sin x <= x, so
        // bounding the rise by reach * aim is safe without solving for the angle.
        let reach = max(w * 9, 1.2), aim = min(0.5, max(0, 2.15 - yoke) / reach)
        let axis = SIMD3<Double>(0, sin(aim), cos(aim)), lens = SIMD3<Double>(0, yoke, lensZ)
        // Light you can see through, and — like a fogger's output — the one part of a prop that is allowed
        // out past its own footprint: a beam you can walk into is the whole point of a projector.
        let beamM = glow(rgb, strength: 0.95)
        beamM.transparency = 0.12
        let mid = lens + axis * (reach / 2)
        let beam = add(SCNCone(topRadius: reach * 0.26, bottomRadius: lensR, height: reach), beamM,
                       mid.x, mid.y, mid.z, rotate: SCNVector3(Float(.pi / 2 - aim), 0, 0))
        neonLight(beam, rgb, intensity: 90, reach: 2.4)
        let far = lens + axis * (reach * 0.86)
        let shape = glow(rgb, strength: 0.95)
        for k in 0..<4 {                                  // the projected pattern, out where the beam is widest
            let p = far + SIMD3<Double>((random(k) - 0.5) * reach * 0.4, (random(k + 4) - 0.5) * reach * 0.3, 0)
            let sr = reach * (0.03 + 0.02 * random(k + 8))
            ball(sr, shape, p.x, p.y, p.z).scale = swirl ? SCNVector3(1.6, 0.8, 0.2) : SCNVector3(2.4, 0.4, 0.2)
            if !swirl { ball(sr * 0.6, shape, p.x, p.y + sr * 0.5, p.z).scale = SCNVector3(0.8, 1.1, 0.2) }
        }
    }

    /// The one real light on a lit fitting, hung on a node that already has geometry — every part of a piece
    /// has to be something you can see and tap. Coloured like its own glow, and falling off within a few
    /// metres, so a sign lights the wall it is on rather than the whole room.
    private func neonLight(_ n: SCNNode, _ rgb: Palette.RGB, intensity: Double, reach: Double = 2) {
        let light = SCNLight()
        light.type = .omni
        light.color = CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        light.intensity = CGFloat(intensity * 0.22) // These materials take far less light up close than the original's.
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = CGFloat(reach)
        n.light = light
    }

    /// A length of neon flex (or of lamp wire): short rods between the points of a path, with a ball at
    /// every kink so the tube reads as bent rather than mitred. Returns the first segment, which is where
    /// a light belongs.
    @discardableResult
    private func neonTube(_ pts: [SIMD3<Double>], _ r: Double, _ mat: SCNMaterial) -> SCNNode {
        var first = node                                  // never returned: every path here has two points or more
        guard pts.count > 1 else { return first }
        for k in 1..<pts.count {
            let seg = rod(pts[k - 1], pts[k], r, mat)
            ball(r, mat, pts[k].x, pts[k].y, pts[k].z)
            if k == 1 { first = seg }
        }
        return first
    }
}
#endif
