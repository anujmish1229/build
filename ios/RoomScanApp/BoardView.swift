import RoomScanKit
import SwiftUI

/// Pictures of designs, rendered on the device off the main thread and kept in memory (FR-O7).
@MainActor
final class PinPictures: ObservableObject {
    static let shared = PinPictures()
    @Published private(set) var images: [String: UIImage] = [:]
    private var pending = Set<String>()

    func request(_ pin: BoardPin) {
        guard images[pin.id] == nil, pending.insert(pin.id).inserted else { return }
        let design = pin.design
        Task.detached(priority: .utility) {
            let image = RoomScene.snapshot(design.room, design.layout, colours: design.colours, products: design.products, style: design.plan.style, size: CGSize(width: 480, height: 600)).map { UIImage(cgImage: $0) }
            await MainActor.run {
                if let image { self.images[pin.id] = image }
            }
        }
    }
}

/// The home screen: a two-column board of designs (FR-B1). It shows straight away from the ready-made
/// file; pictures fill in as they render, with the floor plan standing in until then.
struct BoardView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("feedAddress") private var feedAddress = ""
    @State private var filter = BoardContents.Filter()
    @State private var scanning = false
    @State private var newRoom: SavedRoom?

    private static let rooms = [("bedroom", "Bedroom"), ("living", "Living"), ("office", "Office"), ("dining", "Dining")]
    private static let styles = FurniturePlanner.styles

    var body: some View {
        let all = app.pins
        let shown = BoardContents.filtered(all, filter)
        let columns = BoardContents.columns(shown) { 1 + Double(($0.design.title.count + 3) % 4) * 0.08 }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                filters(all)
                if shown.isEmpty {
                    Text("Nothing matches those filters.").foregroundStyle(.secondary).padding()
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns.indices, id: \.self) { i in
                        LazyVStack(spacing: 10) {
                            ForEach(columns[i]) { pin in
                                NavigationLink(value: Route.pin(pin)) { PinCard(pin: pin) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("pin-\(pin.id)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .background(Editorial.paper)
        .refreshable { if !feedAddress.isEmpty { await app.refreshFeed(feedAddress) } }
        .navigationTitle("Board")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: Route.rooms) { Image(systemName: "square.split.bottomrightquarter") }
                    .accessibilityLabel("Rooms").accessibilityIdentifier("goRooms")
                NavigationLink(value: Route.boards) { Image(systemName: "bookmark") }
                    .accessibilityLabel("Boards").accessibilityIdentifier("goBoards")
                Button { scanning = true } label: { Image(systemName: "camera.metering.matrix") }
                    .accessibilityLabel("Scan").accessibilityIdentifier("goScan")
                NavigationLink(value: Route.settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings").accessibilityIdentifier("goSettings")
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
    }

    private func filters(_ all: [BoardPin]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chips {
                Chip(title: "All", selected: filter.source == nil) { filter.source = nil }
                Chip(title: "Yours", selected: filter.source == .mine) { filter.source = .mine }
                if all.contains(where: { $0.source == .shared }) { Chip(title: "Shared", selected: filter.source == .shared) { filter.source = .shared } }
                if all.contains(where: { $0.source == .feed }) { Chip(title: "Feed", selected: filter.source == .feed) { filter.source = .feed } }
                ForEach(Self.rooms, id: \.0) { value, title in
                    Chip(title: title, selected: filter.roomType == value) { filter.roomType = filter.roomType == value ? nil : value }
                }
            }
            chips {
                ForEach(Self.styles, id: \.self) { style in
                    Chip(title: style.capitalized, selected: filter.style == style) { filter.style = filter.style == style ? nil : style }
                }
            }
        }
    }

    private func chips<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }.padding(.horizontal, 10)
        }
    }
}

struct PinCard: View {
    let pin: BoardPin
    @ObservedObject private var pictures = PinPictures.shared

    private var height: CGFloat { 170 + CGFloat((pin.design.title.count + 3) % 4) * 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The colour sets the card's width, so a picture can't push its column wider.
            Color(red: 0.93, green: 0.91, blue: 0.88)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let image = pictures.images[pin.id] {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        FurnishedPlanView(room: pin.design.room, layout: pin.design.layout).padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(pin.design.title).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(Editorial.ink)
            Text(cardLine).font(.caption).foregroundStyle(.secondary)
            Text(pin.source.label).font(.caption2).foregroundStyle(Editorial.accent)
        }
        .padding(8)
        .background(Editorial.card, in: RoundedRectangle(cornerRadius: 16))
        .task { pictures.request(pin) }
        .accessibilityElement(children: .combine)
    }

    private var cardLine: String {
        let total = Prices.totalText(pin.design.placedProducts, home: Prices.homeCurrency).map { ", \($0)" } ?? ""
        let count = pin.design.layout.placed.count
        return "\(count) piece\(count == 1 ? "" : "s")\(total)"
    }
}

/// The user's named boards (FR-B7).
struct BoardsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var creating = false
    @State private var name = ""

    var body: some View {
        List {
            ForEach(app.library.boards) { board in
                NavigationLink(value: Route.board(board.id)) {
                    LabeledContent(board.name, value: "\(board.pinIDs.count)")
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { app.library.boards[$0].id }
                app.change { store in for id in ids { try store.deleteBoard(id) } }
            }
            if app.library.boards.isEmpty {
                Text("Save a design from the Board to start a board.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Boards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { name = ""; creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("New board")
            }
        }
        .alert("New board", isPresented: $creating) {
            TextField("Name", text: $name)
            Button("Create") { app.change { try $0.addBoard(name) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SavedBoardView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let boardID: UUID
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        if let board = app.library.boards.first(where: { $0.id == boardID }) {
            List {
                ForEach(board.pinIDs, id: \.self) { id in
                    if let pin = app.pin(id) {
                        NavigationLink(value: Route.pin(pin)) { Text(pin.design.title) }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { board.pinIDs[$0] }
                    app.change { store in for id in ids { try store.remove(pinID: id, from: boardID) } }
                }
                if board.pinIDs.isEmpty { Text("Nothing saved here yet.").foregroundStyle(.secondary) }
            }
            .navigationTitle(board.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Rename") { name = board.name; renaming = true }
                        Button("Delete board", role: .destructive) {
                            dismiss()
                            app.change { try $0.deleteBoard(boardID) }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .alert("Rename board", isPresented: $renaming) {
                TextField("Name", text: $name)
                Button("Save") { app.change { try $0.renameBoard(boardID, to: name) } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
