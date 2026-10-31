import RoomScanKit
import SwiftUI

@main
struct RoomScanApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .onOpenURL { app.open($0) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack(path: $app.path) {
            BoardView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .room(let id): RoomDetailView(roomID: id)
                    case .design(let id): DesignDetailView(designID: id)
                    case .pin(let pin): PinDetailView(pin: pin)
                    case .board(let id): SavedBoardView(boardID: id)
                    case .rooms: RoomsView()
                    case .boards: BoardsView()
                    }
                }
        }
        .modifier(ToastModifier(message: $app.toast))
        .tint(Editorial.accent)
        .preferredColorScheme(.light)
    }
}
