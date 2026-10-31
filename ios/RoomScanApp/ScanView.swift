import SwiftUI
import RoomScanKit
#if canImport(RoomPlan)
import RoomPlan
#endif

/// The whole capture flow: capability check, tutorial, capture, then result.
struct ScanView: View {
    /// Called when the user accepts a usable scan.
    let onFinished: (RawRoom) -> Void
    /// The label for the accept button on the result screen.
    var continueTitle = "Continue"

    private enum Stage {
        case tutorial, capturing, result(RawRoom), failed(String)
    }
    @State private var stage: Stage = .tutorial

    var body: some View {
        switch CapabilityGate.check() {
        case .unsupported(let reason):
            VStack(spacing: 16) {
                Image(systemName: "sensor.tag.radiowaves.forward").font(.largeTitle)
                Text("Scanning isn't available").font(.title2.bold())
                Text(reason).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding()
            .accessibilityIdentifier("scanUnsupported")
        case .supported:
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .tutorial:
            ScanTutorialView { stage = .capturing }
        case .capturing:
            CaptureScreen { result in
                switch result {
                case .success(let raw):
                    // A scan too small to use never replaces earlier data.
                    stage = raw.hasEnoughWalls ? .result(raw)
                        : .failed("That scan found only \(raw.walls.count) wall\(raw.walls.count == 1 ? "" : "s"). A room needs at least three, so nothing was saved.")
                case .failure:
                    stage = .failed("The scan didn't finish. Try again with more light, and move a little more slowly.")
                }
            }
        case .result(let raw):
            ScanResultView(raw: raw, continueTitle: continueTitle, onContinue: { onFinished(raw) }, onRescan: { stage = .tutorial })
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text(message).multilineTextAlignment(.center)
                Button("Scan again") { stage = .tutorial }.buttonStyle(.borderedProminent)
            }.padding()
        }
    }
}

/// Shows what was found and offers to continue or scan again.
struct ScanResultView: View {
    let raw: RawRoom
    let continueTitle: String
    let onContinue: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Found \(raw.summary)").font(.title3.bold()).multilineTextAlignment(.center)
            ScanSketchView(review: ScanReview(raw: raw)).frame(height: 240)
            Button(action: onContinue) { Text(continueTitle).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Scan again", action: onRescan)
            if let data = try? raw.encoded() {
                ShareLink("Export JSON", item: RawScanFile(data: data), preview: SharePreview("Raw scan"))
                    .font(.footnote)
            }
        }
        .padding()
    }
}

/// A sketch of the scan: orange when a surface is flagged, red when that flag is tapped.
struct ScanSketchView: View {
    let review: ScanReview
    @State private var tapped: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in
                let points = review.lines.flatMap { [$0.a, $0.b] }
                let fit = PlanFit(bounds: PlanMath.bounds(points), width: size.width, height: size.height, padding: 12)
                for line in review.lines {
                    let a = fit.screen(line.a), b = fit.screen(line.b)
                    var path = Path()
                    path.move(to: CGPoint(x: a.x, y: a.y)); path.addLine(to: CGPoint(x: b.x, y: b.y))
                    let color: Color = line.id == tapped ? .red : line.flagged ? .orange : (line.kind == "wall" ? .primary : .blue)
                    ctx.stroke(path, with: .color(color), lineWidth: line.kind == "wall" ? 3 : 5)
                }
            }
            ForEach(review.flags) { flag in
                Button { tapped = tapped == flag.id ? nil : flag.id } label: {
                    Label(flag.message ?? "", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(tapped == flag.id ? .red : .orange)
                }
            }
        }
    }
}

struct RawScanFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("raw_room.json")
    }
}

#if canImport(RoomPlan) && !targetEnvironment(simulator)
private struct CaptureScreen: View {
    let onResult: (Result<RawRoom, Error>) -> Void
    @State private var stopRequested = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureRepresentable(stopRequested: $stopRequested, onResult: onResult)
                .ignoresSafeArea()
            if !stopRequested {
                Button("Done") { stopRequested = true }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom, 32)
            }
        }
    }
}

private struct RoomCaptureRepresentable: UIViewRepresentable {
    @Binding var stopRequested: Bool
    let onResult: (Result<RawRoom, Error>) -> Void

    func makeCoordinator() -> RoomCaptureCoordinator { RoomCaptureCoordinator(onResult: onResult) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        if stopRequested, !context.coordinator.stopped {
            context.coordinator.stopped = true
            view.captureSession.stop()
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        view.captureSession.stop()
    }
}

@objc(RoomCaptureCoordinator)
final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate {
    let onResult: (Result<RawRoom, Error>) -> Void
    var stopped = false
    init(onResult: @escaping (Result<RawRoom, Error>) -> Void) { self.onResult = onResult }
    required init?(coder: NSCoder) { return nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error { onResult(.failure(error)); return false }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error { onResult(.failure(error)); return }
        onResult(.success(RoomPlanExport.rawRoom(from: processedResult)))
    }
}
#else
private struct CaptureScreen: View {
    let onResult: (Result<RawRoom, Error>) -> Void
    var body: some View { Text("Scanning isn't available on this device.") }
}
#endif
