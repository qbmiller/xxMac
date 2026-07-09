import SwiftUI
import HotKey

// MARK: - Main View

struct SettingsView: View {
    @State private var selectedTool: ToolOption? = ToolOption.allTools.first
    @State private var selectedFunction: ToolFunction? = ToolOption.allTools.first?.functions.first
    @State private var selectedSnippetCollectionID: SnippetCollection.ID?
    @State private var selectedQuickShortcutID: QuickShortcut.ID?
    @State private var isToolSidebarVisible = true
    @State private var monitor: Any?
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var snippetManager = SnippetManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            sidebarToggleRail

            Divider()

            HSplitView {
                if isToolSidebarVisible {
                    toolSidebar
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                }

                secondarySidebar
                    .frame(minWidth: 220, idealWidth: secondaryColumnWidth, maxWidth: 380)

                detailContent
                    .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1050, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .id(localization.language)
        .onAppear {
            setupWindowCloseMonitor()
            ensureSelection()
        }
        .onDisappear {
            removeMonitor()
        }
        .onChange(of: selectedTool) { newValue in
            // When tool changes, select the first function of that tool
            if let tool = newValue, tool.type == .snippets {
                ensureSnippetCollectionSelection()
                selectedQuickShortcutID = nil
            } else if let tool = newValue, tool.type == .quickShortcut {
                ensureQuickShortcutSelection()
            } else if let tool = newValue, let firstFunc = tool.functions.first {
                selectedFunction = firstFunc
            }
        }
        .onChange(of: snippetManager.collections) { _ in
            ensureSnippetCollectionSelection()
        }
        .onChange(of: QuickShortcutManager.shared.items) { _ in
            ensureQuickShortcutSelection()
        }
    }

    private var secondaryColumnWidth: CGFloat {
        switch selectedTool?.type {
        case .quickShortcut:
            return 300
        case .snippets:
            return 260
        default:
            return 240
        }
    }

    private var sidebarToggleRail: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isToolSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(L10n.t("settings.toggle_sidebar"))
            .padding(.top, 12)

            Spacer()
        }
        .frame(width: 48)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var toolSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("settings.tools"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            List(selection: $selectedTool) {
                ForEach(ToolOption.allTools) { tool in
                    Label(tool.type.displayName, systemImage: tool.type.icon)
                        .padding(.vertical, 4)
                        .tag(tool)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedTool = tool
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var secondarySidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedTool?.type.displayName ?? L10n.t("settings.select_tool"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            secondaryContent
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var secondaryContent: some View {
        if let tool = selectedTool {
            if tool.type == .snippets {
                SnippetCollectionSidebar(selection: $selectedSnippetCollectionID)
            } else if tool.type == .quickShortcut {
                QuickShortcutItemsSidebar(selection: $selectedQuickShortcutID)
            } else {
                List(selection: $selectedFunction) {
                    ForEach(tool.functions) { function in
                        Label(function.name, systemImage: function.icon)
                            .padding(.vertical, 4)
                            .tag(function)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedFunction = function
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        } else {
            VStack {
                Spacer()
                Text(L10n.t("settings.select_tool"))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if selectedTool?.type == .snippets {
            SnippetsSettingsView(selectedCollectionID: $selectedSnippetCollectionID)
        } else if selectedTool?.type == .quickShortcut {
            QuickShortcutDetailView(selectedItemID: $selectedQuickShortcutID)
        } else if let function = selectedFunction {
            ConfigurationView(function: function)
        } else {
            Text(L10n.t("settings.select_function"))
                .foregroundColor(.secondary)
        }
    }
    
    private func ensureSelection() {
        if selectedTool == nil {
            selectedTool = ToolOption.allTools.first
        }
        if selectedFunction == nil, let tool = selectedTool {
            selectedFunction = tool.functions.first
        }
        ensureSnippetCollectionSelection()
        ensureQuickShortcutSelection()
    }

    private func ensureSnippetCollectionSelection() {
        guard selectedTool?.type == .snippets else { return }
        if selectedSnippetCollectionID == nil ||
            !snippetManager.collections.contains(where: { $0.id == selectedSnippetCollectionID }) {
            selectedSnippetCollectionID = snippetManager.collections.first?.id
        }
    }

    private func ensureQuickShortcutSelection() {
        guard selectedTool?.type == .quickShortcut else { return }
        if selectedQuickShortcutID == nil ||
            !QuickShortcutManager.shared.items.contains(where: { $0.id == selectedQuickShortcutID }) {
            selectedQuickShortcutID = QuickShortcutManager.shared.items.first?.id
        }
    }
    
    private func setupWindowCloseMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC
                guard NSApp.keyWindow?.sheetParent == nil else {
                    return event
                }
                NSApp.keyWindow?.close()
                return nil
            }
            return event
        }
    }
    
    private func removeMonitor() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct SnippetCollectionSidebar: View {
    @ObservedObject private var manager = SnippetManager.shared
    @Binding var selection: SnippetCollection.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if let selection,
                       let collection = manager.collections.first(where: { $0.id == selection }) {
                        manager.removeCollection(collection)
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                Button {
                    manager.addCollection(named: L10n.t("snippets.new_collection"))
                    selection = manager.collections.last?.id
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $selection) {
                ForEach(manager.collections) { collection in
                    SnippetCollectionSidebarRow(collection: collection)
                        .tag(collection.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                manager.removeCollection(collection)
                            } label: {
                                Text(L10n.t("snippets.delete_collection"))
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct SnippetCollectionSidebarRow: View {
    @ObservedObject private var manager = SnippetManager.shared
    let collection: SnippetCollection

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                TextField(L10n.t("snippets.collection_name"), text: Binding(
                    get: { collection.name },
                    set: { manager.updateCollection(collection, name: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.body)

                Text(L10n.f("snippets.items_count_format", manager.entries(in: collection).count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 3)
        } icon: {
            Image(systemName: "folder")
        }
    }
}

// MARK: - About View

struct AboutSettingsView: View {
    @State private var isCheckingForUpdates = false
    @State private var updateMessage: String?
    private let releaseURL = URL(string: "https://github.com/qbmiller/xxMac/releases")!
    
    var body: some View {
        VStack(spacing: 24) {
            // App Icon & Name
            VStack(spacing: 12) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: "command")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                }
                
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "xxMac")
                    .font(.title)
                    .fontWeight(.bold)
            }
            .padding(.top, 20)
            
            // Info Grid
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(label: L10n.t("about.author_label"), value: "Miller")
                InfoRow(label: L10n.t("about.version_label"), value: currentVersion)
                InfoRow(label: L10n.t("about.build_label"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                InfoRow(label: L10n.t("about.last_updated_label"), value: Bundle.main.object(forInfoDictionaryKey: "XXLastUpdated") as? String ?? "2026-02-09")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .frame(maxWidth: 400)
            
            // Update Section
            VStack(spacing: 12) {
                Text(releaseURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                Button(action: checkForUpdates) {
                    HStack {
                        if isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isCheckingForUpdates ? L10n.t("about.checking") : L10n.t("about.check_updates"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCheckingForUpdates)

                if let message = updateMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(L10n.t("about.copyright"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func checkForUpdates() {
        Task {
            await loadLatestRelease()
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @MainActor
    private func loadLatestRelease() async {
        isCheckingForUpdates = true
        updateMessage = nil

        do {
            let release = try await GitHubRelease.latest()
            if isNewerVersion(release.version, than: currentVersion) {
                updateMessage = L10n.f("about.update_available_format", release.version)
            } else {
                updateMessage = L10n.f("about.up_to_date_format", currentVersion)
            }
        } catch {
            updateMessage = L10n.t("about.update_check_failed")
        }

        isCheckingForUpdates = false
    }

    private func isNewerVersion(_ remoteVersion: String, than localVersion: String) -> Bool {
        let remoteParts = versionParts(remoteVersion)
        let localParts = versionParts(localVersion)
        let count = max(remoteParts.count, localParts.count)

        for index in 0..<count {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart {
                return remotePart > localPart
            }
        }

        return false
    }

    private func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}

private struct GitHubRelease {
    let tagName: String

    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    static func latest() async throws -> GitHubRelease {
        let url = URL(string: "https://github.com/qbmiller/xxMac/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "HEAD"

        let delegate = LatestReleaseRedirectDelegate()
        let (_, response) = try await URLSession.shared.data(for: request, delegate: delegate)
        let tagURL = delegate.redirectURL ?? response.url
        guard let tagName = tagURL?.lastPathComponent,
              tagURL?.path.contains("/releases/tag/") == true else {
            throw URLError(.badURL)
        }

        return GitHubRelease(tagName: tagName)
    }
}

private final class LatestReleaseRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private(set) var redirectURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard 300..<400 ~= response.statusCode,
              let url = request.url else {
            return request
        }

        redirectURL = url
        return nil
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct ConfigurationView: View {
    let function: ToolFunction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(function.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
            
            configurationContent
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var configurationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                configurationBody
            }
            .padding()
        }
    }

    @ViewBuilder
    private var configurationBody: some View {
        switch function.type {
        case .commonConfig:
            CommonSettingsView()
        case .commonShortcuts:
            CommonShortcutSettingsView()
        case .commonLanguage:
            LanguageSettingsView()
        case .searchPaths:
            SearchPathsSettingsView()
        case .wmShortcuts:
            HotKeySettingsView()
        case .shortcutDetectiveGeneral:
            ShortcutDetectiveSettingsView()
        case .clipboardGeneral:
            ClipboardSettingsView()
        case .snippetsLibrary:
            SnippetsSettingsView(selectedCollectionID: .constant(SnippetManager.shared.collections.first?.id))
        case .quickShortcutLibrary:
            QuickShortcutDetailView(selectedItemID: .constant(QuickShortcutManager.shared.items.first?.id))
        case .launcherApps:
            AppLauncherSettingsView()
        case .launcherAppearance:
            LauncherAppearanceSettingsView()
        case .calendarGeneral:
            CalendarFeatureView(showsSettings: true)
        case .lockAIGeneral:
            LockAISettingsView()
        case .lockAIScreen:
            LockAIScreenSettingsView()
        case .aboutInfo:
            AboutSettingsView()
        default:
            VStack(spacing: 20) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text(L10n.f("settings.configuration_coming_soon", function.name))
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }
}

// MARK: - Subviews

struct SearchPathsSettingsView: View {
    @ObservedObject var appSearchManager = AppSearchManager.shared
    @State private var newPath: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("searchpaths.description"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 0) {
                ForEach(appSearchManager.searchPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.blue)
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: {
                            appSearchManager.removePath(path)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            HStack {
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    
                    if panel.runModal() == .OK {
                        if let url = panel.url {
                            appSearchManager.addPath(url.path)
                        }
                    }
                }) {
                    Label(L10n.t("searchpaths.add_path"), systemImage: "plus")
                }
                .controlSize(.large)
                
                Button(L10n.t("searchpaths.reset_defaults")) {
                    appSearchManager.resetPaths()
                }
                .controlSize(.large)
                
                Spacer()
            }
            .padding(.top, 8)
        }
    }
}

struct HotKeySettingsView: View {
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(WindowAction.windowManagementCases, id: \.self) { action in
                HStack {
                    Text(action.displayName)
                        .frame(width: 140, alignment: .trailing)
                        .foregroundColor(.secondary)
                    
                    HotKeyRecorderView(action: action)
                        .frame(maxWidth: 200)
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                
                if action != WindowAction.windowManagementCases.last {
                    Divider()
                }
            }
            
            Divider()
                .padding(.vertical, 20)
            
            HStack {
                Button(L10n.t("hotkey.restore_defaults")) {
                    hotKeyManager.setupDefaultConfigurations()
                    hotKeyManager.saveConfigurations()
                    hotKeyManager.refreshHotKeys()
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct CommonShortcutSettingsView: View {
    @ObservedObject var hotKeyManager = HotKeyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("common_shortcuts.desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(WindowAction.commonShortcutCases, id: \.self) { action in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.displayName)
                            if action == .pasteFinderPath {
                                Text(L10n.t("common_shortcuts.paste_finder_path_desc"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        HotKeyRecorderView(action: action)
                            .frame(maxWidth: 200)
                    }
                    .padding(.vertical, 10)

                    if action != WindowAction.commonShortcutCases.last {
                        Divider()
                    }
                }

                Divider()
                    .padding(.vertical, 20)

                HStack {
                    Button(L10n.t("hotkey.restore_defaults")) {
                        WindowAction.commonShortcutCases.compactMap { action -> (WindowAction, HotKeyConfiguration)? in
                            guard let configuration = hotKeyManager.defaultConfigurationForUserReset(action) else {
                                return nil
                            }
                            return (action, configuration)
                        }.forEach { action, configuration in
                            hotKeyManager.updateConfiguration(for: action, key: configuration.key, modifiers: configuration.modifiers)
                        }
                    }
                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            Spacer()
        }
    }
}

struct LockAISettingsView: View {
    @ObservedObject private var manager = LockAIManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("lock_ai.desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.t("lock_ai.hotkey"))
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .trailing)
                    HotKeyRecorderView(action: .lockAI)
                        .frame(maxWidth: 200)
                    Spacer()
                }

                HStack {
                    Button {
                        manager.lock()
                    } label: {
                        Label(L10n.t("lock_ai.lock_now"), systemImage: "lock.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            Text(L10n.t("lock_ai.note"))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

struct LockAIScreenSettingsView: View {
    @ObservedObject private var manager = LockAIManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("lock_ai.screen_desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                TextField(L10n.t("lock_ai.status_text"), text: $manager.statusText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            Spacer()
        }
    }
}

struct ShortcutDetectiveSettingsView: View {
    @ObservedObject var shortcutDetectiveManager = ShortcutDetectiveManager.shared

    private var detectionTimeString: String {
        guard let lastDetection = shortcutDetectiveManager.lastDetection else { return "-" }
        return lastDetection.timestamp.formatted(date: .abbreviated, time: .standard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(L10n.t("shortcut.enable"), isOn: $shortcutDetectiveManager.isEnabled)

            Text(L10n.t("shortcut.desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            if shortcutDetectiveManager.isEnabled {
                if let lastDetection = shortcutDetectiveManager.lastDetection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t("shortcut.last_detection"))
                            .font(.headline)
                        Text(L10n.f("shortcut.action_format", lastDetection.displayActionName))
                        Text(L10n.f("shortcut.hotkey_format", lastDetection.hotkeyDisplay))
                        Text(L10n.f("shortcut.app_format", lastDetection.handlerAppName))
                        Text(L10n.f("shortcut.bundle_format", lastDetection.handlerBundleIdentifier))
                        Text(L10n.f("shortcut.frontmost_format", lastDetection.frontmostAppName))
                        if lastDetection.isBackgroundHandler {
                            Text(L10n.t("shortcut.background_handler"))
                                .foregroundColor(.orange)
                        }
                        if lastDetection.isSynthesized {
                            Text(L10n.t("shortcut.synthesized"))
                                .foregroundColor(.orange)
                        }
                        if !lastDetection.suspectedHandlers.isEmpty {
                            Text(L10n.f("shortcut.suspects_format", lastDetection.suspectedHandlers.joined(separator: ", ")))
                                .foregroundColor(.secondary)
                        }
                        Text(L10n.f("shortcut.time_format", detectionTimeString))
                            .foregroundColor(.secondary)
                    }
                    .font(.body)
                } else {
                    Text(L10n.t("shortcut.none"))
                        .foregroundColor(.secondary)
                }

                Button(L10n.t("shortcut.clear")) {
                    shortcutDetectiveManager.clearLastDetection()
                }
                .disabled(shortcutDetectiveManager.lastDetection == nil)
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct LauncherAppearanceSettingsView: View {
    @ObservedObject private var appearance = LauncherAppearanceManager.shared

    private var colorBinding: Binding<Color> {
        Binding(
            get: { appearance.backgroundColor },
            set: { newValue in
                if let nsColor = NSColor(newValue).usingColorSpace(.sRGB) {
                    appearance.setBackgroundColor(nsColor)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("launcher_appearance.desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                ColorPicker(L10n.t("launcher_appearance.background"), selection: colorBinding, supportsOpacity: false)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("launcher_appearance.size"))
                        Spacer()
                        Text("\(Int(appearance.sizeScale * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $appearance.sizeScale, in: LauncherAppearanceManager.sizeScaleRange, step: 0.01)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("launcher_appearance.text_size"))
                        Spacer()
                        Text("\(Int(appearance.textScale * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $appearance.textScale, in: LauncherAppearanceManager.textScaleRange, step: 0.01)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("launcher_appearance.width"))
                        Spacer()
                        Text("\(Int(appearance.launcherWidth)) px")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $appearance.launcherWidth, in: 560...980, step: 10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("launcher_appearance.height"))
                        Spacer()
                        Text("\(Int(appearance.launcherHeight)) px")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $appearance.launcherHeight, in: 220...520, step: 10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("launcher_appearance.opacity"))
                        Spacer()
                        Text("\(Int(appearance.opacity * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $appearance.opacity, in: 0.35...0.95, step: 0.01)
                }

                LauncherAppearancePreview()

                HStack {
                    Button(L10n.t("launcher_appearance.restore_defaults")) {
                        appearance.reset()
                    }
                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            Spacer()
        }
    }
}

private struct LauncherAppearancePreview: View {
    @ObservedObject private var appearance = LauncherAppearanceManager.shared

    private var sizeScale: CGFloat {
        CGFloat(appearance.sizeScale)
    }

    private var textScale: CGFloat {
        CGFloat(appearance.textScale)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * sizeScale
    }

    private func scaledText(_ value: CGFloat) -> CGFloat {
        value * sizeScale * textScale
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: scaled(12)) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: scaled(22), weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                Text("xxMac")
                    .font(.system(size: scaledText(28), weight: .light))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(scaled(16))
            .background(Color.white.opacity(0.08))

            HStack(spacing: scaled(12)) {
                Image(systemName: "app.fill")
                    .font(.system(size: scaled(22), weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: scaled(36), height: scaled(36))
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacEfficiencyTool")
                        .font(.system(size: scaledText(17), weight: .semibold))
                        .foregroundColor(.white)
                    Text("/Applications/MacEfficiencyTool.app")
                        .font(.system(size: scaledText(12)))
                        .foregroundColor(.white.opacity(0.64))
                }
                Spacer()
                Image(systemName: "return")
                    .font(.system(size: scaled(16), weight: .semibold))
                    .foregroundColor(.white.opacity(0.68))
            }
            .padding(scaled(16))
            .background(Color.white.opacity(0.14))
        }
        .frame(width: 420)
        .background(appearance.backgroundColor.opacity(appearance.opacity))
        .clipShape(RoundedRectangle(cornerRadius: scaled(14), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: scaled(14), style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }
}

struct HotKeyRecorderView: View {
    let action: WindowAction
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pauseToken: UUID?
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack {
                    Spacer()
            if isRecording {
                        Text(L10n.t("hotkey.type_hotkey"))
                            .foregroundColor(.blue)
                    } else {
                        if let config = hotKeyManager.configurations[action] {
                            Text(config.modifiers.displayString + config.key.displayString)
                                .fontWeight(.medium)
                        } else {
                            Text(L10n.t("hotkey.click_to_record"))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(isRecording ? Color.blue.opacity(0.1) : Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            if let _ = hotKeyManager.configurations[action], !isRecording {
                Button(action: {
                    hotKeyManager.removeConfiguration(for: action)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray.opacity(0.4))
                        .padding(.horizontal, 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .onDisappear {
            if isRecording {
                stopRecording()
            }
        }
    }
    
    func startRecording() {
        isRecording = true
        pauseToken = hotKeyManager.pauseHotKeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if isRecording {
                if event.keyCode == 53 { // ESC
                    stopRecording()
                    return nil
                }
                
                // Allow backspace or delete to clear
                if event.keyCode == 51 || event.keyCode == 117 {
                    hotKeyManager.removeConfiguration(for: action)
                    stopRecording()
                    return nil
                }

                if let key = Key(carbonKeyCode: UInt32(event.keyCode)) {
                    hotKeyManager.updateConfiguration(for: action, key: key, modifiers: event.modifierFlags)
                    stopRecording()
                    return nil
                }
            }
            return event
        }
    }
    
    func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        hotKeyManager.resumeHotKeys(pauseToken)
        pauseToken = nil
    }
}
