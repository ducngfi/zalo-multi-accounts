import AppKit
import Combine
import SwiftUI
import ZaloProfilesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    enum Mode {
        case normal
        case demo
        case screenshots(URL, only: String?)
    }

    private let mode: Mode
    private var settings: AppSettings!
    private var model: AppModel!
    private var window: NSWindow?
    private var statusMenu: StatusMenuController?
    private var observations: Set<AnyCancellable> = []

    init(mode: Mode) {
        self.mode = mode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDemo: Bool
        let manager: ProfileManager
        switch mode {
        case .normal:
            isDemo = false
            manager = ProfileManager()
        case .demo, .screenshots:
            isDemo = true
            do {
                manager = try Demo.makeManager()
            } catch {
                Prompt.error(error)
                NSApp.terminate(nil)
                return
            }
        }
        settings = AppSettings(isDemo: isDemo)
        model = AppModel(manager: manager, isDemo: isDemo)
        model.setLowSpaceThreshold(gigabytes: settings.lowSpaceGB)

        if case .screenshots(let folder, let only) = mode {
            NSApp.setActivationPolicy(.accessory)
            Task {
                do {
                    try await Screenshots.render(model: model, settings: settings, into: folder, only: only)
                } catch {
                    FileHandle.standardError.write(Data("\(error)\n".utf8))
                }
                NSApp.terminate(nil)
            }
            return
        }

        NSApp.mainMenu = MainMenu.make()
        model.start()
        statusMenu = StatusMenuController(model: model) { [weak self] in self?.showMainWindow(nil) }

        settings.$showDockIcon
            .sink { [weak self] show in self?.applyDockIcon(show) }
            .store(in: &observations)
        settings.$showMenuBarIcon
            .sink { [weak self] show in self?.statusMenu?.setVisible(show) }
            .store(in: &observations)
        settings.$lowSpaceGB
            .dropFirst()
            .sink { [weak self] gigabytes in self?.model.setLowSpaceThreshold(gigabytes: gigabytes) }
            .store(in: &observations)

        if !launchedAtLogin() {
            showMainWindow(nil)
        } else if settings.openAllAtLogin {
            // Give Zalo a moment, in case it opens at login by itself; open skips what is already open.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.model.openAll(asking: false)
            }
        }
    }

    /// Clicking the Dock icon, or opening the app again from Finder, Launchpad or Spotlight.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        statusMenu?.dockMenu()
    }

    @objc func showMainWindow(_ sender: Any?) {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings(_ sender: Any?) {
        showMainWindow(nil)
        model.showingSettings = true
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "Dùng nhiều tài khoản Zalo cùng lúc trên một máy Mac, mỗi tài khoản một cửa sổ, không cần đăng xuất hay đăng nhập lại.\n\nDự án độc lập, không liên kết với Zalo hay VNG.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = model.isDemo ? "Zalo Switcher — Bản demo" : "Zalo Switcher"
        window.contentView = NSHostingView(rootView: MainView(model: model, settings: settings))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName(model.isDemo ? "DemoWindow" : "MainWindow")
        return window
    }

    private func applyDockIcon(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        // Leaving the Dock deactivates the app; keep the window in front if it is open.
        if !show, window?.isVisible == true {
            DispatchQueue.main.async { self.showMainWindow(nil) }
        }
    }

    /// When the Mac starts the app at login, it runs in the background without a window.
    private func launchedAtLogin() -> Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        return settings.openAtLogin && ProcessInfo.processInfo.systemUptime < 300
    }
}
