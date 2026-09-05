import XCTest

@testable import TimestampOnlyCore

final class LoginItemPolicyTests: XCTestCase {
    func testUnseenServiceCanBeRegistered() {
        XCTAssertEqual(
            LoginItemPolicy.presentationState(for: .notFound),
            .disabled
        )
        XCTAssertEqual(
            LoginItemPolicy.change(to: true, from: .notFound),
            .register
        )
    }

    func testRegisteredStatesDoNotReregister() {
        XCTAssertEqual(
            LoginItemPolicy.change(to: true, from: .enabled),
            .none
        )
        XCTAssertEqual(
            LoginItemPolicy.change(to: true, from: .requiresApproval),
            .none
        )
    }

    func testEnabledServiceCanBeUnregistered() {
        XCTAssertEqual(
            LoginItemPolicy.change(to: false, from: .enabled),
            .unregister
        )
        XCTAssertEqual(
            LoginItemPolicy.change(to: false, from: .requiresApproval),
            .unregister
        )
    }

    func testUnknownServiceIsUnavailable() {
        XCTAssertEqual(
            LoginItemPolicy.presentationState(for: .unknown),
            .unavailable
        )
        XCTAssertEqual(
            LoginItemPolicy.change(to: true, from: .unknown),
            .unavailable
        )
        XCTAssertEqual(
            LoginItemPolicy.change(to: false, from: .unknown),
            .unavailable
        )
    }
}
