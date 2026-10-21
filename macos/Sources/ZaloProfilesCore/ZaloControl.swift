import AppKit
import Foundation

/// Everything the profile manager needs from the running system. Tests swap in a fake.
public protocol ZaloControl {
    /// The pid of the Zalo instance that has `dataFolder` open, if any.
    func pidUsing(dataFolder: URL) -> pid_t?
    /// Whether any Zalo instance is running (main or side by side).
    func anyInstanceRunning() -> Bool
    /// Asks the Zalo instance using `dataFolder` to quit, and waits until it and its helpers are gone.
    func quit(dataFolder: URL, timeout: TimeInterval) throws
    /// Starts Zalo normally, so it uses the main `ZaloData` folder.
    func launchMain(app: URL) throws
    /// Starts another Zalo instance whose home folder is `home`.
    func launchIsolated(app: URL, home: URL) throws
    /// Brings an already running instance to the front.
    func activate(pid: pid_t)
}

public final class SystemZaloControl: ZaloControl {
    public init() {}

    public func pidUsing(dataFolder: URL) -> pid_t? {
        // Chromium keeps a `SingletonLock` symlink to "<host>-<pid>" while a profile folder is open.
        let lock = dataFolder.appendingPathComponent("SingletonLock").path
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: lock),
              let dash = target.lastIndex(of: "-"),
              let pid = pid_t(target[target.index(after: dash)...]),
              isAlive(pid),
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == ZaloApp.bundleID
        else { return nil }
        return pid
    }

    public func anyInstanceRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: ZaloApp.bundleID).isEmpty
    }

    public func quit(dataFolder: URL, timeout: TimeInterval) throws {
        guard let pid = pidUsing(dataFolder: dataFolder) else { return }
        // Wait for the helpers too: the call and screenshot helpers write logs into the data folder.
        let related = relatedProcesses(of: pid, dataFolder: dataFolder)
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.terminate()

        let deadline = Date().addingTimeInterval(timeout)
        var windowsGoneSince: Date?
        var accountOpen: Bool?
        var lastSignal = Date.distantPast
        while Date() < deadline {
            if related.allSatisfy({ !isAlive($0) }) { return }
            // At the login screen, Zalo closes its window and renderers when asked to quit, then may
            // never exit. With no account open there is nothing to save, so after a moment finish the
            // quit with SIGTERM, the polite request macOS also sends at shutdown, repeated every few
            // seconds until it goes. A Zalo that still shows a window, or has an account's messages
            // open, is never sent it.
            if isAlive(pid), !hasRenderer(pid) {
                let since = windowsGoneSince ?? Date()
                windowsGoneSince = since
                if Date().timeIntervalSince(since) > Self.stuckQuitGrace {
                    if accountOpen == nil {
                        accountOpen = hasAccountOpen(related.filter(isAlive), dataFolder: dataFolder)
                    }
                    if accountOpen == false, Date().timeIntervalSince(lastSignal) > 5 {
                        kill(pid, SIGTERM)
                        lastSignal = Date()
                    }
                }
            } else {
                windowsGoneSince = nil
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw ProfileError.zaloDidNotQuit
    }

    /// How long a Zalo at the login screen may sit without a window, still running, before SIGTERM.
    static let stuckQuitGrace: TimeInterval = 3

    /// Whether any of these processes has a Zalo account's databases open, that is, someone is logged in.
    private func hasAccountOpen(_ pids: Set<pid_t>, dataFolder: URL) -> Bool {
        let list = pids.map(String.init).joined(separator: ",")
        // lsof exits with 1 when one of the processes has just gone.
        guard !pids.isEmpty, let output = try? run("/usr/sbin/lsof", ["-n", "-P", "-Fn", "-p", list], allowFailure: true)
        else { return true }
        let accounts = "n" + dataFolder.appendingPathComponent("Database/_production").path + "/"
        return output.split(separator: "\n").contains { line in
            guard line.hasPrefix(accounts) else { return false }
            let parts = line.dropFirst(accounts.count).split(separator: "/")
            return parts.count > 1 && parts[0].count >= 6 && parts[0].allSatisfy(\.isNumber)
        }
    }

    public func launchMain(app: URL) throws {
        // With another instance already running, a plain `open` would only bring that one forward.
        var args = ["-a", app.path]
        if anyInstanceRunning() { args.insert("-n", at: 0) }
        try runOpen(args)
    }

    public func launchIsolated(app: URL, home: URL) throws {
        // CoreFoundation reads CFFIXED_USER_HOME for the home folder, so Electron's appData becomes
        // `<home>/Library/Application Support` and Zalo opens `<home>/Library/Application Support/ZaloData`.
        try runOpen(["-n", "-a", app.path, "--env", "CFFIXED_USER_HOME=\(home.path)"])
    }

    public func activate(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    private func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Whether the process still has a renderer, that is, a window or page that could hold unsaved work.
    private func hasRenderer(_ pid: pid_t) -> Bool {
        guard let output = try? run("/bin/ps", ["-axww", "-o", "ppid=,command="]) else { return true }
        return output.split(separator: "\n").contains { line in
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            return fields.count == 2 && pid_t(fields[0]) == pid && fields[1].contains("--type=renderer")
        }
    }

    /// The main process, its descendants, and any of Zalo's own processes whose command line names
    /// the data folder (helpers that outlive their parent). Other programs that mention the folder,
    /// such as a Terminal command, don't count.
    private func relatedProcesses(of root: pid_t, dataFolder: URL) -> Set<pid_t> {
        var result: Set<pid_t> = [root]
        // Every Zalo process runs from inside the app bundle the main process runs from.
        let appPath = NSRunningApplication(processIdentifier: root)?.bundleURL?.path ?? "/Applications/Zalo.app"
        guard let output = try? run("/bin/ps", ["-axww", "-o", "pid=,ppid=,command="]) else { return result }
        var children: [pid_t: [pid_t]] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count >= 2, let pid = pid_t(fields[0]), let ppid = pid_t(fields[1]) else { continue }
            children[ppid, default: []].append(pid)
            if fields.count == 3, fields[2].hasPrefix(appPath), fields[2].contains(dataFolder.path) {
                result.insert(pid)
            }
        }
        var seen: Set<pid_t> = [root]
        var queue = [root]
        while let next = queue.popLast() {
            for child in children[next] ?? [] where seen.insert(child).inserted {
                queue.append(child)
            }
        }
        return result.union(seen)
    }

    private func runOpen(_ args: [String]) throws {
        do {
            _ = try run("/usr/bin/open", args)
        } catch {
            throw ProfileError.launchFailed(String(describing: error))
        }
    }
}

struct CommandFailed: Error, CustomStringConvertible {
    var description: String
}

@discardableResult
func run(_ tool: String, _ args: [String], allowFailure: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 || allowFailure else {
        let message = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw CommandFailed(description: "\(tool) exited with \(process.terminationStatus): \(message)")
    }
    return String(decoding: data, as: UTF8.self)
}
