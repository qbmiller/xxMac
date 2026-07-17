import AppKit
import OSLog

final class FilePathPasteManager {
    static let shared = FilePathPasteManager()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "FilePathPaste")
    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    private init() {}

    func pasteFinderPaths() {
        let pasteboard = NSPasteboard.general
        guard let urls = readFileURLs(from: pasteboard), !urls.isEmpty else {
            Self.logger.notice("no file URLs on pasteboard")
            return
        }

        let pathText = Self.pathText(for: urls)
        ClipboardManager.shared.recordText(pathText)
        typeTextAfterModifierRelease(pathText)
    }

    static func pathText(for urls: [URL]) -> String {
        urls
            .map { shellEscapedPath($0.path) }
            .joined(separator: " ")
    }

    static func nameText(for urls: [URL]) -> String {
        urls
            .map { shellEscapedPath($0.lastPathComponent) }
            .joined(separator: " ")
    }

    private func readFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls
        }

        let itemURLs = pasteboard.pasteboardItems?
            .compactMap(fileURL(from:))
        if let itemURLs, !itemURLs.isEmpty {
            return itemURLs
        }

        if let fileNames = pasteboard.propertyList(forType: Self.legacyFilenamesType) as? [String],
           !fileNames.isEmpty {
            return fileNames.map { URL(fileURLWithPath: $0) }
        }

        if let fileName = pasteboard.propertyList(forType: Self.legacyFilenamesType) as? String {
            return [URL(fileURLWithPath: fileName)]
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL {
            return [url]
        }

        return nil
    }

    private func fileURL(from item: NSPasteboardItem) -> URL? {
        for type in [NSPasteboard.PasteboardType.fileURL, NSPasteboard.PasteboardType("public.file-url")] {
            guard let string = item.string(forType: type) else { continue }
            if let url = URL(string: string), url.isFileURL {
                return url
            }
            return URL(fileURLWithPath: string)
        }
        return nil
    }

    private static func shellEscapedPath(_ path: String) -> String {
        if path.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "'\"\\$`!*?[]{}()&;|<>"))) == nil {
            return path
        }

        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func typeTextAfterModifierRelease(_ text: String, attemptsRemaining: Int = 20) {
        let activeModifiers = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        guard activeModifiers.isEmpty || attemptsRemaining <= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                self.typeTextAfterModifierRelease(text, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        typeText(text)
    }

    private func typeText(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for scalar in text.unicodeScalars {
            var units = Array(String(scalar).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            units.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
