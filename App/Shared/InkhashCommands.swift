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
            Button("PDF oder GoodNotes importieren…") { model.importRequested = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandMenu("Schreiben") {
            Button("Fett") { model.sendInline(.toggleBold) }
                .keyboardShortcut("b")
            Button("Kursiv") { model.sendInline(.toggleItalic) }
                .keyboardShortcut("i")
            Button("Code im Text") { model.sendInline(.toggleCode) }
                .keyboardShortcut("e", modifiers: [.command])
            Button("Link…") { model.promptLink() }
                .keyboardShortcut("k")
            Divider()
            Button("Suchen") { model.focusSearch() }
                .keyboardShortcut("f")
        }
    }
}
