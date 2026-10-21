import XCTest
@testable import ZaloProfilesCore

/// Pretends to be Zalo: tracks which data folders are "open", and like the real app creates
/// `ZaloData` when it starts without one.
final class FakeZalo: ZaloControl {
    let layout: Layout
    var open: [String: pid_t] = [:]
    var launches: [String] = []
    var refusesToQuit = false
    private var nextPID: pid_t = 1000

    init(layout: Layout) { self.layout = layout }

    func pidUsing(dataFolder: URL) -> pid_t? { open[dataFolder.path] }
    func anyInstanceRunning() -> Bool { !open.isEmpty }

    func quit(dataFolder: URL, timeout: TimeInterval) throws {
        if refusesToQuit { throw ProfileError.zaloDidNotQuit }
        open[dataFolder.path] = nil
        launches.append("quit:\(dataFolder.lastPathComponent)")
    }

    func launchMain(app: URL) throws {
        launches.append("main")
        try FileManager.default.createDirectory(at: layout.liveData, withIntermediateDirectories: true)
        open[layout.liveData.path] = nextPID
        nextPID += 1
    }

    func launchIsolated(app: URL, home: URL) throws {
        launches.append("isolated:\(home.lastPathComponent)")
        let data = home.appendingPathComponent("Library/Application Support/ZaloData")
        open[data.path] = nextPID
        nextPID += 1
    }

    func activate(pid: pid_t) { launches.append("activate:\(pid)") }
}

final class ProfileManagerTests: XCTestCase {
    var root: URL!
    var layout: Layout!
    var zalo: FakeZalo!
    var manager: ProfileManager!
    var trashed: [URL] = []
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("zalo-profiles-tests-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let app = root.appendingPathComponent("Zalo.app")
        try fm.createDirectory(at: home.appendingPathComponent("Library/Application Support"), withIntermediateDirectories: true)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        layout = Layout(realHome: home, zaloApp: app)
        zalo = FakeZalo(layout: layout)
        manager = ProfileManager(layout: layout, zalo: zalo)
        manager.moveToTrash = { [unowned self] url in
            let dest = self.root.appendingPathComponent("Trash-\(url.lastPathComponent)")
            try self.fm.moveItem(at: url, to: dest)
            self.trashed.append(dest)
            return dest
        }
        manager.freeSpaceProvider = { _ in 100_000_000_000 }
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    /// Puts an account's data in the main ZaloData folder, as a logged-in Zalo would leave it.
    func makeLiveData(account: String, running: Bool = true) throws {
        let db = layout.liveData.appendingPathComponent("Database/_production/\(account)")
        try fm.createDirectory(at: db, withIntermediateDirectories: true)
        try Data("messages of \(account)".utf8).write(to: db.appendingPathComponent("Message.db"))
        try Data("session of \(account)".utf8).write(to: layout.liveData.appendingPathComponent("Cookies"))
        if running { zalo.open[layout.liveData.path] = 1 }
    }

    /// Gives a saved profile its own data, as if it had been logged in before.
    @discardableResult
    func makeParkedProfile(_ name: String, account: String) throws -> Profile {
        let profile = try manager.addProfile(named: name)
        let data = layout.parkedData(profile.id)
        let db = data.appendingPathComponent("Database/_production/\(account)")
        try fm.createDirectory(at: db, withIntermediateDirectories: true)
        try Data("session of \(account)".utf8).write(to: data.appendingPathComponent("Cookies"))
        try manager.writeMarker(profile.id, in: data)
        return profile
    }

    func liveSession() -> String? {
        try? String(contentsOf: layout.liveData.appendingPathComponent("Cookies"), encoding: .utf8)
    }

    func test_saveCurrent_registersTheDataThatIsInZalo() throws {
        try makeLiveData(account: "111111")
        XCTAssertEqual(manager.mainSlot(), .unsaved)

        let profile = try manager.saveCurrent(as: "Personal")

        XCTAssertEqual(profile.id, "personal")
        XCTAssertEqual(manager.mainSlot(), .profile("personal"))
        let status = try XCTUnwrap(manager.status(of: "personal"))
        XCTAssertEqual(status.place, .main)
        XCTAssertEqual(status.zaloUserID, "111111")
        XCTAssertNotNil(status.runningPID)
        XCTAssertEqual(liveSession(), "session of 111111", "saving must not touch Zalo's data")
    }

    func test_saveCurrent_refusesWhenThereIsNothingOrItIsAlreadySaved() throws {
        XCTAssertThrowsError(try manager.saveCurrent(as: "X")) { XCTAssertEqual($0 as? ProfileError, .nothingToSave) }
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        XCTAssertThrowsError(try manager.saveCurrent(as: "Other")) {
            XCTAssertEqual($0 as? ProfileError, .alreadySaved("Personal"))
        }
    }

    func test_switchingToANewProfileParksTheCurrentOneAndStartsFresh() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        let work = try manager.addProfile(named: "Work")
        XCTAssertEqual(manager.status(of: "work")?.place, .new)

        try manager.switchTo(work.id)

        XCTAssertEqual(manager.mainSlot(), .profile("work"))
        XCTAssertNil(liveSession(), "the new profile starts without the old session")
        let parked = layout.parkedData("personal")
        XCTAssertEqual(try String(contentsOf: parked.appendingPathComponent("Cookies"), encoding: .utf8), "session of 111111")
        XCTAssertEqual(manager.status(of: "personal")?.place, .parked)
        XCTAssertEqual(zalo.launches, ["quit:ZaloData", "main"])
    }

    func test_switchingBackRestoresEachAccountsOwnDataUntouched() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        try manager.switchTo(try manager.addProfile(named: "Work").id)
        // Log in to the second account in the fresh Zalo.
        try makeLiveData(account: "222222")

        try manager.switchTo("personal")
        XCTAssertEqual(liveSession(), "session of 111111")
        XCTAssertEqual(manager.status(of: "personal")?.zaloUserID, "111111")
        XCTAssertEqual(manager.status(of: "work")?.zaloUserID, "222222")

        try manager.switchTo("work")
        XCTAssertEqual(liveSession(), "session of 222222")
        let message = layout.liveData.appendingPathComponent("Database/_production/222222/Message.db")
        XCTAssertEqual(try String(contentsOf: message, encoding: .utf8), "messages of 222222")
        XCTAssertFalse(fm.fileExists(atPath: layout.liveData.appendingPathComponent("Database/_production/111111").path),
                       "accounts' data must not mix")
    }

    func test_switchRefusesWhileTheCurrentAccountIsUnsaved() throws {
        try makeLiveData(account: "111111")
        let work = try manager.addProfile(named: "Work")
        XCTAssertThrowsError(try manager.switchTo(work.id)) {
            XCTAssertEqual($0 as? ProfileError, .currentDataNotSaved)
        }
        XCTAssertEqual(liveSession(), "session of 111111")
        XCTAssertTrue(zalo.launches.isEmpty)
    }

    func test_nothingMovesWhenZaloWontQuit() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        let work = try manager.addProfile(named: "Work")
        zalo.refusesToQuit = true

        XCTAssertThrowsError(try manager.switchTo(work.id)) { XCTAssertEqual($0 as? ProfileError, .zaloDidNotQuit) }

        XCTAssertEqual(manager.mainSlot(), .profile("personal"))
        XCTAssertEqual(liveSession(), "session of 111111")
        XCTAssertFalse(fm.fileExists(atPath: layout.parkedData("personal").path))
    }

    func test_switchStopsIfTheParkingPlaceIsTaken() throws {
        try makeLiveData(account: "111111", running: false)
        try manager.saveCurrent(as: "Personal")
        let work = try manager.addProfile(named: "Work")
        try fm.createDirectory(at: layout.parkedData("personal"), withIntermediateDirectories: true)

        XCTAssertThrowsError(try manager.switchTo(work.id)) {
            guard case .conflict = $0 as? ProfileError else { return XCTFail("expected a conflict, got \($0)") }
        }
        XCTAssertEqual(liveSession(), "session of 111111")
    }

    func test_switchToAProfileOpenInItsOwnWindowIsRefused() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        let shop = try manager.addProfile(named: "Shop")
        try manager.open(shop.id)

        XCTAssertThrowsError(try manager.switchTo(shop.id)) {
            XCTAssertEqual($0 as? ProfileError, .isOpen("Shop"))
        }
        XCTAssertEqual(liveSession(), "session of 111111")
    }

    func test_markerLossFallsBackToTheLastSwitch() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        try fm.removeItem(at: layout.liveData.appendingPathComponent(ProfileManager.markerName))
        XCTAssertEqual(manager.mainSlot(), .profile("personal"))
    }

    func test_openPreparesASeparateHome() throws {
        let home = layout.realHome
        try fm.createDirectory(at: home.appendingPathComponent("Library/Keychains"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        let shop = try manager.addProfile(named: "Shop")

        try manager.open(shop.id)

        let profileHome = layout.profileHome(shop.id)
        XCTAssertTrue(fm.fileExists(atPath: layout.parkedData(shop.id).path))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: profileHome.appendingPathComponent("Library/Keychains").path),
                       home.appendingPathComponent("Library/Keychains").path)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: profileHome.appendingPathComponent("Downloads").path),
                       home.appendingPathComponent("Downloads").path)
        XCTAssertFalse(fm.fileExists(atPath: profileHome.appendingPathComponent("Desktop").path),
                       "folders the real home doesn't have are not linked")
        XCTAssertEqual(zalo.launches, ["isolated:shop"])
        XCTAssertEqual(manager.status(of: shop.id)?.isOpen, true)

        // Opening it again only brings it forward.
        try manager.open(shop.id)
        XCTAssertEqual(zalo.launches.count, 2)
        XCTAssertTrue(zalo.launches[1].hasPrefix("activate:"))
    }

    func test_accountsOpenAtTheSameTimeWithoutClosingTheMainZalo() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        let work = try makeParkedProfile("Work", account: "222222")
        let shop = try manager.addProfile(named: "Shop")

        try manager.open(work.id)
        try manager.open(shop.id)

        XCTAssertEqual(zalo.launches, ["isolated:work", "isolated:shop"], "the main Zalo is never quit")
        XCTAssertEqual(manager.statuses().filter(\.isOpen).map(\.profile.id), ["personal", "shop", "work"])
        XCTAssertEqual(liveSession(), "session of 111111")
        XCTAssertEqual(manager.status(of: "work")?.place, .parked, "nothing moves to open an account")
    }

    func test_theFirstNewAccountGoesIntoTheEmptyMainSlot() throws {
        let personal = try manager.addProfile(named: "Personal")
        try manager.open(personal.id)
        XCTAssertEqual(manager.mainSlot(), .profile("personal"))
        XCTAssertEqual(zalo.launches, ["main"])

        // Once the main slot has an account, new ones open in windows of their own.
        let work = try manager.addProfile(named: "Work")
        try manager.open(work.id)
        XCTAssertEqual(zalo.launches, ["main", "isolated:work"])
        XCTAssertEqual(manager.mainSlot(), .profile("personal"))
    }

    func test_openAllOpensLoggedInAccountsWithTheMainZaloLast() throws {
        try makeLiveData(account: "111111", running: false)
        try manager.saveCurrent(as: "Personal")
        try makeParkedProfile("Work", account: "222222")
        try makeParkedProfile("Work copy", account: "222222")
        try manager.addProfile(named: "Shop")

        let opened = try manager.openAll()

        XCTAssertEqual(opened, ["Work", "Personal"], "skips the second copy of an account and the one never logged in")
        XCTAssertEqual(zalo.launches, ["isolated:work", "main"])
        XCTAssertEqual(try manager.openAll(), [], "nothing more to open")
    }

    func test_aZaloAccountOpensInOneWindowOnly() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        let work = try makeParkedProfile("Work", account: "222222")
        let copy = try makeParkedProfile("Work copy", account: "222222")
        try manager.open(work.id)

        XCTAssertThrowsError(try manager.open(copy.id)) {
            XCTAssertEqual($0 as? ProfileError, .sameAccountOpen("Work copy", other: "Work"))
        }
        XCTAssertEqual(zalo.launches, ["isolated:work"])
    }

    func test_makeMainSwapsTheFoldersAndKeepsBothAccountsOpen() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        let work = try makeParkedProfile("Work", account: "222222")
        let shop = try makeParkedProfile("Shop", account: "333333")
        try manager.open(work.id)
        try manager.open(shop.id)
        zalo.launches = []

        try manager.makeMain(work.id)

        XCTAssertEqual(manager.mainSlot(), .profile("work"))
        XCTAssertEqual(liveSession(), "session of 222222")
        XCTAssertEqual(manager.status(of: "personal")?.place, .parked)
        XCTAssertEqual(zalo.launches, ["quit:ZaloData", "quit:ZaloData", "main", "isolated:personal"])
        XCTAssertEqual(manager.statuses().filter(\.isOpen).map(\.profile.id), ["personal", "shop", "work"],
                       "both swapped accounts open again, and the other window never closed")
    }

    func test_makeMainRefusesWhileTheMainZaloHoldsAnUnsavedAccount() throws {
        try makeLiveData(account: "111111")
        let work = try makeParkedProfile("Work", account: "222222")
        XCTAssertThrowsError(try manager.makeMain(work.id)) {
            XCTAssertEqual($0 as? ProfileError, .currentDataNotSaved)
        }
        XCTAssertEqual(liveSession(), "session of 111111")
        XCTAssertTrue(zalo.launches.isEmpty)
    }

    func test_closeAllQuitsEveryWindow() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        try manager.open(try makeParkedProfile("Work", account: "222222").id)

        try manager.closeAll()

        XCTAssertTrue(manager.statuses().allSatisfy { !$0.isOpen })
        XCTAssertNil(manager.mainZaloPID())
    }

    func test_removeMovesParkedProfilesToTheTrashOnly() throws {
        try makeLiveData(account: "111111")
        try manager.saveCurrent(as: "Personal")
        let work = try manager.addProfile(named: "Work")

        XCTAssertThrowsError(try manager.remove("personal")) {
            XCTAssertEqual($0 as? ProfileError, .isInMainZalo("Personal"))
        }
        try manager.remove(work.id)
        XCTAssertEqual(manager.profiles().map(\.id), ["personal"])
        XCTAssertEqual(trashed.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: trashed[0].appendingPathComponent("profile.json").path))
    }

    func test_namesAndIds() throws {
        let p = try manager.addProfile(named: "  Đức – Work ")
        XCTAssertEqual(p.id, "duc-work")
        XCTAssertEqual(p.name, "Đức – Work")
        XCTAssertEqual(try manager.find("đức – work").id, "duc-work")
        XCTAssertEqual(try manager.find("duc-work").id, "duc-work")
        XCTAssertThrowsError(try manager.addProfile(named: "ĐỨC – WORK")) {
            XCTAssertEqual($0 as? ProfileError, .nameTaken("ĐỨC – WORK"))
        }
        XCTAssertThrowsError(try manager.addProfile(named: "   ")) { XCTAssertEqual($0 as? ProfileError, .emptyName) }
        XCTAssertEqual(try manager.addProfile(named: "Duc Work!").id, "duc-work-2")
        XCTAssertEqual(try manager.addProfile(named: "Cửa hàng").id, "cua-hang")
        XCTAssertThrowsError(try manager.find("nobody")) { XCTAssertEqual($0 as? ProfileError, .notFound("nobody")) }

        try manager.rename("cua-hang", to: "Shop")
        XCTAssertEqual(try manager.find("shop").id, "cua-hang")
    }
}
