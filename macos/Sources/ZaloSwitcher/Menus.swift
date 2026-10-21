import AppKit
import Combine
import ZaloProfilesCore

/// A menu item that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool = true, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        isEnabled = enabled
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

/// The menu-bar item and the Dock icon's menu. Both are rebuilt from the model each time they open.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let openWindow: () -> Void
    private var item: NSStatusItem?
    private var observation: AnyCancellable?

    init(model: AppModel, openWindow: @escaping () -> Void) {
        self.model = model
        self.openWindow = openWindow
        super.init()
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateButton() }
        }
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            item.menu = menu
            self.item = item
            updateButton()
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addAccounts(to: menu)
        return menu
    }

    private func updateButton() {
        guard let button = item?.button else { return }
        let symbol = model.busy != nil ? "hourglass"
            : model.copying != nil ? "externaldrive"
            : model.lowSpace ? "exclamationmark.triangle"
            : "person.2.circle"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Zalo Switcher")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        let name = model.currentName.map { " \($0)" } ?? ""
        button.title = model.isDemo ? " Demo ·\(name)" : name
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(ActionItem(model.busy ?? model.headline, enabled: false) {})
        if let free = model.freeSpace {
            let line = model.lowSpace ? "⚠︎ Ổ đĩa sắp đầy: còn trống \(Disk.format(free))" : "Ổ đĩa còn trống \(Disk.format(free))"
            menu.addItem(ActionItem(line, enabled: false) {})
        }
        if let copying = model.copying {
            menu.addItem(ActionItem(copying, enabled: false) {})
            menu.addItem(ActionItem("Hủy sao chép") { [model] in model.cancelCopy() })
        }
        menu.addItem(.separator())
        menu.addItem(ActionItem("Mở cửa sổ Zalo Switcher…") { [openWindow] in openWindow() })
        menu.addItem(.separator())
        addAccounts(to: menu)
        menu.addItem(.separator())
        menu.addItem(ActionItem("Thoát Zalo Switcher") { NSApp.terminate(nil) })
    }

    /// The accounts, to switch with one click, and the most common actions.
    private func addAccounts(to menu: NSMenu) {
        let idle = model.busy == nil
        if model.statuses.isEmpty {
            menu.addItem(ActionItem("Chưa có tài khoản nào", enabled: false) {})
        }
        for status in model.statuses {
            var title = status.profile.name
            if let size = model.sizes[status.profile.id] { title += "  —  \(Disk.format(size))" }
            if status.isOpenSideBySide { title += "  (đang mở ở cửa sổ thứ hai)" }
            if status.place == .new { title += "  (chưa đăng nhập)" }
            menu.addItem(ActionItem(title, enabled: idle && !status.isOpenSideBySide, checked: status.place == .main) { [model] in
                model.switchTo(status)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ActionItem("Thêm tài khoản…", enabled: idle) { [model] in model.addAccount() })

        let side = NSMenu()
        side.autoenablesItems = false
        for status in model.statuses where status.place != .main {
            if status.isOpenSideBySide {
                side.addItem(ActionItem("Hiện \(status.profile.name)") { [model] in model.openSideBySide(status) })
                side.addItem(ActionItem("Đóng \(status.profile.name)") { [model] in model.close(status) })
            } else {
                side.addItem(ActionItem("Mở \(status.profile.name)") { [model] in model.openSideBySide(status) })
            }
        }
        side.addItem(.separator())
        side.addItem(ActionItem("Thêm tài khoản ở cửa sổ thứ hai…") { [model] in model.addAccountSideBySide() })
        side.addItem(.separator())
        side.addItem(ActionItem("Gọi thoại và video chỉ ổn định ở một cửa sổ.", enabled: false) {})
        let sideItem = NSMenuItem(title: "Mở song song (thử nghiệm)", action: nil, keyEquivalent: "")
        sideItem.submenu = side
        sideItem.isEnabled = idle
        menu.addItem(sideItem)
    }
}

/// The app's menus at the top of the screen while it shows in the Dock.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Giới thiệu Zalo Switcher", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Cài đặt…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Ẩn Zalo Switcher", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Ẩn các ứng dụng khác", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Hiện tất cả", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Thoát Zalo Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, titled: "Zalo Switcher", to: main)

        let edit = NSMenu(title: "Sửa")
        edit.addItem(withTitle: "Hoàn tác", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Làm lại", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cắt", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Sao chép", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Dán", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Chọn tất cả", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, titled: "Sửa", to: main)

        let window = NSMenu(title: "Cửa sổ")
        window.addItem(withTitle: "Thu nhỏ", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Phóng to", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Đóng", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(.separator())
        window.addItem(withTitle: "Cửa sổ Zalo Switcher", action: #selector(AppDelegate.showMainWindow(_:)), keyEquivalent: "0")
        add(window, titled: "Cửa sổ", to: main)
        NSApp.windowsMenu = window

        return main
    }

    private static func add(_ menu: NSMenu, titled title: String, to main: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        main.addItem(item)
    }
}
