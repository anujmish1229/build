import SwiftUI

/// Shown before every scan.
struct ScanTutorialView: View {
    let onStart: () -> Void

    private let tips: [(icon: String, title: String, detail: String)] = [
        ("sun.max", "Good lighting", "Turn on the lights so walls and corners are easy to see."),
        ("curtains.open", "Curtains open", "Keep curtains open so windows are found."),
        ("figure.walk", "Walk the perimeter slowly", "Move steadily along each wall."),
        ("arrow.up.left.and.arrow.down.right", "Scan the ceiling and corners", "Tilt up and down so every corner is seen."),
        ("rectangle.on.rectangle.slash", "Avoid mirrors and glass", "Reflections can look like extra rooms."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Before you scan").font(.largeTitle.bold())
                ForEach(tips, id: \.title) { tip in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: tip.icon).font(.title3).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title).font(.headline)
                            Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Only walls, doors and windows are kept. No photos or video are saved.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(action: onStart) {
                    Text("Start scanning").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding()
        }
    }
}
