import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject private var appSearchManager = AppSearchManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var appearance = LauncherAppearanceManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isCommandPressed = false

    private func focusSearch() {
        NotificationCenter.default.post(name: NSNotification.Name("LauncherSearchFieldFocusRequested"), object: nil)
    }

    private var selectedClipboardItem: SearchItem? {
        guard viewModel.mode == .clipboard, viewModel.results.indices.contains(viewModel.selectedIndex) else { return nil }
        return viewModel.results[viewModel.selectedIndex]
    }

    private var selectedSnippetItem: SearchItem? {
        guard viewModel.mode == .snippets, viewModel.results.indices.contains(viewModel.selectedIndex) else { return nil }
        return viewModel.results[viewModel.selectedIndex]
    }

    private var sizeScale: CGFloat {
        CGFloat(appearance.sizeScale)
    }

    private var textScale: CGFloat {
        CGFloat(appearance.textScale)
    }

    private var launcherWidth: CGFloat {
        CGFloat(appearance.launcherWidth)
    }

    private var launcherHeight: CGFloat {
        CGFloat(appearance.launcherHeight)
    }

    private var launcherHasQuery: Bool {
        !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchFieldText: Binding<String> {
        Binding(
            get: { viewModel.searchFieldText },
            set: { viewModel.updateSearchFieldText($0) }
        )
    }

    private var clipboardImageFilter: Binding<Bool> {
        Binding(
            get: { viewModel.isClipboardImageFilterActive },
            set: { viewModel.setClipboardImageFilterEnabled($0) }
        )
    }

    private var shouldShowLauncherIndexing: Bool {
        viewModel.mode == .launcher && launcherHasQuery && appSearchManager.isIndexing
    }

    private var shouldShowLauncherResults: Bool {
        (viewModel.mode == .launcher || viewModel.mode == .snippets) && !viewModel.results.isEmpty
    }

    private var searchIconName: String {
        switch viewModel.mode {
        case .clipboard:
            return "doc.on.clipboard"
        case .snippets:
            return "text.quote"
        case .launcher:
            return "magnifyingglass"
        }
    }

    private var searchPlaceholder: String {
        switch viewModel.mode {
        case .clipboard:
            return L10n.t("launcher.search_clipboard_placeholder")
        case .snippets:
            return L10n.t("launcher.search_snippets_placeholder")
        case .launcher:
            return L10n.t("launcher.search_placeholder")
        }
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * sizeScale
    }

    private func scaledText(_ value: CGFloat) -> CGFloat {
        value * sizeScale * textScale
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: scaled(18)) {
                Image(systemName: searchIconName)
                    .font(.system(size: scaled(34), weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(width: scaled(42), height: scaled(42))
                
                LauncherSearchField(
                    placeholder: searchPlaceholder,
                    text: searchFieldText,
                    searchID: viewModel.searchID,
                    fontSize: scaledText(36),
                    onSubmit: {
                        viewModel.executeSelection()
                    },
                    onCancel: {
                        NotificationCenter.default.post(name: NSNotification.Name("CloseLauncher"), object: nil)
                    },
                    onMoveDown: {
                        viewModel.selectNext()
                    },
                    onMoveUp: {
                        viewModel.selectPrevious()
                    },
                    onPageDown: {
                        viewModel.selectNextPage()
                    },
                    onPageUp: {
                        viewModel.selectPreviousPage()
                    }
                )
                .frame(height: scaled(48))

                if let availableVersion = updateManager.availableVersion {
                    Button {
                        NSWorkspace.shared.open(UpdateManager.releasesURL)
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: scaled(24), weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: scaled(32), height: scaled(32))
                    .help(L10n.f("launcher.update_available_format", availableVersion))
                    .accessibilityLabel(L10n.f("launcher.update_available_format", availableVersion))
                }

                if viewModel.mode == .clipboard {
                    Toggle(isOn: clipboardImageFilter) {
                        Image(systemName: "photo")
                            .font(.system(size: scaled(20), weight: .semibold))
                            .foregroundColor(.white.opacity(viewModel.isClipboardImageFilterActive ? 1 : 0.72))
                    }
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                    .padding(.horizontal, scaled(10))
                    .frame(height: scaled(42))
                    .background(
                        RoundedRectangle(cornerRadius: scaled(7), style: .continuous)
                            .fill(
                                viewModel.isClipboardImageFilterActive
                                    ? Color.accentColor.opacity(0.28)
                                    : Color.white.opacity(0.08)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: scaled(7), style: .continuous)
                            .stroke(
                                viewModel.isClipboardImageFilterActive
                                    ? Color.accentColor.opacity(0.85)
                                    : Color.white.opacity(0.16),
                                lineWidth: viewModel.isClipboardImageFilterActive ? 1.5 : 1
                            )
                    )
                    .help(L10n.t("clipboard.filter_images"))
                    .accessibilityLabel(L10n.t("clipboard.filter_images"))
                }
            }
            .padding(.horizontal, scaled(28))
            .padding(.vertical, scaled(22))
            .background(Color.white.opacity(0.08))

            if shouldShowLauncherIndexing {
                Divider()
                    .overlay(Color.white.opacity(0.12))

                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.t("common.indexing_apps"))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                    Spacer()
                }
                .padding(.horizontal, scaled(28))
                .padding(.vertical, scaled(6))
            }
            
            if viewModel.mode == .clipboard || viewModel.mode == .snippets {
                Divider()
                    .overlay(Color.white.opacity(0.12))

                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.results.indices, id: \.self) { index in
                                    let item = viewModel.results[index]
                                    SearchResultRow(
                                        item: item,
                                        isSelected: index == viewModel.selectedIndex,
                                        showsRevealInFinderAction: false
                                    )
                                    .id(index)
                                    .onTapGesture {
                                        viewModel.selectedIndex = index
                                        viewModel.executeSelection()
                                    }
                                }
                            }
                        }
                        .onChange(of: viewModel.selectedIndex) { newIndex in
                            withAnimation {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                    .frame(width: min(360, launcherWidth * 0.45))
                    .frame(maxHeight: launcherHeight)

                    Divider()
                        .overlay(Color.white.opacity(0.12))

                    if viewModel.mode == .clipboard {
                        ClipboardDetailPane(item: selectedClipboardItem)
                            .frame(maxWidth: .infinity, maxHeight: launcherHeight)
                    } else {
                        SnippetDetailPane(item: selectedSnippetItem)
                            .frame(maxWidth: .infinity, maxHeight: launcherHeight)
                    }
                }
            } else if shouldShowLauncherResults {
                Divider()
                    .overlay(Color.white.opacity(0.12))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.results.indices, id: \.self) { index in
                                let item = viewModel.results[index]
                                SearchResultRow(
                                    item: item,
                                    isSelected: index == viewModel.selectedIndex,
                                    showsRevealInFinderAction: isCommandPressed && item.type == .app
                                )
                                    .id(index)
                                    .onTapGesture {
                                        viewModel.selectedIndex = index
                                        viewModel.executeSelection()
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: launcherHeight)
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                .frame(maxHeight: launcherHeight)
            }
        }
        .frame(width: viewModel.mode == .clipboard || viewModel.mode == .snippets ? max(launcherWidth, 920) : launcherWidth)
        .background(
            ZStack {
                if reduceTransparency {
                    appearance.backgroundColor
                } else {
                    EffectView(material: .hudWindow, blendingMode: .behindWindow)
                    appearance.backgroundColor.opacity(appearance.opacity)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: scaled(18), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: scaled(18), style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: scaled(26), x: 0, y: scaled(18))
        .id(localization.language)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusLauncherSearch"))) { _ in
            focusSearch()
        }
        .onAppear {
            isCommandPressed = NSEvent.modifierFlags.contains(.command)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            isCommandPressed = false
        }
        .background(ModifierKeyMonitor(isCommandPressed: $isCommandPressed))
    }
}

enum LauncherSearchFieldFocus {
    static func focus(_ textField: NSTextField?) {
        guard let textField, let window = textField.window else { return }

        if let editor = textField.currentEditor(), window.firstResponder === editor {
            return
        }

        window.makeFirstResponder(textField)
    }
}

enum LauncherSearchFieldTextSync {
    static func update(_ textField: NSTextField, text: String) {
        guard textField.stringValue != text else { return }

        textField.stringValue = text
        textField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }
}

private struct LauncherSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let searchID: UUID
    let fontSize: CGFloat
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onMoveDown: () -> Void
    let onMoveUp: () -> Void
    let onPageDown: () -> Void
    let onPageUp: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .white
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LauncherSearchFieldFocusRequested"),
            object: nil,
            queue: .main
        ) { [weak textField] _ in
            LauncherSearchFieldFocus.focus(textField)
        }
        DispatchQueue.main.async {
            LauncherSearchFieldFocus.focus(textField)
        }
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        LauncherSearchFieldTextSync.update(textField, text: text)
        textField.font = NSFont.systemFont(ofSize: fontSize, weight: .light)
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.42),
                .font: NSFont.systemFont(ofSize: fontSize, weight: .light)
            ]
        )

        if context.coordinator.lastSearchID != searchID {
            context.coordinator.lastSearchID = searchID
            DispatchQueue.main.async {
                LauncherSearchFieldFocus.focus(textField)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherSearchField
        var lastSearchID: UUID?
        var focusObserver: Any?

        init(parent: LauncherSearchField) {
            self.parent = parent
            self.lastSearchID = parent.searchID
        }

        deinit {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.pageDown(_:)):
                parent.onPageDown()
                return true
            case #selector(NSResponder.pageUp(_:)):
                parent.onPageUp()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

struct SearchResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    let showsRevealInFinderAction: Bool
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
        HStack(spacing: scaled(18)) {
            Circle()
                .fill(Color.red)
                .frame(width: scaled(9), height: scaled(9))
                .opacity(isSelected ? 1 : 0)

            SearchResultIcon(item: item)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: scaledText(27), weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.white.opacity(isSelected ? 1 : 0.86))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: scaledText(17), weight: .medium))
                        .foregroundColor(.white.opacity(isSelected ? 0.78 : 0.56))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if isSelected {
                if showsRevealInFinderAction {
                    HStack(spacing: scaled(6)) {
                        Image(systemName: "folder")
                            .font(.system(size: scaled(16), weight: .semibold))
                        Text("Reveal in Finder")
                            .font(.system(size: scaledText(14), weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.72))
                } else {
                    Image(systemName: "return")
                        .font(.system(size: scaled(18), weight: .semibold))
                        .foregroundColor(.white.opacity(0.68))
                }
            }
        }
        .padding(.horizontal, scaled(28))
        .padding(.vertical, scaled(10))
        .frame(height: scaled(86))
        .background(isSelected ? Color.white.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
    }
}

private struct ModifierKeyMonitor: NSViewRepresentable {
    @Binding var isCommandPressed: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { event in
            DispatchQueue.main.async {
                isCommandPressed = event.modifierFlags.contains(.command)
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var monitor: Any?

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

struct SearchResultIcon: View {
    let item: SearchItem
    @ObservedObject private var appearance = LauncherAppearanceManager.shared
    @ObservedObject private var iconCache = QuickShortcutIconCacheManager.shared

    private var sizeScale: CGFloat {
        CGFloat(appearance.sizeScale)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * sizeScale
    }

    var body: some View {
        Group {
            if item.type == .app, let image = appIcon {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let image = cachedIcon {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(scaled(8))
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: scaled(12), style: .continuous))
            } else {
                Image(systemName: item.iconName)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white.opacity(0.84))
                    .padding(scaled(10))
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: scaled(12), style: .continuous))
            }
        }
        .frame(width: scaled(50), height: scaled(50))
        .id(iconCache.refreshToken)
    }

    private var appIcon: NSImage? {
        guard item.type == .app else { return nil }
        return NSWorkspace.shared.icon(forFile: item.subtitle)
    }

    private var cachedIcon: NSImage? {
        guard let iconFileURL = item.iconFileURL else { return nil }
        return NSImage(contentsOf: iconFileURL)
    }
}

struct ClipboardDetailPane: View {
    let item: SearchItem?

    var body: some View {
        Group {
            if let item, let preview = item.clipboardPreview {
                switch preview {
                case .text(_, let preview, let fullLength):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            let isTruncated = fullLength > preview.count
                            if isTruncated {
                                Text(L10n.t("clipboard.preview_truncated"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if isTruncated {
                                Text(verbatim: preview)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            } else {
                                Text(verbatim: preview)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(16)
                    }
                case .image(let filename, let thumbnailFilename, _, let ocrStatus, let ocrTextPreview):
                    VStack(spacing: 0) {
                        ClipboardImagePreview(filename: filename, thumbnailFilename: thumbnailFilename)
                        ClipboardOCRSummary(status: ocrStatus, textPreview: ocrTextPreview)
                    }
                        .id(filename)
                }
            } else {
                VStack {
                    Spacer()
                    Text(L10n.t("clipboard.select_item_preview"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .background(Color.white.opacity(0.08))
        .id(item?.id)
    }
}

struct SnippetDetailPane: View {
    let item: SearchItem?

    var body: some View {
        Group {
            if let content = item?.snippetPreview?.content {
                ScrollView {
                    Text(content.isEmpty ? L10n.t("snippets.empty_content") : content)
                        .font(.body)
                        .foregroundColor(content.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(16)
                }
            } else {
                VStack {
                    Spacer()
                    Text(L10n.t("snippets.select_item_preview"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .background(Color.white.opacity(0.08))
        .id(item?.id)
    }
}

struct ClipboardOCRSummary: View {
    let status: ClipboardOCRStatus?
    let textPreview: String?

    var body: some View {
        if let displayText {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(.caption)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
        }
    }

    private var title: String {
        switch status {
        case .pending:
            return L10n.t("clipboard.ocr_status_pending")
        case .ready:
            return L10n.t("clipboard.ocr_recognized_text")
        case .failed:
            return L10n.t("clipboard.ocr_status_failed")
        case .skipped:
            return L10n.t("clipboard.ocr_status_skipped")
        case nil:
            return ""
        }
    }

    private var displayText: String? {
        switch status {
        case .ready:
            return textPreview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? textPreview : nil
        case .pending, .failed:
            return title
        case .skipped, nil:
            return nil
        }
    }
}

struct ClipboardImagePreview: View {
    let filename: String
    let thumbnailFilename: String?

    var body: some View {
        let imageURL = imageURL
        let image = NSImage(contentsOf: imageURL)

        return Group {
            if let image {
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: proxy.size.width - 32, maxHeight: proxy.size.height - 48)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(16)
            } else {
                VStack {
                    Spacer()
                    Text(L10n.t("clipboard.image_unavailable"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var imageURL: URL {
        if let thumbnailFilename {
            return ClipboardStorageManager.shared.getThumbnailPath(filename: thumbnailFilename)
        }
        return ClipboardStorageManager.shared.getImagePath(filename: filename)
    }
}

// Helper for Visual Effect
struct EffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
