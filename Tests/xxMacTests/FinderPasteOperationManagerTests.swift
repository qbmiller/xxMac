import AppKit
import XCTest
@testable import xxMac

final class FinderPasteOperationManagerTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_787_623_456.789)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testFileURLWinsWhenPasteboardItemAlsoContainsImageAndText() {
        let pasteboard = makePasteboard()
        let item = NSPasteboardItem()
        item.setString(URL(fileURLWithPath: "/tmp/copied.png").absoluteString, forType: .fileURL)
        item.setData(Data([1, 2, 3]), forType: .png)
        item.setString("ignored", forType: .string)
        pasteboard.writeObjects([item])

        XCTAssertEqual(
            SystemFinderPasteboardReader(pasteboard: pasteboard).readPayload(),
            .fileURLs([URL(fileURLWithPath: "/tmp/copied.png")])
        )
    }

    func testReadsRawImageData() {
        let pasteboard = makePasteboard()
        pasteboard.setData(Data([4, 5, 6]), forType: .png)

        XCTAssertEqual(
            SystemFinderPasteboardReader(pasteboard: pasteboard).readPayload(),
            .image(Data([4, 5, 6]))
        )
    }

    func testReadsPlainText() {
        let pasteboard = makePasteboard()
        pasteboard.setString("large: config", forType: .string)

        XCTAssertEqual(
            SystemFinderPasteboardReader(pasteboard: pasteboard).readPayload(),
            .text("large: config")
        )
    }

    func testEmptyPasteboardIsUnsupported() {
        let pasteboard = makePasteboard()

        XCTAssertEqual(
            SystemFinderPasteboardReader(pasteboard: pasteboard).readPayload(),
            .unsupported
        )
    }

    func testFinderDirectoryResolverUsesAppleEventFrontWindowTarget() {
        let resolver = FinderAppleEventDirectoryResolver(
            directoryQuery: StubFinderTargetDirectoryQuery(path: "/Users/miller/Pictures/images"),
            frontmostBundleIdentifier: { "com.apple.finder" },
            isDirectory: { $0.path == "/Users/miller/Pictures/images" }
        )

        XCTAssertEqual(
            resolver.currentDirectory(),
            URL(fileURLWithPath: "/Users/miller/Pictures/images", isDirectory: true)
        )
    }

    func testFinderDirectoryResolverDoesNotQueryOutsideFinder() {
        let query = RecordingFinderTargetDirectoryQuery(path: "/Users/miller/Pictures/images")
        let resolver = FinderAppleEventDirectoryResolver(
            directoryQuery: query,
            frontmostBundleIdentifier: { "com.apple.TextEdit" },
            isDirectory: { _ in true }
        )

        XCTAssertNil(resolver.currentDirectory())
        XCTAssertEqual(query.queryCount, 0)
    }

    func testSuccessfulImageWriteAdvancesOnlyImageCounter() {
        let writer = RecordingFinderPasteWriter()
        let feedback = RecordingFinderPasteFeedback()
        let saved = expectation(description: "image saved")
        feedback.onSuccess = { _ in saved.fulfill() }
        let manager = makeManager(
            payload: .image(Data([1, 2, 3])),
            settings: .init(imageEnabled: true),
            writer: writer,
            feedback: feedback
        )

        manager.perform()
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(writer.lastURL?.path, "/tmp/finder-target/20260825-001.png")
        XCTAssertEqual(writer.lastData, Data([137, 80, 78, 71]))
        XCTAssertEqual(manager.imageNextNumber, 2)
        XCTAssertEqual(manager.textNextNumber, 1)
    }

    func testImageConversionEnsuresFinderAutomationPermission() {
        var openSettingsIfNeededValues: [Bool] = []
        let saved = expectation(description: "image saved")
        let feedback = RecordingFinderPasteFeedback()
        feedback.onSuccess = { _ in saved.fulfill() }
        let manager = makeManager(
            payload: .image(Data([1, 2, 3])),
            settings: .init(imageEnabled: true),
            feedback: feedback,
            ensureFinderAutomationPermission: { openSettingsIfNeeded in
                openSettingsIfNeededValues.append(openSettingsIfNeeded)
                return true
            }
        )

        manager.perform()
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(openSettingsIfNeededValues, [true])
    }

    func testDeniedFinderAutomationPermissionPreventsImageWrite() {
        let writer = RecordingFinderPasteWriter()
        let feedback = RecordingFinderPasteFeedback()
        let manager = makeManager(
            payload: .image(Data([1, 2, 3])),
            settings: .init(imageEnabled: true),
            writer: writer,
            feedback: feedback,
            ensureFinderAutomationPermission: { _ in false }
        )

        manager.perform()

        XCTAssertNil(writer.lastURL)
        XCTAssertEqual(feedback.failureCount, 1)
    }

    func testSuccessfulTextWriteUsesDetectedExtensionAndPreservesBytes() {
        let text = #"{"name":"xxMac","enabled":true}"#
        let writer = RecordingFinderPasteWriter()
        let feedback = RecordingFinderPasteFeedback()
        let saved = expectation(description: "text saved")
        feedback.onSuccess = { _ in saved.fulfill() }
        let manager = makeManager(
            payload: .text(text),
            settings: .init(textEnabled: true),
            writer: writer,
            feedback: feedback
        )

        manager.perform()
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(writer.lastURL?.path, "/tmp/finder-target/20260825-001.json")
        XCTAssertEqual(writer.lastData, Data(text.utf8))
        XCTAssertEqual(manager.imageNextNumber, 1)
        XCTAssertEqual(manager.textNextNumber, 2)
    }

    func testWriteFailureDoesNotAdvanceCounter() {
        let writer = RecordingFinderPasteWriter(error: TestError.writeFailed)
        let feedback = RecordingFinderPasteFeedback()
        let failed = expectation(description: "failure shown")
        feedback.onFailure = { _ in failed.fulfill() }
        let manager = makeManager(
            payload: .text("plain text"),
            settings: .init(textEnabled: true),
            writer: writer,
            feedback: feedback
        )

        manager.perform()
        wait(for: [failed], timeout: 2)

        XCTAssertEqual(manager.textNextNumber, 1)
    }

    func testMissingFinderDirectoryDoesNotWriteOrAdvance() {
        let writer = RecordingFinderPasteWriter()
        let feedback = RecordingFinderPasteFeedback()
        let manager = makeManager(
            payload: .text("plain text"),
            settings: .init(textEnabled: true),
            directory: nil,
            writer: writer,
            feedback: feedback
        )

        manager.perform()

        XCTAssertNil(writer.lastURL)
        XCTAssertEqual(manager.textNextNumber, 1)
        XCTAssertEqual(feedback.failureCount, 1)
    }

    func testFilePayloadPastesPathsOutsideFinder() {
        let url = URL(fileURLWithPath: "/tmp/copied file.txt")
        var pastedURLs: [URL] = []
        var openSettingsIfNeededValues: [Bool] = []
        let manager = makeManager(
            payload: .fileURLs([url]),
            settings: .init(),
            isFinderFrontmost: false,
            pathPaster: { pastedURLs = $0 },
            ensureFinderAutomationPermission: { openSettingsIfNeeded in
                openSettingsIfNeededValues.append(openSettingsIfNeeded)
                return true
            }
        )

        manager.perform()

        XCTAssertEqual(pastedURLs, [url])
        XCTAssertEqual(openSettingsIfNeededValues, [])
    }

    func testDisabledConversionDoesNothing() {
        let writer = RecordingFinderPasteWriter()
        let feedback = RecordingFinderPasteFeedback()
        let manager = makeManager(
            payload: .image(Data([1, 2, 3])),
            settings: .init(imageEnabled: false),
            writer: writer,
            feedback: feedback
        )

        manager.perform()

        XCTAssertNil(writer.lastURL)
        XCTAssertEqual(feedback.successCount, 0)
        XCTAssertEqual(feedback.failureCount, 0)
    }

    func testPersistedSettingsReloadWithIndependentCounters() {
        let store = MemoryFinderPasteSettingsStore(settings: .init(
            imageEnabled: true,
            textEnabled: false,
            imageCounter: .init(dateKey: "20260825", nextValue: 7),
            textCounter: .init(dateKey: "20260825", nextValue: 3)
        ))

        let manager = makeManager(settingsStore: store)

        XCTAssertTrue(manager.settings.imageEnabled)
        XCTAssertFalse(manager.settings.textEnabled)
        XCTAssertEqual(manager.imageNextNumber, 7)
        XCTAssertEqual(manager.textNextNumber, 3)
    }

    func testMissingPersistedSettingsUseDisabledDefaults() {
        let manager = makeManager(settingsStore: MemoryFinderPasteSettingsStore(settings: nil))

        XCTAssertFalse(manager.settings.imageEnabled)
        XCTAssertFalse(manager.settings.textEnabled)
        XCTAssertEqual(manager.imageNextNumber, 1)
        XCTAssertEqual(manager.textNextNumber, 1)
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("FinderPasteOperationManagerTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeManager(
        payload: FinderPastePayload = .unsupported,
        settings: FinderPasteOperationSettings = .init(),
        settingsStore: MemoryFinderPasteSettingsStore? = nil,
        isFinderFrontmost: Bool = true,
        directory: URL? = URL(fileURLWithPath: "/tmp/finder-target", isDirectory: true),
        writer: RecordingFinderPasteWriter = RecordingFinderPasteWriter(),
        feedback: RecordingFinderPasteFeedback = RecordingFinderPasteFeedback(),
        pathPaster: @escaping ([URL]) -> Void = { _ in },
        ensureFinderAutomationPermission: @escaping (Bool) -> Bool = { _ in true }
    ) -> FinderPasteOperationManager {
        FinderPasteOperationManager(
            pasteboardReader: StubFinderPasteboardReader(payload: payload),
            directoryResolver: StubFinderDirectoryResolver(directory: directory),
            fileWriter: writer,
            imageEncoder: StubFinderPasteImageEncoder(),
            settingsStore: settingsStore ?? MemoryFinderPasteSettingsStore(settings: settings),
            frontmostBundleIdentifier: { isFinderFrontmost ? "com.apple.finder" : "com.apple.TextEdit" },
            now: { self.fixedDate },
            calendar: calendar,
            pathPaster: pathPaster,
            feedback: feedback,
            ensureFinderAutomationPermission: ensureFinderAutomationPermission,
            operationQueue: DispatchQueue(label: "FinderPasteOperationManagerTests")
        )
    }
}

private struct StubFinderPasteboardReader: FinderPasteboardReading {
    let payload: FinderPastePayload
    func readPayload() -> FinderPastePayload { payload }
}

private struct StubFinderDirectoryResolver: FinderDirectoryResolving {
    let directory: URL?
    func currentDirectory() -> URL? { directory }
}

private struct StubFinderTargetDirectoryQuery: FinderTargetDirectoryQuerying {
    let path: String?
    func currentDirectoryPath() -> String? { path }
}

private final class RecordingFinderTargetDirectoryQuery: FinderTargetDirectoryQuerying {
    let path: String?
    private(set) var queryCount = 0

    init(path: String?) {
        self.path = path
    }

    func currentDirectoryPath() -> String? {
        queryCount += 1
        return path
    }
}

private final class RecordingFinderPasteWriter: FinderPasteFileWriting {
    private let error: Error?
    private(set) var lastData: Data?
    private(set) var lastURL: URL?

    init(error: Error? = nil) {
        self.error = error
    }

    func write(_ data: Data, to url: URL) throws {
        if let error { throw error }
        lastData = data
        lastURL = url
    }
}

private struct StubFinderPasteImageEncoder: FinderPasteImageEncoding {
    func pngData(from data: Data) -> Data? { Data([137, 80, 78, 71]) }
}

private final class MemoryFinderPasteSettingsStore: FinderPasteSettingsStoring {
    private(set) var settings: FinderPasteOperationSettings?

    init(settings: FinderPasteOperationSettings?) {
        self.settings = settings
    }

    func load() -> FinderPasteOperationSettings? { settings }
    func save(_ settings: FinderPasteOperationSettings) { self.settings = settings }
}

private final class RecordingFinderPasteFeedback: FinderPasteFeedbackPresenting {
    private(set) var successCount = 0
    private(set) var failureCount = 0
    var onSuccess: ((URL) -> Void)?
    var onFailure: ((String) -> Void)?

    func showSuccess(fileURL: URL) {
        successCount += 1
        onSuccess?(fileURL)
    }

    func showFailure(message: String) {
        failureCount += 1
        onFailure?(message)
    }
}

private enum TestError: Error {
    case writeFailed
}
