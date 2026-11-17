import AppKit
import SwiftUI

/// Message input: grows with its content up to `maxLines`, then scrolls with a native scroller.
/// Return sends; Shift+Return or Option+Return inserts a new line.
struct InputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    /// Incremented by the parent to move keyboard focus into the field.
    var focusRequest: Int
    var onSubmit: () -> Void

    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let maxLines: CGFloat = 6
    static var lineHeight: CGFloat { NSLayoutManager().defaultLineHeight(for: font) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text
        context.coordinator.textView = textView
        DispatchQueue.main.async { context.coordinator.recomputeHeight() }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.recomputeHeight()
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputField
        weak var textView: NSTextView?
        var lastFocusRequest = -1

        init(_ parent: InputField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recomputeHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }

        func recomputeHeight() {
            guard let textView, let container = textView.textContainer,
                  let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let used = max(layout.usedRect(for: container).height, InputField.lineHeight)
            let clamped = min(used, InputField.lineHeight * InputField.maxLines)
            if abs(clamped - parent.height) > 0.5 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }
}
