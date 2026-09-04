import XCTest

@testable import TimestampOnlyCore

final class RenameSettingsTests: XCTestCase {
    func testDefaultsAreStableAndLocal() {
        let settings = RenameSettings.default

        XCTAssertEqual(settings.schemaVersion, RenameSettings.currentSchemaVersion)
        XCTAssertEqual(settings.filenameFormat, "yyyy-MM-dd HH.mm.ss")
        XCTAssertEqual(settings.clockMode, .local)
        XCTAssertFalse(settings.isPaused)
    }

    func testSettingsRoundTripThroughJSON() throws {
        let settings = RenameSettings(
            filenameFormat: "yyyyMMdd-HHmmss",
            clockMode: .utc,
            isPaused: true
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(RenameSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }
}
