import AppKit
import OSLog
import TimestampOnlyCore

private enum OperationalState: Equatable {
    case running
    case paused
    case folderAccessNeeded(String?)
    case error(String)
}

final class AppController: NSObject, SettingsWindowControllerDelegate {
    private let preferences: AppPreferences
    private let folderAccess = FolderAccessController()
    private let monitor = DirectoryMonitorService()
    private let logger: Logger
    private let loginItemManager: LoginItemManager
    private var settings = RenameSettings.default
    private var filenameFormatDraft = FilenameFormatDraft(
        committedFormat: RenameSettings.defaultFilenameFormat,
        clockMode: .local
    )
    private var state = OperationalState.folderAccessNeeded(nil)
    private var lastRenamedFilename: String?
    private var statusItem: NSStatusItem?
    private lazy var settingsWindowController = SettingsWindowController(delegate: self)

    override init() {
        let preferences = AppPreferences()
        self.preferences = preferences
        loginItemManager = LoginItemManager(preferences: preferences)
        logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "dev.j-256.timestamponly",
            category: "renaming"
        )
        super.init()
    }

    func start() {
        settings = preferences.settings
        filenameFormatDraft = FilenameFormatDraft(
            committedFormat: settings.filenameFormat,
            clockMode: settings.clockMode
        )
        configureStatusItem()
        monitor.updateHandler = { [weak self] update in
            self?.handleMonitorUpdate(update)
        }
        restoreFolderAndStartIfPossible()

        switch state {
        case .running, .paused:
            return
        case .folderAccessNeeded, .error:
            showSettings()
        }
    }

    func stop() {
        monitor.stop()
        folderAccess.stop()
    }

    @objc func showSettings() {
        refreshPresentation()
        settingsWindowController.present()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.toolTip = "Timestamp Only"
        }
        statusItem = item
        rebuildMenu()
    }

    private func restoreFolderAndStartIfPossible() {
        guard let bookmark = preferences.folderBookmark else {
            state = .folderAccessNeeded(nil)
            refreshPresentation()
            return
        }

        do {
            let restored = try folderAccess.restore(bookmark: bookmark)
            if let refreshedBookmark = restored.refreshedBookmark {
                preferences.folderBookmark = refreshedBookmark
            }
            if settings.isPaused {
                state = .paused
            } else {
                try startMonitoring(restored.url)
            }
        } catch {
            folderAccess.stop()
            state = .folderAccessNeeded(error.localizedDescription)
        }
        refreshPresentation()
    }

    private func startMonitoring(_ directory: URL) throws {
        try monitor.start(directory: directory, settings: settings)
        state = .running
    }

    private func handleMonitorUpdate(_ update: DirectoryMonitorUpdate) {
        switch update.state {
        case .running:
            var encounteredFailure: String?
            var didRename = false
            for outcome in update.outcomes {
                switch outcome {
                case .renamed(let record):
                    didRename = true
                    lastRenamedFilename = record.destination.lastPathComponent
                    logger.notice(
                        "Renamed a screenshot to \(record.destination.lastPathComponent, privacy: .private)"
                    )
                case .failed(let url, let message):
                    encounteredFailure = message
                    logger.error(
                        "Could not process \(url.lastPathComponent, privacy: .private): \(message, privacy: .private)"
                    )
                case .expired(let url):
                    logger.debug(
                        "Stopped retrying \(url.lastPathComponent, privacy: .private) until another event"
                    )
                case .alreadyNamed, .sourceChanged, .ignored, .waitingForMetadata:
                    break
                }
            }
            if let encounteredFailure {
                state = .error(encounteredFailure)
            } else if didRename || update.outcomes.isEmpty {
                state = .running
            }
        case .paused:
            state = .paused
        case .error:
            state = .error(update.errorMessage ?? "Folder monitoring stopped unexpectedly.")
        case .stopped:
            break
        }
        refreshPresentation()
    }

    private func rebuildMenu() {
        guard let statusItem else {
            return
        }

        updateStatusItemAppearance(statusItem)

        let menu = NSMenu()
        let statusMenuItem = NSMenuItem(
            title: "Status: \(statusTitle)",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        if let folder = folderAccess.url {
            let folderMenuItem = NSMenuItem(
                title: "Folder: \(folder.lastPathComponent)",
                action: nil,
                keyEquivalent: ""
            )
            folderMenuItem.toolTip = folder.path
            folderMenuItem.isEnabled = false
            menu.addItem(folderMenuItem)
        }

        if let lastRenamedFilename {
            let lastRenameMenuItem = NSMenuItem(
                title: "Last renamed: \(lastRenamedFilename)",
                action: nil,
                keyEquivalent: ""
            )
            lastRenameMenuItem.isEnabled = false
            menu.addItem(lastRenameMenuItem)
        }

        menu.addItem(.separator())
        switch state {
        case .running:
            let pauseItem = menu.addItem(
                withTitle: "Pause Renaming",
                action: #selector(pauseRenaming),
                keyEquivalent: ""
            )
            pauseItem.target = self
        case .paused:
            let resumeItem = menu.addItem(
                withTitle: "Resume Renaming",
                action: #selector(resumeRenaming),
                keyEquivalent: ""
            )
            resumeItem.target = self
        case .folderAccessNeeded:
            let chooseItem = menu.addItem(
                withTitle: "Choose Screenshot Folder...",
                action: #selector(chooseFolderFromMenu),
                keyEquivalent: ""
            )
            chooseItem.target = self
        case .error:
            break
        }

        let settingsItem = menu.addItem(
            withTitle: "Settings...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        let aboutItem = menu.addItem(
            withTitle: "About Timestamp Only",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(
            withTitle: "Quit Timestamp Only",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "Timestamp Only: \(statusTitle)"
    }

    private func updateStatusItemAppearance(_ statusItem: NSStatusItem) {
        guard let button = statusItem.button else {
            return
        }
        if let image = NSImage(
            systemSymbolName: menuBarSymbolName,
            accessibilityDescription: "Timestamp Only: \(statusTitle)"
        ) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = menuBarFallbackTitle
        }
    }

    private func refreshPresentation() {
        rebuildMenu()
        settingsWindowController.update(
            SettingsPresentation(
                statusTitle: statusTitle,
                statusDetail: statusDetail,
                statusSymbolName: statusSymbolName,
                recoveryAction: recoveryAction,
                recoveryTitle: recoveryTitle,
                folderPath: folderAccess.url?.path,
                filenameFormat: filenameFormatDraft.value,
                filenamePreview: filenameFormatDraft.preview,
                filenameError: filenameFormatDraft.validationError,
                canApplyFilenameFormat: filenameFormatDraft.canCommit,
                clockMode: settings.clockMode,
                loginItemState: loginItemManager.state
            ))
    }

    private var statusTitle: String {
        switch state {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .folderAccessNeeded:
            return "Folder Access Needed"
        case .error:
            return "Error"
        }
    }

    private var statusDetail: String {
        switch state {
        case .running:
            return "Watching for new Apple screenshots. Existing files are left unchanged."
        case .paused:
            return "Renaming is paused. Screenshots created while paused will be left unchanged."
        case .folderAccessNeeded(let detail):
            return detail ?? "Choose the folder where macOS saves screenshots. macOS grants access only to that folder."
        case .error(let message):
            return message
        }
    }

    private var statusSymbolName: String {
        switch state {
        case .running:
            return "checkmark.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .folderAccessNeeded, .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var menuBarSymbolName: String {
        switch state {
        case .running:
            return "camera.viewfinder"
        case .paused:
            return "pause.circle"
        case .folderAccessNeeded, .error:
            return "exclamationmark.triangle"
        }
    }

    private var menuBarFallbackTitle: String {
        switch state {
        case .running:
            return "TO"
        case .paused:
            return "II"
        case .folderAccessNeeded, .error:
            return "!"
        }
    }

    private var recoveryAction: SettingsRecoveryAction? {
        switch state {
        case .folderAccessNeeded:
            return nil
        case .error:
            return folderAccess.url == nil ? nil : .resume
        case .running:
            return .pause
        case .paused:
            return .resume
        }
    }

    private var recoveryTitle: String? {
        switch recoveryAction {
        case .pause:
            return "Pause Renaming"
        case .resume:
            return state == .paused ? "Resume Renaming" : "Try Again"
        case nil:
            return nil
        }
    }

    @objc private func pauseRenaming() {
        settings.isPaused = true
        preferences.settings = settings
        monitor.pause()
        state = .paused
        refreshPresentation()
    }

    @objc private func resumeRenaming() {
        guard let directory = folderAccess.url else {
            state = .folderAccessNeeded(nil)
            refreshPresentation()
            return
        }

        do {
            settings.isPaused = false
            try startMonitoring(directory)
            preferences.settings = settings
        } catch {
            settings.isPaused = true
            state = .error(error.localizedDescription)
        }
        refreshPresentation()
    }

    @objc private func chooseFolderFromMenu() {
        showSettings()
        settingsWindowDidRequestFolderSelection(settingsWindowController)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func settingsWindowDidRequestFolderSelection(_ controller: SettingsWindowController) {
        guard let selectedURL = folderAccess.chooseFolder() else {
            return
        }

        monitor.stop()
        do {
            let restored = try folderAccess.activateSelectedFolder(selectedURL)
            preferences.folderBookmark = restored.refreshedBookmark
            if settings.isPaused {
                state = .paused
            } else {
                try startMonitoring(restored.url)
            }
        } catch {
            state = .folderAccessNeeded(error.localizedDescription)
        }
        refreshPresentation()
    }

    func settingsWindow(
        _ controller: SettingsWindowController,
        didChangeFilenameFormat format: String
    ) {
        filenameFormatDraft.update(value: format, clockMode: settings.clockMode)
        refreshPresentation()
    }

    func settingsWindow(
        _ controller: SettingsWindowController,
        didCommitFilenameFormat format: String
    ) {
        filenameFormatDraft.update(value: format, clockMode: settings.clockMode)
        guard let committedFormat = filenameFormatDraft.commit() else {
            refreshPresentation()
            return
        }
        settings.filenameFormat = committedFormat
        preferences.settings = settings
        monitor.update(settings: settings)
        refreshPresentation()
    }

    func settingsWindow(
        _ controller: SettingsWindowController,
        didChangeClockMode clockMode: ClockMode
    ) {
        settings.clockMode = clockMode
        preferences.settings = settings
        monitor.update(settings: settings)
        filenameFormatDraft.revalidate(clockMode: clockMode)
        refreshPresentation()
    }

    func settingsWindow(
        _ controller: SettingsWindowController,
        didRequestLaunchAtLogin enabled: Bool
    ) {
        do {
            try loginItemManager.setEnabled(enabled)
        } catch {
            controller.showError(
                title: "Could Not Change Launch at Login",
                message: error.localizedDescription
            )
        }
        refreshPresentation()
    }

    func settingsWindow(
        _ controller: SettingsWindowController,
        didRequestRecovery action: SettingsRecoveryAction
    ) {
        switch action {
        case .pause:
            pauseRenaming()
        case .resume:
            resumeRenaming()
        }
    }

    func settingsWindowDidRequestLoginApproval(_ controller: SettingsWindowController) {
        loginItemManager.openApprovalSettings()
    }

    func settingsWindowDidRequestRemovalPreparation(_ controller: SettingsWindowController) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Prepare Timestamp Only for removal?"
        alert.informativeText =
            "This turns off launch at login, stops renaming, clears the selected-folder permission and app settings, then quits. It does not delete or change any screenshots."
        alert.addButton(withTitle: "Prepare and Quit")
        alert.addButton(withTitle: "Cancel")

        guard let window = controller.window else {
            return
        }
        alert.beginSheetModal(for: window) { [weak self, weak controller] response in
            guard response == .alertFirstButtonReturn,
                let self
            else {
                return
            }
            do {
                try self.loginItemManager.setEnabled(false)
            } catch {
                controller?.showError(
                    title: "Could Not Turn Off Launch at Login",
                    message: error.localizedDescription
                )
                return
            }

            self.monitor.stop()
            self.folderAccess.stop()
            self.preferences.clear()
            NSApp.terminate(nil)
        }
    }
}
