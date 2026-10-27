import InkhashCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The one text view of a text note. See ADR 0025.
struct NoteTextView: View {
    let session: TextSession
    /// Changes with every edit, so SwiftUI asks for the height again.
    var version: Int

    var body: some View {
        #if os(macOS)
        MacNoteText(session: session, version: version)
        #else
        IOSNoteText(session: session, version: version)
        #endif
    }
}

/// TextKit 1 stack with the marker layout manager. TextKit 2 has no `drawBackground` hook for the markers.
@MainActor
func makeTextStack() -> (NSTextStorage, MarkerLayoutManager, NSTextContainer) {
    let storage = NSTextStorage()
    let layout = MarkerLayoutManager()
    storage.addLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    container.lineFragmentPadding = 0
    layout.addTextContainer(container)
    return (storage, layout, container)
}

#if os(macOS)
struct MacNoteText: NSViewRepresentable {
    let session: TextSession
    var version: Int

    func makeNSView(context: Context) -> InkNoteTextView {
        // The storage owns the layout manager, the container only points at it. Keep it alive until the view holds it.
        let (storage, _, container) = makeTextStack()
        let view = withExtendedLifetime(storage) { InkNoteTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 200), textContainer: container) }
        view.ownedStorage = storage
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        // Finding has a bar of its own over the note, see ADR 0084.
        view.usesFindBar = false
        let engine = EditorEngine(host: view, blocks: session.initialBlocks, source: session.excerptSource)
        engine.session = session
        view.engine = engine
        view.delegate = context.coordinator
        context.coordinator.engine = engine
        session.engine = engine
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            view.undoManager?.levelsOfUndo = 100
            session.history.follow(view.undoManager)
            engine.updateState()
        }
        return view
    }

    func updateNSView(_ view: InkNoteTextView, context: Context) {
        context.coordinator.engine?.session = session
    }

    func makeCoordinator() -> MacNoteCoordinator { MacNoteCoordinator() }

    /// The window's undo manager outlives the note; its steps must not. See ADR 0059 and P-063.
    static func dismantleNSView(_ view: InkNoteTextView, coordinator: MacNoteCoordinator) {
        view.undoManager?.removeAllActions()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: InkNoteTextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 640, 80)
        return CGSize(width: width, height: view.engine?.height(for: width) ?? 40)
    }
}

@MainActor
final class MacNoteCoordinator: NSObject, NSTextViewDelegate {
    var engine: EditorEngine?

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard let text else { return true }
        return engine?.shouldChange(range, replacement: text) ?? true
    }

    func textDidChange(_ notification: Notification) {
        engine?.didChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        engine?.selectionChanged()
    }
}

final class InkNoteTextView: NSTextView, EditorHost {
    var engine: EditorEngine?
    /// A text view built on a given container does not retain the storage at the top of the stack.
    var ownedStorage: NSTextStorage?

    var storage: NSTextStorage { textStorage! }
    var markers: MarkerLayoutManager { layoutManager as! MarkerLayoutManager }
    var container: NSTextContainer { textContainer! }
    var containerOrigin: CGPoint { textContainerOrigin }
    var isComposing: Bool { hasMarkedText() }

    var selection: NSRange {
        get { selectedRange() }
        set { setSelectedRange(NSRange(location: min(newValue.location, storage.length), length: min(newValue.length, storage.length - min(newValue.location, storage.length)))) }
    }

    var typing: [NSAttributedString.Key: Any] {
        get { typingAttributes }
        set { typingAttributes = newValue }
    }

    func performEdit(_ range: NSRange, replacement: String?, _ body: () -> Void) {
        // Through shouldChangeText/didChangeText, so the edit lands on the undo stack.
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        storage.beginEditing()
        body()
        storage.endEditing()
        didChangeText()
    }

    func focus() {
        window?.makeFirstResponder(self)
    }

    func contentChanged() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func reveal(_ rect: CGRect) {
        // Some room below, so a menu under the cursor has a line to start in.
        scrollToVisible(rect.insetBy(dx: 0, dy: -24))
    }

    /// The system's find commands open the note's own find bar. See ADR 0084.
    override func performTextFinderAction(_ sender: Any?) {
        guard let finder = engine?.session?.finder,
              let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return super.performTextFinderAction(sender) }
        switch action {
        case .nextMatch: finder.next()
        case .previousMatch: finder.previous()
        case .hideFindInterface: finder.close()
        default: finder.open()
        }
    }

    override func performFindPanelAction(_ sender: Any?) {
        performTextFinderAction(sender)
    }

    /// Plain text only. Formatting from other apps would bring fonts the note cannot store.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    /// Where copying writes and pasting reads. Tests hand in a pasteboard of their own.
    var pasteboard: NSPasteboard = .general

    /// Copying keeps the style: Markdown for inkhash, RTF for other apps. See ADR 0063.
    override func copy(_ sender: Any?) {
        guard let clip = engine?.clipboard(for: selectedRange()) else { return super.copy(sender) }
        write(clip)
    }

    override func cut(_ sender: Any?) {
        guard let clip = engine?.clipboard(for: selectedRange()) else { return super.cut(sender) }
        write(clip)
        delete(sender)
    }

    override func paste(_ sender: Any?) {
        if let engine, let markdown = pasteboard.string(forType: .inkhashMarkdown) {
            engine.paste(markdown: markdown)
        } else if pasteboard == .general {
            super.paste(sender)
        } else {
            readSelection(from: pasteboard)
        }
    }

    private func write(_ clip: ClipboardContent) {
        pasteboard.clearContents()
        pasteboard.setString(clip.markdown, forType: .inkhashMarkdown)
        pasteboard.setString(clip.markdown, forType: .string)
        if let rtf = clip.rtf { pasteboard.setData(rtf, forType: .rtf) }
    }

    override func insertLineBreak(_ sender: Any?) {
        insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if engine?.backspaceAtStart() == true { return }
        super.deleteBackward(sender)
    }

    override func moveUp(_ sender: Any?) {
        if engine?.noteLinkOpen == true, let session = engine?.session {
            session.moveNoteLink(-1)
            return
        }
        if engine?.slashOpen == true, let session = engine?.session {
            session.moveSlash(-1)
            return
        }
        super.moveUp(sender)
    }

    override func moveDown(_ sender: Any?) {
        if engine?.noteLinkOpen == true, let session = engine?.session {
            session.moveNoteLink(1)
            return
        }
        if engine?.slashOpen == true, let session = engine?.session {
            session.moveSlash(1)
            return
        }
        super.moveDown(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        if engine?.noteLinkOpen == true {
            engine?.escapeNoteLink()
            return
        }
        if engine?.slashOpen == true {
            engine?.escapeSlash()
            return
        }
        super.cancelOperation(sender)
    }

    /// Tab moves between table cells and indents list items (ADR 0086); elsewhere it does nothing, a note has no tab
    /// characters.
    override func insertTab(_ sender: Any?) {
        guard let engine else { return }
        if engine.isInTable { return super.insertTab(sender) }
        engine.indent(by: 1)
    }

    /// Shift-Tab moves list items out one level; elsewhere it leaves the text view as usual.
    override func insertBacktab(_ sender: Any?) {
        guard let engine, engine.canIndent else { return super.insertBacktab(sender) }
        engine.indent(by: -1)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let engine, let paragraph = engine.checkbox(at: point) {
            engine.toggleChecked(paragraph)
            return
        }
        // A click on an excerpt opens its source. See ADR 0032.
        if let excerpt = engine?.excerpt(at: point) {
            engine?.session?.openLink(excerpt.target)
            return
        }
        // Cmd+click follows a link; a plain click edits it like any other text.
        if event.modifierFlags.contains(.command), let target = linkTarget(at: point) {
            engine?.session?.openLink(target)
            return
        }
        super.mouseDown(with: event)
    }

    private func linkTarget(at point: NSPoint) -> String? {
        guard storage.length > 0 else { return nil }
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length else { return nil }
        return storage.attribute(.inkhashLink, at: index, effectiveRange: nil) as? String
    }
}
#else
struct IOSNoteText: UIViewRepresentable {
    let session: TextSession
    var version: Int

    func makeUIView(context: Context) -> InkNoteTextView {
        // The storage owns the layout manager, the container only points at it. Keep it alive until the view holds it.
        let (storage, _, container) = makeTextStack()
        let view = withExtendedLifetime(storage) { InkNoteTextView(frame: CGRect(x: 0, y: 0, width: 640, height: 200), textContainer: container) }
        view.ownedStorage = storage
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.allowsEditingTextAttributes = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.dataDetectorTypes = []
        let engine = EditorEngine(host: view, blocks: session.initialBlocks, source: session.excerptSource)
        engine.session = session
        view.engine = engine
        view.delegate = context.coordinator
        context.coordinator.engine = engine
        session.engine = engine
        view.installCheckboxTap()
        view.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: InkNoteTextView, _: UITraitCollection) in
            view.engine?.textSizeChanged()
        }
        DispatchQueue.main.async {
            view.becomeFirstResponder()
            session.history.follow(view.undoManager)
            engine.updateState()
        }
        return view
    }

    func updateUIView(_ view: InkNoteTextView, context: Context) {
        context.coordinator.engine?.session = session
    }

    func makeCoordinator() -> IOSNoteCoordinator { IOSNoteCoordinator() }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: InkNoteTextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 640, 80)
        return CGSize(width: width, height: view.engine?.height(for: width) ?? 40)
    }
}

@MainActor
final class IOSNoteCoordinator: NSObject, UITextViewDelegate {
    var engine: EditorEngine?

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        (textView as? InkNoteTextView)?.recordTyping(range, replacement: text)
        return engine?.shouldChange(range, replacement: text) ?? true
    }

    func textViewDidChange(_ textView: UITextView) {
        engine?.didChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        engine?.selectionChanged()
    }
}

final class InkNoteTextView: UITextView, EditorHost {
    var engine: EditorEngine?
    /// A text view built on a given container does not retain the storage at the top of the stack.
    var ownedStorage: NSTextStorage?
    /// The note's own undo steps. UIKit drops its typing steps whenever the engine changes the text
    /// itself, so typing is recorded here too, and UIKit's manager stays unused. See ADR 0059 and P-060.
    private let history: UndoManager = {
        let manager = UndoManager()
        manager.levelsOfUndo = 100
        return manager
    }()
    /// Where the current run of typing ends. A change that starts there joins the run's undo step.
    private var typingEnd: Int?

    override var undoManager: UndoManager? { history }

    /// Where copying writes and pasting reads. Tests hand in a pasteboard of their own.
    var pasteboard: UIPasteboard = .general

    /// Copying keeps the style: Markdown for inkhash, RTF for other apps. See ADR 0063.
    override func copy(_ sender: Any?) {
        guard let clip = engine?.clipboard(for: selectedRange) else { return super.copy(sender) }
        write(clip)
    }

    /// Deleting goes the keyboard's way, through the delegate, so it is one undo step.
    override func cut(_ sender: Any?) {
        guard let clip = engine?.clipboard(for: selectedRange) else { return super.cut(sender) }
        write(clip)
        deleteBackward()
    }

    override func paste(_ sender: Any?) {
        if let engine, let data = pasteboard.data(forPasteboardType: ClipboardContent.markdownType),
           let markdown = String(data: data, encoding: .utf8) {
            engine.paste(markdown: markdown)
        } else {
            super.paste(sender)
        }
    }

    private func write(_ clip: ClipboardContent) {
        var item: [String: Any] = [
            ClipboardContent.markdownType: Data(clip.markdown.utf8),
            UTType.utf8PlainText.identifier: clip.markdown,
        ]
        if let rtf = clip.rtf { item[UTType.rtf.identifier] = rtf }
        pasteboard.setItems([item])
    }

    var storage: NSTextStorage { textStorage }
    var markers: MarkerLayoutManager { layoutManager as! MarkerLayoutManager }
    var container: NSTextContainer { textContainer }
    var containerOrigin: CGPoint { CGPoint(x: textContainerInset.left, y: textContainerInset.top) }
    var isComposing: Bool { markedTextRange != nil }

    var selection: NSRange {
        get { selectedRange }
        set {
            let location = min(newValue.location, storage.length)
            let next = NSRange(location: location, length: min(newValue.length, storage.length - location))
            guard next != selectedRange else { return }
            inputDelegate?.selectionWillChange(self)
            selectedRange = next
            inputDelegate?.selectionDidChange(self)
        }
    }

    var typing: [NSAttributedString.Key: Any] {
        get { typingAttributes }
        set { typingAttributes = newValue }
    }

    func performEdit(_ range: NSRange, replacement: String?, _ body: () -> Void) {
        typingEnd = nil
        let before = engine?.snapshot()
        // Tell the keyboard, or its autocorrect buffer still holds the old text. See P-038.
        inputDelegate?.textWillChange(self)
        storage.beginEditing()
        body()
        storage.endEditing()
        inputDelegate?.textDidChange(self)
        if let before { registerRestore(before) }
    }

    /// One undo step per run of typing: it starts with the first change and goes on while each change
    /// starts where the last one ended. A new line, a jump of the cursor or an edit of the engine ends it.
    func recordTyping(_ range: NSRange, replacement: String) {
        guard engine?.programmatic != true, !history.isUndoing, !history.isRedoing else { return }
        if typingEnd != NSMaxRange(range), let before = engine?.snapshot() {
            registerRestore(before)
        }
        typingEnd = replacement.contains("\n") ? nil : range.location + (replacement as NSString).length
    }

    /// Undo puts `snapshot` back and leaves the text it replaced as the redo step.
    private func registerRestore(_ snapshot: EditorEngine.Snapshot) {
        undoManager?.registerUndo(withTarget: self) { view in
            MainActor.assumeIsolated { view.restore(snapshot) }
        }
    }

    private func restore(_ snapshot: EditorEngine.Snapshot) {
        guard let engine else { return }
        typingEnd = nil
        let current = engine.snapshot()
        inputDelegate?.textWillChange(self)
        engine.restore(snapshot)
        inputDelegate?.textDidChange(self)
        registerRestore(current)
    }

    func focus() {
        if !isFirstResponder { becomeFirstResponder() }
    }

    func contentChanged() {
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    /// The text view does not scroll; the sheet's scroll view around it does, just far enough.
    func reveal(_ rect: CGRect) {
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? UIScrollView else { return }
        scroll.scrollRectToVisible(convert(rect.insetBy(dx: 0, dy: -24), to: scroll), animated: false)
    }

    override func deleteBackward() {
        if engine?.backspaceAtStart() == true { return }
        super.deleteBackward()
    }

    /// UIKit spans the caret over the whole line fragment, with the space above a paragraph and the
    /// line spacing below it. It belongs on the text: from the top of the used line, as high as the font.
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let index = offset(from: beginningOfDocument, to: position)
        let length = storage.length
        let attributes = index > 0 && index <= length && character(at: index - 1) != 0x0A
            ? storage.attributes(at: index - 1, effectiveRange: nil)
            : (index < length ? storage.attributes(at: index, effectiveRange: nil) : typingAttributes)
        guard let font = attributes[.font] as? UIFont else { return rect }
        let line: CGRect
        if index >= length, !layoutManager.extraLineFragmentRect.isEmpty {
            line = layoutManager.extraLineFragmentUsedRect
        } else if layoutManager.numberOfGlyphs > 0 {
            let point = CGPoint(x: rect.minX - textContainerInset.left, y: rect.midY - textContainerInset.top)
            let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
            line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        } else {
            return rect
        }
        rect.origin.y = line.minY + textContainerInset.top
        rect.size.height = font.lineHeight
        return rect
    }

    private func character(at index: Int) -> unichar {
        (storage.string as NSString).character(at: index)
    }

    /// UIKit caps the container at the view's height; the text must lay out in full to be measured.
    override func layoutSubviews() {
        super.layoutSubviews()
        if textContainer.size.height < 100_000 {
            textContainer.size = CGSize(width: textContainer.size.width, height: .greatestFiniteMagnitude)
        }
    }

    /// With a hardware keyboard, iPadOS hands Return to the toolbar's primary action before the
    /// text view sees it. A key command on the first responder wins, see P-029.
    override var keyCommands: [UIKeyCommand]? {
        var commands = [UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(returnPressed))]
        if engine?.noteLinkOpen == true {
            commands.append(UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(noteUp)))
            commands.append(UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(noteDown)))
            commands.append(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(noteEscape)))
        } else if engine?.slashOpen == true {
            commands.append(UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(slashUp)))
            commands.append(UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(slashDown)))
            commands.append(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(slashEscape)))
        }
        if engine?.canIndent == true {
            // Tab and Shift-Tab indent list items instead of moving the focus (ADR 0086).
            commands.append(UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentIn)))
            commands.append(UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(indentOut)))
        }
        for command in commands { command.wantsPriorityOverSystemBehavior = true }
        return commands + (super.keyCommands ?? [])
    }

    @objc private func indentIn() { engine?.indent(by: 1) }
    @objc private func indentOut() { engine?.indent(by: -1) }

    @objc private func returnPressed() {
        guard let engine else { return insertText("\n") }
        engine.returnKey { insertText("\n") }
    }
    @objc private func slashUp() { engine?.session?.moveSlash(-1) }
    @objc private func slashDown() { engine?.session?.moveSlash(1) }
    @objc private func slashEscape() { engine?.escapeSlash() }
    @objc private func noteUp() { engine?.session?.moveNoteLink(-1) }
    @objc private func noteDown() { engine?.session?.moveNoteLink(1) }
    @objc private func noteEscape() { engine?.escapeNoteLink() }

    private let checkboxDelegate = CheckboxTapDelegate()

    func installCheckboxTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(checkboxTapped(_:)))
        checkboxDelegate.view = self
        tap.delegate = checkboxDelegate
        addGestureRecognizer(tap)
    }

    @objc private func checkboxTapped(_ gesture: UITapGestureRecognizer) {
        guard let engine else { return }
        let point = gesture.location(in: self)
        if let excerpt = engine.excerpt(at: point) {
            engine.session?.openLink(excerpt.target)
            return
        }
        guard let paragraph = engine.checkbox(at: point) else { return }
        engine.toggleChecked(paragraph)
    }
}

/// Lets the checkbox tap begin only on a checkbox or an excerpt, and makes the text view's own taps wait for it there.
@MainActor
final class CheckboxTapDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var view: InkNoteTextView?

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let view else { return false }
        let point = gesture.location(in: view)
        return view.engine?.checkbox(at: point) != nil || view.engine?.excerpt(at: point) != nil
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif

#if os(macOS)
extension NSPasteboard.PasteboardType {
    static let inkhashMarkdown = NSPasteboard.PasteboardType(ClipboardContent.markdownType)
}
#endif
