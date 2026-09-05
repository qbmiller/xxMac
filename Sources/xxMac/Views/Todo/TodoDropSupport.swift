import SwiftUI

struct TodoDropDestination: Equatable {
    enum Kind: Equatable {
        case quadrant(TodoQuadrant)
        case status(TodoStatus)
    }

    let kind: Kind
    let beforeID: UUID?
}

struct TodoDraggableTaskCard<Content: View>: View {
    let payload: TodoDragPayload
    let destination: TodoDropDestination
    let onMove: (TodoDragPayload, TodoDropDestination) -> Void
    let content: Content

    @State private var isDropTargeted = false

    init(
        payload: TodoDragPayload,
        destination: TodoDropDestination,
        onMove: @escaping (TodoDragPayload, TodoDropDestination) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.payload = payload
        self.destination = destination
        self.onMove = onMove
        self.content = content()
    }

    var body: some View {
        content
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .opacity(isDropTargeted ? 1 : 0)
            }
            .onDrag { payload.itemProvider() }
            .onDrop(
                of: [TodoDragPayload.contentType.identifier],
                delegate: TodoTaskDropDelegate(
                    destination: destination,
                    isTargeted: $isDropTargeted,
                    onMove: onMove
                )
            )
    }
}

struct TodoLaneDropTarget<Content: View>: View {
    let destination: TodoDropDestination
    let onMove: (TodoDragPayload, TodoDropDestination) -> Void
    let content: Content

    @State private var isDropTargeted = false

    init(
        destination: TodoDropDestination,
        onMove: @escaping (TodoDragPayload, TodoDropDestination) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.onMove = onMove
        self.content = content()
    }

    var body: some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(isDropTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onDrop(
                of: [TodoDragPayload.contentType.identifier],
                delegate: TodoTaskDropDelegate(
                    destination: destination,
                    isTargeted: $isDropTargeted,
                    onMove: onMove
                )
            )
    }
}

private struct TodoTaskDropDelegate: DropDelegate {
    let destination: TodoDropDestination
    @Binding var isTargeted: Bool
    let onMove: (TodoDragPayload, TodoDropDestination) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [TodoDragPayload.contentType.identifier])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [TodoDragPayload.contentType.identifier]).first else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: TodoDragPayload.contentType.identifier) { data, _ in
            guard let data,
                  let payload = try? TodoDragPayload.decode(data),
                  payload.taskID != destination.beforeID else {
                return
            }
            DispatchQueue.main.async {
                onMove(payload, destination)
            }
        }
        return true
    }
}
