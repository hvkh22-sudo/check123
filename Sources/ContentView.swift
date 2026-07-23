import SwiftUI

/// App root — hosts the navigation flow (Intro → Document type → Review).
struct ContentView: View {
    var body: some View {
        RootView()
            .tint(Brand.primary)   // one accent colour across every screen
    }
}

#Preview {
    ContentView()
}
