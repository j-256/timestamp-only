import Foundation
import XCTest

@testable import TimestampOnlyCore

final class DirectoryMonitorServiceTests: XCTestCase {
    func testEndToEndRenameUsesRealFSEventsAndSyntheticMetadata() throws {
        let fixture = try MonitorServiceFixture()
        defer { fixture.remove() }
        let renamed = expectation(description: "The synthetic screenshot is renamed")
        let service = makeService()
        service.updateHandler = { update in
            if update.outcomes.contains(where: {
                if case .renamed = $0 {
                    return true
                }
                return false
            }) {
                renamed.fulfill()
            }
        }

        try service.start(directory: fixture.directory, settings: .default)
        defer { service.stop() }
        let source = fixture.directory.appendingPathComponent("Localized synthetic.png")
        try fixture.createMarkedScreenshotInChildProcess(at: source)

        wait(for: [renamed], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try fixture.visibleFiles().count, 1)
    }

    func testResumeBaselinesFilesCreatedWhilePaused() throws {
        let fixture = try MonitorServiceFixture()
        defer { fixture.remove() }
        let unexpectedRename = expectation(description: "No paused file is renamed")
        unexpectedRename.isInverted = true
        let service = makeService()
        service.updateHandler = { update in
            if update.outcomes.contains(where: {
                if case .renamed = $0 {
                    return true
                }
                return false
            }) {
                unexpectedRename.fulfill()
            }
        }

        try service.start(directory: fixture.directory, settings: .default)
        service.pause()
        let source = fixture.directory.appendingPathComponent("Paused.png")
        try fixture.createMarkedScreenshotInChildProcess(at: source)
        try service.resume()
        defer { service.stop() }

        wait(for: [unexpectedRename], timeout: 0.75)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeService() -> DirectoryMonitorService {
        DirectoryMonitorService(engineFactory: { directory in
            DirectoryRenameEngine(
                directory: directory,
                candidatePolicy: CandidatePolicy(
                    initialDelay: 0.05,
                    stabilityDelay: 0.05,
                    retryDelay: 0.05,
                    requiredConsecutiveStableChecks: 1,
                    maximumAttempts: 20
                )
            )
        })
    }
}

private final class MonitorServiceFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimestampOnlyMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func createMarkedScreenshotInChildProcess(at url: URL) throws {
        let touch = Process()
        touch.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        touch.arguments = [url.path]
        try touch.run()
        touch.waitUntilExit()
        guard touch.terminationStatus == 0 else {
            throw MonitorServiceFixtureError.processFailed("touch")
        }

        let attributeData = try PropertyListSerialization.data(
            fromPropertyList: true,
            format: .binary,
            options: 0
        )
        let hexadecimalValue = attributeData.map { String(format: "%02x", $0) }.joined()
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = [
            "-wx",
            ScreenshotMetadataAttribute.isScreenCapture,
            hexadecimalValue,
            url.path,
        ]
        try xattr.run()
        xattr.waitUntilExit()
        guard xattr.terminationStatus == 0 else {
            throw MonitorServiceFixtureError.processFailed("xattr")
        }
    }

    func visibleFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum MonitorServiceFixtureError: Error {
    case processFailed(String)
}
