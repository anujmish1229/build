import ARKit
import QuickLook
import RoomScanKit
import SceneKit
import SwiftUI

/// The room in 3D: an Object view to orbit and pinch, and an AR view that puts it on a real floor or
/// table. Tapping a piece shows its card (FR-O2 to FR-O4).
struct RoomViewer: View {
    let room: CanonicalRoom
    let layout: FurnitureLayout?
    var colours: RoomColours?
    var wallPaint: String?
    var products: [CatalogEntry] = []
    var style: DesignStyle?
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case object = "Object"
        case ar = "AR"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .object
    @State private var selected: String?
    @State private var tabletop = true
    @State private var placed = false
    @State private var placeAgain = 0
    @State private var quickLook: URL?

    private var arAvailable: Bool { ARWorldTrackingConfiguration.isSupported }

    var body: some View {
        ZStack {
            Group {
                switch mode {
                case .object:
                    ObjectSceneView(room: room, layout: layout, colours: colours, wallPaint: wallPaint, products: products, style: style) { selected = $0 }
                case .ar:
                    ARRoomView(room: room, layout: layout, colours: colours, wallPaint: wallPaint, products: products, style: style, tabletop: tabletop, placeAgain: placeAgain,
                               onPlaced: { placed = $0 }, onTap: { selected = $0 })
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).padding(10)
                    }
                    .background(.thinMaterial, in: Circle())
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("closeViewer")
                    Button {
                        quickLook = RoomScene.writeUSDZ(room, layout, colours: colours, wallPaint: wallPaint, products: products, style: style)
                    } label: {
                        Label("Quick Look", systemImage: "arkit").font(.footnote).padding(8)
                    }
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityIdentifier("quickLook")
                    Spacer()
                    if arAvailable {
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }
                .padding()
                if mode == .ar {
                    HStack {
                        Picker("Size", selection: $tabletop) {
                            Text("Table size").tag(true)
                            Text("Real size").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        if placed {
                            Button("Move") { placeAgain += 1; placed = false }.buttonStyle(.soft)
                        }
                    }
                    .padding(.horizontal)
                    if !placed {
                        Text("Point at the floor or a table, then tap to place the room.")
                            .font(.footnote).padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Spacer()
                if let id = selected, let piece = layout?.placed.first(where: { $0.itemID == id }) {
                    ProductCard(piece: piece, entry: products.first { $0.catalogID == piece.catalogID } ?? FurnitureCatalog.current.entry(piece.catalogID)) { selected = nil }
                        .padding()
                } else if layout?.placed.isEmpty == false && mode == .object {
                    Text("Tap a piece to see what it is.")
                        .font(.footnote).padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom)
                }
            }
        }
        .quickLookPreview($quickLook)
        .onChange(of: mode) { _ in selected = nil; placed = false }
        .onChange(of: tabletop) { _ in placed = false }
    }
}

/// The small card for a tapped piece (FR-O4, FR-C8).
struct ProductCard: View {
    let piece: FurnitureLayout.Placed
    let entry: CatalogEntry?
    let close: () -> Void
    @Environment(\.openURL) private var openURL

    private var size: String {
        let values = entry?.size ?? (piece.footprint + [piece.height].compactMap { $0 })
        return values.map { Units.format($0, UnitSystem(rawValue: UserDefaults.standard.string(forKey: "unitSystem") ?? "") ?? .deviceDefault) }.joined(separator: " × ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(entry?.name ?? piece.name ?? piece.itemID).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Close")
            }
            Text([entry?.store, entry?.priceText].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            if let original = entry?.originalPriceText { Text("Store price: \(original)").font(.caption).foregroundStyle(.secondary) }
            Text(size).font(.footnote).foregroundStyle(.secondary)
            if let note = entry?.note { Text(note).font(.footnote).foregroundStyle(.orange) }
            if let url = entry?.url {
                Button { openURL(url) } label: {
                    Label("View in store", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pumpkin)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Object view

struct ObjectSceneView: UIViewRepresentable {
    let room: CanonicalRoom
    let layout: FurnitureLayout?
    var colours: RoomColours?
    var wallPaint: String?
    var products: [CatalogEntry] = []
    var style: DesignStyle?
    var interactive = true
    let onTap: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        configure(view, context: context)
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = UIColor(Editorial.paper)
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        return view
    }

    private func configure(_ view: SCNView, context: Context) {
        // Walls cut away at 1.1 m, like a doll's house, so the room can be seen into from any angle.
        let scene = RoomScene.make(room, layout, colours: colours, wallPaint: wallPaint, cutaway: 1.1, products: products, style: style)
        Self.addLights(to: scene)
        let b = room.derived.bounds
        let centre = SCNVector3(Float(b.centre.x), 0.2, Float(b.centre.z))
        let span = max(b.width, b.depth, 2)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 58
        camera.camera?.zNear = 0.05
        camera.position = SCNVector3(centre.x, Float(span * 1.15), centre.z + Float(span * 0.85))
        camera.look(at: centre)
        scene.rootNode.addChildNode(camera)
        view.scene = scene
        view.pointOfView = camera
        view.allowsCameraControl = interactive
        view.defaultCameraController.target = centre
        view.defaultCameraController.interactionMode = .orbitTurntable
        context.coordinator.shown = room
        context.coordinator.shownLayout = layout
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        if context.coordinator.shown != room || context.coordinator.shownLayout != layout { configure(view, context: context) }
    }

    static func addLights(to scene: SCNScene) {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 900
        sun.eulerAngles = SCNVector3(-1.0, 0.6, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 450
        scene.rootNode.addChildNode(ambient)
    }

    final class Coordinator: NSObject {
        var onTap: (String?) -> Void
        var shown: CanonicalRoom?
        var shownLayout: FurnitureLayout?
        init(onTap: @escaping (String?) -> Void) { self.onTap = onTap }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            onTap(hits.lazy.compactMap { RoomScene.itemID(of: $0.node) }.first)
        }
    }
}

// MARK: - AR view

struct ARRoomView: UIViewRepresentable {
    let room: CanonicalRoom
    let layout: FurnitureLayout?
    var colours: RoomColours?
    var wallPaint: String?
    var products: [CatalogEntry] = []
    var style: DesignStyle?
    let tabletop: Bool
    let placeAgain: Int
    let onPlaced: (Bool) -> Void
    let onTap: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.automaticallyUpdatesLighting = true
        view.autoenablesDefaultLighting = true
        view.scene = SCNScene()
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        view.session.run(configuration)
        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.topAnchor.constraint(equalTo: view.topAnchor), coaching.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            coaching.leadingAnchor.constraint(equalTo: view.leadingAnchor), coaching.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        context.coordinator.view = view
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        let c = context.coordinator
        c.onPlaced = onPlaced
        c.onTap = onTap
        if c.room != room || c.tabletop != tabletop || c.placeAgain != placeAgain {
            c.room = room
            c.layout = layout
            c.colours = colours
            c.wallPaint = wallPaint
            c.products = products
            c.style = style
            c.tabletop = tabletop
            c.placeAgain = placeAgain
            c.removeRoom()
        }
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject {
        weak var view: ARSCNView?
        var room: CanonicalRoom?
        var layout: FurnitureLayout?
        var colours: RoomColours?
        var wallPaint: String?
        var products: [CatalogEntry] = []
        var style: DesignStyle?
        var tabletop = true
        var placeAgain = 0
        var onPlaced: (Bool) -> Void = { _ in }
        var onTap: (String?) -> Void = { _ in }
        private var roomNode: SCNNode?

        func removeRoom() {
            roomNode?.removeFromParentNode()
            roomNode = nil
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let room else { return }
            let point = gesture.location(in: view)
            if roomNode != nil {
                let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
                onTap(hits.lazy.compactMap { RoomScene.itemID(of: $0.node) }.first)
                return
            }
            guard let query = view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .horizontal),
                  let hit = view.session.raycast(query).first else { return }
            guard let built = RoomScene.make(room, layout, colours: colours, wallPaint: wallPaint, products: products, style: style).rootNode
                .childNode(withName: "room", recursively: false) else { return }
            let b = room.derived.bounds
            built.position = SCNVector3(Float(-b.centre.x), 0, Float(-b.centre.z))
            // See-through walls, so the furniture stays visible.
            built.enumerateChildNodes { node, _ in
                if node.name?.hasPrefix("wall:") == true || node.name?.hasPrefix("opening:") == true { node.opacity = 0.3 }
            }
            let anchor = SCNNode()
            anchor.simdTransform = hit.worldTransform
            let scale: Float = tabletop ? 0.08 : 1
            anchor.scale = SCNVector3(scale, scale, scale)
            anchor.addChildNode(built)
            view.scene.rootNode.addChildNode(anchor)
            roomNode = anchor
            onPlaced(true)
        }
    }
}
