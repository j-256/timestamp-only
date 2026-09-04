import Darwin
import Foundation
import XCTest

@testable import TimestampOnlyCore

final class ScreenshotRenameIntegrationTests: XCTestCase {
    func testMetadataDrivenRenamePreservesBytesAndAvoidsCollision() throws {
        let fixture = try RenameIntegrationFixture()
        defer { fixture.remove() }

        let source = fixture.directory.appendingPathComponent("Localized screenshot name.JPEG")
        let contents = Data("synthetic screenshot bytes".utf8)
        try contents.write(to: source)
        try setBooleanExtendedAttribute(
            ScreenshotMetadataAttribute.isScreenCapture,
            value: true,
            at: source
        )

        let creationDate = try XCTUnwrap(
            source.resourceValues(forKeys: [.creationDateKey]).creationDate
        )
        let formatter = ScreenshotNameFormatter()
        let baseName = try formatter.name(
            for: creationDate,
            format: RenameSettings.defaultFilenameFormat,
            clockMode: .utc
        )
        let collision = fixture.directory.appendingPathComponent("\(baseName).JPEG")
        let collisionContents = Data("existing user file".utf8)
        try collisionContents.write(to: collision)

        let identity = FileIdentityResolver().identity(for: source)
        let candidate = RenameCandidate(
            identity: identity,
            url: source,
            firstObservedDate: Date(),
            attempts: 2,
            nextCheckDate: Date(),
            lastObservation: try URLCandidateFileInspector().observation(at: source),
            consecutiveStableChecks: 1
        )

        let result = try ScreenshotRenameProcessor().process(
            candidate,
            settings: RenameSettings(clockMode: .utc),
            at: Date()
        )

        guard case .renamed(let record) = result else {
            return XCTFail("Expected a renamed screenshot")
        }
        XCTAssertEqual(record.destination.lastPathComponent, "\(baseName)-1.JPEG")
        XCTAssertEqual(try Data(contentsOf: record.destination), contents)
        XCTAssertEqual(try Data(contentsOf: collision), collisionContents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testScreenRecordingMarkerPreventsRename() throws {
        let fixture = try RenameIntegrationFixture()
        defer { fixture.remove() }

        let source = fixture.directory.appendingPathComponent("Recording.mov")
        try Data([0]).write(to: source)
        try setBooleanExtendedAttribute(
            ScreenshotMetadataAttribute.isScreenCapture,
            value: true,
            at: source
        )
        try setBooleanExtendedAttribute(
            ScreenshotMetadataAttribute.isScreenRecording,
            value: true,
            at: source
        )
        let candidate = RenameCandidate(
            identity: FileIdentityResolver().identity(for: source),
            url: source,
            firstObservedDate: Date(),
            attempts: 2,
            nextCheckDate: Date(),
            lastObservation: try URLCandidateFileInspector().observation(at: source),
            consecutiveStableChecks: 1
        )

        XCTAssertEqual(
            try ScreenshotRenameProcessor().process(
                candidate,
                settings: .default,
                at: Date()
            ),
            .ignored(.screenRecording)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func setBooleanExtendedAttribute(
        _ attribute: String,
        value: Bool,
        at url: URL
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        )
        let result: Int32 = try data.withUnsafeBytes { bytes in
            try url.withUnsafeFileSystemRepresentation { path in
                guard let path else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                return setxattr(path, attribute, bytes.baseAddress, data.count, 0, 0)
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

private final class RenameIntegrationFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimestampOnlyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
