import SwiftUI
import RoomScanKit

enum PlanSelection: Equatable, Identifiable {
    case wall(String), opening(String)
    var id: String { switch self { case .wall(let s): "w:" + s; case .opening(let s): "o:" + s } }
}

/// The top-down plan: walls with lengths, doors with swing or keep-clear square, windows, gaps, and corner handles.
struct FloorPlanView: View {
    @ObservedObject var model: ReviewModel
    @Binding var selection: PlanSelection?
    @State private var draggedCorner: Int?
    /// Frozen during a drag so the plan doesn't shift under the finger.
    @State private var frozenBounds: Bounds?

    var body: some View {
        GeometryReader { geo in
            let fit = PlanFit(bounds: frozenBounds ?? model.room.derived.bounds, width: geo.size.width, height: geo.size.height, padding: 36)
            Canvas { ctx, _ in draw(ctx, fit: fit) }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { handleChange($0, fit) }.onEnded { handleEnd($0, fit) })
        }
        .background(Color(.secondarySystemBackground))
        .accessibilityIdentifier("floorPlan")
        .accessibilityLabel("Floor plan with \(model.room.walls.count) walls and \(model.room.openings.count) openings")
    }

    private func pt(_ p: Point2, _ fit: PlanFit) -> CGPoint {
        let s = fit.screen(p)
        return CGPoint(x: s.x, y: s.y)
    }

    private func draw(_ ctx: GraphicsContext, fit: PlanFit) {
        let room = model.room
        // Floor.
        var floor = Path()
        for (i, p) in room.floorPolygon.enumerated() {
            if i == 0 { floor.move(to: pt(p, fit)) } else { floor.addLine(to: pt(p, fit)) }
        }
        floor.closeSubpath()
        ctx.fill(floor, with: .color(Color(.systemBackground)))

        for wall in room.walls {
            let selected = selection == .wall(wall.id)
            let hasError = model.issues(wall: wall.id).contains { $0.level == .error }
            let isWarned = model.issues(wall: wall.id).contains { $0.level == .warning }
            var path = Path()
            path.move(to: pt(wall.start, fit)); path.addLine(to: pt(wall.end, fit))
            let color: Color = hasError ? .red : isWarned ? .orange : selected ? .accentColor : .primary
            ctx.stroke(path, with: .color(color), lineWidth: selected ? 5 : 3)
            // Length label just outside the wall.
            // Side walls need more room than top and bottom ones, as the text runs across them.
            let gap = abs(wall.direction.z) > abs(wall.direction.x) ? 26.0 : 16.0
            let mid = wall.point(at: wall.length / 2) - wall.inwardNormal * (gap / fit.scale)
            ctx.draw(Text(Units.format(wall.length, model.units)).font(.caption2.monospacedDigit()).foregroundColor(color), at: pt(mid, fit))
        }

        for o in room.openings {
            guard let wall = room.wall(o.wallID) else { continue }
            let selected = selection == .opening(o.id)
            let bad = model.issues(opening: o.id).contains { $0.level == .error }
            let a = pt(wall.point(at: o.offset), fit), b = pt(wall.point(at: o.offset + o.width), fit)
            var gap = Path(); gap.move(to: a); gap.addLine(to: b)
            let tint: Color = bad ? .red : selected ? .accentColor : o.type == .window ? .blue : .brown
            ctx.stroke(gap, with: .color(Color(.systemBackground)), lineWidth: 5)
            ctx.stroke(gap, with: .color(tint), style: StrokeStyle(lineWidth: selected ? 4 : 2, dash: o.type == .opening ? [4, 3] : []))
            guard o.type == .door else { continue }
            if let leaf = PlanGeometry.doorLeaf(o, wall: wall) {
                var path = Path()
                path.move(to: pt(leaf.hinge, fit)); path.addLine(to: pt(leaf.openEnd, fit))
                ctx.stroke(path, with: .color(tint), lineWidth: 1.5)
                var arc = Path()
                let steps = 16
                for s in 0...steps {
                    let t = Double(s) / Double(steps) * .pi / 2
                    let u = (leaf.closedEnd - leaf.hinge) * cos(t) + (leaf.openEnd - leaf.hinge) * sin(t)
                    let q = pt(leaf.hinge + u, fit)
                    if s == 0 { arc.move(to: q) } else { arc.addLine(to: q) }
                }
                ctx.stroke(arc, with: .color(tint.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else {
                // Unknown swing: draw the keep-clear square.
                let zone = PlanGeometry.keepClearZone(o, wall: wall)
                var path = Path()
                for (i, c) in zone.corners.enumerated() {
                    if i == 0 { path.move(to: pt(c, fit)) } else { path.addLine(to: pt(c, fit)) }
                }
                path.closeSubpath()
                ctx.fill(path, with: .color(.orange.opacity(0.12)))
                ctx.stroke(path, with: .color(.orange.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }

        for (i, c) in room.floorPolygon.enumerated() {
            let p = pt(c, fit)
            let r: CGFloat = draggedCorner == i ? 9 : 6
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(draggedCorner == i ? .accentColor : Color(.systemBackground)))
            ctx.stroke(dot, with: .color(.accentColor), lineWidth: 2)
        }
    }

    private func handleChange(_ value: DragGesture.Value, _ fit: PlanFit) {
        if draggedCorner == nil, hypot(value.translation.width, value.translation.height) > 6 {
            let start = value.startLocation
            let nearest = model.room.floorPolygon.indices.min {
                dist(pt(model.room.floorPolygon[$0], fit), start) < dist(pt(model.room.floorPolygon[$1], fit), start)
            }
            if let nearest, dist(pt(model.room.floorPolygon[nearest], fit), start) <= 30 {
                draggedCorner = nearest
                frozenBounds = model.room.derived.bounds
                model.beginDrag()
            }
        }
        if let corner = draggedCorner {
            let p = fit.plan(x: value.location.x, y: value.location.y)
            model.drag(corner: corner, to: p)
        }
    }

    private func handleEnd(_ value: DragGesture.Value, _ fit: PlanFit) {
        if draggedCorner != nil {
            model.endDrag()
            draggedCorner = nil
            frozenBounds = nil
            return
        }
        guard hypot(value.translation.width, value.translation.height) <= 6 else { return }
        select(at: fit.plan(x: value.location.x, y: value.location.y), tolerance: 22 / fit.scale)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func select(at p: Point2, tolerance: Double) {
        let room = model.room
        for o in room.openings {
            guard let wall = room.wall(o.wallID) else { continue }
            if PlanMath.distance(p, toSegment: wall.point(at: o.offset), wall.point(at: o.offset + o.width)) <= tolerance {
                selection = .opening(o.id)
                return
            }
        }
        let closest = room.walls.min { PlanMath.distance(p, toSegment: $0.start, $0.end) < PlanMath.distance(p, toSegment: $1.start, $1.end) }
        if let closest, PlanMath.distance(p, toSegment: closest.start, closest.end) <= tolerance {
            selection = .wall(closest.id)
        } else {
            selection = nil
        }
    }
}
