import SwiftUI

/// A carved pumpkin, drawn so it stays sharp at any size.
struct PumpkinMark: View {
    var body: some View {
        Canvas { context, size in
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
            func shape(_ points: [(Double, Double)]) -> Path {
                var path = Path()
                path.addLines(points.map { point($0.0, $0.1) })
                path.closeSubpath()
                return path
            }
            context.fill(shape([(0.45, 0.2), (0.47, 0.03), (0.59, 0), (0.56, 0.2)]), with: .color(Color(red: 0.42, green: 0.35, blue: 0.18)))
            // Ribs: overlapping ovals, the outer ones darker, so the middle looks nearest.
            for (x, width, light) in [(0.0, 0.58, 0.72), (0.42, 0.58, 0.72), (0.12, 0.5, 0.88), (0.38, 0.5, 0.88), (0.25, 0.5, 1.0)] {
                let oval = CGRect(origin: point(x, 0.15), size: CGSize(width: width * size.width, height: 0.85 * size.height))
                context.fill(Path(ellipseIn: oval), with: .color(Color(red: 0.91 * light, green: 0.522 * light, blue: 0.176 * light)))
            }
            let carved = GraphicsContext.Shading.color(Editorial.paper)
            context.fill(shape([(0.22, 0.52), (0.43, 0.52), (0.34, 0.36)]), with: carved)
            context.fill(shape([(0.57, 0.52), (0.78, 0.52), (0.66, 0.36)]), with: carved)
            context.fill(shape([(0.46, 0.63), (0.54, 0.63), (0.5, 0.55)]), with: carved)
            context.fill(shape([(0.18, 0.66), (0.3, 0.72), (0.36, 0.67), (0.44, 0.74), (0.5, 0.68), (0.57, 0.74), (0.64, 0.67), (0.7, 0.72), (0.82, 0.66),
                                (0.72, 0.84), (0.62, 0.8), (0.56, 0.88), (0.5, 0.82), (0.43, 0.88), (0.37, 0.8), (0.28, 0.84)]), with: carved)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The app's loading mark: a pumpkin breathing gently, or sitting still when Reduce Motion is on.
struct PumpkinSpinner: View {
    var size: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        PumpkinMark()
            .frame(width: size, height: size)
            .scaleEffect(breathing ? 1.12 : 0.88)
            .opacity(breathing ? 1 : 0.7)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = !reduceMotion }
            .accessibilityElement()
            .accessibilityLabel("Loading")
    }
}

/// A bat in silhouette: one wing, then its mirror image.
struct Bat: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for side in [-1.0, 1.0] {
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: rect.midX + side * x / 100 * rect.width, y: rect.minY + y / 56 * rect.height)
            }
            path.move(to: point(0, 14))
            path.addLine(to: point(5, 3))
            path.addLine(to: point(8, 14))
            path.addQuadCurve(to: point(50, 6), control: point(28, 0))
            path.addQuadCurve(to: point(36, 30), control: point(39, 12))
            path.addQuadCurve(to: point(22, 34), control: point(29, 22))
            path.addQuadCurve(to: point(8, 40), control: point(15, 27))
            path.addQuadCurve(to: point(0, 54), control: point(5, 47))
            path.closeSubpath()
        }
        return path
    }
}

/// A cobweb spun out from the top left corner of its frame.
struct Cobweb: Shape {
    func path(in rect: CGRect) -> Path {
        let spokes = 5, length = max(rect.width, rect.height)
        func point(_ radius: Double, _ spoke: Double) -> CGPoint {
            let angle = spoke / Double(spokes) * .pi / 2
            return CGPoint(x: rect.minX + radius * cos(angle), y: rect.minY + radius * sin(angle))
        }
        var path = Path()
        for spoke in 0...spokes {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: point(length, Double(spoke)))
        }
        for ring in [0.3, 0.52, 0.74, 0.96] {
            for spoke in 0..<spokes {
                path.move(to: point(ring * length, Double(spoke)))
                path.addQuadCurve(to: point(ring * length, Double(spoke + 1)), control: point(ring * length * 0.84, Double(spoke) + 0.5))
            }
        }
        return path
    }
}

/// The Board's seasonal banner.
struct TrickOrTreatBanner: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Editorial.pumpkin.opacity(0.42), Editorial.card], startPoint: .leading, endPoint: .trailing)
            Cobweb().stroke(Editorial.ink.opacity(0.2), lineWidth: 0.6)
                .frame(width: 92, height: 92)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Cobweb().stroke(Editorial.ink.opacity(0.2), lineWidth: 0.6)
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            Bat().fill(Editorial.paper).frame(width: 30, height: 17).rotationEffect(.degrees(-12)).offset(x: 34, y: -32)
            Bat().fill(Editorial.paper).frame(width: 22, height: 12).rotationEffect(.degrees(14)).offset(x: 150, y: -36)
            Bat().fill(Editorial.paper).frame(width: 18, height: 10).rotationEffect(.degrees(-8)).offset(x: 52, y: 34)
            PumpkinMark()
                .frame(width: 88)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("TRICK OR TREAT").font(Editorial.title(25)).foregroundStyle(Editorial.pumpkin)
                Text("your room").font(Editorial.title(21)).foregroundStyle(Editorial.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
