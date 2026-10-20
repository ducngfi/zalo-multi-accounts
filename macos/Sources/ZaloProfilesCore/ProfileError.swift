import Foundation

public enum ProfileError: LocalizedError, Equatable {
    case notFound(String)
    case ambiguous(String)
    case nameTaken(String)
    case emptyName
    case currentDataNotSaved
    case nothingToSave
    case alreadySaved(String)
    case isInMainZalo(String)
    case openSideBySide(String)
    case zaloDidNotQuit
    case zaloNotInstalled(String)
    case conflict(String)
    case moveFailed(from: String, to: String, reason: String)
    case launchFailed(String)
    case nothingToBackUp(String)
    case notAFolder(String)
    case badBackupFolder
    case notEnoughSpace(place: String, needed: Int64, free: Int64)
    case snapshotFailed(String)
    case copyFailed(String, reason: String)
    case copyMismatch(String)
    case notABackup(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notFound(let query):
            return "No profile called “\(query)”."
        case .ambiguous(let query):
            return "More than one profile matches “\(query)”. Use the profile id instead."
        case .nameTaken(let name):
            return "A profile called “\(name)” already exists."
        case .emptyName:
            return "Give the profile a name."
        case .currentDataNotSaved:
            return "The account that is in Zalo now isn't saved as a profile yet. Save it first, so its data is kept when you switch."
        case .nothingToSave:
            return "Zalo has no data on this Mac yet, so there is nothing to save. Add a profile instead."
        case .alreadySaved(let name):
            return "The account in Zalo now is already saved as “\(name)”."
        case .isInMainZalo(let name):
            return "“\(name)” is the profile open in Zalo now. Switch to another profile first."
        case .openSideBySide(let name):
            return "“\(name)” is open in a side-by-side Zalo window. Quit that window first."
        case .zaloDidNotQuit:
            return "Zalo did not quit in time (maybe a call or a dialog is open). Quit Zalo yourself, then try again. Nothing was moved."
        case .zaloNotInstalled(let path):
            return "Zalo isn't installed at \(path)."
        case .conflict(let detail):
            return "Stopped to keep your data safe: \(detail)"
        case .moveFailed(let from, let to, let reason):
            return "Could not move \(from) to \(to): \(reason)"
        case .launchFailed(let reason):
            return "Could not start Zalo: \(reason)"
        case .nothingToBackUp(let name):
            return "“\(name)” has no Zalo data yet, so there is nothing to back up."
        case .notAFolder(let path):
            return "\(path) isn't a folder that can be written to."
        case .badBackupFolder:
            return "Choose a folder outside Zalo's own data and the profiles folder, for example on an external drive."
        case .notEnoughSpace(let place, let needed, let free):
            return "Not enough free space on \(place): this needs about \(Disk.format(needed)), and \(Disk.format(free)) is free."
        case .snapshotFailed(let reason):
            return "Could not take a snapshot of the profile's data: \(reason). Nothing was changed."
        case .copyFailed(let path, let reason):
            return "Could not copy \(path): \(reason)"
        case .copyMismatch(let what):
            return "The copy of \(what) doesn't match the original, so it was not kept."
        case .notABackup(let path):
            return "\(path) isn't a Zalo Switcher backup. Choose a folder inside “Zalo Backups” that holds backup.json and ZaloData."
        case .cancelled:
            return "Cancelled. The unfinished copy was removed; nothing else changed."
        }
    }
}
