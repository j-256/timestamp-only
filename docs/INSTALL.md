# Installation, first run, and updates

## Direct DMG installation

The primary release artifact is `Timestamp-Only-<version>.dmg` on the [GitHub Releases page](https://github.com/j-256/timestamp-only/releases).

1. Download the DMG from the repository's Releases page.
2. Open the DMG and drag Timestamp Only to Applications.
3. Eject the DMG, then launch Timestamp Only from Applications.
4. In the Settings window, choose the folder where macOS saves screenshots.
5. Turn on Launch Timestamp Only at login if you want it available after every sign-in.

A release is accepted for distribution only after the app and DMG are Developer ID signed, notarized by Apple, and stapled. Apple's notarization service scans distributed software and gives Gatekeeper a ticket it can verify during first launch. See [Apple's notarization overview](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

On first launch, macOS may confirm that the app was downloaded from the Internet and report that Apple checked it for malicious software. Click Open. A valid release does not require removing quarantine or bypassing Gatekeeper.

## Homebrew Cask

Homebrew Cask is the secondary installation and upgrade path:

```sh
brew install --cask j-256/tap/timestamp-only
```

The Cask downloads the same signed and notarized DMG as the direct installation. It does not use a separate build, package installer, LaunchAgent, or privileged helper.

## First-run folder access

Timestamp Only presents the standard macOS folder picker. Choose the location shown under Options in the Screenshot toolbar, which opens with Shift-Command-5. Most Macs use Desktop unless that setting has been changed.

The folder picker records an explicit choice and gives the sandboxed app read/write access to that folder. Timestamp Only stores a security-scoped bookmark so that the choice survives relaunches. Apple documents this flow in [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

Timestamp Only does not request Full Disk Access, Screen Recording, Accessibility, or Automation permission. Folder access is needed to observe and rename directory entries; the app does not inspect the screenshot image.

## Updates

For a direct installation, quit Timestamp Only, download the newer notarized DMG, and replace the copy in Applications. The stable bundle identifier preserves settings and the selected-folder bookmark across ordinary upgrades signed by the same developer identity.

For a Homebrew installation, update Homebrew and upgrade the Cask:

```sh
brew update
brew upgrade --cask timestamp-only
```

Version 1 does not contain an update framework, perform update checks, or connect to the network. The release format leaves room for a future opt-in updater, but automatic checks will remain disabled unless the user explicitly enables them.
