import XCTest
@testable import xxMac

final class SpotlightApplicationFinderTests: XCTestCase {
    func testFilteredApplicationPathsKeepsOnlyTopLevelAppsInsideSearchRoots() {
        let paths = [
            "/Applications/Safari.app",
            "/Applications/Safari.app/Contents/Helpers/Safari Helper.app",
            "/Users/test/Tools/Example.app",
            "/Users/test/Downloads/Outside.app",
            "/Applications/Readme.txt"
        ]

        XCTAssertEqual(
            SpotlightApplicationFinder.filteredApplicationPaths(
                paths,
                within: ["/Applications", "/Users/test/Tools"]
            ),
            ["/Applications/Safari.app", "/Users/test/Tools/Example.app"]
        )
    }

    func testFilteredApplicationPathsRemovesDuplicates() {
        XCTAssertEqual(
            SpotlightApplicationFinder.filteredApplicationPaths(
                ["/Applications/Safari.app", "/Applications/Safari.app"],
                within: ["/Applications"]
            ),
            ["/Applications/Safari.app"]
        )
    }
}
