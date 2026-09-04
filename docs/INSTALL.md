# Installation, first run, and updates

## Direct DMG installation

The primary release artifact is `Timestamp-Only-<version>.dmg`.

1. Download the DMG from the repository's Releases page.
2. Open the DMG and drag Timestamp Only to Applications.
3. Eject the DMG, then launch Timestamp Only from Applications.
4. In the Settings window, choose the folder where macOS saves screenshots.
5. Turn on Launch Timestamp Only at login if you want it available after every sign-in.

A release is accepted for distribution only after the app and DMG are Developer ID signed, notarized by Apple, and stapled. Apple's notarization service scans distributed software and gives Gatekeeper a ticket it can verify during first launch. See [Apple's notarization overview](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Homebrew Cask

Homebrew Cask is the planned secondary installation and upgrade path. The Cask will use the same notarized DMG as direct installation, not a separate build or installer. Installation instructions will be added when the Cask is published; a local build or an unpublished Cask should not be treated as a release.

## First-run folder access

Timestamp Only presents the standard macOS folder picker. Choose the location shown under Options in the Screenshot toolbar, which opens with Shift-Command-5. Most Macs use Desktop unless that setting has been changed.

The folder picker records an explicit choice and gives the sandboxed app read/write access to that folder. Timestamp Only stores a security-scoped bookmark so that the choice survives relaunches. Apple documents this flow in [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

Timestamp Only does not request Full Disk Access, Screen Recording, Accessibility, or Automation permission. Folder access is needed to observe and rename directory entries; the app does not inspect the screenshot image.

## Updates

For a direct installation, quit Timestamp Only, download the newer notarized DMG, and replace the copy in Applications. The stable bundle identifier preserves settings and the selected-folder bookmark across ordinary upgrades signed by the same developer identity.

For a Homebrew installation, use the Cask's standard upgrade flow after it is published.

Version 1 does not contain an update framework, perform update checks, or connect to the network. The release format leaves room for a future opt-in updater, but automatic checks will remain disabled unless the user explicitly enables them.
