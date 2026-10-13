import XCTest
@testable import Huati

@MainActor final class HuatiTests: XCTestCase {
    func testBundledBridgeAndCampusResources() throws {
        let core = try CoreBridge()
        XCTAssertFalse(core.map.isEmpty)
        XCTAssertFalse(core.graph.isEmpty)
        XCTAssertEqual(try core.number("randomDuration", [0]), 720001)
        XCTAssertEqual(try core.number("randomDuration", [0.999999999]), 959999)
        for point in AppModel.referencePoints {
            let wgs = try core.object("wgs", [point])
            XCTAssertTrue(try core.flag("contains", [wgs, core.boundary]))
        }
    }
    func testAndroidCompatibleEncryption() throws {
        let encrypted = try HuatiAPI.encrypt(["fixture": 1], iv: Data(count: 16))
        XCTAssertEqual(encrypted, "AAAAAAAAAAAAAAAAAAAAAA==:BGu00rSpvgFKuj16y9KktQ==")
        XCTAssertNotEqual(try HuatiAPI.encrypt(["fixture": 1]), encrypted)
    }
    func testSessionHeaderValidation() throws {
        XCTAssertThrowsError(try HuatiAPI.clean(["X-Session-ID": "1111"]))
        XCTAssertThrowsError(try HuatiAPI.clean(["X-Session-ID": "test\r\nheader"]))
        let headers = try HuatiAPI.clean(["X-Session-ID": "fixture-session", "Cookie": "excluded"])
        XCTAssertEqual(headers["x-session-id"], "fixture-session")
        XCTAssertNil(headers["cookie"])
    }
    func testEncryptedStoreRoundTripAndAuthenticatedName() throws {
        let store = try SecureStore()
        let name = "unit-test-" + UUID().uuidString
        defer { try? store.remove(name) }
        try store.write(name, ["fixture": 42])
        XCTAssertEqual(try store.read(name)?.number("fixture"), 42)
    }
    func testPauseAndContinueRetainExactDuration() throws {
        let core = try CoreBridge()
        let initial: JSON = ["status": "created", "start_ms": 100000, "duration_ms": 720123, "pauses": [JSON](), "auto_submit": true]
        let paused = try core.object("pause", [initial, 200000])
        XCTAssertEqual(try core.number("remaining", [paused, 900000]), 620123)
        let resumed = try core.object("resume", [paused, 900000])
        XCTAssertEqual(resumed.number("duration_ms"), 720123)
        XCTAssertEqual(try core.number("remaining", [resumed, 1000000]), 520123)
    }
}
