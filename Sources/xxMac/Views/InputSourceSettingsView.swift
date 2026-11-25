import AppKit
import SwiftUI
import HotKey
import UniformTypeIdentifiers

struct InputSourceSettingsView: View {
    let section: FunctionType
    @ObservedObject private var manager = InputSourceAutomationManager.shared
    @State private var websiteDraft: InputSourceWebsiteRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch section {
            case .inputSourceApps: apps
            case .inputSourceWebsites: websites
            case .inputSourceIndicator: indicator
            case .inputSourceShortcuts: shortcuts
            default: general
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { manager.refreshSources() }
        .sheet(item: $websiteDraft) { draft in
            InputSourceWebsiteEditor(rule: draft, sources: manager.sources) { rule in
                if let index = manager.settings.websiteRules.firstIndex(where: { $0.id == rule.id }) {
                    manager.settings.websiteRules[index] = rule
                } else { manager.settings.websiteRules.append(rule) }
            }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("input.description")).foregroundColor(.secondary)
            Toggle(L10n.t("input.enabled"), isOn: $manager.settings.enabled)
            Toggle(L10n.t("input.paused"), isOn: $manager.isPaused)
                .disabled(!manager.settings.enabled)
            InputSourcePicker(title: L10n.t("input.fallback"), selection: $manager.settings.defaultSourceID, sources: manager.sources, allowsKeep: true)
            Text(L10n.t("input.manual_hint")).font(.caption).foregroundColor(.secondary)
            Divider()
            GroupBox(L10n.t("input.current_status")) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(L10n.t("input.current_app"), value: manager.currentAppName.isEmpty ? "—" : manager.currentAppName)
                    LabeledContent(L10n.t("input.current_source"), value: manager.currentSource?.name ?? "—")
                    LabeledContent(L10n.t("input.current_site"), value: manager.currentHost.isEmpty ? "—" : manager.currentHost)
                    Text(L10n.t(manager.isPaused ? "input.status.paused" : manager.settings.enabled ? manager.statusKey : "input.status.disabled"))
                        .font(.caption).foregroundColor(.secondary)
                    if let issue = manager.issueKey { Label(L10n.t(issue), systemImage: "exclamationmark.triangle").foregroundColor(.orange) }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(L10n.t("input.refresh")) { manager.refreshSources() }
                Button(L10n.t("input.clear_memory")) { manager.clearMemory() }
            }
            Text(L10n.t("input.launcher_hint")).font(.caption).foregroundColor(.secondary)
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("input.apps_hint")).foregroundColor(.secondary)
            HStack {
                Button(L10n.t("input.add_app")) {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.canChooseDirectories = false
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let url = panel.url { manager.addApp(at: url) }
                }
                Button(L10n.t("input.add_current_app")) { manager.addCurrentAppRule() }
            }
            if manager.settings.appRules.isEmpty { emptyState }
            ForEach($manager.settings.appRules) { $rule in
                GroupBox {
                    HStack(spacing: 12) {
                        Toggle(isOn: $rule.enabled) {
                            HStack(spacing: 6) {
                                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "app")
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(.secondary)
                                        .accessibilityHidden(true)
                                }
                                Text(rule.name)
                            }
                        }
                            .lineLimit(1)
                            .help(rule.name + "\n" + rule.bundleID)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker(L10n.t("input.strategy"), selection: $rule.policy) {
                            ForEach(InputSourceAppPolicy.allCases, id: \.self) { policy in Text(policy.title).tag(policy) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .help(L10n.t("input.strategy"))
                        if rule.policy == .fixed {
                            InputSourcePicker(title: L10n.t("input.source"), selection: $rule.sourceID, sources: manager.sources)
                                .labelsHidden()
                                .frame(width: 180)
                                .help(L10n.t("input.source"))
                        }
                        Button(role: .destructive) { manager.settings.appRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                            .help(L10n.t("general.delete"))
                    }.padding(4)
                }
            }
        }
    }

    private var websites: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("input.websites_hint")).foregroundColor(.secondary)
            if !manager.accessibilityGranted {
                Label(L10n.t("input.error.accessibility"), systemImage: "hand.raised").foregroundColor(.orange)
                Button(L10n.t("accessibility.open_settings")) { AccessibilityManager.shared.openAccessibilitySettings() }
            }
            InputSourcePicker(title: L10n.t("input.address_source"), selection: $manager.settings.addressBarSourceID, sources: manager.sources, allowsKeep: true)
            Text(L10n.t("input.address_hint")).font(.caption).foregroundColor(.secondary)
            Button(L10n.t("input.add_website")) {
                websiteDraft = .init(pattern: manager.currentHost, sourceID: manager.currentSource?.id ?? "")
            }
            if manager.settings.websiteRules.isEmpty { emptyState }
            ForEach($manager.settings.websiteRules) { $rule in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(rule.pattern, isOn: $rule.enabled).font(.headline)
                            Spacer()
                            Button { moveWebsite(rule.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(manager.settings.websiteRules.first?.id == rule.id).help(L10n.t("input.move_up"))
                            Button { moveWebsite(rule.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(manager.settings.websiteRules.last?.id == rule.id).help(L10n.t("input.move_down"))
                            Button { websiteDraft = rule } label: { Image(systemName: "pencil") }.help(L10n.t("input.edit"))
                            Button(role: .destructive) { manager.settings.websiteRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                                .help(L10n.t("general.delete"))
                        }
                        Text(rule.match.title + " · " + (InputSourcePolicy.browsers[rule.browserID] ?? L10n.t("input.all_browsers")))
                            .font(.caption).foregroundColor(.secondary)
                        InputSourcePicker(title: L10n.t("input.source"), selection: $rule.sourceID, sources: manager.sources)
                    }.padding(8)
                }
            }
        }
    }

    private var indicator: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("input.indicator_hint")).foregroundColor(.secondary)
            Toggle(L10n.t("input.show_change"), isOn: $manager.settings.showOnChange)
            Toggle(L10n.t("input.show_app"), isOn: $manager.settings.showOnAppSwitch)
            Toggle(L10n.t("input.show_mouse"), isOn: $manager.settings.showOnLongPress)
            Picker(L10n.t("input.position"), selection: $manager.settings.indicatorPosition) {
                ForEach(InputSourceIndicatorPosition.allCases, id: \.self) { position in Text(position.title).tag(position) }
            }
            Toggle(L10n.t("input.abbreviated"), isOn: $manager.settings.indicatorAbbreviated)
            HStack {
                Text(L10n.t("input.duration"))
                Slider(value: $manager.settings.indicatorDuration, in: 0.3...5, step: 0.1)
                Text(String(format: "%.1f s", manager.settings.indicatorDuration)).monospacedDigit().frame(width: 55)
            }
            HStack {
                Text(L10n.t("input.font_size"))
                Slider(value: $manager.settings.indicatorFontSize, in: 12...32, step: 1)
                Text("\(Int(manager.settings.indicatorFontSize)) pt").monospacedDigit().frame(width: 55)
            }
            ColorPicker(L10n.t("input.color"), selection: Binding(get: {
                let value = UInt64(manager.settings.indicatorColor.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x00C553
                return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
            }, set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                manager.settings.indicatorColor = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
            }), supportsOpacity: false)
            Button(L10n.t("input.preview")) { manager.previewIndicator() }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("input.shortcuts_hint")).foregroundColor(.secondary)
            Button(L10n.t("input.add_shortcut")) {
                manager.settings.shortcuts.append(.init(sourceIDs: manager.currentSource.map { [$0.id] } ?? []))
            }
            ForEach($manager.settings.shortcuts) { $shortcut in
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            InputSourceShortcutRecorder(shortcut: shortcut, manager: manager)
                            Button(L10n.t("input.clear_shortcut")) { _ = manager.updateShortcut(shortcut.id, configuration: nil) }
                            Spacer()
                            Button(role: .destructive) { manager.settings.shortcuts.removeAll { $0.id == shortcut.id } } label: { Image(systemName: "trash") }
                                .help(L10n.t("general.delete"))
                        }
                        ForEach(manager.sources) { source in
                            Toggle(source.name, isOn: Binding(get: { shortcut.sourceIDs.contains(source.id) }, set: { selected in
                                if selected { shortcut.sourceIDs.append(source.id) }
                                else { shortcut.sourceIDs.removeAll { $0 == source.id } }
                            }))
                        }
                        if shortcut.sourceIDs.contains(where: { id in !manager.sources.contains(where: { $0.id == id }) }) {
                            Text(L10n.t("input.error.unavailable")).font(.caption).foregroundColor(.orange)
                        }
                        if manager.shortcutIssueIDs.contains(shortcut.id) {
                            Text(L10n.t("input.shortcut_failed")).font(.caption).foregroundColor(.orange)
                        }
                    }.padding(8)
                }
            }
        }
    }

    private var emptyState: some View {
        Text(L10n.t("input.no_rules")).foregroundColor(.secondary).padding(.vertical, 20)
    }

    private func moveWebsite(_ id: UUID, by offset: Int) {
        guard let index = manager.settings.websiteRules.firstIndex(where: { $0.id == id }),
              manager.settings.websiteRules.indices.contains(index + offset) else { return }
        manager.settings.websiteRules.swapAt(index, index + offset)
    }
}

struct InputSourcePicker: View {
    let title: String
    @Binding var selection: String
    let sources: [InputSourceDescriptor]
    var allowsKeep = false

    var body: some View {
        Picker(title, selection: $selection) {
            Text(L10n.t(allowsKeep ? "input.policy.keepCurrent" : "input.choose_source")).tag("")
            ForEach(sources) { source in Text(source.name).tag(source.id) }
            if !selection.isEmpty, !sources.contains(where: { $0.id == selection }) {
                Text(L10n.t("input.missing_source") + " · " + selection).tag(selection)
            }
        }
    }
}

private struct InputSourceWebsiteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: InputSourceWebsiteRule
    let sources: [InputSourceDescriptor]
    let save: (InputSourceWebsiteRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("input.website_rule")).font(.title2)
            Picker(L10n.t("input.browser"), selection: $rule.browserID) {
                Text(L10n.t("input.all_browsers")).tag("")
                ForEach(InputSourcePolicy.browsers.keys.sorted(), id: \.self) { id in Text(InputSourcePolicy.browsers[id] ?? id).tag(id) }
            }
            Picker(L10n.t("input.match_type"), selection: $rule.match) {
                ForEach(InputSourceWebsiteMatch.allCases, id: \.self) { match in Text(match.title).tag(match) }
            }
            TextField(rule.match == .urlPrefix ? "https://example.com/docs" : "example.com", text: $rule.pattern)
                .textFieldStyle(.roundedBorder)
            InputSourcePicker(title: L10n.t("input.source"), selection: $rule.sourceID, sources: sources)
            if !rule.isValid { Text(L10n.t("input.invalid_pattern")).font(.caption).foregroundColor(.orange) }
            HStack {
                Spacer()
                Button(L10n.t("general.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.t("general.save")) { save(rule); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!rule.isValid || !sources.contains { $0.id == rule.sourceID })
            }
        }.padding(24).frame(width: 480)
    }
}

private struct InputSourceShortcutRecorder: View {
    let shortcut: InputSourceShortcut
    @ObservedObject var manager: InputSourceAutomationManager
    @State private var recording = false
    @State private var monitor: Any?
    @State private var recordingToken: UUID?
    @State private var conflict = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(recording ? L10n.t("input.recording") : shortcut.configuration.map { $0.modifiers.displayString + $0.key.displayString } ?? L10n.t("input.record")) {
                if recording { stop() } else { start() }
            }
            if conflict { Text(L10n.t("shortcut.internal_conflict")).font(.caption).foregroundColor(.orange) }
        }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start() {
        recording = true
        conflict = false
        recordingToken = CarbonHotKeyRegistration.beginRecording({ configuration in accept(configuration) }, didEnd: { cleanup() })
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            guard let key = Key(carbonKeyCode: UInt32(event.keyCode)) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard !modifiers.isEmpty else { return nil }
            accept(HotKeyConfiguration(key: key, modifiers: modifiers))
            return nil
        }
    }

    private func accept(_ configuration: HotKeyConfiguration) {
        conflict = !manager.updateShortcut(shortcut.id, configuration: configuration)
        stop()
    }

    private func stop() {
        let token = recordingToken
        cleanup()
        CarbonHotKeyRegistration.endRecording(token)
    }

    private func cleanup() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingToken = nil
        recording = false
    }
}
