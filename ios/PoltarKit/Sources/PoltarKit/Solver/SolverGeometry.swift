import Foundation

// Exact 2D tests for the solver. Footprints and zones are convex quadrilaterals; the room is a
// simple, possibly concave outline.

enum Shape {
    // MARK: Convex shapes

    /// True when two convex shapes share any point. Touching counts.
    static func intersects(_ a: [Point2], _ b: [Point2]) -> Bool {
        for shape in [a, b] {
            let n = shape.count
            for i in 0..<n {
                let p = shape[i], q = shape[(i + 1) % n]
                let axis = Point2(-(q.z - p.z), q.x - p.x)
                if axis.x == 0 && axis.z == 0 { continue }
                var minA = Double.infinity, maxA = -Double.infinity, minB = Double.infinity, maxB = -Double.infinity
                for v in a {
                    let d = v.dot(axis)
                    minA = min(minA, d)
                    maxA = max(maxA, d)
                }
                for v in b {
                    let d = v.dot(axis)
                    minB = min(minB, d)
                    maxB = max(maxB, d)
                }
                if maxA < minB || maxB < minA { return false }
            }
        }
        return true
    }

    /// Distance from a point to a convex shape (0 inside or on it).
    static func distance(_ p: Point2, toConvex shape: [Point2]) -> Double {
        contains(shape, p) ? 0 : edgeDistance(p, shape)
    }

    /// Distance from a point to the nearest edge of any polygon.
    static func edgeDistance(_ p: Point2, _ shape: [Point2]) -> Double {
        var best = Double.infinity
        for i in shape.indices {
            best = min(best, PlanMath.distance(p, toSegment: shape[i], shape[(i + 1) % shape.count]))
        }
        return best
    }

    /// Distance between two convex shapes (0 when they touch or overlap).
    static func distance(_ a: [Point2], _ b: [Point2]) -> Double {
        if intersects(a, b) { return 0 }
        var best = Double.infinity
        for p in a { best = min(best, edgeDistance(p, b)) }
        for p in b { best = min(best, edgeDistance(p, a)) }
        return best
    }

    // MARK: Simple polygons

    /// Point inside or on the boundary of a simple polygon.
    static func contains(_ polygon: [Point2], _ p: Point2) -> Bool {
        let n = polygon.count
        guard n >= 3 else { return false }
        var inside = false
        for i in 0..<n {
            let a = polygon[i], b = polygon[(i + 1) % n]
            if PlanMath.distance(p, toSegment: a, b) <= 1e-12 { return true }
            if (a.z > p.z) != (b.z > p.z) {
                let x = a.x + (p.z - a.z) * (b.x - a.x) / (b.z - a.z)
                if p.x < x { inside.toggle() }
            }
        }
        return inside
    }

    /// Point strictly inside a simple polygon.
    static func strictlyContains(_ polygon: [Point2], _ p: Point2) -> Bool {
        for i in polygon.indices where PlanMath.distance(p, toSegment: polygon[i], polygon[(i + 1) % polygon.count]) <= 1e-12 {
            return false
        }
        return contains(polygon, p)
    }

    private static func cross(_ o: Point2, _ a: Point2, _ b: Point2) -> Double { (a - o).cross(b - o) }

    /// True when two segments cross at a point inside both, not just touching.
    private static func properlyCross(_ p1: Point2, _ p2: Point2, _ q1: Point2, _ q2: Point2) -> Bool {
        let d1 = cross(q1, q2, p1), d2 = cross(q1, q2, p2), d3 = cross(p1, p2, q1), d4 = cross(p1, p2, q2)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    /// True when every point of the convex `shape` is inside or on the simple `polygon`.
    static func covers(_ polygon: [Point2], _ shape: [Point2]) -> Bool {
        guard polygon.count >= 3 else { return false }
        for v in shape where !contains(polygon, v) { return false }
        let n = polygon.count, m = shape.count
        for i in 0..<n {
            let a = polygon[i], b = polygon[(i + 1) % n]
            // A room corner strictly inside the shape means a wall cuts into it.
            if strictlyInsideConvex(shape, a) { return false }
            for j in 0..<m where properlyCross(a, b, shape[j], shape[(j + 1) % m]) { return false }
        }
        return true
    }

    private static func strictlyInsideConvex(_ shape: [Point2], _ p: Point2) -> Bool {
        let area = PlanMath.signedArea(shape)
        guard area != 0 else { return false }
        for i in shape.indices {
            let c = cross(shape[i], shape[(i + 1) % shape.count], p)
            if area > 0 ? c <= 0 : c >= 0 { return false }
        }
        return true
    }

    static func bounds(_ points: [Point2]) -> (min: Point2, max: Point2) {
        let b = PlanMath.bounds(points)
        return (Point2(b.minX, b.minZ), Point2(b.maxX, b.maxZ))
    }

    /// The outline moved `inset` metres inward with mitred corners. Expects positive orientation.
    static func inset(_ polygon: [Point2], by inset: Double) -> [Point2] {
        guard inset > 0 else { return polygon }
        let n = polygon.count
        return (0..<n).map { i in
            let prev = polygon[(i + n - 1) % n], p = polygon[i], next = polygon[(i + 1) % n]
            guard let n1 = PlanMath.inwardNormal(prev, p), let n2 = PlanMath.inwardNormal(p, next) else { return p }
            let denom = 1 + n1.dot(n2)
            if denom < 1e-9 { return p + n1 * inset }
            return p + (n1 + n2) * (inset / denom)
        }
    }

    /// Area-weighted centre of a simple polygon.
    static func centroid(_ polygon: [Point2]) -> Point2 {
        let n = polygon.count
        var cx = 0.0, cz = 0.0, area = 0.0
        for i in 0..<n {
            let a = polygon[i], b = polygon[(i + 1) % n]
            let w = a.x * b.z - b.x * a.z
            area += w
            cx += (a.x + b.x) * w
            cz += (a.z + b.z) * w
        }
        guard area != 0 else { return polygon.first ?? Point2(0, 0) }
        return Point2(cx / (3 * area), cz / (3 * area))
    }

    /// A point surely inside the polygon: the middle of the widest stretch on a horizontal line
    /// between the corners either side of the middle height.
    static func representativePoint(_ polygon: [Point2]) -> Point2 {
        let (lo, hi) = bounds(polygon)
        let centreZ = (lo.z + hi.z) / 2
        var above = hi.z, below = lo.z
        for p in polygon {
            if p.z > centreZ && p.z < above { above = p.z }
            if p.z < centreZ && p.z > below { below = p.z }
        }
        let scanZ = (above + below) / 2
        var xs: [Double] = []
        let n = polygon.count
        for i in 0..<n {
            let a = polygon[i], b = polygon[(i + 1) % n]
            if (a.z > scanZ) != (b.z > scanZ) { xs.append(a.x + (scanZ - a.z) * (b.x - a.x) / (b.z - a.z)) }
        }
        xs.sort()
        var best: (width: Double, mid: Double)?
        var k = 0
        while k + 1 < xs.count {
            let width = xs[k + 1] - xs[k]
            if best.map({ width > $0.width }) ?? true { best = (width, (xs[k] + xs[k + 1]) / 2) }
            k += 2
        }
        return Point2(best?.mid ?? centroid(polygon).x, scanZ)
    }
}
