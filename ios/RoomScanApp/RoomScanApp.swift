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
            RoomsView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .room(let id): RoomDetailView(roomID: id)
                    case .design(let id): DesignDetailView(designID: id)
                    case .pin(let pin): Text(pin.design.title)
                    case .board: EmptyView()
                    }
                }
        }
        .modifier(ToastModifier(message: $app.toast))
    }
}
