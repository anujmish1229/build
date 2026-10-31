import Foundation

/// The floor plan as an SVG file, drawn from the room and layout alone.
public enum RoomRenderer {
    static func placedShape(_ p: FurnitureLayout.Placed) -> [Point2] {
        let w = p.footprint.first ?? 0, d = p.footprint.count > 1 ? p.footprint[1] : 0
        return Solver.localRect(p.x, p.z, p.rotation, (-w / 2, w / 2, -d / 2, d / 2))
    }

    /// A placed piece's outline, for drawing.
    public static func outline(_ p: FurnitureLayout.Placed) -> [Point2] { placedShape(p) }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    public static func svg(_ room: CanonicalRoom, _ layout: FurnitureLayout?, units: UnitSystem = .metric) -> String {
        let scale = 100.0, pad = 40.0
        let (lo, hi) = Shape.bounds(room.floorPolygon)
        func x(_ p: Point2) -> String { String(format: "%.1f", pad + (p.x - lo.x) * scale) }
        func y(_ p: Point2) -> String { String(format: "%.1f", pad + (p.z - lo.z) * scale) }
        func points(_ shape: [Point2]) -> String { shape.map { "\(x($0)),\(y($0))" }.joined(separator: " ") }
        func line(_ a: Point2, _ b: Point2, _ colour: String, _ width: Double) -> String {
            "<line x1=\"\(x(a))\" y1=\"\(y(a))\" x2=\"\(x(b))\" y2=\"\(y(b))\" stroke=\"\(colour)\" stroke-width=\"\(width)\"/>"
        }
        let width = (hi.x - lo.x) * scale + 2 * pad, height = (hi.z - lo.z) * scale + 2 * pad
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(Int(width)) \(Int(height))\" font-family=\"-apple-system, sans-serif\">"
        out += "<polygon points=\"\(points(room.floorPolygon))\" fill=\"#f4f1ea\" stroke=\"#333\" stroke-width=\"6\" stroke-linejoin=\"miter\"/>"
        for wall in room.walls {
            let at = wall.point(at: wall.length / 2) - wall.inwardNormal * 0.18
            out += "<text x=\"\(x(at))\" y=\"\(y(at))\" font-size=\"12\" text-anchor=\"middle\" fill=\"#666\">\(escaped(Units.format(wall.length, units)))</text>"
        }
        for o in room.openings {
            guard let wall = room.wall(o.wallID) else { continue }
            let colour = o.type == .window ? "#3b82f6" : (o.type == .door ? "#f59e0b" : "#ffffff")
            out += line(wall.point(at: o.offset), wall.point(at: o.offset + o.width), colour, 8)
        }
        for p in layout?.placed ?? [] {
            let c = Point2(p.x, p.z)
            out += "<polygon points=\"\(points(placedShape(p)))\" fill=\"#c7d2fe\" fill-opacity=\"0.85\" stroke=\"#4338ca\" stroke-width=\"2\"/>"
            let front = c + PlanMath.front(degrees: p.rotation) * ((p.footprint.count > 1 ? p.footprint[1] : 0) / 2)
            out += line(c, front, "#4338ca", 1.5)
            let label = (p.name ?? p.itemID).split(separator: ",").first.map(String.init) ?? p.itemID
            out += "<text x=\"\(x(c))\" y=\"\(y(c))\" font-size=\"11\" text-anchor=\"middle\" fill=\"#1e1b4b\">\(escaped(label))</text>"
        }
        return out + "</svg>"
    }
}
