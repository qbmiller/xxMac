import AppKit
import ApplicationServices
import OSLog

class AccessibilityManager {
    static let shared = AccessibilityManager()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "Accessibility")

    struct FocusedTextInputSnapshot {
        let app: NSRunningApplication
        let element: AXUIElement
    }

    private var suspendedTextInput: FocusedTextInputSnapshot?
    private var lastPermissionAlertAt = Date.distantPast
    private let permissionAlertCooldown: TimeInterval = 10
    
    private init() {}
    
    func hasAccessibilityPermissions() -> Bool {
        AXIsProcessTrusted()
    }

    // Check if we have accessibility permissions
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @discardableResult
    func requestAccessibilityPermissions() -> Bool {
        let isTrusted = checkAccessibilityPermissions()
        openAccessibilitySettings()
        return isTrusted
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func ensureAccessibilityPermissions() -> Bool {
        guard checkAccessibilityPermissions() else {
            showAccessibilityPermissionAlert()
            return false
        }
        return true
    }

    func suspendFocusedTextInputForOverlay() {
        guard checkAccessibilityPermissions(),
              let snapshot = captureFocusedTextInputSnapshot() else {
            return
        }

        suspendedTextInput = snapshot
        AXUIElementSetAttributeValue(snapshot.element, kAXFocusedAttribute as CFString, kCFBooleanFalse)
        Self.logger.notice("suspended focused text input app=\(snapshot.app.bundleIdentifier ?? "unknown.bundle", privacy: .public)#\(snapshot.app.processIdentifier)")
    }

    func restoreSuspendedTextInputFocus() {
        guard let snapshot = suspendedTextInput else { return }
        suspendedTextInput = nil

        if snapshot.app.isHidden {
            snapshot.app.unhide()
        }
        snapshot.app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(snapshot.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Self.logger.notice("restored focused text input app=\(snapshot.app.bundleIdentifier ?? "unknown.bundle", privacy: .public)#\(snapshot.app.processIdentifier)")
    }

    private func captureFocusedTextInputSnapshot() -> FocusedTextInputSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              focusedElement != nil else {
            return nil
        }
        let element = focusedElement as! AXUIElement
        guard isTextInputElement(element) else { return nil }

        return FocusedTextInputSnapshot(app: app, element: element)
    }

    private func isTextInputElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as CFString)
        let subrole = stringAttribute(element, kAXSubroleAttribute as CFString)
        let roleDescription = stringAttribute(element, kAXRoleDescriptionAttribute as CFString)

        let joined = [role, subrole, roleDescription]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return joined.contains("text") ||
            joined.contains("edit") ||
            joined.contains("secure") ||
            joined.contains("password")
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func showAccessibilityPermissionAlert() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let now = Date()
            guard now.timeIntervalSince(self.lastPermissionAlertAt) >= self.permissionAlertCooldown else { return }
            self.lastPermissionAlertAt = now

            let alert = NSAlert()
            alert.messageText = L10n.t("accessibility.required_title")
            alert.informativeText = L10n.t("accessibility.required_message")
            alert.addButton(withTitle: L10n.t("accessibility.open_settings"))
            alert.addButton(withTitle: L10n.t("general.cancel"))

            if alert.runModal() == .alertFirstButtonReturn {
                self.openAccessibilitySettings()
            }
        }
    }
    
    // Get the frontmost application's focused window
    func getFocusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        let focusedAppResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

        let appElement: AXUIElement
        if focusedAppResult == .success, let focusedApp = focusedApp {
            appElement = (focusedApp as! AXUIElement)
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        } else {
            return nil
        }

        var focusedWindow: AnyObject?
        let focusedWindowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        if focusedWindowResult == .success, focusedWindow != nil {
            return (focusedWindow as! AXUIElement)
        }

        var mainWindow: AnyObject?
        let mainWindowResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
        if mainWindowResult == .success, mainWindow != nil {
            return (mainWindow as! AXUIElement)
        }

        // Fallback: focused UI element -> its window
        var focusedElement: AnyObject?
        let focusedElementResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if focusedElementResult == .success, let focusedElement = focusedElement {
            var elementWindow: AnyObject?
            let elementWindowResult = AXUIElementCopyAttributeValue((focusedElement as! AXUIElement), kAXWindowAttribute as CFString, &elementWindow)
            if elementWindowResult == .success, elementWindow != nil {
                return (elementWindow as! AXUIElement)
            }
        }

        NSLog("[AccessibilityManager] no focused window found focusedAppResult=%@ focusedWindowResult=%@ focusedElementResult=%@",
              String(describing: focusedAppResult),
              String(describing: focusedWindowResult),
              String(describing: focusedElementResult))
        return nil
    }
    
    // Helper to get current window frame
    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        var position = CGPoint.zero
        guard let posVal = positionValue as! AXValue?, AXValueGetValue(posVal, .cgPoint, &position) else { return nil }
        
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        var size = CGSize.zero
        guard let sizeVal = sizeValue as! AXValue?, AXValueGetValue(sizeVal, .cgSize, &size) else { return nil }
        
        return CGRect(origin: position, size: size)
    }
    
    // Helper to get screen containing the window
    private func getScreen(containing rect: CGRect) -> NSScreen? {
        // The input rect is in AX/Carbon coordinates (top-left origin).
        // Compare against each screen converted into AX space and pick max intersection.
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main }

        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0

        for screen in screens {
            let axFrame = carbonRect(from: screen.frame)
            let intersection = rect.intersection(axFrame)
            if !intersection.isNull && intersection.width > 0 && intersection.height > 0 {
                let area = intersection.width * intersection.height
                if area > bestArea {
                    bestArea = area
                    bestScreen = screen
                }
            }
        }

        return bestScreen ?? NSScreen.main
    }
    
    // Helper to convert NSScreen frame to Carbon coordinates
    private func carbonRect(from cocoaRect: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else { return cocoaRect }
        let primaryHeight = primaryScreen.frame.height
        return CGRect(
            x: cocoaRect.origin.x,
            y: primaryHeight - (cocoaRect.origin.y + cocoaRect.height),
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }

    // Get the screen where the focused window is currently located
    private func getCurrentScreen() -> NSScreen? {
        guard let window = getFocusedWindow(),
              let frame = getWindowFrame(window) else {
            return NSScreen.main
        }
        return getScreen(containing: frame)
    }

    private func getCurrentScreenVisibleFrame() -> CGRect? {
        guard let screen = getCurrentScreen() else { return nil }
        return carbonRect(from: screen.visibleFrame)
    }

    // Resize and move window
    func moveWindow(to rect: CGRect) {
        guard ensureAccessibilityPermissions() else { return }
        guard let window = getFocusedWindow() else { return }
        
        // Position
        var position = CGPoint(x: rect.origin.x, y: rect.origin.y)
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            if result != .success {
                NSLog("[AccessibilityManager] failed to set window position: %@", String(describing: result))
            }
        }
        
        // Size
        var size = CGSize(width: rect.size.width, height: rect.size.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            if result != .success {
                NSLog("[AccessibilityManager] failed to set window size: %@", String(describing: result))
            }
        }
    }
    
    // Actions
    func maximize() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        moveWindow(to: screen)
    }
    
    func leftHalf() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
        moveWindow(to: rect)
    }
    
    func rightHalf() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX + screen.width / 2, y: screen.minY, width: screen.width / 2, height: screen.height)
        moveWindow(to: rect)
    }
    
    func topHalf() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func bottomHalf() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY + screen.height / 2, width: screen.width, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func topLeft() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func topRight() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX + screen.width / 2, y: screen.minY, width: screen.width / 2, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func bottomLeft() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY + screen.height / 2, width: screen.width / 2, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func bottomRight() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX + screen.width / 2, y: screen.minY + screen.height / 2, width: screen.width / 2, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func center() {
        guard ensureAccessibilityPermissions() else { return }
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let width = screen.width * 0.8
        let height = screen.height * 0.8
        let x = screen.minX + (screen.width - width) / 2
        let y = screen.minY + (screen.height - height) / 2
        moveWindow(to: CGRect(x: x, y: y, width: width, height: height))
    }
    
    func toggleZoom() {
        guard ensureAccessibilityPermissions() else { return }
        guard let window = getFocusedWindow() else { return }
        let result = AXUIElementPerformAction(window, kAXZoomButtonAttribute as CFString)
        if result != .success {
            NSLog("[AccessibilityManager] failed to toggle zoom: %@", String(describing: result))
        }
    }
    
    func toggleFullscreen() {
        guard ensureAccessibilityPermissions() else { return }
        guard let window = getFocusedWindow() else { return }
        var fullscreen: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen)
        if result == .success, let isFullscreen = fullscreen as? Bool {
            let setResult = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, !isFullscreen as CFTypeRef)
            if setResult != .success {
                NSLog("[AccessibilityManager] failed to toggle fullscreen: %@", String(describing: setResult))
            }
        } else {
            NSLog("[AccessibilityManager] failed to read fullscreen state: %@", String(describing: result))
        }
    }
    
    func nextScreen() {
        guard ensureAccessibilityPermissions() else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        guard let window = getFocusedWindow(), let currentFrame = getWindowFrame(window) else { return }
        
        let currentScreen = getScreen(containing: currentFrame) ?? screens[0]
        
        guard let currentIndex = screens.firstIndex(of: currentScreen) else { return }
        let nextIndex = (currentIndex + 1) % screens.count
        let nextScreen = screens[nextIndex]
        
        moveWindowToScreen(window: window, currentFrame: currentFrame, currentScreen: currentScreen, targetScreen: nextScreen)
    }
    
    func increase() {
        guard ensureAccessibilityPermissions() else { return }
        guard let window = getFocusedWindow() else { return }
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        var posValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
        var pos = CGPoint.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        
        let deltaW = size.width * 0.1
        let deltaH = size.height * 0.1
        
        let newSize = CGSize(width: size.width + deltaW, height: size.height + deltaH)
        let newPos = CGPoint(x: pos.x - deltaW / 2, y: pos.y - deltaH / 2)
        
        moveWindow(to: CGRect(origin: newPos, size: newSize))
    }
    
    func reduce() {
        guard ensureAccessibilityPermissions() else { return }
        guard let window = getFocusedWindow() else { return }
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        var posValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
        var pos = CGPoint.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        
        let deltaW = size.width * 0.1
        let deltaH = size.height * 0.1
        
        let newSize = CGSize(width: size.width - deltaW, height: size.height - deltaH)
        let newPos = CGPoint(x: pos.x + deltaW / 2, y: pos.y + deltaH / 2)
        
        moveWindow(to: CGRect(origin: newPos, size: newSize))
    }
    
    func previousScreen() {
        guard ensureAccessibilityPermissions() else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        guard let window = getFocusedWindow(), let currentFrame = getWindowFrame(window) else { return }
        
        let currentScreen = getScreen(containing: currentFrame) ?? screens[0]
        
        guard let currentIndex = screens.firstIndex(of: currentScreen) else { return }
        let prevIndex = (currentIndex - 1 + screens.count) % screens.count
        let prevScreen = screens[prevIndex]
        
        moveWindowToScreen(window: window, currentFrame: currentFrame, currentScreen: currentScreen, targetScreen: prevScreen)
    }
    
    private func moveWindowToScreen(window: AXUIElement, currentFrame: CGRect, currentScreen: NSScreen, targetScreen: NSScreen) {
        let currentVisible = carbonRect(from: currentScreen.visibleFrame)
        let targetVisible = carbonRect(from: targetScreen.visibleFrame)
        
        // Calculate relative position and size
        let xRatio = (currentFrame.minX - currentVisible.minX) / currentVisible.width
        let yRatio = (currentFrame.minY - currentVisible.minY) / currentVisible.height
        let wRatio = currentFrame.width / currentVisible.width
        let hRatio = currentFrame.height / currentVisible.height
        
        let newX = targetVisible.minX + (targetVisible.width * xRatio)
        let newY = targetVisible.minY + (targetVisible.height * yRatio)
        let newW = targetVisible.width * wRatio
        let newH = targetVisible.height * hRatio
        
        let newRect = CGRect(x: newX, y: newY, width: newW, height: newH)
        moveWindow(to: newRect)
    }
}
