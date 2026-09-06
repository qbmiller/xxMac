import XCTest
@testable import xxMac

final class TodoDeepLinkTests: XCTestCase {
    func testRoutesTodoURL() throws {
        let url = try XCTUnwrap(URL(string: "xxmac://todo"))

        XCTAssertEqual(TodoDeepLink.route(for: url), .todo)
    }

    func testRejectsWrongScheme() throws {
        let url = try XCTUnwrap(URL(string: "https://todo"))

        XCTAssertNil(TodoDeepLink.route(for: url))
    }

    func testRejectsWrongHost() throws {
        let url = try XCTUnwrap(URL(string: "xxmac://settings"))

        XCTAssertNil(TodoDeepLink.route(for: url))
    }

    func testRejectsAdditionalPath() throws {
        let url = try XCTUnwrap(URL(string: "xxmac://todo/task"))

        XCTAssertNil(TodoDeepLink.route(for: url))
    }
}
