import SwiftUI

struct ContentView: View {
    var body: some View {
        MapScreen()
    }
}

#Preview {
    ContentView()
        .environment(LocationService())
}
