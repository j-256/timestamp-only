import Foundation
import XCTest

@testable import TimestampOnlyCore

final class ExclusiveRenamerTests: XCTestCase {
    func testUsesNumericSuffixesWithoutOverwriting() throws {
        let fileRenamer = StubExclusiveFileRenamer(existingNames: [
            "2026-09-04 13.05.09.png",
            "2026-09-04 13.05.09-1.png",
        ])
        let renamer = CollisionSafeRenamer(fileRenamer: fileRenamer)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("Localized source.png")

        let outcome = try renamer.rename(source, toBaseName: "2026-09-04 13.05.09")

        XCTAssertEqual(outcome.destination.lastPathComponent, "2026-09-04 13.05.09-2.png")
        XCTAssertEqual(outcome.collisionIndex, 2)
        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(
            fileRenamer.attemptedNames,
            [
                "2026-09-04 13.05.09.png",
                "2026-09-04 13.05.09-1.png",
                "2026-09-04 13.05.09-2.png",
            ])
    }

    func testPreservesExtensionCase() throws {
        let fileRenamer = StubExclusiveFileRenamer()
        let renamer = CollisionSafeRenamer(fileRenamer: fileRenamer)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("source.JPEG")

        let outcome = try renamer.rename(source, toBaseName: "capture")

        XCTAssertEqual(outcome.destination.lastPathComponent, "capture.JPEG")
    }

    func testRealExclusiveRenamePreservesExistingDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.png")
        let destination = directory.appendingPathComponent("target.png")
        try Data("source".utf8).write(to: source)
        try Data("destination".utf8).write(to: destination)

        XCTAssertThrowsError(
            try POSIXExclusiveFileRenamer().renameExclusive(from: source, to: destination)
        ) { error in
            XCTAssertEqual(error as? ExclusiveRenameError, .destinationExists)
        }
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: destination), Data("destination".utf8))
    }
}

private final class StubExclusiveFileRenamer: ExclusiveFileRenaming {
    private(set) var existingNames: Set<String>
    private(set) var attemptedNames: [String] = []

    init(existingNames: Set<String> = []) {
        self.existingNames = existingNames
    }

    func renameExclusive(from source: URL, to destination: URL) throws {
        attemptedNames.append(destination.lastPathComponent)
        if existingNames.contains(destination.lastPathComponent) {
            throw ExclusiveRenameError.destinationExists
        }
        existingNames.insert(destination.lastPathComponent)
    }
}
