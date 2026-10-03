import SwiftUI

/// Real control frames keep coach marks attached to the buttons on every screen size.
enum MapHelpTarget: Int, CaseIterable {
    case layers, filters, legend, missions, offline, gpx, route, location, add

    var next: Self? {
        Self(rawValue: rawValue + 1)
    }

    /// The next step whose control is on screen: the route chip exists only while a route
    /// is on the map, and a step without its control would leave the tour stuck.
    func next(among frames: [MapHelpTarget: CGRect]) -> Self? {
        var candidate = next
        while let target = candidate, frames[target] == nil { candidate = target.next }
        return candidate
    }

    var title: String {
        switch self {
        case .layers: L10n.t("map.layers")
        case .filters: L10n.t("map.filters")
        case .legend: L10n.t("legend.show")
        case .missions: L10n.t("mission.title")
        case .offline: L10n.t("ios.offline.title")
        case .gpx: "GPX"
        case .route: L10n.t("ios.routes.title")
        case .location: L10n.t("map.recenter")
        case .add: L10n.t("map.addFont")
        }
    }

    var detail: String {
        let key: String = switch self {
        case .layers: "ios.mapHelp.layers"
        case .filters: "ios.mapHelp.filters"
        case .legend: "ios.mapHelp.legend"
        case .missions: "ios.mapHelp.missions"
        case .offline: "ios.mapHelp.offline"
        case .gpx: "ios.mapHelp.gpx"
        case .route: "ios.mapHelp.route"
        case .location: "ios.mapHelp.location"
        case .add: "ios.mapHelp.add"
        }
        return L10n.t(key)
    }
}

struct MapHelpFrames: PreferenceKey {
    static var defaultValue: [MapHelpTarget: CGRect] { [:] }

    static func reduce(value: inout [MapHelpTarget: CGRect],
                       nextValue: () -> [MapHelpTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}

extension View {
    func mapHelpTarget(_ target: MapHelpTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: MapHelpFrames.self,
                                       value: [target: proxy.frame(in: .global)])
            }
        }
    }
}

/// One translucent step at a time: a clear hole reveals the actual button, while the
/// arrow and card explain it. The overlay consumes touches so the map does not move.
struct MapHelpOverlay: View {
    let target: MapHelpTarget
    let globalFrame: CGRect
    /// Position among the steps on screen, and how many there are.
    let step: Int
    let steps: Int
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        // The dimming covers the whole screen, notch and home indicator included (a field
        // test saw undimmed strips there); the card and the close button stay inside the
        // safe area, read from the outer reader before the inner one ignores it.
        GeometryReader { outer in
        let insets = outer.safeAreaInsets
        GeometryReader { proxy in
            // The map ignores safe areas while its overlays do not. Convert both from
            // the same global space, rather than resolving an anchor in the overlay's
            // local space (which shifted the highlight up by one button).
            let origin = proxy.frame(in: .global).origin
            let control = globalFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let hole = control.insetBy(dx: -5, dy: -5)
            let cardWidth = min(236.0, max(190.0, proxy.size.width - 110))
            // Controls on the right get the card to their left; the route chip, on the left
            // and wide, gets it below.
            let below = control.midX < proxy.size.width / 2
            let cardX = below ? 16.0 : max(16.0, control.minX - cardWidth - 38)
            let cardHeight = min(196.0, max(160.0, proxy.size.height * 0.32))
            let cardY = below
                ? min(control.maxY + 44, proxy.size.height - insets.bottom - cardHeight - 8)
                : max(insets.top + 8, min(control.midY - cardHeight / 2,
                                          proxy.size.height - insets.bottom - cardHeight - 8))
            let arrowY = max(cardY + 20, min(control.midY, cardY + cardHeight - 20))
            let arrowFrom = below ? CGPoint(x: cardX + 40, y: cardY - 3) : CGPoint(x: cardX + cardWidth + 3, y: arrowY)
            let arrowTo = below ? CGPoint(x: cardX + 40, y: control.maxY + 8) : CGPoint(x: control.minX - 8, y: control.midY)
            let closeY = control.midY > proxy.size.height / 2
                ? insets.top + 26
                : proxy.size.height - insets.bottom - 110

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16))
                }
                .fill(.black.opacity(0.68), style: FillStyle(eoFill: true))

                Arrow(from: arrowFrom, to: arrowTo)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                VStack(alignment: .leading, spacing: 10) {
                    Text(target.title).font(.headline)
                    Text(target.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack {
                        Text("\(step) / \(steps)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.t(step == steps ? "ios.close" : "welcome.next")) {
                            if step == steps { onClose() } else { onNext() }
                        }
                        .font(.subheadline.bold())
                        .frame(minHeight: 44)
                    }
                }
                .foregroundStyle(.primary)
                .padding(14)
                .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .position(x: cardX + cardWidth / 2, y: cardY + cardHeight / 2)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel(L10n.t("ios.close"))
                .position(x: 34, y: closeY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
        .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
    }
}

private struct Arrow: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(1, hypot(dx, dy))
        let direction = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let base = CGPoint(x: to.x - direction.x * 12, y: to.y - direction.y * 12)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        path.move(to: CGPoint(x: base.x + normal.x * 6, y: base.y + normal.y * 6))
        path.addLine(to: to)
        path.addLine(to: CGPoint(x: base.x - normal.x * 6, y: base.y - normal.y * 6))
        return path
    }
}
