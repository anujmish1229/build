import SwiftUI

/// The way in, built from the "Haunted Edition" frame in Figma (390 × 844, scaled to the phone's
/// width). The app has no accounts, so the design's two buttons go to the two real ways in instead.
struct WelcomeView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 390
            ZStack(alignment: .top) {
                Editorial.paper
                artwork("HauntedMoon", top: 0, height: 505, scale: scale)
                artwork("HauntedPath", top: 505, height: 112, scale: scale)
                title("Poltar :", size: 43, top: 446, scale: scale)
                shade(top: 465, height: 100, scale: scale, stops: [
                    .init(color: Self.dusk.opacity(0), location: 0), .init(color: Self.dusk, location: 0.4),
                    .init(color: Self.dusk, location: 0.55), .init(color: Self.dusk.opacity(0), location: 1),
                ])
                shade(top: 500, height: 344, scale: scale, stops: [
                    .init(color: Editorial.paper.opacity(0.188), location: 0), .init(color: Editorial.paper.opacity(0.502), location: 0.2),
                    .init(color: Editorial.paper, location: 0.33), .init(color: Editorial.paper, location: 1),
                ])
                title("Haunted Edition", size: 36, top: 498, scale: scale)
                buttons.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 62 * scale)
                credits.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 26 * scale)
            }
        }
        .ignoresSafeArea()
    }

    /// The fade between the two pieces of artwork, which also hides the join.
    private static let dusk = Color(red: 0.063, green: 0.102, blue: 0.137)

    private func artwork(_ name: String, top: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        Image(name)
            .resizable()
            .frame(width: 390 * scale, height: height * scale)
            .offset(y: top * scale)
            .accessibilityHidden(true)
    }

    private func title(_ text: String, size: CGFloat, top: CGFloat, scale: CGFloat) -> some View {
        Text(text)
            .font(Editorial.title(size * scale))
            .foregroundStyle(Editorial.ink)
            .offset(y: top * scale)
    }

    private func shade(top: CGFloat, height: CGFloat, scale: CGFloat, stops: [Gradient.Stop]) -> some View {
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            .frame(height: height * scale)
            .offset(y: top * scale)
            .accessibilityHidden(true)
    }

    private var credits: some View {
        (Text("Created by Anirud, Anuj, Suad, and Tamir ") + Text(Image(systemName: "heart.fill")).foregroundColor(.red))
            .font(.footnote)
            .foregroundStyle(Editorial.ink.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .accessibilityLabel("Created by Anirud, Anuj, Suad, and Tamir")
            .accessibilityIdentifier("welcomeCredits")
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                app.entered = true
                app.scanRequested = true
            } label: {
                Text("Scan a room →").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.soft)
            .accessibilityIdentifier("welcomeScan")
            Button {
                app.entered = true
            } label: {
                Text("Explore →").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.pumpkin)
            .accessibilityIdentifier("welcomeExplore")
        }
        .controlSize(.large)
        .padding(.horizontal, 18)
    }
}
