import AppKit

// `--demo` runs the app on synthetic accounts in a temporary folder, without touching Zalo.
// `--render-screenshots <folder> [--only <name>]` draws the README screenshots from the demo data
// and exits.
let arguments = CommandLine.arguments

func value(after flag: String) -> String? {
    arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
}

let screenshotFolder = value(after: "--render-screenshots").map { URL(fileURLWithPath: $0, isDirectory: true) }
let mode: AppDelegate.Mode = screenshotFolder.map { .screenshots($0, only: value(after: "--only")) }
    ?? (arguments.contains("--demo") ? .demo : .normal)

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(mode: mode)
    app.delegate = delegate
    app.run()
}
