import RoomScanKit
import SwiftUI

/// After a scan: name the room, check its colours, then design it or check the plan first.
struct NewRoomView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let roomID: UUID
    @State private var name = ""

    var body: some View {
        if let room = app.library.room(roomID) {
            let hasErrors = RoomValidation.hasErrors(RoomValidation.validate(room.room, units: app.units))
            Form {
                Section {
                    FurnishedPlanView(room: room.room, layout: nil).frame(height: 240)
                    LabeledContent("Area", value: Units.area(room.room.derived.area, app.units))
                    LabeledContent("Doors and windows", value: "\(room.room.openings.count)")
                }
                Section("Name") {
                    TextField("Name", text: $name)
                        .onSubmit(saveName)
                        .accessibilityIdentifier("roomName")
                }
                Section("Colours") {
                    ColourEditor(colours: Binding(get: { app.library.room(roomID)?.colours ?? RoomColours() }, set: { app.setColours(roomID, $0) }))
                }
                Section {
                    NavigationLink("Design this room") { NewDesignView(roomID: roomID) }
                        .disabled(hasErrors)
                    NavigationLink("Check the floor plan first") {
                        ReviewView(model: ReviewModel(editable: room.editable, units: app.units, onSave: { [app] in try app.saveEdits(roomID, $0) }))
                    }
                    if hasErrors { Text("This plan has a problem. Check the floor plan to fix it.").font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Your room")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { saveName(); dismiss() } } }
            .onAppear { if name.isEmpty { name = room.name } }
            .onDisappear(perform: saveName)
        }
    }

    private func saveName() {
        guard app.library.room(roomID)?.name != name, !name.isEmpty else { return }
        app.change { try $0.renameRoom(roomID, to: name) }
    }
}
