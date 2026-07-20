import AppKit
import Combine
import HotKey
import ApplicationServices
import OSLog

// MARK: - Clipboard Manager

struct ClipboardSettings: Codable {
    var clipboardMonitoringEnabled = AppDefaultSettings.Clipboard.monitoringEnabled
    var manageImages = AppDefaultSettings.Clipboard.manageImages
    var imageCacheDurationDays = AppDefaultSettings.Clipboard.imageCacheDurationDays
    var textCacheDurationDays = AppDefaultSettings.Clipboard.textCacheDurationDays
    var maxImageSizeMB = AppDefaultSettings.Clipboard.maxImageSizeMB
    var maxHistoryItems = AppDefaultSettings.Clipboard.maxHistoryItems
    var maxImageStorageSizeMB = AppDefaultSettings.Clipboard.maxImageStorageSizeMB
    var thumbnailGenerationThresholdMB = AppDefaultSettings.Clipboard.thumbnailGenerationThresholdMB
    var imageOCREnabled = AppDefaultSettings.Clipboard.imageOCREnabled
    var maxOCRImageSizeMB = AppDefaultSettings.Clipboard.maxOCRImageSizeMB
    var imageOCRLanguages = AppDefaultSettings.Clipboard.imageOCRLanguages
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
        case imageOCREnabled
        case maxOCRImageSizeMB
        case imageOCRLanguages
        case hotKey
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clipboardMonitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardMonitoringEnabled) ?? AppDefaultSettings.Clipboard.monitoringEnabled
        manageImages = try container.decodeIfPresent(Bool.self, forKey: .manageImages) ?? AppDefaultSettings.Clipboard.manageImages
        imageCacheDurationDays = try container.decodeIfPresent(Int.self, forKey: .imageCacheDurationDays) ?? AppDefaultSettings.Clipboard.imageCacheDurationDays
        textCacheDurationDays = try container.decodeIfPresent(Int.self, forKey: .textCacheDurationDays) ?? AppDefaultSettings.Clipboard.textCacheDurationDays
        maxImageSizeMB = try container.decodeIfPresent(Int.self, forKey: .maxImageSizeMB) ?? AppDefaultSettings.Clipboard.maxImageSizeMB
        maxHistoryItems = try container.decodeIfPresent(Int.self, forKey: .maxHistoryItems) ?? AppDefaultSettings.Clipboard.maxHistoryItems
        maxImageStorageSizeMB = try container.decodeIfPresent(Int.self, forKey: .maxImageStorageSizeMB) ?? AppDefaultSettings.Clipboard.maxImageStorageSizeMB
        thumbnailGenerationThresholdMB = try container.decodeIfPresent(Int.self, forKey: .thumbnailGenerationThresholdMB) ?? AppDefaultSettings.Clipboard.thumbnailGenerationThresholdMB
        imageOCREnabled = try container.decodeIfPresent(Bool.self, forKey: .imageOCREnabled) ?? AppDefaultSettings.Clipboard.imageOCREnabled
        maxOCRImageSizeMB = try container.decodeIfPresent(Int.self, forKey: .maxOCRImageSizeMB) ?? AppDefaultSettings.Clipboard.maxOCRImageSizeMB
        imageOCRLanguages = try container.decodeIfPresent([String].self, forKey: .imageOCRLanguages) ?? AppDefaultSettings.Clipboard.imageOCRLanguages
        hotKey = try container.decodeIfPresent(HotKeyConfiguration.self, forKey: .hotKey)
    }
}

enum ClipboardFocusRestorationAction: Equatable {
    case wait
    case restoreTextInput
}

enum ClipboardFocusRestorationPolicy {
    static func action(
        targetPID: pid_t?,
        frontmostPID: pid_t?,
        retriesRemaining: Int
    ) -> ClipboardFocusRestorationAction {
        guard let targetPID, retriesRemaining > 0 else {
            return .restoreTextInput
        }
        return targetPID == frontmostPID ? .restoreTextInput : .wait
    }
}

enum ClipboardPanelTab: CaseIterable, Hashable {
    case history
    case favorites
    case snippets

    var titleKey: String {
        switch self {
        case .history: return "clipboard.tab.history"
        case .favorites: return "clipboard.tab.favorites"
        case .snippets: return "clipboard.tab.snippets"
        }
    }

    var iconName: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .favorites: return "star"
        case .snippets: return "text.quote"
        }
    }
}

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "ClipboardFlow")
    
    @Published var history: [SearchItem] = []
    @Published private(set) var activeTab: ClipboardPanelTab = .history
    @Published var settings: ClipboardSettings = ClipboardSettings() {
        didSet {
            saveSettings()
            updateStorageLimits()
            updateHotKey()
            updateMonitoringState()
        }
    }
    
    private var clipboardItems: [ClipboardListItem] = []
    private var currentQuery = ""
    private var changeCount: Int
    private var timer: Timer?
    private var hotKey: CarbonHotKeyRegistration?
    private var previousFrontmostApp: NSRunningApplication?
    
    private let storage = ClipboardStorageManager.shared
    private var cancellables = Set<AnyCancellable>()

    private func logClipboardFlow(_ stage: String) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier ?? "nil"
        let pid = frontmost?.processIdentifier ?? 0
        let previous = previousFrontmostApp?.bundleIdentifier ?? "nil"
        let previousPID = previousFrontmostApp?.processIdentifier ?? 0
        Self.logger.notice("stage=\(stage, privacy: .public) frontmost=\(bundleID, privacy: .public)#\(pid) previous=\(previous, privacy: .public)#\(previousPID) appActive=\(NSApp.isActive) appHidden=\(NSApp.isHidden)")
    }
    
    private init() {
        self.changeCount = NSPasteboard.general.changeCount
        
        loadSettings()
        
        // Initial load
        refreshHistory()
        
        updateStorageLimits()
        updateMonitoringState()
        updateHotKey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onClipboardOCRDidUpdate),
            name: .clipboardOCRDidUpdate,
            object: nil
        )

        SnippetManager.shared.$entries
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.activeTab == .snippets else { return }
                self?.refreshHistory()
            }
            .store(in: &cancellables)

        SnippetManager.shared.$collections
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.activeTab == .snippets else { return }
                self?.refreshHistory()
            }
            .store(in: &cancellables)
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
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        var imageToSave: NSImage?

        if !fileURLs.isEmpty {
            let nameText = FilePathPasteManager.nameText(for: fileURLs)
            addItem(type: .text, content: nameText, size: nameText.utf8.count)
            return
        } else if let str = pasteboard.string(forType: .string), Self.shouldRecordText(str) {
            addItem(type: .text, content: str, size: str.utf8.count)
            return
        } else {
            guard settings.manageImages else { return }
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
                    let shouldOCR = shouldOCRImage(byteSize: pngData.count)
                    let itemID = storage.saveImageItem(
                        content: filename,
                        size: pngData.count,
                        width: dimensions.width,
                        height: dimensions.height,
                        thumbnailFilename: thumbnailFilename,
                        ocrStatus: shouldOCR ? .pending : .skipped
                    )
                    if shouldOCR {
                        ClipboardOCRManager.shared.enqueueImageOCR(
                            itemID: itemID,
                            imageURL: fileURL,
                            languages: settings.imageOCRLanguages
                        )
                    }
                    refreshHistory()
                } catch {
                    print("Failed to save clipboard image: \(error)")
                }
            }
        }
    }
    
    private func addItem(type: ClipboardContentType, content: String, size: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.storage.saveItem(type: type, content: content, size: size)
            self?.refreshHistory()
        }
    }

    func recordText(_ text: String) {
        guard settings.clipboardMonitoringEnabled, Self.shouldRecordText(text) else { return }
        addItem(type: .text, content: text, size: text.utf8.count)
    }
    
    func refreshHistory() {
        if activeTab == .snippets {
            publishSnippetHistory(query: currentQuery)
            return
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let items = self.items(for: self.activeTab, query: self.currentQuery)
            DispatchQueue.main.async {
                self.clipboardItems = items
                self.updatePublishedHistory()
            }
        }
    }

    func searchClipboard(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = trimmedQuery

        if activeTab == .snippets {
            publishSnippetHistory(query: trimmedQuery)
            return
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let listItems = self.items(for: self.activeTab, query: trimmedQuery)

            DispatchQueue.main.async {
                self.clipboardItems = listItems
                self.updatePublishedHistory()
            }
        }
    }

    func selectTab(_ tab: ClipboardPanelTab) {
        activeTab = tab
        refreshHistory()
    }

    func selectNextTab() {
        selectAdjacentTab(offset: 1)
    }

    func selectPreviousTab() {
        selectAdjacentTab(offset: -1)
    }

    private func selectAdjacentTab(offset: Int) {
        let tabs = ClipboardPanelTab.allCases
        guard let index = tabs.firstIndex(of: activeTab) else {
            selectTab(.history)
            return
        }
        selectTab(tabs[(index + offset + tabs.count) % tabs.count])
    }

    private func items(for tab: ClipboardPanelTab, query: String) -> [ClipboardListItem] {
        switch tab {
        case .history:
            return query.isEmpty ? storage.getListItems() : storage.searchListItems(query: query)
        case .favorites:
            return query.isEmpty ? storage.getFavoriteListItems() : storage.searchFavoriteListItems(query: query)
        case .snippets:
            return []
        }
    }

    private func publishSnippetHistory(query: String) {
        let publish = { [weak self] in
            guard let self, self.activeTab == .snippets else { return }
            self.clipboardItems = []
            self.history = SnippetManager.shared.search(query: query)
        }

        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async {
                publish()
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
                    clipboardAction: ClipboardActionData(id: item.id, isFavorite: item.isFavorite, isPinned: item.isPinned),
                    action: { [weak self] in self?.pasteItem(id: item.id) }
                )
            case .image:
                return SearchItem(
                    id: "clipboard.\(item.id.uuidString)",
                    title: imageDisplayTitle(for: item),
                    subtitle: imageSubtitle(for: item),
                    iconName: "photo",
                    type: .clipboard,
                    clipboardPreview: .image(
                        filename: item.imageFilename ?? item.previewContent,
                        thumbnailFilename: item.thumbnailFilename,
                        byteSize: item.size,
                        ocrStatus: item.imageOCRStatus,
                        ocrTextPreview: item.imageOCRTextPreview
                    ),
                    clipboardAction: ClipboardActionData(id: item.id, isFavorite: item.isFavorite, isPinned: item.isPinned),
                    action: { [weak self] in self?.pasteItem(id: item.id) }
                )
            }
        }
    }

    func toggleFavorite(id: UUID) {
        guard let item = storage.getItem(id: id) else { return }
        setFavorite(id: id, isFavorite: !item.isFavorite)
    }

    func addFavorite(id: UUID) {
        setFavorite(id: id, isFavorite: true)
    }

    func removeFavorite(id: UUID) {
        setFavorite(id: id, isFavorite: false)
    }

    func togglePinned(id: UUID) {
        guard let item = storage.getItem(id: id), item.isFavorite else { return }
        storage.setPinned(id: id, isPinned: !item.isPinned)
        refreshHistory()
    }

    private func setFavorite(id: UUID, isFavorite: Bool) {
        storage.setFavorite(id: id, isFavorite: isFavorite)
        refreshHistory()
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
            AccessibilityManager.shared.restoreSuspendedTextInputFocus()
            self.restoreFocusToCapturedApp()
            self.sendPasteCommandWhenReady(retries: 8)
        }
    }

    func cancelClipboardHistory() {
        logClipboardFlow("cancel.begin")
        NotificationCenter.default.post(name: NSNotification.Name("CloseLauncherPanelOnly"), object: nil)
        restoreFocusToCapturedApp()
        restoreTextInputWhenCapturedAppIsActive(retries: 8)
    }

    private func restoreTextInputWhenCapturedAppIsActive(retries: Int) {
        let action = ClipboardFocusRestorationPolicy.action(
            targetPID: previousFrontmostApp?.processIdentifier,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            retriesRemaining: retries
        )

        switch action {
        case .restoreTextInput:
            AccessibilityManager.shared.restoreSuspendedTextInputFocus()
            previousFrontmostApp = nil
            logClipboardFlow("cancel.restored retries=\(retries)")
        case .wait:
            restoreFocusToCapturedApp()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.restoreTextInputWhenCapturedAppIsActive(retries: retries - 1)
            }
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
        logClipboardFlow("restoreFocus.activated=\(activated)")
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
        ShortcutRegistryStore.shared.unregister(action: .clipboard)
        if let config = settings.hotKey {
            guard ShortcutRegistryStore.shared.register(
                action: .clipboard,
                trigger: .keyboard(config)
            ) == nil else { return }
            hotKey = CarbonHotKeyRegistration(configuration: config, name: "clipboard") { [weak self] in
                self?.showClipboardHistory()
            }
        }
    }

    @discardableResult
    func setHotKey(_ configuration: HotKeyConfiguration?) -> ShortcutConflict? {
        if let configuration,
           let conflict = ShortcutRegistryStore.shared.conflict(
               for: .clipboard,
               trigger: .keyboard(configuration)
           ) {
            return conflict
        }
        settings.hotKey = configuration
        return nil
    }

    func captureCurrentFrontmostApp() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostApp = app
        }
    }

    func showClipboardHistory() {
        DispatchQueue.main.async {
            self.logClipboardFlow("showClipboardHistory.begin")
            self.captureCurrentFrontmostApp()
            AccessibilityManager.shared.suspendFocusedTextInputForOverlay()
            self.logClipboardFlow("showClipboardHistory.postNotification")
            NotificationCenter.default.post(name: NSNotification.Name("ShowClipboardHistory"), object: nil)
        }
    }

    @objc private func onClipboardOCRDidUpdate() {
        refreshHistory()
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

    private func imageSubtitle(for item: ClipboardListItem) -> String {
        let base = L10n.f("clipboard.item.image_subtitle_format", formatSize(item.size), formatDate(item.timestamp))
        switch item.imageOCRStatus {
        case .pending:
            return "\(L10n.t("clipboard.ocr_status_pending")) • \(base)"
        case .ready where item.hasImageOCRText:
            return "\(L10n.t("clipboard.ocr_status_ready")) • \(base)"
        default:
            return base
        }
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

    private func shouldOCRImage(byteSize: Int) -> Bool {
        guard settings.imageOCREnabled else { return false }
        let maxBytes = max(1, settings.maxOCRImageSizeMB) * 1024 * 1024
        return byteSize <= maxBytes
    }

    static func shouldRecordText(_ text: String) -> Bool {
        !text.isEmpty
    }
}
