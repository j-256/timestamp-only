import XCTest

@testable import TimestampOnlyCore

final class ScreenshotRenameProcessorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = FileManager.default.temporaryDirectory
        .appendingPathComponent("Localized capture.png")

    func testRenamesMarkedScreenshotUsingSelectedTimestamp() throws {
        let creationDate = start.addingTimeInterval(-10)
        let inspector = StubCandidateFileInspector(creationDate: creationDate)
        let renamer = StubCollisionSafeRenamer()
        let candidate = makeCandidate()
        let processor = ScreenshotRenameProcessor(
            classifier: StubScreenshotClassifier(classification: .stillScreenshot),
            inspector: inspector,
            renamer: renamer,
            identityResolver: StubFileIdentityResolver(identity: candidate.identity)
        )

        let result = try processor.process(
            candidate,
            settings: RenameSettings(filenameFormat: "yyyyMMdd-HHmmss", clockMode: .utc),
            at: start
        )

        guard case .renamed(let record) = result else {
            return XCTFail("Expected a rename record")
        }
        XCTAssertEqual(record.timestamp, creationDate)
        XCTAssertEqual(record.timestampSource, .fileCreationDate)
        XCTAssertEqual(record.destination.lastPathComponent, "20270115-075950.png")
        XCTAssertEqual(renamer.requestedBaseNames, ["20270115-075950"])
    }

    func testUnmarkedFileRequestsRetryWithoutRenaming() throws {
        let renamer = StubCollisionSafeRenamer()
        let candidate = makeCandidate()
        let processor = ScreenshotRenameProcessor(
            classifier: StubScreenshotClassifier(classification: .unmarked),
            inspector: StubCandidateFileInspector(),
            renamer: renamer,
            identityResolver: StubFileIdentityResolver(identity: candidate.identity)
        )

        XCTAssertEqual(
            try processor.process(
                candidate,
                settings: .default,
                at: start
            ),
            .retryUnmarked
        )
        XCTAssertTrue(renamer.requestedBaseNames.isEmpty)
    }

    func testRecordingAndUnsupportedFilesAreIgnored() throws {
        for classification in [
            ScreenshotClassification.screenRecording,
            ScreenshotClassification.unsupportedType,
        ] {
            let candidate = makeCandidate()
            let processor = ScreenshotRenameProcessor(
                classifier: StubScreenshotClassifier(classification: classification),
                inspector: StubCandidateFileInspector(),
                renamer: StubCollisionSafeRenamer(),
                identityResolver: StubFileIdentityResolver(identity: candidate.identity)
            )

            XCTAssertEqual(
                try processor.process(
                    candidate,
                    settings: .default,
                    at: start
                ),
                .ignored(classification)
            )
        }
    }

    func testIdentityChangeBeforeRenameLeavesReplacementUntouched() throws {
        let candidate = makeCandidate()
        let renamer = StubCollisionSafeRenamer()
        let identityResolver = SequenceFileIdentityResolver(identities: [
            candidate.identity,
            .inode(device: 1, inode: 3),
        ])
        let processor = ScreenshotRenameProcessor(
            classifier: StubScreenshotClassifier(classification: .stillScreenshot),
            inspector: StubCandidateFileInspector(creationDate: start),
            renamer: renamer,
            identityResolver: identityResolver
        )

        XCTAssertEqual(
            try processor.process(candidate, settings: .default, at: start),
            .sourceChanged(candidate.url)
        )
        XCTAssertTrue(renamer.requestedBaseNames.isEmpty)
    }

    private func makeCandidate() -> RenameCandidate {
        RenameCandidate(
            identity: .inode(device: 1, inode: 2),
            url: source,
            firstObservedDate: start.addingTimeInterval(-5),
            attempts: 2,
            nextCheckDate: start,
            lastObservation: FileObservation(byteCount: 10, modificationDate: start),
            consecutiveStableChecks: 1
        )
    }
}

private struct StubFileIdentityResolver: FileIdentityResolving {
    let identity: FileIdentity?

    func existingIdentity(for url: URL) -> FileIdentity? {
        identity
    }
}

private final class SequenceFileIdentityResolver: FileIdentityResolving {
    private var identities: [FileIdentity?]

    init(identities: [FileIdentity?]) {
        self.identities = identities
    }

    func existingIdentity(for url: URL) -> FileIdentity? {
        guard !identities.isEmpty else {
            return nil
        }
        if identities.count == 1 {
            return identities[0]
        }
        return identities.removeFirst()
    }
}

private struct StubScreenshotClassifier: ScreenshotClassifying {
    let classification: ScreenshotClassification

    func classify(_ url: URL) throws -> ScreenshotClassification {
        classification
    }
}

private struct StubCandidateFileInspector: CandidateFileInspecting {
    var creationDate: Date?
    var contentCreationDate: Date?

    init(creationDate: Date? = nil, contentCreationDate: Date? = nil) {
        self.creationDate = creationDate
        self.contentCreationDate = contentCreationDate
    }

    func observation(at url: URL) throws -> FileObservation? {
        FileObservation(byteCount: 10, modificationDate: nil)
    }

    func timestampEvidence(
        at url: URL,
        firstObservedDate: Date?,
        renameDate: Date
    ) throws -> TimestampEvidence {
        TimestampEvidence(
            fileCreationDate: creationDate,
            contentCreationDate: contentCreationDate,
            firstObservedDate: firstObservedDate,
            renameDate: renameDate
        )
    }
}

private final class StubCollisionSafeRenamer: CollisionSafeRenaming {
    private(set) var requestedBaseNames: [String] = []

    func rename(_ source: URL, toBaseName baseName: String) throws -> RenameOutcome {
        requestedBaseNames.append(baseName)
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).\(source.pathExtension)")
        return RenameOutcome(
            source: source,
            destination: destination,
            collisionIndex: 0,
            changed: true
        )
    }
}
