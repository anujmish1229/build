import Foundation

/// A point on the plan. Encoded as `[x, z]`.
public struct Point2: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var z: Double
    public init(_ x: Double, _ z: Double) { self.x = x; self.z = z }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        z = try c.decode(Double.self)
        guard x.isFinite, z.isFinite else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Point must be finite")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x); try c.encode(z)
    }

    public static func + (a: Point2, b: Point2) -> Point2 { Point2(a.x + b.x, a.z + b.z) }
    public static func - (a: Point2, b: Point2) -> Point2 { Point2(a.x - b.x, a.z - b.z) }
    public static func * (a: Point2, s: Double) -> Point2 { Point2(a.x * s, a.z * s) }
    public func dot(_ o: Point2) -> Double { x * o.x + z * o.z }
    public func cross(_ o: Point2) -> Double { x * o.z - z * o.x }
    public var length: Double { (x * x + z * z).squareRoot() }
    public var normalized: Point2 { let l = length; return l > 0 ? self * (1 / l) : self }
    public func distance(to o: Point2) -> Double { (self - o).length }
    /// Left of the direction of travel: the inward normal of a wall (`docs/CONVENTIONS.md`).
    public var leftNormal: Point2 { Point2(-z, x) }
    public func rotated(by radians: Double) -> Point2 {
        let c = cos(radians), s = sin(radians)
        return Point2(x * c - z * s, x * s + z * c)
    }
}

public struct Bounds: Equatable, Sendable {
    public var minX, minZ, maxX, maxZ: Double
    public var width: Double { maxX - minX }
    public var depth: Double { maxZ - minZ }
    public var centre: Point2 { Point2((minX + maxX) / 2, (minZ + maxZ) / 2) }
}

/// Plan geometry and the conventions everything else follows.
public enum PlanMath {
    public static let snapTolerance = 0.05
    public static let wallAgreementTolerance = 0.001

    public static func signedArea(_ p: [Point2]) -> Double {
        guard p.count >= 3 else { return 0 }
        var sum = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += a.x * b.z - b.x * a.z
        }
        return sum / 2
    }

    public static func perimeter(_ p: [Point2]) -> Double {
        guard p.count >= 2 else { return 0 }
        return p.indices.reduce(0) { $0 + p[$1].distance(to: p[($1 + 1) % p.count]) }
    }

    public static func bounds(_ p: [Point2]) -> Bounds {
        Bounds(minX: p.map(\.x).min() ?? 0, minZ: p.map(\.z).min() ?? 0,
               maxX: p.map(\.x).max() ?? 0, maxZ: p.map(\.z).max() ?? 0)
    }

    /// Whether segments ab and cd properly cross or touch.
    public static func segmentsIntersect(_ a: Point2, _ b: Point2, _ c: Point2, _ d: Point2) -> Bool {
        func orient(_ p: Point2, _ q: Point2, _ r: Point2) -> Double { (q - p).cross(r - p) }
        func onSegment(_ p: Point2, _ q: Point2, _ r: Point2) -> Bool {
            min(p.x, q.x) - 1e-12 <= r.x && r.x <= max(p.x, q.x) + 1e-12 &&
            min(p.z, q.z) - 1e-12 <= r.z && r.z <= max(p.z, q.z) + 1e-12
        }
        let d1 = orient(c, d, a), d2 = orient(c, d, b), d3 = orient(a, b, c), d4 = orient(a, b, d)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) { return true }
        let eps = 1e-12
        if abs(d1) < eps, onSegment(c, d, a) { return true }
        if abs(d2) < eps, onSegment(c, d, b) { return true }
        if abs(d3) < eps, onSegment(a, b, c) { return true }
        if abs(d4) < eps, onSegment(a, b, d) { return true }
        return false
    }

    public static func isSelfIntersecting(_ p: [Point2]) -> Bool {
        let n = p.count
        guard n >= 4 else { return false }
        for i in 0..<n {
            for j in (i + 1)..<n {
                if j == i { continue }
                if (i + 1) % n == j || (j + 1) % n == i { continue }
                if segmentsIntersect(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]) { return true }
            }
        }
        return false
    }

    public static func contains(_ polygon: [Point2], _ q: Point2) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.z > q.z) != (b.z > q.z) {
                let x = (b.x - a.x) * (q.z - a.z) / (b.z - a.z) + a.x
                if q.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    public static func distance(_ q: Point2, toSegment a: Point2, _ b: Point2) -> Double {
        let ab = b - a
        let len2 = ab.dot(ab)
        guard len2 > 0 else { return q.distance(to: a) }
        let t = min(1, max(0, (q - a).dot(ab) / len2))
        return q.distance(to: a + ab * t)
    }

    /// Where two infinite lines meet, or nil when nearly parallel.
    public static func lineIntersection(_ a: Point2, _ b: Point2, _ c: Point2, _ d: Point2) -> Point2? {
        let r = b - a, s = d - c
        let denom = r.normalized.cross(s.normalized)
        guard abs(denom) > 0.05 else { return nil }   // Under about 3 degrees apart.
        let t = (c - a).cross(s) / r.cross(s)
        return a + r * t
    }

    public static func round6(_ v: Double) -> Double { (v * 1e6).rounded(.toNearestOrEven) / 1e6 }

    /// The inward normal of a wall running from a to b, or nil when they coincide.
    public static func inwardNormal(_ a: Point2, _ b: Point2) -> Point2? {
        let d = b - a
        return d.length > 1e-12 ? d.normalized.leftNormal : nil
    }

    /// Turns a point about +Y by degrees: (1, 0) goes to (cos, -sin) and (0, 1) to (sin, cos).
    public static func rotate(_ p: Point2, degrees: Double) -> Point2 {
        let t = degrees * .pi / 180, c = cos(t), s = sin(t)
        return Point2(p.x * c + p.z * s, -p.x * s + p.z * c)
    }

    /// The way an item faces at a rotation.
    public static func front(degrees: Double) -> Point2 { rotate(Point2(0, 1), degrees: degrees) }

    /// The rotation in degrees that makes an item face a direction.
    public static func rotationFacing(_ direction: Point2) -> Double { atan2(direction.x, direction.z) * 180 / .pi }

    /// Rounds to a tenth of a millimetre so stored numbers stay readable.
    public static func tidy(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
}
