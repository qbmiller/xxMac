import XCTest
@testable import xxMac

final class SpotlightApplicationFinderTests: XCTestCase {
    func testApplicationPathInsideExcludedDirectoryIsNotIndexed() {
        XCTAssertFalse(
            AppSearchManager.shouldIndexApplicationPath(
                "/Applications/Utilities/Terminal.app",
                roots: ["/Applications"],
                excludedPaths: ["/Applications/Utilities"]
            )
        )
    }

    func testApplicationPathInSiblingDirectoryWithSamePrefixIsIndexed() {
        XCTAssertTrue(
            AppSearchManager.shouldIndexApplicationPath(
                "/Applications/Utilities Plus/Example.app",
                roots: ["/Applications"],
                excludedPaths: ["/Applications/Utilities"]
            )
        )
    }

    func testFilteredApplicationPathsKeepsOnlyTopLevelAppsInsideSearchRoots() {
        let paths = [
            "/Applications/Safari.app",
            "/Applications/Safari.app/Contents/Helpers/Safari Helper.app",
            "/Applications/.Kimi.app.installing/Contents/Frameworks/Kimi Helper.app",
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
