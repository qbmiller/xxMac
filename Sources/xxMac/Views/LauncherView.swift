import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject private var appSearchManager = AppSearchManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var appearance = LauncherAppearanceManager.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isSearchFocused: Bool
    @State private var isCommandPressed = false

    private func focusSearch() {
        // Use a slightly longer delay and ensure reset
        isSearchFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isSearchFocused = true
        }
    }

    private var selectedClipboardItem: SearchItem? {
        guard viewModel.mode == .clipboard, viewModel.results.indices.contains(viewModel.selectedIndex) else { return nil }
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

    private var shouldShowLauncherIndexing: Bool {
        viewModel.mode == .launcher && launcherHasQuery && appSearchManager.isIndexing
    }

    private var shouldShowLauncherResults: Bool {
        ((viewModel.mode == .launcher && launcherHasQuery) || viewModel.mode == .snippets) && !viewModel.results.isEmpty
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
                
                TextField(searchPlaceholder, text: $viewModel.query)
                    .font(.system(size: scaledText(36), weight: .light))
                    .textFieldStyle(PlainTextFieldStyle())
                    .id(viewModel.searchID) // Force recreation when session resets
                    .focused($isSearchFocused)
                    .foregroundColor(.white)
                    .onAppear {
                        focusSearch()
                    }
                    .onSubmit {
                        viewModel.executeSelection()
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
            
            if viewModel.mode == .clipboard {
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

                    ClipboardDetailPane(item: selectedClipboardItem)
                        .frame(maxWidth: .infinity, maxHeight: launcherHeight)
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
        .frame(width: viewModel.mode == .clipboard ? max(launcherWidth, 920) : launcherWidth)
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
    }

    private var appIcon: NSImage? {
        guard item.type == .app else { return nil }
        return NSWorkspace.shared.icon(forFile: item.subtitle)
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
                            if fullLength > preview.count {
                                Text(L10n.t("clipboard.preview_truncated"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(preview)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                    }
                case .image(let filename, let thumbnailFilename, _):
                    ClipboardImagePreview(filename: filename, thumbnailFilename: thumbnailFilename)
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
