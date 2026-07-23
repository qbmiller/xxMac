import XCTest
@testable import xxMac

final class QuickShortcutRoutingTests: XCTestCase {
    func testExactWebSearchKeywordCoexistsWithAppResults() {
        let item = makeShortcut(actionType: .webSearch)

        let activation = QuickShortcutManager.resolveActivation(query: "db", items: [item])

        XCTAssertEqual(activation?.resultScope, .shortcutAndAppResults)
        XCTAssertEqual(activation?.itemID, item.id)
        guard case .ready(let match) = activation?.state else {
            return XCTFail("Expected an exact web-search keyword to be ready")
        }
        XCTAssertEqual(match.query, "")
    }

    func testWhitespaceAfterWebSearchKeywordUsesShortcutOnly() {
        let item = makeShortcut(actionType: .webSearch)

        for query in ["db ", "db movie"] {
            let activation = QuickShortcutManager.resolveActivation(query: query, items: [item])

            XCTAssertEqual(activation?.resultScope, .shortcutOnly)
        }
    }

    func testLongerAppNameDoesNotActivateShorterShortcutKeyword() {
        let item = makeShortcut(actionType: .webSearch)

        let activation = QuickShortcutManager.resolveActivation(query: "dbx", items: [item])

        XCTAssertNil(activation)
    }

    func testInputCommandCoexistsWhenExactAndWaitsExclusivelyAfterWhitespace() {
        let item = makeShortcut(actionType: .commandScript, commandInputMode: .queryPlaceholder)

        let exactActivation = QuickShortcutManager.resolveActivation(query: "db", items: [item])
        let explicitActivation = QuickShortcutManager.resolveActivation(query: "db ", items: [item])

        XCTAssertEqual(exactActivation?.resultScope, .shortcutAndAppResults)
        XCTAssertEqual(explicitActivation?.resultScope, .shortcutOnly)
        guard case .waitingForInput = exactActivation?.state,
              case .waitingForInput = explicitActivation?.state else {
            return XCTFail("Expected an input command without query text to wait for input")
        }
    }

    func testNoInputCommandCoexistsWhenExactAndRunsExclusivelyAfterWhitespace() {
        let item = makeShortcut(actionType: .commandScript, commandInputMode: .noInput)

        let exactActivation = QuickShortcutManager.resolveActivation(query: "db", items: [item])
        let explicitActivation = QuickShortcutManager.resolveActivation(query: "db ", items: [item])

        XCTAssertEqual(exactActivation?.resultScope, .shortcutAndAppResults)
        XCTAssertEqual(explicitActivation?.resultScope, .shortcutOnly)
        guard case .ready = exactActivation?.state,
              case .ready = explicitActivation?.state else {
            return XCTFail("Expected a no-input command to be ready")
        }
    }

    private func makeShortcut(
        actionType: QuickShortcutActionType,
        commandInputMode: QuickShortcutCommandInputMode = .queryPlaceholder
    ) -> QuickShortcut {
        QuickShortcut(
            title: "Test Shortcut",
            keyword: "db",
            actionType: actionType,
            payload: "",
            commandInputMode: commandInputMode
        )
    }
}
