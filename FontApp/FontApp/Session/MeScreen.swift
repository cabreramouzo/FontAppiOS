import SwiftUI

/// The "Me" tab: the account and signing out. The rest of the web's profile comes later.
struct MeScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(Outbox.self) private var outbox
    @State private var showsSignIn = false
    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            Group {
                if session.isSignedIn {
                    account
                } else if !outbox.items.isEmpty {
                    // Signed out with contributions still on the phone: show them, they
                    // are why signing in matters right now.
                    List {
                        Section {
                            Button(L10n.t("nav.enter")) { showsSignIn = true }.frame(minHeight: 44)
                        } footer: {
                            Text(L10n.t("ios.signInPrompt"))
                        }
                        PendingSection()
                    }
                } else {
                    ContentUnavailableView {
                        Label(L10n.t("nav.profile"), systemImage: "person.crop.circle")
                    } description: {
                        Text(L10n.t("ios.signInPrompt"))
                    } actions: {
                        Button(L10n.t("nav.enter")) { showsSignIn = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            .navigationTitle(L10n.t("nav.profile"))
            .sheet(isPresented: $showsSignIn) { SignInView() }
        }
    }

    private var account: some View {
        List {
            Section(L10n.t("settings.account")) {
                if let user = session.user {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(user.name).font(.headline)
                            if session.isStaff {
                                Text(L10n.t("staff.tag"))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.white)
                                    .background(Color.staff, in: Capsule())
                            }
                        }
                        Text("@\(user.username)").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ProgressView()
                }
            }
            PendingSection()
            Section {
                Button(role: .destructive) {
                    isSigningOut = true
                    Task {
                        await session.signOut()
                        isSigningOut = false
                    }
                } label: {
                    HStack {
                        Text(L10n.t("nav.logout"))
                        if isSigningOut { Spacer(); ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isSigningOut)
            }
        }
        .task { await session.refresh() }
    }
}

extension Color {
    /// Staff accounts contribute in this purple, so it is never done as staff by mistake.
    static let staff = Color(hex: 0x7C3AED)
}
