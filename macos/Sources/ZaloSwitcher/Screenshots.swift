import AppKit
import SwiftUI

/// Draws the README screenshots from the demo data: real app windows, rendered off screen.
@MainActor
enum Screenshots {
    static let names = ["cua-so-chinh", "cua-so-chinh-toi", "sao-luu", "cai-dat"]

    /// Draws every screenshot, or only the one named. Only the first window an app shows is sure to
    /// draw as active while another app is in front, so make-screenshots.sh draws one per launch.
    static func render(model: AppModel, settings: AppSettings, into folder: URL, only: String? = nil) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        model.refreshNow()
        let main = NSSize(width: 820, height: 560)
        for name in names where only == nil || only == name {
            let url = folder.appendingPathComponent("\(name).png")
            switch name {
            case "cua-so-chinh-toi":
                try await snapshot(MainView(model: model, settings: settings), size: main, title: "Zalo Switcher",
                                   appearance: .darkAqua, to: url)
            case "sao-luu":
                model.showDemoProgress("Đang sao lưu Cá nhân… 42% (3,54 GB / 8,42 GB)", fraction: 0.42)
                try await snapshot(MainView(model: model, settings: settings), size: main, title: "Zalo Switcher",
                                   appearance: .aqua, to: url)
            case "cai-dat":
                try await snapshot(SettingsView(model: model, settings: settings, showsDoneButton: false),
                                   size: NSSize(width: 560, height: 750), title: "Cài đặt", appearance: .aqua, to: url)
            default:
                try await snapshot(MainView(model: model, settings: settings), size: main, title: "Zalo Switcher",
                                   appearance: .aqua, to: url)
            }
        }
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
        if !NSApp.isActive {
            FileHandle.standardError.write(Data("Warning: the app is not in front; \(url.lastPathComponent) may look inactive.\n".utf8))
        }

        guard let frame = window.contentView?.superview else { return }
        frame.layoutSubtreeIfNeeded()
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        print("Wrote \(url.path)")
    }
}
