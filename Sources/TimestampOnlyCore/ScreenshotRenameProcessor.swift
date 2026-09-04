import Foundation

public protocol ScreenshotClassifying {
    func classify(_ url: URL) throws -> ScreenshotClassification
}

extension ScreenshotClassifier: ScreenshotClassifying {}

public protocol CollisionSafeRenaming {
    func rename(_ source: URL, toBaseName baseName: String) throws -> RenameOutcome
}

extension CollisionSafeRenamer: CollisionSafeRenaming {}

public struct RenameRecord: Equatable {
    public let source: URL
    public let destination: URL
    public let timestamp: Date
    public let timestampSource: TimestampSource
    public let collisionIndex: Int

    public init(
        source: URL,
        destination: URL,
        timestamp: Date,
        timestampSource: TimestampSource,
        collisionIndex: Int
    ) {
        self.source = source
        self.destination = destination
        self.timestamp = timestamp
        self.timestampSource = timestampSource
        self.collisionIndex = collisionIndex
    }
}

public enum ScreenshotProcessingResult: Equatable {
    case renamed(RenameRecord)
    case alreadyNamed(URL)
    case sourceChanged(URL)
    case retryUnmarked
    case ignored(ScreenshotClassification)
}

public struct ScreenshotRenameProcessor {
    private let classifier: ScreenshotClassifying
    private let inspector: CandidateFileInspecting
    private let timestampSelector: TimestampSelector
    private let nameFormatter: ScreenshotNameFormatter
    private let renamer: CollisionSafeRenaming
    private let identityResolver: FileIdentityResolving

    public init(
        classifier: ScreenshotClassifying = ScreenshotClassifier(),
        inspector: CandidateFileInspecting = URLCandidateFileInspector(),
        timestampSelector: TimestampSelector = TimestampSelector(),
        nameFormatter: ScreenshotNameFormatter = ScreenshotNameFormatter(),
        renamer: CollisionSafeRenaming = CollisionSafeRenamer(),
        identityResolver: FileIdentityResolving = FileIdentityResolver()
    ) {
        self.classifier = classifier
        self.inspector = inspector
        self.timestampSelector = timestampSelector
        self.nameFormatter = nameFormatter
        self.renamer = renamer
        self.identityResolver = identityResolver
    }

    public func process(
        _ candidate: RenameCandidate,
        settings: RenameSettings,
        at renameDate: Date
    ) throws -> ScreenshotProcessingResult {
        guard identityResolver.existingIdentity(for: candidate.url) == candidate.identity else {
            return .sourceChanged(candidate.url)
        }

        let classification = try classifier.classify(candidate.url)
        switch classification {
        case .screenRecording, .unsupportedType:
            return .ignored(classification)
        case .unmarked:
            return .retryUnmarked
        case .stillScreenshot:
            break
        }

        let evidence = try inspector.timestampEvidence(
            at: candidate.url,
            firstObservedDate: candidate.firstObservedDate,
            renameDate: renameDate
        )
        let timestamp = timestampSelector.select(from: evidence)
        let baseName = try nameFormatter.name(
            for: timestamp.date,
            format: settings.filenameFormat,
            clockMode: settings.clockMode
        )
        guard identityResolver.existingIdentity(for: candidate.url) == candidate.identity else {
            return .sourceChanged(candidate.url)
        }
        let outcome = try renamer.rename(candidate.url, toBaseName: baseName)

        guard outcome.changed else {
            return .alreadyNamed(outcome.destination)
        }

        return .renamed(
            RenameRecord(
                source: outcome.source,
                destination: outcome.destination,
                timestamp: timestamp.date,
                timestampSource: timestamp.source,
                collisionIndex: outcome.collisionIndex
            ))
    }
}
