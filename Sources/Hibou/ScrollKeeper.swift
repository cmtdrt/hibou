import AppKit
import SwiftUI

/// Tracks the conversation's scroll position through the underlying NSScrollView,
/// so the popup can reopen exactly where the user left off.
@MainActor
final class ScrollKeeper {
    private weak var scrollView: NSScrollView?
    private var observer: NSObjectProtocol?
    /// Ignore scroll reports until the saved position has been restored.
    private var restored = false

    var onScroll: ((_ offsetFromTop: CGFloat, _ atBottom: Bool) -> Void)?

    func attach(_ newScrollView: NSScrollView, restoreTo offset: CGFloat?, atBottom: Bool) {
        guard newScrollView !== scrollView else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        scrollView = newScrollView
        restored = false
        let clip = newScrollView.contentView
        clip.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        // Wait for SwiftUI to lay the messages out before scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.restore(offset: offset, atBottom: atBottom)
        }
    }

    func restore(offset: CGFloat?, atBottom: Bool) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let maxTop = max(0, document.frame.height - clip.bounds.height)
        let top = (atBottom || offset == nil) ? maxTop : min(max(0, offset!), maxTop)
        let y = document.isFlipped ? top : maxTop - top
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
        restored = true
        report()
    }

    private func report() {
        guard restored, let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let maxTop = max(0, document.frame.height - clip.bounds.height)
        let top = document.isFlipped ? clip.bounds.minY : maxTop - clip.bounds.minY
        onScroll?(top, maxTop - top < 24)
    }
}

/// Invisible view that hands back the NSScrollView it lives in.
struct EnclosingScrollViewReader: NSViewRepresentable {
    var onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView { onResolve(scrollView) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView { onResolve(scrollView) }
        }
    }
}
