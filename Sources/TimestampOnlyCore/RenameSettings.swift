import Foundation

public enum ClockMode: String, CaseIterable, Codable {
    case local
    case utc

    public var displayName: String {
        switch self {
        case .local:
            return "Local Time"
        case .utc:
            return "UTC"
        }
    }

    public func timeZone(localTimeZone: TimeZone = .autoupdatingCurrent) -> TimeZone {
        switch self {
        case .local:
            return localTimeZone
        case .utc:
            return TimeZone(secondsFromGMT: 0)!
        }
    }
}

public struct RenameSettings: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let defaultFilenameFormat = "yyyy-MM-dd HH.mm.ss"

    public var schemaVersion: Int
    public var filenameFormat: String
    public var clockMode: ClockMode
    public var isPaused: Bool

    public init(
        schemaVersion: Int = RenameSettings.currentSchemaVersion,
        filenameFormat: String = RenameSettings.defaultFilenameFormat,
        clockMode: ClockMode = .local,
        isPaused: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.filenameFormat = filenameFormat
        self.clockMode = clockMode
        self.isPaused = isPaused
    }

    public static let `default` = RenameSettings()
}
