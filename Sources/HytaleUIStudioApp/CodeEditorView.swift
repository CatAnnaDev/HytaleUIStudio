import SwiftUI
import AppKit
import HytaleUICore

final class CompletingTextView: NSTextView {
    var completionProvider: ((String, Int) -> CompletionResult)?
    private var lastResult: CompletionResult?

    override var rangeForUserCompletion: NSRange {
        guard let completionProvider else { return super.rangeForUserCompletion }
        let text = string
        let selection = selectedRange()
        let charCursor = CompletingTextView.characterOffset(in: text, utf16Location: selection.location)
        let result = completionProvider(text, charCursor)
        lastResult = result
        let start = CompletingTextView.utf16Location(in: text, characterOffset: result.replaceStart)
        let end = CompletingTextView.utf16Location(in: text, characterOffset: result.replaceEnd)
        return NSRange(location: start, length: max(0, end - start))
    }

    func currentCompletions() -> [String] {
        lastResult?.items.map { $0.insertText } ?? []
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard let inserted = string as? String, let last = inserted.last, CompletingTextView.isTrigger(last) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.complete(nil)
        }
    }

    private static func isTrigger(_ character: Character) -> Bool {
        character == "_" || character == "@" || character == "$" || character == "." || character.isLetter || character.isNumber
    }

    static func characterOffset(in text: String, utf16Location: Int) -> Int {
        guard let index = String.Index(utf16Offset: utf16Location, in: text) as String.Index?,
              index <= text.endIndex else {
            return text.count
        }
        return text.distance(from: text.startIndex, to: index)
    }

    static func utf16Location(in text: String, characterOffset: Int) -> Int {
        let clamped = max(0, min(characterOffset, text.count))
        let index = text.index(text.startIndex, offsetBy: clamped)
        return index.utf16Offset(in: text)
    }
}

struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var store: DocumentStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CompletingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = store.sourceText
        textView.completionProvider = { [weak store] text, cursor in
            guard let store else { return CompletionResult(replaceStart: cursor, replaceEnd: cursor, items: []) }
            return SourceAssist.complete(source: text, cursor: cursor, moduleMembers: { store.moduleMemberNames($0) })
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        context.coordinator.ruler = ruler

        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observeScrolling(scrollView.contentView)

        if let storage = textView.textStorage {
            SyntaxHighlighter.highlight(storage, font: CodeEditorView.editorFont)
        }
        return scrollView
    }

    static let editorFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CompletingTextView else { return }
        if textView.string != store.sourceText {
            let selected = textView.selectedRange()
            textView.string = store.sourceText
            let safeLocation = min(selected.location, (store.sourceText as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            if let storage = textView.textStorage {
                SyntaxHighlighter.highlight(storage, font: CodeEditorView.editorFont)
            }
        }

        if let ruler = context.coordinator.ruler {
            ruler.errorLines = Set(store.diagnostics.filter { $0.severity == .error }.map { $0.range.start.line })
            ruler.warningLines = Set(store.requirementWarnings.map { $0.range.start.line })
            ruler.needsDisplay = true
        }

        if let target = store.scrollTarget {
            let text = textView.string
            let location = CompletingTextView.utf16Location(in: text, characterOffset: target)
            let lineRange = (text as NSString).lineRange(for: NSRange(location: min(location, (text as NSString).length), length: 0))
            textView.scrollRangeToVisible(lineRange)
            textView.setSelectedRange(lineRange)
            DispatchQueue.main.async { store.scrollTarget = nil }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let store: DocumentStore
        weak var textView: CompletingTextView?
        weak var ruler: LineNumberRulerView?

        init(store: DocumentStore) {
            self.store = store
        }

        func observeScrolling(_ contentView: NSClipView) {
            NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: contentView)
        }

        @objc private func boundsChanged() {
            ruler?.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            store.sourceText = textView.string
            store.onSourceEdited()
            if let storage = textView.textStorage {
                SyntaxHighlighter.highlight(storage, font: CodeEditorView.editorFont)
            }
            ruler?.needsDisplay = true
        }

        func textView(_ view: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            guard let completing = view as? CompletingTextView else { return [] }
            return completing.currentCompletions()
        }
    }
}
