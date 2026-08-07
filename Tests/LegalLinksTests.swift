import Foundation
import XCTest
@testable import PassCheck

/// Guideline 5.1.1(i) requires a working in-app privacy link. `LegalLinksView.Destination`
/// force-unwraps its URLs, so these tests are what keeps that force-unwrap honest: a typo
/// that stops the string parsing fails the build here instead of crashing a reviewer's app.
final class LegalLinksTests: XCTestCase {
    func testPrivacyURLParsesAsHTTPS() throws {
        let url = try XCTUnwrap(URL(string: LegalLinksView.Destination.privacyString))
        XCTAssertEqual(url, LegalLinksView.Destination.privacy)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertFalse(try XCTUnwrap(url.host).isEmpty)
    }

    func testSupportURLParsesAsHTTPS() throws {
        let url = try XCTUnwrap(URL(string: LegalLinksView.Destination.supportString))
        XCTAssertEqual(url, LegalLinksView.Destination.support)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertFalse(try XCTUnwrap(url.host).isEmpty)
    }

    /// The App Store Connect Privacy URL and the in-app link must be the same page. If this
    /// constant is edited, the App Store Connect field has to be updated in the same change.
    func testPrivacyURLMatchesThePublishedPage() {
        XCTAssertEqual(LegalLinksView.Destination.privacyString,
                       "https://hvkh22-sudo.github.io/borderpixel/privacy/")
    }

    func testSupportURLMatchesThePublishedPage() {
        XCTAssertEqual(LegalLinksView.Destination.supportString,
                       "https://hvkh22-sudo.github.io/borderpixel/support/")
    }
}
