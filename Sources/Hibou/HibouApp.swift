import AppKit
import SwiftUI

@main
struct HibouApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        MenuBarExtra {
            ChatView()
                .environmentObject(store)
        } label: {
            Image(nsImage: store.hasUnread ? MenuBarIcon.withBadge : MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar icon: a monochrome template image that macOS tints for light/dark mode.
enum MenuBarIcon {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            let height: CGFloat = 16
            img.size = NSSize(width: height * img.size.width / img.size.height, height: height)
            img.isTemplate = true
            return img
        }
        // Fallback when running via `swift run` (no .app bundle).
        let fallback = NSImage(systemSymbolName: "bird", accessibilityDescription: "Hibou")!
        fallback.isTemplate = true
        return fallback
    }()

    /// Same icon with a red dot. A template image can't hold color, so the owl is drawn
    /// at display time in the menu bar's text color (follows light/dark menu bar).
    static let withBadge: NSImage = {
        let base = image
        let size = base.size
        let badged = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (dark ? NSColor.white : NSColor.black).set()
            rect.fill(using: .sourceAtop)

            let diameter: CGFloat = 6.5
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemRed.set()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        badged.isTemplate = false
        badged.cacheMode = .never
        return badged
    }()
}
