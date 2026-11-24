import AppKit
import ApplicationServices

/// Browser inspection uses Accessibility only: no scripts, extension, or browsing-history database.
final class InputSourceBrowserObserver {
    private let queue = DispatchQueue(label: "xxMac.input-source.browser", qos: .userInitiated)
    private var observer: AXObserver?
    private var timer: Timer?
    private var pid: pid_t?
    private var bundleID = ""
    private var generation = UUID()
    private var queryState = InputSourceBrowserRequestState()
    private var callback: ((InputSourceContext) -> Void)?

    func watch(pid: pid_t, bundleID: String, callback: @escaping (InputSourceContext) -> Void) {
        stop()
        guard AXIsProcessTrusted() else { return }
        self.pid = pid
        self.bundleID = bundleID
        self.callback = callback
        var created: AXObserver?
        if AXObserverCreate(pid, { _, _, _, pointer in
            guard let pointer else { return }
            let watcher = Unmanaged<InputSourceBrowserObserver>.fromOpaque(pointer).takeUnretainedValue()
            watcher.refresh(invalidateCurrent: true)
        }, &created) == .success, let created {
            observer = created
            let application = AXUIElementCreateApplication(pid)
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            for notification in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
                AXObserverAddNotification(created, application, notification as CFString, pointer)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        // Some browsers don't send tab URL notifications. Poll only the frontmost supported
        // browser with active rules; serialize, cap tree work, and discard stale replies.
        timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        refresh()
    }

    func snapshot(pid: pid_t, bundleID: String, completion: @escaping (InputSourceContext) -> Void) {
        guard AXIsProcessTrusted() else { return }
        let token = generation
        queue.async { [weak self] in
            let context = Self.readContext(pid: pid, bundleID: bundleID)
            DispatchQueue.main.async {
                guard self?.generation == token, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                completion(context)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        pid = nil
        callback = nil
        generation = UUID()
        queryState = InputSourceBrowserRequestState()
    }

    deinit { stop() }

    private func refresh(invalidateCurrent: Bool = false) {
        guard let pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let revision = queryState.begin(invalidateCurrent: invalidateCurrent) else { return }
        let token = generation
        let bundleID = bundleID
        queue.async { [weak self] in
            let context = Self.readContext(pid: pid, bundleID: bundleID)
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                let accepted = self.queryState.finish(revision)
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                guard accepted else { self.refresh(); return }
                self.callback?(context)
            }
        }
    }

    private static func readContext(pid: pid_t, bundleID: String) -> InputSourceContext {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var context = InputSourceContext(bundleID: bundleID)
        let focused = element(app, kAXFocusedUIElementAttribute)
        if let focused { context.addressBarFocused = isAddressBar(focused, bundleID: bundleID) }
        guard let window = element(app, kAXFocusedWindowAttribute) else { return context }
        if let document = attribute(window, kAXDocumentAttribute) as? String,
           let url = webURL(document) { context.url = url }
        // Prefer the active web area URL over omnibox text (which can be a search query).
        if context.url == nil {
            var pending: [AXUIElement] = [window]
            var visited = 0
            let deadline = ProcessInfo.processInfo.systemUptime + 0.35
            while !pending.isEmpty, visited < 120, ProcessInfo.processInfo.systemUptime < deadline {
                let node = pending.removeLast()
                visited += 1
                if attribute(node, kAXRoleAttribute) as? String == "AXWebArea" {
                    if let value = attribute(node, kAXURLAttribute) {
                        let url = (value as? URL) ?? (value as? String).flatMap(webURL)
                        if let url, ["http", "https"].contains(url.scheme ?? "") { context.url = url; break }
                    }
                    continue // Never traverse webpage inputs or read page content.
                }
                let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
                pending.append(contentsOf: children.prefix(40).reversed())
            }
        }
        return context
    }

    private static func isAddressBar(_ focused: AXUIElement, bundleID: String) -> Bool {
        // A page can expose arbitrary AX identifiers. Require a browser-chrome element.
        var ancestor = element(focused, kAXParentAttribute)
        var reachedWindow = false
        for _ in 0..<32 {
            guard let node = ancestor, let role = attribute(node, kAXRoleAttribute) as? String else { return false }
            if role == "AXWebArea" { return false }
            if role == kAXWindowRole { reachedWindow = true; break }
            ancestor = element(node, kAXParentAttribute)
        }
        guard reachedWindow else { return false }
        if bundleID == "com.apple.Safari" {
            return attribute(focused, kAXIdentifierAttribute) as? String == "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
        }
        let classes = attribute(focused, "AXDOMClassList") as? [String] ?? []
        return classes.contains("OmniboxViewViews")
    }

    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ parent: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = attribute(parent, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
