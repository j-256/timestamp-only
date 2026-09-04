import XCTest

@testable import TimestampOnlyCore

final class FilenameFormatDraftTests: XCTestCase {
    private let previewDate = Date(timeIntervalSince1970: 1_725_547_767)

    func testInvalidDraftDoesNotReplaceCommittedFormat() {
        var draft = FilenameFormatDraft(
            committedFormat: RenameSettings.defaultFilenameFormat,
            clockMode: .utc,
            previewDate: previewDate
        )

        draft.update(
            value: "yyyy/MM/dd",
            clockMode: .utc,
            previewDate: previewDate
        )

        XCTAssertFalse(draft.isValid)
        XCTAssertFalse(draft.canCommit)
        XCTAssertNil(draft.preview)
        XCTAssertNil(draft.commit())
        XCTAssertEqual(draft.committedFormat, RenameSettings.defaultFilenameFormat)
    }

    func testValidDraftCommitsAfterProducingPreview() {
        var draft = FilenameFormatDraft(
            committedFormat: RenameSettings.defaultFilenameFormat,
            clockMode: .utc,
            previewDate: previewDate
        )

        draft.update(
            value: "yyyyMMdd-HHmmss",
            clockMode: .utc,
            previewDate: previewDate
        )

        XCTAssertTrue(draft.isValid)
        XCTAssertTrue(draft.canCommit)
        XCTAssertEqual(draft.preview, "20240905-144927")
        XCTAssertEqual(draft.commit(), "yyyyMMdd-HHmmss")
        XCTAssertEqual(draft.committedFormat, "yyyyMMdd-HHmmss")
        XCTAssertFalse(draft.canCommit)
    }
}
