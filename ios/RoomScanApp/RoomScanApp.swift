import SwiftUI
import RoomScanKit

@main
struct RoomScanApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScanView(onFinished: { _ in })
                    .navigationTitle("RoomScan")
            }
        }
    }
}
