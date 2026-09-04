import XCTest

@testable import TimestampOnlyCore

final class ScreenshotNameFormatterTests: XCTestCase {
    private let formatter = ScreenshotNameFormatter()

    func testFormatsStableUTCName() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 9
        components.day = 4
        components.hour = 13
        components.minute = 5
        components.second = 9
        let date = try XCTUnwrap(components.date)

        XCTAssertEqual(
            try formatter.name(
                for: date,
                format: RenameSettings.defaultFilenameFormat,
                clockMode: .utc
            ),
            "2026-09-04 13.05.09"
        )
    }

    func testLocalTimeTracksDaylightSavingTransition() throws {
        let localTimeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let beforeTransition = try utcDate(
            year: 2026,
            month: 3,
            day: 8,
            hour: 9,
            minute: 59,
            second: 59
        )
        let afterTransition = try utcDate(
            year: 2026,
            month: 3,
            day: 8,
            hour: 10,
            minute: 0,
            second: 0
        )

        XCTAssertEqual(
            try formatter.name(
                for: beforeTransition,
                format: RenameSettings.defaultFilenameFormat,
                clockMode: .local,
                localTimeZone: localTimeZone
            ),
            "2026-03-08 01.59.59"
        )
        XCTAssertEqual(
            try formatter.name(
                for: afterTransition,
                format: RenameSettings.defaultFilenameFormat,
                clockMode: .local,
                localTimeZone: localTimeZone
            ),
            "2026-03-08 03.00.00"
        )
    }

    func testUTCIgnoresInjectedLocalTimeZone() throws {
        let localTimeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let date = try utcDate(
            year: 2026,
            month: 3,
            day: 8,
            hour: 10,
            minute: 0,
            second: 0
        )

        XCTAssertEqual(
            try formatter.name(
                for: date,
                format: RenameSettings.defaultFilenameFormat,
                clockMode: .utc,
                localTimeZone: localTimeZone
            ),
            "2026-03-08 10.00.00"
        )
    }

    func testRejectsEmptyFormat() {
        XCTAssertThrowsError(try formatter.preview(format: "", clockMode: .utc)) { error in
            XCTAssertEqual(error as? FilenameFormatValidationError, .emptyFormat)
        }
    }

    func testRejectsPathSeparatorsAndColons() {
        XCTAssertThrowsError(try formatter.preview(format: "yyyy/MM/dd", clockMode: .utc)) { error in
            XCTAssertEqual(error as? FilenameFormatValidationError, .forbiddenCharacter("/"))
        }
        XCTAssertThrowsError(try formatter.preview(format: "HH:mm:ss", clockMode: .utc)) { error in
            XCTAssertEqual(error as? FilenameFormatValidationError, .forbiddenCharacter(":"))
        }
    }

    func testRejectsDotOnlyAndLongResults() {
        XCTAssertThrowsError(try formatter.preview(format: "'.'", clockMode: .utc)) { error in
            XCTAssertEqual(error as? FilenameFormatValidationError, .dotOnlyResult)
        }

        let longLiteral = "'\(String(repeating: "a", count: 221))'"
        XCTAssertThrowsError(try formatter.preview(format: longLiteral, clockMode: .utc)) { error in
            XCTAssertEqual(
                error as? FilenameFormatValidationError,
                .resultTooLong(maximumBytes: ScreenshotNameFormatter.maximumBaseNameUTF8Length)
            )
        }
    }

    func testRejectsBlankHiddenAndControlCharacterResults() {
        XCTAssertThrowsError(try formatter.preview(format: "'   '", clockMode: .utc)) { error in
            XCTAssertEqual(error as? FilenameFormatValidationError, .blankResult)
        }
        XCTAssertThrowsError(try formatter.preview(format: "'.hidden'", clockMode: .utc)) { error in
            XCTAssertEqual(error as? FilenameFormatValidationError, .hiddenResult)
        }
        XCTAssertThrowsError(try formatter.preview(format: "'line\nbreak'", clockMode: .utc)) { error in
            XCTAssertEqual(error as? FilenameFormatValidationError, .controlCharacter)
        }
        XCTAssertThrowsError(try formatter.preview(format: "' trailing '", clockMode: .utc)) { error in
            XCTAssertEqual(error as? FilenameFormatValidationError, .surroundingWhitespace)
        }
    }

    private func utcDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return try XCTUnwrap(components.date)
    }
}
