import Foundation

enum PreferenceValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case data(Data)
    case stringArray([String])

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case string
        case bool
        case int
        case double
        case data
        case stringArray
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .data:
            self = .data(try container.decode(Data.self, forKey: .value))
        case .stringArray:
            self = .stringArray(try container.decode([String].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case .data(let value):
            try container.encode(ValueType.data, forKey: .type)
            try container.encode(value, forKey: .value)
        case .stringArray(let value):
            try container.encode(ValueType.stringArray, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

final class FileBackedPreferences {
    let fileURL: URL

    private let fileManager: FileManager
    private var values: [String: PreferenceValue] = [:]

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        try? reload()
    }

    func string(forKey key: String) -> String? {
        guard case .string(let value) = values[key] else { return nil }
        return value
    }

    func stringArray(forKey key: String) -> [String]? {
        guard case .stringArray(let value) = values[key] else { return nil }
        return value
    }

    func data(forKey key: String) -> Data? {
        guard case .data(let value) = values[key] else { return nil }
        return value
    }

    func boolObject(forKey key: String) -> Bool? {
        guard case .bool(let value) = values[key] else { return nil }
        return value
    }

    func intObject(forKey key: String) -> Int? {
        guard case .int(let value) = values[key] else { return nil }
        return value
    }

    func doubleObject(forKey key: String) -> Double? {
        guard case .double(let value) = values[key] else { return nil }
        return value
    }

    func set(_ value: String, forKey key: String) {
        values[key] = .string(value)
    }

    func set(_ value: Bool, forKey key: String) {
        values[key] = .bool(value)
    }

    func set(_ value: Int, forKey key: String) {
        values[key] = .int(value)
    }

    func set(_ value: Double, forKey key: String) {
        values[key] = .double(value)
    }

    func set(_ value: Data, forKey key: String) {
        values[key] = .data(value)
    }

    func set(_ value: [String], forKey key: String) {
        values[key] = .stringArray(value)
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }

    func flush() throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(values)
        let temporaryURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")

        try data.write(to: temporaryURL, options: .atomic)

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    func reload() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            values = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        values = (try? JSONDecoder().decode([String: PreferenceValue].self, from: data)) ?? [:]
    }
}
