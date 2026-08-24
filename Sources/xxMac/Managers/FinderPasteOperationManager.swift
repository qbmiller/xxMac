import AppKit
import Foundation
import OSLog

protocol FinderPasteboardReading {
    func readPayload() -> FinderPastePayload
}

struct SystemFinderPasteboardReader: FinderPasteboardReading {
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("com.microsoft.bmp")
    ]

    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func readPayload() -> FinderPastePayload {
        if let urls = FilePathPasteManager.fileURLs(from: pasteboard), !urls.isEmpty {
            return .fileURLs(urls)
        }

        let availableTypes = pasteboard.types ?? []
        for type in Self.imageTypes where availableTypes.contains(type) {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return .image(data)
            }
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }

        return .unsupported
    }
}

protocol FinderDirectoryResolving {
    func currentDirectory() -> URL?
}

protocol FinderTargetDirectoryQuerying {
    func currentDirectoryPath() -> String?
}

protocol FinderPasteFileWriting {
    func write(_ data: Data, to url: URL) throws
}

protocol FinderPasteImageEncoding {
    func pngData(from data: Data) -> Data?
}

protocol FinderPasteSettingsStoring {
    func load() -> FinderPasteOperationSettings?
    func save(_ settings: FinderPasteOperationSettings)
}

protocol FinderPasteFeedbackPresenting {
    func showSuccess(fileURL: URL)
    func showFailure(message: String)
}

struct FinderAppleEventDirectoryResolver: FinderDirectoryResolving {
    private let directoryQuery: FinderTargetDirectoryQuerying
    private let frontmostBundleIdentifier: () -> String?
    private let isDirectory: (URL) -> Bool

    init(
        directoryQuery: FinderTargetDirectoryQuerying = FinderAppleScriptTargetDirectoryQuery(),
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        isDirectory: @escaping (URL) -> Bool = { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    ) {
        self.directoryQuery = directoryQuery
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.isDirectory = isDirectory
    }

    func currentDirectory() -> URL? {
        guard frontmostBundleIdentifier() == "com.apple.finder",
              let path = directoryQuery.currentDirectoryPath(),
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard isDirectory(url) else { return nil }
        return url
    }
}

struct FinderAppleScriptTargetDirectoryQuery: FinderTargetDirectoryQuerying {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xxMac",
        category: "FinderPasteOperation"
    )

    func currentDirectoryPath() -> String? {
        let source = #"""
        tell application id "com.apple.finder"
            if (count of Finder windows) is 0 then
                set targetFolder to desktop as alias
            else
                set targetFolder to target of front Finder window as alias
            end if
            return POSIX path of targetFolder
        end tell
        """#
        guard let script = NSAppleScript(source: source) else { return nil }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            Self.logger.error("Finder target query failed: \(String(describing: errorInfo), privacy: .public)")
            return nil
        }
        return result.stringValue
    }
}

struct SystemFinderPasteFileWriter: FinderPasteFileWriting {
    func write(_ data: Data, to url: URL) throws {
        guard FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) else {
            throw FinderPasteOperationError.directoryNotWritable
        }
        try data.write(to: url, options: .withoutOverwriting)
    }
}

struct SystemFinderPasteImageEncoder: FinderPasteImageEncoding {
    func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

struct PreferencesFinderPasteSettingsStore: FinderPasteSettingsStoring {
    private static let key = "FinderPasteOperationSettings"
    private let preferences: PreferencesStore

    init(preferences: PreferencesStore = .shared) {
        self.preferences = preferences
    }

    func load() -> FinderPasteOperationSettings? {
        guard let data = preferences.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(FinderPasteOperationSettings.self, from: data)
    }

    func save(_ settings: FinderPasteOperationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        preferences.set(data, forKey: Self.key)
    }
}

final class FinderPasteOperationManager: ObservableObject {
    static let shared = FinderPasteOperationManager()

    @Published private(set) var settings: FinderPasteOperationSettings

    private let pasteboardReader: FinderPasteboardReading
    private let directoryResolver: FinderDirectoryResolving
    private let fileWriter: FinderPasteFileWriting
    private let imageEncoder: FinderPasteImageEncoding
    private let settingsStore: FinderPasteSettingsStoring
    private let frontmostBundleIdentifier: () -> String?
    private let now: () -> Date
    private let calendar: Calendar
    private let pathPaster: ([URL]) -> Void
    private let feedback: FinderPasteFeedbackPresenting
    private let ensureFinderAutomationPermission: (Bool) -> Bool
    private let operationQueue: DispatchQueue

    convenience init() {
        self.init(
            pasteboardReader: SystemFinderPasteboardReader(),
            directoryResolver: FinderAppleEventDirectoryResolver(),
            fileWriter: SystemFinderPasteFileWriter(),
            imageEncoder: SystemFinderPasteImageEncoder(),
            settingsStore: PreferencesFinderPasteSettingsStore(),
            frontmostBundleIdentifier: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
            now: Date.init,
            calendar: .current,
            pathPaster: { FilePathPasteManager.shared.pasteFinderPaths($0) },
            feedback: FinderPasteFeedbackPresenter(),
            ensureFinderAutomationPermission: { openSettingsIfNeeded in
                FinderAutomationPermissionManager.shared.ensurePermission(
                    openSettingsIfNeeded: openSettingsIfNeeded
                )
            },
            operationQueue: DispatchQueue(label: "com.xxmac.finder-paste-operation", qos: .userInitiated)
        )
    }

    init(
        pasteboardReader: FinderPasteboardReading,
        directoryResolver: FinderDirectoryResolving,
        fileWriter: FinderPasteFileWriting,
        imageEncoder: FinderPasteImageEncoding,
        settingsStore: FinderPasteSettingsStoring,
        frontmostBundleIdentifier: @escaping () -> String?,
        now: @escaping () -> Date,
        calendar: Calendar,
        pathPaster: @escaping ([URL]) -> Void,
        feedback: FinderPasteFeedbackPresenting,
        ensureFinderAutomationPermission: @escaping (Bool) -> Bool,
        operationQueue: DispatchQueue
    ) {
        self.pasteboardReader = pasteboardReader
        self.directoryResolver = directoryResolver
        self.fileWriter = fileWriter
        self.imageEncoder = imageEncoder
        self.settingsStore = settingsStore
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.now = now
        self.calendar = calendar
        self.pathPaster = pathPaster
        self.feedback = feedback
        self.ensureFinderAutomationPermission = ensureFinderAutomationPermission
        self.operationQueue = operationQueue
        settings = settingsStore.load() ?? FinderPasteOperationSettings()
    }

    var imageNextNumber: Int {
        settings.imageCounter.nextNumber(on: now(), calendar: calendar)
    }

    var textNextNumber: Int {
        settings.textCounter.nextNumber(on: now(), calendar: calendar)
    }

    func perform() {
        let route = FinderPasteRoutingPolicy.route(
            payload: pasteboardReader.readPayload(),
            isFinderFrontmost: frontmostBundleIdentifier() == "com.apple.finder",
            settings: settings
        )

        switch route {
        case .pastePaths(let urls):
            pathPaster(urls)
        case .saveImage(let data):
            save(kind: .image, fileExtension: "png") { [imageEncoder] in
                imageEncoder.pngData(from: data)
            }
        case .saveText(let text):
            save(kind: .text, fileExtension: ClipboardTextFormatDetector.fileExtension(for: text)) {
                Data(text.utf8)
            }
        case .none:
            break
        }
    }

    func setImageEnabled(_ enabled: Bool) {
        settings.imageEnabled = enabled
        persistSettings()
    }

    func setTextEnabled(_ enabled: Bool) {
        settings.textEnabled = enabled
        persistSettings()
    }

    func resetImageCounter() {
        settings.imageCounter.reset(on: now(), calendar: calendar)
        persistSettings()
    }

    func resetTextCounter() {
        settings.textCounter.reset(on: now(), calendar: calendar)
        persistSettings()
    }

    private func save(
        kind: SavedContentKind,
        fileExtension: String?,
        dataProvider: @escaping () -> Data?
    ) {
        guard ensureFinderAutomationPermission(true) else {
            feedback.showFailure(message: L10n.t("clipboard_paste.error.no_finder_directory"))
            return
        }
        guard let directory = directoryResolver.currentDirectory() else {
            feedback.showFailure(message: L10n.t("clipboard_paste.error.no_finder_directory"))
            return
        }

        operationQueue.async { [weak self] in
            guard let self else { return }
            guard let data = dataProvider() else {
                DispatchQueue.main.async {
                    self.feedback.showFailure(message: L10n.t("clipboard_paste.error.image_conversion"))
                }
                return
            }

            let context: (date: Date, number: Int) = DispatchQueue.main.sync {
                let date = self.now()
                let number = kind == .image
                    ? self.settings.imageCounter.nextNumber(on: date, calendar: self.calendar)
                    : self.settings.textCounter.nextNumber(on: date, calendar: self.calendar)
                return (date, number)
            }
            let destinationURL = FinderPasteFileNamer.destinationURL(
                directory: directory,
                date: context.date,
                number: context.number,
                fileExtension: fileExtension,
                calendar: self.calendar,
                fileExists: { FileManager.default.fileExists(atPath: $0.path) }
            )

            do {
                try self.fileWriter.write(data, to: destinationURL)
                DispatchQueue.main.sync {
                    switch kind {
                    case .image:
                        self.settings.imageCounter.recordSuccess(on: context.date, calendar: self.calendar)
                    case .text:
                        self.settings.textCounter.recordSuccess(on: context.date, calendar: self.calendar)
                    }
                    self.persistSettings()
                    self.feedback.showSuccess(fileURL: destinationURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.feedback.showFailure(message: error.localizedDescription)
                }
            }
        }
    }

    private func persistSettings() {
        settingsStore.save(settings)
    }

    private enum SavedContentKind {
        case image
        case text
    }
}

enum FinderPasteOperationError: LocalizedError {
    case directoryNotWritable

    var errorDescription: String? {
        switch self {
        case .directoryNotWritable:
            return L10n.t("clipboard_paste.error.directory_not_writable")
        }
    }
}

private final class FinderPasteFeedbackPresenter: FinderPasteFeedbackPresenting {
    private let banner = FinderPasteFeedbackBanner()

    func showSuccess(fileURL: URL) {
        banner.show(message: L10n.f("clipboard_paste.saved_format", fileURL.lastPathComponent))
    }

    func showFailure(message: String) {
        banner.show(message: L10n.f("clipboard_paste.failed_format", message))
    }
}

private final class FinderPasteFeedbackBanner {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideWorkItem: DispatchWorkItem?

    func show(message: String) {
        if Thread.isMainThread {
            showOnMain(message: message)
        } else {
            DispatchQueue.main.async { [weak self] in self?.showOnMain(message: message) }
        }
    }

    private func showOnMain(message: String) {
        ensurePanel()
        guard let panel, let label else { return }

        label.stringValue = message
        let width = min(max(label.intrinsicContentSize.width + 40, 300), 680)
        let labelSize = label.sizeThatFits(NSSize(width: width - 40, height: 120))
        let height = max(labelSize.height + 24, 48)
        panel.setContentSize(NSSize(width: width, height: height))
        label.frame = NSRect(x: 20, y: (height - labelSize.height) / 2, width: width - 40, height: labelSize.height)

        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.maxY - height - 36
            ))
        }
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8

        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.textColor = .labelColor
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        effectView.addSubview(label)
        panel.contentView = effectView

        self.panel = panel
        self.label = label
    }
}
