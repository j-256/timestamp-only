import AppKit
import TimestampOnlyCore

// Compile the production view, but never instantiate AppController or its watcher
final class CaptureDelegate: NSObject, SettingsWindowControllerDelegate {
    func settingsWindowDidRequestFolderSelection(_ controller: SettingsWindowController) {}
    func settingsWindow(_ controller: SettingsWindowController, didChangeFilenameFormat format: String) {}
    func settingsWindow(_ controller: SettingsWindowController, didCommitFilenameFormat format: String) {}
    func settingsWindow(_ controller: SettingsWindowController, didChangeClockMode clockMode: ClockMode) {}
    func settingsWindow(_ controller: SettingsWindowController, didRequestLaunchAtLogin enabled: Bool) {}
    func settingsWindow(_ controller: SettingsWindowController, didRequestRecovery action: SettingsRecoveryAction) {}
    func settingsWindowDidRequestLoginApproval(_ controller: SettingsWindowController) {}
    func settingsWindowDidRequestRemovalPreparation(_ controller: SettingsWindowController) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .darkAqua)
let delegate = CaptureDelegate()
let controller = SettingsWindowController(delegate: delegate)
let preview = try ScreenshotNameFormatter().preview(
    format: RenameSettings.defaultFilenameFormat, clockMode: .utc)
controller.update(
    SettingsPresentation(
        statusTitle: "Running",
        statusDetail: "Watching for new Apple screenshots. Existing files are left unchanged.",
        statusSymbolName: "checkmark.circle.fill",
        recoveryAction: .pause,
        recoveryTitle: "Pause Renaming",
        folderPath: "/Screenshots",
        filenameFormat: RenameSettings.defaultFilenameFormat,
        filenamePreview: preview,
        filenameError: nil,
        canApplyFilenameFormat: false,
        clockMode: .utc,
        loginItemState: .disabled
    ))
controller.present()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
guard let view = controller.window?.contentView?.superview else {
    fatalError("Settings window has no content view")
}
view.layoutSubtreeIfNeeded()
let scale = 4
guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(view.bounds.width) * scale,
        pixelsHigh: Int(view.bounds.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )
else {
    fatalError("Cannot allocate settings bitmap")
}
bitmap.size = view.bounds.size
view.cacheDisplay(in: view.bounds, to: bitmap)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode settings bitmap")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("Captured settings view: \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
controller.close()
