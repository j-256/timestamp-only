import Foundation
import XCTest

@testable import TimestampOnlyCore

final class ScreenshotMetadataTests: XCTestCase {
    func testPositiveCaptureMarkerClassifiesStillImageWithoutUsingLocalizedFilename() throws {
        let fixture = try TemporaryFileFixture(extension: "png")
        let reader = StubMetadataReader(values: [
            ScreenshotMetadataAttribute.isScreenCapture: true
        ])

        XCTAssertEqual(
            try ScreenshotClassifier(metadataReader: reader).classify(fixture.url),
            .stillScreenshot
        )
    }

    func testRecordingMarkerWinsOverCaptureMarkerAndUnsupportedType() throws {
        let fixture = try TemporaryFileFixture(extension: "mov")
        let reader = StubMetadataReader(values: [
            ScreenshotMetadataAttribute.isScreenCapture: true,
            ScreenshotMetadataAttribute.isScreenRecording: true,
        ])

        XCTAssertEqual(
            try ScreenshotClassifier(metadataReader: reader).classify(fixture.url),
            .screenRecording
        )
    }

    func testUnmarkedImageFailsClosed() throws {
        let fixture = try TemporaryFileFixture(extension: "png")

        XCTAssertEqual(
            try ScreenshotClassifier(metadataReader: StubMetadataReader()).classify(fixture.url),
            .unmarked
        )
    }

    func testPositiveMarkerSupportsNonPNGStillAndPDF() throws {
        let reader = StubMetadataReader(values: [
            ScreenshotMetadataAttribute.isScreenCapture: true
        ])

        for pathExtension in ["jpg", "tiff", "heic", "pdf"] {
            let fixture = try TemporaryFileFixture(extension: pathExtension)
            XCTAssertEqual(
                try ScreenshotClassifier(metadataReader: reader).classify(fixture.url),
                .stillScreenshot,
                "Expected support for \(pathExtension)"
            )
        }
    }

    func testUnsupportedTypeStaysUntouched() throws {
        let fixture = try TemporaryFileFixture(extension: "mov")
        let reader = StubMetadataReader(values: [
            ScreenshotMetadataAttribute.isScreenCapture: true
        ])

        XCTAssertEqual(
            try ScreenshotClassifier(metadataReader: reader).classify(fixture.url),
            .unsupportedType
        )
    }

    func testSymlinkToMarkedImageIsRejected() throws {
        let fixture = try TemporaryFileFixture(extension: "png")
        let symlink = fixture.directory.appendingPathComponent("Link.png")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: fixture.url
        )
        let reader = StubMetadataReader(values: [
            ScreenshotMetadataAttribute.isScreenCapture: true
        ])

        XCTAssertEqual(
            try ScreenshotClassifier(metadataReader: reader).classify(symlink),
            .unsupportedType
        )
    }
}

private struct StubMetadataReader: ScreenshotMetadataReading {
    var values: [String: Bool] = [:]

    func booleanValue(forAttribute attribute: String, at url: URL) throws -> Bool? {
        values[attribute]
    }
}

private final class TemporaryFileFixture {
    let directory: URL
    let url: URL

    init(extension pathExtension: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        url = directory.appendingPathComponent("スクリーンショット ٢٠٢٦.\(pathExtension)")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0])))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
