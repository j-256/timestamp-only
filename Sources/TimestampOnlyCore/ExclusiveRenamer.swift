import Darwin
import Foundation

public enum ExclusiveRenameError: Error, Equatable, LocalizedError {
    case destinationExists
    case unsupportedAtomicRename
    case fileSystem(code: Int32)
    case collisionLimitReached

    public var errorDescription: String? {
        switch self {
        case .destinationExists:
            return "The destination already exists."
        case .unsupportedAtomicRename:
            return "This volume does not support safe exclusive renaming."
        case .fileSystem(let code):
            return "The file could not be renamed (error \(code))."
        case .collisionLimitReached:
            return "No available collision-safe filename was found."
        }
    }
}

public protocol ExclusiveFileRenaming {
    func renameExclusive(from source: URL, to destination: URL) throws
}

public struct POSIXExclusiveFileRenamer: ExclusiveFileRenaming {
    public init() {}

    public func renameExclusive(from source: URL, to destination: URL) throws {
        let result: Int32 = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else {
                    errno = EINVAL
                    return -1
                }
                return renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
            }
        }

        guard result == 0 else {
            switch errno {
            case EEXIST:
                throw ExclusiveRenameError.destinationExists
            case ENOTSUP, EINVAL:
                throw ExclusiveRenameError.unsupportedAtomicRename
            default:
                throw ExclusiveRenameError.fileSystem(code: errno)
            }
        }
    }
}

public struct RenameOutcome: Equatable {
    public let source: URL
    public let destination: URL
    public let collisionIndex: Int
    public let changed: Bool

    public init(source: URL, destination: URL, collisionIndex: Int, changed: Bool) {
        self.source = source
        self.destination = destination
        self.collisionIndex = collisionIndex
        self.changed = changed
    }
}

public struct CollisionSafeRenamer {
    public static let maximumCollisionAttempts = 10_000

    private let fileRenamer: ExclusiveFileRenaming

    public init(fileRenamer: ExclusiveFileRenaming = POSIXExclusiveFileRenamer()) {
        self.fileRenamer = fileRenamer
    }

    public func rename(_ source: URL, toBaseName baseName: String) throws -> RenameOutcome {
        let directory = source.deletingLastPathComponent()
        let pathExtension = source.pathExtension

        for collisionIndex in 0..<Self.maximumCollisionAttempts {
            let collisionSuffix = collisionIndex == 0 ? "" : "-\(collisionIndex)"
            let filename =
                pathExtension.isEmpty
                ? "\(baseName)\(collisionSuffix)"
                : "\(baseName)\(collisionSuffix).\(pathExtension)"
            let destination = directory.appendingPathComponent(filename, isDirectory: false)

            if destination.standardizedFileURL == source.standardizedFileURL {
                return RenameOutcome(
                    source: source,
                    destination: destination,
                    collisionIndex: collisionIndex,
                    changed: false
                )
            }

            do {
                try fileRenamer.renameExclusive(from: source, to: destination)
                return RenameOutcome(
                    source: source,
                    destination: destination,
                    collisionIndex: collisionIndex,
                    changed: true
                )
            } catch ExclusiveRenameError.destinationExists {
                continue
            }
        }

        throw ExclusiveRenameError.collisionLimitReached
    }
}
