import CoreServices
import Darwin
import Foundation

public enum FileInspectionError: Error, Equatable, LocalizedError {
    case fileSystem(code: Int32)

    public var errorDescription: String? {
        switch self {
        case .fileSystem(let code):
            return "The file could not be inspected (error \(code))."
        }
    }
}

public protocol CandidateFileInspecting {
    func observation(at url: URL) throws -> FileObservation?
    func timestampEvidence(
        at url: URL,
        firstObservedDate: Date?,
        renameDate: Date
    ) throws -> TimestampEvidence
}

public struct URLCandidateFileInspector: CandidateFileInspecting {
    public init() {}

    public func observation(at url: URL) throws -> FileObservation? {
        var information = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                errno = EINVAL
                return Int32(-1)
            }
            return lstat(path, &information)
        }

        if result != 0 && errno == ENOENT {
            return nil
        }
        guard result == 0 else {
            throw FileInspectionError.fileSystem(code: errno)
        }
        guard information.st_mode & S_IFMT == S_IFREG,
            information.st_size >= 0
        else {
            return nil
        }

        let modificationTime =
            TimeInterval(information.st_mtimespec.tv_sec)
            + TimeInterval(information.st_mtimespec.tv_nsec) / 1_000_000_000
        let creationTime =
            TimeInterval(information.st_birthtimespec.tv_sec)
            + TimeInterval(information.st_birthtimespec.tv_nsec) / 1_000_000_000

        return FileObservation(
            byteCount: UInt64(information.st_size),
            creationDate: creationTime > 0 ? Date(timeIntervalSince1970: creationTime) : nil,
            modificationDate: Date(timeIntervalSince1970: modificationTime)
        )
    }

    public func timestampEvidence(
        at url: URL,
        firstObservedDate: Date?,
        renameDate: Date
    ) throws -> TimestampEvidence {
        let values = try url.resourceValues(forKeys: [.creationDateKey])
        return TimestampEvidence(
            fileCreationDate: values.creationDate,
            contentCreationDate: contentCreationDate(at: url),
            firstObservedDate: firstObservedDate,
            renameDate: renameDate
        )
    }

    private func contentCreationDate(at url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
            let value = MDItemCopyAttribute(item, kMDItemContentCreationDate)
        else {
            return nil
        }
        return value as? Date
    }
}
