import AppKit
import Combine
import HotKey
import ApplicationServices

// MARK: - Clipboard Manager

struct ClipboardSettings: Codable {
    var clipboardMonitoringEnabled: Bool = false
    var manageImages: Bool = true
    var imageCacheDurationDays: Int = 7
    var textCacheDurationDays: Int = 30
    var maxImageSizeMB: Int = 100
    var hotKey: HotKeyConfiguration?

    enum CodingKeys: String, CodingKey {
        case clipboardMonitoringEnabled
        case manageImages
        case imageCacheDurationDays
        case textCacheDurationDays
        case maxImageSizeMB
        case hotKey
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clipboardMonitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardMonitoringEnabled) ?? false
        manageImages = try container.decodeIfPresent(Bool.self, forKey: .manageImages) ?? true
        imageCacheDurationDays = try container.decodeIfPresent(Int.self, forKey: .imageCacheDurationDays) ?? 7
        textCacheDurationDays = try container.decodeIfPresent(Int.self, forKey: .textCacheDurationDays) ?? 30
        maxImageSizeMB = try container.decodeIfPresent(Int.self, forKey: .maxImageSizeMB) ?? 100
        hotKey = try container.decodeIfPresent(HotKeyConfiguration.self, forKey: .hotKey)
    }
}

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var history: [SearchItem] = []
    @Published var settings: ClipboardSettings = ClipboardSettings() {
        didSet {
            saveSettings()
            updateHotKey()
            updateMonitoringState()
        }
    }
    
    private var clipboardItems: [ClipboardItem] = []
    private var changeCount: Int
    private var timer: Timer?
    private var hotKey: HotKey?
    private var previousFrontmostApp: NSRunningApplication?
    
    private let storage = ClipboardStorageManager.shared
    private var cancellables = Set<AnyCancellable>()

    private func logClipboardFlow(_ stage: String) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier ?? "nil"
        let pid = frontmost?.processIdentifier ?? 0
        let previous = previousFrontmostApp?.bundleIdentifier ?? "nil"
        let previousPID = previousFrontmostApp?.processIdentifier ?? 0
        NSLog("[ClipboardFlow][%@] frontmost=%@#%d appActive=%@ appHidden=%@",
              "\(stage) previous=\(previous)#\(previousPID)",
              bundleID,
              pid,
              NSApp.isActive.description,
              NSApp.isHidden.description)
    }
    
    private init() {
        self.changeCount = NSPasteboard.general.changeCount
        
        loadSettings()
        
        // Initial load
        refreshHistory()
        
        updateMonitoringState()
        updateHotKey()
    }
    
    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMonitoringState() {
        if settings.clipboardMonitoringEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    private func checkPasteboard() {
        guard settings.clipboardMonitoringEnabled else { return }

        let currentCount = NSPasteboard.general.changeCount
        if currentCount != changeCount {
            changeCount = currentCount
            processPasteboardContent()
        }
    }
    
    private func processPasteboardContent() {
        let pasteboard = NSPasteboard.general
        
        // 1. Check for text
        if let str = pasteboard.string(forType: .string), !str.trimmingCharacters(in: .whitespaces).isEmpty {
            addItem(type: .text, content: str, size: str.utf8.count)
            return
        }
        
        // 2. Check for images if enabled
        guard settings.manageImages else { return }
        
        var imageToSave: NSImage?
        
        // Check for file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
             let ext = firstURL.pathExtension.lowercased()
             let imageExtensions = ["png", "jpg", "jpeg", "tiff", "gif", "bmp", "heic", "webp"]
             if imageExtensions.contains(ext), let image = NSImage(contentsOf: firstURL) {
                 imageToSave = image
             }
        }
        
        // Check for direct image data
        if imageToSave == nil, let image = NSImage(pasteboard: pasteboard) {
            imageToSave = image
        }
        
        if let image = imageToSave,
           let tiffData = image.tiffRepresentation {
            
            if let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                
                let filename = "\(UUID().uuidString).png"
                let fileURL = storage.getImagePath(filename: filename)
                
                do {
                    try pngData.write(to: fileURL)
                    addItem(type: .image, content: filename, size: pngData.count)
                } catch {
                    print("Failed to save clipboard image: \(error)")
                }
            }
        }
    }
    
    private func addItem(type: ClipboardContentType, content: String, size: Int) {
        storage.saveItem(type: type, content: content, size: size)
        refreshHistory()
    }
    
    func refreshHistory() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let items = self?.storage.getAllItems() ?? []
            DispatchQueue.main.async {
                self?.clipboardItems = items
                self?.updatePublishedHistory()
            }
        }
    }

    func searchClipboard(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let allItems = self.storage.getAllItems()
            let items: [ClipboardItem]

            if trimmedQuery.isEmpty {
                items = allItems
            } else {
                let normalizedQuery = trimmedQuery.lowercased()
                items = allItems.filter { $0.content.lowercased().contains(normalizedQuery) }
            }

            DispatchQueue.main.async {
                self.clipboardItems = items
                self.updatePublishedHistory()
            }
        }
    }
    
    private func updatePublishedHistory() {
        history = clipboardItems.map { item in
            switch item.type {
            case .text:
                return SearchItem(
                    title: item.content.prefix(100).replacingOccurrences(of: "\n", with: " "),
                    subtitle: L10n.f("clipboard.item.text_format", formatDate(item.timestamp)),
                    iconName: "doc.text",
                    type: .clipboard,
                    clipboardPreview: .text(item.content),
                    action: { [weak self] in self?.paste(item) }
                )
            case .image:
                return SearchItem(
                    title: L10n.t("clipboard.item.image_title"),
                    subtitle: L10n.f("clipboard.item.image_subtitle_format", formatSize(item.size), formatDate(item.timestamp)),
                    iconName: "photo",
                    type: .clipboard,
                    clipboardPreview: .image(filename: item.content, byteSize: item.size),
                    action: { [weak self] in self?.paste(item) }
                )
            }
        }
    }
    
    private func paste(_ item: ClipboardItem) {
        logClipboardFlow("paste.begin type=\(item.type.rawValue)")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            pasteboard.setString(item.content, forType: .string)
        case .image:
            let url = storage.getImagePath(filename: item.content)
            if let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            }
        }
        
        logClipboardFlow("paste.afterPasteboardWrite")
        pasteToActiveApp()
    }
    
    private func pasteToActiveApp() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.logClipboardFlow("pasteToActiveApp.begin")
            NotificationCenter.default.post(name: NSNotification.Name("CloseLauncherPanelOnly"), object: nil)
            self.restoreFocusToCapturedApp()
            self.sendPasteCommandWhenReady(retries: 8)
        }
    }

    private func sendPasteCommandWhenReady(retries: Int) {
        let targetPID = previousFrontmostApp?.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if targetPID == nil || targetPID == frontmostPID || retries <= 0 {
            logClipboardFlow("pasteToActiveApp.beforeSendCmdV retries=\(retries)")
            sendCommandV()
            logClipboardFlow("pasteToActiveApp.afterSendCmdV retries=\(retries)")
            previousFrontmostApp = nil
            return
        }

        restoreFocusToCapturedApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.sendPasteCommandWhenReady(retries: retries - 1)
        }
    }

    private func restoreFocusToCapturedApp() {
        guard let app = previousFrontmostApp else {
            logClipboardFlow("restoreFocus.noPrevious")
            return
        }

        if app.isHidden {
            app.unhide()
        }

        let activated = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        let reopened = sendReopenAndActivateAppleScript(to: app)
        logClipboardFlow("restoreFocus.activated=\(activated) reopened=\(reopened)")
    }

    private func sendReopenAndActivateAppleScript(to app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        let safeBundleIdentifier = bundleIdentifier.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application id "\(safeBundleIdentifier)"
            reopen
            activate
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let commandKeyCode: CGKeyCode = 55 // Command
        let vKeyCode: CGKeyCode = 9 // 'v'

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        vUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false)

        [cmdDown, vDown, vUp, cmdUp].forEach { event in
            event?.post(tap: .cghidEventTap)
        }
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "ClipboardSettings")
        }
    }
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "ClipboardSettings"),
           let savedSettings = try? JSONDecoder().decode(ClipboardSettings.self, from: data) {
            settings = savedSettings
        }
    }
    
    private func updateHotKey() {
        hotKey = nil
        if let config = settings.hotKey {
            hotKey = HotKey(key: config.key, modifiers: config.modifiers)
            hotKey?.keyDownHandler = { [weak self] in
                self?.toggleClipboardHistory()
            }
        }
    }
    
    private func toggleClipboardHistory() {
        DispatchQueue.main.async {
            self.logClipboardFlow("toggleClipboardHistory.begin")
            if let app = NSWorkspace.shared.frontmostApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self.previousFrontmostApp = app
            }
            self.logClipboardFlow("toggleClipboardHistory.afterCapture")
            NotificationCenter.default.post(name: NSNotification.Name("ShowClipboardHistory"), object: nil)
        }
    }
    
    func clearPlainTextHistory() {
        storage.clearHistory(type: .text)
        refreshHistory()
    }

    func clearImageHistory() {
        storage.clearHistory(type: .image)
        refreshHistory()
    }
    
    // Helpers
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
