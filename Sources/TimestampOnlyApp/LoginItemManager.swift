import AppKit
import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case disabled
    case enabled
    case approvalRequired
    case notFound

    var detail: String {
        switch self {
        case .disabled:
            return "Off"
        case .enabled:
            return "On"
        case .approvalRequired:
            return "Approval needed in System Settings"
        case .notFound:
            return "Available after installing a signed release"
        }
    }
}

enum LoginItemError: Error, LocalizedError {
    case helperRequestFailed
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .helperRequestFailed:
            return "macOS could not change the launch-at-login setting."
        case .serviceUnavailable:
            return
                "Launch at login is available after installing a signed release in Applications."
        }
    }
}

final class LoginItemManager {
    static let helperBundleIdentifier = "dev.j-256.timestamponly.loginitem"

    private let preferences: AppPreferences

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    var state: LoginItemState {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .notRegistered:
                return .disabled
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .approvalRequired
            case .notFound:
                return .notFound
            @unknown default:
                return .notFound
            }
        }
        return preferences.launchAtLoginRequested ? .enabled : .disabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if enabled {
                switch service.status {
                case .notRegistered:
                    try service.register()
                case .enabled, .requiresApproval:
                    break
                case .notFound:
                    throw LoginItemError.serviceUnavailable
                @unknown default:
                    throw LoginItemError.serviceUnavailable
                }
            } else {
                switch service.status {
                case .enabled, .requiresApproval:
                    try service.unregister()
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    throw LoginItemError.serviceUnavailable
                }
            }
        } else {
            guard
                SMLoginItemSetEnabled(
                    Self.helperBundleIdentifier as CFString,
                    enabled
                )
            else {
                throw LoginItemError.helperRequestFailed
            }
        }
        preferences.launchAtLoginRequested = enabled
    }

    func openApprovalSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
