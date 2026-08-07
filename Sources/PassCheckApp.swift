import SwiftUI

// BorderPixel — honest, on-device US passport-photo compliance checker.
// The type and target keep the original PassCheck names on purpose; see project.yml.
// NOTE: authored on Windows without Xcode; first compiled/verified by CI (macOS runner).
@main
struct PassCheckApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
