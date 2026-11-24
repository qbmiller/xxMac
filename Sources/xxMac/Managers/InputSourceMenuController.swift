import AppKit

/// Retained by AppDelegate because NSMenu's delegate is weak.
final class InputSourceMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    func menuWillOpen(_ menu: NSMenu) {
        let manager = InputSourceAutomationManager.shared
        manager.refreshSources()
        menu.removeAllItems()
        let pause = item(L10n.t("input.paused"), action: #selector(togglePause))
        pause.state = manager.isPaused ? .on : .off
        pause.isEnabled = manager.settings.enabled
        menu.addItem(pause)
        menu.addItem(item(L10n.t("input.add_current_app"), action: #selector(addApp)))
        let website = item(L10n.t("input.use_current_for_website"), action: #selector(addWebsite))
        website.isEnabled = !manager.currentHost.isEmpty
        menu.addItem(website)
        menu.addItem(.separator())
        for source in manager.sources {
            let entry = item(source.name, action: #selector(selectSource(_:)))
            entry.representedObject = source.id
            entry.state = manager.currentSource?.id == source.id ? .on : .off
            menu.addItem(entry)
        }
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func togglePause() { InputSourceAutomationManager.shared.isPaused.toggle() }
    @objc private func addApp() { InputSourceAutomationManager.shared.addCurrentAppRule() }
    @objc private func addWebsite() { InputSourceAutomationManager.shared.addCurrentWebsiteRule() }
    @objc private func selectSource(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { _ = InputSourceAutomationManager.shared.select(id, automatic: false) }
    }
}
