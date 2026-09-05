import Foundation
import UniformTypeIdentifiers

enum TodoDragSource: Codable, Equatable {
    case quadrant(TodoQuadrant)
    case status(TodoStatus)
}

struct TodoDragPayload: Codable, Equatable {
    static let contentType = UTType(exportedAs: "com.macefficiency.todo-task")

    let taskID: UUID
    let source: TodoDragSource

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> TodoDragPayload {
        try JSONDecoder().decode(TodoDragPayload.self, from: data)
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.contentType.identifier,
            visibility: .ownProcess
        ) { completion in
            do {
                completion(try encoded(), nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        return provider
    }
}
