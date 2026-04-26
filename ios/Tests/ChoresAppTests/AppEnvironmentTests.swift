import XCTest
@testable import ChoresApp

final class AppEnvironmentTests: XCTestCase {
    func testApiBaseURLIsConfigured() {
        let url = AppEnvironment.apiBaseURL
        XCTAssertFalse(url.absoluteString.isEmpty, "ApiBaseURL must be set in Info.plist")
        XCTAssertNotNil(url.scheme, "ApiBaseURL must include a scheme")
    }
}
