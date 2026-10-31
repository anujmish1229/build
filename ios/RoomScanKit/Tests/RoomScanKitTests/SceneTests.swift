#if canImport(SceneKit)
import Foundation
import SceneKit
import Testing
@testable import RoomScanKit

@Suite struct SceneTests {
    let sample = SampleRooms.all[1]

    func layout() async -> FurnitureLayout {
        await FurniturePlanner.design(room: sample.room, theme: "living room", catalog: .bundled, reader: nil).layout
    }

    func nodes(_ scene: SCNScene, prefix: String) -> [SCNNode] {
        scene.rootNode.childNodes { node, _ in node.name?.hasPrefix(prefix) == true }
    }

    @Test func wallsMatchRoomJSONAndStandOutsideTheOutline() throws {
        let scene = RoomScene.make(sample.room, nil)
        for wall in sample.room.walls {
            let node = try #require(scene.rootNode.childNode(withName: "wall:\(wall.id)", recursively: true))
            let box = try #require(node.geometry as? SCNBox)
            #expect(abs(Double(box.width) - wall.length) < 1e-5)
            #expect(abs(Double(box.height) - wall.height) < 1e-5)
            // The inner face lies on the wall line, so the interior is exact.
            let centre = Point2(Double(node.position.x), Double(node.position.z))
            let offset = (wall.point(at: wall.length / 2) - centre).dot(wall.inwardNormal)
            #expect(abs(offset - RoomScene.wallThickness / 2) < 1e-5)
        }
    }

    @Test func furnitureIsWhereTheLayoutSays() async throws {
        let layout = await layout()
        #expect(!layout.placed.isEmpty)
        let scene = RoomScene.make(sample.room, layout, catalog: .bundled)
        for p in layout.placed {
            let holder = try #require(scene.rootNode.childNode(withName: RoomScene.itemPrefix + p.itemID, recursively: true))
            #expect(abs(Double(holder.position.x) - p.x) < 1e-5 && abs(Double(holder.position.z) - p.z) < 1e-5)
            #expect(abs(Double(holder.eulerAngles.y) - p.rotation * .pi / 180) < 1e-5)
        }
    }

    @Test func rotationSendsTheFrontTheRightWay() {
        var p = FurnitureLayout.Placed(itemID: "a", x: 1, z: 1, rotation: 90, footprint: [1, 1], height: 1)
        let node = RoomScene.furniture(p)
        let front = node.convertPosition(SCNVector3(0, 0, 1), to: nil)
        #expect(abs(Double(front.x) - 2) < 1e-4 && abs(Double(front.z) - 1) < 1e-4)
        p.rotation = 0
        #expect(abs(Double(RoomScene.furniture(p).convertPosition(SCNVector3(0, 0, 1), to: nil).z) - 2) < 1e-4)
    }

    @Test func cutawayLowersTheWalls() throws {
        let scene = RoomScene.make(sample.room, nil, cutaway: 1.1)
        for node in nodes(scene, prefix: "wall:") {
            #expect(abs(Double((node.geometry as? SCNBox)?.height ?? 0) - 1.1) < 1e-5)
        }
    }

    @Test func aFurnishedRoomIsDressedAndABareOneIsNot() async throws {
        let layout = await layout()
        let dressed = RoomScene.make(sample.room, layout, catalog: .bundled)
        #expect(dressed.rootNode.childNode(withName: "dressing", recursively: true) != nil)
        #expect(!nodes(dressed, prefix: "rug").isEmpty)
        #expect(!nodes(dressed, prefix: RoomScene.wallPartPrefix).isEmpty)
        #expect(RoomScene.make(sample.room, nil).rootNode.childNode(withName: "dressing", recursively: true) == nil)
    }

    @Test func nothingOnTheWallFloatsAboveACutaway() async throws {
        let layout = await layout()
        let scene = RoomScene.make(sample.room, layout, cutaway: 1.1, catalog: .bundled)
        let dressing = try #require(scene.rootNode.childNode(withName: "dressing", recursively: true))
        #expect(dressing.childNodes.allSatisfy { !($0.name ?? "").hasPrefix(RoomScene.wallPartPrefix) })
    }

    @Test(arguments: StarterBoard.load())
    func dressingStaysInTheRoom(_ d: DesignPackage) throws {
        let b = d.room.derived.bounds, t = RoomScene.wallThickness + 0.001
        let scene = RoomScene.make(d.room, d.layout, colours: d.colours, products: d.products, style: d.plan.style, catalog: FurnitureCatalog(entries: d.products))
        let dressing = try #require(scene.rootNode.childNode(withName: "dressing", recursively: true))
        let (lo, hi) = dressing.boundingBox
        #expect(Double(lo.x) >= b.minX - t && Double(hi.x) <= b.minX + b.width + t, "\(d.title): x \(lo.x) to \(hi.x)")
        #expect(Double(lo.z) >= b.minZ - t && Double(hi.z) <= b.minZ + b.depth + t, "\(d.title): z \(lo.z) to \(hi.z)")
        #expect(Double(lo.y) >= -0.001 && Double(hi.y) <= d.room.ceilingHeight + 0.001, "\(d.title): y \(lo.y) to \(hi.y)")
    }

    @Test(arguments: StarterBoard.load())
    func floorTouchesKeepClearOfPiecesAndDoors(_ d: DesignPackage) {
        let blocked = RoomDressing.blockedShapes(d.room, d.layout)
        for spot in RoomDressing.wallSpots(room: d.room, layout: d.layout, size: 0.36) {
            let shape = RoomDressing.square(spot, 0.36)
            #expect(!blocked.contains { Shape.intersects($0, shape) }, "\(d.title)")
            #expect(Shape.covers(d.room.floorPolygon, shape), "\(d.title)")
        }
    }

    @Test func aHiddenWallTakesWhatsOnItAlong() throws {
        let d = try #require(StarterBoard.load().first { $0.id == "starter-christmas" })
        let scene = RoomScene.make(d.room, d.layout, colours: d.colours, products: d.products, style: d.plan.style)
        let parts = RoomScene.wallParts(in: scene.rootNode)
        // From beyond w0 (the z = 0 side), that wall hides and the one opposite stays.
        RoomScene.hideWalls(parts, room: d.room, from: Point2(3.2, -6))
        #expect(parts.filter { $0.name == "wall:w0" || $0.name == RoomScene.wallPartPrefix + "w0" }.allSatisfy { $0.isHidden })
        #expect(parts.filter { $0.name == "wall:w2" }.allSatisfy { !$0.isHidden })
    }

    @Test func aPictureLooksAtTheFrontsOfThePieces() throws {
        let d = try #require(StarterBoard.load().first { $0.id == "starter-christmas" })
        let eye = RoomScene.viewpoint(d.room, layout: d.layout).eye
        let fireplace = try #require(d.layout.placed.first { $0.category == "fireplace" })
        let toCamera = Point2(Double(eye.x), Double(eye.z)) - Point2(fireplace.x, fireplace.z)
        #expect(PlanMath.front(degrees: fireplace.rotation).dot(toCamera) > 0)
    }

    @Test func floorCoversTheWholeOutline() {
        let tris = RoomScene.triangulate(sample.room.floorPolygon)
        var area = 0.0
        for t in stride(from: 0, to: tris.count, by: 3) {
            area += abs(PlanMath.signedArea([sample.room.floorPolygon[tris[t]], sample.room.floorPolygon[tris[t + 1]], sample.room.floorPolygon[tris[t + 2]]]))
        }
        #expect(abs(area - sample.room.derived.area) < 1e-9)
    }

    @Test func tappedNodeLeadsBackToItsPiece() {
        let holder = RoomScene.furniture(.init(itemID: "bed", x: 0, z: 0, rotation: 0, footprint: [1, 1], height: 1))
        #expect(RoomScene.itemID(of: holder.childNodes.first) == "bed")
        #expect(RoomScene.itemID(of: SCNNode()) == nil)
    }

    @Test func usdzFileKeepsTheRoomsTrueSize() async throws {
        let layout = await layout()
        let url = try #require(RoomScene.writeUSDZ(sample.room, layout, products: FurnitureCatalog.bundled.entries))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: url).count > 1000)
        let loaded = try SCNScene(url: url, options: nil)
        let (lo, hi) = loaded.rootNode.boundingBox
        let b = sample.room.derived.bounds, t = RoomScene.wallThickness
        // Measured in the file itself: the room plus a wall's thickness on each side, within a millimetre.
        #expect(abs(Double(hi.x - lo.x) - (b.width + 2 * t)) < 0.001)
        #expect(abs(Double(hi.z - lo.z) - (b.depth + 2 * t)) < 0.001)
        #expect(abs(Double(hi.y - lo.y) - sample.room.ceilingHeight) < 0.001)
    }
}
#endif
