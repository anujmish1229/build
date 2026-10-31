import Foundation

/// A rectangle at any angle: centre, half sizes, and unit axes.
public struct OrientedRect: Equatable, Sendable {
    public var centre: Point2
    public var halfU: Double
    public var halfV: Double
    public var u: Point2
    public var v: Point2

    public init(centre: Point2, halfU: Double, halfV: Double, u: Point2, v: Point2) {
        self.centre = centre; self.halfU = halfU; self.halfV = halfV; self.u = u; self.v = v
    }

    /// Footprint at a rotation in degrees (`docs/CONVENTIONS.md`): width along local x, depth along local z.
    public init(centre: Point2, width: Double, depth: Double, rotation: Double) {
        let a = rotation * .pi / 180
        self.init(centre: centre, halfU: width / 2, halfV: depth / 2,
                  u: Point2(cos(a), -sin(a)), v: Point2(sin(a), cos(a)))
    }

    public var corners: [Point2] {
        [centre - u * halfU - v * halfV, centre + u * halfU - v * halfV,
         centre + u * halfU + v * halfV, centre - u * halfU + v * halfV]
    }

    /// Whether interiors overlap. Touching edges don't count.
    public func overlaps(_ o: OrientedRect, tolerance: Double = 1e-6) -> Bool {
        let delta = o.centre - centre
        for axis in [u, v, o.u, o.v] {
            let r1 = halfU * abs(u.dot(axis)) + halfV * abs(v.dot(axis))
            let r2 = o.halfU * abs(o.u.dot(axis)) + o.halfV * abs(o.v.dot(axis))
            if abs(delta.dot(axis)) >= r1 + r2 - tolerance { return false }
        }
        return true
    }

    public func contains(_ p: Point2) -> Bool {
        let d = p - centre
        return abs(d.dot(u)) <= halfU && abs(d.dot(v)) <= halfV
    }

    /// Shortest distance from a point to this rectangle (0 when inside).
    public func distance(to p: Point2) -> Double {
        let d = p - centre
        let du = max(abs(d.dot(u)) - halfU, 0), dv = max(abs(d.dot(v)) - halfV, 0)
        return (du * du + dv * dv).squareRoot()
    }
}

public enum PlanGeometry {
    public static let outwardZoneDepth = 0.6
    public static let windowZoneDepth = 0.4

    /// A rectangle extending into the room from a stretch of wall.
    static func zone(wall: Wall, offset: Double, width: Double, depth: Double) -> OrientedRect {
        let n = wall.inwardNormal, d = wall.direction
        let centre = wall.point(at: offset + width / 2) + n * (depth / 2)
        return OrientedRect(centre: centre, halfU: width / 2, halfV: depth / 2, u: d, v: n)
    }

    /// Door width square when it swings in or is unknown; 0.6 m deep when it swings out or there is no door (FR-P3).
    public static func keepClearZone(_ o: Opening, wall: Wall) -> OrientedRect {
        let swingsIn = o.type == .door && !(o.swing?.isOutward ?? false)
        return zone(wall: wall, offset: o.offset, width: o.width, depth: swingsIn ? o.width : outwardZoneDepth)
    }

    public static func windowZone(_ o: Opening, wall: Wall) -> OrientedRect {
        zone(wall: wall, offset: o.offset, width: o.width, depth: windowZoneDepth)
    }

    public static func keepClearZones(_ room: CanonicalRoom) -> [(opening: Opening, zone: OrientedRect)] {
        room.openings.filter { $0.type != .window }.compactMap { o in
            room.wall(o.wallID).map { (o, keepClearZone(o, wall: $0)) }
        }
    }

    public struct DoorLeaf: Equatable, Sendable {
        public var hinge: Point2
        /// The door's free end when fully open, perpendicular to the wall.
        public var openEnd: Point2
        /// Where the free end sits when closed.
        public var closedEnd: Point2
    }

    /// The door's leaf for drawing, or nil when the swing is unknown.
    public static func doorLeaf(_ o: Opening, wall: Wall) -> DoorLeaf? {
        guard o.type == .door, let swing = o.swing, swing != .unknown else { return nil }
        let left = wall.point(at: o.offset), right = wall.point(at: o.offset + o.width)
        let hingedLeft = swing == .inwardLeft || swing == .outwardLeft
        let hinge = hingedLeft ? left : right
        let normal = swing.isInward ? wall.inwardNormal : wall.inwardNormal * -1
        return DoorLeaf(hinge: hinge, openEnd: hinge + normal * o.width, closedEnd: hingedLeft ? right : left)
    }
}

/// Maps plan metres to a drawing area, keeping proportions. z runs down the screen.
public struct PlanFit: Equatable, Sendable {
    public let scale: Double
    public let originX: Double
    public let originY: Double
    let bounds: Bounds

    public init(bounds: Bounds, width: Double, height: Double, padding: Double = 28) {
        self.bounds = bounds
        let w = max(bounds.width, 0.01), d = max(bounds.depth, 0.01)
        scale = max(min((width - padding * 2) / w, (height - padding * 2) / d), 1)
        originX = (width - w * scale) / 2
        originY = (height - d * scale) / 2
    }

    public func screen(_ p: Point2) -> (x: Double, y: Double) {
        (originX + (p.x - bounds.minX) * scale, originY + (p.z - bounds.minZ) * scale)
    }

    public func plan(x: Double, y: Double) -> Point2 {
        Point2((x - originX) / scale + bounds.minX, (y - originY) / scale + bounds.minZ)
    }
}
