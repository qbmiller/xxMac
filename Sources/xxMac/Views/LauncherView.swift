import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject private var appSearchManager = AppSearchManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @FocusState private var isSearchFocused: Bool

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
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Field
            HStack {
                Image(systemName: viewModel.mode == .clipboard ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.title2)
                    .foregroundColor(viewModel.mode == .clipboard ? .blue : .gray)
                
                TextField(viewModel.mode == .clipboard ? L10n.t("launcher.search_clipboard_placeholder") : L10n.t("launcher.search_placeholder"), text: $viewModel.query)
                    .font(.title2)
                    .textFieldStyle(PlainTextFieldStyle())
                    .id(viewModel.searchID) // Force recreation when session resets
                    .focused($isSearchFocused)
                    .onAppear {
                        focusSearch()
                    }
                    .onSubmit {
                        viewModel.executeSelection()
                    }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()

            if viewModel.mode == .launcher && appSearchManager.isIndexing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.t("clipboard.indexing_apps"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                Divider()
            }
            
            if viewModel.mode == .clipboard {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.results.indices, id: \.self) { index in
                                    let item = viewModel.results[index]
                                    SearchResultRow(
                                        item: item,
                                        isSelected: index == viewModel.selectedIndex
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
                    .frame(width: 360)
                    .frame(maxHeight: 400)

                    Divider()

                    ClipboardDetailPane(item: selectedClipboardItem)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.results.indices, id: \.self) { index in
                                let item = viewModel.results[index]
                                SearchResultRow(item: item, isSelected: index == viewModel.selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        viewModel.selectedIndex = index
                                        viewModel.executeSelection()
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: viewModel.mode == .clipboard ? 920 : 600)
        .background(EffectView(material: .sidebar, blendingMode: .behindWindow))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .id(localization.language)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusLauncherSearch"))) { _ in
            focusSearch()
        }
    }
}

struct SearchResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: item.iconName)
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "return")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue : Color.clear)
        .contentShape(Rectangle())
    }
}

struct ClipboardDetailPane: View {
    let item: SearchItem?

    var body: some View {
        Group {
            if let item, let preview = item.clipboardPreview {
                switch preview {
                case .text(let text):
                    ScrollView {
                        Text(text)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(16)
                    }
                case .image(let filename, _):
                    ClipboardImagePreview(filename: filename)
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
        .background(Color(NSColor.windowBackgroundColor).opacity(0.55))
    }
}

struct ClipboardImagePreview: View {
    let filename: String

    var body: some View {
        let imageURL = ClipboardStorageManager.shared.getImagePath(filename: filename)
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
