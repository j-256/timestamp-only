import Foundation
import TimestampOnlyCore

final class AppPreferences {
    private enum Key {
        static let settings = "renameSettings"
        static let folderBookmark = "folderBookmark"
        static let launchAtLoginRequested = "launchAtLoginRequested"
    }

    private let defaults: UserDefaults
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    private let nameFormatter = ScreenshotNameFormatter()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.launchAtLoginRequested: false])
    }

    var settings: RenameSettings {
        get {
            guard let data = defaults.data(forKey: Key.settings),
                let decoded = try? decoder.decode(RenameSettings.self, from: data),
                isValid(decoded)
            else {
                return .default
            }
            return decoded
        }
        set {
            guard isValid(newValue),
                let data = try? encoder.encode(newValue)
            else {
                return
            }
            defaults.set(data, forKey: Key.settings)
        }
    }

    var folderBookmark: Data? {
        get { defaults.data(forKey: Key.folderBookmark) }
        set { defaults.set(newValue, forKey: Key.folderBookmark) }
    }

    var launchAtLoginRequested: Bool {
        get { defaults.bool(forKey: Key.launchAtLoginRequested) }
        set { defaults.set(newValue, forKey: Key.launchAtLoginRequested) }
    }

    func clear() {
        defaults.removeObject(forKey: Key.settings)
        defaults.removeObject(forKey: Key.folderBookmark)
        defaults.removeObject(forKey: Key.launchAtLoginRequested)
    }

    private func isValid(_ settings: RenameSettings) -> Bool {
        settings.schemaVersion == RenameSettings.currentSchemaVersion
            && (try? nameFormatter.preview(
                format: settings.filenameFormat,
                clockMode: settings.clockMode
            )) != nil
    }
}
