import InkhashCore
import SwiftUI

struct InkhashCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neue Textnotiz") { model.createText() }
                .keyboardShortcut("n")
            Button("Neue Stiftnotiz") { model.createInk(data: InkDrawing.empty()) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("PDF, GoodNotes oder Sicherung importieren…") { model.importRequested = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandMenu("Schreiben") {
            Button("Fett") { model.sendInline(.toggleBold) }
                .keyboardShortcut("b")
            Button("Kursiv") { model.sendInline(.toggleItalic) }
                .keyboardShortcut("i")
            Button("Unterstrichen") { model.sendInline(.toggleDecoration(.underline)) }
                .keyboardShortcut("u")
            Button("Durchgestrichen") { model.sendInline(.toggleDecoration(.strike)) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Textmarker") { model.sendInline(.toggleDecoration(.highlight)) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Code im Text") { model.sendInline(.toggleCode) }
                .keyboardShortcut("e", modifiers: [.command])
            Button("Link…") { model.promptLink() }
                .keyboardShortcut("k")
            Divider()
            Button(model.findsInNote ? "In der Notiz suchen" : "Suchen") { model.find() }
                .keyboardShortcut("f")
            Button("Weitersuchen") { model.sendFind(.next) }
                .keyboardShortcut("g")
                .disabled(!model.findsInNote)
            Button("Rückwärts suchen") { model.sendFind(.previous) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!model.findsInNote)
            Button("In allen Notizen suchen") { model.focusSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}
