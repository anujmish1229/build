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

/// A fixed list of furniture on a sample room: the solver on its own, before themes exist.
struct SolverDemoView: View {
    let sample: SampleRooms.Sample

    private var plan: FurniturePlan {
        let catalog = FurnitureCatalog.bundled
        func item(_ id: String, _ catalogID: String, _ rule: PlacementRule, _ priority: Int) -> FurnitureItem? {
            catalog.entry(catalogID).map {
                FurnitureItem(itemID: id, catalogID: catalogID, name: $0.name, category: $0.category, size: $0.size, placement: rule, priority: priority)
            }
        }
        let longest = sample.room.walls.max { $0.length < $1.length }?.id ?? "w0"
        return FurniturePlan(theme: "Fixed list", items: [
            item("bed", "sample_bed_queen_oak", .againstWall(wallID: longest, align: "center"), 1),
            item("left", "sample_nightstand_oak", .beside(targetItemID: "bed", side: "left", gap: 0.05), 2),
            item("right", "sample_nightstand_oak", .beside(targetItemID: "bed", side: "right", gap: 0.05), 2),
            item("wardrobe", "sample_wardrobe_white", .againstWall(wallID: longest, align: "start"), 3),
            item("plant", "sample_plant_fig", .corner(wallID: longest, corner: "end"), 4),
        ].compactMap { $0 })
    }

    var body: some View {
        let layout = LayoutSolver.solve(sample.room, plan, catalog: .bundled)
        List {
            FurnishedPlanView(room: sample.room, layout: layout).frame(height: 300)
            Section("Placed") { ForEach(layout.placed) { Text($0.name ?? $0.itemID) } }
            if !layout.unplaced.isEmpty {
                Section("Didn't fit") { ForEach(layout.unplaced) { Text("\($0.itemID): \($0.reason)") } }
            }
            if let url = writeSVG(layout) {
                ShareLink("Share floor plan (SVG)", item: url)
            }
        }
        .navigationTitle(sample.name)
    }

    private func writeSVG(_ layout: FurnitureLayout) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floor-plan.svg")
        do {
            try RoomRenderer.svg(sample.room, layout).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
