package enum LoginItemServiceStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

package enum LoginItemPresentationState: Equatable {
    case disabled
    case enabled
    case approvalRequired
    case unavailable
}

package enum LoginItemChange: Equatable {
    case none
    case register
    case unregister
    case unavailable
}

package struct LoginItemPolicy {
    package static func presentationState(
        for status: LoginItemServiceStatus
    ) -> LoginItemPresentationState {
        switch status {
        case .notRegistered, .notFound:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .approvalRequired
        case .unknown:
            return .unavailable
        }
    }

    package static func change(
        to enabled: Bool,
        from status: LoginItemServiceStatus
    ) -> LoginItemChange {
        if enabled {
            switch status {
            case .notRegistered, .notFound:
                return .register
            case .enabled, .requiresApproval:
                return .none
            case .unknown:
                return .unavailable
            }
        }

        switch status {
        case .enabled, .requiresApproval:
            return .unregister
        case .notRegistered, .notFound:
            return .none
        case .unknown:
            return .unavailable
        }
    }
}
