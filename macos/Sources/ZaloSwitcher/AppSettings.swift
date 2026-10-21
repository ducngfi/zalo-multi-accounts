import AppKit
import ServiceManagement

/// The person's choices, kept in the app's preferences. The demo keeps its own copy, so trying
/// the demo never changes the real app's settings.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showDockIcon = "showDockIcon"
        static let lowSpaceGB = "lowSpaceGB"
    }

    private let defaults: UserDefaults
    private let isDemo: Bool
    private var demoOpenAtLogin = false

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) }
    }
    /// Below this many GB free, the app warns and asks before adding or opening accounts.
    /// zalo-profiles reads the same value.
    @Published var lowSpaceGB: Int {
        didSet { defaults.set(lowSpaceGB, forKey: Key.lowSpaceGB) }
    }

    init(isDemo: Bool) {
        self.isDemo = isDemo
        defaults = isDemo ? UserDefaults(suiteName: "local.zalo-switcher.demo") ?? .standard : .standard
        defaults.register(defaults: [Key.showMenuBarIcon: true, Key.showDockIcon: true, Key.lowSpaceGB: 5])
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        showDockIcon = defaults.bool(forKey: Key.showDockIcon)
        lowSpaceGB = defaults.integer(forKey: Key.lowSpaceGB)
    }

    var openAtLogin: Bool {
        isDemo ? demoOpenAtLogin : SMAppService.mainApp.status == .enabled
    }

    func setOpenAtLogin(_ on: Bool) throws {
        objectWillChange.send()
        if isDemo {
            demoOpenAtLogin = on
        } else if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
