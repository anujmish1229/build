import SwiftUI
import RoomScanKit

/// A top-down plan with furniture on it, drawn from the room and layout alone.
struct FurnishedPlanView: View {
    let room: CanonicalRoom
    let layout: FurnitureLayout?

    var body: some View {
        Canvas { ctx, size in
            let fit = PlanFit(bounds: room.derived.bounds, width: size.width, height: size.height, padding: 14)
            func pt(_ p: Point2) -> CGPoint {
                let s = fit.screen(p)
                return CGPoint(x: s.x, y: s.y)
            }
            func outline(_ points: [Point2]) -> Path {
                var path = Path()
                for (i, p) in points.enumerated() {
                    if i == 0 { path.move(to: pt(p)) } else { path.addLine(to: pt(p)) }
                }
                path.closeSubpath()
                return path
            }
            let floor = outline(room.floorPolygon)
            ctx.fill(floor, with: .color(Color(red: 0.96, green: 0.94, blue: 0.9)))
            ctx.stroke(floor, with: .color(.primary), lineWidth: 2.5)
            for o in room.openings {
                guard let wall = room.wall(o.wallID) else { continue }
                var gap = Path()
                gap.move(to: pt(wall.point(at: o.offset)))
                gap.addLine(to: pt(wall.point(at: o.offset + o.width)))
                ctx.stroke(gap, with: .color(o.type == .window ? .blue : .brown), lineWidth: 4)
            }
            for p in layout?.placed ?? [] {
                let shape = outline(RoomRenderer.outline(p))
                ctx.fill(shape, with: .color(Color(red: 0.55, green: 0.42, blue: 0.3).opacity(0.75)))
                ctx.stroke(shape, with: .color(Color(red: 0.3, green: 0.22, blue: 0.15)), lineWidth: 1)
            }
        }
        .accessibilityLabel("Floor plan with \(layout?.placed.count ?? 0) pieces of furniture")
    }
}
