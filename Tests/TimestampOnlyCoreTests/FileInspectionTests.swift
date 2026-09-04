import Foundation
import XCTest

@testable import TimestampOnlyCore

final class FileInspectionTests: XCTestCase {
    func testRegularFileObservationIncludesCreationAndModificationDates() throws {
        let fixture = try FileInspectionFixture()
        defer { fixture.remove() }
        let file = fixture.directory.appendingPathComponent("Synthetic.png")
        try Data("synthetic".utf8).write(to: file)

        let observation = try XCTUnwrap(URLCandidateFileInspector().observation(at: file))

        XCTAssertEqual(observation.byteCount, 9)
        XCTAssertNotNil(observation.creationDate)
        XCTAssertNotNil(observation.modificationDate)
    }

    func testDirectorySymlinkAndMissingPathAreNotCandidates() throws {
        let fixture = try FileInspectionFixture()
        defer { fixture.remove() }
        let target = fixture.directory.appendingPathComponent("Target.png")
        let symlink = fixture.directory.appendingPathComponent("Link.png")
        let missing = fixture.directory.appendingPathComponent("Missing.png")
        try Data([0]).write(to: target)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let inspector = URLCandidateFileInspector()

        XCTAssertNil(try inspector.observation(at: fixture.directory))
        XCTAssertNil(try inspector.observation(at: symlink))
        XCTAssertNil(try inspector.observation(at: missing))
    }
}

private final class FileInspectionFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimestampOnlyInspectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
