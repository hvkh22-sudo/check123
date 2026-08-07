import SwiftUI
import UIKit

/// Opaque cover used by every PassCheck-owned screen that can display a face/photo.
/// It appears while the scene is inactive so iOS app-switcher snapshots do not capture it.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                Text("PassCheck")
                    .font(.headline)
                Text("Your photo is hidden while the app is inactive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .accessibilityElement(children: .combine)
    }
}
