import AppKit
import Carbon
import Combine

final class InputSourceAutomationManager: ObservableObject {
    static let shared = InputSourceAutomationManager()
    static let settingsKey = "InputSourceSettings"
    static let memoryKey = "InputSourceAppMemory"

    @Published var settings: InputSourceSettings {
        didSet {
            guard !loading else { return }
            if let data = try? JSONEncoder().encode(settings) { store.set(data, forKey: Self.settingsKey) }
            if running { configure() }
        }
    }
    @Published var isPaused = false { didSet { if running { activateCurrentApplication() } } }
    @Published private(set) var sources: [InputSourceDescriptor] = []
    @Published private(set) var currentSource: InputSourceDescriptor?
    @Published private(set) var currentAppName = ""
    @Published private(set) var currentHost = ""
    @Published private(set) var statusKey = "input.status.disabled"
    @Published private(set) var issueKey: String?
    @Published private(set) var shortcutIssueIDs = Set<UUID>()
    @Published private(set) var accessibilityGranted = false
    private(set) var memory: [String: String] = [:]

    private let store: PreferencesStore
    private let controller: InputSourceControlling
    private let uptime: () -> TimeInterval
    private let frontmostBundleID: () -> String?
    private let browser = InputSourceBrowserObserver()
    private let indicator: InputSourceIndicatorPresenting
    private let isOwnApplicationActive: () -> Bool
    private var context: InputSourceContext?
    private var selectionState = InputSourceSelectionState()
    private var contextBeganAt: TimeInterval = 0
    private var sourceBeforeAddress: String?
    private var lastExternalApp: NSRunningApplication?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var hotKeys: [UUID: CarbonHotKeyRegistration] = [:]
    private var registeredIDs = Set<UUID>()
    private var globalMouseMonitor: Any?
    private var longPress: DispatchWorkItem?
    private var activationToken = UUID()
    private var launcherActive = false
    private var sleeping = false
    private var screenLocked = false
    private var suspended: Bool { sleeping || screenLocked }
    private var appIndicatorRequest = InputSourceAppIndicatorRequest()
    private var running = false
    private var loading = false

    init(store: PreferencesStore = .shared, controller: InputSourceControlling = SystemInputSourceController(),
         indicator: InputSourceIndicatorPresenting = InputSourceIndicatorController(),
         isOwnApplicationActive: @escaping () -> Bool = { NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) {
        self.store = store
        self.controller = controller
        self.indicator = indicator
        self.isOwnApplicationActive = isOwnApplicationActive
        self.uptime = uptime
        self.frontmostBundleID = frontmostBundleID
        settings = store.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(InputSourceSettings.self, from: $0) } ?? .init()
        memory = store.data(forKey: Self.memoryKey).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        refreshSources()
    }

    func start() {
        guard !running else { return }
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in self?.activateCurrentApplication(showIndicator: true) }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] _ in self?.setSleeping(true) }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] _ in self?.setSleeping(false) }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)) { [weak self] _ in self?.sourceChanged() }
        observe(distributed, Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)) { [weak self] _ in
            self?.refreshSources()
            self?.activateCurrentApplication()
        }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] _ in self?.setScreenLocked(true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] _ in self?.setScreenLocked(false) }
        observe(.default, .configDirectoryDidChange) { [weak self] _ in self?.reload() }
        configure()
    }

    func stop() {
        running = false
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        resetContext()
        removeMouseMonitors()
        clearHotKeys()
        indicator.hide()
    }

    deinit {
        observers.forEach { $0.0.removeObserver($0.1) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        registeredIDs.forEach { ShortcutRegistryStore.shared.unregister(action: .inputSource($0)) }
    }

    func refreshSources() {
        sources = controller.availableSources()
        currentSource = controller.currentSource()
        accessibilityGranted = AXIsProcessTrusted()
    }

    func reload() {
        loading = true
        settings = store.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(InputSourceSettings.self, from: $0) } ?? .init()
        memory = store.data(forKey: Self.memoryKey).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        loading = false
        if running { configure() }
    }

    @discardableResult
    func importSettings(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(InputSourceSettings.self, from: data) else { return false }
        settings = decoded
        return true
    }

    func clearMemory() {
        memory = [:]
        store.set(Data("{}".utf8), forKey: Self.memoryKey)
    }

    func previewIndicator() {
        refreshSources()
        if let currentSource { indicator.show(source: currentSource, settings: settings) }
    }

    func selectForLauncher() {
        // Launcher is an overlay; keep its explicit preference above external app rules.
        resetContext()
        _ = select("com.apple.keylayout.ABC", automatic: true)
    }

    func launcherWillOpen() {
        launcherActive = true
        resetContext()
        indicator.hide()
    }

    func launcherDidClose() {
        launcherActive = false
        if running { activateCurrentApplication() }
    }

    @discardableResult
    func select(_ id: String, automatic: Bool) -> Bool {
        guard !id.isEmpty else { return false }
        if controller.currentSource()?.id == id { return true }
        guard sources.contains(where: { $0.id == id }) else { issueKey = "input.error.unavailable"; return false }
        if automatic { selectionState.beginAutomaticSelection(target: id, now: uptime()) }
        else { selectionState.userSelected(id) }
        guard controller.selectSource(id: id) else {
            selectionState.userSelected(id)
            issueKey = "input.error.selection"
            return false
        }
        issueKey = nil
        sourceChanged()
        return true
    }

    func captureForMenu() {
        refreshSources()
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier, let id = app.bundleIdentifier else { return }
        lastExternalApp = app
        currentAppName = app.localizedName ?? id
        currentHost = ""
        if InputSourcePolicy.browsers[id] != nil {
            browser.snapshot(pid: app.processIdentifier, bundleID: id) { [weak self] context in
                self?.currentHost = context.url?.host ?? ""
            }
        }
    }

    func addCurrentWebsiteRule() {
        guard !currentHost.isEmpty, let source = currentSource?.id else { return }
        if let index = settings.websiteRules.firstIndex(where: { $0.pattern == currentHost && $0.match == .domain && $0.browserID.isEmpty }) {
            settings.websiteRules[index].sourceID = source
        } else { settings.websiteRules.insert(.init(pattern: currentHost, match: .domain, sourceID: source), at: 0) }
    }

    func addCurrentAppRule() {
        guard let app = lastExternalApp, let id = app.bundleIdentifier else { return }
        if settings.appRules.contains(where: { $0.bundleID == id }) { return }
        settings.appRules.append(.init(bundleID: id, name: app.localizedName ?? id, sourceID: currentSource?.id ?? ""))
    }

    func addApp(at url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              !settings.appRules.contains(where: { $0.bundleID == id }) else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        settings.appRules.append(.init(bundleID: id, name: name, sourceID: currentSource?.id ?? ""))
    }

    @discardableResult
    func updateShortcut(_ id: UUID, configuration: HotKeyConfiguration?) -> Bool {
        guard let index = settings.shortcuts.firstIndex(where: { $0.id == id }) else { return false }
        if let configuration, configuration.modifiers.intersection([.command, .control, .option, .shift]).isEmpty { return false }
        if let configuration, settings.shortcuts.contains(where: {
            $0.id != id && $0.configuration?.key == configuration.key && $0.configuration?.modifiers == configuration.modifiers
        }) { return false }
        if let configuration, ShortcutRegistryStore.shared.conflict(for: .inputSource(id), trigger: .keyboard(configuration)) != nil { return false }
        settings.shortcuts[index].configuration = configuration
        return true
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, handler: @escaping (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: handler)))
    }

    private func configure() {
        refreshSources()
        indicator.hide()
        refreshHotKeys()
        configureMouseMonitors()
        activateCurrentApplication()
    }

    private func resetContext() {
        activationToken = UUID()
        browser.stop()
        context = nil
        sourceBeforeAddress = nil
        appIndicatorRequest = InputSourceAppIndicatorRequest()
    }

    private func activateCurrentApplication(showIndicator: Bool = false) {
        resetContext()
        if isOwnApplicationActive() {
            longPress?.cancel()
            longPress = nil
            indicator.hide()
            return
        }
        guard !suspended, !launcherActive, let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApp = app
        currentAppName = app.localizedName ?? bundleID
        currentHost = ""
        accessibilityGranted = AXIsProcessTrusted()
        if showIndicator, settings.showOnAppSwitch { appIndicatorRequest.request() }
        guard settings.enabled, !isPaused else {
            statusKey = isPaused ? "input.status.paused" : "input.status.disabled"
            appIndicatorRequest.resolve(target: nil)
            showPendingAppIndicator()
            return
        }
        let token = activationToken
        // Let macOS finish restoring the newly focused application's input context first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.activationToken == token,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            let needsBrowser = InputSourcePolicy.browsers[bundleID] != nil &&
                (!self.settings.addressBarSourceID.isEmpty || self.settings.websiteRules.contains { $0.enabled && ($0.browserID.isEmpty || $0.browserID == bundleID) })
            if needsBrowser, self.accessibilityGranted {
                self.browser.watch(pid: app.processIdentifier, bundleID: bundleID) { [weak self] context in self?.acceptContext(context) }
            } else {
                self.acceptContext(.init(bundleID: bundleID))
                if needsBrowser { self.issueKey = "input.error.accessibility" }
            }
        }
    }

    /// Main-thread state transition; called only for the current browser/application generation.
    func acceptContext(_ next: InputSourceContext, force: Bool = false) {
        guard settings.enabled, !isPaused, !suspended, !launcherActive else { return }
        guard force || next != context else { return }
        let previous = context
        if next.addressBarFocused, previous?.addressBarFocused != true {
            sourceBeforeAddress = controller.currentSource()?.id
        }
        context = next
        contextBeganAt = uptime()
        currentHost = next.url?.host ?? ""
        let decision = InputSourcePolicy.resolve(settings: settings, context: next, memory: memory)
        statusKey = decision.reason
        issueKey = nil
        // A temporary address-bar override must not erase the page's manual choice.
        let returningFromAddress = previous?.addressBarFocused == true && !next.addressBarFocused && previous?.bundleID == next.bundleID
        let target = returningFromAddress && decision.reason != "input.status.website"
            ? sourceBeforeAddress ?? decision.sourceID : decision.sourceID
        appIndicatorRequest.resolve(target: target)
        if let target, !select(target, automatic: true) { appIndicatorRequest.resolve(target: nil) }
        if !next.addressBarFocused { sourceBeforeAddress = nil }
        showPendingAppIndicator()
    }

    func sourceChanged() {
        let source = controller.currentSource()
        let changed = currentSource?.id != source?.id
        currentSource = source
        guard !suspended, let source else { return }
        if changed, settings.showOnChange { showAutomaticIndicator(source) }
        let now = uptime()
        let manual = selectionState.shouldRemember(sourceID: source.id, now: now)
        showPendingAppIndicator()
        guard changed, settings.enabled, !isPaused, let context,
              frontmostBundleID() == context.bundleID,
              !context.addressBarFocused, now - contextBeganAt > 0.2,
              manual,
              InputSourcePolicy.resolve(settings: settings, context: context, memory: memory).reason == "input.status.memory" else { return }
        memory[context.bundleID] = source.id
        if let data = try? JSONEncoder().encode(memory) { store.set(data, forKey: Self.memoryKey) }
    }

    private func showPendingAppIndicator() {
        guard let source = controller.currentSource(), appIndicatorRequest.takeIfReady(currentSourceID: source.id) else { return }
        showAutomaticIndicator(source)
    }

    private func showAutomaticIndicator(_ source: InputSourceDescriptor) {
        guard !suspended, !launcherActive, !isOwnApplicationActive() else { return }
        indicator.show(source: source, settings: settings)
    }

    func setSleeping(_ value: Bool) {
        sleeping = value
        updateSuspension()
    }

    func setScreenLocked(_ value: Bool) {
        screenLocked = value
        updateSuspension()
    }

    private func updateSuspension() {
        if suspended {
            resetContext()
            removeMouseMonitors()
            indicator.hide()
            clearHotKeys()
        } else if running { configure() }
    }

    private func clearHotKeys() {
        hotKeys.removeAll()
        registeredIDs.forEach { ShortcutRegistryStore.shared.unregister(action: .inputSource($0)) }
        registeredIDs.removeAll()
    }

    private func refreshHotKeys() {
        clearHotKeys()
        shortcutIssueIDs = []
        guard running, !suspended else { return }
        for shortcut in settings.shortcuts {
            guard let configuration = shortcut.configuration else { continue }
            let action = ShortcutAction.inputSource(shortcut.id)
            guard ShortcutRegistryStore.shared.register(action: action, trigger: .keyboard(configuration)) == nil else {
                shortcutIssueIDs.insert(shortcut.id); continue
            }
            registeredIDs.insert(shortcut.id)
            guard let registration = CarbonHotKeyRegistration(configuration: configuration, name: "inputSource.\(shortcut.id)", handler: { [weak self] in
                self?.runShortcut(shortcut.id)
            }) else { shortcutIssueIDs.insert(shortcut.id); continue }
            hotKeys[shortcut.id] = registration
        }
    }

    private func runShortcut(_ id: UUID) {
        guard !suspended, let shortcut = settings.shortcuts.first(where: { $0.id == id }) else { return }
        let valid = shortcut.sourceIDs.filter { id in sources.contains { $0.id == id } }
        guard !valid.isEmpty else { issueKey = "input.error.unavailable"; return }
        let index = valid.firstIndex(of: controller.currentSource()?.id ?? "").map { ($0 + 1) % valid.count } ?? 0
        _ = select(valid[index], automatic: false)
        sourceChanged()
        if let source = currentSource, settings.showOnChange { showAutomaticIndicator(source) }
    }

    private func configureMouseMonitors() {
        removeMouseMonitors()
        guard running, !suspended, settings.showOnLongPress else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handleMouse(event) }
    }

    private func handleMouse(_ event: NSEvent) {
        longPress?.cancel()
        longPress = nil
        guard event.type == .leftMouseDown, !isOwnApplicationActive() else { return }
        let work = DispatchWorkItem { [weak self] in self?.handleLongPress() }
        longPress = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func handleLongPress() {
        guard settings.showOnLongPress, !suspended, !launcherActive, !isOwnApplicationActive() else { return }
        refreshSources()
        if let currentSource { showAutomaticIndicator(currentSource) }
    }

    private func removeMouseMonitors() {
        longPress?.cancel()
        longPress = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        globalMouseMonitor = nil
    }
}
