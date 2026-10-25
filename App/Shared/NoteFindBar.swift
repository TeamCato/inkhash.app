import InkhashCore
import SwiftUI

/// Floats over the top of an open text note while finding in it: query, „2 von 5“, back, forward, close.
/// Paper like the library search. See ADR 0084.
struct NoteFindBar: View {
    let finder: NoteFinder
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Ink.muted)
            TextField("In der Notiz suchen", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
                .onSubmit {
                    finder.next()
                    focused = true
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    finder.previous()
                    return .handled
                }
                .onKeyPress(.escape) {
                    finder.close()
                    return .handled
                }
            Text(finder.find?.countLabel ?? "")
                .font(.callout.monospacedDigit())
                .foregroundStyle(Ink.muted)
                .fixedSize()
            Button { finder.previous() } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .disabled(finder.find?.current == nil)
                .accessibilityLabel("Vorheriger Treffer")
            Button { finder.next() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .disabled(finder.find?.current == nil)
                .accessibilityLabel("Nächster Treffer")
            Button { finder.close() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.muted) }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche schließen")
        }
        .foregroundStyle(Ink.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .inkSurface(in: Capsule())
        .frame(maxWidth: 420)
        .onAppear {
            query = finder.find?.query ?? ""
            focused = true
        }
        .onChange(of: query) { _, next in finder.setQuery(next) }
        // Cmd+F again, or with a new selection: the bar takes the keyboard and the query it was handed.
        .onChange(of: finder.focusToken) { _, _ in
            query = finder.find?.query ?? query
            focused = true
        }
        #if os(macOS)
        .onExitCommand { finder.close() }
        #endif
    }
}
