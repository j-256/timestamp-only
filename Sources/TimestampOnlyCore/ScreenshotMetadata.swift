import Darwin
import Foundation
import UniformTypeIdentifiers

public enum ScreenshotMetadataAttribute {
    public static let isScreenCapture = "com.apple.metadata:kMDItemIsScreenCapture"
    public static let isScreenRecording = "com.apple.metadata:kMDItemIsScreenRecording"
}

public protocol ScreenshotMetadataReading {
    func booleanValue(forAttribute attribute: String, at url: URL) throws -> Bool?
}

public enum MetadataReadError: Error, Equatable, LocalizedError {
    case fileSystem(attribute: String, code: Int32)
    case invalidValue(attribute: String)

    public var errorDescription: String? {
        switch self {
        case .fileSystem(let attribute, let code):
            return "Could not read \(attribute) (error \(code))."
        case .invalidValue(let attribute):
            return "The value of \(attribute) is not a supported Boolean."
        }
    }
}

public struct ExtendedAttributeMetadataReader: ScreenshotMetadataReading {
    public init() {}

    public func booleanValue(forAttribute attribute: String, at url: URL) throws -> Bool? {
        let data: Data? = try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw MetadataReadError.fileSystem(attribute: attribute, code: EINVAL)
            }

            let size = getxattr(path, attribute, nil, 0, 0, 0)
            if size < 0 {
                if errno == ENOATTR || errno == ENOENT {
                    return nil
                }
                throw MetadataReadError.fileSystem(attribute: attribute, code: errno)
            }

            var data = Data(count: size)
            let bytesRead = data.withUnsafeMutableBytes { bytes in
                getxattr(path, attribute, bytes.baseAddress, size, 0, 0)
            }
            guard bytesRead >= 0 else {
                if errno == ENOATTR || errno == ENOENT {
                    return nil
                }
                throw MetadataReadError.fileSystem(attribute: attribute, code: errno)
            }
            data.count = bytesRead
            return data
        }

        guard let data else {
            return nil
        }

        if let propertyListValue = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) {
            if let boolean = propertyListValue as? Bool {
                return boolean
            }
            if let number = propertyListValue as? NSNumber {
                return number.boolValue
            }
        }

        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            .lowercased()
        switch text {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            throw MetadataReadError.invalidValue(attribute: attribute)
        }
    }
}

public enum ScreenshotClassification: Equatable {
    case stillScreenshot
    case screenRecording
    case unsupportedType
    case unmarked
}

public struct ScreenshotClassifier {
    private let metadataReader: ScreenshotMetadataReading

    public init(metadataReader: ScreenshotMetadataReading = ExtendedAttributeMetadataReader()) {
        self.metadataReader = metadataReader
    }

    public func classify(_ url: URL) throws -> ScreenshotClassification {
        let values = try url.resourceValues(forKeys: [
            .contentTypeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])

        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            return .unsupportedType
        }

        if try metadataReader.booleanValue(
            forAttribute: ScreenshotMetadataAttribute.isScreenRecording,
            at: url
        ) == true {
            return .screenRecording
        }

        guard isSupportedStillType(values.contentType, extension: url.pathExtension) else {
            return .unsupportedType
        }

        if try metadataReader.booleanValue(
            forAttribute: ScreenshotMetadataAttribute.isScreenCapture,
            at: url
        ) == true {
            return .stillScreenshot
        }

        return .unmarked
    }

    private func isSupportedStillType(_ contentType: UTType?, extension pathExtension: String) -> Bool {
        let type = contentType ?? UTType(filenameExtension: pathExtension)
        guard let type else {
            return false
        }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }
}
