import Foundation

public struct FilenameFormatDraft: Equatable {
    public private(set) var committedFormat: String
    public private(set) var value: String
    public private(set) var preview: String?
    public private(set) var validationError: String?

    public init(
        committedFormat: String,
        clockMode: ClockMode,
        previewDate: Date = Date()
    ) {
        self.committedFormat = committedFormat
        value = committedFormat
        preview = nil
        validationError = nil
        revalidate(clockMode: clockMode, previewDate: previewDate)
    }

    public var isValid: Bool {
        validationError == nil
    }

    public var canCommit: Bool {
        isValid && value != committedFormat
    }

    public mutating func update(
        value: String,
        clockMode: ClockMode,
        previewDate: Date = Date()
    ) {
        self.value = value
        revalidate(clockMode: clockMode, previewDate: previewDate)
    }

    public mutating func revalidate(
        clockMode: ClockMode,
        previewDate: Date = Date()
    ) {
        do {
            preview = try ScreenshotNameFormatter().name(
                for: previewDate,
                format: value,
                clockMode: clockMode
            )
            validationError = nil
        } catch {
            preview = nil
            validationError = error.localizedDescription
        }
    }

    @discardableResult
    public mutating func commit() -> String? {
        guard isValid else {
            return nil
        }
        committedFormat = value
        return value
    }
}
