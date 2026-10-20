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
        while Date() < deadline {
            if related.allSatisfy({ !isAlive($0) }) { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw ProfileError.zaloDidNotQuit
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

    /// The main process, its descendants, and any process whose command line names the data folder.
    private func relatedProcesses(of root: pid_t, dataFolder: URL) -> Set<pid_t> {
        var result: Set<pid_t> = [root]
        guard let output = try? run("/bin/ps", ["-axww", "-o", "pid=,ppid=,command="]) else { return result }
        var children: [pid_t: [pid_t]] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count >= 2, let pid = pid_t(fields[0]), let ppid = pid_t(fields[1]) else { continue }
            children[ppid, default: []].append(pid)
            if fields.count == 3, fields[2].contains(dataFolder.path) { result.insert(pid) }
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
