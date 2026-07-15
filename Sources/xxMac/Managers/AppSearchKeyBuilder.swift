import Foundation

struct AppSearchKeyBuilder {
    struct Keys {
        let normalized: [String]
        let compact: [String]
    }

    private static let pinyinAliases = loadPinyinAliases()

    static func keys(for names: [String]) -> Keys {
        var normalized = Set<String>()
        var compact = Set<String>()

        for name in names {
            insert(name, into: &normalized, &compact)
            insertInitials(from: name, into: &normalized, &compact)

            guard containsCJK(name), let pinyin = pinyin(for: name) else {
                continue
            }

            insert(pinyin, into: &normalized, &compact)
            insertInitials(from: pinyin, into: &normalized, &compact)
            insertPhrasePinyinAliases(for: name, into: &normalized, &compact)
            insertPinyinAliases(for: name, into: &normalized, &compact)
        }

        return Keys(
            normalized: normalized.sorted(),
            compact: compact.sorted()
        )
    }

    static func normalize(_ value: String) -> String {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        let cleanedScalars = folded.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) &&
            !CharacterSet.nonBaseCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(cleanedScalars)).lowercased()
    }

    static func normalizeCompact(_ value: String) -> String {
        let lowered = normalize(value)
        let filteredScalars = lowered.unicodeScalars.filter { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
            if CharacterSet.punctuationCharacters.contains(scalar) { return false }
            if CharacterSet.symbols.contains(scalar) { return false }
            return true
        }
        return String(String.UnicodeScalarView(filteredScalars))
    }

    private static func insert(_ value: String, into normalized: inout Set<String>, _ compact: inout Set<String>) {
        let normalizedValue = normalize(value)
        if !normalizedValue.isEmpty {
            normalized.insert(normalizedValue)
        }

        let compactValue = normalizeCompact(value)
        if !compactValue.isEmpty {
            compact.insert(compactValue)
        }
    }

    private static func insertInitials(from value: String, into normalized: inout Set<String>, _ compact: inout Set<String>) {
        let initials = normalize(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap { $0.first }
            .map(String.init)
            .joined()

        guard initials.count > 1 else { return }
        insert(initials, into: &normalized, &compact)
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func pinyin(for value: String) -> String? {
        let mutable = NSMutableString(string: value)
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false),
              CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false) else {
            return nil
        }
        return String(mutable)
    }

    private static func insertPinyinAliases(for value: String, into normalized: inout Set<String>, _ compact: inout Set<String>) {
        var syllables: [String] = []
        for character in value {
            if let aliases = pinyinAliases.characters[String(character)], let alias = aliases.first {
                syllables.append(alias)
            } else {
                let characterText = String(character)
                guard containsCJK(characterText), let pinyin = pinyin(for: characterText) else {
                    continue
                }
                syllables.append(pinyin)
            }
        }

        guard syllables.count > 1 else { return }
        let aliasPinyin = syllables.joined(separator: " ")
        insert(aliasPinyin, into: &normalized, &compact)
        insertInitials(from: aliasPinyin, into: &normalized, &compact)
    }

    private static func insertPhrasePinyinAliases(for value: String, into normalized: inout Set<String>, _ compact: inout Set<String>) {
        for (phrase, aliases) in pinyinAliases.phrases where value.contains(phrase) {
            for alias in aliases {
                insert(alias, into: &normalized, &compact)
                insertInitials(from: alias, into: &normalized, &compact)
            }
        }
    }

    private struct PinyinAliases {
        var characters: [String: [String]]
        var phrases: [String: [String]]
    }

    private static func loadPinyinAliases() -> PinyinAliases {
        guard let url = resourceURL(named: "pinyin_aliases", extension: "json"),
              let data = try? Data(contentsOf: url),
              let aliases = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return PinyinAliases(characters: [:], phrases: [:])
        }

        return aliases.reduce(into: PinyinAliases(characters: [:], phrases: [:])) { result, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let values = pair.value
                .map { normalizeCompact($0) }
                .filter { !$0.isEmpty }
            guard !key.isEmpty, !values.isEmpty else { return }
            if key.count == 1 {
                result.characters[key] = values
            } else {
                result.phrases[key] = values
            }
        }
    }

    private static func resourceURL(named name: String, extension fileExtension: String) -> URL? {
        if let bundleURL = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return bundleURL
        }

        let fileManager = FileManager.default
        let candidateDirectories = [
            fileManager.currentDirectoryPath,
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("Resources").path,
            URL(fileURLWithPath: fileManager.currentDirectoryPath).deletingLastPathComponent().appendingPathComponent("Resources").path
        ]

        for directory in candidateDirectories {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).\(fileExtension)")
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }
}
