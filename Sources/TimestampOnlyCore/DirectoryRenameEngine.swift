import Foundation

public enum DirectoryRenameEngineOutcome: Equatable {
    case renamed(RenameRecord)
    case alreadyNamed(URL)
    case sourceChanged(URL)
    case ignored(URL, ScreenshotClassification)
    case waitingForMetadata(URL)
    case expired(URL)
    case failed(URL, String)
}

public struct DirectoryRenameEngine {
    public static let startupEventTolerance: TimeInterval = 2

    public let directory: URL

    private let fileManager: FileManager
    private let identityResolver: FileIdentityResolving
    private let inspector: CandidateFileInspecting
    private let processor: ScreenshotRenameProcessor
    private var registry: CandidateRegistry
    private var processedCache: ProcessedIdentityCache
    private var knownPaths: [String: FileIdentity] = [:]
    private var knownIdentities: Set<FileIdentity> = []
    private var monitoringStartDate = Date.distantPast

    public init(
        directory: URL,
        fileManager: FileManager = .default,
        identityResolver: FileIdentityResolving = FileIdentityResolver(),
        inspector: CandidateFileInspecting = URLCandidateFileInspector(),
        processor: ScreenshotRenameProcessor = ScreenshotRenameProcessor(),
        candidatePolicy: CandidatePolicy = CandidatePolicy(),
        processedIdentityPolicy: ProcessedIdentityPolicy = ProcessedIdentityPolicy()
    ) {
        self.directory = directory.standardizedFileURL
        self.fileManager = fileManager
        self.identityResolver = identityResolver
        self.inspector = inspector
        self.processor = processor
        registry = CandidateRegistry(policy: candidatePolicy)
        processedCache = ProcessedIdentityCache(policy: processedIdentityPolicy)
    }

    public var pendingCandidateCount: Int {
        registry.count
    }

    public mutating func establishBaseline(startedAt date: Date = Date()) throws {
        monitoringStartDate = date
        knownPaths = try snapshot()
        knownIdentities = Set(knownPaths.values)
        registry.removeAll()
    }

    public mutating func receive(_ events: [DirectoryEvent], at date: Date) throws {
        if events.contains(where: { $0.flags.contains(.mustRescan) }) {
            try rescan(at: date)
        }
        let identitiesKnownBeforeEvents = knownIdentities

        for event in events {
            if event.flags.contains(.ownEvent) {
                continue
            }

            let path = event.url.standardizedFileURL.path
            if event.flags.contains(.removed) {
                _ = removeKnownPath(path)
                continue
            }

            guard event.flags.isCandidateEvent,
                isDirectChild(event.url),
                !event.flags.contains(.directory)
            else {
                continue
            }

            guard let observation = try inspector.observation(at: event.url) else {
                if event.flags.contains(.renamed) {
                    _ = removeKnownPath(path)
                }
                continue
            }

            guard let identity = identityResolver.existingIdentity(for: event.url) else {
                continue
            }
            if processedCache.contains(identity, at: date) {
                setKnownPath(path, identity: identity)
                continue
            }

            let wasKnown = identitiesKnownBeforeEvents.contains(identity)
            let isCreationSignal = event.flags.contains(.created) || event.flags.contains(.renamed)
            let isNewFileEvent = isCreationSignal && appearedDuringMonitoring(observation)
            if isNewFileEvent || registry.contains(identity) || !wasKnown {
                registry.enqueue(identity: identity, url: event.url, at: date)
            }
            setKnownPath(path, identity: identity)
        }
    }

    public mutating func processDueCandidates(
        settings: RenameSettings,
        at date: Date
    ) -> [DirectoryRenameEngineOutcome] {
        var outcomes: [DirectoryRenameEngineOutcome] = []

        for candidate in registry.dueCandidates(at: date) {
            let observation: FileObservation?
            do {
                observation = try inspector.observation(at: candidate.url)
            } catch {
                registry.complete(identity: candidate.identity)
                outcomes.append(.failed(candidate.url, error.localizedDescription))
                continue
            }

            switch registry.recordProbe(
                identity: candidate.identity,
                observation: observation,
                at: date
            ) {
            case .waiting, .missing:
                continue
            case .expired:
                outcomes.append(.expired(candidate.url))
            case .ready(let readyCandidate):
                process(
                    readyCandidate,
                    settings: settings,
                    at: date,
                    outcomes: &outcomes
                )
            }
        }

        return outcomes
    }

    private mutating func process(
        _ candidate: RenameCandidate,
        settings: RenameSettings,
        at date: Date,
        outcomes: inout [DirectoryRenameEngineOutcome]
    ) {
        do {
            switch try processor.process(candidate, settings: settings, at: date) {
            case .renamed(let record):
                registry.complete(identity: candidate.identity)
                processedCache.insert(candidate.identity, at: date)
                _ = removeKnownPath(
                    record.source.standardizedFileURL.path,
                    matching: candidate.identity
                )
                setKnownPath(
                    record.destination.standardizedFileURL.path,
                    identity: candidate.identity
                )
                outcomes.append(.renamed(record))
            case .alreadyNamed(let url):
                registry.complete(identity: candidate.identity)
                processedCache.insert(candidate.identity, at: date)
                outcomes.append(.alreadyNamed(url))
            case .sourceChanged(let url):
                registry.complete(identity: candidate.identity)
                _ = removeKnownPath(
                    url.standardizedFileURL.path,
                    matching: candidate.identity
                )
                outcomes.append(.sourceChanged(url))
            case .ignored(let classification):
                registry.complete(identity: candidate.identity)
                processedCache.insert(candidate.identity, at: date)
                outcomes.append(.ignored(candidate.url, classification))
            case .retryUnmarked:
                registry.deferCandidate(
                    identity: candidate.identity,
                    until: date.addingTimeInterval(registry.policy.retryDelay)
                )
                outcomes.append(.waitingForMetadata(candidate.url))
            }
        } catch {
            registry.complete(identity: candidate.identity)
            outcomes.append(.failed(candidate.url, error.localizedDescription))
        }
    }

    private mutating func rescan(at date: Date) throws {
        let latestPaths = try snapshot()
        let priorIdentities = Set(knownPaths.values)

        for (path, identity) in latestPaths where !priorIdentities.contains(identity) {
            let url = URL(fileURLWithPath: path)
            guard !processedCache.contains(identity, at: date),
                let observation = try inspector.observation(at: url),
                appearedDuringMonitoring(observation)
            else {
                continue
            }
            registry.enqueue(identity: identity, url: url, at: date)
        }

        knownPaths = latestPaths
        knownIdentities = Set(latestPaths.values)
    }

    private func snapshot() throws -> [String: FileIdentity] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        var result: [String: FileIdentity] = [:]
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            if try inspector.observation(at: standardizedURL) != nil,
                let identity = identityResolver.existingIdentity(for: standardizedURL)
            {
                result[standardizedURL.path] = identity
            }
        }
        return result
    }

    private func isDirectChild(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent() == directory
    }

    private func appearedDuringMonitoring(_ observation: FileObservation) -> Bool {
        let oldestAvailableDate = [
            observation.creationDate,
            observation.modificationDate,
        ].compactMap { $0 }.min()
        return oldestAvailableDate.map {
            $0 >= monitoringStartDate.addingTimeInterval(-Self.startupEventTolerance)
        } ?? false
    }

    private mutating func removeKnownPath(
        _ path: String,
        matching expectedIdentity: FileIdentity? = nil
    ) -> FileIdentity? {
        guard let identity = knownPaths[path],
            expectedIdentity == nil || identity == expectedIdentity
        else {
            return nil
        }
        knownPaths.removeValue(forKey: path)
        if !knownPaths.values.contains(identity) {
            knownIdentities.remove(identity)
        }
        return identity
    }

    private mutating func setKnownPath(_ path: String, identity: FileIdentity) {
        let previousIdentity = knownPaths.updateValue(identity, forKey: path)
        if let previousIdentity,
            previousIdentity != identity,
            !knownPaths.values.contains(previousIdentity)
        {
            knownIdentities.remove(previousIdentity)
        }
        knownIdentities.insert(identity)
    }
}
