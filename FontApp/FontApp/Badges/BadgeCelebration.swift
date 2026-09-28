import Observation
import SwiftUI
import UIKit

/// Notices a badge or a level you did not have, to celebrate it, as the web does.
///
/// Badges count only settled contributions, but the celebration counts what is settling
/// too (the server's preview), so it comes while the fountain is still in front of you.
/// What was already seen is kept on the phone per account; **the first time nothing is
/// celebrated**, only remembered, or someone with eight badges would get eight parties
/// the day this ships. Several at once: one is shown and the rest are counted.
@Observable
final class BadgeCelebrations {
    struct Novelty: Identifiable, Equatable {
        let badge: BadgesPreview.Badge?
        let level: String?
        let others: Int
        var id: String { level.map { "level-\($0)" } ?? "\(badge?.family ?? ""):\(badge?.tier ?? "")" }
    }

    private(set) var current: Novelty?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var checkedAtLaunch: UUID?
    @ObservationIgnored private var polling: Task<Void, Never>?

    init(api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
    }

    func dismiss() { current = nil }

    /// Once per launch and account, after a breath so it does not land on a loading screen.
    func checkAtLaunch(_ userID: UUID?) {
        guard let userID, checkedAtLaunch != userID else { return }
        checkedAtLaunch = userID
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await check(userID)
        }
    }

    /// Right after contributing. The game runs a few seconds behind the request on
    /// purpose, so it asks at 2, 6 and 14 s and stops: by then there was nothing to give.
    func contributed(_ userID: UUID?) {
        guard let userID else { return }
        polling?.cancel()
        polling = Task {
            for wait in [2.0, 4.0, 8.0] {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                if await check(userID) { return }
            }
        }
    }

    @discardableResult
    func check(_ userID: UUID) async -> Bool {
        guard current == nil, let preview = try? await api.badgesPreview() else { return false }
        guard let novelty = Self.novelty(in: preview, user: userID, defaults: defaults) else { return false }
        current = novelty
        return true
    }

    /// Compares with what was seen and remembers what there is now.
    static func novelty(in preview: BadgesPreview, user: UUID, defaults: UserDefaults) -> Novelty? {
        let badgesKey = "badges.seen.\(user.uuidString)"
        let levelKey = "level.seen.\(user.uuidString)"
        let badges = preview.badges ?? []
        let marks = badges.map { "\($0.family):\($0.tier)" }
        let seen = defaults.stringArray(forKey: badgesKey)
        let seenLevel = defaults.string(forKey: levelKey)
        defaults.set(marks, forKey: badgesKey)
        defaults.set(preview.level, forKey: levelKey)
        guard let seen else { return nil }

        let known = Set(seen)
        let fresh = badges.filter { !known.contains("\($0.family):\($0.tier)") }
        // Going up a level first: it is the bigger step, and the badge is counted.
        if let level = preview.level, let seenLevel, level != seenLevel {
            return Novelty(badge: nil, level: level, others: fresh.count)
        }
        guard !fresh.isEmpty else { return nil }
        // The highest tier first: with a gold and a bronze at once, the gold is the one.
        let order = ["bronze", "silver", "gold", "unique"]
        let sorted = fresh.sorted { (order.firstIndex(of: $0.tier) ?? -1) > (order.firstIndex(of: $1.tier) ?? -1) }
        return Novelty(badge: sorted[0], level: nil, others: fresh.count - 1)
    }
}

/// "Thanks for contributing, you just earned Pioneer", with confetti. Full screen over the
/// app, the badge settling in with a spring, and the success haptic.
struct BadgeCelebrationView: View {
    let novelty: BadgeCelebrations.Novelty
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showsAll = false

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55)).ignoresSafeArea()
                .onTapGesture {}
            VStack(spacing: 10) {
                Text(L10n.t(novelty.level != nil ? "celebrate.levelUp" : "celebrate.eyebrow"))
                    .font(.caption.bold()).textCase(.uppercase).foregroundStyle(Color.accentColor)
                art
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
                    .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -20))
                    .padding(.vertical, 8)
                Text(name).font(.title2.bold()).multilineTextAlignment(.center)
                if let tier = novelty.badge?.tier, tier != "unique", tier != "special" {
                    Text(L10n.t("game.tier.\(tier)")).font(.subheadline.bold())
                        .foregroundStyle(TierColor.color(tier) ?? .secondary)
                }
                Text(L10n.t("celebrate.thanks")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let about { Text(about).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if novelty.others > 0 {
                    Text(L10n.t(novelty.level != nil ? "celebrate.andBadges" : "celebrate.andMore", ["n": novelty.others]))
                        .font(.footnote.bold()).foregroundStyle(.secondary)
                }
                // It goes ahead of the 72 h settling: for three days the showcase still
                // says "on its way". One line here; without it, it looks broken.
                Text(L10n.t("celebrate.pending")).font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                Button(action: onClose) {
                    Text(L10n.t("celebrate.nice")).bold().frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 8)
                Button(L10n.t("celebrate.seeAll")) { showsAll = true }
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 360)
            // Tinted so the text reads over the map; the glass alone let everything through.
            .glassEffect(.regular.tint(Color(.systemBackground).opacity(0.75)), in: RoundedRectangle(cornerRadius: 32))
            .padding(24)
            .opacity(appeared || reduceMotion ? 1 : 0)
            // In front of everything, falling over the card, as Messages does.
            if !reduceMotion {
                ConfettiView().ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.15)) { appeared = true }
        }
        .sheet(isPresented: $showsAll, onDismiss: onClose) {
            NavigationStack { BadgesScreen() }
        }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder private var art: some View {
        if let level = novelty.level {
            LevelImage(key: level, size: 160)
        } else if let badge = novelty.badge {
            BadgeImage(family: badge.family, tier: badge.tier, size: 150)
                .shadow(color: (TierColor.color(badge.tier) ?? .accentColor).opacity(0.5), radius: 20)
        }
    }

    private var name: String {
        if let level = novelty.level { return L10n.t("game.level.\(level)") }
        return L10n.t("game.badge.\(novelty.badge?.family ?? "")")
    }

    private var about: String? {
        novelty.level != nil ? L10n.lookup("game.levelAbout") : novelty.badge.flatMap { L10n.lookup("game.badgeAbout.\($0.family)") }
    }
}

/// Confetti the iOS way: a Core Animation emitter above the screen that bursts for a
/// moment and lets the pieces fall and tumble, as Messages does. Water colours.
struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = EmitterHost()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class EmitterHost: UIView {
        private let emitter = CAEmitterLayer()
        private var started = false

        override func layoutSubviews() {
            super.layoutSubviews()
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: -20)
            emitter.emitterSize = CGSize(width: bounds.width, height: 1)
            emitter.frame = bounds
            guard !started, bounds.width > 0 else { return }
            started = true
            burst()
        }

        private func burst() {
            emitter.emitterShape = .line
            emitter.renderMode = .oldestLast
            let colors: [UIColor] = [.systemBlue, .systemTeal, .systemCyan, .systemYellow, .systemGreen, .systemPink, .systemOrange]
            emitter.emitterCells = colors.flatMap { color in
                [Self.cell(color, image: Self.piece(CGSize(width: 10, height: 6), round: false)),
                 Self.cell(color, image: Self.piece(CGSize(width: 7, height: 7), round: true))]
            }
            emitter.beginTime = CACurrentMediaTime()
            layer.addSublayer(emitter)
            // A burst, not a rain: stop making pieces and let the last ones fall.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [emitter] in emitter.birthRate = 0 }
        }

        private static func cell(_ color: UIColor, image: CGImage?) -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            cell.birthRate = 7
            cell.lifetime = 7
            cell.velocity = 260
            cell.velocityRange = 120
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 5
            cell.yAcceleration = 180
            cell.spin = 3
            cell.spinRange = 6
            cell.scale = 1
            cell.scaleRange = 0.5
            cell.alphaSpeed = -0.1
            return cell
        }

        private static func piece(_ size: CGSize, round: Bool) -> CGImage? {
            UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill()
                let rect = CGRect(origin: .zero, size: size)
                if round { context.cgContext.fillEllipse(in: rect) } else { context.fill(rect) }
            }.cgImage
        }
    }
}
