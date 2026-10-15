import Foundation
import Observation
import SwiftUI

/// Follows the undo manager of an editor and tells its buttons what is possible. See ADR 0059.
@MainActor
@Observable
final class UndoHistory {
    private(set) var canUndo = false
    private(set) var canRedo = false
    @ObservationIgnored private weak var manager: UndoManager?
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Starts following `manager`. Nil keeps the one followed so far: views lose theirs when they leave the window.
    func follow(_ manager: UndoManager?) {
        guard let manager, manager !== self.manager else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        self.manager = manager
        let names: [Notification.Name] = [.NSUndoManagerCheckpoint, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange, .NSUndoManagerDidCloseUndoGroup]
        // Without a queue the block runs where the manager posts, on the main thread like every editor.
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: manager, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func undo() {
        guard let manager, manager.canUndo else { return }
        manager.undo()
        refresh()
    }

    func redo() {
        guard let manager, manager.canRedo else { return }
        manager.redo()
        refresh()
    }

    private func refresh() {
        let undo = manager?.canUndo ?? false
        let redo = manager?.canRedo ?? false
        if undo != canUndo { canUndo = undo }
        if redo != canRedo { canRedo = redo }
    }
}

/// Undo and redo in the bar of an editor, before its other buttons. See ADR 0059.
struct UndoToolbar: ToolbarContent {
    var history: UndoHistory

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { history.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!history.canUndo)
                .accessibilityLabel("Rückgängig")
                .help("Rückgängig")
            Button { history.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!history.canRedo)
                .accessibilityLabel("Wiederholen")
                .help("Wiederholen")
        }
    }
}
