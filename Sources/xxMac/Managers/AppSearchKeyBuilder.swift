import Foundation

struct AppSearchKeyBuilder {
    struct Keys {
        let normalized: [String]
        let compact: [String]
    }

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
}
