import SwiftUI
import TipKit

/// One-off hints, each shown once, where the action it explains is about to happen.
/// Not a guided tour: a walkthrough after the welcome and the permissions would be a third
/// interruption in a row (FontAppBE/CLAUDE.md, "Qué hace cada botón del mapa").
enum AppTips {
    static func configure() {
        #if DEBUG
        // `-resetTips` in the scheme's launch arguments brings them all back.
        if ProcessInfo.processInfo.arguments.contains("-resetTips") { try? Tips.resetDatastore() }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// Over the three chips, the first time a fountain opens.
struct QuickReviewTip: Tip {
    var title: Text { Text(L10n.t("ios.tip.quickTitle")) }
    var message: Text? { Text(L10n.t("ios.tip.quickBody")) }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// Under the thanks of the first review that landed: it would also have worked offline.
struct OfflineReviewTip: Tip {
    var title: Text { Text(L10n.t("ios.tip.offlineTitle")) }
    var message: Text? { Text(L10n.t("ios.tip.offlineBody")) }
    var image: Image? { Image(systemName: "wifi.slash") }
}

/// On the (?) of the map, after the app has been opened three times in a week and the
/// help never (opening it invalidates the tip).
struct MapHelpTip: Tip {
    static let appOpened = Event(id: "appOpened")

    var title: Text { Text(L10n.t("ios.tip.helpTitle")) }
    var message: Text? { Text(L10n.t("ios.tip.helpBody")) }
    var image: Image? { Image(systemName: "questionmark.circle") }

    var rules: [Rule] {
        #Rule(Self.appOpened) { $0.donations.donatedWithin(.week).count >= 3 }
    }
}

/// The first tap on GPX: what the two choices do, with the choices on the tip itself.
struct GPXTip: Tip {
    static let import_ = "import"
    static let export = "export"
    static let tapped = Event(id: "gpxTapped")

    var title: Text { Text(verbatim: "GPX") }
    var message: Text? { Text(L10n.t("ios.tip.gpxBody")) }
    var image: Image? { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") }

    var rules: [Rule] {
        #Rule(Self.tapped) { $0.donations.count >= 1 }
    }

    var actions: [Action] {
        Action(id: Self.import_, title: L10n.t("ios.gpx.import"))
        Action(id: Self.export, title: L10n.t("ios.gpx.export"))
    }
}

/// For a tip the reader stops to read: larger type and full-width buttons that never
/// have to scroll inside the popover (the Spanish export label did not fit).
struct RoomyTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                configuration.image?
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 6) {
                    configuration.title?.font(.title3.weight(.semibold))
                    configuration.message?
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    configuration.tip.invalidate(reason: .tipClosed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("ios.close"))
            }
            ForEach(Array(configuration.actions.enumerated()), id: \.offset) { index, action in
                Button(action: action.handler) {
                    action.label()
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(index == 0 ? AnyPrimitiveButtonStyle(.borderedProminent) : AnyPrimitiveButtonStyle(.bordered))
                .buttonBorderShape(.capsule)
            }
        }
        .padding(18)
        .frame(idealWidth: 340)
    }
}

/// Lets one `ForEach` pick a different button style per row.
private struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init(_ style: some PrimitiveButtonStyle) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
