import Darwin
import Foundation

public enum FileIdentity: Hashable {
    case inode(device: UInt64, inode: UInt64)
    case path(String)
}

public protocol FileIdentityResolving {
    func existingIdentity(for url: URL) -> FileIdentity?
}

public struct FileIdentityResolver: FileIdentityResolving {
    public init() {}

    public func existingIdentity(for url: URL) -> FileIdentity? {
        var information = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return lstat(path, &information)
        }

        guard result == 0 else {
            return nil
        }

        return .inode(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    public func identity(for url: URL) -> FileIdentity {
        existingIdentity(for: url) ?? .path(url.standardizedFileURL.path)
    }
}

public struct FileObservation: Equatable {
    public let byteCount: UInt64
    public let creationDate: Date?
    public let modificationDate: Date?

    public init(
        byteCount: UInt64,
        creationDate: Date? = nil,
        modificationDate: Date?
    ) {
        self.byteCount = byteCount
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

public struct RenameCandidate: Equatable {
    public let identity: FileIdentity
    public var url: URL
    public let firstObservedDate: Date
    public var attempts: Int
    public var nextCheckDate: Date
    public var lastObservation: FileObservation?
    public var consecutiveStableChecks: Int
}

public enum CandidateProbeResult: Equatable {
    case waiting
    case ready(RenameCandidate)
    case expired
    case missing
}

public struct CandidatePolicy: Equatable {
    public var initialDelay: TimeInterval
    public var stabilityDelay: TimeInterval
    public var retryDelay: TimeInterval
    public var requiredConsecutiveStableChecks: Int
    public var maximumAttempts: Int
    public var maximumTrackedCandidates: Int

    public init(
        initialDelay: TimeInterval = 0.20,
        stabilityDelay: TimeInterval = 0.25,
        retryDelay: TimeInterval = 0.50,
        requiredConsecutiveStableChecks: Int = 2,
        maximumAttempts: Int = 20,
        maximumTrackedCandidates: Int = 512
    ) {
        self.initialDelay = initialDelay
        self.stabilityDelay = stabilityDelay
        self.retryDelay = retryDelay
        self.requiredConsecutiveStableChecks = requiredConsecutiveStableChecks
        self.maximumAttempts = maximumAttempts
        self.maximumTrackedCandidates = maximumTrackedCandidates
    }
}

public struct CandidateRegistry {
    public let policy: CandidatePolicy
    private var candidates: [FileIdentity: RenameCandidate] = [:]

    public init(policy: CandidatePolicy = CandidatePolicy()) {
        self.policy = policy
    }

    public var count: Int {
        candidates.count
    }

    public func contains(_ identity: FileIdentity) -> Bool {
        candidates[identity] != nil
    }

    @discardableResult
    public mutating func enqueue(identity: FileIdentity, url: URL, at date: Date) -> Bool {
        if var existing = candidates[identity] {
            existing.url = url
            existing.nextCheckDate = min(
                existing.nextCheckDate,
                date.addingTimeInterval(policy.initialDelay)
            )
            candidates[identity] = existing
            return false
        }

        if candidates.count >= policy.maximumTrackedCandidates,
            let oldest = candidates.min(by: {
                $0.value.firstObservedDate < $1.value.firstObservedDate
            })?.key
        {
            candidates.removeValue(forKey: oldest)
        }

        candidates[identity] = RenameCandidate(
            identity: identity,
            url: url,
            firstObservedDate: date,
            attempts: 0,
            nextCheckDate: date.addingTimeInterval(policy.initialDelay),
            lastObservation: nil,
            consecutiveStableChecks: 0
        )
        return true
    }

    public func dueCandidates(at date: Date) -> [RenameCandidate] {
        candidates.values
            .filter { $0.nextCheckDate <= date }
            .sorted { $0.firstObservedDate < $1.firstObservedDate }
    }

    public mutating func recordProbe(
        identity: FileIdentity,
        observation: FileObservation?,
        at date: Date
    ) -> CandidateProbeResult {
        guard var candidate = candidates[identity] else {
            return .missing
        }

        candidate.attempts += 1
        guard candidate.attempts <= policy.maximumAttempts else {
            candidates.removeValue(forKey: identity)
            return .expired
        }

        guard let observation else {
            candidate.nextCheckDate = date.addingTimeInterval(policy.retryDelay)
            candidates[identity] = candidate
            return .waiting
        }

        if candidate.lastObservation == observation {
            candidate.consecutiveStableChecks += 1
        } else {
            candidate.lastObservation = observation
            candidate.consecutiveStableChecks = 0
        }

        if candidate.consecutiveStableChecks >= policy.requiredConsecutiveStableChecks {
            candidates[identity] = candidate
            return .ready(candidate)
        }

        candidate.nextCheckDate = date.addingTimeInterval(policy.stabilityDelay)
        candidates[identity] = candidate
        return .waiting
    }

    public mutating func deferCandidate(identity: FileIdentity, until date: Date) {
        guard var candidate = candidates[identity] else {
            return
        }
        candidate.nextCheckDate = date
        candidates[identity] = candidate
    }

    public mutating func complete(identity: FileIdentity) {
        candidates.removeValue(forKey: identity)
    }

    public mutating func removeAll() {
        candidates.removeAll()
    }
}

public struct ProcessedIdentityPolicy: Equatable {
    public var retentionInterval: TimeInterval
    public var maximumCount: Int

    public init(retentionInterval: TimeInterval = 10, maximumCount: Int = 512) {
        self.retentionInterval = retentionInterval
        self.maximumCount = maximumCount
    }
}

public struct ProcessedIdentityCache {
    public let policy: ProcessedIdentityPolicy
    private var processedDates: [FileIdentity: Date] = [:]

    public init(policy: ProcessedIdentityPolicy = ProcessedIdentityPolicy()) {
        self.policy = policy
    }

    public var count: Int {
        processedDates.count
    }

    public mutating func contains(_ identity: FileIdentity, at date: Date) -> Bool {
        prune(at: date)
        return processedDates[identity] != nil
    }

    public mutating func insert(_ identity: FileIdentity, at date: Date) {
        prune(at: date)
        processedDates[identity] = date

        if processedDates.count > policy.maximumCount,
            let oldest = processedDates.min(by: { $0.value < $1.value })?.key
        {
            processedDates.removeValue(forKey: oldest)
        }
    }

    private mutating func prune(at date: Date) {
        let cutoff = date.addingTimeInterval(-policy.retentionInterval)
        processedDates = processedDates.filter { $0.value >= cutoff }
    }
}
