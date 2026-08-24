import Foundation

enum ClipboardTextFormatDetector {
    static func fileExtension(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let data = Data(trimmed.utf8)
        if isJSON(data, text: trimmed) { return "json" }
        if isPropertyList(data, text: trimmed) { return "plist" }
        if isXML(data, text: trimmed) { return "xml" }

        let lines = meaningfulLines(in: trimmed)
        if isYAML(lines) { return "yml" }
        if isTOML(lines) { return "toml" }
        if isINI(lines) { return "ini" }
        if isEnvironment(lines) { return "env" }
        return nil
    }

    private static func isJSON(_ data: Data, text: String) -> Bool {
        guard text.hasPrefix("{") || text.hasPrefix("[") else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func isPropertyList(_ data: Data, text: String) -> Bool {
        guard text.contains("<plist") else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil
    }

    private static func isXML(_ data: Data, text: String) -> Bool {
        guard text.hasPrefix("<") else { return false }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        return parser.parse()
    }

    private static func meaningfulLines(in text: String) -> [String] {
        text.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix(";")
        }
    }

    private static func isYAML(_ lines: [String]) -> Bool {
        guard lines.count >= 2, !lines.contains(where: { $0.contains("=") }) else { return false }

        let mappingCount = lines.filter {
            $0.range(of: #"^\s*(?:-\s+)?[A-Za-z_][A-Za-z0-9_.-]*\s*:\s*.*$"#, options: .regularExpression) != nil
        }.count
        let hasIndentedStructure = lines.contains {
            $0.range(of: #"^\s{2,}(?:-|[A-Za-z_])"#, options: .regularExpression) != nil
        }
        let hasListItem = lines.contains {
            $0.range(of: #"^\s*-\s+\S"#, options: .regularExpression) != nil
        }
        let hasDocumentMarker = lines.contains("---")

        return mappingCount >= 2 && (hasIndentedStructure || hasListItem || hasDocumentMarker)
    }

    private static func isTOML(_ lines: [String]) -> Bool {
        guard hasSectionHeader(lines) else { return false }
        let assignments = lines.filter {
            $0.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*\s+=\s+.+$"#, options: .regularExpression) != nil
        }
        return assignments.count >= 2
    }

    private static func isINI(_ lines: [String]) -> Bool {
        guard hasSectionHeader(lines) else { return false }
        let assignments = lines.filter {
            $0.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*\s*=\s*.*$"#, options: .regularExpression) != nil
        }
        return assignments.count >= 2
    }

    private static func isEnvironment(_ lines: [String]) -> Bool {
        guard lines.count >= 2 else { return false }
        return lines.allSatisfy {
            $0.range(of: #"^(?:export\s+)?[A-Za-z_][A-Za-z0-9_]*=.*$"#, options: .regularExpression) != nil
        }
    }

    private static func hasSectionHeader(_ lines: [String]) -> Bool {
        lines.contains {
            $0.range(of: #"^\s*\[[A-Za-z0-9_.-]+\]\s*$"#, options: .regularExpression) != nil
        }
    }
}
