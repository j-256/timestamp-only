import AppKit

let mainBundleIdentifier = "dev.j-256.timestamponly"
let helperBundleURL = Bundle.main.bundleURL
let mainApplicationURL =
    helperBundleURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false

if NSRunningApplication.runningApplications(
    withBundleIdentifier: mainBundleIdentifier
).isEmpty {
    NSWorkspace.shared.openApplication(
        at: mainApplicationURL,
        configuration: configuration
    )
}

NSApplication.shared.run()
