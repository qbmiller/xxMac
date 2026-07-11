import AppKit
import Foundation
import OSLog

final class QuickShortcutIconCacheManager: ObservableObject {
    static let shared = QuickShortcutIconCacheManager()

    @Published private(set) var refreshToken = UUID()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "QuickShortcutIcon")
    private let fileManager: FileManager
    private let configDirectoryManager: ConfigDirectoryManager
    private let stateQueue = DispatchQueue(label: "xxmac.quickShortcutIconCache")
    private var inFlightKeys: Set<String> = []
    private var generations: [UUID: Int] = [:]

    init(
        fileManager: FileManager = .default,
        configDirectoryManager: ConfigDirectoryManager = .shared
    ) {
        self.fileManager = fileManager
        self.configDirectoryManager = configDirectoryManager
    }

    func cachedIconURL(for item: QuickShortcut) -> URL? {
        guard item.actionType == .webSearch,
              let url = iconFileURL(for: item),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func iconURL(for item: QuickShortcut) -> URL? {
        guard item.actionType == .webSearch else { return nil }
        return iconFileURL(for: item)
    }

    func ensureIconsCached(for items: [QuickShortcut]) {
        for item in items where item.actionType == .webSearch {
            ensureIconCached(for: item)
        }
    }

    func ensureIconCached(for item: QuickShortcut) {
        guard item.actionType == .webSearch,
              let host = webSearchHost(for: item),
              let iconFileURL = iconFileURL(for: item),
              !fileManager.fileExists(atPath: iconFileURL.path) else {
            return
        }

        let inFlightKey = iconFileURL.path
        let downloadGeneration = stateQueue.sync { () -> Int? in
            guard !inFlightKeys.contains(inFlightKey) else { return nil }
            inFlightKeys.insert(inFlightKey)
            return generations[item.id, default: 0]
        }
        guard let downloadGeneration else { return }

        downloadIcon(for: host, itemID: item.id, generation: downloadGeneration, destinationURL: iconFileURL)
    }

    func removeIcon(for item: QuickShortcut) {
        let prefix = item.id.uuidString + "-"
        stateQueue.sync {
            generations[item.id, default: 0] += 1
            inFlightKeys = inFlightKeys.filter { key in
                !URL(fileURLWithPath: key).lastPathComponent.hasPrefix(prefix)
            }
        }

        guard let files = try? fileManager.contentsOfDirectory(
            at: configDirectoryManager.quickShortcutIconsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: file)
        }
        publishRefresh()
    }

    func webSearchHost(for item: QuickShortcut) -> String? {
        guard item.actionType == .webSearch else { return nil }
        let renderedTemplate = item.payload.replacingOccurrences(of: "{query}", with: "xxmac")
        guard let url = URL(string: renderedTemplate),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        return host
    }

    private func iconFileURL(for item: QuickShortcut) -> URL? {
        guard let host = webSearchHost(for: item) else { return nil }
        let safeHost = host.map { character -> Character in
            character.isLetter || character.isNumber || character == "." || character == "-" ? character : "-"
        }
        let fileName = "\(item.id.uuidString)-\(String(safeHost)).png"
        return configDirectoryManager.quickShortcutIconsDirectoryURL.appendingPathComponent(fileName)
    }

    private func downloadIcon(for host: String, itemID: UUID, generation: Int, destinationURL: URL) {
        downloadIcon(
            from: faviconURLs(for: host),
            host: host,
            itemID: itemID,
            generation: generation,
            destinationURL: destinationURL
        )
    }

    func faviconURLs(for host: String) -> [URL] {
        [
            URL(string: "https://\(host)/favicon.ico"),
            URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
        ].compactMap { $0 }
    }

    private func downloadIcon(
        from urls: [URL],
        host: String,
        itemID: UUID,
        generation: Int,
        destinationURL: URL
    ) {
        guard let url = urls.first else {
            markDownloadFinished(destinationURL)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("xxMac/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                Self.logger.debug("Failed to download favicon for \(host, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self.downloadIcon(from: Array(urls.dropFirst()), host: host, itemID: itemID, generation: generation, destinationURL: destinationURL)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let imageData = self.pngData(from: data) else {
                self.downloadIcon(from: Array(urls.dropFirst()), host: host, itemID: itemID, generation: generation, destinationURL: destinationURL)
                return
            }
            guard self.isCurrent(itemID: itemID, generation: generation) else {
                self.markDownloadFinished(destinationURL)
                return
            }

            do {
                try self.fileManager.createDirectory(
                    at: self.configDirectoryManager.quickShortcutIconsDirectoryURL,
                    withIntermediateDirectories: true
                )
                try imageData.write(to: destinationURL, options: .atomic)
                self.publishRefresh()
            } catch {
                Self.logger.debug("Failed to cache favicon for \(host, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            self.markDownloadFinished(destinationURL)
        }.resume()
    }

    private func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func isCurrent(itemID: UUID, generation: Int) -> Bool {
        stateQueue.sync {
            generations[itemID, default: 0] == generation
        }
    }

    private func markDownloadFinished(_ destinationURL: URL) {
        let inFlightKey = destinationURL.path
        stateQueue.async {
            self.inFlightKeys.remove(inFlightKey)
        }
    }

    private func publishRefresh() {
        DispatchQueue.main.async {
            self.refreshToken = UUID()
        }
    }
}
