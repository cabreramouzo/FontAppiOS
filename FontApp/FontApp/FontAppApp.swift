import SwiftUI

@main
struct FontAppApp: App {
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(location)
        }
    }
}
