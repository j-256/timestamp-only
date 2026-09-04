import Foundation

public enum FilenameFormatValidationError: Error, Equatable, LocalizedError {
    case emptyFormat
    case emptyResult
    case blankResult
    case forbiddenCharacter(Character)
    case controlCharacter
    case dotOnlyResult
    case hiddenResult
    case surroundingWhitespace
    case resultTooLong(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyFormat:
            return "Enter a filename format."
        case .emptyResult:
            return "The format produces an empty filename."
        case .blankResult:
            return "The filename must include a visible character."
        case .forbiddenCharacter(let character):
            return "The filename cannot contain \"\(character)\"."
        case .controlCharacter:
            return "The filename cannot contain control characters."
        case .dotOnlyResult:
            return "The format cannot produce \".\" or \"..\"."
        case .hiddenResult:
            return "The filename cannot begin with a period because Finder would hide it."
        case .surroundingWhitespace:
            return "The filename cannot begin or end with whitespace."
        case .resultTooLong(let maximumBytes):
            return "The filename must use no more than \(maximumBytes) UTF-8 bytes."
        }
    }
}

public struct ScreenshotNameFormatter {
    public static let maximumBaseNameUTF8Length = 220
    public static let previewDate = Date(timeIntervalSince1970: 1_725_547_767)

    private let locale = Locale(identifier: "en_US_POSIX")
    private let calendar = Calendar(identifier: .gregorian)

    public init() {}

    public func name(
        for date: Date,
        format: String,
        clockMode: ClockMode,
        localTimeZone: TimeZone = .autoupdatingCurrent
    ) throws -> String {
        guard !format.isEmpty else {
            throw FilenameFormatValidationError.emptyFormat
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = clockMode.timeZone(localTimeZone: localTimeZone)
        formatter.dateFormat = format

        let result = formatter.string(from: date)
        try validate(result: result)
        return result
    }

    public func preview(format: String, clockMode: ClockMode) throws -> String {
        try name(for: Self.previewDate, format: format, clockMode: clockMode)
    }

    public func validate(result: String) throws {
        guard !result.isEmpty else {
            throw FilenameFormatValidationError.emptyResult
        }

        let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResult.isEmpty else {
            throw FilenameFormatValidationError.blankResult
        }
        guard trimmedResult == result else {
            throw FilenameFormatValidationError.surroundingWhitespace
        }

        for character in [Character("/"), Character(":")] where result.contains(character) {
            throw FilenameFormatValidationError.forbiddenCharacter(character)
        }

        guard !result.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw FilenameFormatValidationError.controlCharacter
        }

        guard result != "." && result != ".." else {
            throw FilenameFormatValidationError.dotOnlyResult
        }
        guard !result.hasPrefix(".") else {
            throw FilenameFormatValidationError.hiddenResult
        }

        guard result.utf8.count <= Self.maximumBaseNameUTF8Length else {
            throw FilenameFormatValidationError.resultTooLong(
                maximumBytes: Self.maximumBaseNameUTF8Length
            )
        }
    }
}
