import RoomScanKit
import SwiftUI

/// One design from the Board: picture, facts, "Shop the look", and 3D or AR, Save, Remix, Share (FR-B5).
struct PinDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let pin: BoardPin
    @ObservedObject private var pictures = PinPictures.shared
    @State private var viewing = false
    @State private var saving = false
    @State private var choosingRoom = false
    @State private var remix: RemixRequest?
    @State private var confirmDelete = false

    struct RemixRequest: Identifiable {
        let room: SavedRoom
        let options: [LayoutOption]
        var id: UUID { room.id }
    }

    private var design: DesignPackage { pin.design }

    var body: some View {
        CardList {
            Section {
                Group {
                    if let image = pictures.images[pin.id] {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        FurnishedPlanView(room: design.room, layout: design.layout)
                    }
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                Text(design.title).font(Editorial.title(26)).foregroundStyle(Editorial.ink)
                Text(pin.source.label).font(.caption).foregroundStyle(Editorial.accent)
                if let line = priceLine { Text(line).font(.subheadline) }
                if !design.stores.isEmpty { Text(design.stores.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary) }
                if !design.notes.isEmpty { Text(design.notes).font(.footnote) }
                HStack(spacing: 6) {
                    ColourSwatches(colours: design.colours)
                    Text("\(design.colours.wallName) walls, \(design.colours.floorName) floor").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button { viewing = true } label: { Label("View in 3D and AR", systemImage: "cube") }
                    .accessibilityIdentifier("open3D")
                Button { saving = true } label: { Label("Save to a board", systemImage: "bookmark") }
                    .accessibilityIdentifier("savePin")
                Button { startRemix() } label: { Label("Remix into my room", systemImage: "wand.and.stars") }
                    .disabled(app.library.rooms.isEmpty)
                    .accessibilityIdentifier("remixPin")
                if let url = shareFile { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
                if pin.source == .shared {
                    Button("Delete this design", role: .destructive) { confirmDelete = true }
                }
            }
            Section("Shop the look") {
                ForEach(design.layout.placed) { p in
                    ProductRow(piece: p, entry: design.products.first { $0.catalogID == p.catalogID })
                }
            }
        }
        .nightBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { pictures.request(pin) }
        .fullScreenCover(isPresented: $viewing) {
            RoomViewer(room: design.room, layout: design.layout, colours: design.colours, products: design.products, style: design.plan.style)
        }
        .sheet(isPresented: $saving) { SaveToBoardSheet(pin: pin) }
        .confirmationDialog("Remix into which room?", isPresented: $choosingRoom, titleVisibility: .visible) {
            ForEach(app.library.rooms) { room in Button(room.name) { remixInto(room) } }
        }
        .sheet(item: $remix) { request in
            NavigationStack {
                LayoutPickerView(room: request.room.room, colours: request.room.colours, wallPaint: nil, options: request.options) { option in
                    if let saved = app.remixed(pin, option: option, into: request.room.id) {
                        remix = nil
                        app.say("Saved \(saved.name) to \(request.room.name).")
                        app.path.append(Route.design(saved.id))
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { remix = nil } } }
            }
        }
        .confirmationDialog("Delete \(design.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                app.change { try $0.deletePin(pin.id) }
            }
        }
    }

    private var priceLine: String? {
        Prices.totalText(design.placedProducts, home: Prices.homeCurrency)
    }

    private var shareFile: URL? {
        try? ShareFiles.temporaryFile(ShareFiles.data(design), name: ShareFiles.fileName(design.title, ext: ShareFiles.designExtension))
    }

    /// Skips the choice if there is only one room (FR-B8).
    private func startRemix() {
        if app.library.rooms.count == 1, let only = app.library.rooms.first { remixInto(only) } else { choosingRoom = true }
    }

    private func remixInto(_ room: SavedRoom) {
        let (design, plan) = (design, room.room)
        Task {
            let options = await Task.detached { DesignStudio.remix(design, into: plan) }.value
            remix = RemixRequest(room: room, options: options)
        }
    }
}

/// Save a design to one or more boards, creating one on the spot (FR-B6).
struct SaveToBoardSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let pin: BoardPin
    @State private var name = ""

    var body: some View {
        NavigationStack {
            CardList {
                Section("Your boards") {
                    ForEach(app.library.boards) { board in
                        Button {
                            toggle(board)
                        } label: {
                            HStack {
                                Text(board.name).foregroundStyle(.primary)
                                Spacer()
                                if board.pinIDs.contains(pin.id) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                Section("New board") {
                    TextField("Name", text: $name).accessibilityIdentifier("newBoardName")
                    Button("Create and save") {
                        if let board = app.change({ try $0.addBoard(name) }) {
                            app.change { try $0.save(pin, to: board.id) }
                            name = ""
                            app.say("Saved to \(board.name).")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("createBoard")
                }
            }
            .nightBackground()
            .navigationTitle("Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("saveDone") } }
        }
    }

    private func toggle(_ board: Board) {
        app.change { store in
            if board.pinIDs.contains(pin.id) { try store.remove(pinID: pin.id, from: board.id) } else { try store.save(pin, to: board.id) }
        }
    }
}
