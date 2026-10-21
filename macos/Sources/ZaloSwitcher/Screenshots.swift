import AppKit
import SwiftUI

/// Draws the README screenshots from the demo data: real app windows, rendered off screen.
@MainActor
enum Screenshots {
    static func render(model: AppModel, settings: AppSettings, into folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        model.refreshNow()
        let size = NSSize(width: 820, height: 560)

        for (name, appearance) in [("cua-so-chinh", NSAppearance.Name.aqua), ("cua-so-chinh-toi", .darkAqua)] {
            try await snapshot(MainView(model: model, settings: settings), size: size, title: "Zalo Switcher",
                               appearance: appearance, to: folder.appendingPathComponent("\(name).png"))
        }

        model.showDemoProgress("Đang sao lưu Cá nhân… 42% (3,54 GB / 8,42 GB)", fraction: 0.42)
        try await snapshot(MainView(model: model, settings: settings), size: size, title: "Zalo Switcher",
                           appearance: .aqua, to: folder.appendingPathComponent("sao-luu.png"))

        try await snapshot(SettingsView(model: model, settings: settings, showsDoneButton: false),
                           size: NSSize(width: 560, height: 720), title: "Cài đặt",
                           appearance: .aqua, to: folder.appendingPathComponent("cai-dat.png"))
    }

    /// Draws as the active window, so buttons and switches have their normal colours.
    private final class ActiveWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
    }

    /// Puts a view in a window off screen and saves the window, title bar included, as a PNG.
    private static func snapshot<Content: View>(_ view: Content, size: NSSize, title: String,
                                                appearance: NSAppearance.Name, to url: URL) async throws {
        let window = ActiveWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.appearance = NSAppearance(named: appearance)
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        // Controls only draw in their active colours while the app itself is in front.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 800_000_000)

        guard let frame = window.contentView?.superview else { return }
        frame.layoutSubtreeIfNeeded()
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        print("Wrote \(url.path)")
    }
}
