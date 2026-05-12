import Foundation

public enum AnnotationCommand: Sendable {
    case add(Element)
    case remove(Element)
    case update(old: Element, new: Element)
}

public struct UndoStack {
    public let capacity: Int
    private var undoStack: [AnnotationCommand] = []
    private var redoStack: [AnnotationCommand] = []

    public init(capacity: Int = 50) { self.capacity = capacity }

    public var undoDepth: Int { undoStack.count }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func perform(_ command: AnnotationCommand, on doc: inout AnnotationDocument) {
        apply(command, on: &doc)
        undoStack.append(command)
        if undoStack.count > capacity { undoStack.removeFirst(undoStack.count - capacity) }
        redoStack.removeAll()
    }

    public mutating func undo(on doc: inout AnnotationDocument) {
        guard let cmd = undoStack.popLast() else { return }
        apply(invert(cmd), on: &doc)
        redoStack.append(cmd)
    }

    public mutating func redo(on doc: inout AnnotationDocument) {
        guard let cmd = redoStack.popLast() else { return }
        apply(cmd, on: &doc)
        undoStack.append(cmd)
    }

    private func apply(_ command: AnnotationCommand, on doc: inout AnnotationDocument) {
        switch command {
        case .add(let e): doc.add(e)
        case .remove(let e): doc.remove(id: e.id)
        case .update(_, let new): doc.update(new)
        }
    }

    private func invert(_ command: AnnotationCommand) -> AnnotationCommand {
        switch command {
        case .add(let e): return .remove(e)
        case .remove(let e): return .add(e)
        case .update(let old, let new): return .update(old: new, new: old)
        }
    }
}
