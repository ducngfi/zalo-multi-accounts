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
        XCTAssertEqual(byName["Cửa hàng Hoa Mai"]?.place, .parked)
        XCTAssertEqual(byName["Cửa hàng Hoa Mai"]?.isOpen, true)
        XCTAssertEqual(byName["Công ty An Phát"]?.place, .parked)
        XCTAssertEqual(byName["Công ty An Phát"]?.isOpen, false)
        XCTAssertEqual(byName["Shop mới"]?.place, .new)
        XCTAssertEqual(manager.dataSize(of: try XCTUnwrap(byName["Cá nhân"])), 8_420_000_000)

        // Opening and making another account the main one work on the synthetic data, and sizes
        // follow the data.
        try manager.makeMain(try XCTUnwrap(byName["Công ty An Phát"]).profile.id)
        let after = Dictionary(uniqueKeysWithValues: manager.statuses().map { ($0.profile.name, $0) })
        XCTAssertEqual(after["Công ty An Phát"]?.place, .main)
        XCTAssertEqual(after["Cá nhân"]?.place, .parked)
        XCTAssertEqual(after.values.filter(\.isOpen).count, 3)
        XCTAssertEqual(manager.dataSize(of: try XCTUnwrap(after["Công ty An Phát"])), 640_000_000)
    }
}
