import RoomScanKit
import SceneKit
import SwiftUI

/// A picture for the share sheet, rendered on the device. Falls back to a plain icon if rendering isn't possible.
enum SharePicture {
    @MainActor static func image(_ room: CanonicalRoom, _ layout: FurnitureLayout?, colours: RoomColours?, wallPaint: String? = nil,
                                 products: [CatalogEntry] = [], style: DesignStyle? = nil) -> Image {
        if let cg = RoomScene.snapshot(room, layout, colours: colours, wallPaint: wallPaint, products: products, style: style, size: CGSize(width: 480, height: 600)) {
            return Image(uiImage: UIImage(cgImage: cg))
        }
        return Image(systemName: "square.split.bottomrightquarter")
    }
}

/// Enter a theme and constraints.
struct NewDesignForm: View {
    @Binding var theme: String
    @Binding var mustHave: String
    @Binding var leaveOut: String
    @Binding var budget: String

    static let suggestions = ["Calm japandi bedroom", "Warm boho living room", "Minimalist home office", "Scandinavian dining room", "Dark moody lounge"]

    var body: some View {
        Section("Theme") {
            TextField("For example, calm japandi bedroom", text: $theme, axis: .vertical)
                .accessibilityIdentifier("themeField")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Self.suggestions, id: \.self) { s in
                        Button(s) { theme = s }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        Section("Optional") {
            TextField("Must have, such as desk, pine bed", text: $mustHave)
            TextField("Leave out, such as wardrobe", text: $leaveOut)
            TextField("Budget, such as 2500", text: $budget)
        }
    }
}

/// Theme to layouts for one of the user's rooms.
struct NewDesignView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let roomID: UUID
    @State private var theme = ""
    @State private var mustHave = ""
    @State private var leaveOut = ""
    @State private var budget = ""
    @State private var working = false
    @State private var options: [LayoutOption] = []
    @State private var showPicker = false
    @State private var askPaint = false
    @State private var paint: WallPaint.Paint?

    var body: some View {
        if let room = app.library.room(roomID) {
            let issues = RoomValidation.validate(room.room, units: app.units)
            Form {
                NewDesignForm(theme: $theme, mustHave: $mustHave, leaveOut: $leaveOut, budget: $budget)
                Section("Room colours") {
                    ColourEditor(colours: Binding(get: { app.library.room(roomID)?.colours ?? RoomColours() }, set: { app.setColours(roomID, $0) }))
                }
                if RoomValidation.hasErrors(issues) {
                    Section("Fix these first") { ForEach(issues.filter { $0.level == .error }) { IssueRow(issue: $0) } }
                }
                Section {
                    Button(action: { start(room) }) {
                        HStack {
                            Text(working ? "Designing…" : "Show me layouts")
                            if working { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(working || RoomValidation.hasErrors(issues))
                    .accessibilityIdentifier("designButton")
                }
            }
            .navigationTitle("New design")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showPicker) {
                LayoutPickerView(room: room.room, colours: room.colours, wallPaint: paint, options: options) { option in
                    save(option)
                }
            }
            .confirmationDialog("Your walls clash with this look. Would you repaint?", isPresented: $askPaint, titleVisibility: .visible) {
                ForEach(WallPaint.suggestions(for: theme), id: \.self) { p in
                    Button(p.name.capitalized) { paint = p; generate(room) }
                }
                Button("Keep my walls") { paint = nil; generate(room) }
            }
        }
    }

    private var constraints: FurnishConstraints {
        func list(_ s: String) -> [String] { s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return FurnishConstraints(mustHave: list(mustHave), mustAvoid: list(leaveOut), budget: budget.isEmpty ? nil : budget)
    }

    private func start(_ room: SavedRoom) {
        paint = nil
        if WallPaint.clashes(room.colours.wall, theme: theme) { askPaint = true } else { generate(room) }
    }

    private func generate(_ room: SavedRoom) {
        working = true
        let (plan, theme, constraints, name, colours) = (room.room, theme, constraints, room.name, room.colours)
        Task {
            let found = await Task.detached {
                await DesignStudio.options(room: plan, theme: theme, constraints: constraints, roomName: name, colours: colours)
            }.value
            options = found
            working = false
            showPicker = !found.isEmpty
            if found.isEmpty { app.say("Couldn't make a layout for this room.") }
        }
    }

    private func save(_ option: LayoutOption) {
        let name = theme.isEmpty ? "Design" : String(theme.prefix(40))
        if let design = app.change({ try $0.addDesign(SavedDesign(option: option, roomID: roomID, name: name, theme: theme, wallPaint: paint)) }) {
            showPicker = false
            dismiss()
            app.path.append(Route.design(design.id))
            app.say("Saved \(design.name).")
        }
    }
}

/// A saved design: 3D, facts, pieces, typed changes, and actions.
struct DesignDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let designID: UUID
    @State private var request = ""
    @State private var working = false
    @State private var report: [String] = []
    @State private var undo: SavedDesign?
    @State private var viewing = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var swapping: FurnitureLayout.Placed?
    @State private var adding = false

    static let suggestions = ["Make it cheaper", "Paint the walls sage", "Remove the plant", "Add a lamp"]

    private var design: SavedDesign? { app.library.designs.first { $0.id == designID } }

    var body: some View {
        if let design, let room = app.library.room(design.roomID) {
            let colours = room.colours
            List {
                Section {
                    ObjectSceneView(room: room.room, layout: design.layout, colours: colours, wallPaint: design.wallPaint?.hex, products: design.products, style: design.plan.style, interactive: false, onTap: { _ in })
                        .frame(height: 240).allowsHitTesting(false)
                    Button("View in 3D and AR") { viewing = true }.accessibilityIdentifier("open3D")
                    Text(design.summary).font(.headline)
                    Text(factLine(design)).font(.subheadline).foregroundStyle(.secondary)
                    if let paint = design.wallPaint { Text("Walls painted \(paint.name) in this design.").font(.footnote) }
                    if !design.notes.isEmpty { Text(design.notes).font(.footnote) }
                    Text("Furniture chosen by: \(design.provider)").font(.caption).foregroundStyle(.secondary)
                }
                Section("Floor plan") {
                    FurnishedPlanView(room: room.room, layout: design.layout).frame(height: 220)
                    if let url = svgFile(design, room: room) { ShareLink("Share floor plan (SVG)", item: url) }
                }
                Section("Change it in your own words") {
                    TextField("For example, swap the sofa for a smaller one", text: $request)
                        .onSubmit { runEdit(design, room) }
                        .accessibilityIdentifier("editField")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.suggestions, id: \.self) { s in
                                Button(s) { request = s; runEdit(design, room) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    if working { ProgressView("Working…") }
                    ForEach(report, id: \.self) { Text($0).font(.footnote) }
                    if let undo {
                        Button("Undo that change") {
                            app.change { store in try store.updateDesign(designID) { $0 = undo } }
                            self.undo = nil
                            report = []
                        }
                    }
                }
                Section("Pieces (\(design.layout.placed.count))") {
                    ForEach(design.layout.placed) { p in
                        ProductRow(piece: p, entry: design.products.first { $0.catalogID == p.catalogID })
                            .swipeActions {
                                Button("Remove", role: .destructive) { apply(design) { DesignStudio.remove($0, itemID: p.itemID, room: room.room) } }
                                Button("Swap") { swapping = p }.tint(.blue)
                            }
                            .contextMenu {
                                Button("Swap") { swapping = p }
                                Button("Remove", role: .destructive) { apply(design) { DesignStudio.remove($0, itemID: p.itemID, room: room.room) } }
                            }
                    }
                    Button { adding = true } label: { Label("Add a piece", systemImage: "plus") }
                }
                if !design.layout.unplaced.isEmpty {
                    Section("Didn't fit") {
                        ForEach(design.layout.unplaced) { u in
                            VStack(alignment: .leading) {
                                Text(design.plan.items.first { $0.itemID == u.itemID }?.name ?? u.itemID)
                                Text(u.reason).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    if let url = app.shareFile(design: design, room: room) {
                        ShareLink(item: url, preview: SharePreview(design.name, image: SharePicture.image(room.room, design.layout, colours: colours, wallPaint: design.wallPaint?.hex, products: design.products, style: design.plan.style))) { Text("Send this design") }
                    }
                    Button("Rename") { newName = design.name; renaming = true }
                    Button("Duplicate") {
                        var copy = design
                        copy.id = UUID()
                        copy.createdAt = Date()
                        app.change { try $0.addDesign(copy) }
                        app.say("Duplicated \(design.name).")
                    }
                    Button("Delete this design", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(design.name)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $viewing) {
                RoomViewer(room: room.room, layout: design.layout, colours: colours, wallPaint: design.wallPaint?.hex, products: design.products, style: design.plan.style)
            }
            .sheet(item: $swapping) { piece in
                CatalogPicker(title: "Swap \(piece.name ?? piece.itemID)", entries: DesignStudio.alternatives(for: piece.itemID, in: design.option)) { entry in
                    apply(design) { option in
                        let swapped = DesignStudio.swap(option, itemID: piece.itemID, to: entry, room: room.room)
                        guard swapped.layout.placed.contains(where: { $0.itemID == piece.itemID }) else {
                            app.say("\(entry.name) doesn't fit there, so nothing changed.")
                            return option
                        }
                        return swapped
                    }
                }
            }
            .sheet(isPresented: $adding) {
                CatalogPicker(title: "Add a piece", entries: FurnitureCatalog.current.entries) { entry in
                    apply(design) { option in
                        guard let added = DesignStudio.add(option, entry: entry, room: room.room) else {
                            app.say("There's no room for \(entry.name).")
                            return option
                        }
                        return added
                    }
                }
            }
            .alert("Rename design", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") { app.change { store in try store.updateDesign(designID) { $0.name = newName } } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete \(design.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    app.change { try $0.deleteDesign(designID) }
                }
            }
        } else {
            Text("This design is gone.").foregroundStyle(.secondary)
        }
    }

    private func factLine(_ design: SavedDesign) -> String {
        let count = design.layout.placed.count
        let total = Prices.totalText(design.placedProducts, home: Prices.homeCurrency).map { ", \($0)" } ?? ""
        return "\(count) piece\(count == 1 ? "" : "s")\(total)"
    }

    private func store(_ option: LayoutOption, paint: WallPaint.Paint?, into design: SavedDesign) {
        app.change { store in
            try store.updateDesign(designID) {
                $0.plan = option.plan
                $0.layout = option.layout
                $0.summary = option.summary
                $0.products = option.products
                $0.wallPaint = paint
            }
        }
    }

    private func apply(_ design: SavedDesign, _ edit: (LayoutOption) -> LayoutOption) {
        store(edit(design.option), paint: design.wallPaint, into: design)
    }

    private func runEdit(_ design: SavedDesign, _ room: SavedRoom) {
        let text = request.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        working = true
        let (option, plan, colours, paint) = (design.option, room.room, room.colours, design.wallPaint)
        Task {
            let result = await Task.detached {
                await DesignEditor.edit(option, request: text, room: plan, colours: colours, wallPaint: paint)
            }.value
            working = false
            report = result.report
            if result.changed {
                undo = design
                store(result.option, paint: result.wallPaint, into: design)
                request = ""
            }
        }
    }

    private func svgFile(_ design: SavedDesign, room: SavedRoom) -> URL? {
        try? ShareFiles.temporaryFile(Data(RoomRenderer.svg(room.room, design.layout, units: app.units).utf8),
                                      name: ShareFiles.fileName(design.name, ext: "svg"))
    }
}

/// A searchable list of products.
struct CatalogPicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let entries: [CatalogEntry]
    let onPick: (CatalogEntry) -> Void
    @State private var search = ""

    private var shown: [CatalogEntry] {
        let q = search.lowercased()
        return q.isEmpty ? entries : entries.filter { $0.name.lowercased().contains(q) || $0.category.replacingOccurrences(of: "_", with: " ").contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(shown) { entry in
                Button {
                    onPick(entry)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(entry.name).foregroundStyle(.primary)
                        Text([entry.priceText, entry.size.map { String(format: "%.2f", $0) }.joined(separator: " × ") + " m"].compactMap { $0 }.joined(separator: ", "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
