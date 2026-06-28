import AppKit
import Foundation
import OSLog

final class QuickShortcutManager: ObservableObject {
    static let shared = QuickShortcutManager()

    @Published var items: [QuickShortcut] = [] {
        didSet { saveItems() }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "QuickShortcut")
    private let storageKey = "QuickShortcutItems"

    struct Match {
        let item: QuickShortcut
        let query: String
    }

    private init() {
        loadItems()
    }

    func addWebSearch() {
        items.append(QuickShortcut(
            title: L10n.t("quick_shortcut.default_web_title"),
            keyword: "",
            actionType: .webSearch,
            payload: "https://www.google.com/search?q={query}",
            isEnabled: false
        ))
    }

    func addCommandScript() {
        items.append(QuickShortcut(
            title: L10n.t("quick_shortcut.default_command_title"),
            keyword: "",
            actionType: .commandScript,
            payload: Self.defaultTimestampScript,
            shellPath: "/bin/zsh",
            previewQuery: "2026-06-27 21:21:38",
            isEnabled: false
        ))
    }

    func removeItem(_ item: QuickShortcut) {
        items.removeAll { $0.id == item.id }
    }

    func updateItem(_ item: QuickShortcut) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func search(query: String) -> [SearchItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        return items.compactMap { item in
            guard item.isEnabled else { return nil }
            guard let invokedQuery = invokedQuery(for: trimmedQuery, keyword: item.keyword) else { return nil }

            return SearchItem(
                id: "quick_shortcut.\(item.id.uuidString)",
                title: item.title,
                subtitle: subtitle(for: item),
                iconName: item.actionType.iconName,
                type: .quickShortcut,
                action: { [weak self] in
                    self?.execute(item: item, query: invokedQuery)
                }
            )
        }
    }

    func match(query: String) -> Match? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        for item in items where item.isEnabled {
            if let invokedQuery = invokedQuery(for: trimmedQuery, keyword: item.keyword) {
                return Match(item: item, query: invokedQuery)
            }
        }
        return nil
    }

    private func invokedQuery(for query: String, keyword: String) -> String? {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return nil }

        let lowerQuery = query.lowercased()
        let lowerKeyword = trimmedKeyword.lowercased()

        guard lowerQuery == lowerKeyword || lowerQuery.hasPrefix(lowerKeyword + " ") else {
            return nil
        }

        if query.count == trimmedKeyword.count {
            return ""
        }

        let startIndex = query.index(query.startIndex, offsetBy: trimmedKeyword.count)
        return query[startIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func subtitle(for item: QuickShortcut) -> String {
        let keyword = item.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return item.actionType.displayName
        }
        return "\(item.actionType.displayName) · \(keyword)"
    }

    func execute(item: QuickShortcut, query: String) {
        switch item.actionType {
        case .webSearch:
            openWebSearch(template: item.payload, query: query)
        case .commandScript:
            runCommandScript(item: item, query: query) { [weak self] output in
                self?.copyToPasteboard(output)
            }
        }
    }

    private func openWebSearch(template: String, query: String) {
        let encodedQuery = percentEncodedQuery(query)
        let urlString = template.replacingOccurrences(of: "{query}", with: encodedQuery)
        guard let url = URL(string: urlString) else {
            Self.logger.error("Invalid web shortcut URL template: \(urlString, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func runCommandScript(item: QuickShortcut, query: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let scriptFileURL: URL
            do {
                scriptFileURL = try self.writeTemporaryScript(item.payload)
            } catch {
                DispatchQueue.main.async {
                    completion(error.localizedDescription)
                }
                return
            }

            let interpreter = self.interpreter(for: item.payload, fallbackShellPath: item.shellPath)
            process.executableURL = URL(fileURLWithPath: interpreter.executable)
            process.arguments = interpreter.arguments + [scriptFileURL.path] + self.commandArguments(for: item, query: query)
            var environment = ProcessInfo.processInfo.environment
            environment["XXMAC_QUERY"] = query
            process.environment = environment
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

            let standardOutput = Pipe()
            let standardError = Pipe()
            process.standardOutput = standardOutput
            process.standardError = standardError

            do {
                try process.run()
                process.waitUntilExit()
                let output = self.commandOutput(
                    outputData: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                    errorData: standardError.fileHandleForReading.readDataToEndOfFile(),
                    terminationStatus: process.terminationStatus
                )
                DispatchQueue.main.async {
                    completion(output)
                }
            } catch {
                Self.logger.error("Failed to run quick shortcut script: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    completion(error.localizedDescription)
                }
            }

            try? FileManager.default.removeItem(at: scriptFileURL)
        }
    }

    private func writeTemporaryScript(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent("xxmac-quick-shortcut-\(UUID().uuidString).sh")
        try script.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fileURL.path)
        return fileURL
    }

    private func interpreter(for script: String, fallbackShellPath: String) -> (executable: String, arguments: [String]) {
        guard let firstLine = script.split(whereSeparator: \.isNewline).first.map(String.init),
              firstLine.hasPrefix("#!") else {
            return (fallbackShellPath.isEmpty ? "/bin/zsh" : fallbackShellPath, [])
        }

        let shebang = firstLine.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = shebang.split(separator: " ").map(String.init)
        guard let executable = parts.first, !executable.isEmpty else {
            return (fallbackShellPath.isEmpty ? "/bin/zsh" : fallbackShellPath, [])
        }
        return (executable, Array(parts.dropFirst()))
    }

    private func commandOutput(outputData: Data, errorData: Data, terminationStatus: Int32) -> String {
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        var sections: [String] = []

        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(output)
        }
        if !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("stderr:\n\(error)")
        }
        if terminationStatus != 0 {
            sections.append(L10n.f("quick_shortcut.exit_status_format", terminationStatus))
        }

        if sections.isEmpty {
            return L10n.t("quick_shortcut.no_output")
        }
        return sections.joined(separator: "\n")
    }

    func previewCommandOutput(item: QuickShortcut) -> String {
        guard item.actionType == .commandScript else { return "" }
        let result = executeCommandSynchronously(item: item, query: item.previewQuery)
        return result
    }

    private func executeCommandSynchronously(item: QuickShortcut, query: String) -> String {
        let scriptFileURL: URL
        do {
            scriptFileURL = try writeTemporaryScript(item.payload)
        } catch {
            return error.localizedDescription
        }

        defer {
            try? FileManager.default.removeItem(at: scriptFileURL)
        }

        let interpreter = interpreter(for: item.payload, fallbackShellPath: item.shellPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: interpreter.executable)
        process.arguments = interpreter.arguments + [scriptFileURL.path] + commandArguments(for: item, query: query)
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["XXMAC_QUERY"] = query
        process.environment = environment

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
            process.waitUntilExit()
            return commandOutput(
                outputData: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                errorData: standardError.fileHandleForReading.readDataToEndOfFile(),
                terminationStatus: process.terminationStatus
            )
        } catch {
            return error.localizedDescription
        }
    }

    func renderedWebSearchURL(item: QuickShortcut) -> String {
        let encodedQuery = percentEncodedQuery(item.previewQuery)
        return item.payload.replacingOccurrences(of: "{query}", with: encodedQuery)
    }

    func renderedCommandArguments(item: QuickShortcut) -> [String] {
        commandArguments(for: item, query: item.previewQuery)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func commandArguments(for item: QuickShortcut, query: String) -> [String] {
        switch item.commandInputMode {
        case .queryPlaceholder:
            return [query]
        case .argv:
            let parsed = parseShellArguments(query)
            return parsed.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [query] : parsed
        }
    }

    private func parseShellArguments(_ input: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in input {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    arguments.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if isEscaping {
            current.append("\\")
        }
        if !current.isEmpty {
            arguments.append(current)
        }
        return arguments
    }

    private func percentEncodedQuery(_ query: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+#"))
        return query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
    }

    private static let defaultTimestampScript = #"""

"""#

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([QuickShortcut].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func saveItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
