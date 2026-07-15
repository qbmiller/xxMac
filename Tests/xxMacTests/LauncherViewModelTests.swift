import XCTest
@testable import xxMac

final class LauncherViewModelTests: XCTestCase {
    func testSearchFieldTextDisplaysSelectedHistoryInputWithoutChangingQuery() {
        let viewModel = LauncherViewModel()
        viewModel.query = ""
        viewModel.results = [
            SearchItem(
                title: "Translate",
                subtitle: "Recent action",
                iconName: "terminal",
                type: .launcherHistory,
                launcherInputText: "yd Argentina",
                action: {}
            ),
            SearchItem(
                title: "Translate",
                subtitle: "Recent action",
                iconName: "terminal",
                type: .launcherHistory,
                launcherInputText: "yd Brazil",
                action: {}
            )
        ]

        XCTAssertEqual(viewModel.searchFieldText, "yd Argentina")
        XCTAssertEqual(viewModel.query, "")

        viewModel.selectedIndex = 1

        XCTAssertEqual(viewModel.searchFieldText, "yd Brazil")
        XCTAssertEqual(viewModel.query, "")
    }

    func testDebouncerOnlyRunsLatestScheduledAction() {
        let debouncer = LauncherCommandDebouncer(delay: 0.02)
        let latestRan = expectation(description: "latest action ran")
        var executions: [String] = []

        debouncer.schedule {
            executions.append("first")
        }
        debouncer.schedule {
            executions.append("latest")
            latestRan.fulfill()
        }

        wait(for: [latestRan], timeout: 0.5)

        XCTAssertEqual(executions, ["latest"])
    }

    func testDebouncerCancelPreventsPendingAction() {
        let debouncer = LauncherCommandDebouncer(delay: 0.02)
        let actionRan = expectation(description: "cancelled action did not run")
        actionRan.isInverted = true

        debouncer.schedule {
            actionRan.fulfill()
        }
        debouncer.cancel()

        wait(for: [actionRan], timeout: 0.1)
    }

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
