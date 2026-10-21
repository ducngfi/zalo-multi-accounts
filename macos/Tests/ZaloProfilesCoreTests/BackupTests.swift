import XCTest
@testable import ZaloProfilesCore

extension ProfileManagerTests {
    /// A folder standing in for the external drive.
    func makeDrive() throws -> URL {
        let drive = root.appendingPathComponent("Drive", isDirectory: true)
        try fm.createDirectory(at: drive, withIntermediateDirectories: true)
        return drive
    }

    /// Personal in the main Zalo (running) and Work parked, each with a few files.
    func makeTwoProfiles() throws {
        try makeLiveData(account: "111111")
        let media = layout.liveData.appendingPathComponent("media/111111")
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 200_000).write(to: media.appendingPathComponent("photo.jpg"))
        try manager.saveCurrent(as: "Personal")
        try manager.switchTo(try manager.addProfile(named: "Work").id)
        try makeLiveData(account: "222222")
        try manager.switchTo("personal")
        zalo.launches.removeAll()
    }

    func contents(of folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let scan = try XCTUnwrap(fm.enumerator(atPath: folder.path))
        while let path = scan.nextObject() as? String {
            if scan.fileAttributes?[.type] as? FileAttributeType == .typeRegular {
                result[path] = try Data(contentsOf: folder.appendingPathComponent(path))
            }
        }
        return result
    }

    func leftovers() -> [String] {
        ((try? fm.contentsOfDirectory(atPath: layout.profilesRoot.path)) ?? []).filter { $0.hasPrefix(".") }
    }

    func test_statusesSayWhereDataIsAndHowBigItIs() throws {
        try makeTwoProfiles()
        let personal = try XCTUnwrap(manager.status(of: "personal"))
        let work = try XCTUnwrap(manager.status(of: "work"))
        XCTAssertEqual(personal.dataFolder, layout.liveData)
        XCTAssertEqual(work.dataFolder, layout.parkedData("work"))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(manager.dataSize(of: personal)), 200_000)
        XCTAssertNil(manager.dataSize(of: ProfileStatus(profile: personal.profile, place: .new)))
    }

    func test_lowSpaceWarningBelowTheThreshold() {
        manager.freeSpaceProvider = { _ in 6_000_000_000 }
        XCTAssertNil(manager.lowSpaceWarning())
        manager.freeSpaceProvider = { _ in 3_000_000_000 }
        XCTAssertNotNil(manager.lowSpaceWarning())
    }

    func test_backupOfAParkedProfileCopiesEverythingWithoutTouchingZalo() throws {
        try makeTwoProfiles()
        let drive = try makeDrive()

        let backup = try manager.backup("work", to: drive)

        XCTAssertEqual(backup.deletingLastPathComponent().lastPathComponent, "Zalo Backups")
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("work "))
        XCTAssertEqual(try contents(of: backup.appendingPathComponent("ZaloData")),
                       try contents(of: layout.parkedData("work")))
        let info = try manager.readBackup(backup)
        XCTAssertEqual(info.profileName, "Work")
        XCTAssertEqual(info.zaloUserID, "222222")
        XCTAssertEqual(info.files, try contents(of: layout.parkedData("work")).count)
        XCTAssertTrue(zalo.launches.isEmpty, "a profile that isn't open needs no Zalo restart")
        XCTAssertEqual(leftovers(), [], "the snapshot is removed")
    }

    func test_backupOfTheOpenMainProfileClosesZaloBrieflyAndReopensIt() throws {
        try makeTwoProfiles()
        let drive = try makeDrive()

        let backup = try manager.backup("personal", to: drive)

        XCTAssertEqual(zalo.launches, ["quit:ZaloData", "main"])
        XCTAssertNotNil(manager.mainZaloPID())
        XCTAssertEqual(try contents(of: backup.appendingPathComponent("ZaloData"))["media/111111/photo.jpg"]?.count, 200_000)
        XCTAssertEqual(liveSession(), "session of 111111", "the original stays in place")
    }

    func test_backupOfAProfileOpenInItsOwnWindowReopensItThere() throws {
        try makeTwoProfiles()
        try manager.open("work")
        zalo.launches.removeAll()

        try manager.backup("work", to: try makeDrive())

        XCTAssertEqual(zalo.launches, ["quit:ZaloData", "isolated:work"])
        XCTAssertEqual(manager.status(of: "work")?.isOpen, true)
    }

    func test_backupRefusalsLeaveNothingBehind() throws {
        try makeTwoProfiles()
        let drive = try makeDrive()
        let empty = try manager.addProfile(named: "Empty")

        XCTAssertThrowsError(try manager.backup(empty.id, to: drive)) {
            XCTAssertEqual($0 as? ProfileError, .nothingToBackUp("Empty"))
        }
        XCTAssertThrowsError(try manager.backup("work", to: layout.profileHome("personal"))) {
            XCTAssertEqual($0 as? ProfileError, .badBackupFolder)
        }
        XCTAssertThrowsError(try manager.backup("work", to: root.appendingPathComponent("missing"))) {
            guard case .notAFolder = $0 as? ProfileError else { return XCTFail("got \($0)") }
        }
        manager.freeSpaceProvider = { _ in 1000 }
        XCTAssertThrowsError(try manager.backup("work", to: drive)) {
            guard case .notEnoughSpace = $0 as? ProfileError else { return XCTFail("got \($0)") }
        }
        XCTAssertFalse(fm.fileExists(atPath: drive.appendingPathComponent("Zalo Backups").path))
        XCTAssertTrue(zalo.launches.isEmpty)
        XCTAssertEqual(leftovers(), [])
    }

    func test_cancelledBackupRemovesTheUnfinishedCopy() throws {
        try makeTwoProfiles()
        let drive = try makeDrive()
        let cancel = CancelFlag()
        cancel.cancel()

        XCTAssertThrowsError(try manager.backup("personal", to: drive, cancel: cancel)) {
            XCTAssertEqual($0 as? ProfileError, .cancelled)
        }
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: drive.appendingPathComponent("Zalo Backups").path), [])
        XCTAssertEqual(leftovers(), [])
        XCTAssertNotNil(manager.mainZaloPID(), "Zalo was reopened after the snapshot")
    }

    func test_restoreAddsANewProfileAndNeverReplacesOne() throws {
        try makeTwoProfiles()
        let backup = try manager.backup("work", to: try makeDrive())

        let restored = try manager.restore(from: backup, as: "Work (restored)")

        XCTAssertEqual(restored.id, "work-restored")
        let status = try XCTUnwrap(manager.status(of: restored.id))
        XCTAssertEqual(status.place, .parked)
        XCTAssertEqual(status.zaloUserID, "222222")
        var original = try contents(of: layout.parkedData("work"))
        var copy = try contents(of: layout.parkedData(restored.id))
        XCTAssertEqual(copy.removeValue(forKey: ProfileManager.markerName), Data("work-restored\n".utf8))
        original.removeValue(forKey: ProfileManager.markerName)
        XCTAssertEqual(copy, original)
        XCTAssertEqual(manager.profiles().count, 3, "the original Work profile is still there")
        XCTAssertThrowsError(try manager.restore(from: backup, as: "Work")) {
            XCTAssertEqual($0 as? ProfileError, .nameTaken("Work"))
        }
        XCTAssertEqual(leftovers(), [])
    }

    func test_restoreRejectsDamagedBackupsAndFullDisks() throws {
        try makeTwoProfiles()
        let backup = try manager.backup("work", to: try makeDrive())

        manager.freeSpaceProvider = { _ in 4_000_000_000 }
        XCTAssertThrowsError(try manager.restore(from: backup, as: "Copy")) {
            guard case .notEnoughSpace = $0 as? ProfileError else { return XCTFail("got \($0)") }
        }
        manager.freeSpaceProvider = { _ in 100_000_000_000 }

        try fm.removeItem(at: backup.appendingPathComponent("ZaloData/Cookies"))
        XCTAssertThrowsError(try manager.restore(from: backup, as: "Copy")) {
            guard case .copyMismatch = $0 as? ProfileError else { return XCTFail("got \($0)") }
        }
        XCTAssertThrowsError(try manager.restore(from: try makeDrive(), as: "Copy")) {
            guard case .notABackup = $0 as? ProfileError else { return XCTFail("got \($0)") }
        }
        XCTAssertEqual(manager.profiles().map(\.id), ["personal", "work"])
        XCTAssertEqual(leftovers(), [])
    }

    func test_hardLinkedFilesAreBackedUpAndRestoredOnceAndStayLinked() throws {
        try makeTwoProfiles()
        // Zalo keeps much of its media under two names that share the same data.
        let media = layout.liveData.appendingPathComponent("media/111111")
        let big = media.appendingPathComponent("video.mp4")
        try Data(repeating: 9, count: 1_000_000).write(to: big)
        let other = layout.liveData.appendingPathComponent("Database/_production/111111/video-link.mp4")
        try fm.linkItem(at: big, to: other)

        let backup = try manager.backup("personal", to: try makeDrive())

        let info = try manager.readBackup(backup)
        XCTAssertEqual(info.links, 1)
        let copy = backup.appendingPathComponent("ZaloData")
        let a = try fm.attributesOfItem(atPath: copy.appendingPathComponent("media/111111/video.mp4").path)
        let b = try fm.attributesOfItem(atPath: copy.appendingPathComponent("Database/_production/111111/video-link.mp4").path)
        XCTAssertEqual(a[.systemFileNumber] as? Int, b[.systemFileNumber] as? Int, "still one file under two names")
        let allFiles = try contents(of: copy)
        let total = allFiles.values.reduce(0) { $0 + Int64($1.count) }
        XCTAssertEqual(info.bytes, total - 1_000_000, "the linked data is counted once")
        XCTAssertEqual(info.files, allFiles.count)

        let restored = try manager.restore(from: backup, as: "Personal copy")
        let data = layout.parkedData(restored.id)
        let c = try fm.attributesOfItem(atPath: data.appendingPathComponent("media/111111/video.mp4").path)
        let d = try fm.attributesOfItem(atPath: data.appendingPathComponent("Database/_production/111111/video-link.mp4").path)
        XCTAssertEqual(c[.systemFileNumber] as? Int, d[.systemFileNumber] as? Int)
        XCTAssertEqual(c[.size] as? Int, 1_000_000)
    }

    func test_closeQuitsOnlyThatProfilesWindow() throws {
        try makeTwoProfiles()
        try manager.open("work")

        try manager.close("work")

        XCTAssertEqual(manager.status(of: "work")?.isOpen, false)
        XCTAssertNotNil(manager.mainZaloPID(), "the main Zalo keeps running")
        try manager.close("work")  // closing a closed profile does nothing
    }

    func test_staleTemporaryFoldersAreCleanedUpButRecentOnesKept() throws {
        try fm.createDirectory(at: layout.profilesRoot, withIntermediateDirectories: true)
        let old = Int(Date().timeIntervalSince1970) - 13 * 3600
        let now = Int(Date().timeIntervalSince1970)
        for name in [".snapshot-\(old)-a", ".restore-\(old)-b", ".snapshot-\(now)-c"] {
            try fm.createDirectory(at: layout.profilesRoot.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        manager.removeStaleTemporaryFolders()
        XCTAssertEqual(leftovers(), [".snapshot-\(now)-c"])
    }
}
