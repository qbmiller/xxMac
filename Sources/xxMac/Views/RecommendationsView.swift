import SwiftUI

struct RecommendationCategory: Codable, Identifiable {
    let id: String
    let title: String
    let symbol: String?
    let items: [RecommendationItem]
}

struct RecommendationItem: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let url: String
    let iconURL: String?

    var destination: URL? {
        guard let url = URL(string: url), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }

    var icon: URL? {
        guard let iconURL, let url = URL(string: iconURL), url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }
}

struct RecommendationsDocument: Codable {
    let categories: [RecommendationCategory]
}

@MainActor
final class RecommendationsStore: ObservableObject {
    @Published private(set) var categories: [RecommendationCategory] = []
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var sourceURL: String

    private let configDirectory: ConfigDirectoryManager
    private let session: URLSession
    private let preferences: PreferencesStore
    private static let sourceKey = "RecommendationsSourceURL"
    private static let defaultSourceURL = "https://cf.xiaomi318.com/xxmac/xxmac.json"
    private var refreshID = UUID()

    init(
        configDirectory: ConfigDirectoryManager = .shared,
        session: URLSession = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self.configDirectory = configDirectory
        self.session = session
        self.preferences = preferences
        sourceURL = preferences.string(forKey: Self.sourceKey) ?? Self.defaultSourceURL
    }

    func load() {
        sourceURL = preferences.string(forKey: Self.sourceKey) ?? Self.defaultSourceURL
        let fileURL = configDirectory.recommendationsURL
        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let document = RecommendationsDocument(categories: [
                    RecommendationCategory(id: "tools", title: "工具", symbol: "hammer", items: [
                        RecommendationItem(id: "status-trio", title: "Status Trio", description: "将 Wi-Fi、电池和音量整合到一个原生 macOS 状态图标", url: "https://github.com/lingyired/status-trio", iconURL: "https://github.com/lingyired.png"),
                        RecommendationItem(id: "neat-download-manager", title: "Neat Download Manager", description: "适用于 macOS 和 Windows 的免费下载管理器", url: "https://www.neatdownloadmanager.com/", iconURL: "https://www.neatdownloadmanager.com/favicon.ico")
                    ]),
                    RecommendationCategory(id: "websites", title: "网站", symbol: "globe", items: [
                        RecommendationItem(id: "v2ex", title: "V2EX", description: "技术与创意话题社区", url: "https://www.v2ex.com/", iconURL: "https://www.v2ex.com/favicon.ico"),
                        RecommendationItem(id: "linux-do", title: "Linux.do", description: "技术交流社区", url: "https://linux.do/", iconURL: "https://linux.do/favicon.ico")
                    ])
                ])
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(document).write(to: fileURL, options: .atomic)
            }
            let document = try JSONDecoder().decode(RecommendationsDocument.self, from: Data(contentsOf: fileURL))
            categories = document.categories
            error = nil
        } catch {
            categories = []
            self.error = error.localizedDescription
        }
    }

    func setSourceURL(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host != nil else {
            throw URLError(.badURL)
        }
        sourceURL = trimmed
        refreshID = UUID()
        preferences.set(trimmed, forKey: Self.sourceKey)
        error = nil
    }

    func refresh() async {
        guard let url = URL(string: sourceURL), url.scheme?.lowercased() == "https", url.host != nil else { return }
        let requestID = UUID()
        refreshID = requestID
        isRefreshing = true
        defer { if refreshID == requestID { isRefreshing = false } }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 12
            let (data, response) = try await session.data(for: request)
            guard refreshID == requestID else { return }
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                  data.count <= 1_000_000 else { throw URLError(.badServerResponse) }
            let document = try JSONDecoder().decode(RecommendationsDocument.self, from: data)
            try data.write(to: configDirectory.recommendationsURL, options: .atomic)
            categories = document.categories
            error = nil
        } catch {
            if refreshID == requestID {
                self.error = "远程更新失败，正在显示上次保存的内容：\(error.localizedDescription)"
            }
        }
    }

    var fileURL: URL { configDirectory.recommendationsURL }
}

private enum RecommendationLayout: String, CaseIterable {
    case grid
    case list

    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
    var title: String { self == .grid ? "平铺" : "列表" }
}

struct RecommendationsView: View {
    @ObservedObject var store: RecommendationsStore
    let category: RecommendationCategory?
    @State private var layout: RecommendationLayout = .grid
    @State private var showingSourceSheet = false
    @State private var sourceDraft = ""
    @State private var sourceError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(category?.title ?? "推荐")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("显示方式", selection: $layout) {
                    ForEach(RecommendationLayout.allCases, id: \.self) { option in
                        Image(systemName: option.symbol)
                            .accessibilityLabel(option.title)
                            .help(option.title)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 88)
                .help("切换平铺或列表")
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshing || store.sourceURL.isEmpty)
                .help("从 Cloudflare 重新获取推荐")
                Button {
                    sourceDraft = store.sourceURL
                    sourceError = nil
                    showingSourceSheet = true
                } label: {
                    Image(systemName: "link")
                }
                .help("设置 Cloudflare JSON 地址")
            }
            .padding(.horizontal, 24)
            .frame(height: 58)
            Divider()

            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }

            if let category, !category.items.isEmpty {
                ScrollView {
                    LazyVGrid(columns: layout == .grid ? [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 12)] : [GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        ForEach(category.items) { item in
                            RecommendationRow(item: item, compact: layout == .list)
                        }
                    }
                    .padding(24)
                }
            } else {
                emptyState("暂无推荐", detail: "刷新远程推荐数据", symbol: "star")
            }
        }
        .sheet(isPresented: $showingSourceSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cloudflare 推荐数据").font(.headline)
                TextField("https://example.pages.dev/recommendations.json", text: $sourceDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 480)
                Text("更新远程文件后，打开推荐页或点击刷新即可获取最新内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let sourceError {
                    Text(sourceError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("取消") { showingSourceSheet = false }
                    Button("保存并刷新") {
                        do {
                            try store.setSourceURL(sourceDraft)
                            showingSourceSheet = false
                            Task { await store.refresh() }
                        } catch {
                            sourceError = "请输入有效的 HTTPS JSON 地址"
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
    }

    private func emptyState(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecommendationRow: View {
    let item: RecommendationItem
    let compact: Bool

    var body: some View {
        if let destination = item.destination {
            Link(destination: destination) {
                cardContent
            }
            .buttonStyle(.plain)
            .help("打开 \(item.title)")
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        HStack(alignment: .center, spacing: 12) {
            AsyncImage(url: item.icon) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline)
                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
                if !compact, let host = item.destination?.host {
                    Text(host).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            if item.destination != nil {
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(compact ? 10 : 16)
        .frame(maxWidth: .infinity, minHeight: compact ? 62 : 92, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
