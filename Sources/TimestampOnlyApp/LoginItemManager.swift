import AppKit
import Foundation
import ServiceManagement
import TimestampOnlyCore

enum LoginItemState: Equatable {
    case disabled
    case enabled
    case approvalRequired
    case unavailable

    var detail: String {
        switch self {
        case .disabled:
            return "Off"
        case .enabled:
            return "On"
        case .approvalRequired:
            return "Approval needed in System Settings"
        case .unavailable:
            return "Launch at login is unavailable for this installation"
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
                "macOS could not register this copy of Timestamp Only to launch at login. Make sure it is installed in Applications and try again."
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
            switch LoginItemPolicy.presentationState(
                for: serviceStatus(SMAppService.mainApp)
            ) {
            case .disabled:
                return .disabled
            case .enabled:
                return .enabled
            case .approvalRequired:
                return .approvalRequired
            case .unavailable:
                return .unavailable
            }
        }
        return preferences.launchAtLoginRequested ? .enabled : .disabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            switch LoginItemPolicy.change(
                to: enabled,
                from: serviceStatus(service)
            ) {
            case .register:
                try service.register()
            case .unregister:
                try service.unregister()
            case .none:
                break
            case .unavailable:
                throw LoginItemError.serviceUnavailable
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

    @available(macOS 13.0, *)
    private func serviceStatus(_ service: SMAppService) -> LoginItemServiceStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }
}
