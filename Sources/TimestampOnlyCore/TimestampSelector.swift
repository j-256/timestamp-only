import Foundation

public enum TimestampSource: String, Equatable {
    case fileCreationDate
    case contentCreationDate
    case firstObservedDate
    case renameDate
}

public struct TimestampEvidence: Equatable {
    public var fileCreationDate: Date?
    public var contentCreationDate: Date?
    public var firstObservedDate: Date?
    public var renameDate: Date

    public init(
        fileCreationDate: Date?,
        contentCreationDate: Date?,
        firstObservedDate: Date?,
        renameDate: Date
    ) {
        self.fileCreationDate = fileCreationDate
        self.contentCreationDate = contentCreationDate
        self.firstObservedDate = firstObservedDate
        self.renameDate = renameDate
    }
}

public struct SelectedTimestamp: Equatable {
    public let date: Date
    public let source: TimestampSource

    public init(date: Date, source: TimestampSource) {
        self.date = date
        self.source = source
    }
}

public struct TimestampSelector {
    public static let oldestPlausibleDate = Date(timeIntervalSince1970: 978_307_200)
    public static let futureTolerance: TimeInterval = 5 * 60

    public init() {}

    public func select(from evidence: TimestampEvidence) -> SelectedTimestamp {
        if let fileCreationDate = evidence.fileCreationDate,
            isPlausible(fileCreationDate, relativeTo: evidence.renameDate)
        {
            return SelectedTimestamp(date: fileCreationDate, source: .fileCreationDate)
        }

        if let contentCreationDate = evidence.contentCreationDate,
            isPlausible(contentCreationDate, relativeTo: evidence.renameDate)
        {
            return SelectedTimestamp(date: contentCreationDate, source: .contentCreationDate)
        }

        if let firstObservedDate = evidence.firstObservedDate,
            isPlausible(firstObservedDate, relativeTo: evidence.renameDate)
        {
            return SelectedTimestamp(date: firstObservedDate, source: .firstObservedDate)
        }

        return SelectedTimestamp(date: evidence.renameDate, source: .renameDate)
    }

    private func isPlausible(_ date: Date, relativeTo renameDate: Date) -> Bool {
        date >= Self.oldestPlausibleDate
            && date <= renameDate.addingTimeInterval(Self.futureTolerance)
    }
}
