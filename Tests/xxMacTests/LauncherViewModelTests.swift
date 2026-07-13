import XCTest
@testable import xxMac

final class LauncherViewModelTests: XCTestCase {
    func testExecuteSelectionClosesLauncherBeforeRunningAction() {
        let viewModel = LauncherViewModel()
        var events: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloseLauncher"),
            object: nil,
            queue: nil
        ) { _ in
            events.append("close")
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        viewModel.mode = .launcher
        viewModel.results = [
            SearchItem(
                title: "Slow App",
                subtitle: "/Applications/Slow App.app",
                iconName: "app.fill",
                type: .bookmark,
                action: { events.append("action") }
            )
        ]

        viewModel.executeSelection()

        XCTAssertEqual(events, ["close", "action"])
    }
}
