import AppKit
import TimestampOnlyCore

enum SettingsRecoveryAction: Equatable {
    case pause
    case resume
}

struct SettingsPresentation {
    let statusTitle: String
    let statusDetail: String
    let statusSymbolName: String
    let recoveryAction: SettingsRecoveryAction?
    let recoveryTitle: String?
    let folderPath: String?
    let filenameFormat: String
    let filenamePreview: String?
    let filenameError: String?
    let canApplyFilenameFormat: Bool
    let clockMode: ClockMode
    let loginItemState: LoginItemState
}

protocol SettingsWindowControllerDelegate: AnyObject {
    func settingsWindowDidRequestFolderSelection(_ controller: SettingsWindowController)
    func settingsWindow(
        _ controller: SettingsWindowController,
        didChangeFilenameFormat format: String
    )
    func settingsWindow(
        _ controller: SettingsWindowController,
        didCommitFilenameFormat format: String
    )
    func settingsWindow(
        _ controller: SettingsWindowController,
        didChangeClockMode clockMode: ClockMode
    )
    func settingsWindow(
        _ controller: SettingsWindowController,
        didRequestLaunchAtLogin enabled: Bool
    )
    func settingsWindow(
        _ controller: SettingsWindowController,
        didRequestRecovery action: SettingsRecoveryAction
    )
    func settingsWindowDidRequestLoginApproval(_ controller: SettingsWindowController)
    func settingsWindowDidRequestRemovalPreparation(_ controller: SettingsWindowController)
}

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    weak var delegate: SettingsWindowControllerDelegate?

    private let statusImage = NSImageView()
    private let statusTitle = NSTextField(labelWithString: "")
    private let statusDetail = NSTextField(wrappingLabelWithString: "")
    private let recoveryButton = NSButton()
    private let folderPath = NSTextField(labelWithString: "")
    private let filenameField = NSTextField()
    private let filenameApplyButton = NSButton()
    private let filenamePreview = NSTextField(labelWithString: "")
    private let filenameError = NSTextField(wrappingLabelWithString: "")
    private let clockMode = NSPopUpButton()
    private let launchAtLogin = NSButton()
    private let loginItemDetail = NSTextField(wrappingLabelWithString: "")
    private let loginApprovalButton = NSButton()
    private var recoveryAction: SettingsRecoveryAction?

    init(delegate: SettingsWindowControllerDelegate) {
        self.delegate = delegate
        super.init(window: nil)
        window = makeWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func present() {
        guard let window else {
            return
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(_ presentation: SettingsPresentation) {
        statusTitle.stringValue = presentation.statusTitle
        statusDetail.stringValue = presentation.statusDetail
        statusImage.image = NSImage(
            systemSymbolName: presentation.statusSymbolName,
            accessibilityDescription: presentation.statusTitle
        )
        statusImage.contentTintColor = statusColor(for: presentation)
        recoveryAction = presentation.recoveryAction
        recoveryButton.title = presentation.recoveryTitle ?? ""
        recoveryButton.isHidden = presentation.recoveryAction == nil

        folderPath.stringValue = presentation.folderPath ?? "No folder selected"
        folderPath.textColor = presentation.folderPath == nil ? .secondaryLabelColor : .labelColor

        if window?.firstResponder !== filenameField.currentEditor() {
            filenameField.stringValue = presentation.filenameFormat
        }
        filenamePreview.stringValue =
            presentation.filenamePreview.map {
                "Example: \($0).png"
            } ?? "Example unavailable"
        filenameError.stringValue = presentation.filenameError ?? ""
        filenameError.isHidden = presentation.filenameError == nil
        filenameField.setAccessibilityHelp(presentation.filenameError)
        filenameApplyButton.isEnabled = presentation.canApplyFilenameFormat

        clockMode.selectItem(withTitle: presentation.clockMode.displayName)
        launchAtLogin.state =
            presentation.loginItemState == .enabled
                || presentation.loginItemState == .approvalRequired ? .on : .off
        launchAtLogin.isEnabled = presentation.loginItemState != .notFound
        loginItemDetail.stringValue = presentation.loginItemState.detail
        loginApprovalButton.isHidden = presentation.loginItemState != .approvalRequired
    }

    func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func makeWindow() -> NSWindow {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 680))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -22),
        ])

        configureStatusSection(in: stack)
        addSeparator(to: stack)
        configureFolderSection(in: stack)
        addSeparator(to: stack)
        configureNamingSection(in: stack)
        addSeparator(to: stack)
        configureLoginSection(in: stack)
        addSeparator(to: stack)
        configurePrivacySection(in: stack)

        let window = NSWindow(
            contentRect: rootView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Timestamp Only Settings"
        window.contentView = rootView
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("TimestampOnlySettingsWindow")
        window.setContentSize(rootView.frame.size)
        window.tabbingMode = .disallowed
        return window
    }

    private func configureStatusSection(in stack: NSStackView) {
        let heading = sectionHeading("Status")
        addFullWidth(heading, to: stack)

        statusImage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusImage.widthAnchor.constraint(equalToConstant: 32),
            statusImage.heightAnchor.constraint(equalToConstant: 32),
        ])

        statusTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.maximumNumberOfLines = 3

        recoveryButton.target = self
        recoveryButton.action = #selector(performRecovery)
        recoveryButton.bezelStyle = .rounded

        let textStack = NSStackView(views: [statusTitle, statusDetail, recoveryButton])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 5
        let row = NSStackView(views: [statusImage, textStack])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        addFullWidth(row, to: stack)
    }

    private func configureFolderSection(in stack: NSStackView) {
        addFullWidth(sectionHeading("Screenshot folder"), to: stack)
        folderPath.lineBreakMode = .byTruncatingMiddle
        folderPath.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderPath.setAccessibilityLabel("Selected screenshot folder")

        let chooseButton = NSButton(
            title: "Choose Folder...",
            target: self,
            action: #selector(chooseFolder)
        )
        chooseButton.bezelStyle = .rounded
        chooseButton.setAccessibilityHelp("Choose the folder where macOS saves screenshots")

        let row = NSStackView(views: [folderPath, chooseButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        addFullWidth(row, to: stack)

        let explanation = NSTextField(
            wrappingLabelWithString:
                "Select the location shown in the Screenshot toolbar under Options. Only new Apple screenshots directly inside this folder are renamed."
        )
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 2
        addFullWidth(explanation, to: stack)
    }

    private func configureNamingSection(in stack: NSStackView) {
        addFullWidth(sectionHeading("Filename"), to: stack)

        let formatLabel = NSTextField(labelWithString: "Format:")
        formatLabel.alignment = .right
        filenameField.delegate = self
        filenameField.target = self
        filenameField.action = #selector(applyFilenameFormat)
        filenameField.placeholderString = RenameSettings.defaultFilenameFormat
        filenameField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        filenameField.setAccessibilityLabel("Filename format")

        filenameApplyButton.title = "Apply"
        filenameApplyButton.target = self
        filenameApplyButton.action = #selector(applyFilenameFormat)
        filenameApplyButton.bezelStyle = .rounded
        filenameApplyButton.setAccessibilityHelp("Apply the valid filename format")

        let formatRow = NSStackView(views: [formatLabel, filenameField, filenameApplyButton])
        formatRow.orientation = .horizontal
        formatRow.alignment = .centerY
        formatRow.spacing = 10
        formatLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        filenameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        addFullWidth(formatRow, to: stack)

        filenamePreview.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        filenamePreview.textColor = .secondaryLabelColor
        filenamePreview.setAccessibilityLabel("Filename preview")
        addFullWidth(filenamePreview, to: stack)

        filenameError.textColor = .systemRed
        filenameError.maximumNumberOfLines = 2
        filenameError.setAccessibilityLabel("Filename format error")
        addFullWidth(filenameError, to: stack)

        let formatHelp = NSTextField(
            wrappingLabelWithString:
                "Common symbols: yyyy year, MM month, dd day, HH hour, mm minute, ss second. Slashes and colons are not valid in filenames."
        )
        formatHelp.textColor = .secondaryLabelColor
        formatHelp.maximumNumberOfLines = 2
        addFullWidth(formatHelp, to: stack)

        clockMode.addItems(withTitles: ClockMode.allCases.map(\.displayName))
        clockMode.target = self
        clockMode.action = #selector(changeClockMode)
        clockMode.setAccessibilityLabel("Timestamp time zone")
        let clockLabel = NSTextField(labelWithString: "Time zone:")
        clockLabel.alignment = .right
        clockLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let clockRow = NSStackView(views: [clockLabel, clockMode])
        clockRow.orientation = .horizontal
        clockRow.alignment = .centerY
        clockRow.spacing = 10
        addFullWidth(clockRow, to: stack)
    }

    private func configureLoginSection(in stack: NSStackView) {
        addFullWidth(sectionHeading("Background operation"), to: stack)

        launchAtLogin.setButtonType(.switch)
        launchAtLogin.title = "Launch Timestamp Only at login"
        launchAtLogin.target = self
        launchAtLogin.action = #selector(toggleLaunchAtLogin)
        launchAtLogin.setAccessibilityHelp("Keep Timestamp Only available after signing in")
        loginItemDetail.textColor = .secondaryLabelColor
        loginItemDetail.maximumNumberOfLines = 2
        loginApprovalButton.title = "Open Login Items Settings..."
        loginApprovalButton.target = self
        loginApprovalButton.action = #selector(openLoginApproval)
        loginApprovalButton.bezelStyle = .rounded

        let row = NSStackView(views: [launchAtLogin, loginItemDetail, loginApprovalButton])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 10
        addFullWidth(row, to: stack)

        let menuBarDetail = NSTextField(
            wrappingLabelWithString:
                "Closing Settings leaves Timestamp Only running in the menu bar."
        )
        menuBarDetail.textColor = .secondaryLabelColor
        menuBarDetail.maximumNumberOfLines = 2
        addFullWidth(menuBarDetail, to: stack)
    }

    private func configurePrivacySection(in stack: NSStackView) {
        addFullWidth(sectionHeading("Privacy and removal"), to: stack)
        let privacy = NSTextField(
            wrappingLabelWithString:
                "Timestamp Only runs locally. It reads filename and filesystem metadata only. It does not inspect image content, connect to the network, collect telemetry, or upload anything."
        )
        privacy.maximumNumberOfLines = 3
        addFullWidth(privacy, to: stack)

        let removeButton = NSButton(
            title: "Prepare for Removal...",
            target: self,
            action: #selector(prepareForRemoval)
        )
        removeButton.bezelStyle = .rounded
        removeButton.setAccessibilityHelp("Turn off launch at login and clear Timestamp Only settings")
        stack.addArrangedSubview(removeButton)
    }

    private func sectionHeading(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        return field
    }

    private func addSeparator(to stack: NSStackView) {
        let separator = NSBox()
        separator.boxType = .separator
        addFullWidth(separator, to: stack)
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func statusColor(for presentation: SettingsPresentation) -> NSColor {
        switch presentation.statusSymbolName {
        case "checkmark.circle.fill":
            return .systemGreen
        case "pause.circle.fill":
            return .systemOrange
        default:
            return .systemRed
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        delegate?.settingsWindow(
            self,
            didChangeFilenameFormat: filenameField.stringValue
        )
    }

    @objc private func applyFilenameFormat() {
        delegate?.settingsWindow(
            self,
            didCommitFilenameFormat: filenameField.stringValue
        )
    }

    @objc private func chooseFolder() {
        delegate?.settingsWindowDidRequestFolderSelection(self)
    }

    @objc private func changeClockMode() {
        guard let title = clockMode.selectedItem?.title,
            let selectedMode = ClockMode.allCases.first(where: { $0.displayName == title })
        else {
            return
        }
        delegate?.settingsWindow(self, didChangeClockMode: selectedMode)
    }

    @objc private func toggleLaunchAtLogin() {
        delegate?.settingsWindow(
            self,
            didRequestLaunchAtLogin: launchAtLogin.state == .on
        )
    }

    @objc private func performRecovery() {
        guard let recoveryAction else {
            return
        }
        delegate?.settingsWindow(self, didRequestRecovery: recoveryAction)
    }

    @objc private func openLoginApproval() {
        delegate?.settingsWindowDidRequestLoginApproval(self)
    }

    @objc private func prepareForRemoval() {
        delegate?.settingsWindowDidRequestRemovalPreparation(self)
    }
}
