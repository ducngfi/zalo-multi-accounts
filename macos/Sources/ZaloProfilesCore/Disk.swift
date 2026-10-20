import Foundation

public enum Disk {
    /// Free space on the disk that holds `url`, the figure `df` shows.
    public static func freeBytes(at url: URL) -> Int64? {
        guard let values = try? existingAncestor(of: url).resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let free = values.volumeAvailableCapacity else { return nil }
        return Int64(free)
    }

    /// The space a folder takes on disk, the figure `du` shows. Symbolic links aren't followed.
    public static func allocatedSize(of folder: URL) -> Int64? {
        // du exits non-zero when a running Zalo removes a file mid-scan; the total is still right.
        guard let output = try? run("/usr/bin/du", ["-sk", folder.path], allowFailure: true),
              let field = output.split(separator: "\t").first,
              let kilobytes = Int64(field.trimmingCharacters(in: .whitespaces)) else { return nil }
        return kilobytes * 1024
    }

    /// Whether two paths are on the same disk.
    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key = URLResourceKey.volumeIdentifierKey
        guard let x = try? existingAncestor(of: a).resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
              let y = try? existingAncestor(of: b).resourceValues(forKeys: [key]).volumeIdentifier as? NSObject
        else { return false }
        return x.isEqual(y)
    }

    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func existingAncestor(of url: URL) -> URL {
        var probe = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
            probe.deleteLastPathComponent()
        }
        return probe
    }
}
