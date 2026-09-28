import SwiftUI

/// Someone's public profile, as the web's `/users/:id`: who they are, what they have
/// earned (never what is missing: that is their business), their fountains and reviews.
/// `handle` is the username or the id; the server resolves both.
struct UserProfileScreen: View {
    let handle: String

    @State private var user: PublicUser?
    @State private var notFound = false
    @State private var fonts: [FontSummary]?
    @State private var comments: [MyComment]?
    @State private var game: PublicGamification?
    @State private var showcase: Showcase?

    /// Long lists are cut, as on the web: a prolific account's page must not be endless
    /// for whoever comes to look at it.
    private static let cap = 10
    @State private var allFonts = false
    @State private var allComments = false

    var body: some View {
        List {
            if notFound {
                Text(L10n.t("user.notFound")).foregroundStyle(.secondary)
            } else if let user {
                header(user)
                if let game, game.level != nil || !game.badges.isEmpty { gameSection(game) }
                fontsSection
                commentsSection
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .navigationTitle(user.map { "@\($0.username)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: handle) { await load() }
        .sheet(item: $showcase) { BadgeShowcaseView(showcase: $0) }
    }

    private func load() async {
        let api = APIClient.shared
        do { user = try await api.publicUser(handle) } catch { notFound = true; return }
        async let f = try? api.userFonts(handle)
        async let c = try? api.userComments(handle)
        async let g = try? api.userGamification(handle)
        fonts = await f ?? []
        comments = await c ?? []
        game = await g
    }

    private func header(_ user: PublicUser) -> some View {
        Section {
            HStack(spacing: 16) {
                Text(initials(user.name))
                    .font(.title2.bold()).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name).font(.title2.bold())
                    Text(verbatim: "@\(user.username)" + (user.createdAt.map {
                        " · " + L10n.t("user.memberSince", ["when": RelativeTime.string(since: $0)])
                    } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                    if user.anonymized == true {
                        Text(L10n.t("user.deleted")).font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                    // Only when they chose to make it public.
                    if let email = user.email, let url = URL(string: "mailto:\(email)") {
                        Link(destination: url) { Text("\(L10n.t("user.contact")): \(email)").font(.subheadline) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func gameSection(_ game: PublicGamification) -> some View {
        Section(L10n.t("user.gamification")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    if let level = game.level {
                        Button {
                            showcase = Showcase(kind: .level, key: level, tier: nil, locked: false, subtitle: nil)
                        } label: {
                            VStack(spacing: 4) {
                                LevelImage(key: level, size: 56)
                                Text(L10n.t("game.level.\(level)")).font(.caption.weight(.heavy))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("game.level.\(level)"))
                    }
                    ForEach(game.badges, id: \.family) { badge in
                        Button {
                            showcase = Showcase(kind: .badge, key: badge.family, tier: badge.tier, locked: false, subtitle: nil)
                        } label: {
                            BadgeImage(family: badge.family, tier: badge.tier, size: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("game.badge.\(badge.family)"))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private var fontsSection: some View {
        Section(L10n.t("user.fonts", ["n": fonts?.count ?? 0])) {
            if let fonts {
                if fonts.isEmpty { Text(L10n.t("user.noFonts")).foregroundStyle(.secondary) }
                ForEach(allFonts ? fonts : Array(fonts.prefix(Self.cap))) { font in
                    NavigationLink { FontDetailView(fontID: font.id) } label: {
                        HStack(spacing: 12) {
                            Text(font.source?.emoji ?? "💧").font(.title3).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.fontName(font.name))
                                if let place = font.municipality ?? font.region {
                                    Text(place).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
                if !allFonts, fonts.count > Self.cap {
                    Button(L10n.t("ios.showAll", ["n": fonts.count])) { withAnimation { allFonts = true } }
                }
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder private var commentsSection: some View {
        Section(L10n.t("user.reviews", ["n": comments?.count ?? 0])) {
            if let comments {
                if comments.isEmpty { Text(L10n.t("user.noReviews")).foregroundStyle(.secondary) }
                ForEach(allComments ? comments : Array(comments.prefix(Self.cap))) { comment in
                    NavigationLink { FontDetailView(fontID: comment.fontID) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(L10n.fontName(comment.fontName)).font(.body.weight(.semibold))
                                if let status = WaterStatus(comment.waterStatus) {
                                    Text("\(status.emoji) \(L10n.t(status.labelKey))").font(.caption)
                                }
                            }
                            if let date = comment.createdAt {
                                Text(RelativeTime.string(since: date)).font(.caption).foregroundStyle(.secondary)
                            }
                            if !comment.body.isEmpty { Text(comment.body).font(.subheadline).lineLimit(4) }
                        }
                        .padding(.vertical, 2)
                    }
                }
                if !allComments, comments.count > Self.cap {
                    Button(L10n.t("ios.showAll", ["n": comments.count])) { withAnimation { allComments = true } }
                }
            } else {
                ProgressView()
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        guard let first = parts.first?.first else { return "?" }
        return (String(first) + (parts.dropFirst().first?.first.map(String.init) ?? "")).uppercased()
    }
}

/// "@someone", tappable: opens their profile from wherever a page shows the way to.
struct UserLink: View {
    let username: String
    @Environment(\.openProfile) private var openProfile

    var body: some View {
        if let openProfile {
            // The accent explicitly: inside a secondary caption it would read as plain text.
            Button { openProfile(username) } label: { Text(verbatim: "@\(username)").foregroundStyle(Color.accentColor) }
                .buttonStyle(.borderless)
        } else {
            Text(verbatim: "@\(username)")
        }
    }
}

extension EnvironmentValues {
    /// Set by a page that can push a profile onto its navigation stack.
    @Entry var openProfile: ((String) -> Void)? = nil
}
