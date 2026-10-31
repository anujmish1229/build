import SwiftUI
import RoomScanKit

@main
struct RoomScanApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Single-room flow until the library arrives: scan or pick a sample, then review.
struct RootView: View {
    private let store = RoomStore(url: RoomStore.defaultURL)
    @State private var stored: StoredRoom?
    @State private var scanning = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            List {
                if let stored {
                    NavigationLink("Check the floor plan") {
                        ReviewView(model: ReviewModel(editable: stored.editable, onSave: { edited in
                            var copy = stored
                            copy.editable = edited
                            try store.save(copy)
                            self.stored = copy
                        }))
                    }
                }
                Button("Scan a room") { scanning = true }
                Section("Sample rooms") {
                    ForEach(SampleRooms.all, id: \.name) { sample in
                        Button(sample.name) { save(StoredRoom(editable: EditableRoom(room: sample.room))) }
                    }
                }
                Section("Design a sample room") {
                    ForEach(SampleRooms.all, id: \.name) { sample in
                        NavigationLink(sample.name) { ThemeDesignView(room: sample.room, roomName: sample.name) }
                    }
                }
                Section("Fixed furniture list") {
                    ForEach(SampleRooms.all, id: \.name) { sample in
                        NavigationLink(sample.name) { SolverDemoView(sample: sample) }
                    }
                }
                if let note { Text(note).font(.footnote) }
            }
            .navigationTitle("RoomScan")
            .navigationDestination(isPresented: $scanning) {
                ScanView(onFinished: accept)
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        do { stored = try store.load() } catch { note = error.localizedDescription }
    }

    private func save(_ value: StoredRoom) {
        do { try store.save(value); stored = value } catch { note = "Couldn't save: \(error.localizedDescription)" }
    }

    private func accept(_ raw: RawRoom) {
        scanning = false
        do {
            let result = try RoomImport.importRoom(raw)
            var editable = EditableRoom(room: result.room)
            if let previous = stored?.editable {
                let merged = RoomMerge.merge(previous: previous, rescan: result.room)
                editable = merged.result
                note = (["Kept: " + merged.report.kept.joined(separator: ", ")] + merged.report.notKept).joined(separator: "\n")
            }
            save(StoredRoom(editable: editable, rawScan: raw, sourceIDs: result.sourceIDs))
        } catch {
            note = error.localizedDescription
        }
    }
}
