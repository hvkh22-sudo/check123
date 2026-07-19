import XCTest
import CoreImage
@testable import PassCheck

final class ComplianceEngineTests: XCTestCase {

    func testStubReturnsNonEmptyReport() async {
        let engine = StubComplianceEngine()
        let report = await engine.analyze(CIImage.empty())
        XCTAssertFalse(report.results.isEmpty)
    }

    func testStubReportNeedsAttention() async {
        // Stub includes assisted + confirm rules, so overall is needsAttention.
        let engine = StubComplianceEngine()
        let report = await engine.analyze(CIImage.empty())
        XCTAssertEqual(report.overall, .needsAttention)
    }

    func testEngineVersionIsSet() async {
        let engine = StubComplianceEngine()
        let report = await engine.analyze(CIImage.empty())
        XCTAssertFalse(report.engineVersion.isEmpty)
    }
}
