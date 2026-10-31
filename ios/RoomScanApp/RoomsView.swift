import RoomScanKit
import SwiftUI
import UniformTypeIdentifiers

/// All the user's rooms and their designs.
struct RoomsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var scanning = false
    @State private var opening = false
    @State private var newRoom: SavedRoom?

    var body: some View {
        List {
            ForEach(app.library.rooms) { room in
                Section {
                    NavigationLink(value: Route.room(room.id)) { RoomRow(room: room, designCount: app.library.designs(for: room.id).count, units: app.units) }
                        .accessibilityIdentifier("room-\(room.name)")
                    ForEach(app.library.designs(for: room.id)) { design in
                        NavigationLink(value: Route.design(design.id)) { Label(design.name, systemImage: "sofa") }
                    }
                    NavigationLink { NewDesignView(roomID: room.id) } label: { Label("New design", systemImage: "plus") }
                        .accessibilityIdentifier("newDesign-\(room.name)")
                }
            }
            if app.library.rooms.isEmpty {
                Text("No rooms yet. Scan one, or add the sample rooms from the + menu.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Rooms")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { scanning = true } label: { Label("Scan a room", systemImage: "camera.metering.matrix") }
                    Button { app.change { try $0.addSamples() } } label: { Label("Add sample rooms", systemImage: "square.stack.3d.up") }
                    Button { opening = true } label: { Label("Open a file", systemImage: "folder") }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add")
                .accessibilityIdentifier("roomsAdd")
            }
        }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                ScanView(onFinished: { raw, colours in
                    scanning = false
                    newRoom = app.addScan(raw, colours: colours)
                })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
            }
        }
        .sheet(item: $newRoom) { room in NavigationStack { NewRoomView(roomID: room.id) } }
        .fileImporter(isPresented: $opening, allowedContentTypes: Self.openTypes) { result in
            if case .success(let url) = result { app.open(url) }
        }
    }

    static var openTypes: [UTType] {
        [UTType(ShareFiles.scanType), UTType(ShareFiles.designType), .json].compactMap { $0 }
    }
}

struct RoomRow: View {
    let room: SavedRoom
    let designCount: Int
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            FurnishedPlanView(room: room.room, layout: nil).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name).font(.headline)
                Text("\(Units.area(room.room.derived.area, units)), \(designCount) design\(designCount == 1 ? "" : "s")")
                    .font(.footnote).foregroundStyle(.secondary)
                ColourSwatches(colours: room.colours)
            }
        }
    }
}

/// One room: plan, facts, colours, designs and actions.
struct RoomDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let roomID: UUID
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var rescanning = false
    @State private var report: MergeReport?
    @State private var viewing = false

    var body: some View {
        if let room = app.library.room(roomID) {
            let issues = RoomValidation.validate(room.room, units: app.units)
            List {
                Section {
                    FurnishedPlanView(room: room.room, layout: nil).frame(height: 240)
                    LabeledContent("Area", value: Units.area(room.room.derived.area, app.units))
                    LabeledContent("Ceiling", value: Units.format(room.room.ceilingHeight, app.units))
                    LabeledContent("Walls", value: "\(room.room.walls.count)")
                    LabeledContent("Doors and windows", value: "\(room.room.openings.count)")
                }
                if RoomValidation.hasErrors(issues) {
                    Section("Fix these first") { ForEach(issues.filter { $0.level == .error }) { IssueRow(issue: $0) } }
                }
                Section("Colours") {
                    ColourEditor(colours: Binding(get: { app.library.room(roomID)?.colours ?? RoomColours() }, set: { app.setColours(roomID, $0) }))
                }
                Section("Designs") {
                    ForEach(app.library.designs(for: roomID)) { d in NavigationLink(d.name, value: Route.design(d.id)) }
                    NavigationLink { NewDesignView(roomID: roomID) } label: { Label("New design", systemImage: "plus") }
                }
                Section {
                    NavigationLink("Check the floor plan") {
                        ReviewView(model: ReviewModel(editable: room.editable, units: app.units, onSave: { [app] in try app.saveEdits(roomID, $0) }))
                    }
                    .accessibilityIdentifier("checkFloorPlan")
                    Button("View in 3D and AR") { viewing = true }
                    Button("Rescan this room") { rescanning = true }
                    if let url = app.shareFile(room: room) {
                        ShareLink(item: url, preview: SharePreview(room.name, image: SharePicture.image(room.room, nil, colours: room.colours))) { Text("Send this room") }
                    }
                    Button("Rename") { newName = room.name; renaming = true }
                    Button("Delete this room", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(room.name)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $viewing) { RoomViewer(room: room.room, layout: nil, colours: room.colours) }
            .sheet(isPresented: $rescanning) {
                NavigationStack {
                    ScanView(onFinished: { raw, colours in
                        rescanning = false
                        report = app.rescan(roomID, raw: raw, colours: colours)
                    }, continueTitle: "Use this scan")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { rescanning = false } } }
                }
            }
            .alert("Rename room", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") { app.change { try $0.renameRoom(roomID, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete \(room.name) and its designs?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    app.change { try $0.deleteRoom(roomID) }
                }
            }
            .alert("Rescan finished", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reportText)
            }
        } else {
            Text("This room is gone.").foregroundStyle(.secondary)
        }
    }

    private var reportText: String {
        guard let report else { return "" }
        let kept = report.kept.isEmpty ? "No corrections to keep." : "Kept: " + report.kept.joined(separator: ", ") + "."
        return ([kept] + report.notKept).joined(separator: "\n")
    }
}
