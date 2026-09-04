import Foundation
import XCTest

@testable import TimestampOnlyCore

final class FSEventDirectoryWatcherTests: XCTestCase {
    func testReportsFileCreatedByAnotherProcessInTemporaryDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimestampOnlyFSEvents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let createdURL = directory.appendingPathComponent("Synthetic.png")
        let expectation = expectation(description: "FSEvents reports the created file")
        let watcher = FSEventDirectoryWatcher()
        try watcher.start(watching: directory) { events in
            if events.contains(where: {
                $0.url.standardizedFileURL == createdURL.standardizedFileURL
                    && $0.flags.contains(.created)
            }) {
                expectation.fulfill()
            }
        }
        defer { watcher.stop() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        process.arguments = [createdURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        wait(for: [expectation], timeout: 5)
    }
}
