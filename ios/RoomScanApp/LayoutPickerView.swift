import RoomScanKit
import SwiftUI

/// One layout at a time in 3D, moved through with arrows or a swipe. "Use this layout" keeps it.
struct LayoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let room: CanonicalRoom
    let colours: RoomColours
    let wallPaint: WallPaint.Paint?
    let options: [LayoutOption]
    let onUse: (LayoutOption) -> Void
    @State private var index = 0

    private var option: LayoutOption { options[min(index, options.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(options.indices, id: \.self) { i in
                    ObjectSceneView(room: room, layout: options[i].layout, colours: colours, wallPaint: wallPaint?.hex, interactive: false, onTap: { _ in })
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 340)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button { index = max(index - 1, 0) } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0)
                            .accessibilityLabel("Previous layout")
                        Spacer()
                        Text("Layout \(index + 1) of \(options.count)").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button { index = min(index + 1, options.count - 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(index >= options.count - 1)
                            .accessibilityLabel("Next layout")
                    }
                    Text(option.summary).font(.headline).accessibilityIdentifier("layoutSummary")
                    Text(pieceLine).font(.subheadline)
                    if !option.layout.unplaced.isEmpty {
                        Text("\(option.layout.unplaced.count) didn't fit").font(.footnote).foregroundStyle(.orange)
                    }
                    if !option.notes.isEmpty { Text(option.notes).font(.footnote) }
                    Text("Furniture chosen by: \(option.provider)").font(.caption).foregroundStyle(.secondary)
                    Button {
                        onUse(option)
                    } label: {
                        Text("Use this layout").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pumpkin).controlSize(.large)
                    .accessibilityIdentifier("useLayout")
                }
                .padding()
            }
        }
        .nightBackground()
        .navigationTitle("Choose a layout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pieceLine: String {
        let count = option.layout.placed.count
        let total = option.placedProducts.compactMap(\.price).reduce(0, +)
        let currency = option.placedProducts.first?.currency ?? ""
        return "\(count) piece\(count == 1 ? "" : "s")" + (total > 0 ? ", about $\(Int(total)) \(currency)" : "")
    }
}
