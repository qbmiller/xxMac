import XCTest
import AppKit
@testable import xxMac

final class LauncherViewModelTests: XCTestCase {
    func testClipboardImagePreviewOpensOnlyForSelectedImage() {
        let viewModel = LauncherViewModel()
        viewModel.mode = .clipboard
        ClipboardManager.shared.selectTab(.history)
        defer { ClipboardManager.shared.selectTab(.history) }

        viewModel.results = [
            SearchItem(
                title: "Image",
                subtitle: "Clipboard image",
                iconName: "photo",
                type: .clipboard,
                clipboardPreview: .image(
                    filename: "original.png",
                    thumbnailFilename: "thumbnail.png",
                    byteSize: 1,
                    ocrStatus: nil,
                    ocrTextPreview: nil
                ),
                action: {}
            ),
            SearchItem(
                title: "Text",
                subtitle: "Clipboard text",
                iconName: "doc.text",
                type: .clipboard,
                clipboardPreview: .text(id: UUID(), preview: "text", fullLength: 4),
                action: {}
            )
        ]

        XCTAssertTrue(viewModel.openSelectedClipboardImagePreview())
        XCTAssertEqual(viewModel.previewImageFilename, "original.png")

        viewModel.closeClipboardImagePreview()
        viewModel.selectedIndex = 1

        XCTAssertFalse(viewModel.openSelectedClipboardImagePreview())
        XCTAssertNil(viewModel.previewImageFilename)
    }

    func testClipboardImagePreviewStateClearsWhenLauncherCloses() {
        let viewModel = LauncherViewModel()
        viewModel.mode = .clipboard
        ClipboardManager.shared.selectTab(.history)
        viewModel.results = [
            SearchItem(
                title: "Image",
                subtitle: "Clipboard image",
                iconName: "photo",
                type: .clipboard,
                clipboardPreview: .image(
                    filename: "original.png",
                    thumbnailFilename: nil,
                    byteSize: 1,
                    ocrStatus: nil,
                    ocrTextPreview: nil
                ),
                action: {}
            )
        ]

        XCTAssertTrue(viewModel.openSelectedClipboardImagePreview())
        viewModel.onCloseLauncher()

        XCTAssertNil(viewModel.previewImageFilename)
    }

    func testClipboardImagePreviewFrameUsesScreenBoundsInsteadOfLauncherBounds() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)

        let frame = ClipboardImagePreviewPanelController.previewFrame(
            imageSize: NSSize(width: 4000, height: 3000),
            visibleFrame: visibleFrame
        )

        XCTAssertTrue(visibleFrame.contains(frame))
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.001)
        XCTAssertGreaterThan(frame.width, 600)
        XCTAssertGreaterThan(frame.height, 400)
    }

    func testClipboardPanelTabOrderPlacesImageHistoryAfterHistory() {
        XCTAssertEqual(ClipboardPanelTab.allCases, [.history, .imageHistory, .favorites, .snippets])
    }

    func testClipboardImageFilterRecognizesOnlyImageAndImg() {
        let viewModel = LauncherViewModel()
        viewModel.mode = .clipboard

        for query in ["image", "img", " IMAGE ", " Img "] {
            viewModel.query = query
            XCTAssertTrue(viewModel.isClipboardImageFilterActive, "Expected \(query) to activate image filter")
        }

        for query in ["", "images", "photo", "图片", "other"] {
            viewModel.query = query
            XCTAssertFalse(viewModel.isClipboardImageFilterActive, "Expected \(query) not to activate image filter")
        }
    }

    func testClipboardImageFilterIsInactiveOutsideClipboardMode() {
        let viewModel = LauncherViewModel()
        viewModel.mode = .launcher
        viewModel.query = "img"

        XCTAssertFalse(viewModel.isClipboardImageFilterActive)
    }

    func testSelectingImageHistoryTabWritesImgQuery() {
        let viewModel = LauncherViewModel()
        viewModel.mode = .clipboard
        viewModel.query = "image"
        defer { ClipboardManager.shared.selectTab(.history) }

        viewModel.selectClipboardTab(.imageHistory)

        XCTAssertEqual(viewModel.query, "img")
        XCTAssertTrue(viewModel.isClipboardImageFilterActive)
        XCTAssertEqual(ClipboardManager.shared.activeTab, .imageHistory)
    }

    func testLeavingImageHistoryTabClearsImageFilterQuery() {
        let viewModel = LauncherViewModel()
        viewModel.mode = .clipboard
        defer { ClipboardManager.shared.selectTab(.history) }
        viewModel.selectClipboardTab(.imageHistory)

        viewModel.selectClipboardTab(.favorites)

        XCTAssertEqual(viewModel.query, "")
        XCTAssertFalse(viewModel.isClipboardImageFilterActive)
        XCTAssertEqual(ClipboardManager.shared.activeTab, .favorites)
    }

    func testSelectingClipboardTabOutsideClipboardModeDoesNothing() {
        let viewModel = LauncherViewModel()
        viewModel.mode = .launcher
        viewModel.query = "existing"
        ClipboardManager.shared.selectTab(.history)

        viewModel.selectClipboardTab(.imageHistory)

        XCTAssertEqual(viewModel.query, "existing")
        XCTAssertEqual(ClipboardManager.shared.activeTab, .history)
    }

    func testClipboardTabShortcutsOnlyHandleClipboardMode() {
        let viewModel = LauncherViewModel()

        viewModel.mode = .launcher
        XCTAssertFalse(viewModel.selectNextClipboardTab())
        XCTAssertFalse(viewModel.selectPreviousClipboardTab())

        viewModel.mode = .clipboard
        XCTAssertTrue(viewModel.selectNextClipboardTab())
        XCTAssertTrue(viewModel.selectPreviousClipboardTab())
    }

    func testRepeatedLauncherFocusPreservesActiveEditorSelection() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        window.contentView = textField

        LauncherSearchFieldFocus.focus(textField)
        guard let editor = textField.currentEditor() else {
            return XCTFail("Expected the launcher search field to enter editing mode")
        }
        textField.stringValue = "c"
        editor.selectedRange = NSRange(location: 1, length: 0)

        LauncherSearchFieldFocus.focus(textField)

        XCTAssertEqual(editor.selectedRange, NSRange(location: 1, length: 0))
    }

    func testSearchFieldTextUpdateMovesCaretToEndWithoutSelectingText() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        window.contentView = textField
        LauncherSearchFieldFocus.focus(textField)

        guard let editor = textField.currentEditor() else {
            return XCTFail("Expected the launcher search field to enter editing mode")
        }
        editor.selectedRange = NSRange(location: 0, length: 0)

        LauncherSearchFieldTextSync.update(textField, text: "img")

        XCTAssertEqual(textField.stringValue, "img")
        XCTAssertEqual(editor.selectedRange, NSRange(location: 3, length: 0))
    }

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

    func testCommandReturnInClipboardModeDoesNotPasteSelection() {
        let viewModel = LauncherViewModel()
        var didPaste = false

        viewModel.mode = .clipboard
        viewModel.results = [
            SearchItem(
                title: "Clipboard item",
                subtitle: "Text",
                iconName: "doc.text",
                type: .clipboard,
                clipboardAction: ClipboardActionData(id: UUID(), isFavorite: false, isPinned: false),
                action: { didPaste = true }
            )
        ]

        viewModel.executeSelection(revealInFinder: true)

        XCTAssertFalse(didPaste)
    }

    func testCommandReturnInClipboardSnippetTabOpensSnippetsSettings() {
        let viewModel = LauncherViewModel()
        var didRun = false
        let openedSettings = expectation(forNotification: NSNotification.Name("OpenSnippetsSettings"), object: nil)

        viewModel.mode = .clipboard
        ClipboardManager.shared.selectTab(.snippets)
        defer { ClipboardManager.shared.selectTab(.history) }
        viewModel.results = [
            SearchItem(
                title: "Snippet item",
                subtitle: "Text",
                iconName: "text.quote",
                type: .snippet,
                snippetPreview: SnippetPreviewData(content: "hello"),
                action: { didRun = true }
            )
        ]

        viewModel.executeSelection(revealInFinder: true)

        wait(for: [openedSettings], timeout: 1)
        XCTAssertFalse(didRun)
    }
}
