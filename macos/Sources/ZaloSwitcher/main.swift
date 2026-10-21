import AppKit

// `--demo` runs the app on synthetic accounts in a temporary folder, without touching Zalo.
// `--render-screenshots <folder>` draws the README screenshots from the demo data and exits.
let arguments = CommandLine.arguments
let screenshotFolder = arguments.firstIndex(of: "--render-screenshots").flatMap { index in
    index + 1 < arguments.count ? URL(fileURLWithPath: arguments[index + 1], isDirectory: true) : nil
}
let mode: AppDelegate.Mode = screenshotFolder.map { .screenshots($0) }
    ?? (arguments.contains("--demo") ? .demo : .normal)

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(mode: mode)
    app.delegate = delegate
    app.run()
}
