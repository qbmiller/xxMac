import AppKit
import ApplicationServices

class AccessibilityManager {
    static let shared = AccessibilityManager()
    
    private init() {}
    
    // Check if we have accessibility permissions
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
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
        guard let window = getFocusedWindow() else { return }
        
        // Position
        var position = CGPoint(x: rect.origin.x, y: rect.origin.y)
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        
        // Size
        var size = CGSize(width: rect.size.width, height: rect.size.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }
    
    // Actions
    func maximize() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        moveWindow(to: screen)
    }
    
    func leftHalf() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
        moveWindow(to: rect)
    }
    
    func rightHalf() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX + screen.width / 2, y: screen.minY, width: screen.width / 2, height: screen.height)
        moveWindow(to: rect)
    }
    
    func topHalf() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func bottomHalf() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY + screen.height / 2, width: screen.width, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func topLeft() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func topRight() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX + screen.width / 2, y: screen.minY, width: screen.width / 2, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func bottomLeft() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX, y: screen.minY + screen.height / 2, width: screen.width / 2, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func bottomRight() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let rect = CGRect(x: screen.minX + screen.width / 2, y: screen.minY + screen.height / 2, width: screen.width / 2, height: screen.height / 2)
        moveWindow(to: rect)
    }
    
    func center() {
        guard let screen = getCurrentScreenVisibleFrame() else { return }
        let width = screen.width * 0.8
        let height = screen.height * 0.8
        let x = screen.minX + (screen.width - width) / 2
        let y = screen.minY + (screen.height - height) / 2
        moveWindow(to: CGRect(x: x, y: y, width: width, height: height))
    }
    
    func toggleZoom() {
        guard let window = getFocusedWindow() else { return }
        AXUIElementPerformAction(window, kAXZoomButtonAttribute as CFString)
    }
    
    func toggleFullscreen() {
        guard let window = getFocusedWindow() else { return }
        var fullscreen: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen)
        if result == .success, let isFullscreen = fullscreen as? Bool {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, !isFullscreen as CFTypeRef)
        }
    }
    
    func nextScreen() {
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
