import XCTest
@testable import ZaloProfilesCore

final class DemoTests: XCTestCase {
    func test_demoHasFourSyntheticAccountsInEveryState() throws {
        let manager = try Demo.makeManager()
        defer { try? FileManager.default.removeItem(at: Demo.root) }

        XCTAssertTrue(manager.layout.realHome.path.hasPrefix(Demo.root.path), "the demo never uses the real home")
        let statuses = manager.statuses()
        XCTAssertEqual(statuses.map(\.profile.name), ["Cá nhân", "Công ty An Phát", "Cửa hàng Hoa Mai", "Shop mới"])
        let byName = Dictionary(uniqueKeysWithValues: statuses.map { ($0.profile.name, $0) })
        XCTAssertEqual(byName["Cá nhân"]?.place, .main)
        XCTAssertNotNil(byName["Cá nhân"]?.runningPID)
        XCTAssertTrue(byName["Cửa hàng Hoa Mai"]?.isOpenSideBySide ?? false)
        XCTAssertEqual(byName["Công ty An Phát"]?.place, .parked)
        XCTAssertEqual(byName["Shop mới"]?.place, .new)
        XCTAssertEqual(manager.dataSize(of: try XCTUnwrap(byName["Cá nhân"])), 8_420_000_000)

        // Switching works on the synthetic data, and sizes follow the data.
        try manager.switchTo(try XCTUnwrap(byName["Công ty An Phát"]).profile.id)
        let after = try XCTUnwrap(manager.statuses().first { $0.profile.name == "Công ty An Phát" })
        XCTAssertEqual(after.place, .main)
        XCTAssertEqual(manager.dataSize(of: after), 640_000_000)
    }
}
