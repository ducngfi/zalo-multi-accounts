import SwiftUI
import ZaloProfilesCore

@main
struct ZaloSwitcherApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if model.busy != nil {
                Image(systemName: "hourglass")
            } else {
                if model.copying != nil {
                    Image(systemName: "externaldrive")
                } else if model.lowSpace {
                    Image(systemName: "exclamationmark.triangle")
                } else {
                    Image(systemName: "person.2.circle")
                }
                if let name = model.currentName { Text(name) }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.busy ?? model.headline)
        if let disk = model.diskLine { Text(disk) }
        if let copying = model.copying {
            Text(copying)
            Button("Cancel") { model.cancelCopy() }
        }

        Divider()

        let profiles = model.statuses
        if profiles.isEmpty {
            Text("No profiles yet")
        }
        ForEach(profiles, id: \.profile.id) { status in
            Toggle(isOn: Binding(get: { status.place == .main }, set: { _ in model.switchTo(status) })) {
                Text(label(for: status))
            }
            .disabled(model.busy != nil || status.isOpenSideBySide)
        }

        Divider()

        Button("Add Account…") { model.addAccount() }
            .disabled(model.busy != nil)
        if model.mainSlot == .unsaved {
            Button("Save Current Account as Profile…") { model.saveCurrent() }
                .disabled(model.busy != nil)
        }

        Menu("Side by Side (Experimental)") {
            let others = profiles.filter { $0.place != .main }
            ForEach(others, id: \.profile.id) { status in
                Button(status.isOpenSideBySide ? "Show \(status.profile.name)" : "Open \(status.profile.name)") {
                    model.openSideBySide(status)
                }
                if status.isOpenSideBySide {
                    Button("Close \(status.profile.name)") { model.close(status) }
                }
            }
            if !others.isEmpty { Divider() }
            Button("Add Account in a Second Window…") { model.addAccountSideBySide() }
            Divider()
            Text("Calls work reliably in one window at a time.")
        }
        .disabled(model.busy != nil)

        Menu("Back Up") {
            ForEach(profiles.filter { $0.place != .new }, id: \.profile.id) { status in
                Button("Back Up \(status.profile.name)…") { model.backUp(status) }
            }
            Divider()
            Button("Restore from Backup…") { model.restore() }
        }
        .disabled(model.busy != nil || model.copying != nil)

        Menu("Manage Profiles") {
            Menu("Rename") {
                ForEach(profiles, id: \.profile.id) { status in
                    Button(status.profile.name) { model.rename(status) }
                }
            }
            Menu("Move to Trash") {
                ForEach(profiles.filter { $0.place != .main }, id: \.profile.id) { status in
                    Button(status.profile.name) { model.remove(status) }
                        .disabled(status.isOpenSideBySide)
                }
            }
            Divider()
            Button("Show Profiles in Finder") { model.showProfilesFolder() }
        }
        .disabled(model.busy != nil)

        Divider()

        Button(model.mainRunning ? "Show Zalo" : "Open Zalo") { model.openZalo() }
            .disabled(model.busy != nil)
        Toggle("Open at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
        Button("Quit Zalo Switcher") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func label(for status: ProfileStatus) -> String {
        let size = model.sizes[status.profile.id].map { "  —  \(Disk.format($0))" } ?? ""
        switch status.place {
        case .main: return status.profile.name + size
        case .parked: return status.profile.name + size + (status.isOpenSideBySide ? "  (open in second window)" : "")
        case .new: return status.profile.name + "  (not logged in yet)"
        }
    }
}
