import SwiftUI

@main
struct FontAppApp: App {
    @State private var location = LocationService()
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(location)
                .environment(session)
                .task { await session.refresh() }
        }
    }
}
