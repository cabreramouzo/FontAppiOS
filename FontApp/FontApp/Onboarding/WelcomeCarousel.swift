import SwiftUI

/// Seven short, swipeable introductions. The map underneath remains usable after Skip;
/// no permission or sign-in is requested from this screen.
struct WelcomeCarousel: View {
    let onFinish: () -> Void

    @State private var page = 0

    fileprivate struct Feature {
        let title: String
        let detail: String
        let symbol: String
        let accent: String
        let color: Color
    }

    private let features: [Feature] = [
        .init(title: "welcome.findTitle", detail: "welcome.b1", symbol: "map.fill",
              accent: "magnifyingglass", color: Color(red: 0.15, green: 0.48, blue: 0.83)),
        .init(title: "ios.welcome.waterTitle", detail: "welcome.b2", symbol: "drop.fill",
              accent: "checkmark.seal.fill", color: Color(red: 0.05, green: 0.59, blue: 0.72)),
        .init(title: "ios.welcome.reportTitle", detail: "welcome.b4", symbol: "hand.tap.fill",
              accent: "arrow.triangle.2.circlepath", color: Color(red: 0.12, green: 0.62, blue: 0.43)),
        .init(title: "welcome.contributeTitle", detail: "welcome.b3", symbol: "camera.fill",
              accent: "plus", color: Color(red: 0.74, green: 0.35, blue: 0.58)),
        // Open data (ODbL, photos CC BY-SA): a shared world that is never locked.
        .init(title: "ios.welcome.openTitle", detail: "ios.welcome.openBody", symbol: "globe.europe.africa.fill",
              accent: "lock.open.fill", color: Color(red: 0.20, green: 0.55, blue: 0.30)),
        .init(title: "welcome.readyTitle", detail: "welcome.offline", symbol: "wifi.slash",
              accent: "tray.and.arrow.up.fill", color: Color(red: 0.80, green: 0.47, blue: 0.17)),
        .init(title: "ios.welcome.routeTitle", detail: "ios.welcome.routeBody", symbol: "figure.walk",
              accent: "map.fill", color: Color(red: 0.37, green: 0.42, blue: 0.76)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(features[page].color)
                Text("FontApp").font(.headline.weight(.bold))
                Spacer()
                Button(L10n.t("welcome.skip"), action: onFinish)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $page) {
                ForEach(features.indices, id: \.self) { index in
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing: 28) {
                                Spacer(minLength: 8)
                                WelcomeArtwork(feature: features[index], active: index == page)
                                    .frame(height: min(geometry.size.height * 0.48, 300))
                                VStack(spacing: 12) {
                                    Text(L10n.t(features[index].title))
                                        .font(.system(size: 29, weight: .bold, design: .rounded))
                                        .minimumScaleFactor(0.8)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.primary)
                                    Text(L10n.t(features[index].detail))
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 30)
                                Spacer(minLength: 16)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geometry.size.height)
                        }
                        .scrollIndicators(.hidden)
                    }
                    .tag(index)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(index + 1) / \(features.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(features.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? features[page].color : Color.secondary.opacity(0.25))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(page + 1) / \(features.count)")
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                if page > 0 {
                    Button(L10n.t("welcome.back")) {
                        withAnimation(.easeInOut(duration: 0.25)) { page -= 1 }
                    }
                    .frame(minWidth: 92, minHeight: 52)
                }
                Button {
                    if page == features.count - 1 { onFinish() }
                    else { withAnimation(.easeInOut(duration: 0.25)) { page += 1 } }
                } label: {
                    Text(L10n.t(page == features.count - 1 ? "welcome.cta" : "welcome.next"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(features[page].color)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }
}

private struct WelcomeArtwork: View {
    let feature: WelcomeCarousel.Feature
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floats = false

    var body: some View {
        ZStack {
            Circle()
                .fill(feature.color.opacity(0.10))
                .frame(width: 272, height: 272)
            Circle()
                .stroke(feature.color.opacity(0.18), lineWidth: 1)
                .frame(width: 238, height: 238)
                .scaleEffect(floats ? 1.06 : 0.96)
            Circle()
                .fill(LinearGradient(colors: [feature.color.opacity(0.76), feature.color],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 194, height: 194)
                .shadow(color: feature.color.opacity(0.30), radius: 24, y: 12)
            Image(systemName: feature.symbol)
                .font(.system(size: 90, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .offset(y: floats ? -9 : 5)
            Image(systemName: feature.accent)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(feature.color)
                .frame(width: 66, height: 66)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(feature.color.opacity(0.15)))
                .offset(x: floats ? 82 : 76, y: floats ? 83 : 91)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear { animateIfNeeded() }
        .onChange(of: active) { _, nowActive in
            if nowActive { animateIfNeeded() }
            else { floats = false }
        }
    }

    private func animateIfNeeded() {
        guard active, !reduceMotion else { floats = false; return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            floats = true
        }
    }
}

#Preview {
    WelcomeCarousel(onFinish: {})
}
