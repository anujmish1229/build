#if canImport(SceneKit)
import CoreGraphics
import Foundation

/// A floor surface drawn in code from the room's own floor colour: boards, tiles, pile or trowelled concrete.
enum FloorTexture {
    /// The width of floor one copy of a texture covers, in metres.
    static let tile = 2.4
    private static let size = 1024
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    static func image(hex: String, type: FloorType) -> CGImage? {
        guard let base = RoomColours.rgb(hex) else { return nil }
        let key = hex + type.rawValue
        lock.lock()
        defer { lock.unlock() }
        if let done = cache[key] { return done }
        let made = draw(base, type)
        cache[key] = made
        return made
    }

    /// A fixed sequence, so a floor looks the same every time.
    private struct Noise {
        var state: UInt64 = 0x1234_5678
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 40) & 0xFFFF) / 65535
        }
    }

    private static func draw(_ base: (r: Double, g: Double, b: Double), _ type: FloorType) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var noise = Noise()
        let s = CGFloat(size)
        func colour(_ shade: Double, alpha: Double = 1) -> CGColor {
            CGColor(srgbRed: min(base.r * shade, 1), green: min(base.g * shade, 1), blue: min(base.b * shade, 1), alpha: alpha)
        }
        ctx.setFillColor(colour(1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        switch type {
        case .wood, .laminate:
            // Rows of boards with staggered ends, each its own shade, with a fine grain.
            let rows = 16, rowH = s / CGFloat(rows)
            for row in 0..<rows {
                var x = -noise.next() * 400
                while x < Double(size) {
                    let length = 320 + noise.next() * 340
                    let shade = 0.82 + noise.next() * 0.28
                    let y = CGFloat(row) * rowH
                    let rect = CGRect(x: CGFloat(x), y: y, width: CGFloat(length), height: rowH)
                    ctx.setFillColor(colour(shade))
                    ctx.fill(rect)
                    for _ in 0..<10 {
                        let gy = y + CGFloat(noise.next()) * rowH
                        ctx.setStrokeColor(colour(shade * (0.82 + noise.next() * 0.3), alpha: 0.5))
                        ctx.setLineWidth(CGFloat(0.6 + noise.next() * 1.6))
                        ctx.move(to: CGPoint(x: CGFloat(x), y: gy))
                        ctx.addLine(to: CGPoint(x: CGFloat(x + length), y: gy + CGFloat(noise.next() - 0.5) * 7))
                        ctx.strokePath()
                    }
                    ctx.setFillColor(colour(0.42))
                    ctx.fill(CGRect(x: CGFloat(x), y: y, width: 2, height: rowH))
                    x += length
                }
                ctx.setFillColor(colour(0.46))
                ctx.fill(CGRect(x: 0, y: CGFloat(row) * rowH, width: s, height: 2))
            }
        case .tile:
            let count = 5, each = s / CGFloat(count)
            for x in 0..<count {
                for y in 0..<count {
                    ctx.setFillColor(colour(0.94 + noise.next() * 0.1))
                    ctx.fill(CGRect(x: CGFloat(x) * each, y: CGFloat(y) * each, width: each, height: each).insetBy(dx: 2.5, dy: 2.5))
                }
            }
        case .carpet, .concrete:
            let speck = type == .carpet ? 34_000 : 16_000
            for _ in 0..<speck {
                let dot = CGFloat(type == .carpet ? 2 : 1 + noise.next() * 4)
                ctx.setFillColor(colour(0.82 + noise.next() * 0.36, alpha: 0.42))
                ctx.fill(CGRect(x: CGFloat(noise.next()) * s, y: CGFloat(noise.next()) * s, width: dot, height: dot))
            }
        }
        return ctx.makeImage()
    }
}
#endif
