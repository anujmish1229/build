import RoomScanKit
import SwiftUI

/// The app's state: the library, short messages at the bottom of the screen, and where to go after opening a file.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library = Library()
    @Published var toast: String?
    @Published var path = NavigationPath()

    let store: LibraryStore
    @AppStorage("unitSystem") var unitsRaw = UnitSystem.deviceDefault.rawValue

    var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .deviceDefault }

    init(directory: URL? = nil) {
        let dir = directory ?? (try? LibraryStore.defaultDirectory()) ?? FileManager.default.temporaryDirectory
        store = LibraryStore(directory: dir)
        if let problem = store.problem { toast = problem }
        do {
            try Migrations.importLegacyRoom(from: RoomStore(url: RoomStore.defaultURL), into: store)
            try store.addSamplesIfNeeded()
        } catch {
            toast = error.localizedDescription
        }
        library = store.current
    }

    func say(_ text: String) { toast = text }

    /// Runs a library change, refreshes the screens, and says so if the save failed (FR-T3).
    @discardableResult
    func change<T>(_ work: (LibraryStore) throws -> T) -> T? {
        do {
            let value = try work(store)
            library = store.current
            return value
        } catch {
            toast = "Couldn't save: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Rooms

    func addScan(_ raw: RawRoom, colours: RoomColours?, name: String = "New room") -> SavedRoom? {
        do {
            let imported = try RoomImport.importRoom(raw)
            return change { try $0.addRoom(SavedRoom(name: name, room: imported.room, rawScan: raw, sourceIDs: imported.sourceIDs, colours: colours ?? RoomColours())) }
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    /// A rescan keeps the room's id and designs, and replays its corrections (UC11).
    func rescan(_ id: UUID, raw: RawRoom, colours: RoomColours?) -> MergeReport? {
        guard let previous = library.room(id) else { return nil }
        do {
            let imported = try RoomImport.importRoom(raw)
            let merged = RoomMerge.merge(previous: previous.editable, rescan: imported.room)
            change { store in
                try store.updateRoom(id) { room in
                    room.room = merged.result.room
                    room.corrections = merged.result.corrections
                    room.rawScan = raw
                    room.sourceIDs = imported.sourceIDs
                    if let colours { room.colours = colours }
                }
            }
            return merged.report
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func saveEdits(_ id: UUID, _ edited: EditableRoom) throws {
        try store.updateRoom(id) { room in
            room.room = edited.room
            room.corrections = edited.corrections
        }
        library = store.current
    }

    func setColours(_ id: UUID, _ colours: RoomColours) {
        change { try $0.updateRoom(id) { $0.colours = colours } }
    }

    // MARK: Opening and sending files

    /// Opens a file from outside or from Rooms, then goes to what it added (FR-H3).
    func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            switch try ShareFiles.read(data) {
            case .scan(let scan):
                if let room = change({ try $0.addRoom(SavedRoom(name: scan.name, room: scan.room, colours: scan.colours)) }) {
                    toast = "Added \(room.name)."
                    path = NavigationPath()
                    path.append(Route.room(room.id))
                }
            case .design(let design):
                let pin = BoardPin(id: design.id, source: .shared, design: design)
                if change({ try $0.addPin(pin) }) != nil {
                    toast = "Added \(design.title) to your Board."
                    path = NavigationPath()
                    path.append(Route.pin(pin))
                }
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    func shareFile(room: SavedRoom) -> URL? {
        try? ShareFiles.temporaryFile(ShareFiles.data(ScanPackage(room)), name: ShareFiles.fileName(room.name, ext: ShareFiles.scanExtension))
    }

    func shareFile(design: SavedDesign, room: SavedRoom) -> URL? {
        try? ShareFiles.temporaryFile(ShareFiles.data(DesignPackage(design, room: room)), name: ShareFiles.fileName(design.name, ext: ShareFiles.designExtension))
    }
}

/// Where the main navigation stack can go.
enum Route: Hashable {
    case room(UUID)
    case design(UUID)
    case pin(BoardPin)
    case board(UUID)

    static func == (a: Route, b: Route) -> Bool { a.key == b.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
    private var key: String {
        switch self {
        case .room(let id): "room" + id.uuidString
        case .design(let id): "design" + id.uuidString
        case .pin(let pin): "pin" + pin.id
        case .board(let id): "board" + id.uuidString
        }
    }
}

/// A short message at the bottom of the screen (FR-T3).
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.footnote)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .onTapGesture { self.message = nil }
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if self.message == message { self.message = nil }
                    }
                    .accessibilityIdentifier("toast")
            }
        }
    }
}
