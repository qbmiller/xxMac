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
    var maxHistoryItems: Int = 1000
    var maxImageStorageSizeMB: Int = 500
    var thumbnailGenerationThresholdMB: Int = 5
    var hotKey: HotKeyConfiguration?

    enum CodingKeys: String, CodingKey {
        case clipboardMonitoringEnabled
        case manageImages
        case imageCacheDurationDays
        case textCacheDurationDays
        case maxImageSizeMB
        case maxHistoryItems
        case maxImageStorageSizeMB
        case thumbnailGenerationThresholdMB
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
        maxHistoryItems = try container.decodeIfPresent(Int.self, forKey: .maxHistoryItems) ?? 1000
        maxImageStorageSizeMB = try container.decodeIfPresent(Int.self, forKey: .maxImageStorageSizeMB) ?? 500
        thumbnailGenerationThresholdMB = try container.decodeIfPresent(Int.self, forKey: .thumbnailGenerationThresholdMB) ?? 5
        hotKey = try container.decodeIfPresent(HotKeyConfiguration.self, forKey: .hotKey)
    }
}

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var history: [SearchItem] = []
    @Published var settings: ClipboardSettings = ClipboardSettings() {
        didSet {
            saveSettings()
            updateStorageLimits()
            updateHotKey()
            updateMonitoringState()
        }
    }
    
    private var clipboardItems: [ClipboardListItem] = []
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
        
        updateStorageLimits()
        updateMonitoringState()
        updateHotKey()
    }

    private func updateStorageLimits() {
        storage.configureLimits(
            maxItemsCount: settings.maxHistoryItems,
            maxImageStorageSizeMB: settings.maxImageStorageSizeMB
        )
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
                    let dimensions = imageDimensions(from: bitmap, fallback: image)
                    let thumbnailFilename = saveThumbnailIfNeeded(
                        from: image,
                        originalFilename: filename,
                        byteSize: pngData.count
                    )
                    storage.saveImageItem(
                        content: filename,
                        size: pngData.count,
                        width: dimensions.width,
                        height: dimensions.height,
                        thumbnailFilename: thumbnailFilename
                    )
                    refreshHistory()
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
            let items = self?.storage.getListItems() ?? []
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
            let listItems: [ClipboardListItem]

            if trimmedQuery.isEmpty {
                listItems = self.storage.getListItems()
            } else {
                listItems = self.storage.searchListItems(query: trimmedQuery)
            }

            DispatchQueue.main.async {
                self.clipboardItems = listItems
                self.updatePublishedHistory()
            }
        }
    }
    
    private func updatePublishedHistory() {
        history = clipboardItems.map { item in
            switch item.type {
            case .text:
                return SearchItem(
                    id: "clipboard.\(item.id.uuidString)",
                    title: item.previewContent.prefix(100).replacingOccurrences(of: "\n", with: " "),
                    subtitle: L10n.f("clipboard.item.text_format", formatDate(item.timestamp)),
                    iconName: "doc.text",
                    type: .clipboard,
                    clipboardPreview: .text(
                        id: item.id,
                        preview: item.previewContent,
                        fullLength: item.fullContentLength
                    ),
                    action: { [weak self] in self?.pasteItem(id: item.id) }
                )
            case .image:
                return SearchItem(
                    id: "clipboard.\(item.id.uuidString)",
                    title: imageDisplayTitle(for: item),
                    subtitle: L10n.f("clipboard.item.image_subtitle_format", formatSize(item.size), formatDate(item.timestamp)),
                    iconName: "photo",
                    type: .clipboard,
                    clipboardPreview: .image(
                        filename: item.imageFilename ?? item.previewContent,
                        thumbnailFilename: item.thumbnailFilename,
                        byteSize: item.size
                    ),
                    action: { [weak self] in self?.pasteItem(id: item.id) }
                )
            }
        }
    }

    private func pasteItem(id: UUID) {
        guard let item = storage.getItem(id: id) else { return }
        paste(item)
    }
    
    private func paste(_ item: ClipboardItem) {
        logClipboardFlow("paste.begin type=\(item.type.rawValue)")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var didWritePasteboard = false
        
        switch item.type {
        case .text:
            didWritePasteboard = pasteboard.setString(item.content, forType: .string)
        case .image:
            let url = storage.getImagePath(filename: item.content)
            if let image = NSImage(contentsOf: url) {
                didWritePasteboard = pasteboard.writeObjects([image])
            }
        }

        if didWritePasteboard {
            storage.markItemUsed(item)
            changeCount = pasteboard.changeCount
            refreshHistory()
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
            PreferencesStore.shared.set(data, forKey: "ClipboardSettings")
        }
    }
    
    private func loadSettings() {
        if let data = PreferencesStore.shared.data(forKey: "ClipboardSettings"),
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

    private func imageDisplayTitle(for item: ClipboardItem) -> String {
        guard item.type == .image else { return item.content }

        if let width = item.imageWidth, let height = item.imageHeight {
            return "Image: \(width)x\(height) (\(formatSize(item.size)))"
        }

        return "Image: \(formatSize(item.size))"
    }

    private func imageDisplayTitle(for item: ClipboardListItem) -> String {
        guard item.type == .image else { return item.previewContent }

        if let width = item.imageWidth, let height = item.imageHeight {
            return "Image: \(width)x\(height) (\(formatSize(item.size)))"
        }

        return "Image: \(formatSize(item.size))"
    }

    private func imageDimensions(from bitmap: NSBitmapImageRep, fallback image: NSImage) -> (width: Int?, height: Int?) {
        if bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 {
            return (bitmap.pixelsWide, bitmap.pixelsHigh)
        }
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard width > 0, height > 0 else { return (nil, nil) }
        return (width, height)
    }

    private func saveThumbnailIfNeeded(from image: NSImage, originalFilename: String, byteSize: Int) -> String? {
        let thresholdBytes = max(1, settings.thumbnailGenerationThresholdMB) * 1024 * 1024
        guard byteSize >= thresholdBytes else { return nil }
        guard let thumbnail = resizedImage(image, maxPixelLength: 512),
              let tiffData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let baseName = (originalFilename as NSString).deletingPathExtension
        let thumbnailFilename = "\(baseName)-thumb.png"
        let thumbnailURL = storage.getThumbnailPath(filename: thumbnailFilename)
        do {
            try pngData.write(to: thumbnailURL)
            return thumbnailFilename
        } catch {
            print("Failed to save clipboard thumbnail: \(error)")
            return nil
        }
    }

    private func resizedImage(_ image: NSImage, maxPixelLength: CGFloat) -> NSImage? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = min(maxPixelLength / sourceSize.width, maxPixelLength / sourceSize.height, 1)
        let targetSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        return thumbnail
    }
}
