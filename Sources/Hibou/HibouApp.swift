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
            Image(nsImage: MenuBarIcon.image)
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
}
