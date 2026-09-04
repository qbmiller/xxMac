import XCTest
@testable import xxMac

final class ClipboardSearchRequestTrackerTests: XCTestCase {
    func testOnlyLatestSearchRequestCanPublishResults() {
        var tracker = ClipboardSearchRequestTracker()

        let earlierRequest = tracker.beginRequest()
        let latestRequest = tracker.beginRequest()

        XCTAssertFalse(tracker.isCurrent(earlierRequest))
        XCTAssertTrue(tracker.isCurrent(latestRequest))
    }
}
