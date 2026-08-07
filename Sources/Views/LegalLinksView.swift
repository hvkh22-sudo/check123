import SwiftUI

/// App Review guideline 5.1.1(i): "All apps must include a link to their privacy policy in
/// the App Store Connect metadata field **and within the app in an easily accessible
/// manner**." Metadata alone is not enough, so this sits on the home screen (reachable at
/// launch and after every Done/Restart, which reset navigation to the root) and directly
/// beside the purchase, where a reviewer looks for it.
struct LegalLinksView: View {
    /// One source of truth for the hosted pages, so the in-app links cannot drift away from
    /// the URLs entered in App Store Connect. Verified live on 2026-08-07.
    enum Destination {
        static let privacyString = "https://hvkh22-sudo.github.io/borderpixel/privacy/"
        static let supportString = "https://hvkh22-sudo.github.io/borderpixel/support/"

        // Force-unwrapped deliberately: these are compile-time constants, and
        // LegalLinksTests fails the build if either ever stops parsing as HTTPS.
        static let privacy = URL(string: privacyString)!
        static let support = URL(string: supportString)!
    }

    var body: some View {
        HStack(spacing: 8) {
            Link("Privacy Policy", destination: Destination.privacy)
            Text("·")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Link("Support", destination: Destination.support)
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    LegalLinksView()
}
