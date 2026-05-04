import XCTest
@testable import NICUWebSocket

final class NICUWebSocketTests: XCTestCase {
    func testCancelWithoutConnectDoesNotCrash() {
        let receiver = WebSocketReceiver()
        receiver.cancel()
    }
}
