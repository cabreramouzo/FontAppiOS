import SwiftUI

/// Real control anchors keep coach marks attached to the buttons on every screen size.
enum MapHelpTarget: Int, CaseIterable {
    case layers, filters, missions, offline, gpx, location, add

    var next: Self? {
        Self(rawValue: rawValue + 1)
    }

    var title: String {
        switch self {
        case .layers: L10n.t("map.layers")
        case .filters: L10n.t("map.filters")
        case .missions: L10n.t("mission.title")
        case .offline: L10n.t("ios.offline.title")
        case .gpx: "GPX"
        case .location: L10n.t("map.recenter")
        case .add: L10n.t("map.addFont")
        }
    }

    var detail: String {
        let key: String = switch self {
        case .layers: "ios.mapHelp.layers"
        case .filters: "ios.mapHelp.filters"
        case .missions: "ios.mapHelp.missions"
        case .offline: "ios.mapHelp.offline"
        case .gpx: "ios.mapHelp.gpx"
        case .location: "ios.mapHelp.location"
        case .add: "ios.mapHelp.add"
        }
        return L10n.t(key)
    }
}

struct MapHelpAnchors: PreferenceKey {
    static var defaultValue: [MapHelpTarget: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [MapHelpTarget: Anchor<CGRect>],
                       nextValue: () -> [MapHelpTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}

extension View {
    func mapHelpTarget(_ target: MapHelpTarget) -> some View {
        anchorPreference(key: MapHelpAnchors.self, value: .bounds) { [target: $0] }
    }
}

/// One translucent step at a time: a clear hole reveals the actual button, while the
/// arrow and card explain it. The overlay consumes touches so the map does not move.
struct MapHelpOverlay: View {
    let target: MapHelpTarget
    let anchor: Anchor<CGRect>
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let control = proxy[anchor]
            let hole = control.insetBy(dx: -5, dy: -5)
            let cardWidth = min(236.0, max(190.0, proxy.size.width - 110))
            let cardX = max(16.0, control.minX - cardWidth - 38)
            let cardY = max(64.0, min(control.midY - 75, proxy.size.height - 200))

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16))
                }
                .fill(.black.opacity(0.68), style: FillStyle(eoFill: true))
                .ignoresSafeArea()

                Arrow(from: CGPoint(x: cardX + cardWidth + 3, y: cardY + 72),
                      to: CGPoint(x: control.minX - 8, y: control.midY))
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                VStack(alignment: .leading, spacing: 10) {
                    Text(target.title).font(.headline)
                    Text(target.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("\(target.rawValue + 1) / \(MapHelpTarget.allCases.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.t(target.next == nil ? "ios.close" : "welcome.next")) {
                            if target.next == nil { onClose() } else { onNext() }
                        }
                        .font(.subheadline.bold())
                        .frame(minHeight: 44)
                    }
                }
                .foregroundStyle(.primary)
                .padding(14)
                .frame(width: cardWidth, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .position(x: cardX + cardWidth / 2, y: cardY + 80)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel(L10n.t("ios.close"))
                .position(x: 34, y: 34)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .contain)
    }
}

private struct Arrow: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        path.move(to: CGPoint(x: to.x - 8, y: to.y - 5))
        path.addLine(to: to)
        path.addLine(to: CGPoint(x: to.x - 8, y: to.y + 5))
        return path
    }
}
