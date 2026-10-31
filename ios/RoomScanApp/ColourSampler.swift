import ARKit
import CoreImage
import RoomScanKit

/// Estimates wall and floor colours while scanning: about once a second it averages a patch of the camera
/// picture, as floor when looking down and as wall when roughly level. Only averages are kept, never a picture.
final class ColourSampler {
    private var timer: Timer?
    private weak var session: ARSession?
    private var walls: [(Double, Double, Double)] = []
    private var floors: [(Double, Double, Double)] = []
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    func start(_ session: ARSession) {
        self.session = session
        walls = []
        floors = []
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.sample() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The colours seen so far, or nil with too few samples.
    var colours: RoomColours? { RoomColours.estimate(walls: walls, floors: floors) }

    private func sample() {
        guard let frame = session?.currentFrame, frame.camera.trackingState == .normal else { return }
        let pitch = frame.camera.eulerAngles.x // Negative is looking down.
        let looksDown = pitch < -0.75, level = abs(pitch) < 0.25
        guard looksDown || level else { return }
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let extent = image.extent
        let w = extent.width * 0.2, h = extent.height * 0.2
        // For walls, the part above the middle: furniture is usually lower.
        let y = level ? extent.midY + extent.height * 0.12 : extent.midY - h / 2
        let patch = CGRect(x: extent.midX - w / 2, y: y, width: w, height: h)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: patch)]),
              let output = filter.outputImage else { return }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let rgb = (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
        if looksDown { floors.append(rgb) } else { walls.append(rgb) }
    }
}
