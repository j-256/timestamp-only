import Darwin
import Foundation
import XCTest

@testable import TimestampOnlyCore

final class DirectoryRenameEngineTests: XCTestCase {
    private let start = Date()

    func testBaselineFilesRemainUntouched() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        let existing = try fixture.makeMarkedScreenshot(named: "Existing.png")
        var engine = makeEngine(directory: fixture.directory)

        try engine.establishBaseline()
        try engine.receive(
            [
                DirectoryEvent(url: fixture.directory, flags: .mustRescan)
            ], at: start)

        XCTAssertTrue(engine.processDueCandidates(settings: .default, at: start).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
    }

    func testPartialWriteWaitsForTwoStableProbesBeforeRename() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline()

        let source = try fixture.makeMarkedScreenshot(named: "Localized source.png")
        try engine.receive(
            [
                DirectoryEvent(url: source, flags: .created),
                DirectoryEvent(url: source, flags: .contentModified),
            ], at: start)

        XCTAssertTrue(engine.processDueCandidates(settings: .default, at: start).isEmpty)
        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("continued".utf8))
        try handle.close()

        XCTAssertTrue(
            engine.processDueCandidates(
                settings: .default,
                at: start.addingTimeInterval(1)
            ).isEmpty
        )
        let outcomes = engine.processDueCandidates(
            settings: .default,
            at: start.addingTimeInterval(2)
        )

        guard case .renamed(let record) = try XCTUnwrap(outcomes.first) else {
            return XCTFail("Expected a renamed screenshot")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.destination.path))
    }

    func testDelayedCaptureMarkerIsRetried() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline()

        let source = try fixture.makeFile(named: "Capture.png")
        try engine.receive(
            [
                DirectoryEvent(url: source, flags: .created)
            ], at: start)
        XCTAssertTrue(engine.processDueCandidates(settings: .default, at: start).isEmpty)

        let waiting = engine.processDueCandidates(
            settings: .default,
            at: start.addingTimeInterval(1)
        )
        XCTAssertEqual(waiting, [.waitingForMetadata(source)])

        try fixture.markAsScreenshot(source)
        try engine.receive(
            [
                DirectoryEvent(url: source, flags: .metadataModified)
            ], at: start.addingTimeInterval(1.1))
        let outcomes = engine.processDueCandidates(
            settings: .default,
            at: start.addingTimeInterval(2)
        )

        guard case .renamed = try XCTUnwrap(outcomes.first) else {
            return XCTFail("Expected a rename after the marker appeared")
        }
    }

    func testDroppedEventRescanFindsNewScreenshot() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline()
        _ = try fixture.makeMarkedScreenshot(named: "Missed.png")

        try engine.receive(
            [
                DirectoryEvent(url: fixture.directory, flags: .mustRescan)
            ], at: start)
        XCTAssertTrue(engine.processDueCandidates(settings: .default, at: start).isEmpty)
        let outcomes = engine.processDueCandidates(
            settings: .default,
            at: start.addingTimeInterval(1)
        )

        guard case .renamed = try XCTUnwrap(outcomes.first) else {
            return XCTFail("Expected rescan recovery")
        }
    }

    func testDroppedEventRescanLeavesOldScreenshotMovedIntoFolderUntouched() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        let outsideFixture = try EngineFixture()
        defer { outsideFixture.remove() }
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline(startedAt: start)

        let outsideFile = try outsideFixture.makeMarkedScreenshot(named: "Old screenshot.png")
        try FileManager.default.setAttributes(
            [.modificationDate: start.addingTimeInterval(-60)],
            ofItemAtPath: outsideFile.path
        )
        let movedFile = fixture.directory.appendingPathComponent(outsideFile.lastPathComponent)
        try FileManager.default.moveItem(at: outsideFile, to: movedFile)

        try engine.receive(
            [DirectoryEvent(url: fixture.directory, flags: .mustRescan)],
            at: start.addingTimeInterval(1)
        )

        XCTAssertEqual(engine.pendingCandidateCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedFile.path))
    }

    func testOwnRenameFeedbackEventIsIgnored() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline()
        let source = try fixture.makeMarkedScreenshot(named: "Capture.png")

        try engine.receive(
            [
                DirectoryEvent(url: source, flags: .created)
            ], at: start)
        _ = engine.processDueCandidates(settings: .default, at: start)
        let outcomes = engine.processDueCandidates(
            settings: .default,
            at: start.addingTimeInterval(1)
        )
        guard case .renamed(let record) = try XCTUnwrap(outcomes.first) else {
            return XCTFail("Expected initial rename")
        }

        try engine.receive(
            [
                DirectoryEvent(url: record.destination, flags: [.renamed, .ownEvent])
            ], at: start.addingTimeInterval(1.1))
        XCTAssertEqual(engine.pendingCandidateCount, 0)
    }

    func testOldBaselineScreenshotRenamedByUserRemainsUntouched() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        let original = try fixture.makeMarkedScreenshot(named: "Old.png")
        try FileManager.default.setAttributes(
            [.modificationDate: start.addingTimeInterval(-60)],
            ofItemAtPath: original.path
        )
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline(startedAt: start)

        let renamed = fixture.directory.appendingPathComponent("User renamed.png")
        try FileManager.default.moveItem(at: original, to: renamed)
        try engine.receive(
            [
                DirectoryEvent(url: original, flags: .renamed),
                DirectoryEvent(url: renamed, flags: .renamed),
            ],
            at: start.addingTimeInterval(1)
        )

        XCTAssertEqual(engine.pendingCandidateCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testCreationEventDuringBaselineStillEnqueuesRecentFile() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        let source = try fixture.makeMarkedScreenshot(named: "Racing baseline.png")
        try FileManager.default.setAttributes(
            [.modificationDate: start],
            ofItemAtPath: source.path
        )
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline(startedAt: start)

        try engine.receive(
            [DirectoryEvent(url: source, flags: .created)],
            at: start.addingTimeInterval(0.1)
        )

        XCTAssertEqual(engine.pendingCandidateCount, 1)
    }

    func testCandidateFollowsFinalRenameAfterOldPathEvent() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline(startedAt: start)
        let temporary = try fixture.makeMarkedScreenshot(named: ".capture-in-progress.png")
        try engine.receive(
            [DirectoryEvent(url: temporary, flags: .created)],
            at: start
        )

        let final = fixture.directory.appendingPathComponent("Localized final.png")
        try FileManager.default.moveItem(at: temporary, to: final)
        try engine.receive(
            [DirectoryEvent(url: temporary, flags: [.removed, .renamed])],
            at: start.addingTimeInterval(0.1)
        )
        try engine.receive(
            [DirectoryEvent(url: final, flags: .renamed)],
            at: start.addingTimeInterval(0.2)
        )

        XCTAssertTrue(engine.processDueCandidates(settings: .default, at: start).isEmpty)
        let outcomes = engine.processDueCandidates(
            settings: .default,
            at: start.addingTimeInterval(1)
        )
        guard case .renamed = try XCTUnwrap(outcomes.first) else {
            return XCTFail("Expected the final path to be renamed")
        }
    }

    func testReplacedCandidateIsLeftUntouchedUntilRescanFindsNewIdentity() throws {
        let fixture = try EngineFixture()
        defer { fixture.remove() }
        var engine = makeEngine(directory: fixture.directory)
        try engine.establishBaseline(startedAt: start)
        let source = try fixture.makeMarkedScreenshot(named: "Capture.png")
        try engine.receive(
            [DirectoryEvent(url: source, flags: .created)],
            at: start
        )

        let replacementStaging = try fixture.makeMarkedScreenshot(named: "Replacement.png")
        try Data("replacement".utf8).write(to: replacementStaging)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: replacementStaging, to: source)

        XCTAssertTrue(engine.processDueCandidates(settings: .default, at: start).isEmpty)
        XCTAssertEqual(
            engine.processDueCandidates(
                settings: .default,
                at: start.addingTimeInterval(1)
            ),
            [.sourceChanged(source)]
        )
        XCTAssertEqual(try Data(contentsOf: source), Data("replacement".utf8))

        try engine.receive(
            [DirectoryEvent(url: fixture.directory, flags: .mustRescan)],
            at: start.addingTimeInterval(2)
        )
        XCTAssertTrue(
            engine.processDueCandidates(
                settings: .default,
                at: start.addingTimeInterval(2)
            ).isEmpty
        )
        let outcomes = engine.processDueCandidates(
            settings: .default,
            at: start.addingTimeInterval(3)
        )
        guard case .renamed(let record) = try XCTUnwrap(outcomes.first) else {
            return XCTFail("Expected the replacement to be discovered as a new identity")
        }
        XCTAssertEqual(try Data(contentsOf: record.destination), Data("replacement".utf8))
    }

    private func makeEngine(directory: URL) -> DirectoryRenameEngine {
        DirectoryRenameEngine(
            directory: directory,
            candidatePolicy: CandidatePolicy(
                initialDelay: 0,
                stabilityDelay: 0,
                retryDelay: 0,
                requiredConsecutiveStableChecks: 1,
                maximumAttempts: 6
            )
        )
    }
}

private final class EngineFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimestampOnlyEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func makeFile(named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("synthetic".utf8).write(to: url)
        return url
    }

    func makeMarkedScreenshot(named name: String) throws -> URL {
        let url = try makeFile(named: name)
        try markAsScreenshot(url)
        return url
    }

    func markAsScreenshot(_ url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: true,
            format: .binary,
            options: 0
        )
        let result: Int32 = try data.withUnsafeBytes { bytes in
            try url.withUnsafeFileSystemRepresentation { path in
                guard let path else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                return setxattr(
                    path,
                    ScreenshotMetadataAttribute.isScreenCapture,
                    bytes.baseAddress,
                    data.count,
                    0,
                    0
                )
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
