import XCTest

@testable import TimestampOnlyCore

final class CandidateRegistryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let identity = FileIdentity.inode(device: 1, inode: 2)
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("capture.png")

    func testDuplicateEventsMergeWithoutPostponingCandidate() {
        var registry = CandidateRegistry(policy: CandidatePolicy(initialDelay: 1))

        XCTAssertTrue(registry.enqueue(identity: identity, url: url, at: start))
        XCTAssertFalse(
            registry.enqueue(
                identity: identity,
                url: url,
                at: start.addingTimeInterval(0.5)
            )
        )
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(
            registry.dueCandidates(at: start.addingTimeInterval(1)).map(\.identity),
            [identity]
        )
    }

    func testRequiresConsecutiveStableObservations() {
        var registry = CandidateRegistry(
            policy: CandidatePolicy(
                initialDelay: 0,
                stabilityDelay: 1,
                requiredConsecutiveStableChecks: 1
            ))
        let first = FileObservation(byteCount: 10, modificationDate: start)
        let changed = FileObservation(byteCount: 20, modificationDate: start.addingTimeInterval(1))
        registry.enqueue(identity: identity, url: url, at: start)

        XCTAssertEqual(
            registry.recordProbe(identity: identity, observation: first, at: start),
            .waiting
        )
        XCTAssertEqual(
            registry.recordProbe(
                identity: identity,
                observation: changed,
                at: start.addingTimeInterval(1)
            ),
            .waiting
        )

        let result = registry.recordProbe(
            identity: identity,
            observation: changed,
            at: start.addingTimeInterval(2)
        )
        guard case .ready(let candidate) = result else {
            return XCTFail("Expected a ready candidate")
        }
        XCTAssertEqual(candidate.firstObservedDate, start)
    }

    func testMissingProbeExpiresButLaterEventCanReenqueue() {
        var registry = CandidateRegistry(
            policy: CandidatePolicy(
                initialDelay: 0,
                retryDelay: 1,
                maximumAttempts: 1
            ))
        registry.enqueue(identity: identity, url: url, at: start)

        XCTAssertEqual(
            registry.recordProbe(identity: identity, observation: nil, at: start),
            .waiting
        )
        XCTAssertEqual(
            registry.recordProbe(
                identity: identity,
                observation: nil,
                at: start.addingTimeInterval(1)
            ),
            .expired
        )
        XCTAssertTrue(
            registry.enqueue(
                identity: identity,
                url: url,
                at: start.addingTimeInterval(2)
            )
        )
    }

    func testProcessedCacheExpiresAndEvictsOldest() {
        var cache = ProcessedIdentityCache(
            policy: ProcessedIdentityPolicy(
                retentionInterval: 10,
                maximumCount: 2
            ))
        let second = FileIdentity.inode(device: 1, inode: 3)
        let third = FileIdentity.inode(device: 1, inode: 4)

        cache.insert(identity, at: start)
        cache.insert(second, at: start.addingTimeInterval(1))
        cache.insert(third, at: start.addingTimeInterval(2))

        XCTAssertFalse(cache.contains(identity, at: start.addingTimeInterval(2)))
        XCTAssertTrue(cache.contains(second, at: start.addingTimeInterval(2)))
        XCTAssertFalse(cache.contains(second, at: start.addingTimeInterval(12)))
    }
}
