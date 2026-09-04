import XCTest

@testable import TimestampOnlyCore

final class TimestampSelectorTests: XCTestCase {
    private let selector = TimestampSelector()
    private let renameDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testPrefersFileCreationDate() {
        let creation = renameDate.addingTimeInterval(-30)
        let content = renameDate.addingTimeInterval(-20)

        XCTAssertEqual(
            selector.select(
                from: TimestampEvidence(
                    fileCreationDate: creation,
                    contentCreationDate: content,
                    firstObservedDate: renameDate.addingTimeInterval(-10),
                    renameDate: renameDate
                )),
            SelectedTimestamp(date: creation, source: .fileCreationDate)
        )
    }

    func testFallsBackInDocumentedOrder() {
        let content = renameDate.addingTimeInterval(-20)
        let observed = renameDate.addingTimeInterval(-10)

        XCTAssertEqual(
            selector.select(
                from: TimestampEvidence(
                    fileCreationDate: nil,
                    contentCreationDate: content,
                    firstObservedDate: observed,
                    renameDate: renameDate
                )
            ).source,
            .contentCreationDate
        )
        XCTAssertEqual(
            selector.select(
                from: TimestampEvidence(
                    fileCreationDate: nil,
                    contentCreationDate: nil,
                    firstObservedDate: observed,
                    renameDate: renameDate
                )
            ).source,
            .firstObservedDate
        )
        XCTAssertEqual(
            selector.select(
                from: TimestampEvidence(
                    fileCreationDate: nil,
                    contentCreationDate: nil,
                    firstObservedDate: nil,
                    renameDate: renameDate
                )
            ).source,
            .renameDate
        )
    }

    func testRejectsImplausibleDates() {
        let tooOld = TimestampSelector.oldestPlausibleDate.addingTimeInterval(-1)
        let tooFarInFuture = renameDate.addingTimeInterval(TimestampSelector.futureTolerance + 1)

        let selected = selector.select(
            from: TimestampEvidence(
                fileCreationDate: tooOld,
                contentCreationDate: tooFarInFuture,
                firstObservedDate: renameDate,
                renameDate: renameDate
            ))

        XCTAssertEqual(selected.source, .firstObservedDate)
    }
}
