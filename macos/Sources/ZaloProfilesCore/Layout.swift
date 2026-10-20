import AppKit
import Foundation

/// Where Zalo and the saved profiles live on disk.
///
/// Zalo always keeps its data in `<Application Support>/ZaloData` (it ignores `--user-data-dir`).
/// Each profile is a folder under `<Application Support>/Zalo Profiles/<id>/` shaped like a home
/// folder, so a parked profile's data sits at `<id>/Library/Application Support/ZaloData`. That
/// shape lets the same folder be used as a separate home when a profile is opened side by side.
public struct Layout {
    public var realHome: URL
    public var zaloApp: URL

    public init(realHome: URL, zaloApp: URL) {
        self.realHome = realHome
        self.zaloApp = zaloApp
    }

    public var applicationSupport: URL {
        realHome.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// The folder the normal Zalo app reads and writes.
    public var liveData: URL { applicationSupport.appendingPathComponent("ZaloData", isDirectory: true) }

    public var profilesRoot: URL { applicationSupport.appendingPathComponent("Zalo Profiles", isDirectory: true) }

    var stateFile: URL { profilesRoot.appendingPathComponent("state.json") }

    public func profileHome(_ id: String) -> URL {
        profilesRoot.appendingPathComponent(id, isDirectory: true)
    }

    func profileFile(_ id: String) -> URL {
        profileHome(id).appendingPathComponent("profile.json")
    }

    func profileApplicationSupport(_ id: String) -> URL {
        profileHome(id).appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// Where a profile's Zalo data is kept while it is not in the main slot.
    public func parkedData(_ id: String) -> URL {
        profileApplicationSupport(id).appendingPathComponent("ZaloData", isDirectory: true)
    }

    /// The real layout of the current user. Uses the account's home from the user database rather
    /// than `$HOME`, so a stray override can't point the tool at the wrong folder.
    public static func system() -> Layout {
        var home = FileManager.default.homeDirectoryForCurrentUser
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        var app = URL(fileURLWithPath: "/Applications/Zalo.app", isDirectory: true)
        if !FileManager.default.fileExists(atPath: app.path),
           let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ZaloApp.bundleID) {
            app = found
        }
        return Layout(realHome: home, zaloApp: app)
    }
}

enum ZaloApp {
    static let bundleID = "com.vng.zalo"
}
